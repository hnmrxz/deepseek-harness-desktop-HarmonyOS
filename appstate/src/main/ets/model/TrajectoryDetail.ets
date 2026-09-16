/**
 * 轨迹条目的**事件详情**（官方 `dsh-client-ui-trajectory` 的 `details.*`）。
 *
 * ## 官方长什么样（读 `@deepseek-ai/dsh-client-ui-trajectory` 的字典）
 *
 * 它的轨迹是**表 + 详情面板**：点一条事件会打开「事件详情」（`details.event`），
 * 面板里是**成对字段**：状态（`details.status`）、用途（`details.purpose`）、
 * 提供方（`details.provider`）、模型（`details.model`）、工具调用（`details.toolCalls`）、
 * 子工具调用（`details.subtoolCalls`）、错误（`details.error`）、结果（`details.result`）、
 * 来源（`details.source`）、层级（`details.hierarchy`）、助手消息（`details.assistantMessage`）、
 * 可关闭（`details.close`）、可拖动调宽（`details.resize` / `details.resizeTitle`）。
 *
 * ## 我们做到哪一步，以及**为什么有的行不出现**
 *
 * 官方那些字段来自它自己的事件模型（`purpose` / `provider` / `hierarchy` / `subtoolCalls`…），
 * 我们的投影**没有**它们。按本仓纪律（不造假数据、不编字段名），
 * **有数据的行才出现，没有的行整行不画** —— 而不是画一个空值或"未知"。
 * 于是这层就是"哪些行存在"的唯一判定处，也就能被 fixture 钉住。
 *
 * 另有一处**我们比官方多**的信息：`internal` 的条目（系统提示词、命令、压缩摘要、
 * 未识别事件）在对话视图不显示，只活在轨迹里 ⇒ 详情里如实标注「内部事件」，
 * 免得有人以为"界面上看不见就是没发生过"。
 *
 * ## P8-5：内部事件的**正文不进这里**（这是修一个真实泄露）
 *
 * 时间线是可点的，而**内部事件也会产生格子**（`system/message` 是 kind=MESSAGE ⇒ 有格子）
 * ⇒ 点它就会打开这份详情。而这份详情此前把 `body` 原样画出来，于是
 * **点一下格子就能读到完整的系统提示词**（未识别事件则把整段原始载荷画出来）。
 * 这与 `docs/09-安全与API错误呈现审计.md` §2.2 第 1 条直接冲突：
 * 「轨迹详情：默认不得展示 `internal=true` 的正文」。
 *
 * 现在的规则：**正文类字段一律不画**（正文 / 思考 / 工具参数 / 工具结果 / 错误原文），
 * 只给**结构化事实**（类别、状态、工具名、模型名、字符数、耗时）——
 * 这正是审计要求的"允许进入开发诊断的数据必须单独定义白名单，并默认脱敏"。
 * 判据取自 `Turns.mayExposeBodyToUser()`（与对话可见性同一个来源事实），不在这里另判一次。
 */

import { Speaker, TrajectoryItem, TrajectoryKind } from './Trajectory';
import { formatDuration, previewOutput, toolStateLabel } from './Present';
import { mayExposeBodyToUser } from './Turns';

/** 详情卡的一行（标签 + 值） */
export interface DetailRow {
  label: string;
  value: string;
}

/** 详情卡标题（官方 `details.event` 原文） */
export const TRAJECTORY_DETAIL_TITLE: string = '事件详情';

/**
 * 内部事件正文被隐藏时的说明（**唯一一处文案**）。
 *
 * 【为什么必须说清"为什么"】一句"已隐藏"会被读成"数据丢了"或"这个 App 坏了"。
 * 这句话要同时回答：① 发生了什么（内部事件正文不显示）；② 为什么（可能含系统提示词，
 * 按安全口径不进任何用户可达出口）；③ 还能拿到什么（类别/工具名/模型/字符数在下面几行）。
 */
const INTERNAL_BODY_HIDDEN_PREFIX: string =
  '内部事件正文不显示：它可能包含系统提示词或未识别载荷，按安全口径不进界面/复制/引用/通知/导出。'
  + '下面的类别、工具名、模型与字符数是可核查的结构化事实';

/**
 * 条目类别 → 详情里的「来源」文案。
 *
 * 我们是 8 类（官方 7 类：system/user/context/compacted/message/tool/subtool），
 * 多出来的是 **任务（job）**——官方轨迹没有这个 kind（实测其 bundle 里 `job` 出现 0 次），
 * 它是本仓台账的用法（见矩阵 `jobs` 行）。
 */
export function itemKindLabel(item: TrajectoryItem): string {
  if (item.kind === TrajectoryKind.MESSAGE) {
    return item.speaker === Speaker.USER ? '用户消息' : '助手消息';
  }
  if (item.kind === TrajectoryKind.REASONING) {
    return '思考';
  }
  if (item.kind === TrajectoryKind.TOOL) {
    return '工具';
  }
  if (item.kind === TrajectoryKind.SUBAGENT) {
    return '子代理';
  }
  if (item.kind === TrajectoryKind.DELIVERABLE) {
    return '交付物';
  }
  if (item.kind === TrajectoryKind.GOAL) {
    return '目标';
  }
  if (item.kind === TrajectoryKind.JOB) {
    return '任务';
  }
  if (item.kind === TrajectoryKind.COMMAND) {
    return '斜杠命令';
  }
  return '错误';
}

/** 长文本压成"首段 + 截断说明"（复用工具卡的截断规则 `previewOutput`，不另定一套阈值） */
function clipped(text: string): string {
  const preview = previewOutput(text);
  if (!preview.truncated) {
    return preview.shown;
  }
  return `${preview.shown}…（共 ${preview.totalLength} 字符，已截断）`;
}

/**
 * 一条轨迹条目 → 详情行（**空值不产生行**）。
 *
 * 顺序按"先看该看的"：类别与状态 → 名字/模型 → 参数 → 结果/正文 → 耗时。
 */
export function trajectoryDetailRows(item: TrajectoryItem): DetailRow[] {
  const rows: DetailRow[] = [];
  // 正文类字段能不能画：**判据与对话可见性同源**（`internal` 是上游给的来源事实）
  const expose: boolean = mayExposeBodyToUser(item);
  rows.push({
    label: '来源',
    value: item.internal ? `${itemKindLabel(item)} · 内部事件` : itemKindLabel(item),
  });

  if (item.kind === TrajectoryKind.TOOL) {
    rows.push({ label: '状态', value: toolStateLabel(item.toolState) });
    if (item.toolName.length > 0) {
      // 工具**名字**是结构化事实（不是内容）⇒ 内部事件也画，排查时正是靠它
      rows.push({ label: '工具调用', value: item.toolName });
    }
    if (expose && item.toolArgs.length > 0) {
      // 【为什么叫「参数」】官方把工具参数放在它自己的工具卡里，详情面板用 `details.toolCalls`
      // （调用数）；我们的投影有**单次调用的参数文本**，如实叫「参数」而不是套用官方的字段名。
      rows.push({ label: '参数', value: clipped(item.toolArgs) });
    }
    if (expose && item.toolOutput.length > 0) {
      rows.push({ label: '结果', value: clipped(item.toolOutput) });
    }
  } else if (item.kind === TrajectoryKind.MESSAGE || item.kind === TrajectoryKind.REASONING) {
    if (item.model.length > 0) {
      // 模型名是结构化事实 ⇒ 内部事件也画
      rows.push({ label: '模型', value: item.model });
    }
    if (expose && item.reasoning.length > 0) {
      rows.push({ label: '思考', value: clipped(item.reasoning) });
    }
    if (expose && item.body.length > 0) {
      rows.push({
        label: item.kind === TrajectoryKind.REASONING ? '思考正文' : '正文',
        value: clipped(item.body),
      });
    }
  } else if (item.kind === TrajectoryKind.ERROR) {
    if (expose) {
      rows.push({ label: '错误', value: clipped(item.body) });
    }
  } else if (item.kind === TrajectoryKind.SUBAGENT) {
    if (item.subagentName.length > 0) {
      rows.push({ label: '子代理', value: item.subagentName });
    }
  } else if (item.kind === TrajectoryKind.DELIVERABLE) {
    if (item.fileName.length > 0) {
      rows.push({ label: '文件', value: item.fileName });
    }
    if (item.fileSize > 0) {
      rows.push({ label: '大小', value: `${item.fileSize} 字节` });
    }
  } else {
    // GOAL / JOB
    if (item.title.length > 0) {
      rows.push({ label: '标题', value: item.title });
    }
    if (item.progress.length > 0) {
      rows.push({ label: '进度', value: item.progress });
    }
    if (item.percent >= 0) {
      rows.push({ label: '完成度', value: `${item.percent}%` });
    }
  }

  /*
   * 内部事件：正文类字段已被上面的 `expose` 全部挡掉 ⇒ 这里补一行**结构化事实**
   * （有多少字符被挡），让"看不见"是一个**说明**，而不是一片空白。
   * 只给长度、不给内容：长度不泄露任何东西，却能让人判断"这条是不是那段很长的系统提示词"。
   */
  if (!expose) {
    const hidden: number = item.body.length + item.reasoning.length
      + item.toolArgs.length + item.toolOutput.length;
    if (hidden > 0) {
      rows.push({
        label: item.kind === TrajectoryKind.TOOL ? '内容（内部事件）' : '正文（内部事件）',
        value: `${INTERNAL_BODY_HIDDEN_PREFIX}（共 ${hidden} 字符）`,
      });
    }
  }

  if (item.elapsedMs > 0) {
    rows.push({ label: '耗时', value: formatDuration(item.elapsedMs) });
  }
  return rows;
}
