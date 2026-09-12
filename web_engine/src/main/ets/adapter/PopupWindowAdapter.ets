// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import bundleManager from '@ohos.bundle.bundleManager';
import { BusinessError } from '@ohos.base';
import { Size, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

import { AbilityManager } from '../common/AbilityManager';
import { BaseAdapter } from '../common/BaseAdapter';
import { ContextAdapter } from './ContextAdapter';
import { inject, injectable } from 'inversify';
import LogMethod from '../common/LogDecorator';
import LogUtil from '../utils/LogUtil';
import { NewWindowParam, WindowType, WindowBound } from "../interface/CommonInterface"
import { WindowStyle, IStyleData, IUpdateStyle } from '../common/WindowStyle';
import lazy { PopupWindowManager } from '../common/PopupWindowManager';

const TAG: string = 'PopupWindow';

@injectable()
export class PopupWindowAdapter extends BaseAdapter {
  private abilityManager: AbilityManager;
  private popupWindowManager: PopupWindowManager;
  private bundleName: string = 'com.huawei.ohos_electron';
  private bundleFlags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION |
                        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA;

  constructor(
    @inject(AbilityManager) abilityManager: AbilityManager,
    @inject(ContextAdapter) ctxAdapter: ContextAdapter,
    @inject(PopupWindowManager) popupWindowManager: PopupWindowManager,
  ) {
    super();
    this.abilityManager = abilityManager;
    this.popupWindowManager = popupWindowManager;

    try {
      let data = bundleManager.getBundleInfoForSelfSync(this.bundleFlags);
      this.bundleName = data.name;
    } catch (err) {
      let message = (err as BusinessError).message;
      LogUtil.error(TAG, `getBundleInfoForSelfSync failed.: ${message}`);
    }
  }

  @LogMethod
  createWindow(param: NewWindowParam) {
    let proxy = this.abilityManager.getProxy(param.parent_id);
    proxy?.createSubWindow(param.window_id)
      .then((data: window.Window) => {
        this.adjustWindow(data, param, WindowType.SUB_WINDOW);

        try {
          data.on("windowRectChange", (option) => {
            this.nativeContext.OnWindowRectChange(param.window_id, option.rect, option.reason.valueOf());
          });
        } catch (exception) {
          LogUtil.error(TAG,'Failed to enable the listener for window rect changes. Cause: ' + JSON.stringify(exception));
        }

        try {
          data.on('displayIdChange', (displayId) => {
            this.nativeContext.OnWindowDisplayIdChange(param.window_id, displayId);
          });
        } catch (exception) {
          LogUtil.info(TAG, `register displayIdChange listener fail, xcomponentId:${param.window_id},
                      exception: ${JSON.stringify(exception)}`);
        }
        
      }).catch((err: BusinessError) => {
      LogUtil.error(TAG, 'Failed to create the subWindow. Cause: ' + JSON.stringify(err));
    });
  }

  @LogMethod
  private adjustWindow(windowClass: window.Window, param: NewWindowParam, windowType: WindowType) {
    this.cacheWindow(param.parent_id, param.window_id, windowClass);
    windowClass.setSubWindowModal(param.is_modal);
    windowClass.moveWindowTo(param.bounds.left, param.bounds.top, (err: BusinessError) => {
      let errCode: number = err.code;
      if (errCode) {
        LogUtil.error(TAG, `${windowType} failed to move the window. Cause:${JSON.stringify(err)}`);
        return;
      }
      LogUtil.info(TAG, `${windowType} succeeded in moving the window.`);
    });
    windowClass.resize(param.bounds.width, param.bounds.height, (err: BusinessError) => {
      let errCode: number = err.code;
      if (errCode) {
        LogUtil.error(TAG, `${windowType} failed to change the window size. Cause:${JSON.stringify(err)}`);
        return;
      }
      LogUtil.info(TAG, `${windowType} succeeded in changing the window size.`);
    });

    const para: Record<string, string | IUpdateStyle> = {
      'xcomponentId': param.window_id,
      'updateStyle': {
        'registerUpdateStyleFunction': WindowStyle.registerUpdateStyleFunction,
        'removeUpdateStyleFunction': WindowStyle.removeUpdateStyleFunction
      }
    };
    let storage: LocalStorage = new LocalStorage(para);
    windowClass.loadContent(this.getContentPath(), storage, (err: BusinessError) => {
      let errCode: number = err.code;
      if (errCode) {
        LogUtil.error(TAG, `${windowType} failed to load the content. Cause:${JSON.stringify(err)}`);
        return;
      }
      LogUtil.info(TAG, `${windowType} succeeded in loading the content.`);
      (windowClass as window.Window).showWindow((err: BusinessError) => {
        let errCode: number = err.code;
        if (errCode) {
          LogUtil.error(TAG, `${windowType} failed to show the window. Cause:${JSON.stringify(err)}`);
          return;
        }
        LogUtil.info(TAG, `${windowType} succeeded in showing the window.`);
      });
    });
  }

  private getContentPath(): string {
    if (this.nativeContext.IsSupportNodeHandleFeature()) {
      return 'pages/NodeHandleWindow';
    } else {
      return 'pages/Index';
    }
  }

  @LogMethod
  closeWindow(id: number) {
    let mainWindowId = this.popupWindowManager.getMainWindowId(id);
    if (mainWindowId) {
      let windowClass = this.popupWindowManager.getWindow(id);
      if (windowClass === undefined) {
        LogUtil.error(TAG, `Failed to find the window. windowId: ${id}`);
        return;
      }
      windowClass.destroyWindow((err: BusinessError) => {
        if (err.code) {
          LogUtil.error(TAG, 'Failed to destroy the window. Cause: ' + JSON.stringify(err));
          return;
        }
        LogUtil.info(TAG, 'Succeeded in destroying the window.');
      });
      this.popupWindowManager.removePopupWindow(mainWindowId, id);
    }

  }

  @LogMethod
  showWindow(id: number) {
    let windowClass = this.popupWindowManager.getWindow(id);
    let promise = windowClass?.showWindow();
    promise?.then(() => {
        LogUtil.info(TAG, 'Succeeded in showing the window.');
    }).catch((err: BusinessError) => {
        LogUtil.error(TAG, `Failed to show the window. Cause code: ${err.code}, message: ${err.message}`);
    });
  }

  @LogMethod
  hideWindow(id: number) {
    let windowClass = this.popupWindowManager.getWindow(id);
    let promise = windowClass?.minimize();
    promise?.then(() => {
        LogUtil.info(TAG, 'Succeeded in hiding the window.');
    }).catch((err: BusinessError) => {
        LogUtil.error(TAG, `Failed to hide the window. Cause code: ${err.code}, message: ${err.message}`);
    });
  }

  @LogMethod
  activateWindow(id: number) {
    this.showWindow(id);
  }

  @LogMethod
  setBounds(id: number,
            bounds: WindowBound) {
    let windowClass = this.popupWindowManager.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the popup window.');
      return;
    }

    try {
      windowClass.moveWindowToAsync(bounds.left, bounds.top)
        .catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to move the window. Cause:' + JSON.stringify(err));
        });
      windowClass?.resizeAsync(bounds.width, bounds.height)
        .catch((err: BusinessError) => {
          LogUtil.error(TAG, 'Failed to change the window size. Cause:' + JSON.stringify(err));
        });
    } catch (exception) {
      LogUtil.error(TAG, 'move the window exception. Cause:' + JSON.stringify(exception));
    }
  }

  @LogMethod
  setWindowLimits(minWidth: number,
                  minHeight: number,
                  maxWidth: number,
                  maxHeight: number,
                  id: number) {
    let windowClass = this.popupWindowManager.getWindow(id);
    const windowProp = windowClass?.getWindowProperties();
    let xComBorder: number = windowProp?.drawableRect.left || 0;
    let xComTop: number = windowProp?.drawableRect.top || 0;

    try {
      let windowLimits: window.WindowLimits = {
        minWidth: minWidth === 0 ? minWidth : minWidth + xComBorder + xComBorder,
        minHeight: minHeight === 0 ? minHeight : minHeight + xComTop + xComBorder,
        maxWidth: maxWidth === 0 ? maxWidth : maxWidth + xComBorder + xComBorder,
        maxHeight: maxHeight === 0 ? maxHeight : maxHeight + xComTop + xComBorder,
      };

      windowClass?.setWindowLimits(windowLimits)
        .catch((err: BusinessError) => {
          LogUtil.error(TAG, 'Failed to change the window limits. Cause: ' + JSON.stringify(err));
        });
    } catch (exception) {
      LogUtil.error(TAG, 'change the window limits exception. Cause:' + JSON.stringify(exception));
    }
  }

  @LogMethod
  setWindowShadow(id: number, hasShadow: boolean) {
    let windowClass = this.popupWindowManager.getWindow(id);
    if (windowClass === undefined) {
      LogUtil.error(TAG, `setWindowShadow fail, window is not exist! windowId: ${id}, hasShadow: ${hasShadow}`);
      return;
    }
    const radius: number = hasShadow ? 15 : 0;
    if (deviceInfo.sdkApiVersion >= 17) {
      windowClass.setWindowShadowRadius(radius);
    } else {
      LogUtil.error(TAG, 'setWindowShadow fail, sdkApiVersion is less than 17');
    }
  }

  @LogMethod
  setEnabled(enable: boolean, id: number): boolean {
    let windowClass = this.popupWindowManager.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the sub window.');
      return false;
    }
    windowClass.setWindowTouchable(enable)
      .catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to set the window to be touchable. Cause:' + JSON.stringify(err));
        return false;
      });
    return true;
  }

  @LogMethod
  setBackgroundColor(id: number, argbColor: number) {
    let windowClass = this.popupWindowManager.getWindow(id);
    let backgroundColor = WindowStyle.decimalColorToHex(argbColor);
    let data = WindowStyle.getStyleData(id) ?? {
      backgroundColor: backgroundColor,
      opacity: 1
    };
    data.backgroundColor = backgroundColor;
    WindowStyle.updateStyleData(id, data);
    WindowStyle.getUpdateStyleFunc(id)?.(data);
    windowClass?.setWindowBackgroundColor(`#${backgroundColor}`);
  }

  @LogMethod
  setOpacity(id: number, opacity: number) {
    let windowClass = this.popupWindowManager.getWindow(id);
    let data = WindowStyle.getStyleData(id) ?? {
      backgroundColor: 'ffffffff',
      opacity: opacity
    };
    data.opacity = opacity;
    WindowStyle.updateStyleData(id, data);
    WindowStyle.getUpdateStyleFunc(id)?.(data);
    let lastColor = data.backgroundColor;
    windowClass?.setWindowBackgroundColor(`#${WindowStyle.decimalOpacityToHex(opacity)}${lastColor.slice(2)}`);
  }

  @LogMethod
  setContentProtection(id: number, enable: boolean) {
    let windowClass = this.popupWindowManager.getWindow(id);
    try {
      windowClass?.setWindowPrivacyMode(enable, (err: BusinessError) => {
        const errCode: number = err.code;
        if (errCode) {
          LogUtil.error(TAG, `Failed to set the sub window to privacy mode. Cause code: ${err.code}, message: ${err.message}`);
          return;
        }
        LogUtil.info(TAG, 'Succeeded in setting the sub window to privacy mode.');
      });
    } catch (exception) {
      LogUtil.error(TAG, `Failed to set the sub window to privacy mode. Cause code: ${exception.code}, message: ${exception.message}`);
    }
  }

  @LogMethod
  startWindowMoving(id: number) {
    let window = this.popupWindowManager.getWindow(id);
    window?.startMoving().then(() => {
    }).catch((err: BusinessError) => {
      LogUtil.error(TAG, `startWindowMoving fail, error info: ${JSON.stringify(err)}`);
    });
  }

  @LogMethod
  getOriginWindowId(windowId?: number): number {
    if (!windowId) {
      return -1;
    }
    try {
      let window = this.popupWindowManager.getWindow(windowId);
      if (window) {
        return window.getWindowProperties().id;
      }
    } catch (err) {
      let message = (err as BusinessError).message;
      LogUtil.error(TAG, `getOriginWindowId failed, windowId:${windowId}, message:: ${message}`);
    }
    return -1;
  }

  private cacheWindow(parentId: string, windowId: string, windowClass: window.Window) {
    let mainWindowId = this.abilityManager.getProxy(parentId)?.getWindowId();
    if (mainWindowId) {
      this.popupWindowManager.addPopupWindow(mainWindowId, {
        "id": windowId,
        "window": windowClass
      });
    }
  }
};
