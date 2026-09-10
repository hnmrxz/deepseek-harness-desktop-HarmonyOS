/**
 * 状态层对外入口（HAR 模块 appstate）。
 *
 * 上层（entry 页面与视图）只应通过本入口导入。
 */

// ── 会话列表 ──
export { projectSessionList, sessionListEndpoint, sessionListPayload } from './model/SessionList';
export type { SessionListItem, SessionListPage } from './model/SessionList';

// ── 轨迹与待决的呈现层契约 ──
export {
  PendingKind,
  RiskLevel,
  Speaker,
  ToolState,
  TrajectoryKind,
  makeItem
} from './model/Trajectory';export type {
  PendingChoice,
  PendingItem,
  TrajectoryItem
} from './model/Trajectory';

// ── 呈现层纯函数 ──
export {
  formatBytes,
  formatClock,
  formatDate,
  formatDuration,
  LARGE_OUTPUT_BYTES,
  LARGE_OUTPUT_PREVIEW,
  pendingSortKey,
  previewOutput,
  relativeTime,
  riskLabel,
  sessionSubtitle,
  sortPending,
  speakable,
  toolStateIsProblem,
  toolStateLabel
} from './model/Present';
export type { OutputPreview } from './model/Present';

// ── 工作区与文件 ──
export {
  fileSummary,
  languageOf,
  NodeKind,
  PREVIEW_LIMIT_BYTES,
  PreviewKind,
  previewKindOf
} from './model/Workspace';
export type { FileNode, FilePreview, WorkspaceItem } from './model/Workspace';

// ── 设置 / 凭据 / 插件 / 设备 / 诊断 / 模型 ──
export {
  modelSelectionLabel,
  pluginSummary,
  SettingKind
} from './model/Settings';
export type {
  AboutInfo,
  ConnectionBanner,
  CredentialItem,
  DiagEntry,
  DiagReport,
  HostRecord,
  ModelOption,
  ModelSelection,
  PluginItem,
  SettingGroup,
  SettingItem
} from './model/Settings';

// ── 桩数据源（设备到位前驱动 UI；接入真实数据后只替换数据来源） ──
export { stubHost, stubPending, stubSessions, stubTrajectory } from './model/StubData';
export type { StubHostInfo } from './model/StubData';
export {
  stubAbout,
  stubCommands,
  stubCredentials,
  stubDetailSections,
  stubDiagnostics,
  stubFileTree,
  stubHosts,
  stubModelSelection,
  stubModels,
  stubPlugins,
  stubPreview,
  stubReferences,
  stubSettings,
  stubWorkspaces
} from './model/StubData2';
export type {
  CommandCandidate,
  DetailSection,
  ReferenceCandidate
} from './model/StubData2';

// ── 断点与导航模型 ──
export {
  detailPanelAvailable,
  layoutModeOf,
  navPresentation,
  NavPresentation,
  NavTab,
  navTabLabel,
  navTabSymbol,
  LayoutMode
} from './ui/Breakpoints';

// ── 设计令牌 ──
export { Breakpoint, Dur, Fs, Lh, Radius, SemanticColor, Sp, Sz } from './ui/Tokens';

// ── 会话中枢（D1 §7.7.5b：全应用单一连接池 + 单一会话状态机 + 单一待发队列） ──
export { HubPhase, projectWireRecord, SessionHub } from './store/SessionHub';
export type { HubSnapshot, HubSubscriber, OutboxEntry } from './store/SessionHub';

// ── 通知策略（D3 §6：六类通知的标题/正文/优先级/点击目标 + 内容纪律 + 去重键） ──
export {
  assertNoSensitiveContent,
  collapseWhitespace,
  DEFAULT_DETAIL_LIMIT,
  dedupeKeyOf,
  groupOf,
  inAppFallbackText,
  looksSensitive,
  NOTIFY_POLICIES,
  NotifyKind,
  notificationFor,
  NotifyTarget,
  policyOf,
  QUESTION_DETAIL_LIMIT,
  REDACTED,
  routeOf,
  sanitizeDetail,
  scrubCredentials,
  UNTITLED_SESSION,
  withdrawalKeysFor,
  withdrawalKeysForSession
} from './model/Notify';
export type { InAppNotice, NotifyInput, NotifyPolicy } from './model/Notify';

// ── 2in1 快捷键表（D3 §5.1：规范 11 行 → 13 个规格；数据 + 纯函数） ──
export {
  findShortcut,
  keyboardShortcutSpecs,
  keyEventSpecs,
  MODIFIER_LABEL,
  modifierLabel,
  SHORTCUTS,
  shortcutBindingLabel,
  ShortcutModifier,
  shortcutsForDesktop
} from './ui/Shortcuts';
export type { ShortcutSpec } from './ui/Shortcuts';

// ── 真实连接接线契约（请求构造器 + 回复投影；端点名一律来自 dshcompat） ──
export {
  approvalAnswer,
  ApprovalDecision,
  ApprovalOutcome,
  approvalOutcomeFor,
  APPROVAL_REQUEST_EVENT,
  ControlFrameType,
  cwdBasename,
  decisionIsClientSideOnly,
  eventResultArgs,
  eventResultEndpoint,
  filePart,
  fileUploadEndpoint,
  fileUploadPayload,
  FollowFrameType,
  followSessionAddress,
  followSubagentAddress,
  imagePart,
  isKnownProjectionKey,
  isWaterfallFrame,
  outcomeNext,
  outcomeRejected,
  outcomeResult,
  projectApprovalRequest,
  projectAskUserQuestionRequest,
  projectFileUpload,
  projectSessionCreate,
  projectSessionFork,
  projectSessionListWire,
  projectSessionPrompt,
  projectSessionRename,
  promptPayload,
  PromptMode,
  queueEditAction,
  queueRemoveAction,
  queueSteerAction,
  questionAnswer,
  questionAnswerItem,
  readControlFrame,
  readFollowFrame,
  readWaterfallFrame,
  resolveSessionTitle,
  sessionCancelPayload,
  sessionCreatePayload,
  sessionFollowPayload,
  sessionForkPayload,
  sessionListWirePayload,
  sessionRenamePayload,
  sessionUpdateQueuePayload,
  textPart,
  TitleSource,
  titleOfSummary,
  UNTITLED_SESSION as WIRE_UNTITLED_SESSION,
  USER_QUESTIONS_REQUEST_EVENT
} from './model/Wire';
export type {
  AskUserQuestionAnswer,
  AskUserQuestionAnswerItem,
  AskUserQuestionIntent,
  AskUserQuestionItem,
  AskUserQuestionOption,
  AskUserQuestionRequest,
  ApprovalAnswerValue,
  ApprovalRequestPayload,
  ControlBaseline,
  ControlFrame,
  EventResultArgs,
  FollowAssistantStreamFrame,
  FollowEventFrame,
  FollowFrame,
  FollowSessionAddress,
  FollowSnapshotFrame,
  FollowSubagentAddress,
  FileAttachmentRefValue,
  FileUploadRequest,
  FileUploadValue,
  OutcomeRejected,
  OutcomeResult,
  ProjectionHints,
  PromptContentPart,
  QueueActionBody,
  QueueTextBlock,
  SessionCancelRequest,
  SessionCancelValue,
  SessionCreateRequest,
  SessionCreateValue,
  SessionFollowRequest,
  SessionForkRequest,
  SessionForkValue,
  SessionHistoryRecord,
  SessionJob,
  SessionListRequest,
  SessionListValue,
  SessionPromptRequest,
  SessionPromptValue,
  SessionQueuedItem,
  SessionRenameRequest,
  SessionRenameValue,
  SessionSummaryWire,
  SessionUpdateQueueRequest,
  SessionWireEvent,
  SessionWireHeader,
  TitleResolution,
  WaterfallFrame,
  WireError
} from './model/Wire';
