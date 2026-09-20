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

import { PendingItem, PendingAnswerDraft, PendingKind } from './Trajectory';

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

// ───────────────────────── 待决答复草稿（FR-013：状态必须住在宿主） ─────────────────────────

/**
 * 每个待决项最多留几条草稿（与 `COMPOSER_DRAFT_MAX` 同量级）。
 *
 * 上限的理由与输入草稿那条一样：待决会一条条被处理掉，但"用户点过、又没提交"的那些
 * 如果无限累积，内存与快照都会长起来。
 */
export const PENDING_ANSWER_MAX: number = 24;

/**
 * 一条待决项的答复草稿。
 *
 * 存的是**提问卡的逐题草稿**（第几题选了哪些选项 / 自定义答案填了什么）——
 * 它就是"半截答复"的真实载体：选项点一下即记进草稿（不立即提交，整组要一起交），
 * 自定义答案是真正的自由输入。对照 `QuestionComposer.kt` 的 `drafts`。
 *
 * 【审批卡的"拒绝理由"为什么不在这里】本端**没有任何地方**输入那个理由，而它也无法
 * 随应答上传（上游审批 outcome 是封闭词表 `allowed-once | rejected | cancelled |
 * unavailable`，没有承载理由的字段，见 `Index.decidePending` 的登记）。也就是说：
 * 它既没有生产者、也没有可用的消费者 —— 为它建一份状态只会是"看着像功能"的死管道。
 * （v1 的 `PendingPane.freeText/freeTextFor` 正是这种残留：从来没人写过，本次删除。）
 */
export interface PendingAnswerEntry {
  /** 待决 id（`PendingItem.id`） */
  itemId: string;
  /** 逐题草稿（空数组 = 没写过） */
  group: PendingAnswerDraft[];
}

/**
 * 全部待决项的答复草稿（值类型快照：视图每次拿到新对象，`@State` 才认得出变化）。
 *
 * ## 为什么必须住在**宿主**（FR-013 的硬要求）
 *
 * 折叠屏开合会换渲染路线：`PHONE`（折叠闭合 / 手机）→ `DESKTOP_LIKE`（展开）→ `PHONE`。
 * 那一刻原生树整体重建（`RemoteShell` ↔ `WebShell`），**组件私有的 `@State` 全部作废**——
 * 用户已经点选的选项、以及写了一半的自定义答案会消失，而他并不知道"折叠一下"等于"清空"。
 * 因此这类"用户正在输入的东西"必须与输入区草稿（`ComposerDrafts`）同一待遇：
 * 住在宿主 `Index` 上，经 props 下发、经回调回传。
 *
 * ## 形状为什么是"平行数组 / 条目数组"而不是 `Record<id, …>`
 *
 * 与 `ComposerDrafts` 同一条理由：ArkTS 对索引签名支持有限，而数组还额外把
 * "最近写过谁"变成顺序（不需要另存时间戳）。
 */
export interface PendingAnswerDrafts {
  /** 条目，按"最近写过"排序（第 0 个最新） */
  entries: PendingAnswerEntry[];
}

/** 空草稿袋 */
export function emptyPendingAnswerDrafts(): PendingAnswerDrafts {
  return { entries: [] };
}

/** 一条空条目（"这个待决没写过"与"写了又清空"在界面上是同一件事） */
function emptyEntry(itemId: string): PendingAnswerEntry {
  return { itemId: itemId, group: [] };
}

/**
 * 取某个待决的逐题草稿（没有就是**空数组**）。
 *
 * 【为什么返回空数组而不是 undefined】视图每帧都要读它（每个选项的选中态 + 输入框的值），
 * 让每个调用点都写一次判空只会把"没写过"这件事重复表达 N 遍；而空数组在
 * `QuestionGroupCard` 里等价于"还没点过任何选项"，与"没写过"是同一件事。
 */
export function pendingAnswerGroupOf(drafts: PendingAnswerDrafts, itemId: string): PendingAnswerDraft[] {
  if (itemId.length === 0) {
    return [];
  }
  for (let i = 0; i < drafts.entries.length; i++) {
    if (drafts.entries[i].itemId === itemId) {
      return drafts.entries[i].group;
    }
  }
  return [];
}

/** 写入（**不修改入参**）：把某个待决的条目整体换成 [next]；空条目直接删掉不留壳。 */
function putEntry(drafts: PendingAnswerDrafts, next: PendingAnswerEntry): PendingAnswerDrafts {
  if (next.itemId.length === 0) {
    return drafts;
  }
  const out: PendingAnswerDrafts = { entries: [] };
  if (next.group.length > 0) {
    out.entries.push(next);
  }
  for (let i = 0; i < drafts.entries.length; i++) {
    const e: PendingAnswerEntry = drafts.entries[i];
    if (e.itemId === next.itemId) {
      continue;
    }
    if (out.entries.length >= PENDING_ANSWER_MAX) {
      break;
    }
    out.entries.push(e);
  }
  return out;
}

/** 写逐题草稿（提问卡的一整组答案；空数组 ⇒ 该条目按"没写过"处理） */
export function putPendingAnswerGroup(drafts: PendingAnswerDrafts, itemId: string,
  group: PendingAnswerDraft[]): PendingAnswerDrafts {
  return putEntry(drafts, { itemId: itemId, group: group });
}

/** 丢弃某个待决的草稿（已经答复/被 Host 撤回：那条草稿"用掉"了，留着只会串到下次） */
export function dropPendingAnswer(drafts: PendingAnswerDrafts, itemId: string): PendingAnswerDrafts {
  return putEntry(drafts, emptyEntry(itemId));
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
