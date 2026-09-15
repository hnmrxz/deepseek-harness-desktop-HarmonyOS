/**
 * 提交失败后**要不要把草稿还回去**（P7-15，对齐官方 `dsh-client-ui-conversation` 的 sink 语义）。
 *
 * ## 官方怎么做的（源码原话）
 *
 * `dsh-client-ui-conversation` 的 `sink()` 注释：
 *   > "Default sink: **optimistic clear + prompt**. … a failed first prompt is an ordinary
 *   > prompt failure (banner via promptError, **draft restored only while untouched**)."
 *
 * 也就是三件事：① **先乐观清空**输入框（发出去就先当它发出去了，界面不卡着）；
 * ② 失败时走普通的错误横幅（我们的 `lastError` 就是这条）；③ **只有在用户还没动过输入框时**
 * 才把原文还回去 —— 否则会把用户刚敲的新内容覆盖掉（那是更糟的错）。
 *
 * ## 我们此前差哪一步
 *
 * `Index.sendDraft()` 清空草稿后就不管了：发送失败时用户的长消息**凭空消失**，
 * 只能重新敲一遍（而失败原因往往只是"Host 拒绝了一次参数"这种可以改一改再发的）。
 *
 * ## 一个必须区分的情形：离线排队
 *
 * 离线时中枢**会把这条消息放进待发队列**（`outbox`），并返回 `false`。
 * 这时**不能**把草稿还回去 —— 还回去等于"既排队又留在输入框"，用户一按发送就发出两条。
 * 所以判定要带上"这次失败是不是已经排队了"。
 *
 * 纯逻辑：不 import 任何 kit，可被 `tools/check-layout-fixtures.mjs` 钉住。
 */

/**
 * 失败后是否恢复草稿。
 *
 * @param sendOk 发送是否成功（成功当然不恢复：消息已经在会话里了）
 * @param queued 这次失败是否已经**进了待发队列**（离线排队；进了就不恢复）
 * @param currentDraft 当前输入框内容（用户可能已经敲了新的东西）
 * @param submitted 本次提交的原文（恢复时用**原文**，不是 trim 过的版本：用户敲的空行也是他的输入）
 */
export function shouldRestoreDraft(sendOk: boolean, queued: boolean, currentDraft: string,
  submitted: string): boolean {
  if (sendOk || queued) {
    return false;
  }
  if (submitted.length === 0) {
    return false;
  }
  // 「only while untouched」：只要输入框里已经有内容（哪怕只是空格），就不动它
  return currentDraft.length === 0;
}
