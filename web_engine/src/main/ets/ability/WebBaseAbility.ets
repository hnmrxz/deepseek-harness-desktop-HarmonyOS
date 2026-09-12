// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import UIAbility from '@ohos.app.ability.UIAbility';
import LogUtil from '../utils/LogUtil';
import window from '@ohos.window';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import JsBindingUtils from '../utils/JsBindingUtils';
import { ChangeEventType, NativeContext, WindowPreferences, WindowStatus } from '../interface/CommonInterface';
import { CommandType, ConfigData, ContextType } from '../common/Constants';
import CheckEmptyUtils from '../utils/CheckEmptyUtils';
import { WebProxy } from '../interface/WebProxy';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { ContinueAbility } from './ContinueAbility';

const TAG: string = 'WebBaseAbility';
const SHARE_ACTION: string = 'ohos.want.action.sendData';

interface NormalizedSharedRecord {
  utd?: Object | string | number | boolean;
  content?: Object | string | number | boolean;
  uri?: Object | string | number | boolean;
  title?: Object | string | number | boolean;
  description?: Object | string | number | boolean;
}

export class WebBaseAbility extends UIAbility implements WebProxy {
  protected xcomponentId: string = '';
  protected startUri: string = '';
  protected windowStage: window.WindowStage | undefined = undefined;
  protected nativeContext: NativeContext =
    JsBindingUtils.getNativeContext(ContextType.kMainProcess);
  protected deviceModeChangeEvent: ChangeEventType | undefined = undefined;
  protected initStatus: WindowStatus = WindowStatus.FLOATING;
  protected hideTitleBar: boolean = true;
  protected originWindowId: number = -1;
  protected useDarkMode: boolean = false;
  protected isStateless: boolean = false;
  protected appId: string = '';
  private continueAbility: ContinueAbility | undefined = undefined;

  // Electron
  protected cmdArgs: string[] = [];
  protected minimizable: boolean = !this.hideTitleBar;
  protected maximizable: boolean = !this.hideTitleBar;
  protected closable: boolean = !this.hideTitleBar;
  protected alwaysOntop: boolean = false;
  protected resizable: boolean = true;
  protected focusable: boolean = true;
  protected isModal: boolean = false;
  protected isPanel: boolean = false;

  private initParameters(want: Want) {
    if (want && want.parameters) {
      if (want.parameters['xcomponentId'] !== undefined) {
        this.xcomponentId = want.parameters['xcomponentId'] as string;
      }
      if (want.parameters["useDarkMode"] !== undefined) {
        this.useDarkMode = want.parameters['useDarkMode'] as boolean;
      }
      if (want.parameters["hideTitleBar"] !== undefined) {
        this.hideTitleBar = want.parameters['hideTitleBar'] as boolean;
      }
      if (want.parameters['minimizable'] !== undefined) {
        this.minimizable = want.parameters['minimizable'] as boolean;
      }
      if (want.parameters['maximizable'] !== undefined) {
        this.maximizable = want.parameters['maximizable'] as boolean;
      }
      if (want.parameters['closable'] !== undefined) {
        this.closable = want.parameters['closable'] as boolean;
      }
      if (want.parameters['focusable'] !== undefined) {
        this.focusable = want.parameters['focusable'] as boolean;
      }
      if (want.parameters['isPanel'] !== undefined) {
        this.isPanel = want.parameters['isPanel'] as boolean;
      }
      if (want.parameters["cmdArgs"] !== undefined) {
        (want.parameters["cmdArgs"] as string[]).forEach((arg: string) => {
          this.cmdArgs.push(arg);
        });
        LogUtil.info(TAG, 'cmdArgs = ' + JSON.stringify(this.cmdArgs));
      }
      if (want.parameters["initStatus"] !== undefined) {
        this.initStatus = want.parameters['initStatus'] as WindowStatus;
      }
      if (want.parameters["appId"] !== undefined) {
        this.appId = want.parameters['appId'] as string;
      }
      if (want.parameters["webappWindow"] !== undefined && want.parameters["webappWindow"] !== '') {
        this.appId = "--app-id=" + want.parameters['webappWindow'] as string;
      }
    }

    if (want["uri"]) {
      let storePath = want['uri'] as string;
      // convert storage path to uri
      this.startUri = storePath.replace("file://docs/", "file:///");
    }
  }

  protected getContentPath(): string {
    if (this.nativeContext.IsSupportNodeHandleFeature()) {
      return 'pages/NodeHandleWindow';
    } else {
      return 'pages/Index';
    }
  }

  private getContinueAbility(): ContinueAbility {
    if (this.continueAbility === undefined) {
      this.continueAbility = new ContinueAbility(this.context, this.nativeContext);
    }
    return this.continueAbility;
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    this.initParameters(want);
    this.handleSharedData(want);

    if (CheckEmptyUtils.isEmpty(this.xcomponentId)) {
      LogUtil.info(TAG, 'onCreate, Allocate xcomponent id');
      let widgetId = this.nativeContext.ExecuteCommand(CommandType.kGetWidget, {}).widget_Id;
      this.xcomponentId = ConfigData.WINDOW_PREFIX + widgetId;
    }

    this.handleContinueRestore(want, launchParam);
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    return this.getContinueAbility().onContinue(wantParam);
  }

  protected handleContinueRestore(want: Want, launchParam: AbilityConstant.LaunchParam) {
    this.getContinueAbility().handleContinueRestore(want, launchParam);
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    this.windowStage = windowStage;
    this.originWindowId = windowStage?.getMainWindowSync().getWindowProperties().id;
    // Ensure the distributed permission is granted ahead of any future
    // continuation (file) restore.
    this.getContinueAbility().requestDistributedPermissionIfNeeded();
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleSharedData(want);
  }

  // implements WebProxy interface
  getWindowStage(): window.WindowStage | undefined {
    return this.windowStage;
  }

  getWindow(): window.Window | undefined {
    return this.windowStage?.getMainWindowSync();
  }

  getWindowContext(): common.Context {
    return this.context;
  }

  getWindowId(): string {
    return this.xcomponentId;
  }

  getOriginWindowId(): number {
    return this.originWindowId;
  }

  closeWindow() {
    this.context.terminateSelf()
      .then(() => {
        LogUtil.info(TAG, 'terminate Self id: ' + this.getWindowId());
      })
      .catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to terminate Self: ' + JSON.stringify(err));
      });
  }

  setWindowTitle(title: string) {
    this.context.setMissionLabel(title)
      .catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to set title: ' + JSON.stringify(err));
      });
  }

  createSubWindow(name: string): Promise<window.Window> {
    return new Promise<window.Window>((resolve, reject) => {
      if (!this.windowStage) {
        reject('Failed to get windowStage');
        return;
      }
      this.windowStage.createSubWindow(name)
        .then((data: window.Window) => {
          resolve(data);
        }).catch((error: BusinessError) => {
        reject(error);
      })
    });
  }

  getWindowPreferences(): WindowPreferences {
    return {
      hideTitleBar: this.hideTitleBar,
      maximizable: this.maximizable,
      minimizable: this.minimizable,
      closable: this.closable
    };
  }

  setWindowPreferences(preferences: WindowPreferences) {
    this.hideTitleBar = preferences.hideTitleBar;
    this.maximizable = preferences.maximizable;
    this.minimizable = preferences.minimizable;
    this.closable = preferences.closable;
  }

  isUIAbility(): boolean {
    return true;
  }

  public updateAvoidAreaStatus(isFullScreen: boolean) {
    let windowClass = this.getWindow();
 
    // Set window to full screen.
    windowClass?.setWindowLayoutFullScreen(true).then(() => {
      LogUtil.info(TAG, 'Succeeded in setting the window layout to full-screen mode.');
    }).catch((err: BusinessError) => {
      LogUtil.error(TAG, 'Failed to set the window layout to full-screen mode. Cause:' + JSON.stringify(err));
    });
 
    // Hide the navigation bar here.
    windowClass?.setSpecificSystemBarEnabled('navigationIndicator', false).then(() => {
      LogUtil.info(TAG, 'Succeeded in setting the navigation indicator to be invisible.');
    }).catch((err: BusinessError) => {
      LogUtil.error(TAG, `Failed to set the navigation indicator to be invisible. Code is ${err.code}, message is ${err.message}`);
    });
 
    // The top status bar is set up to be hidden when in full-screen mode and displayed when maximized.
    windowClass?.setSpecificSystemBarEnabled('status', !isFullScreen).then(() => {
      LogUtil.info(TAG, 'Succeeded in setting the status bar to be invisible.');
    }).catch((err: BusinessError) => {
      LogUtil.error(TAG, `Failed to set the status bar to be invisible. Code is ${err.code}, message is ${err.message}`);
    });
  }

  public setDeviceModeChangeEvent(deviceModeChangeEvent: ChangeEventType | undefined) {
    this.deviceModeChangeEvent = deviceModeChangeEvent;
  }

  private handleSharedData(want: Want): void {
    if (!want || want.action !== SHARE_ACTION) {
      return;
    }
    systemShare.getSharedData(want).then((data: systemShare.SharedData) => {
      let records = data.getRecords();
      let sharedRecords: NormalizedSharedRecord[] = [];
      for (let i = 0; i < records.length; i++) {
        sharedRecords.push(this.normalizeSharedRecord(records[i]));
      }
      this.nativeContext.OnSharedDataReceived(JSON.stringify(sharedRecords));
    }).catch((err: BusinessError) => {
      LogUtil.error(TAG, 'Failed to get shared data: ' + JSON.stringify(err));
    });
  }

  private normalizeSharedRecord(record: systemShare.SharedRecord): NormalizedSharedRecord {
    let result: NormalizedSharedRecord = {};
    if (record.utd !== undefined && record.utd !== null) {
      result.utd = record.utd;
    }
    if (record.content !== undefined && record.content !== null) {
      result.content = record.content;
    }
    if (record.uri !== undefined && record.uri !== null) {
      result.uri = record.uri;
    }
    if (record.title !== undefined && record.title !== null) {
      result.title = record.title;
    }
    if (record.description !== undefined && record.description !== null) {
      result.description = record.description;
    }
    return result;
  }
};
