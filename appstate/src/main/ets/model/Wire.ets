/**
 * 真实连接的**接线契约**：请求构造器 + 回复投影（UI 意图 ↔ Host）。
 *
 * 事实基线（**逐条实测自上游声明文件**，不是推测）：
 *   来源：`@deepseek-ai/dsh-api-session-controller` 0.1.5-rc.1 的 `lib/types/types.d.ts`，
 *        外加 `@deepseek-ai/dsh-api-gateway` 的 `lib/types/stream-protocol.d.ts`
 *        与 `@deepseek-ai/dsh-user-approval` / `@deepseek-ai/dsh-user-questions` 的 `types.d.ts`。
 *   采集路径：`.research/upstream-0.1.5/node_modules/@deepseek-ai/`。
 *
 * 分层纪律：
 *   - **端点名**一律来自 `dshcompat`（唯一允许持有上游端点字面量的模块），本文件不写任何端点字面量；
 *   - **取值工具**来自 `connection`（`isRecord` / `getString` 等），因为所有输入都是外部 JSON；
 *   - 本文件不含 UI 依赖，可单测。
 *
 * ───────────────────────── 最重要的一条更正 ─────────────────────────
 * **会话标题不在顶层字段上。**
 *   `SessionSummary` 的实测字段是
 *   `{sessionId, updatedAt, running, blank, parentSessionId?, origin?, cwd?, projections?}`——
 *   **没有** `title`。标题在 `summary.projections.values.title`，由会话标题投影提供，
 *   且其类型是 **`string | null`**（`null` = 还没有标题落地，不是空串）。
 *   因此绝不能用 `getString(summary, 'title')` 去取标题：那永远得到空串，
 *   而「空串」与「用户真的没起标题」在 UI 上表现不同，会被误判成「标题为空」而掩盖问题。
 *   本文件用 `titleOfSummary()` 读投影并给出**诚实**的兜底（cwd 末段），
 *   同时用 `TitleResolution.source` 告诉 UI「这是真标题还是占位」。
 * ─────────────────────────────────────────────────────────────────────
 */

import {
  argsFor,
  FILE_UPLOAD_ENDPOINT,
  SESSION_CANCEL_ENDPOINT,
  SESSION_CREATE_ENDPOINT,
  SESSION_FOLLOW_ENDPOINT,
  SESSION_LIST_ENDPOINT,
  SESSION_PROMPT_ENDPOINT,
  SESSION_RENAME_ENDPOINT
} from 'dshcompat';
import {
  EVENTS_RESULT_ENDPOINT,
  getArray,
  getField,
  getNumber,
  getRecord,
  getString,
  isRecord
} from 'connection';

/** JSON 安全值的读法：一律经 `connection` 的取值工具收窄，不做无检查下标访问。 */
type JsonBag = Record<string, Object>;

/** 标题占位文案（Host 没有标题且无从兜底时使用）。 */
export const UNTITLED_SESSION: string = '未命名会话';

// ═════════════════════════ 1. session/list ═════════════════════════

/**
 * `session/list` 的业务参数体。
 *
 * 实测：该端点参数形态是 `ArgsShape.UNDERSCORE_REQUEST`，
 * 即上线时会被 `dshcompat.buildArgs()` 包成 `{_request: {...}}`。
 * **因此这里不自己加 `_request` 外壳**：外壳由生成上表决定，
 * 手写外壳会在上游改形态时变成双重包装（`{_request:{_request:…}}`）。
 */
export interface SessionListRequest {
  /** 翻页游标；不传表示第一页 */
  cursor?: string;
}

/**
 * 构造 `session/list` 的 args 载荷（含形态外壳）。
 *
 * 返回 `Object | undefined`：undefined 表示该 endpoint 不在兼容上表里
 * （Host 版本过旧或上表未收录），调用方据此走能力探测降级，而不是盲目发包。
 *
 * 命名说明：`SessionList.ets` 已有一份 `sessionListPayload(body: Object)`（容忍字段改名的宽松版）。
 * 本函数是**线形精确版**且入参是游标而不是整包 body，两者签名不同，
 * 因此改名成 `sessionListWirePayload` 以避免 `Index.ets` 出口重名
 * （重复导出会让整个模块编译失败，而不是只报一个警告）。
 */
export function sessionListWirePayload(cursor: string): Object | undefined {
  const body: SessionListRequest = {};
  if (cursor.length > 0) {
    body.cursor = cursor;
  }
  return argsFor(SESSION_LIST_ENDPOINT, body);
}

/** `session/list` 的端点（供连接层发起调用，避免 UI 层写字面量）。 */
export function sessionListEndpoint(): string {
  return SESSION_LIST_ENDPOINT;
}

/** `session/list` 的回复值：`{items: SessionSummary[]}`。 */
export interface SessionListValue {
  items: SessionSummaryWire[];
}

/**
 * 会话列表项的**实测线形**。
 *
 * 字段名与上游声明文件逐字对应；`projections` 是「投影快照」，
 * 标题等被折叠出来的值都在里面（见文件头「最重要的一条更正」）。
 *
 * ── 权威样本（0.1.5-rc.1 真实 Host 实测，逐字保留） ──
 * ```json
 * {"sessionId":"session-07917d40-…","updatedAt":1789051283087,"running":false,"blank":true,
 *  "cwd":"D:\\dev\\deepseek-harness-desktop-HarmonyOS",
 *  "projections":{"asOfSeq":2,"values":{
 *    "title":null,"goal":null,"tokenUsage":{},"contextPressure":{},
 *    "contextBreakdown":{},"sessionStats":{},"turnOutline":[],
 *    "agentPreset":"standard","subagentCatalog":[],"subagentTiming":{},"subagent":null,
 *    "permissions":{"options":[…],"currentValue":"workspace-write"},
 *    "modelSelection":{"lastUsed":null,"next":null},
 *    "sessionListMetadata":{"blank":true,"lastPromptAt":null},
 *    "imageLimits":{"maxImageBytes":20971520,…},
 *    "inbox":{"next-turn":[],"next-step":[]},"todos":null,
 *    "plan":{"active":false,"pending":false}}}}
 * ```
 * 两条可直接依赖的事实：
 *   1. **顶层没有 `title`**（本文件因此把标题读法集中在 `resolveSessionTitle()`）；
 *   2. `projections.values` 实测有 **18 个键**（见下清单），
 *      因此**投影键是开放集合**，不能用「键不存在 ⇒ 值就是空」的假设去读业务字段。
 */
export interface SessionSummaryWire {
  sessionId: string;
  /** 最近活动时间（毫秒时间戳） */
  updatedAt: number;
  running: boolean;
  /** 折叠后的前缀里是否**没有任何轮次**（空会话）；用于列表区分「刚建好还没说话」 */
  blank: boolean;
  /** 父会话 id（仅子代理会话有） */
  parentSessionId?: string;
  /** 来源；实测唯一取值是 `'subagent'` */
  origin?: string;
  /** 工作目录 */
  cwd?: string;
  /** 投影提示：`asOfSeq` 是快照对应的会话事件游标 */
  projections?: ProjectionHints;
}

/** 投影快照：`values` 的每个值都是 JSON 安全值（上游类型 `JsonValue`）。 */
export interface ProjectionHints {
  asOfSeq: number;
  values: JsonBag;
}

/**
 * 投影里承载标题的键。
 *
 * **上游字段名，本文件唯一刻意保留的一处字面量**，理由：
 *   它是**投影键**（由 `dsh-session-title` 注册的 `title` 投影提供），
 *   既不是一个 endpoint，也不在上表（上表只收 endpoint，不收投影键）里，
 *   因此无处可 import。它必须与 endpoint 名一样集中且可被漂移检查发现——
 *   见本文件末尾「上游字段名缺口」一节，已列为待补清单。
 *
 * 实测类型是 `string | null`：`null` = 还没有标题落地（不是空串）。
 */
const TITLE_PROJECTION_KEY: string = 'title';

/**
 * 实测的 `projections.values` 键清单（0.1.5-rc.1，共 18 个，逐字精确）。
 *
 * 存在理由：
 *   这份清单是**可执行的事实记录**。它有两个用途——
 *   1. 评审时可比对「上游新增/删除了哪个投影」；
 *   2. 提醒后续实现者：`values` 是开放集合，读任何键都必须容忍缺失，
 *      绝不能因为「样本里见过 title 就以为 title 一定有值」。
 * 不导出（本层没有消费方）：它只作为本文件的校验性文档。
 */
const KNOWN_PROJECTION_KEYS: string[] = [
  'title', 'goal', 'tokenUsage', 'contextPressure', 'contextBreakdown', 'sessionStats',
  'turnOutline', 'agentPreset', 'subagentCatalog', 'subagentTiming', 'subagent', 'permissions',
  'modelSelection', 'sessionListMetadata', 'imageLimits', 'inbox', 'todos', 'plan'
];

/** 标题来源：区分「Host 真的给了标题」与「我们兜底出来的占位」。 */
export enum TitleSource {
  /** Host 投影里的真标题 */
  HOST = 'host',
  /** Host 没有标题，用 cwd 末段兜底 */
  CWD_FALLBACK = 'cwd-fallback',
  /** 完全无从得知 */
  NONE = 'none'
}

/**
 * 标题解析结果。
 *
 * 为什么要带 `source` 而不只返回字符串：
 *   D3 §4 文案纪律要求「不把技术噪声伪装成用户内容」。
 *   把 cwd 末段当成会话标题显示是可以接受的兜底，但 UI 必须能选择**弱化**显示
 *   （否则用户会以为会话真的叫 `my-repo`）。只返回字符串就永久丢失了这个信息。
 */
export interface TitleResolution {
  title: string;
  source: TitleSource;
}

/**
 * 读取会话标题（**唯一正确姿势**）。
 *
 * 顺序：`projections.values.title`（string | null）
 *   → `cwd` 末段（末段为空则退回完整 cwd）
 *   → `UNTITLED_SESSION`。
 */
export function resolveSessionTitle(summary: SessionSummaryWire): TitleResolution {
  const direct: string | null = projectionTitle(summary);
  if (direct !== null && direct.length > 0) {
    return { title: direct, source: TitleSource.HOST };
  }
  const cwd: string = summary.cwd !== undefined ? summary.cwd : '';
  const base: string = cwdBasename(cwd);
  if (base.length > 0) {
    return { title: base, source: TitleSource.CWD_FALLBACK };
  }
  return { title: UNTITLED_SESSION, source: TitleSource.NONE };
}

/** 便捷形式：只要标题字符串（丢失来源信息，列表排序/搜索等场景够用）。 */
export function titleOfSummary(summary: SessionSummaryWire): string {
  return resolveSessionTitle(summary).title;
}

/**
 * 读投影标题，**严格区分 null 与「键不存在」**。
 *
 * 上游类型是 `string | null`：`null` 有明确语义（还没有标题落地）；
 * 键不存在则说明**这个 Host 根本没挂标题投影**（能力缺失）。
 * 两者对 UI 的含义不同（前者等标题生成，后者永远不会有标题），
 * 因此这里都返回 `null` 但由 `TitleSource` 兜底体现差异——不额外再分一档，
 * 是因为当前 UI 对两者的处理相同（都走 cwd 兜底）。
 */
function projectionTitle(summary: SessionSummaryWire): string | null {
  const hints: ProjectionHints | undefined = summary.projections;
  if (hints === undefined) {
    return null;
  }
  const value: string | undefined = getString(hints.values, TITLE_PROJECTION_KEY);
  return value !== undefined ? value : null;
}

/**
 * 该投影键是否在实测清单内。
 *
 * 用途：诊断页与漂移检查。返回 `false` **不代表数据有问题**——
 * 它只说明「这个键不在我们采集样本时见过的 18 个里」，
 * 可能是上游新增了投影（正是我们想尽早知道的事）。
 * 因此消费方应把它当**提示**而不是校验失败。
 */
export function isKnownProjectionKey(key: string): boolean {
  for (let i = 0; i < KNOWN_PROJECTION_KEYS.length; i++) {
    if (KNOWN_PROJECTION_KEYS[i] === key) {
      return true;
    }
  }
  return false;
}

/**
 * 取路径末段（Windows `\` 与 POSIX `/` 都支持）。
 *
 * 为什么不直接用 `split('/')`：Host 可能跑在 Windows 上（本产品的主力平台之一），
 * cwd 会是 `D:\dev\repo`，只按 `/` 切会得到整条路径。
 */
export function cwdBasename(cwd: string): string {
  let end: number = cwd.length;
  while (end > 0 && isSeparator(cwd.charAt(end - 1))) {
    end--;
  }
  let start: number = end;
  while (start > 0 && !isSeparator(cwd.charAt(start - 1))) {
    start--;
  }
  return cwd.substring(start, end);
}

function isSeparator(ch: string): boolean {
  return ch === '/' || ch === '\\';
}

/**
 * 从 `session/list` 回复里投影出列表。
 *
 * 与 `appstate/model/SessionList.ets` 的宽松投影（多字段别名容忍）不同，
 * 本函数按**实测线形**取值：它服务于已确认 0.1.5-rc.1 的连接。
 * 容忍改名的旧投影仍保留在 SessionList.ets，两者并存不冲突。
 */
export function projectSessionListWire(value: Object | undefined): SessionSummaryWire[] {
  const out: SessionSummaryWire[] = [];
  if (value === undefined) {
    return out;
  }
  const items: Object[] | undefined = getArray(value, 'items');
  if (items === undefined) {
    return out;
  }
  for (let i = 0; i < items.length; i++) {
    const item: Object = items[i];
    if (!isRecord(item)) {
      continue;
    }
    const id: string | undefined = getString(item, 'sessionId');
    if (id === undefined || id.length === 0) {
      // 无 id 的条目无法用于任何后续调用，跳过而不是产出脏数据。
      continue;
    }
    out.push({
      sessionId: id,
      updatedAt: readNumber(item, 'updatedAt'),
      running: readBoolean(item, 'running'),
      blank: readBoolean(item, 'blank'),
      parentSessionId: optionalString(item, 'parentSessionId'),
      origin: optionalString(item, 'origin'),
      cwd: optionalString(item, 'cwd'),
      projections: readProjections(item)
    });
  }
  return out;
}

function readProjections(source: Object | null | undefined): ProjectionHints | undefined {
  const raw: Object | undefined = getRecord(source, 'projections');
  if (raw === undefined) {
    return undefined;
  }
  return {
    asOfSeq: readNumber(raw, 'asOfSeq'),
    values: bagOf(raw, 'values')
  };
}

// ═════════════════════════ 2. session/create ═════════════════════════

/** `session/create` 业务参数体（全部可选：三者都不传即「用默认工作区建一个新会话」）。 */
export interface SessionCreateRequest {
  workspaceId?: string;
  cwd?: string;
  /** 显式指定 id（用于「认领」一个已知 id）；不传由 Host 生成 */
  sessionId?: string;
  agentPreset?: string;
}

/** `session/create` 的 args 载荷（形态外壳由上表决定）。 */
export function sessionCreatePayload(workspaceId: string, cwd: string, sessionId: string,
  agentPreset: string): Object | undefined {
  const body: SessionCreateRequest = {};
  if (workspaceId.length > 0) {
    body.workspaceId = workspaceId;
  }
  if (cwd.length > 0) {
    body.cwd = cwd;
  }
  if (sessionId.length > 0) {
    body.sessionId = sessionId;
  }
  if (agentPreset.length > 0) {
    body.agentPreset = agentPreset;
  }
  return argsFor(SESSION_CREATE_ENDPOINT, body);
}

/** `session/create` 回复值。 */
export interface SessionCreateValue {
  sessionId: string;
  /** Host 实际生效的 agent 预设（未指定时可能回填默认值） */
  agentPreset?: string;
}

/** 投影 `session/create` 回复。 */
export function projectSessionCreate(value: Object | undefined): SessionCreateValue | undefined {
  if (value === undefined) {
    return undefined;
  }
  const id: string | undefined = getString(value, 'sessionId');
  if (id === undefined || id.length === 0) {
    return undefined;
  }
  return { sessionId: id, agentPreset: optionalString(value, 'agentPreset') };
}

// ═════════════════════════ 3. session/prompt ═════════════════════════

/** 提示词入队模式：排队，或打断当前轮次改为插话。 */
export enum PromptMode {
  QUEUE = 'queue',
  STEER = 'steer'
}

/**
 * 提示词内容片段（**三选一**，与上游 `PromptContentPart` 逐字对应）。
 *
 * 取舍：上游是三路联合类型（`{type:'text'} | {type:'image'} | {type:'file'}`）。
 * 本文件按仓内既有约定把联合字段收到一个接口里（可选字段），
 * 原因是对象字面量与联合类型在 ArkTS 里容易触发「字面量必须匹配已声明类型」的报错，
 * 而本结构要由 UI 直接构造。判别依据仍是必需的 `type` 字段。
 */
export interface PromptContentPart {
  /** 判别字段：`'text'` / `'image'` / `'file'` */
  type: string;
  /** 文本正文（仅 `type='text'`） */
  text?: string;
  /** 图片 MIME 类型（仅 `type='image'`） */
  mediaType?: string;
  /** 图片 base64 数据（仅 `type='image'`） */
  data?: string;
  /** 原始文件名（仅 `type='image'`，可选） */
  name?: string;
  /**
   * 上传回执 id（仅 `type='file'`）。
   * 来自**同一会话**上先行的 `fileUploads/upload` 调用返回的不透明回执；
   * 跨会话复用该 id 会被 Host 拒绝（它绑定了会话身份）。
   */
  receiptId?: string;
}

/** 构造文本片段。 */
export function textPart(text: string): PromptContentPart {
  return { type: 'text', text: text };
}

/** 构造图片片段（`data` 是 base64，不含 `data:` 前缀）。 */
export function imagePart(mediaType: string, data: string, name: string): PromptContentPart {
  const part: PromptContentPart = { type: 'image', mediaType: mediaType, data: data };
  if (name.length > 0) {
    part.name = name;
  }
  return part;
}

/** 构造文件片段（`receiptId` 必须来自同一会话的先行上传）。 */
export function filePart(receiptId: string): PromptContentPart {
  return { type: 'file', receiptId: receiptId };
}

/** `session/prompt` 业务参数体。 */
export interface SessionPromptRequest {
  /** 客户端铸造的请求 id：用于把乐观消息与落库消息对上 */
  requestId: string;
  sessionId: string;
  mode: string;
  content: PromptContentPart[];
  /** 客户端时区（可选；Host 需要它来做时间上下文） */
  clientTimeZone?: string;
}

/**
 * 构造 `session/prompt` 的 args 载荷。
 *
 * `requestId` 由**调用方**铸造并传入（而不是本函数内部生成）：
 * 它是纯函数的一部分输入才能让本模块保持可单测，
 * 同时调用方需要在同一处用这个 id 建立「乐观消息 → 落库消息」的映射。
 * 客户端的 uuid 生成器在 `connection`（`randomUuid`），装配层取用即可。
 */
export function promptPayload(requestId: string, sessionId: string, mode: PromptMode,
  content: PromptContentPart[], clientTimeZone: string): Object | undefined {
  const body: SessionPromptRequest = {
    requestId: requestId,
    sessionId: sessionId,
    mode: mode === PromptMode.STEER ? 'steer' : 'queue',
    content: content
  };
  if (clientTimeZone.length > 0) {
    body.clientTimeZone = clientTimeZone;
  }
  return argsFor(SESSION_PROMPT_ENDPOINT, body);
}

/** `session/prompt` 回复值：上游是字面量 `true`（不是对象），表示「已进 Agent 收件箱」。 */
export interface SessionPromptValue {
  accepted: boolean;
}

/** 投影 `session/prompt` 回复（容错：字段缺失视为未接收，绝不乐观当成成功）。 */
export function projectSessionPrompt(value: Object | undefined): SessionPromptValue {
  if (value === undefined) {
    return { accepted: false };
  }
  return { accepted: readBoolean(value, 'accepted') };
}

// ═════════════════════════ 4. 会话变更类端点（endpoint 由调用方给出） ═════════════════════════

/**
 * ⚠ **上游端点名缺口（必须补在 dshcompat，本文件刻意不写）** ⚠
 *
 * 下列两个端点在 `dshcompat` 的上表（`DSH_ENDPOINTS`）里**有记录**，
 * 但 `Aliases.ets` 尚未为它们导出便捷常量：
 *   `session/fork`、`session/updateQueue`
 *
 * 按分层纪律，「上游端点名」只允许出现在 `dshcompat`；
 * 本文件是 `appstate` 的文件，**不得**在此写字面量，也不得在别处新造一个常量模块
 * （那会把上游知识复制出第二份，漂移检查就管不到了）。
 * 因此在常量补齐前，下面两个构造器把 endpoint 作为**参数**接收：
 *   调用方从 `dshcompat` 取得（`argsFor`/上表里可查），本文件保持零端点字面量。
 * 补齐方式：在 `Aliases.ets` 增加 `SESSION_FORK_ENDPOINT` 与
 * `SESSION_UPDATE_QUEUE_ENDPOINT` 两个常量并加入 `Index.ets` 的导出清单即可；
 * 届时把这两个构造器的入参收敛掉，本文件的其余部分不需要改动。
 *
 * （`session/cancel` 与 `session/rename` 原先也在此清单里，
 *   现已在 `dshcompat` 补上常量，故本文件已改为直接使用常量。）
 */

/**
 * 校验并包装一个「由调用方提供的」端点参数体。
 *
 * 用 `argsFor()` 而不是自己拼 `{request: body}`：形态外壳（REQUEST / UNDERSCORE_REQUEST /
 * NAMED）是生成上表的事实，手写会让上游改形态时静默发错包。
 * endpoint 不在上表 ⇒ `argsFor()` 返回 undefined ⇒ 调用方走能力降级。
 *
 * 约定：`endpoint` 必须来自 `dshcompat`（本文件是 appstate 层，不接受端点字面量）。
 * 目前仅 `session/fork` 与 `session/updateQueue` 仍需调用方传入——
 * 见下方「⚠ 上游端点名缺口」。
 */
function payloadFor(endpoint: string, body: Object): Object | undefined {
  if (endpoint.length === 0) {
    return undefined;
  }
  return argsFor(endpoint, body);
}

/** `session/cancel` 业务参数体。 */
export interface SessionCancelRequest {
  sessionId: string;
}

/** `session/cancel` 回复值（`{accepted: true}`）。 */
export interface SessionCancelValue {
  accepted: boolean;
}

/** 构造 `session/cancel` 的 args 载荷（端点取自 `dshcompat`）。 */
export function sessionCancelPayload(sessionId: string): Object | undefined {
  const body: SessionCancelRequest = { sessionId: sessionId };
  return payloadFor(SESSION_CANCEL_ENDPOINT, body);
}

/** `session/rename` 业务参数体。 */
export interface SessionRenameRequest {
  sessionId: string;
  title: string;
}

/** `session/rename` 回复值：规范化后的标题 + 提交它的持久事件序号。 */
export interface SessionRenameValue {
  title: string;
  seq: number;
}

/** 构造 `session/rename` 的 args 载荷（端点取自 `dshcompat`）。 */
export function sessionRenamePayload(sessionId: string, title: string): Object | undefined {
  const body: SessionRenameRequest = { sessionId: sessionId, title: title };
  return payloadFor(SESSION_RENAME_ENDPOINT, body);
}

/**
 * 投影 `session/rename` 回复。
 *
 * 注意：Host 会**规范化**标题（去控制字符、按 UTF-8 字节预算截断），
 * 因此返回的 `title` 可能与我们提交的不同——UI 必须用回复里的值回写输入框，
 * 否则界面显示的标题与落库标题会不一致。
 */
export function projectSessionRename(value: Object | undefined): SessionRenameValue | undefined {
  if (value === undefined) {
    return undefined;
  }
  const title: string | undefined = getString(value, 'title');
  if (title === undefined) {
    return undefined;
  }
  return { title: title, seq: readNumber(value, 'seq') };
}

/** `session/fork` 业务参数体。 */
export interface SessionForkRequest {
  sessionId: string;
  /** 分叉点（含）；不传 = 从当前位置分叉 */
  atSeq?: number;
}

/** `session/fork` 回复值。 */
export interface SessionForkValue {
  sessionId: string;
}

/** 构造 `session/fork` 的 args 载荷（endpoint 由调用方从 dshcompat 提供）。 */
export function sessionForkPayload(endpoint: string, sessionId: string,
  atSeq: number): Object | undefined {
  const body: SessionForkRequest = { sessionId: sessionId };
  if (atSeq >= 0) {
    body.atSeq = atSeq;
  }
  return payloadFor(endpoint, body);
}

/** 投影 `session/fork` 回复。 */
export function projectSessionFork(value: Object | undefined): SessionForkValue | undefined {
  if (value === undefined) {
    return undefined;
  }
  const id: string | undefined = getString(value, 'sessionId');
  if (id === undefined || id.length === 0) {
    return undefined;
  }
  return { sessionId: id };
}

/**
 * 队列项动作（三选一）：改内容 / 移除 / 转插话。
 *
 * 上游是联合类型；按仓内约定收成一个接口 + `kind` 判别字段。
 */
export interface QueueActionBody {
  /** `'edit'` / `'remove'` / `'steer'` */
  kind: string;
  /**
   * 替换内容（仅 `kind='edit'`）。
   *
   * 上游声明为 `readonly ContentBlock[]`，并注明「**非空的纯文本**替换内容」。
   * 已确认 `ContentBlock` = `ContentBlockMap[ContentBlockType]` 的联合，其中
   * `TextBlock = {type:'text', text:string}`（`@deepseek-ai/dsh-llm/lib/types/types.d.ts`）。
   * 上游把编辑限制为纯文本，因此本文件**只**允许 `QueueTextBlock`：
   * 用「任意 ContentBlock」放开等于允许 UI 传图片块/工具块，而那些会被 Host 拒绝。
   */
  content?: QueueTextBlock[];
}

/** 队列编辑用的文本块（`ContentBlock` 里唯一被「编辑」动作接受的分支）。 */
export interface QueueTextBlock {
  type: string;
  text: string;
}

/**
 * `session/updateQueue` 业务参数体。
 *
 * `itemId` 的上游类型是 `MessageId`。**已确认线形就是字符串**：
 * `MessageId = Branded<'MessageId'>`，而
 * `Branded<B> = string & {readonly [BRAND]: B}`（`@deepseek-ai/dsh-brand`）——
 * 品牌是**编译期独有**的标记（源码注释原话：brand is compile-time-only），
 * 运行时与原字符串完全同构（`string & {...}` 在 TS 里退化为 `string`）。
 * 因此本文件用 `string` 承载，不引入品牌类型。
 */
export interface SessionUpdateQueueRequest {
  sessionId: string;
  itemId: string;
  action: QueueActionBody;
}

/**
 * 构造队列「编辑」动作。
 *
 * 入参是**文本数组**而不是块数组：上游要求 `content` 非空且为纯文本，
 * 让调用方自己拼 `{type:'text'}` 只会给「拼错/传图片块」留机会。
 * 返回的 `content` 在 `texts` 为空时为空数组——Host 会拒绝，调用方须保证非空。
 */
export function queueEditAction(texts: string[]): QueueActionBody {
  const blocks: QueueTextBlock[] = [];
  for (let i = 0; i < texts.length; i++) {
    blocks.push({ type: 'text', text: texts[i] });
  }
  return { kind: 'edit', content: blocks };
}

/** 构造队列「移除」动作。 */
export function queueRemoveAction(): QueueActionBody {
  return { kind: 'remove' };
}

/** 构造队列「转插话」动作（把已排队项提前为打断当前轮次）。 */
export function queueSteerAction(): QueueActionBody {
  return { kind: 'steer' };
}

/** 构造 `session/updateQueue` 的 args 载荷（endpoint 由调用方从 dshcompat 提供）。 */
export function sessionUpdateQueuePayload(endpoint: string, sessionId: string, itemId: string,
  action: QueueActionBody): Object | undefined {
  const body: SessionUpdateQueueRequest = { sessionId: sessionId, itemId: itemId, action: action };
  return payloadFor(endpoint, body);
}

// ═════════════════════════ 5. session/follow（流式） ═════════════════════════

/** 追流地址：普通会话。 */
export interface FollowSessionAddress {
  kind: string;
  sessionId: string;
}

/** 追流地址：子代理会话（必须同时给出父子 id 与模式）。 */
export interface FollowSubagentAddress {
  kind: string;
  parentSessionId: string;
  childSessionId: string;
  /** `'one-shot'` 或 `'continuable'`；两种模式的续跑语义不同 */
  mode: string;
}

/** 构造普通会话地址。 */
export function followSessionAddress(sessionId: string): FollowSessionAddress {
  return { kind: 'session', sessionId: sessionId };
}

/** 构造子代理地址。 */
export function followSubagentAddress(parentSessionId: string, childSessionId: string,
  mode: string): FollowSubagentAddress {
  return { kind: 'subagent', parentSessionId: parentSessionId, childSessionId: childSessionId, mode: mode };
}

/** `session/follow` 业务参数体。 */
export interface SessionFollowRequest {
  address: Object;
  /** 快照里最多带多少条历史消息（不传 = Host 默认） */
  maxMessages?: number;
  /** 是否附带进程内的助手流帧（仅 `true` 是合法值；不传即关闭） */
  assistantStream?: boolean;
}

/**
 * 构造 `session/follow` 的 args 载荷。
 *
 * `assistantStream` 取布尔入参而不是写死 `true`：
 * 上游类型是字面量 `true`（只能开不能显式关），
 * 用布尔入参把「开/不开」表达清楚，`false` 时**整个字段不出现**
 * （而不是发 `assistantStream: false`——那不是合法值，会被 Host 拒绝）。
 */
export function sessionFollowPayload(address: Object, maxMessages: number,
  assistantStream: boolean): Object | undefined {
  const body: SessionFollowRequest = { address: address };
  if (maxMessages >= 0) {
    body.maxMessages = maxMessages;
  }
  if (assistantStream) {
    body.assistantStream = true;
  }
  return argsFor(SESSION_FOLLOW_ENDPOINT, body);
}

/** 追流帧类型判别值（收成一个枚举，避免各层拼字符串）。 */
export enum FollowFrameType {
  SNAPSHOT = 'snapshot',
  EVENT = 'event',
  ASSISTANT_STREAM = 'assistant-stream'
}

/** 追流头（快照携带的会话逻辑元信息）。 */
export interface SessionWireHeader {
  version: number;
  id: string;
  createdAt: number;
  cwd?: string;
  parentSession?: string;
  /** 会话是否含分叉继承的前缀 */
  isSeeded: boolean;
  origin?: string;
  /** 子代理委派深度 */
  delegationDepth?: number;
  agentPreset?: string;
}

/** 一条会话事件（线形）。`data` 是事件私有载荷，本层不解释。 */
export interface SessionWireEvent {
  type: string;
  seq: number;
  time: number;
  data: Object;
  /** 可忽略事件标记：客户端不认识的 `ignorable` 事件可以安全跳过 */
  ignorable?: boolean;
  /** 表面替换操作的来源序号（见 `surfaceOp`） */
  sourceEventSeqs?: Object;
  /**
   * 表面位置操作：`'append'` 或 `{op:'replace', startSeq, endSeq}`。
   * 历史页重放时用它把「被替换掉的旧事件」从表面上摘掉。
   */
  surfaceOp?: Object;
}

/** 一条历史记录（实测只有 `type='event'` 一种）。 */
export interface SessionHistoryRecord {
  type: string;
  event: SessionWireEvent;
}

/** 快照帧。 */
export interface FollowSnapshotFrame {
  type: string;
  header: SessionWireHeader;
  /** 快照对应的会话事件游标（后续 `session/page` 要用它作为 `throughSeq`） */
  cursor: number;
  records: SessionHistoryRecord[];
  hasMore: boolean;
  projections: ProjectionHints;
  /** 进程内助手流的基线（仅在请求里开了 `assistantStream` 时出现） */
  assistantStream?: Object;
}

/** 实时事件帧。 */
export interface FollowEventFrame {
  type: string;
  event: SessionWireEvent;
}

/** 助手流帧的外壳。 */
export interface FollowAssistantStreamFrame {
  type: string;
  frame: Object;
}

/** 追流帧读取结果（判别字段 + 三种载荷；同一时刻只有一种非空）。 */
export interface FollowFrame {
  type: string;
  snapshot: FollowSnapshotFrame | undefined;
  event: FollowEventFrame | undefined;
  assistantStream: FollowAssistantStreamFrame | undefined;
}

/**
 * 把一条原始帧投影成 `FollowFrame`。
 *
 * 取值纪律：先读 `type` 再读对应载荷，
 * 不认识的 `type` 原样返回（`snapshot/event/assistantStream` 全为 undefined），
 * 让调用方决定是忽略还是报警——**不抛异常**，因为未知帧在协议升级期是正常现象。
 */
export function readFollowFrame(value: Object): FollowFrame {
  const type: string = readString(value, 'type');
  const frame: FollowFrame = {
    type: type,
    snapshot: undefined,
    event: undefined,
    assistantStream: undefined
  };
  if (type === FollowFrameType.SNAPSHOT) {
    frame.snapshot = readSnapshot(value);
  } else if (type === FollowFrameType.EVENT) {
    const event: SessionWireEvent | undefined = readEvent(getRecord(value, 'event'));
    if (event !== undefined) {
      frame.event = { type: type, event: event };
    }
  } else if (type === FollowFrameType.ASSISTANT_STREAM) {
    const inner: Object | undefined = getRecord(value, 'frame');
    if (inner !== undefined) {
      frame.assistantStream = { type: type, frame: inner };
    }
  }
  return frame;
}

function readSnapshot(value: Object): FollowSnapshotFrame | undefined {
  const header: SessionWireHeader | undefined = readHeader(getRecord(value, 'header'));
  if (header === undefined) {
    return undefined;
  }
  const records: SessionHistoryRecord[] = [];
  const raw: Object[] | undefined = getArray(value, 'records');
  if (raw !== undefined) {
    for (let i = 0; i < raw.length; i++) {
      const entry: Object | undefined = getRecord(raw[i], 'event');
      const event: SessionWireEvent | undefined = readEvent(entry);
      if (event !== undefined) {
        records.push({ type: 'event', event: event });
      }
    }
  }
  const projections: ProjectionHints | undefined = readProjections(value);
  const snapshot: FollowSnapshotFrame = {
    type: FollowFrameType.SNAPSHOT,
    header: header,
    cursor: readNumber(value, 'cursor'),
    records: records,
    hasMore: readBoolean(value, 'hasMore'),
    projections: projections !== undefined ? projections : emptyProjectionHints()
  };
  const stream: Object | undefined = getRecord(value, 'assistantStream');
  if (stream !== undefined) {
    snapshot.assistantStream = stream;
  }
  return snapshot;
}

function readHeader(value: Object | undefined): SessionWireHeader | undefined {
  if (value === undefined) {
    return undefined;
  }
  const id: string | undefined = getString(value, 'id');
  if (id === undefined || id.length === 0) {
    return undefined;
  }
  return {
    version: readNumber(value, 'version'),
    id: id,
    createdAt: readNumber(value, 'createdAt'),
    cwd: optionalString(value, 'cwd'),
    parentSession: optionalString(value, 'parentSession'),
    isSeeded: readBoolean(value, 'isSeeded'),
    origin: optionalString(value, 'origin'),
    delegationDepth: optionalNumber(value, 'delegationDepth'),
    agentPreset: optionalString(value, 'agentPreset')
  };
}

function readEvent(value: Object | undefined): SessionWireEvent | undefined {
  if (value === undefined) {
    return undefined;
  }
  const type: string | undefined = getString(value, 'type');
  if (type === undefined || type.length === 0) {
    return undefined;
  }
  const data: Object | undefined = getRecord(value, 'data');
  const event: SessionWireEvent = {
    type: type,
    seq: readNumber(value, 'seq'),
    time: readNumber(value, 'time'),
    data: data !== undefined ? data : emptyBagObject()
  };
  // 可选字段只在**真的存在**时才赋值：对象字面量里显式写 `undefined`
  // 在 ArkTS 严格模式下容易触发类型不匹配，而且会让「字段存在但为空」与「字段不存在」混淆。
  const ignorable: boolean | undefined = optionalBoolean(value, 'ignorable');
  if (ignorable !== undefined) {
    event.ignorable = ignorable;
  }
  const sources: Object | undefined = getRecord(value, 'sourceEventSeqs');
  if (sources !== undefined) {
    event.sourceEventSeqs = sources;
  }
  const surfaceOp: Object | undefined = getField(value, 'surfaceOp');
  if (surfaceOp !== undefined) {
    event.surfaceOp = surfaceOp;
  }
  return event;
}

// ═════════════════════════ 6. session/control（流式） ═════════════════════════

/** 控制帧类型判别值。 */
export enum ControlFrameType {
  BASELINE = 'baseline',
  QUEUE = 'queue',
  JOBS = 'jobs',
  PROJECTION = 'projection'
}

/** 一个排队项（尚未进入轮次的用户消息）。 */
export interface SessionQueuedItem {
  id: string;
  /** 位置：`'queued'` / `'steering'` / `'context'` */
  placement: string;
  /** 铸造该消息的 prompt 请求 id（用于清掉本地的乐观回显） */
  rpcId?: string;
  message: Object;
}

/**
 * 一条后台任务（`SessionJob`）。
 *
 * `id` 的上游类型是 `JobId`，与 `MessageId` / `SessionId` 同属
 * `Branded<string>`——**编译期独有的标记，线形上就是字符串**（见 `SessionUpdateQueueRequest` 的说明），
 * 因此本文件用 `string` 承载。
 */
export interface SessionJob {
  id: string;
  kind: string;
  label: string;
  /** `'running'` / `'stopping'` / `'completed'` / `'killed'` / `'failed'` */
  status: string;
  detail?: string;
  startedAt: number;
  finishedAt?: number;
}

/**
 * 控制流的起始基线。
 *
 * 三个字段都是 **sessionId → 数据** 的映射（上游是 `Record<SessionId, …>`）。
 */
export interface ControlBaseline {
  queues: JsonBag;
  jobs: JsonBag;
  projections: JsonBag;
}

/** 控制帧读取结果（判别字段 + 各载荷）。 */
export interface ControlFrame {
  type: string;
  baseline: ControlBaseline | undefined;
  sessionId: string;
  items: SessionQueuedItem[];
  jobs: SessionJob[];
  key: string;
  value: Object | undefined;
  seq: number;
}

/**
 * 把一条原始控制帧投影成 `ControlFrame`。
 *
 * **审批与提问不在这里**（重要）：
 *   它们不走 `session/control`，而是走网关 `$events` 流的 waterfall 帧
 *   （见本文件第 7 节）。把这条事实写进注释，是因为
 *   `session/control` 的归属能力恰好叫 `approvals`，
 *   很容易让人以为审批从这里来——实测不是。
 */
export function readControlFrame(value: Object): ControlFrame {
  const type: string = readString(value, 'type');
  const frame: ControlFrame = {
    type: type,
    baseline: undefined,
    sessionId: '',
    items: emptyQueuedItems(),
    jobs: emptyJobs(),
    key: '',
    value: undefined,
    seq: 0
  };
  if (type === ControlFrameType.BASELINE) {
    const raw: Object | undefined = getRecord(value, 'value');
    if (raw !== undefined) {
      frame.baseline = {
        queues: bagOf(raw, 'queues'),
        jobs: bagOf(raw, 'jobs'),
        projections: bagOf(raw, 'projections')
      };
    }
    return frame;
  }
  if (type === ControlFrameType.PROJECTION) {
    frame.sessionId = readString(value, 'sessionId');
    frame.key = readString(value, 'key');
    frame.value = getField(value, 'value');
    frame.seq = readNumber(value, 'seq');
    return frame;
  }
  if (type === ControlFrameType.QUEUE) {
    frame.sessionId = readString(value, 'sessionId');
    frame.items = readQueuedItems(value);
    return frame;
  }
  if (type === ControlFrameType.JOBS) {
    frame.sessionId = readString(value, 'sessionId');
    frame.jobs = readJobs(value);
    return frame;
  }
  return frame;
}

function readQueuedItems(value: Object): SessionQueuedItem[] {
  const out: SessionQueuedItem[] = [];
  const raw: Object[] | undefined = getArray(value, 'items');
  if (raw === undefined) {
    return out;
  }
  for (let i = 0; i < raw.length; i++) {
    const item: Object = raw[i];
    if (!isRecord(item)) {
      continue;
    }
    const id: string | undefined = getString(item, 'id');
    if (id === undefined || id.length === 0) {
      continue;
    }
    const message: Object | undefined = getRecord(item, 'message');
    out.push({
      id: id,
      placement: readString(item, 'placement'),
      rpcId: optionalString(item, 'rpcId'),
      message: message !== undefined ? message : emptyBagObject()
    });
  }
  return out;
}

function readJobs(value: Object): SessionJob[] {
  const out: SessionJob[] = [];
  const raw: Object[] | undefined = getArray(value, 'jobs');
  if (raw === undefined) {
    return out;
  }
  for (let i = 0; i < raw.length; i++) {
    const job: Object = raw[i];
    if (!isRecord(job)) {
      continue;
    }
    const id: string | undefined = getString(job, 'id');
    if (id === undefined || id.length === 0) {
      continue;
    }
    out.push({
      id: id,
      kind: readString(job, 'kind'),
      label: readString(job, 'label'),
      status: readString(job, 'status'),
      detail: optionalString(job, 'detail'),
      startedAt: readNumber(job, 'startedAt'),
      finishedAt: optionalNumber(job, 'finishedAt')
    });
  }
  return out;
}

// ═════════════════════════ 7. 网关 $events waterfall：审批与提问 ═════════════════════════

/**
 * waterfall 事件名（审批 / 提问）。
 *
 * **不再在本文件写字面量，改为从 `dshcompat` 转出。**
 * 这两个名字是上游事实，唯一落点必须是 `dshcompat/RemoteEvents.ets`
 * （`WATERFALL_APPROVAL` / `WATERFALL_QUESTION`，含完整白名单与依据出处）。
 * 本文件原先各自复制了一份字面量，等于在「唯一事实落点」之外又开了一处——
 * 上游改名时必然漏改一处。架构门禁 `tools/arch-check.mjs` 会拒绝这类复制。
 *
 * 保留这两个导出名是为了不破坏既有调用方；它们现在只是别名。
 */
export { WATERFALL_APPROVAL as APPROVAL_REQUEST_EVENT, WATERFALL_QUESTION as USER_QUESTIONS_REQUEST_EVENT } from 'dshcompat';

/**
 * 一条 waterfall 帧。
 *
 * 实测字段：`{type:'waterfall', event, eventId, agentId, request}`。
 * `eventId` 是**回送结果时的关联键**，`clientId` 则由 `$events` 流的 `ready` 帧给出——
 * 两者一起构成 `$events/result` 的定位参数。
 */
export interface WaterfallFrame {
  type: string;
  /** 事件名（`approval/request` / `user-questions/request` / …） */
  event: string;
  eventId: string;
  agentId: string;
  request: Object;
}

/** 判定是否为 waterfall 帧（非 waterfall 的（如 `emit`/`ready`/`cancel`）交给上层忽略）。 */
export function isWaterfallFrame(value: Object): boolean {
  return readString(value, 'type') === 'waterfall';
}

/** 投影一条 waterfall 帧；字段不全（缺 eventId）时返回 undefined，避免发出无法关联的结果。 */
export function readWaterfallFrame(value: Object): WaterfallFrame | undefined {
  if (!isWaterfallFrame(value)) {
    return undefined;
  }
  const eventId: string = readString(value, 'eventId');
  if (eventId.length === 0) {
    return undefined;
  }
  const request: Object | undefined = getRecord(value, 'request');
  return {
    type: 'waterfall',
    event: readString(value, 'event'),
    eventId: eventId,
    agentId: readString(value, 'agentId'),
    request: request !== undefined ? request : emptyBagObject()
  };
}

/** 审批请求载荷（实测：`{agent, toolName, callId?, reason?}`）。 */
export interface ApprovalRequestPayload {
  /** Agent 身份（线形上是不透明对象，本层不解释） */
  agent: Object;
  toolName: string;
  callId?: string;
  reason?: string;
}

/** 投影审批请求载荷。`toolName` 是唯一必填的业务字段（缺它 UI 无法说明「在批准什么」）。 */
export function projectApprovalRequest(request: Object): ApprovalRequestPayload | undefined {
  const toolName: string | undefined = getString(request, 'toolName');
  if (toolName === undefined || toolName.length === 0) {
    return undefined;
  }
  const agent: Object | undefined = getRecord(request, 'agent');
  return {
    agent: agent !== undefined ? agent : emptyBagObject(),
    toolName: toolName,
    callId: optionalString(request, 'callId'),
    reason: optionalString(request, 'reason')
  };
}

/** 审批结果词表（实测的**闭集**，四个值，没有第五个）。 */
export enum ApprovalOutcome {
  /** 只批准这一次 */
  ALLOWED_ONCE = 'allowed-once',
  /** 明确拒绝 */
  REJECTED = 'rejected',
  /** 请求已被撤回 */
  CANCELLED = 'cancelled',
  /** 没有可用的答复者（**fail closed**：视为拒绝） */
  UNAVAILABLE = 'unavailable'
}

/** 审批卡上的三选（产品层词汇，与线形词表刻意分开）。 */
export enum ApprovalDecision {
  /** 仅本次允许 */
  ALLOW_ONCE = 'allow-once',
  /** 拒绝 */
  DENY = 'deny',
  /** 总是允许 */
  ALWAYS = 'always'
}

/**
 * 产品决策 → 线形结果。
 *
 * ⚠ `取舍`（**产品决策，需要确认，不许静默糊过去**）：
 *   上游的结果词表是 `'allowed-once' | 'rejected' | 'cancelled' | 'unavailable'`，
 *   **没有 `'allow-always'`**（也不接受把 `'always'` 当值发出去）。
 *   因此 UI 上的「总是允许」在本线协议里**无处表达**，只能落成 `allowed-once`。
 *   后果必须说清楚：
 *     - 若 UI 保留「总是允许」按钮，那它**只能是纯客户端行为**——
 *       把该工具名记进本地白名单，后续同工具的审批在本端自动回答「允许一次」。
 *       换了设备、清了数据、或另一个客户端在答，就都不生效。
 *     - 更诚实的做法是**去掉这个按钮**，避免用户以为「Host 记住了」。
 *   本文件按最保守的方式映射（`always → allowed-once`），
 *   并提供 `decisionIsClientSideOnly()` 让 UI 能显式提示这一点。
 *   最终保留哪个形态属产品决策，此处只把事实与代价钉在代码里。
 */
export function approvalOutcomeFor(decision: ApprovalDecision): ApprovalOutcome {
  if (decision === ApprovalDecision.DENY) {
    return ApprovalOutcome.REJECTED;
  }
  return ApprovalOutcome.ALLOWED_ONCE;
}

/** 该决策是否只在客户端生效（见 `approvalOutcomeFor()` 的取舍说明）。 */
export function decisionIsClientSideOnly(decision: ApprovalDecision): boolean {
  return decision === ApprovalDecision.ALWAYS;
}

/** 审批答复值（`allowed-once` 只需要回一个词）。 */
export interface ApprovalAnswerValue {
  outcome: string;
}

/** 构造审批答复值。 */
export function approvalAnswer(decision: ApprovalDecision): ApprovalAnswerValue {
  return { outcome: approvalOutcomeFor(decision) };
}

// ── 提问 ──

/** 一个候选项。 */
export interface AskUserQuestionOption {
  label: string;
  description?: string;
}

/** 提问的呈现意图：`plan-review` 表示「这是待批准的方案」，`approve` 指向表示同意的那一项。 */
export interface AskUserQuestionIntent {
  kind: string;
  approve: string;
}

/** 一条提问（实测字段逐字对应）。 */
export interface AskUserQuestionItem {
  id: string;
  question: string;
  detail?: string;
  header?: string;
  options?: AskUserQuestionOption[];
  multiSelect?: boolean;
  intent?: AskUserQuestionIntent;
}

/** 提问请求载荷。 */
export interface AskUserQuestionRequest {
  questions: AskUserQuestionItem[];
  agent?: Object;
}

/**
 * 投影提问请求载荷（跳过无 `id` 的条目：没有 id 就无法把答案对回去）。
 */
export function projectAskUserQuestionRequest(request: Object): AskUserQuestionRequest | undefined {
  const raw: Object[] | undefined = getArray(request, 'questions');
  if (raw === undefined) {
    return undefined;
  }
  const questions: AskUserQuestionItem[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item: Object = raw[i];
    if (!isRecord(item)) {
      continue;
    }
    const id: string | undefined = getString(item, 'id');
    if (id === undefined || id.length === 0) {
      continue;
    }
    questions.push({
      id: id,
      question: readString(item, 'question'),
      detail: optionalString(item, 'detail'),
      header: optionalString(item, 'header'),
      options: readOptions(item),
      multiSelect: optionalBoolean(item, 'multiSelect'),
      intent: readIntent(item)
    });
  }
  const agent: Object | undefined = getRecord(request, 'agent');
  const out: AskUserQuestionRequest = { questions: questions };
  if (agent !== undefined) {
    out.agent = agent;
  }  return out;
}

function readOptions(item: Object): AskUserQuestionOption[] | undefined {
  const raw: Object[] | undefined = getArray(item, 'options');
  if (raw === undefined) {
    return undefined;
  }
  const out: AskUserQuestionOption[] = [];
  for (let i = 0; i < raw.length; i++) {
    const option: Object = raw[i];
    if (!isRecord(option)) {
      continue;
    }
    const label: string | undefined = getString(option, 'label');
    if (label === undefined) {
      continue;
    }
    const entry: AskUserQuestionOption = { label: label };
    const description: string | undefined = getString(option, 'description');
    if (description !== undefined) {
      entry.description = description;
    }
    out.push(entry);
  }
  return out;
}

function readIntent(item: Object): AskUserQuestionIntent | undefined {
  const raw: Object | undefined = getRecord(item, 'intent');
  if (raw === undefined) {
    return undefined;
  }
  const kind: string | undefined = getString(raw, 'kind');
  if (kind === undefined) {
    return undefined;
  }
  return { kind: kind, approve: readString(raw, 'approve') };
}

/** 一条答案（实测：`{id, selected: string[], custom?}`）。 */
export interface AskUserQuestionAnswerItem {
  id: string;
  /** 选中的**选项标签**（不是下标）；多选时可与 `custom` 并存 */
  selected: string[];
  /** 自由文本「其他」答案 */
  custom?: string;
}

/** 提问答复值（实测：`{answers: [...]}`）。 */
export interface AskUserQuestionAnswer {
  answers: AskUserQuestionAnswerItem[];
}

/** 构造一条答案。 */
export function questionAnswerItem(id: string, selected: string[],
  custom: string): AskUserQuestionAnswerItem {
  const item: AskUserQuestionAnswerItem = { id: id, selected: selected };
  if (custom.length > 0) {
    item.custom = custom;
  }
  return item;
}

/** 构造提问答复值。 */
export function questionAnswer(answers: AskUserQuestionAnswerItem[]): AskUserQuestionAnswer {
  return { answers: answers };
}

// ═════════════════════════ 8. $events/result 回送 ═════════════════════════

/** 回送错误（实测：`{name, message, code?, details?}`）。 */
export interface WireError {
  name: string;
  message: string;
  code?: string;
  details?: Object;
}

/** `kind='result'` 的结果值（审批回一个词，提问回一个答案对象）。 */
export interface OutcomeResult {
  value?: Object;
}

/** `kind='rejected'` 的载荷。 */
export interface OutcomeRejected {
  error: WireError;
}

/**
 * 回送参数（实测：`{clientId, eventId, outcome}`；`outcome` 三选一）。
 *
 * 三种 outcome 的含义（照上游语义）：
 *   - `{kind:'next'}`：**把决定权交回 waterfall 链上的下一个答复者**。
 *     这是我们**选择不处理**某请求时的正确回应——
 *     例如宿主自己有自动批准钩子，或另一个客户端更该回答（如方案评审）。
 *     绝不能为了「让流程往下走」而回一个假结果：回假结果等于我们**代替用户批准**了，
 *     这是权限问题，不是便利性问题。
 *   - `{kind:'result', value}`：我们认领了这个请求，附上回答。
 *   - `{kind:'rejected', error}`：我们认领了但处理失败（异常路径）。
 */
export interface EventResultArgs {
  clientId: string;
  eventId: string;
  outcome: Object;
}

/** 构造 `{kind:'next'}` —— 交回链上的下一个答复者（**我们不做决定**）。 */
export function outcomeNext(): Object {
  const outcome: Record<string, Object> = { 'kind': 'next' };
  return outcome as Object;
}

/** 构造 `{kind:'result', value}`。`value` 为 undefined 时不带 `value` 字段。 */
export function outcomeResult(value: Object | undefined): Object {
  const outcome: Record<string, Object> = { 'kind': 'result' };
  if (value !== undefined) {
    outcome['value'] = value;
  }
  return outcome as Object;
}

/** 构造 `{kind:'rejected', error}`。 */
export function outcomeRejected(error: WireError): Object {
  const outcome: Record<string, Object> = { 'kind': 'rejected', 'error': error };
  return outcome as Object;
}

/**
 * 构造 `$events/result` 的 args。
 *
 * **该端点不在业务端点上表内**（它是网关内部端点，不是 `ns/method` 形式的业务端点），
 * 因此 `dshcompat.argsFor()` 对它返回 `undefined` —— 这是**正确行为**，不要试图绕开。
 * 实测依据：上游 `dsh-api-gateway` 的 `dispatchRpc` 直接调用
 * `parseRemoteEventResult(payload.args)`，即 **args 本身就是** `{clientId, eventId, outcome}`，
 * **没有** `request` / `_request` 包装层。
 * 因此这里直接构造扁平对象，不经任何形态包装。
 *
 * endpoint 常量取自 `connection` 的 `EVENTS_RESULT_ENDPOINT`（连接层已导出，本文件不重复定义）。
 */
export function eventResultArgs(clientId: string, eventId: string, outcome: Object): EventResultArgs {
  return { clientId: clientId, eventId: eventId, outcome: outcome };
}

/** `$events/result` 的端点（供连接层直接调用）。 */
export function eventResultEndpoint(): string {
  return EVENTS_RESULT_ENDPOINT;
}

// ═════════════════════════ 9. 附件上传（本机文件 → filePart 所需回执） ═════════════════════════

/**
 * `fileUploads/upload` 的端点（用于把本机文件换成 `filePart()` 所需的不透明回执）。
 *
 * 参数形态是 `ArgsShape.NAMED`（具名参数 `agent` + `request`），
 * 因此下面的构造器返回的 body **不含任何包装层**，由 `argsFor()` 原样透传。
 */
export function fileUploadEndpoint(): string {
  return FILE_UPLOAD_ENDPOINT;
}

/**
 * 一次上传请求（上游 `EncodedFileUploadRequest`）。
 *
 * 已确认（`@deepseek-ai/dsh-client-file-upload/lib/types/types.d.ts`）：
 *   `{data: string, name?: string}`，其中 `data` 是文件字节的规范 base64。
 * `data` 内联在 RPC 里；另有一条原始字节 HTTP 路由
 * `/api/session/uploadFileBinary`，本文件不使用（我们走 RPC 面）。
 */
export interface FileUploadRequest {
  /** 文件字节的规范 base64 编码（不含 `data:` 前缀） */
  data: string;
  /** 展示名；Host 会把它消毒成存储用的叶子名（**永远不会**当路径解释） */
  name?: string;
}

/** 文件附件引用（上游 `FileAttachmentRef`）。 */
export interface FileAttachmentRefValue {
  /** 内容寻址 id：**就是这些字节的 sha256**，不是路径也不是带授权的 URL */
  attachmentId: string;
  /** 消毒后的展示文件名 */
  name: string;
  /** 精确字节数 */
  bytes: number;
}

/** 上传成功后的回执（上游 `FileUploadValue`）。 */
export interface FileUploadValue {
  /**
   * 不透明回执 id。
   * 上游注释：**只在接收它的 Agent 作用域内有效**——
   * 因此它既不能跨会话复用，也不能缓存起来给下次用（见 `filePart()` 的说明）。
   */
  receiptId: string;
  file: FileAttachmentRefValue;
}

/**
 * 构造 `fileUploads/upload` 的 args 载荷。
 *
 * 返回 `Object | undefined`（endpoint 不在上表时为 undefined，调用方降级）。
 * 该端点具名参数是 `agent` + `request`，因此 body 直接给出这两个键，
 * 由 `argsFor()` 按上表判定形态（NAMED ⇒ 原样透传）。
 */
export function fileUploadPayload(agent: Object, data: string, name: string): Object | undefined {
  const request: FileUploadRequest = { data: data };
  if (name.length > 0) {
    request.name = name;
  }
  const body: Record<string, Object> = { 'agent': agent, 'request': request };
  return argsFor(FILE_UPLOAD_ENDPOINT, body as Object);
}

/**
 * 投影上传回执。
 *
 * 收窄策略：`receiptId` 缺失即视为失败（返回 undefined）——
 * 没有回执就没法构造 `filePart()`，静默返回半成品只会让 prompt 在更远处失败。
 */
export function projectFileUpload(value: Object | undefined): FileUploadValue | undefined {
  if (value === undefined) {
    return undefined;
  }
  const receiptId: string | undefined = getString(value, 'receiptId');
  if (receiptId === undefined || receiptId.length === 0) {
    return undefined;
  }
  const file: Object | undefined = getRecord(value, 'file');
  const ref: FileAttachmentRefValue = {
    attachmentId: file !== undefined ? readString(file, 'attachmentId') : '',
    name: file !== undefined ? readString(file, 'name') : '',
    bytes: file !== undefined ? readNumber(file, 'bytes') : 0
  };
  return { receiptId: receiptId, file: ref };
}

// ═════════════════════════ 10. 取值助手 ═════════════════════════

/** 读字符串，缺失返回空串（用于「总是要有值」的展示字段）。 */
function readString(source: Object | null | undefined, key: string): string {
  const value: string | undefined = getString(source, key);
  return value !== undefined ? value : '';
}

/** 读字符串；缺失返回 undefined（用于「缺失与空串语义不同」的字段）。 */
function optionalString(source: Object | null | undefined, key: string): string | undefined {
  return getString(source, key);
}

/** 读数字，缺失返回 0（时间戳/序号的展示兜底）。 */
function readNumber(source: Object | null | undefined, key: string): number {
  const value: number | undefined = getNumber(source, key);
  return value !== undefined ? value : 0;
}

/** 读数字；缺失返回 undefined。 */
function optionalNumber(source: Object | null | undefined, key: string): number | undefined {
  return getNumber(source, key);
}

/** 读布尔，缺失返回 false（`running`/`blank` 这类默认「否」最安全）。 */
function readBoolean(source: Object | null | undefined, key: string): boolean {
  const value: Object | undefined = getField(source, key);
  return typeof value === 'boolean' ? value as boolean : false;
}

function optionalBoolean(source: Object | null | undefined, key: string): boolean | undefined {
  const value: Object | undefined = getField(source, key);
  return typeof value === 'boolean' ? value as boolean : undefined;
}

/** 读对象字段（缺失返回空袋，避免调用方到处判 undefined）。 */
function bagOf(source: Object | null | undefined, key: string): JsonBag {
  const value: Object | undefined = getRecord(source, key);
  return value !== undefined ? value as JsonBag : emptyBag();
}

/**
 * 空字符串键袋。
 *
 * 为什么要写成函数而不是直接写 `{}`：
 *   ArkTS 的 `arkts-no-untyped-obj-literals` 禁止**无法对应到已声明类型**的字面量，
 *   而三元表达式里的 `x !== undefined ? x : {}` 中的 `{}` 正好落在这个禁区
 *   （编译器不会用「另一分支的类型」去推断它）。
 *   因此所有空值都必须由**显式标注返回类型**的工厂函数产出——
 *   这既绕开了限制，也把「空值的类型」写死在了一处。
 */
function emptyBag(): JsonBag {
  const bag: JsonBag = {};
  return bag;
}

/** 空的对象载荷（`wire` 层里 `data` / `request` / `message` 等字段的兜底值）。 */
function emptyBagObject(): JsonBag {
  const bag: JsonBag = {};
  return bag;
}

/** 空的投影提示（快照缺 `projections` 时使用；`asOfSeq = 0` 表示「游标未知」）。 */
function emptyProjectionHints(): ProjectionHints {
  return { asOfSeq: 0, values: emptyBag() };
}

/** 空的排队项数组（同样是为了避开无类型数组字面量）。 */
function emptyQueuedItems(): SessionQueuedItem[] {
  const list: SessionQueuedItem[] = [];
  return list;
}

/** 空的任务数组。 */
function emptyJobs(): SessionJob[] {
  const list: SessionJob[] = [];
  return list;
}
