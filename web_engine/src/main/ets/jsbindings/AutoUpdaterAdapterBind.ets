// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import JsBindingUtils from '../utils/JsBindingUtils';
import Inject from '../common/InjectModule';
import lazy { AutoUpdaterAdapter } from '../adapter/AutoUpdaterAdapter';

function implAutoUpdaterAdapter(): AutoUpdaterAdapter {
  return Inject.getOrCreate(AutoUpdaterAdapter);
}

function checkForUpdates(callback: Function): void {
  return implAutoUpdaterAdapter().checkForUpdates(callback);
}

function quitAndInstall(callback: Function): void {
  return implAutoUpdaterAdapter().quitAndInstall(callback);
}

export class AutoUpdaterAdapterBind {
  static bind() {
    JsBindingUtils.bindFunction('AutoUpdater.CheckForUpdates', checkForUpdates);
    JsBindingUtils.bindFunction('AutoUpdater.QuitAndInstall', quitAndInstall);
  }
}
