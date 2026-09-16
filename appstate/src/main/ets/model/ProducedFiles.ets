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

import { intendedDiffOf, ToolDiff } from './ToolDiff';
import { ToolState, TrajectoryItem, TrajectoryKind } from './Trajectory';

/** 一枚产出文件（视图只用这两个字段） */
export interface ProducedFile {
  /** 工作区相对路径（原样，不做归一化——它就是 Host 与工具用的那个字符串） */
  path: string;
  /** 展示名（路径末段） */
  name: string;
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
    out.push({ path: path, name: baseNameOf(path) });
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
