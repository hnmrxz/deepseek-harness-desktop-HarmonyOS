// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import { injectable } from 'inversify';
import { BusinessError } from '@ohos.base';
import { updateManager } from '@kit.AppGalleryKit';

import { BaseAdapter } from '../common/BaseAdapter';
import { ContextAdapter } from './ContextAdapter';
import { inject } from 'inversify';
import LogUtil from '../utils/LogUtil';
import LogMethod from '../common/LogDecorator';
import { common } from '@kit.AbilityKit';

const TAG: string = 'AutoUpdater';

@injectable()
export class AutoUpdaterAdapter extends BaseAdapter {
  private ctxAdapter: ContextAdapter;

  constructor(@inject(ContextAdapter) ctxAdapter: ContextAdapter) {
    super();
    this.ctxAdapter = ctxAdapter;
  }

  @LogMethod
  checkForUpdates(callback: Function): void {
    let proxy = this.ctxAdapter.getActiveProxy();
    if (!proxy) {
      LogUtil.error(TAG, 'checkForUpdates: no active proxy');
      callback(-1);
      return;
    }
    try {
      updateManager.checkAppUpdate(proxy.getWindowContext() as common.UIAbilityContext).then((result: updateManager.CheckUpdateResult) => {
        if (result && result.updateAvailable) {
          LogUtil.info(TAG, 'checkForUpdates: update available');
          callback(1);
        } else {
          LogUtil.info(TAG, 'checkForUpdates: no update available');
          callback(0);
        }
      }).catch((err: BusinessError) => {
        LogUtil.error(TAG, `checkForUpdates failed, code: ${err.code}, msg: ${err.message}`);
        callback(-1);
      });
    } catch (err) {
      let error = err as BusinessError;
      LogUtil.error(TAG, `checkForUpdates exception, code: ${error.code}, msg: ${error.message}`);
      callback(-1);
    }
  }

  @LogMethod
  quitAndInstall(callback: Function): void {
    let proxy = this.ctxAdapter.getActiveProxy();
    if (!proxy) {
      LogUtil.error(TAG, 'quitAndInstall: no active proxy');
      callback();
      return;
    }
    try {
      updateManager.showUpdateDialog(proxy.getWindowContext() as common.UIAbilityContext).then((resultCode: updateManager.ShowUpdateResultCode) => {
        LogUtil.info(TAG, 'quitAndInstall: dialog shown: ' + resultCode);
        callback();
      }).catch((err: BusinessError) => {
        LogUtil.error(TAG, `quitAndInstall failed, code: ${err.code}, msg: ${err.message}`);
        callback();
      });
    } catch (err) {
      let error = err as BusinessError;
      LogUtil.error(TAG, `quitAndInstall exception, code: ${error.code}, msg: ${error.message}`);
      callback();
    }
  }
}
