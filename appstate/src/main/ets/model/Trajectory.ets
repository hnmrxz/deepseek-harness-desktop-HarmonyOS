/**
 * 轨迹（会话内容）视图模型。
 *
 * 这些类型是**呈现层契约**：UI 只认识它们，不认识协议原始对象。
 * 因此「桩数据」与「真实事件投影」可以互换而不改动任何组件（见 StubFeed）。
 *
 * 与 D3 §3.2 / §3.3 的界面规格一一对应。
 */

/** 角色 */
export enum Speaker {
  USER = 'user',
  ASSISTANT = 'assistant',
  SYSTEM = 'system'
}

/** 工具调用状态（D3 §3.3 的徽标） */
export enum ToolState {
  PENDING = 'pending',
  RUNNING = 'running',
  SUCCESS = 'success',
  FAILED = 'failed',
  REJECTED = 'rejected'
}

/** 轨迹条目类型 */
export enum TrajectoryKind {
  MESSAGE = 'message',
  REASONING = 'reasoning',
  TOOL = 'tool',
  SUBAGENT = 'subagent',
  DELIVERABLE = 'deliverable',
  GOAL = 'goal',
  JOB = 'job',
  ERROR = 'error'
}

/** 轨迹条目基类（用一个接口承载所有可选字段，避免 ArkTS 联合类型在 UI 中难用） */
export interface TrajectoryItem {
  id: string;
  kind: TrajectoryKind;
  /** 稳定排序键（毫秒时间戳） */
  at: number;
  /** 正文（Markdown；仅 MESSAGE / REASONING / ERROR 使用） */
  body: string;
  /** 角色（仅 MESSAGE） */
  speaker: Speaker;
  /** 模型名（仅 ASSISTANT 消息显示为次要信息） */
  model: string;
  /** 耗时毫秒（0 = 不显示） */
  elapsedMs: number;
  /** 工具名（仅 TOOL） */
  toolName: string;
  /** 工具参数摘要（仅 TOOL，单行） */
  toolArgs: string;
  /** 工具状态（仅 TOOL） */
  toolState: ToolState;
  /** 工具输出（仅 TOOL；大输出由 UI 截断，D3 §3.3） */
  toolOutput: string;
  /** 子代理名称（仅 SUBAGENT） */
  subagentName: string;
  /** 交付物文件名（仅 DELIVERABLE） */
  fileName: string;
  /** 交付物大小（字节；0 = 未知） */
  fileSize: number;
  /** 目标/任务标题（仅 GOAL / JOB） */
  title: string;
  /** 目标/任务进度描述（仅 GOAL / JOB） */
  progress: string;
  /** 进度百分比（0–100；负数 = 不确定） */
  percent: number;
  /** 是否正在流式输出（UI 显示尾部光标） */
  streaming: boolean;
  /** 是否默认展开（如失败的工具、错误） */
  expanded: boolean;
}

/** 构造一个带默认值的条目（ArkTS 要求显式初始化所有字段） */
export function makeItem(id: string, kind: TrajectoryKind, at: number): TrajectoryItem {
  return {
    id: id,
    kind: kind,
    at: at,
    body: '',
    speaker: Speaker.ASSISTANT,
    model: '',
    elapsedMs: 0,
    toolName: '',
    toolArgs: '',
    toolState: ToolState.PENDING,
    toolOutput: '',
    subagentName: '',
    fileName: '',
    fileSize: 0,
    title: '',
    progress: '',
    percent: -1,
    streaming: false,
    expanded: false
  };
}

/** 审批风险等级（D3 §3.4：危险动作视觉权重反转） */
export enum RiskLevel {
  NORMAL = 'normal',
  ELEVATED = 'elevated',
  DANGEROUS = 'dangerous'
}

/** 待决类型 */
export enum PendingKind {
  APPROVAL = 'approval',
  QUESTION = 'question'
}

/** 审批/提问的候选项 */
export interface PendingChoice {
  id: string;
  label: string;
  detail: string;
}

/**
 * 审批三选的**稳定 id 契约**。
 *
 * 为什么必须集中声明：审批卡的「主选项判定」（D3 §3.4 危险动作把拒绝提为主选）
 * 依赖 `choice.id`。曾出现过桩数据用 `once`、真实中枢用 `allow` 的分歧——
 * 结果是在真机上**危险动作的拒绝按钮拿不到主选样式**，
 * 而界面看起来完全正常，只是权重反转悄悄失效了（正是最难发现的那类不一致）。
 * 因此把 id 提为唯一契约，桩数据与中枢都从这里取，视图也用它判定。
 *
 * 与上游的对应关系：上游审批结果词表是 `allowed-once | rejected | cancelled | unavailable`
 * （见 `dshcompat.APPROVAL_OUTCOMES`），**没有**「始终允许」。
 * `APPROVAL_CHOICE_ALLOW_ALWAYS` 因此只表达**客户端侧**的「本会话内不再打扰」，
 * 发往 Host 的仍然是 `allowed-once`。
 */
export const APPROVAL_CHOICE_ALLOW: string = 'allow';
/** 客户端侧的「本会话内不再打扰」（**不是**一个上游 outcome） */
export const APPROVAL_CHOICE_ALLOW_ALWAYS: string = 'allow-always';
/** 拒绝 */
export const APPROVAL_CHOICE_DENY: string = 'deny';

/** 待决事项（审批或提问；D3 §3.4 / §3.5） */
export interface PendingItem {
  id: string;
  kind: PendingKind;
  /** 所属会话 id */
  sessionId: string;
  /** 所属会话标题（聚合页展示） */
  sessionTitle: string;
  /** 动作名 / 问题正文 */
  title: string;
  /** 影响说明 / 问题补充说明 */
  detail: string;
  /** 原始请求载荷（可展开查看） */
  raw: string;
  /** 风险等级 */
  risk: RiskLevel;
  /** 选项（审批为三选，提问来自 Host） */
  choices: PendingChoice[];
  /** 是否允许多选（仅提问） */
  multiSelect: boolean;
  /** 是否允许自由文本（仅提问） */
  allowFreeText: boolean;
  /** 入队时间 */
  at: number;
}
