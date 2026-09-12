// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Inject from '../common/InjectModule';
import lazy { ShareAdapter } from '../adapter/ShareAdapter';
import JsBindingUtils from '../utils/JsBindingUtils';

function implShareAdapter(): ShareAdapter {
  return Inject.getOrCreate(ShareAdapter);
}

function shareData(optionsJson: string, callback: (success: boolean, error: string) => void): void {
  implShareAdapter().shareData(optionsJson, callback);
}

export class ShareAdapterBind {
  static bind() {
    JsBindingUtils.bindFunction('ShareAdapter.ShareData', shareData);
  }
}
