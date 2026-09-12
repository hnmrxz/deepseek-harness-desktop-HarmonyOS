// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { distributedDataObject, commonType } from '@kit.ArkData';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import { Permissions } from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { CommandType } from '../common/Constants';
import { NativeContext } from '../interface/CommonInterface';
import LogUtil from '../utils/LogUtil';

const TAG: string = 'ContinueAbility';

// Payload returned by the app in the 'continue' event: business data plus the
// list of local file paths to migrate.
interface ContinuePayload {
  data?: Object;
  urls?: string[];
}

// Root object synced through a distributed data object during file continuation.
// Each value in |assets| is an Asset-typed property the framework migrates.
class ContinueSource {
  assets: Record<string, commonType.Asset>;
  constructor(assets: Record<string, commonType.Asset>) {
    this.assets = assets;
  }
}

export class ContinueAbility {
  private context: common.Context;
  private nativeContext: NativeContext;
  // Keeps the distributed data object alive across the async restore callback.
  private continueDataObject: distributedDataObject.DataObject | undefined = undefined;
  private static readonly PERM_DISTRIBUTED: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC';
  // File continuation (distributedDataObject) is off until the system object-store
  // SA permission (errno 96929750) is resolved: joining the session blocks the
  // main thread and freezes the continuation launch. Data continuation is
  // unaffected. Flip to true to re-enable once the platform permission works.
  private static readonly ENABLE_FILE_CONTINUATION: boolean = false;

  constructor(context: common.Context, nativeContext: NativeContext) {
    this.context = context;
    this.nativeContext = nativeContext;
  }

  // Cross-device continuation (handoff) - source device.
  // Triggered when the app is about to migrate to another device. Ask electron
  // (via the 'continue' event) for the data the app wants to migrate and write
  // it into wantParam so the system carries it to the target device.
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    try {
      this.nativeContext.ExecuteCommand(CommandType.kSaveContinue, { is_sync: true });
      // The data is stashed on the native side during the sync command above;
      // fetch it here (kept off CommandResult to avoid an ABI-fragile string
      // field crossing the libadapter/libelectron boundary).
      let data = this.nativeContext.GetSavedContinueData();
      if (data !== undefined && data !== '') {
        // Store the serialized migration data (JSON string) from the app.
        wantParam['data'] = data;
        LogUtil.info(TAG, 'onContinue, saved migration data, length: ' + data.length);
        // Package any files the app wants to migrate into a distributed data
        // object so the system syncs them to the target device.
        try {
          let payload = JSON.parse(data) as ContinuePayload;
          if (payload && payload.urls && payload.urls.length > 0) {
            this.saveContinueFiles(payload.urls, wantParam);
          }
        } catch (e) {
          LogUtil.error(TAG, 'onContinue, parse payload for files failed: ' + JSON.stringify(e));
        }
      } else {
        LogUtil.info(TAG, 'onContinue, no migration data from app');
      }
    } catch (err) {
      LogUtil.error(TAG, 'onContinue failed: ' + JSON.stringify(err));
    }
    return AbilityConstant.OnContinueResult.AGREE;
  }

  // Cross-device continuation (handoff) - target device.
  // On a continuation launch, hand the restored data back to electron via the
  // 'get-continue-data' event. Called from both onCreate and onNewWant.
  handleContinueRestore(want: Want, launchParam: AbilityConstant.LaunchParam) {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return;
    }
    if (want.parameters === undefined) {
      LogUtil.info(TAG, 'handleContinueRestore, continuation launch without parameters');
      return;
    }
    // Restore business data.
    if (want.parameters['data'] !== undefined) {
      let data = want.parameters['data'];
      let json: string = typeof data === 'string' ? data as string : JSON.stringify(data);
      LogUtil.info(TAG, 'handleContinueRestore, buffer restored data, length: ' + json.length);
      // onCreate runs before the electron browser/app is ready, so buffer the
      // data natively and trigger a flush; the App also flushes once it is
      // ready, so it is delivered to app.on('get-continue-data') exactly once.
      this.nativeContext.SetPendingContinueData(json);
      this.nativeContext.ExecuteCommand(CommandType.kRestoreContinueData,
        { is_sync: false });
    }
    // Restore migrated files via the distributed data object. Gated off by
    // ENABLE_FILE_CONTINUATION (see handleDistributedData): joining the session
    // blocks the main thread when the object-store SA permission fails (96929750),
    // freezing onCreate/the window. Kept wrapped so any throw can't break onCreate.
    if (want.parameters['dataSessionId'] !== undefined) {
      try {
        this.handleDistributedData(want);
      } catch (e) {
        LogUtil.error(TAG, 'handleDistributedData threw, files skipped: ' + JSON.stringify(e));
      }
    }
  }

  // Request DISTRIBUTED_DATASYNC if not yet granted. Called from
  // onWindowStageCreate (UI is up so the system dialog can show) on normal
  // launches, so a later continuation launch, whose onCreate runs the
  // distributed restore before any UI, already has the grant.
  requestDistributedPermissionIfNeeded() {
    if (this.isDistributedPermissionGranted()) {
      return;
    }
    try {
      let atManager = abilityAccessCtrl.createAtManager();
      let perms: Array<Permissions> = [ContinueAbility.PERM_DISTRIBUTED];
      atManager.requestPermissionsFromUser(this.context, perms)
        .then((data) => {
          LogUtil.info(TAG, 'request DISTRIBUTED_DATASYNC authResults: ' +
            JSON.stringify(data.authResults));
        })
        .catch((err: BusinessError) => {
          LogUtil.error(TAG, 'request DISTRIBUTED_DATASYNC failed: ' + JSON.stringify(err));
        });
    } catch (err) {
      LogUtil.error(TAG, 'request DISTRIBUTED_DATASYNC threw: ' + JSON.stringify(err));
    }
  }

  private buildAssetsWrapper(assets: commonType.Asset[]): Record<string, commonType.Asset> {
    let wrapper: Record<string, commonType.Asset> = {};
    for (let i = 0; i < assets.length; i++) {
      wrapper[`asset${i}`] = assets[i];
    }
    return wrapper;
  }

  // Source device: copy each file into the distributed file dir, package the
  // files into a distributed data object, and put its session id into wantParam
  // so the target device can restore them.
  private saveContinueFiles(urls: string[], wantParam: Record<string, Object>) {
    if (!this.isDistributedPermissionGranted()) {
      // Without the grant the distributed data object can't sync; migrate data
      // only (skip files) instead of failing the whole continuation.
      LogUtil.error(TAG, 'saveContinueFiles skipped: DISTRIBUTED_DATASYNC not granted');
      return;
    }
    let distributedDir: string = this.context.distributedFilesDir;
    let assets: commonType.Asset[] = [];
    for (let url of urls) {
      try {
        let srcPath: string = url.startsWith('file://') ? new fileUri.FileUri(url).path : url;
        let fileName: string = srcPath.substring(srcPath.lastIndexOf('/') + 1);
        let destPath: string = `${distributedDir}/${fileName}`;
        if (srcPath !== destPath) {
          fs.copyFileSync(srcPath, destPath);
        }
        let stat: fs.Stat = fs.statSync(destPath);
        let asset: commonType.Asset = {
          name: fileName,
          uri: fileUri.getUriFromPath(destPath),
          path: destPath,
          createTime: stat.ctime.toString(),
          modifyTime: stat.mtime.toString(),
          size: stat.size.toString(),
        };
        assets.push(asset);
      } catch (err) {
        LogUtil.error(TAG, `saveContinueFiles failed for ${url}: ${JSON.stringify(err)}`);
      }
    }
    if (assets.length === 0) {
      return;
    }
    let source = new ContinueSource(this.buildAssetsWrapper(assets));
    this.continueDataObject = distributedDataObject.create(this.context, source);
    let sessionId: string = distributedDataObject.genSessionId();
    this.continueDataObject.setSessionId(sessionId);
    wantParam['dataSessionId'] = sessionId;
    LogUtil.info(TAG, `saveContinueFiles, packaged ${assets.length} files, session: ${sessionId}`);
  }

  // Target device: join the distributed data object session; when its status
  // becomes 'restored', the migrated files are available locally and their info
  // is handed to electron via the 'get-continue-file' event.
  private handleDistributedData(want: Want) {
    if (!ContinueAbility.ENABLE_FILE_CONTINUATION) {
      // Disabled: see ENABLE_FILE_CONTINUATION. Do NOT touch distributedDataObject
      // here; joining the session blocks the main thread and freezes onCreate.
      LogUtil.info(TAG, 'handleDistributedData skipped: file continuation disabled');
      return;
    }
    let sessionId: string | undefined =
      want.parameters?.['dataSessionId'] as string | undefined;
    if (sessionId === undefined || sessionId === '') {
      return;
    }
    if (!this.isDistributedPermissionGranted()) {
      // Skip gracefully (don't touch distributedDataObject without the grant);
      // it will be requested on the next normal startup via onWindowStageCreate.
      LogUtil.error(TAG, 'handleDistributedData skipped: DISTRIBUTED_DATASYNC not granted');
      return;
    }
    let source = new ContinueSource({});
    let dataObject: distributedDataObject.DataObject =
      distributedDataObject.create(this.context, source);
    this.continueDataObject = dataObject;
    dataObject.on('status',
      (sid: string, networkId: string, status: 'online' | 'offline' | 'restored') => {
        LogUtil.info(TAG, `continue dataObject status: ${status}, session: ${sid}`);
        if (status === 'restored') {
          let restored = dataObject['assets'] as Record<string, commonType.Asset>;
          let fileInfo: string = JSON.stringify(restored ?? {});
          this.nativeContext.SetPendingContinueFile(fileInfo);
          this.nativeContext.ExecuteCommand(CommandType.kRestoreContinueFile,
            { is_sync: false });
          LogUtil.info(TAG, 'handleDistributedData, buffered restored files for electron');
        }
      });
    dataObject.setSessionId(sessionId);
  }

  // distributedDataObject (file continuation) requires the user_grant permission
  // ohos.permission.DISTRIBUTED_DATASYNC. Using it without the grant fails, so we
  // check it before any distributed operation and request it on normal startup.
  private isDistributedPermissionGranted(): boolean {
    try {
      let atManager = abilityAccessCtrl.createAtManager();
      let info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      let tokenId = info.appInfo.accessTokenId;
      return atManager.checkAccessTokenSync(tokenId, ContinueAbility.PERM_DISTRIBUTED) ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      LogUtil.error(TAG, 'check DISTRIBUTED_DATASYNC failed: ' + JSON.stringify(err));
      return false;
    }
  }
}
