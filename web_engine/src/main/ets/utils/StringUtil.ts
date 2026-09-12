// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import fileUri from '@ohos.file.fileuri';

export default class StringUtil {
  private static TAG: string = 'StringUtil';

  static uriConvert(docs: string[]): string[] {
    let copy: string[] = [];
    docs.forEach((path) => {
      // Resolve Chinese garbled characters
      path = decodeURI(path);
      // Convert to uri get systeam path
      let uri = new fileUri.FileUri(path);
      copy.push(uri.path);
    });
    return copy;
  }

  /**
   * 单个 URI → 可用文件路径。
   *
   * 【为什么这个方法由本项目补】华为 release 包内部不一致：`PasteBoardApadter.ets:230`
   * 调用了 `StringUtil.filterFileDocs(uri)`，但同一个包里的 `StringUtil` 只有数组版的
   * `uriConvert`，导致 `HarCompileArkTS` 直接报
   * "Property 'filterFileDocs' does not exist on type 'typeof StringUtil'"。
   * 这里按 `uriConvert` 的等价语义补齐单元素版本（先 decodeURI，再取 FileUri.path）。
   *
   * 注意：这是对 **vendor 运行时** 的补丁，与"对 dsh 上游零 patch"的纪律不冲突——
   * 那条纪律约束的是 dsh 本体。
   */
  static filterFileDocs(doc: string): string {
    const decoded: string = decodeURI(doc);
    return new fileUri.FileUri(decoded).path;
  }
}
