/**
 * 输入触发管线：`@` 引用与 `/` 命令的**词法**（P7-14，对齐官方 `dsh-client-ui-input-trigger`）。
 *
 * ## 它修正了什么
 *
 * 视图此前把"插入候选"写成 `draft + insert + ' '`（追加到末尾）。于是用户敲了 `@src/fo`
 * 再点候选，输入框里得到的是 **`@src/fo@src/foo.ts `** —— 半截查询词留在了正文里，
 * 而且它长得像一条引用：Host 拿到这条提示词会去解析一个不存在的 `@src/fo`。
 * 官方不是这样：输入触发管线**替换当前 token**（`inputTriggers` 的 `slash/input-consume-token`
 * 带 `{kind:'span', span}` / `{kind:'bare-token', token}`），而不是往后面接。
 *
 * 所以这里把两件事从视图里搬出来，做成可断言的纯函数：
 *   1. **触发词的识别**（哪一段是"正在输入的 token"、查询词是什么）；
 *   2. **选中候选后的替换**（替换那一段，而不是追加）。
 *
 * ## 与官方对齐的两条细节
 *
 * · **文件引用的引号语法**（官方 `formatFileMention`）：路径含空白时写 `@"path"`；
 *   目录写成 `@"dir/`——**引号故意不闭合**，好让补全能继续往下钻。因此目录引用后面
 *   **不补空格**（补了就把未闭合的引号关在外面，下一次补全接不上）。
 * · **命令与引用的判别**：以 `/` 开头且尚无空白 ⇒ 命令；否则看"行内最后一个 `@` 之后无空白" ⇒ 引用。
 *   两者同时成立时命令优先（与视图既有行为一致）。
 *
 * 纯逻辑：不 import 任何 kit，可被 `tools/check-layout-fixtures.mjs` 直接钉住。
 */

/** 触发词种类 */
export enum TriggerKind {
  /** `@` 引用（文件 / 会话） */
  REFERENCE = 'reference',
  /** `/` 命令 */
  COMMAND = 'command'
}

/** 正在输入的触发词（`start`/`end` 是它在草稿里的**区间**，选中候选时替换这一段） */
export interface TriggerToken {
  /** 种类（`TriggerKind` 的字符串值） */
  kind: string;
  /** 起始下标（含 `@` 或 `/`） */
  start: number;
  /** 结束下标（**不含**；即草稿末尾或 token 末尾） */
  end: number;
  /** 查询词（`@` 或 `/` 之后的部分；可能为空串；**引号已剥掉**，见下面的 `quoted`） */
  query: string;
  /**
   * 是不是**带引号的引用写法**（`@"…"`，官方给候选源的那个 `quoted` 标志）。
   *
   * 【为什么需要这个标志】引号写法存在的唯一理由是**路径里有空格**：
   * 官方 `formatFileMention` 就是"路径含空白 ⇒ 写 `@"path"`（目录故意不闭合引号）"。
   * 而引号里的空格**不是**"停止输入"的信号——不带引号时，空白表示这段话写完了（面板该收），
   * 带引号时它只是路径的一部分。两者混为一谈会让**含空格的路径永远补全不了**（P9-5 修的正是这条）。
   */
  quoted: boolean;
}

/** 草稿是否"以命令开头且还没敲参数"（命令面板的条件） */
function commandTokenOf(text: string): TriggerToken | undefined {
  // 前导空白不算内容，但**下标要落在原文上**（用户可能先敲了空格）
  const lead: number = text.length - text.trimStart().length;
  if (text.length === 0 || text.charAt(lead) !== '/') {
    return undefined;
  }
  const rest: string = text.substring(lead + 1);
  if (rest.indexOf(' ') >= 0 || rest.indexOf('\n') >= 0) {
    return undefined;
  }
  return { kind: TriggerKind.COMMAND, start: lead, end: text.length, query: rest, quoted: false };
}

/**
 * 识别当前正在输入的触发词（没有就返回 undefined）。
 *
 * 判据与视图此前一致（只是搬进了可测的纯函数）：
 *   · 命令：去掉前导空白后以 `/` 开头，且**还没有空白**（一敲空格就说明在写参数了，面板该收）；
 *   · 引用：行内**最后一个 `@`**，且它之后没有空白/换行（`@ a` 不是引用，`look at @src/a` 是）。
 */
export function detectTrigger(text: string): TriggerToken | undefined {
  const command: TriggerToken | undefined = commandTokenOf(text);
  if (command !== undefined) {
    return command;
  }
  const at: number = text.lastIndexOf('@');
  if (at < 0) {
    return undefined;
  }
  if (at > 0 && text.charAt(at - 1) === '\\') {
    // 转义过的 `@` 不是触发词（用户就是要打一个 @ 字符）
    return undefined;
  }
  const after: string = text.substring(at + 1);
  if (after.startsWith('"')) {
    /*
     * ── 引号形态（`@"…"`）：官方语法里存在，而且**只为含空格的路径存在** ──
     *
     * 官方的 `formatFileMention` 逐字：路径没有空白 ⇒ `@path`；**含空白** ⇒
     * 文件写 `@"path"`、**目录写 `@"path/`（故意不闭合引号，留给下一次补全继续钻）**。
     * 所以 `"` 之后的空白是路径的一部分，不该像不带引号那样"一敲空格就收面板"。
     *
     * 闭合的引号（用户自己敲完了）算 token 的结尾，这样"选中即替换"不会把尾巴剩下。
     */
    const close: number = after.indexOf('"', 1);
    if (close >= 0) {
      return {
        kind: TriggerKind.REFERENCE,
        start: at,
        end: at + 1 + close + 1,
        query: after.substring(1, close),
        quoted: true
      };
    }
    return {
      kind: TriggerKind.REFERENCE,
      start: at,
      end: text.length,
      query: after.substring(1),
      quoted: true
    };
  }
  if (after.indexOf(' ') >= 0 || after.indexOf('\n') >= 0) {
    return undefined;
  }
  // `@` 出现在行首之外也没关系：只有"它之后没有空白"才说明它正在被输入
  return { kind: TriggerKind.REFERENCE, start: at, end: text.length, query: after, quoted: false };
}

/**
 * 选中候选后要不要补一个尾随空格。
 *
 * 【为什么目录引用不补】官方目录引用的形态是 `@"dir/`（引号**未闭合**，留给下一次补全继续钻）。
 * 后面补空格会得到一个"引号没关、后面还跟着空格"的坏 token，下一次补全接不上。
 */
export function needsTrailingSpace(insert: string): boolean {
  if (insert.length === 0) {
    return false;
  }
  const openQuoteOnly: boolean = insert.charAt(0) === '@' && insert.charAt(1) === '"'
    && insert.charAt(insert.length - 1) !== '"';
  return !openQuoteOnly;
}

/**
 * 把草稿里的**触发词区间**替换成选中的插入文本。
 *
 * @param draft 当前草稿
 * @param token 触发词（`detectTrigger` 的产物）
 * @param insert 插入文本（文件/会话引用用 Host 给的 `mention`；命令用命令名）
 */
export function applyPick(draft: string, token: TriggerToken, insert: string): string {
  const head: string = draft.substring(0, token.start);
  const tail: string = token.end >= draft.length ? '' : draft.substring(token.end);
  const space: string = needsTrailingSpace(insert) ? ' ' : '';
  return `${head}${insert}${space}${tail}`;
}

/**
 * 没有识别到触发词时的兜底插入（用户先点了按钮、再选候选的情形）。
 *
 * 【为什么兜底也要有空格规则】它同样会走到"引用/命令"两种插入上，
 * 目录引用的未闭合引号问题一样存在。
 */
export function appendPick(draft: string, insert: string): string {
  const sep: string = draft.length > 0 && draft.charAt(draft.length - 1) !== ' ' ? ' ' : '';
  const space: string = needsTrailingSpace(insert) ? ' ' : '';
  return `${draft}${sep}${insert}${space}`;
}

/* ───────────────────────── 选中一条斜杠命令之后（P9-4） ───────────────────────── */

/**
 * 这条命令**需要参数**吗。
 *
 * 【判据来自 Host，不是我们猜】官方 `CommandDescriptor` 的形状是
 * `{name, description, input?: {hint, attachments?}}` —— `input` 存在就表示
 * "这条命令接受（并通常需要）一段自由文本"，`hint` 就是给用户看的占位说明。
 * 我们把它投影成 `CommandCandidate.args`（见 `Wire.projectCommands`），
 * 因此"要不要参数"这件事**有权威来源**：`args` 非空即需要。
 *
 * 【为什么不能靠命令名白名单】命令目录由 Host 提供（不同 Host 装的东西不同），
 * 写死 `/feedback` / `/goal` 这些名字等于把 Host 的目录抄一份到客户端——
 * 那份抄件一旦过期，界面上就会出现"明明要参数却被直接执行"的命令。
 */
export function commandNeedsInput(args: string): boolean {
  return args.trim().length > 0;
}

/** 选中命令后的动作：直接执行 */
export const COMMAND_PICK_RUN: string = 'run';
/** 选中命令后的动作：填进输入框让用户补齐参数 */
export const COMMAND_PICK_DRAFT: string = 'draft';

/**
 * 选中一条命令时该做什么。
 *
 * 【为什么需要这条规则（真实缺陷）】命令面板此前**无论命令要不要参数都直接执行**：
 * 选 `/feedback`（Host 的 hint 写着要一段文本）⇒ 直接发给 Host ⇒ 被拒，
 * 界面上出现 Host 那句英文 usage（`Feedback text is required. Usage: /feedback <text>`），
 * 面板关了、输入框空着。官方的做法是给这类命令挂一个 `popupSelect`：
 * **永远不会发出一次"已知不完整"的调用**（`CommandDecoration` 的注释逐字：
 * "the decoration replaces only the bare menu-pick/enter with a popup whose onSelect
 * **typically submits a completed line back through command.execute**"）。
 *
 * 我们没有它的选项来源（那是各业务包自己的协议），于是取**最小且诚实**的等价物：
 * 需要参数的命令 ⇒ 把 `命令 + 空格` 填进输入框（与输入区斜杠菜单**同一条规则**），
 * 并把 Host 给的 hint 显示出来；不需要参数的 ⇒ 照旧直接执行。
 */
export function commandPickAction(args: string): string {
  return commandNeedsInput(args) ? COMMAND_PICK_DRAFT : COMMAND_PICK_RUN;
}

/**
 * 需要参数时填进输入框的文本：`/name `（**末尾一个空格**）。
 *
 * 空格不是装饰：Host 的用法行是 `/feedback <text>`，用户接着打的就是"参数"，
 * 而输入区的补全与 `detectTrigger` 都要求命令名后**恰好**有一处空白才开始算参数
 * （见本文件顶部的词法说明）。
 */
export function commandDraftText(name: string): string {
  const trimmed: string = name.trim();
  return trimmed.length === 0 ? '' : `${trimmed} `;
}

/**
 * 需要参数时的提示文案（出现在输入区上方那条通道里）。
 *
 * 三件事都要说清：① 为什么没执行（这条命令要参数）；② 参数长什么样（Host 的 hint 原话）；
 * ③ 下一步（已填进输入框，补齐后发送）。
 */
export function commandInputNotice(name: string, hint: string): string {
  const trimmed: string = name.trim();
  const what: string = trimmed.length > 0 ? trimmed : '这条命令';
  const expected: string = hint.trim();
  const detail: string = expected.length > 0 ? `参数是「${expected}」。` : '';
  return `${what} 需要参数，没有执行（直接发出去只会被 Host 拒绝）。`
    + `${detail}已经填进输入框，补齐后按发送即可。`;
}

/* ───────────────────────── `@` 引用菜单：钻取、面包屑与行信息（P9-5） ───────────────────────── */

/**
 * 面包屑根（**逐字取官方** `dsh-client-ui-reference` 中文字典的 `crumb.root`）。
 *
 * 官方还有 `time.*` 的六个桶词（`{n}分钟` / `{n}小时` / `{n}天` / `{n}个月` / `{n}年` / `刚刚`）
 * 与 `candidate.noCwd`（`（无工作目录）`），下面的函数用的就是它们。
 */
export const REFERENCE_CRUMB_ROOT: string = '工作区';
/** 候选没有工作目录时显示什么（官方 `candidate.noCwd` 逐字） */
export const REFERENCE_NO_CWD: string = '（无工作目录）';

/**
 * 未命名会话的回落文案（F15）。
 *
 * **与资源串 `app.string.label_unnamed_session` 逐字相同**（本轮把那条资源从
 * `（未命名会话）` 改成了 `未命名会话`——列表里显示成带括号的样子像是"附注"而不是标题）。
 * 两边说的必须是同一句话，否则又会变成"同一件事两套口径"，而 F15/F23 正是这么被抓出来的。
 * 这里不引资源串是因为模型层零依赖（本仓的分层规矩）；代价是这行注释必须一直留着。
 */
const REFERENCE_UNNAMED_SESSION: string = '未命名会话';

/**
 * 一次"钻取"之后用于继续补全的查询词（官方 `onPick` 的 `{text, continue: true}` 那一支）。
 *
 * 【为什么要有这个函数】官方选中**目录**时**不关菜单**：把更深一层的路径写进草稿并
 * `continue: true`，菜单接着列那个目录的内容。我们此前一律 `panel = ''` ⇒
 * 选一个文件夹之后菜单就关了，用户要再点一次 `@`（而那时查询词已经不在补全状态）——
 * "目录可钻取"这件事在界面上等于没有。
 *
 * @returns 当前草稿里 `@`/`@"` token 的查询词；不在引用 token 里时给空串
 */
export function referenceDrillQuery(draft: string): string {
  const token: TriggerToken | undefined = detectTrigger(draft);
  if (token === undefined || token.kind !== TriggerKind.REFERENCE) {
    return '';
  }
  return referenceQueryOf(token.query);
}

/**
 * 查询词的**规范化**：剥掉 `@"` 那个引号。
 *
 * 【官方把引号当成单独的标志】它的候选源签名是 `candidates(session, {query, quoted, drilled, signal})`
 * —— `quoted` 是布尔标志，**`query` 里不含引号**。而本仓的 `detectTrigger` 按词法把引号留在了
 * `query` 里（`@"src/comp` ⇒ query = `"src/comp`）。不剥掉会在两处出错：
 *   ① **发给 Host 的查询词带着引号** ⇒ 路径匹配不上，菜单空着（而带空格的路径**必须**用引号写法，
 *      所以这条正好卡在最需要它的场景上）；
 *   ② 面包屑里会出现 `"src` 这种带引号的段。
 * 已闭合的引号（用户自己敲完了 `@"a b.ts"`）一并剥掉尾部那一个。
 */
export function referenceQueryOf(rawQuery: string): string {
  let out: string = rawQuery;
  if (out.startsWith('"')) {
    out = out.substring(1);
  }
  if (out.endsWith('"') && out.length > 0) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

/**
 * 钻取列表的面包屑（官方 `crumbsFor` 的等价实现）。
 *
 * 官方注释写明了**为什么只有钻取才有面包屑**：
 * > "Only a drill produces one: a path the user typed carries its own context in the draft,
 * > while a drill **replaced the text they were reading with a deeper one and owes them the way back**."
 * 也就是：用户自己敲出来的路径，草稿里看得见上下文；而钻孔是界面替他换了路径，所以要还他"回得去"的感觉。
 *
 * 切法也照官方：取最后一个 `/` 之前的部分按 `/` 分段（空段丢掉），前面补上 `工作区`。
 *
 * @returns 面包屑段（`['工作区', 'src', 'components']`）；不是钻取、或查询词里没有 `/` ⇒ 空数组
 */
export function referenceCrumbs(query: string, drilled: boolean): string[] {
  if (!drilled) {
    return [];
  }
  const slash: number = query.lastIndexOf('/');
  if (slash < 0) {
    return [];
  }
  const parts: string[] = [];
  const segments: string[] = query.substring(0, slash).split('/');
  for (let i = 0; i < segments.length; i++) {
    if (segments[i].length > 0) {
      parts.push(segments[i]);
    }
  }
  return [REFERENCE_CRUMB_ROOT].concat(parts);
}

/**
 * 相对时间的**桶词**（官方 `reference` 命名空间的 `time.*`：`{n}分钟` 这一套）。
 *
 * 【为什么不用 `Present.relativeTime`】那句话是**会话行**的措辞（`3 分钟前` / `2 小时前`）；
 * 而官方给引用菜单单独准备了一套（`3分钟` / `2小时`，没有"前"、没有空格），
 * 并且在自己的字典注释里写明了原因：*"locale-owned copy keeps the words per plugin,
 * while the bucketing they name is the one shared relativeTime in ui-primitives."*
 * 也就是**分桶逻辑共用、措辞各插件自带**。
 *
 * @param unit `now` / `minutes` / `hours` / `days` / `months` / `years`
 * @param n 桶内数量（`now` 时忽略）
 */
export function referenceAgeText(unit: string, n: number): string {
  if (unit === 'minutes') {
    return `${n}分钟`;
  }
  if (unit === 'hours') {
    return `${n}小时`;
  }
  if (unit === 'days') {
    return `${n}天`;
  }
  if (unit === 'months') {
    return `${n}个月`;
  }
  if (unit === 'years') {
    return `${n}年`;
  }
  return '刚刚';
}

/**
 * 一个时间戳 → 引用菜单里的时间文案（与 `Present.relativeTime` **同一套分桶**）。
 *
 * 分桶边界照本仓既有实现（1 分钟 / 1 小时 / 1 天 / 30 天 / 365 天），
 * 只把措辞换成官方引用命名空间那一套。
 */
export function referenceAgeLine(atMs: number, nowMs: number): string {
  if (atMs <= 0) {
    return '';
  }
  const diff: number = nowMs - atMs;
  if (diff < 60 * 1000) {
    return referenceAgeText('now', 0);
  }
  const minute: number = 60 * 1000;
  const hour: number = 60 * minute;
  const day: number = 24 * hour;
  if (diff < hour) {
    return referenceAgeText('minutes', Math.floor(diff / minute));
  }
  if (diff < day) {
    return referenceAgeText('hours', Math.floor(diff / hour));
  }
  if (diff < 30 * day) {
    return referenceAgeText('days', Math.floor(diff / day));
  }
  if (diff < 365 * day) {
    return referenceAgeText('months', Math.floor(diff / (30 * day)));
  }
  return referenceAgeText('years', Math.floor(diff / (365 * day)));
}

/**
 * 文件候选那一行的两段文字（官方 `fileCandidate` 的等价实现）。
 *
 * 官方：`name = basename + (目录 ? '/' : '')`；`description = 未钻取时的父目录`（根目录下不给）。
 * 目录还带 `drill: true`——那是"选中后继续钻"的标记，我们的等价物是 `ReferenceCandidate.kind === 'directory'`。
 */
export function referenceFileRowName(path: string, isDirectory: boolean): string {
  const slash: number = path.lastIndexOf('/');
  const name: string = slash >= 0 ? path.substring(slash + 1) : path;
  const shown: string = name.length > 0 ? name : path;
  return isDirectory ? `${shown}/` : shown;
}

/** 文件候选的父目录（未钻取时显示；根目录下的文件给空串，官方同） */
export function referenceFileRowDetail(path: string, showLocation: boolean): string {
  if (!showLocation) {
    return '';
  }
  const slash: number = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

/**
 * 会话候选那一行的两段文字（官方 `sessionCandidate` 的等价实现）。
 *
 * 官方三条规则：① 会话在当前工作区（`sameWorkspace`）⇒ **不显示位置**（同一处，写了是噪声）；
 * ② 没有 cwd ⇒ 写 `（无工作目录）`（而不是留空，让用户以为界面吞了信息）；
 * ③ 有位置 ⇒ `位置 · 时间`。
 */
export function referenceSessionRowDetail(cwd: string, sameWorkspace: boolean, ageText: string): string {
  const location: string = sameWorkspace ? '' : (cwd.length > 0 ? cwd : REFERENCE_NO_CWD);
  if (location.length === 0) {
    return ageText;
  }
  return ageText.length > 0 ? `${location} · ${ageText}` : location;
}

/**
 * 会话候选那一行的**名字**（F15）。
 *
 * 真机读数：`@` 菜单里的会话候选直接显示 `session-22a1d0f0-e811-4932-afee-ea8a76215dc1`。根因是
 * Host 的 `sessionReferenceResolver/candidates` 对**还没有标题**的会话，`label` 就是 sessionId
 * （已用 fport 取证），而客户端**原样显示**。
 *
 * 判据刻意做窄——**只有"长得就像 sessionId"才回落**：
 * 前缀是 `session-` **且**总长 ≥ 16（真机给的 id 是 UUID 形态，远长于此）。
 * 不做"凡是含横杠就当 id"那种宽判据：那会把用户自己起的名字也吞掉，
 * 而"显示成未命名会话"比"显示成一个真名字"更糟。
 */
export function referenceSessionRowName(label: string): string {
  const looksLikeSessionId: boolean = label.startsWith('session-') && label.length >= 16;
  if (label.length === 0 || looksLikeSessionId) {
    return REFERENCE_UNNAMED_SESSION;
  }
  return label;
}