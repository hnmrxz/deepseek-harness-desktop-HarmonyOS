/**
 * 系统剪贴板机制封装。
 *
 * 用途（D3 §5.2 长按消息 / §7.8 导出诊断）：复制消息、复制代码块、复制诊断报告。
 * 只做「写文本」，不决定复制什么内容——那是 UI 的事。
 *
 * 【为什么只有「写」】（P5-7 / E370）这里曾另有 `readText` / `clearClipboard` 两个零消费者函数，
 * 逐一拍板后**删掉**：
 *   · `readText`：应用**没有**"主动读剪贴板"的需求。用户往输入框里粘贴走的是**系统文本域自己的**
 *     粘贴菜单（应用不参与），而"程序化读剪贴板"要么声明 `ohos.permission.READ_PASTEBOARD`、
 *     要么用系统安全控件 `PasteButton`：前者与"不申请特殊权限"（README 设计原则 2）冲突；
 *     后者会在工具行里多一个**不能自由改样式**、且**被布局截断就不授权**的控件 ——
 *     为一件系统已经提供的事付这两种代价都不划算。
 *   · `clearClipboard`：它的注释写着"含凭据的复制之后应主动清理"，但**全仓没有任何复制凭据的入口**
 *     （复核过三处 `copyText`：诊断报告〔已显式剔除凭据〕、右栏行复制、消息复制）⇒ 这条策略
 *     当前没有前提。将来若新增"复制凭据"的入口，要同时接清理 —— 这条登记在 parity-matrix 的
 *     `hdsh-clipboard` 行，而不是留一个没人调用的函数在这里。
 */

import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD5A1;
const TAG: string = 'platform/clipboard';

/** 写入纯文本；返回是否成功（失败不抛，调用方可降级为提示「复制失败」）。 */
export async function copyText(text: string): Promise<boolean> {
  try {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    await pasteboard.getSystemPasteboard().setData(data);
    return true;
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'setData failed: %{public}s', e.message);
    return false;
  }
}
