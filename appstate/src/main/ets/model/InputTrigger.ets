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
  /** 查询词（`@` 或 `/` 之后的部分；可能为空串） */
  query: string;
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
  return { kind: TriggerKind.COMMAND, start: lead, end: text.length, query: rest };
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
  const after: string = text.substring(at + 1);
  if (after.indexOf(' ') >= 0 || after.indexOf('\n') >= 0) {
    return undefined;
  }
  // `@` 出现在行首之外也没关系：只有"它之后没有空白"才说明它正在被输入
  if (at > 0 && text.charAt(at - 1) === '\\') {
    // 转义过的 `@` 不是触发词（用户就是要打一个 @ 字符）
    return undefined;
  }
  return { kind: TriggerKind.REFERENCE, start: at, end: text.length, query: after };
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
