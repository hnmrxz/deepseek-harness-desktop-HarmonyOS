/**
 * 「输入区接管」的**焦点规则**（官方 `dsh-client-ui-approval` / `-user-questions` 的语义）。
 *
 * ## 官方怎么做的（读 `@deepseek-ai/dsh-client-ui-approval` 的客户端源码）
 *
 * 官方把审批做成**输入区接管**：往 `conversation.composer` 槽位注册一个
 * **优先级 1、`select` 只选"本会话当前那一条"待决**的组件 ⇒
 *   · 卡片摆在**输入区**（用户的眼与手都在对话里），不是另一个页面；
 *   · **一次只呈现一条**（slot 的 `select` 返回单个 `PendingApproval`），不是一摞；
 *   · 文案取自官方字典：`waiting: "等待审批"`、`escalation: "工具 {toolName} 请求越权执行"`、
 *     `reject: "拒绝"`、`allowOnce: "允许一次"`。
 *
 * ## 为什么"只看本会话"是要紧的一条
 *
 * 我们自己那份 `pending` 是**中枢全量**（多会话混在一起）。在会话 A 的输入区列出会话 B 的审批，
 * 用户点下去**就是在替另一场会话放行** —— 这是误操作，不是排版问题。
 * 官方用 `sessions.scopeOf(owner)` 把范围钉死在当前会话，本文件把这层判断搬到纯模型里，
 * 于是"该显示哪一条"可以被 fixture 钉住，而不是散在视图的条件表达式里。
 */

import { PendingItem, PendingKind } from './Trajectory';

/**
 * 本会话当前该接管输入区的那一条待决（**没有就是 undefined**）。
 *
 * 取**第一条**（Host 的到达顺序）而不是"最新一条"：待决是**阻塞**语义，
 * 后到的不会让先到的失效，按到达顺序处理才是对的。
 */
export function pendingForSession(items: PendingItem[], sessionId: string): PendingItem | undefined {
  if (sessionId.length === 0) {
    return undefined;
  }
  for (let i = 0; i < items.length; i++) {
    if (items[i].sessionId === sessionId) {
      return items[i];
    }
  }
  return undefined;
}

/** 除本会话外还有多少条待决（用于那句"其它会话还有 N 项"的提示；0 = 不提示） */
export function pendingElsewhere(items: PendingItem[], sessionId: string): number {
  let n: number = 0;
  for (let i = 0; i < items.length; i++) {
    if (items[i].sessionId !== sessionId) {
      n++;
    }
  }
  return n;
}

/**
 * 卡片顶部那条状态带的文案。
 *
 * 审批用**官方原文** `等待审批`；提问官方没有对应的"等待"串（它的字典里是导航与提交类文案），
 * 故这里用同一句式的「等待回答」，并在文档里如实标注这是本仓措辞。
 */
export function takeoverStripText(item: PendingItem): string {
  return item.kind === PendingKind.APPROVAL ? '等待审批' : '等待回答';
}

/**
 * 卡片正文标题。
 *
 * 审批用**官方原文句式**：`工具 {toolName} 请求越权执行`（`toolName` 就是我们的 `item.title`）。
 * 提问直接用问题正文（官方也是把问题本身当标题）。
 */
export function takeoverHeadline(item: PendingItem): string {
  if (item.kind === PendingKind.APPROVAL) {
    return item.title.length > 0 ? `工具 ${item.title} 请求越权执行` : '工具请求越权执行';
  }
  return item.title;
}

/**
 * 卡片里那行**等宽**的原始请求（官方 `command` 样式：等宽字体、可换行）。
 *
 * 只对审批给：提问的 `raw` 是整组问题的 JSON，摆在这一行既读不懂也没必要；
 * 提问的补充说明走 `item.detail`，由卡片正文照常显示。
 */
export function takeoverCommand(item: PendingItem): string {
  return item.kind === PendingKind.APPROVAL ? item.raw : '';
}
