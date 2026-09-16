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
 * 做：**按会话保存与取回**纯文本草稿，并给一个上限（会话多起来也不能无限长）；
 *     以及**落盘用的编解码**（`serializeDrafts` / `parseDrafts`）——官方那句
 *     "survives session switches **and reloads**" 的后半截靠它们兑现。
 * 不做：不碰存储。读写由 `platform/LocalPrefs` 负责（`platform` 不许依赖 `appstate`，
 *     所以"存成什么形状"必须由这一层决定、以字符串交给平台层）。
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

/**
 * 袋子的落盘表示（JSON 字符串）。
 *
 * 【为什么用平行数组直接序列化，而不是 `Record<会话 id, 文本>`】顺序就是"最近写过"，
 * `Record` 会把顺序丢掉（JS 对象键序不是契约）；而平行数组原样可存，解析回来顺序仍在。
 * 会话 id 是我们自己从 Host 拿的字符串，这里只做 JSON 转义，不猜内容。
 */
export function serializeDrafts(drafts: ComposerDrafts): string {
  const ids: string[] = [];
  const texts: string[] = [];
  for (let i = 0; i < drafts.sessionIds.length; i++) {
    if (i >= COMPOSER_DRAFT_MAX) {
      break;
    }
    if (drafts.sessionIds[i].length === 0 || drafts.texts[i].length === 0) {
      // 空文本不落盘：落盘只该存"真的有内容"的那些（与 `putDraft` 的规则一致）
      continue;
    }
    ids.push(drafts.sessionIds[i]);
    texts.push(drafts.texts[i]);
  }
  return JSON.stringify({ sessionIds: ids, texts: texts });
}

/**
 * 解析落盘的草稿袋。**坏输入一律当空**（而不是抛错、也不是半份数据）。
 *
 * 【为什么必须宽容】这段字符串来自上一次运行的磁盘（可能被截断、可能是旧版本写的、
 * 也可能被用户/系统清理工具改过）。草稿是**便利数据**，为它崩一次启动完全不值得；
 * 而"半个袋子"比"空袋子"更危险（可能出现 `sessionIds` 与 `texts` 长度不一致的错配，
 * 把甲的草稿显示在乙的会话里 —— 正是 P8-3 要修的那类错误）。故：**校验长度一致 + 类型正确 + 丢空项**，
 * 任何一条不满足就退回空袋子。
 */
export function parseDrafts(raw: string): ComposerDrafts {
  if (raw.length === 0) {
    return emptyComposerDrafts();
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (err) {
    return emptyComposerDrafts();
  }
  if (parsed === null || typeof parsed !== 'object') {
    return emptyComposerDrafts();
  }
  const record = parsed as Record<string, Object>;
  const ids: Object = record.sessionIds;
  const texts: Object = record.texts;
  if (!Array.isArray(ids) || !Array.isArray(texts)) {
    return emptyComposerDrafts();
  }
  const idList: Object[] = ids as Object[];
  const textList: Object[] = texts as Object[];
  if (idList.length !== textList.length) {
    // 长度不一致 = 错配风险 ⇒ 宁可全部丢掉（见上面的说明）
    return emptyComposerDrafts();
  }
  const out: ComposerDrafts = emptyComposerDrafts();
  for (let i = 0; i < idList.length; i++) {
    if (out.sessionIds.length >= COMPOSER_DRAFT_MAX) {
      break;
    }
    if (typeof idList[i] !== 'string' || typeof textList[i] !== 'string') {
      continue;
    }
    const id: string = idList[i] as string;
    const text: string = textList[i] as string;
    if (id.length === 0 || text.length === 0) {
      continue;
    }
    out.sessionIds.push(id);
    out.texts.push(text);
  }
  return out;
}
