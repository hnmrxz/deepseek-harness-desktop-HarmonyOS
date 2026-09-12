// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AbilityStage from '@ohos.app.ability.AbilityStage';
import { CommandType, ConfigData, ContextType } from '../common/Constants';
import JsBindingUtils from '../utils/JsBindingUtils';
import Want from '@ohos.app.ability.Want';
import lazy { GlobalThisHelper } from '../utils/GlobalThisHelper';
import lazy { NativeContext, TrayExitResponse } from '../interface/CommonInterface';
import lazy { CommonDependencyProvider } from '../common/CommonDependencyProvider';
import { AbilityConstant } from '@kit.AbilityKit';
import { ConfigurationConstant, Configuration } from '@kit.AbilityKit';
import { NativeThemeAdapter } from '../adapter/NativeThemeAdapter'
import Inject from '../common/InjectModule';
import LogUtil from '../utils/LogUtil';

const DELAYED_TIME = 0;
const TAG: string = 'WebAbilityStage';

export class WebAbilityStage extends AbilityStage {
  private static SLEEP_INTERVAL_MS = 10;
  private static MAXIMUM_NUM_OF_SLEEP_CYCLES = 250;

  private nativeContext: NativeContext | undefined = undefined;
  private nativeThemeAdapter: NativeThemeAdapter | undefined;

  onCreate(): void {
    this.runTaskAsync();
  }

  onAcceptWant(want: Want): string {
    let instanceKey = want.parameters?.instanceKey;
    if (instanceKey) {
      return instanceKey.toString();
    }

    if (GlobalThisHelper.isLaunched()) {
      let lastActiveBrowserId = GlobalThisHelper.getLastActiveBrowserId();
      if (lastActiveBrowserId !== undefined) {
        return lastActiveBrowserId;
      }
      let widgetId = this.nativeContext?.GetLastActiveWidgetId();
      if (widgetId) {
        return ConfigData.WINDOW_PREFIX + widgetId;
      }
    }
    this.context.getApplicationContext().tempDir;
    return ConfigData.DEFAULT_WINDOW_ID;
  }

  // Tray-quit gate: give the JS layer a chance to handle 'tray-request-quit'
  // and preventDefault. Adapted for 138, which has no app-close (kAppExit)
  // handshake — once the tray quit is allowed we fall back to 138's existing
  // kAppQuit + immediate termination.
  async onPrepareTerminationAsync(): Promise<AbilityConstant.PrepareTermination> {
    LogUtil.info(TAG, "ability stage prepare to quit async - tray quit request");
    if (!this.nativeContext) {
      this.nativeContext = JsBindingUtils.getNativeContext(ContextType.kMainProcess);
    }

    if (!GlobalThisHelper.isLaunched()) {
      return AbilityConstant.PrepareTermination.TERMINATE_IMMEDIATELY;
    }

    LogUtil.info(TAG, "sending tray quit request to JS layer");
    this.nativeContext?.ExecuteCommand(
      CommandType.kTrayQuitRequest, { is_sync: false });

    let trayExitResponse: TrayExitResponse = TrayExitResponse.kUndetermined;
    let cnt = 0;
    for (let i = 0; i < WebAbilityStage.MAXIMUM_NUM_OF_SLEEP_CYCLES; i++) {
      cnt++;
      await this.sleep(WebAbilityStage.SLEEP_INTERVAL_MS);
      trayExitResponse = this.nativeContext.GetTrayExitResponse();
      if (trayExitResponse !== TrayExitResponse.kUndetermined) {
        break;
      }
    }

    LogUtil.info(TAG, `tray quit response: ${trayExitResponse} after ${cnt} checks`);

    if (trayExitResponse === TrayExitResponse.kPrevented ||
        trayExitResponse === TrayExitResponse.kUndetermined) {
      LogUtil.info(TAG, "tray quit blocked by JS or timeout, returning CANCEL");
      return AbilityConstant.PrepareTermination.CANCEL;
    }

    LogUtil.info(TAG, "tray quit allowed, proceeding with quit");
    this.nativeContext?.ExecuteCommand(CommandType.kAppQuit, { is_sync: false });
    return AbilityConstant.PrepareTermination.TERMINATE_IMMEDIATELY;
  }

  sleep(delay: number) {
    return new Promise<void>((resolve) => setTimeout(resolve, delay));
  }

  onConfigurationUpdate(config: Configuration) {
    if (config.colorMode !== undefined) {
      this.nativeThemeAdapter?.setSystemNativeTheme(config.colorMode);
    }
  }

  private runTaskAsync() {
    setTimeout(() => {
      JsBindingUtils.initNativeContext(ContextType.kMainProcess);
      this.nativeContext = JsBindingUtils.getNativeContext(ContextType.kMainProcess);
      if (!GlobalThisHelper.isLaunched()) {
        let appContext = this.context.getApplicationContext();
        GlobalThisHelper.appInit(new CommonDependencyProvider(appContext));
      }
      import('../jsbindings/JsBindingMethod').then((ns:ESObject) => {
        ns.JsBindingMethod.bind();
        this.nativeThemeAdapter = Inject.get(NativeThemeAdapter);
        JsBindingUtils.SetContextPaths();
      }).catch(()=>{
        LogUtil.error(TAG, 'runTaskAsync: import JsBindingMethod failed');
      });
    }, DELAYED_TIME)
  }
}
