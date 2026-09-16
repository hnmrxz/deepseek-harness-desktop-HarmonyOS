/**
 * 呈现层纯函数（无 UI 依赖，可单测）。
 *
 * 这些函数把模型值翻译成界面文字，是 D3 §4「状态与文案规范」与 §3 各表格的实现依据。
 */

import { PendingKind, PendingItem, RiskLevel, RETRY_STATE_CANCELLED, RETRY_STATE_STARTED, ToolState } from './Trajectory';

/** 相对时间（D3 §3.1） */
export function relativeTime(atMs: number, nowMs: number): string {
  if (atMs <= 0) {
    return '';
  }
  const diff = nowMs - atMs;
  if (diff < 0) {
    return '刚刚';
  }
  const minute = 60 * 1000;
  const hour = 60 * minute;
  const day = 24 * hour;
  if (diff < minute) {
    return '刚刚';
  }
  if (diff < hour) {
    return `${Math.floor(diff / minute)} 分钟前`;
  }
  if (diff < day) {
    return `${Math.floor(diff / hour)} 小时前`;
  }
  if (diff < 30 * day) {
    return `${Math.floor(diff / day)} 天前`;
  }
  return formatDate(atMs);
}

/** 绝对日期 YYYY-MM-DD */
export function formatDate(atMs: number): string {
  const d: Date = new Date(atMs);
  const y: number = d.getFullYear();
  const m: number = d.getMonth() + 1;
  const day: number = d.getDate();
  return `${y}-${pad2(m)}-${pad2(day)}`;
}

/** 时钟 HH:MM */
export function formatClock(atMs: number): string {
  const d: Date = new Date(atMs);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

function pad2(v: number): string {
  return v < 10 ? `0${v}` : `${v}`;
}

/** 耗时（D3 §3.2「已思考 N 秒」/ §3.3 耗时列） */
export function formatDuration(ms: number): string {
  if (ms <= 0) {
    return '';
  }
  if (ms < 1000) {
    return `${ms} ms`;
  }
  if (ms < 60 * 1000) {
    return `${(ms / 1000).toFixed(1)} s`;
  }
  const totalSeconds: number = Math.floor(ms / 1000);
  const minutes: number = Math.floor(totalSeconds / 60);
  const seconds: number = totalSeconds % 60;
  return `${minutes} 分 ${seconds} 秒`;
}

/** 文件大小 */
export function formatBytes(bytes: number): string {
  if (bytes <= 0) {
    return '';
  }
  const kb: number = 1024;
  if (bytes < kb) {
    return `${bytes} B`;
  }
  if (bytes < kb * kb) {
    return `${(bytes / kb).toFixed(1)} KB`;
  }
  return `${(bytes / (kb * kb)).toFixed(1)} MB`;
}

/** 工具状态徽标文字（D3 §3.3） */
export function toolStateLabel(state: ToolState): string {
  if (state === ToolState.PENDING) {
    return '等待';
  }
  if (state === ToolState.RUNNING) {
    return '运行中';
  }
  if (state === ToolState.SUCCESS) {
    return '成功';
  }
  if (state === ToolState.FAILED) {
    return '失败';
  }
  return '被拒';
}

export const LARGE_OUTPUT_PREVIEW: number = 2 * 1024;

/** 按 D3 §3.3 截断输出 */
export interface OutputPreview {
  shown: string;
  truncated: boolean;
  totalLength: number;
}

export function previewOutput(output: string): OutputPreview {
  if (output.length <= LARGE_OUTPUT_PREVIEW) {
    return { shown: output, truncated: false, totalLength: output.length };
  }
  return {
    shown: output.substring(0, LARGE_OUTPUT_PREVIEW),
    truncated: true,
    totalLength: output.length
  };
}

/** 待决聚合页排序键（D3 §3.7：危险动作 > 普通审批 > 提问 > 完成通知，再按时间） */
export function pendingSortKey(item: PendingItem): number {
  if (item.kind === PendingKind.APPROVAL) {
    if (item.risk === RiskLevel.DANGEROUS) {
      return 0;
    }
    if (item.risk === RiskLevel.ELEVATED) {
      return 1;
    }
    return 2;
  }
  return 3;
}

/** 按 D3 §3.7 排序（返回新数组，不改原数组） */
export function sortPending(items: PendingItem[]): PendingItem[] {
  const copy: PendingItem[] = items.slice();
  copy.sort((a: PendingItem, b: PendingItem) => {
    const ka: number = pendingSortKey(a);
    const kb: number = pendingSortKey(b);
    if (ka !== kb) {
      return ka - kb;
    }
    return a.at - b.at;
  });
  return copy;
}

/*
 * 重试节点的文案（P8-6：**逐字取官方**）。
 *
 * 官方的四段状态标签与状态行模板都在 `@deepseek-ai/dsh-client-locale` 里（逐字）：
 *   `message.retry.scheduled` = 等待重试模型请求
 *   `message.retry.active`    = 正在重试模型请求
 *   `message.retry.started`   = 已重试模型请求
 *   `message.retry.cancelled` = 模型请求重试已取消
 *   `message.retry.status`    = `{label}（{retry}/{maximum}） · {seconds}s`
 *   `message.retry.delay`     = 重试延迟：     `message.retry.failure` = 失败原因：
 * 渲染见 `dsh-client-ui-chat` 的 `ModelRetryItem`：`maximum = node.mode === 'normal' ? node.maxRetries : '∞'`，
 * `retrySeconds(ms) = Math.max(1, Math.ceil(ms / 1000))`（**最小 1 秒**：显示 "0s" 会被读成卡住），
 * 且 `seconds = active ? 剩余秒 : scheduledSeconds`——即**什么时候都带秒数**。
 *
 * 【为什么换掉我们原来那两句】P7-18 写的是"正在重试（第 2/5 次）" + "约 N 秒后重试"：
 * 同一件事用了两行、两套措辞，而且和官方一个词都对不上（官方是一行 `标签（n/max） · Ns`）。
 * 现在按官方模板合成**一行**，并把三种状态映射清楚（见 `retryStatusLine`）。
 */
export const RETRY_LABEL_SCHEDULED: string = '等待重试模型请求';
export const RETRY_LABEL_ACTIVE: string = '正在重试模型请求';
export const RETRY_LABEL_STARTED: string = '已重试模型请求';
export const RETRY_LABEL_CANCELLED: string = '模型请求重试已取消';
export const RETRY_DELAY_LABEL: string = '重试延迟：';
export const RETRY_FAILURE_LABEL: string = '失败原因：';

/** 秒数（**逐字对齐官方 `retrySeconds`**：向上取整且最小 1 秒） */
export function retrySecondsOf(milliseconds: number): number {
  return Math.max(1, Math.ceil(milliseconds / 1000));
}

/**
 * 重试行的一行文案（官方 `message.retry.status` 模板）。
 *
 * 四种状态各有出处，**不许含糊**：
 *   · 还在等（`scheduled`，倒计时 > 0）⇒ 「等待重试模型请求（2/5） · 8s」；
 *   · 等到点了但还没收到 `llm/retry-started`（`scheduled`，倒计时 ≤ 0）⇒
 *     「正在重试模型请求（2/5） · 1s」——"该开始却还没开始的这一小段"真实存在，
 *     说"正在重试"比显示 "0s" 诚实；
 *   · 已经收到 `llm/retry-started`（`started`）⇒ 「已重试模型请求（2/5） · 8s」，
 *     秒数取**当初计划的延迟**（官方在非 active 状态下就是回落到 `scheduledSeconds`）；
 *   · 用户按了停止（`cancelled`）⇒ 「模型请求重试已取消（2/5） · 8s」——
 *     **这条必须显示**：不说的话那一行会一直写着"等待重试… 7s"，而那次重试永远不会发生。
 *
 * @param state `Trajectory.RETRY_STATE_*`
 * @param max 上限；`<= 0` 表示上游这一帧没给（`mode: 'always'` 的分支没有 `maxRetries`）⇒ 按官方显示 `∞`
 */
export function retryStatusLine(attempt: number, max: number, state: string,
  remainingMs: number, delayMs: number): string {
  if (attempt <= 0) {
    return '';
  }
  const maximum: string = max > 0 ? `${max}` : '∞';
  let label: string = RETRY_LABEL_SCHEDULED;
  if (state === RETRY_STATE_CANCELLED) {
    label = RETRY_LABEL_CANCELLED;
  } else if (state === RETRY_STATE_STARTED) {
    label = RETRY_LABEL_STARTED;
  } else if (remainingMs <= 0) {
    label = RETRY_LABEL_ACTIVE;
  }
  const waiting: boolean = label === RETRY_LABEL_SCHEDULED;
  const seconds: number = waiting ? retrySecondsOf(remainingMs) : retrySecondsOf(delayMs);
  return `${label}（${attempt}/${maximum}） · ${seconds}s`;
}

/** 风险等级文案 */
export function riskLabel(risk: RiskLevel): string {
  if (risk === RiskLevel.DANGEROUS) {
    return '高风险';
  }
  if (risk === RiskLevel.ELEVATED) {
    return '需留意';
  }
  return '常规';
}
