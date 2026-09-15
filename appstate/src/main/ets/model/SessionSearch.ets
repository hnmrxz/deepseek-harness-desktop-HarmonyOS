/**
 * 会话搜索（官方 `dsh-client-ui-sidebar` 的 search / `dsh-client-ui-workspace` 的扁平结果行）。
 *
 * ## 官方语义（读的是 `@deepseek-ai/dsh-client-ui-workspace` 的客户端源码）
 *
 * 官方把搜索做成**一条扁平结果列表**，每行 = 标题 + 工作区上下文 +（可选）**内容片段**；
 * 片段来自 Host 的**内容搜索**（`session/search`，按字面量搜会话内容，不是正则），
 * 标题命中由客户端本地算。两路**合并**后渲染，所以"按名字找"和"按内容找"是同一个入口。
 *   · 结果上限 20（`SESSION_SEARCH_RESULT_LIMIT`）
 *   · 片段上限 240 code points（上游截，我们不二次截断，免得多截一次）
 *   · **标题为空的行不参与本地匹配**（官方注释：blank rows are query-excluded）——
 *     否则一个空标题能匹配任何查询
 *
 * ## 为什么是纯函数
 *
 * "哪条算命中、谁排在前面、重复怎么去重、上限怎么算"是**判定**，不是渲染。
 * 放这里之后能在本机被 fixture 直接钉住（含"Host 没回内容命中时只按标题"这条降级路径）。
 */

import { workspaceNameOf } from './SessionContext';

/**
 * 本地会话行的**结构子集**：搜索只用 `id` / `title` / `cwd` 三个字段。
 *
 * 【为什么不 import `SessionListItem`】那个模块（`model/SessionList`）会拉进 `connection` 与
 * `dshcompat` ⇒ fixture 编译器（只摊平纯逻辑文件）加载不了本文件，这一层就**测不到**了。
 * 而 ArkTS **禁止结构化类型**（E364：形状相同也不能互赋）⇒ 调用点必须**显式**把会话行
 * 拷成这三字段（`hub` 里那几行循环就是这么来的），不能直接把 `SessionListItem[]` 传进来。
 */
export interface SessionSearchLocal {
  id: string;
  title: string;
  cwd: string;
}

/**
 * `session/search` 的请求内层（`docs/11-请求载荷契约.md`：`args = { request: { query } }`，
 * 包装由 `dshcompat.argsFor` 按 `ArgsShape.REQUEST` 做）。单独声明类型是 ArkTS 的要求：
 * **对象字面量必须对应显式声明的类型**（`arkts-no-untyped-obj-literals`）。
 */
export interface SessionSearchRequest {
  /** 字面量内容查询（**不是正则**：上游按字面量搜） */
  query: string;
}

/** Host 内容搜索的一条命中（`session/search` 回复的 item：只有 id 与片段） */
export interface SessionSearchHit {
  sessionId: string;
  snippet: string;
}

/** 合并后的一条扁平结果（界面直接渲染它） */
export interface SessionSearchRow {
  sessionId: string;
  /** 标题；本地查不到这个会话时用兜底文案（不编标题） */
  title: string;
  /** 工作区名（取会话自己 `cwd` 的末两段；没有 cwd 就是空串 ⇒ 界面不画这一段） */
  workspace: string;
  /** 内容片段（Host 给的原文；没有内容命中时是空串） */
  snippet: string;
}

/** 与上游 `SESSION_SEARCH_RESULT_LIMIT` 对齐：一次最多给用户看这么多条 */
export const SESSION_SEARCH_LIMIT = 20;

/** 本地查不到该会话时的标题兜底（与 `Notify.UNTITLED_SESSION` 同一套措辞，未命名就说未命名） */
const UNTITLED: string = '未命名会话';

/**
 * 合并「Host 内容命中」与「本地标题命中」成一条扁平结果列表。
 *
 * 顺序是**有讲究的**：Host 的内容命中排前面（它已经排过序：内容匹配比标题匹配更贵也更准），
 * 本地标题命中补在后面。同一会话在两路都出现时**只留一条**（并保留内容片段）。
 */
export function mergeSessionSearch(local: SessionSearchLocal[], host: SessionSearchHit[],
  query: string): SessionSearchRow[] {
  const q: string = query.trim().toLowerCase();
  if (q.length === 0) {
    return [];
  }
  const byId: Map<string, SessionSearchLocal> = new Map<string, SessionSearchLocal>();
  for (let i = 0; i < local.length; i++) {
    byId.set(local[i].id, local[i]);
  }
  const out: SessionSearchRow[] = [];
  const seen: Set<string> = new Set<string>();

  // ① Host 的内容命中：**不因"本地没有这条会话"而丢弃** —— 内容确实命中了，
  //    大不了标题用兜底文案、工作区留空（界面据此不画那一段）。
  for (let i = 0; i < host.length; i++) {
    const hit: SessionSearchHit = host[i];
    if (hit.sessionId.length === 0 || seen.has(hit.sessionId)) {
      continue;
    }
    if (out.length >= SESSION_SEARCH_LIMIT) {
      return out;
    }
    const item: SessionSearchLocal | undefined = byId.get(hit.sessionId);
    out.push({
      sessionId: hit.sessionId,
      title: rowTitle(item),
      workspace: item === undefined ? '' : workspaceNameOf(item.cwd),
      snippet: hit.snippet,
    });
    seen.add(hit.sessionId);
  }

  // ② 本地标题命中（大小写不敏感的子串；**标题为空的跳过**，否则空标题匹配一切）
  for (let i = 0; i < local.length; i++) {
    const item: SessionSearchLocal = local[i];
    if (out.length >= SESSION_SEARCH_LIMIT) {
      break;
    }
    const title: string = item.title.trim();
    if (title.length === 0 || seen.has(item.id)) {
      continue;
    }
    if (!title.toLowerCase().includes(q)) {
      continue;
    }
    out.push({
      sessionId: item.id,
      title: title,
      workspace: workspaceNameOf(item.cwd),
      snippet: '',
    });
    seen.add(item.id);
  }
  return out;
}

/** 结果行的标题：本地有就用自己的，没有就用兜底（不编造） */
function rowTitle(item: SessionSearchLocal | undefined): string {
  if (item === undefined) {
    return UNTITLED;
  }
  const title: string = item.title.trim();
  return title.length === 0 ? UNTITLED : title;
}

/**
 * Host 内容搜索不可用时（老 Host 没这个端点、或能力探测说没有）给用户的那句话。
 *
 * 【为什么要专门一句】这条降级**不是错误**：按标题找会话仍然可用，用户看到的列表是
 * "标题匹配"而不是"标题 + 内容"。不说清的话，用户会以为"搜不到就是没有"。
 */
export function localOnlySearchNote(): string {
  return `当前 Host 未提供内容搜索（\`session/search\`），下面是**按标题匹配**的结果。`;
}
