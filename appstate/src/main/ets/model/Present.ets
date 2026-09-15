/**
 * 呈现层纯函数（无 UI 依赖，可单测）。
 *
 * 这些函数把模型值翻译成界面文字，是 D3 §4「状态与文案规范」与 §3 各表格的实现依据。
 */

import { PendingKind, PendingItem, RiskLevel, ToolState, TrajectoryItem, TrajectoryKind } from './Trajectory';

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
