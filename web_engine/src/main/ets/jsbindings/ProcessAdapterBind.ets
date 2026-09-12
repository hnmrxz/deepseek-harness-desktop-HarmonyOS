// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import JsBindingUtils from '../utils/JsBindingUtils';
import Inject from '../common/InjectModule';
import lazy { ProcessAdapter } from '../adapter/ProcessAdapter';

function implProcessAdapter(): ProcessAdapter {
  return Inject.getOrCreate(ProcessAdapter);
}

function startChildProcess(
  srcEntry: string,
  entryParams: string,
  fdsId: number[],
  fds: number[],
  isolationMode: boolean,
  callback: Function
): void {
  let fd_mappings: Record<string, number> = {};
  if (fdsId && fds && fdsId.length === fds.length) {
    for (let i = 0; i < fdsId.length; i++) {
      fd_mappings[`${fdsId[i]}`] = fds[i];
    }
  }
  implProcessAdapter().startChildProcess(srcEntry, entryParams, fd_mappings, isolationMode, callback);
}

export class ProcessAdapterBind {
  static bind() {
    JsBindingUtils.bindFunction("ChromiumChildProcessStarter.StartChildProcess", startChildProcess);
  }
}