/**
 * 子代理引用模型（DSH Full Parity §FR-022–025）。
 *
 * ## 存在理由
 *
 * 子代理是 DSH 的核心编排能力——主代理可以派生出独立的子会话来处理子任务。
 * 界面需要在对话中展示子代理卡片（状态摘要），并在点击时打开子代理转录视图。
 *
 * 本模型是 HubSnapshot 里的子代理引用列表——只记摘要，不记完整对话内容
 * （完整内容由子代理自己的 follow 流提供，复用 ConversationPane 渲染）。
 *
 * ## 为什么是值类型
 *
 * 与 RemoteHost 同理：纯数据记录，行为在 SessionHub（promptSubagent / interruptSubagent）。
 */

import type { ReferenceCandidate } from './Wire';

/** 子代理运行状态 */
export enum SubagentStatus {
  /** 正在运行 */
  RUNNING = 'running',
  /** 已完成 */
  COMPLETED = 'completed',
  /** 被中断 */
  INTERRUPTED = 'interrupted',
  /** 运行失败 */
  FAILED = 'failed'
}

/** 子代理引用——HubSnapshot 里的摘要行 */
export interface SubagentRef {
  /** 子代理会话 ID（用于 follow / prompt / interrupt） */
  sessionId: string;
  /** 父会话 ID（用于关联到主对话） */
  parentSessionId: string;
  /** 运行状态 */
  status: SubagentStatus;
  /** 已完成的轮次计数 */
  turnCount: number;
  /** 最后一条消息的摘要（截断后；空串 = 尚无消息） */
  lastMessage: string;
}

/** 子代理状态的中文名（界面卡片显示） */
export function subagentStatusLabel(status: SubagentStatus): string {
  if (status === SubagentStatus.RUNNING) {
    return '运行中';
  }
  if (status === SubagentStatus.COMPLETED) {
    return '已完成';
  }
  if (status === SubagentStatus.INTERRUPTED) {
    return '已中断';
  }
  return '失败';
}

/** 子代理是否仍可接受追问（运行中或已完成时可以） */
export function subagentCanPrompt(status: SubagentStatus): boolean {
  return status === SubagentStatus.RUNNING || status === SubagentStatus.COMPLETED;
}

/** 子代理是否可以被中断（仅运行中） */
export function subagentCanInterrupt(status: SubagentStatus): boolean {
  return status === SubagentStatus.RUNNING;
}

/** §FR-048：将子代理引用转换为 @ 候选行 */
export function subagentReferenceCandidate(ref: SubagentRef): ReferenceCandidate {
  return {
    kind: 'subagent',
    label: ref.sessionId,
    insert: `@${ref.sessionId}`,
    detail: subagentStatusLabel(ref.status),
    createdAt: 0,
    sameWorkspace: true
  };
}
