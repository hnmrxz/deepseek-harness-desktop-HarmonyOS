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
