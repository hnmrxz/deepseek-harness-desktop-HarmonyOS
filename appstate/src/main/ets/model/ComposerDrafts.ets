/**
 * **每个会话各有一份输入草稿**（P8-3，上下文契约）。
 *
 * ## 官方契约（逐字）
 *
 * `dsh-client-ui-conversation/lib/types/client/contract/views.d.ts`：
 *
 * ```ts
 * /** Composer draft (persisted; survives session switches and reloads). *\/
 * draft: string;
 * ```
 *
 * 两件事都写在这一行里：草稿是**会话视图状态的一部分**（即"每个会话各有一份"），
 * 而且它**跨会话切换与重载都要活着**。
 *
 * ## 我们此前是什么样，以及真实后果
 *
 * 草稿是 `Index` 上的**一个** `@State draft`（全应用一份），切会话时不动它。于是：
 *   1. 在会话 A 里写了一半 ⇒ 切到会话 B ⇒ 输入框里还是 A 的那段话。用户顺手一按发送，
 *      **那段话发给了 B**（内容与收件人都错，而他只会看到"怎么发到这儿了"）；
 *   2. 附件是**会话作用域**的（中枢切会话时清空，理由见 `clearAttachments` 的注释），
 *      草稿却不是 ⇒ 同一个输入框里"文字属于上一个会话、附件属于这一个"，
 *      两者本来就不是一套上下文；
 *   3. 从会话退回列表再进来：文字仍在（因为压根没动过），看起来像"对了"，
 *      但期间在别的会话里打的内容会被冲掉。
 *
 * ## 这一层做什么、不做什么
 *
 * 做：**按会话保存与取回**纯文本草稿，并给一个上限（会话多起来也不能无限长）。
 * 不做：**持久化到磁盘**（官方那句 "survives … reloads" 的后半截）。
 *     应用重启后草稿仍然会丢，这一条如实登记在 `docs/parity-matrix.md` §6，不在这里假装做到了。
 *
 * ## 为什么用两个平行数组而不是 `Record<string, string>`
 *
 * ArkTS 对索引签名的支持有限（本仓已在别处踩过），而**平行数组**还额外带来一个好处：
 * 顺序就是"最近写过谁"，淘汰规则因此不需要另存时间戳——`sessionIds[0]` 永远是最新的那条。
 */

/** 每会话草稿的容量上限（超出丢最久没写的那些）。 */
export const COMPOSER_DRAFT_MAX: number = 24;

/** 全部会话的草稿（值类型快照：视图每次拿到新对象，@State 才认得出变化）。 */
export interface ComposerDrafts {
  /** 会话 id，按"最近写过"排序（第 0 个最新） */
  sessionIds: string[];
  /** 与 `sessionIds` 一一对应的正文 */
  texts: string[];
}

/** 空草稿袋 */
export function emptyComposerDrafts(): ComposerDrafts {
  return { sessionIds: [], texts: [] };
}

/**
 * 取某个会话的草稿。
 *
 * 【空串的两种含义要分开看】"这个会话没写过"与"写了又清空了"在界面上是同一件事
 * （输入框是空的），所以这里一律返回空串；清空的条目会在 `putDraft` 里被**删掉**，
 * 不会在袋子里留一个空壳占位置。
 */
export function draftOf(drafts: ComposerDrafts, sessionId: string): string {
  if (sessionId.length === 0) {
    return '';
  }
  for (let i = 0; i < drafts.sessionIds.length; i++) {
    if (drafts.sessionIds[i] === sessionId) {
      return drafts.texts[i];
    }
  }
  return '';
}

/**
 * 写入某个会话的草稿（**不修改入参**：值类型快照，视图直接赋新对象）。
 *
 * 规则：
 *   · `text` 为空 ⇒ **删除**该会话的条目（不留空壳）；
 *   · 已存在 ⇒ 移到最前（"最近写过"）；
 *   · 超过上限 ⇒ 丢掉最久没写的（数组尾部）。
 */
export function putDraft(drafts: ComposerDrafts, sessionId: string, text: string): ComposerDrafts {
  if (sessionId.length === 0) {
    // 没有会话就没有"这个会话的草稿"可存：调用方（宿主）此时应把它当作界面临时状态处理
    return drafts;
  }
  const next: ComposerDrafts = { sessionIds: [], texts: [] };
  if (text.length > 0) {
    next.sessionIds.push(sessionId);
    next.texts.push(text);
  }
  for (let i = 0; i < drafts.sessionIds.length; i++) {
    if (drafts.sessionIds[i] === sessionId) {
      continue;
    }
    if (next.sessionIds.length >= COMPOSER_DRAFT_MAX) {
      break;
    }
    next.sessionIds.push(drafts.sessionIds[i]);
    next.texts.push(drafts.texts[i]);
  }
  return next;
}

/** 丢弃某个会话的草稿（发送成功后调用：那条草稿已经"用掉"了） */
export function dropDraft(drafts: ComposerDrafts, sessionId: string): ComposerDrafts {
  return putDraft(drafts, sessionId, '');
}

/** 袋子里有几个会话留着草稿（诊断/断言用；不做成界面读数，避免多一个没人看的数字） */
export function draftCount(drafts: ComposerDrafts): number {
  return drafts.sessionIds.length;
}
