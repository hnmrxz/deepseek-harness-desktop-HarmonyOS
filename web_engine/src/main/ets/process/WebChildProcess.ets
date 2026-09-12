// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import { ChildProcess, ChildProcessArgs } from '@kit.AbilityKit';
import { ContextType } from '../common/Constants';
import { NativeContext } from '../interface/CommonInterface';
import JsBindingUtils from '../utils/JsBindingUtils';
import LogUtil from '../utils/LogUtil';

export class WebChildProcess extends ChildProcess {
  private nativeContext: NativeContext = JsBindingUtils.getNativeContext(ContextType.kRenderProcess);

  onStart(args?: ChildProcessArgs): void {
    LogUtil.info("childProcess", "WebChildProcess onStart, args: " + JSON.stringify(args));
    const entryParams = args?.entryParams || '';
    const fd_mappings = args?.fds || {};
    const fdsId: number[] = [];
    const fds: number[] = [];
    const keys: string[] = Object.keys(fd_mappings);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      fdsId.push(parseInt(key));
      fds.push(fd_mappings[key]);
    }
    this.nativeContext.runArkProcess(entryParams, fdsId, fds);
  }
}
