/**
 * 一个回合**产出的文件**（P7-21，对齐官方 `dsh-client-ui-deliverables`）。
 *
 * ## 官方的规则（`lib/types/client/turn-deliverables.d.ts` 的文档注释，逐字）
 *
 *   > "The source is the arguments of **successful `write`, `edit`, and mutating
 *   > `str_replace_editor` calls**, not the closing prose: **a produced file must be listed
 *   > whether or not the model remembered to name it**. Reads, unsupported tools, malformed
 *   > calls, and failed results contribute nothing. Paths keep **first-seen order** and appear
 *   > **once**, so a file written and then edited in the same turn is one entry."
 *
 * 三件事因此是**规则**：
 *   ① 来源是**工具调用**，不是回答正文里有没有写文件名（"模型记不记得说"不该影响清单）；
 *   ② **只算成功**的写类调用（读、未知工具、畸形参数、失败结果都不算）；
 *   ③ **首次出现顺序 + 去重**（同一回合先写后改只算一条）。
 *
 * ## 我们此前的问题
 *
 * 交付物只有两条来源：`deliverables/presented` 事件（**取决于模型是否上报**）与右栏那份
 * "按条目筛"的清单。也就是说：agent 改了 5 个文件但没上报，用户在界面上**看不到产出了什么**——
 * 只能一条条翻工具卡。这里把它按官方规则**推导**出来。
 *
 * ## 复用而不是重写
 *
 * "这个调用是不是写类、路径是哪个"这件事 `model/ToolDiff.intendedDiffOf()` 已经实现了
 * （逐条对齐官方 `intendedDiff` 的字段与拒绝条件）。这里只用它的结论，不重写一份解析——
 * 两份实现必然走样，而它对"畸形参数 / 缺路径"的收窄判据正是官方那套。
 *
 * 纯逻辑：只依赖 `ToolDiff` 与 `Trajectory`（都是零依赖），可被 fixture 钉住。
 */

import { DiffStat, MAX_DIFF_LINES, diffLines, diffStatOf, intendedDiffOf, ToolDiff } from './ToolDiff';
import { ToolState, TrajectoryItem, TrajectoryKind } from './Trajectory';

/** 一枚产出文件（视图只用这两个字段） */
export interface ProducedFile {
  /** 工作区相对路径（原样，不做归一化——它就是 Host 与工具用的那个字符串） */
  path: string;
  /** 展示名（路径末段） */
  name: string;
  /**
   * 该文件在这回合里的最终增行 / 删行（官方逐文件 `+15 -2`）。
   *
   * 同一个文件被改多次时取**最后一次**对照的结果（"现在它是什么样"），
   * 不是累加（"总共敲了多少"）——累加值由行尾的 `+N −M` 表达。
   */
  added: number;
  removed: number;
}

/** 路径末段（`a/b/c.ts` → `c.ts`；没有分隔符就是它自己） */
export function baseNameOf(path: string): string {
  const slash: number = path.lastIndexOf('/');
  return slash >= 0 ? path.substring(slash + 1) : path;
}

/**
 * 一个回合产出的文件（首次出现顺序、去重）。
 *
 * @param items 该回合的条目（工具条目在过程分组里，见 `Turns.isProcessKind`）
 */
export function producedFilesOf(items: TrajectoryItem[]): ProducedFile[] {
  const out: ProducedFile[] = [];
  const seen: string[] = [];
  for (let i = 0; i < items.length; i++) {
    const item: TrajectoryItem = items[i];
    if (item.kind !== TrajectoryKind.TOOL) {
      continue;
    }
    /*
     * **只算成功的写类调用**（官方："successful … calls"；"failed results contribute nothing"）。
     * `SUCCESS` 是结果帧到达且没报错的取值；`PENDING`/`RUNNING`（还没结算）与
     * `FAILED`/`REJECTED`（没写成）都不算——把没写成的文件列进"产出"就是撒谎。
     */
    if (item.toolState !== ToolState.SUCCESS) {
      continue;
    }
    const diff: ToolDiff | null = intendedDiffOf(item.toolName, item.toolArgs);
    if (diff === null) {
      continue;
    }
    const path: string = diff.path;
    if (path.length === 0 || seen.indexOf(path) >= 0) {
      continue;
    }
    seen.push(path);
    /*
     * 逐文件 ±（官方那张卡里每个文件后面都跟着 `+15 -2`）。
     * 判据就在这里**已经算出来了**（上面那行 `intendedDiffOf`），以前只用了 `path` 就把它丢了。
     * 同一个文件被改多次时取**最后一次**的对照——那张卡说的是"现在这个文件变成了什么样"，
     * 而不是"这一回合总共敲了多少增删"。要总数看行尾那个 `+N −M`。
     */
    const stat: DiffStat = diffStatOf(diffLines(diff.oldText, diff.newText));
    const known: number = out.findIndex((f: ProducedFile) => f.path === path);
    if (known >= 0) {
      out[known].added = stat.added;
      out[known].removed = stat.removed;
      continue;
    }
    out.push({ path: path, name: baseNameOf(path), added: stat.added, removed: stat.removed });
  }
  return out;
}

/**
 * 产出行的**文案**（有 0 个时返回空串 ⇒ 调用方不渲染这一行）。
 *
 * 与官方一致：本回合没写文件就**什么都不显示**（不画一行"本回合没有产出文件"占位）。
 */
export function producedRowText(count: number, maxShown: number): string {
  if (count <= 0) {
    return '';
  }
  if (count <= maxShown) {
    return `本回合写入 ${count} 个文件`;
  }
  return `本回合写入 ${count} 个文件（显示前 ${maxShown} 个）`;
}

/**
 * 一回合的**改动量**（官方那张"已编辑 N 个文件 · `+86 -9`"卡片要的两个数）。
 *
 * 【为什么不复用 `producedFilesOf` 的结果】那个函数只收**成功**的写类调用
 * （官方语义："successful … calls"），而这里的行数是给用户看"这一轮改了多少"——
 * 同一批调用，只是取值口径不同。所以两个函数各自扫一遍 `process`，
 * **共用 `intendedDiffOf` 这一份判据**（谁是写类工具、参数里哪两个是前后文），不另写一套。
 *
 * `truncated` 表示**至少**这么多：有工具的 diff 触到篇幅上限时真实改动只会更大，
 * 视图据此说"至少"，不说"就是这么多"——这是本仓对被截断数据的一贯口径。
 */
export interface TurnChangeStat {
  added: number;
  removed: number;
  files: number;
  truncated: boolean;
}

export function turnChangeStatOf(items: TrajectoryItem[]): TurnChangeStat {
  let added: number = 0;
  let removed: number = 0;
  let files: number = 0;
  let truncated: boolean = false;
  for (let i = 0; i < items.length; i++) {
    const item: TrajectoryItem = items[i];
    if (item.kind !== TrajectoryKind.TOOL) {
      continue;
    }
    const diff: ToolDiff | null = intendedDiffOf(item.toolName, item.toolArgs);
    if (diff === null) {
      continue;
    }
    const stat: DiffStat = diffStatOf(diffLines(diff.oldText, diff.newText));
    added += stat.added;
    removed += stat.removed;
    files += 1;
    if (stat.added + stat.removed >= MAX_DIFF_LINES) {
      truncated = true;
    }
  }
  return { added: added, removed: removed, files: files, truncated: truncated };
}

/** 改动量的显示文案（`+86 −9`；两个都是 0 时返回空串 ⇒ 视图不渲染这一格） */
export function changeStatText(stat: TurnChangeStat): string {
  if (stat.added === 0 && stat.removed === 0) {
    return '';
  }
  const sign: string = stat.truncated ? '至少 ' : '';
  return `${sign}+${stat.added} −${stat.removed}`;
}

/* ───────────────────────── 正文里的文件提及（P9-3） ───────────────────────── */

/** 提及 token 的长度上限：行内代码里那种长串多半是命令或摘要，不是文件名 */
export const MENTION_TOKEN_MAX: number = 200;

/**
 * 把**行内代码**里的一个 token 解析成"本回合真实产出的文件"。
 *
 * ## 官方契约（逐字）
 *
 * `dsh-client-ui-primitives` 的 `MarkdownFileMentions`：
 * > "File-mention affordance for inline code: the owner resolves an authored token to the file it
 * > names, using **its own vocabulary of real files** — **the renderer never guesses at what looks
 * > like a path**."
 * > `resolve(value)`: "…or **undefined when the token names no known file — it then stays inert code**."
 *
 * 两件事被这句话钉死：① 可点的**只有行内代码**（`\`src/a.ts\``），普通正文里的路径**不猜**；
 * ② 认不出来的 token **保持普通代码**（不许凭"看着像路径"就变可点）。
 * 词汇表就是**本回合的产出文件**（`producedFilesOf`）——与回合尾部那行 chip **同一份来源**，
 * 这正是官方 `slots.d.ts` 里 `fileMentions` 挂在 turn-tail owner 上的意思。
 *
 * ## 匹配规则（我们声明的三条，按顺序取第一个命中）
 *
 *   1. **全路径相等**（模型最常写的就是工具参数里那个路径）；
 *   2. **以 `/token` 结尾**（模型只写了后半截，例如 `components/Button.tsx`）；
 *   3. **basename 相等**（模型只写了文件名，例如 `Button.tsx`）。
 *
 * 【歧义怎么办】第 2、3 条可能命中多个（两个目录下都有 `index.ts`）⇒ 此时返回空串
 * （保持普通代码）。**猜一个**是最坏的选择：用户点下去打开了**另一个**文件，而他会以为
 * 自己点对了。这条与官方"never guesses"是同一条纪律。
 *
 * @param files 本回合的产出文件（`producedFilesOf` 的结论）
 * @param token 行内代码的原文（**原样**，含大小写与空格）
 * @returns 目标文件的完整路径；空串 = 不是已知文件（保持普通代码）
 */
export function resolveProducedMention(files: ProducedFile[], token: string): string {
  const text: string = token.trim();
  if (text.length === 0 || text.length > MENTION_TOKEN_MAX) {
    return '';
  }
  // ① 全路径相等（含大小写：端侧文件系统区分大小写，不能"宽容"到匹配错文件）
  for (let i = 0; i < files.length; i++) {
    if (files[i].path === text) {
      return files[i].path;
    }
  }
  // ② 以 `/token` 结尾
  const suffix: string = '/' + text;
  let suffixHit: string = '';
  let suffixCount: number = 0;
  for (let i = 0; i < files.length; i++) {
    const path: string = files[i].path;
    if (path.length > suffix.length && path.endsWith(suffix)) {
      suffixHit = path;
      suffixCount++;
    }
  }
  if (suffixCount === 1) {
    return suffixHit;
  }
  // ③ basename 相等
  let nameHit: string = '';
  let nameCount: number = 0;
  for (let i = 0; i < files.length; i++) {
    if (files[i].name === text) {
      nameHit = files[i].path;
      nameCount++;
    }
  }
  return nameCount === 1 ? nameHit : '';
}

/* ───────────────────────── 交付物的「分享」能分享什么（P9-7） ───────────────────────── */

/** 分享目标：文件本体（系统分享拿到可打开的 URI） */
export const SHARE_TARGET_FILE: string = 'file';
/** 分享目标：只有路径文本（文件在应用沙箱外，系统分享拿不到 URI） */
export const SHARE_TARGET_TEXT: string = 'text';
/** 分享目标：什么都不能分享（禁用，并把原因写在旁边） */
export const SHARE_TARGET_NONE: string = 'none';

/** 一次「分享」的目标与理由 */
export interface ShareTarget {
  /** `SHARE_TARGET_*` */
  kind: string;
  /** `kind === 'file'` 时的**绝对路径**（转 URI 由平台层做，见 `platform/system/ShareBoard`） */
  absPath: string;
  /** `kind === 'text'` 时要分享的文本 */
  text: string;
  /** `kind === 'none'` 时**必须**写清为什么（假入口是本仓明令禁止的） */
  reason: string;
}

/**
 * 一条交付物能不能分享、以什么形式分享。
 *
 * ## 官方契约（逐字）
 *
 * `dsh-tool-present` 的 `PresentedFile.path`：
 * > "**Original absolute path or path relative to the Session working directory.**"
 *
 * 也就是路径可能是绝对的、也可能相对会话工作目录 ⇒ 先归一成绝对路径再判断。
 *
 * ## 为什么分三档（而不是"能分享/不能分享"）
 *
 * 系统分享面板要的是**文件 URI**（`systemShare.SharedRecord.uri`，SDK 文档："Either **content**
 * or **uri** must be set"，URI 由 `fileUri.getUriFromPath` 从**沙箱路径**得到）。而工作区可能是
 * 用户经系统选择器挑的**沙箱外**目录 ⇒ 那种路径转不出可用 URI。此时**如实降级**：
 * 分享路径文本（接收方仍能用它定位文件），而不是给一个点了报错、或干脆假装禁用的按钮。
 *
 * @param rawPath 交付物给的路径（绝对或相对会话工作目录）
 * @param sessionCwd 会话工作目录（绝对路径；不知道传空串）
 * @param sandboxRoot 应用沙箱根（`context.filesDir`；不知道传空串）
 */
export function deliverableShareTarget(rawPath: string, sessionCwd: string,
  sandboxRoot: string): ShareTarget {
  const raw: string = rawPath.trim();
  if (raw.length === 0) {
    return noneShare('这条交付物没有路径，无法分享。');
  }
  const absolute: string = raw.startsWith('/') ? raw : joinPath(sessionCwd, raw);
  if (absolute.length === 0) {
    return noneShare('不知道会话的工作目录，没法定位这个文件（相对路径无从解析）。');
  }
  if (sandboxRoot.length > 0 && absolute.startsWith(sandboxRoot)) {
    return { kind: SHARE_TARGET_FILE, absPath: absolute, text: '', reason: '' };
  }
  return {
    kind: SHARE_TARGET_TEXT,
    absPath: absolute,
    text: absolute,
    reason: sandboxRoot.length === 0
      ? '拿不到应用沙箱路径，只能分享路径文本。'
      : '这个文件在工作区（应用沙箱外）：系统分享拿不到它的 URI，只能分享路径文本。'
  };
}

function noneShare(reason: string): ShareTarget {
  return { kind: SHARE_TARGET_NONE, absPath: '', text: '', reason: reason };
}

/** 拼绝对路径（两端各补一个 `/`；工作目录为空 ⇒ 空串表示"不知道"） */
function joinPath(dir: string, rel: string): string {
  if (dir.length === 0) {
    return '';
  }
  const left: string = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
  const right: string = rel.startsWith('/') ? rel.substring(1) : rel;
  return `${left}/${right}`;
}

/** 「分享」按钮的文案（三档各自的说法，不混用） */
export function shareActionLabel(target: ShareTarget): string {
  if (target.kind === SHARE_TARGET_FILE) {
    return '分享文件';
  }
  if (target.kind === SHARE_TARGET_TEXT) {
    return '分享路径';
  }
  return '分享';
}
