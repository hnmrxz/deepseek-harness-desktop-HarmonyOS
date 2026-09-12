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
  APPROVAL_CHOICE_ALLOW,
  APPROVAL_CHOICE_ALLOW_ALWAYS,
  APPROVAL_CHOICE_DENY,
  PendingKind,
  RiskLevel,
  Speaker,
  ToolState,
  TrajectoryKind,
  indexOfItem,
  makeItem,
  mergeTrajectoryItem
} from './model/Trajectory';
export type {
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
  humanizeKey,
  mergeSettingsGroups,
  modelSelectionLabel,
  pluginSummary,
  projectCredentials,
  projectCredentialRefs,
  projectDefaultSelection,
  projectModelCatalog,
  projectPluginInventory,
  projectSettingsEntries,
  projectSettingsGroups,
  projectSettingsNamespace,
  parseSettingInput,
  parseStructInput,
  SettingKind,
  SettingOrigin,
  SettingValueType,
  SettingsWriteOutcome,
  settingsMutateArgs,
  settingsUnsetArgs,
  splitSettingKey
} from './model/Settings';
export type {
  AboutInfo,
  ConnectionBanner,
  CredentialItem,
  CredentialWriteResult,
  DiagEntry,
  DiagReport,
  HostRecord,
  ModelOption,
  ModelSelection,
  PluginItem,
  SettingChoice,
  SettingGroup,
  SettingItem,
  SettingInputResult,
  SettingsGroupEntry,
  SettingsKeyParts,
  SettingsNamespaceItems,
  SettingsNamespaceState,
  SettingsWriteResult
} from './model/Settings';

// ── 「关于」与诊断空态（**不是桩数据**：全部从 dshcompat 实时派生） ──
export { aboutInfo } from './model/StubData2';
export { emptyDiagReport } from './model/Diag';

// ── 会话内搜索（D3 §5.1 的 Ctrl/Cmd + F） ──
export { matchCounterText, matchTrajectoryIndices, stepMatch } from './model/Search';

// ── 详情栏分区（从真实轨迹派生，D3 §3.6） ──
export { projectDetailSections } from './model/Detail';
export type { DetailSection } from './model/Detail';

// ── 端侧核心的呈现契约（D6 §2/§6）：阶段、运行时事实、版本行、插件分类、动作可用性 ──
export {
  CorePhase,
  buildCoreView,
  classifyPlugin,
  corePhaseLabel,
  corePhaseOfHostState,
  emptyCoreView,
  fact,
  sessionEmptyCopy,
  unknownFact
} from './model/Core';
export type { CoreActionSpec, CoreFact, CoreVersionRow, CoreViewInput, CoreViewState, EmptyCopy, PluginRow } from './model/Core';

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
export type {
  AttachOutcome,
  HubSnapshot,
  HubSubscriber,
  NotifyHooks,
  OutboxEntry,
  PendingAttachment
} from './store/SessionHub';

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
  NOTIFY_PAGES,
  NotifyKind,
  notificationFor,
  notifyInputForConnection,
  notifyInputForPending,
  notifyInputForTurn,
  NotifyTarget,
  parseNotifyRoute,
  policyOf,
  QUESTION_DETAIL_LIMIT,
  REDACTED,
  routeOf,
  sanitizeDetail,
  scrubCredentials,
  UNTITLED_SESSION,
  withdrawalKeysFor,
  withdrawalKeysForPending,
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
  authorityOfUrl,
  basenameOf,
  commandsListEndpoint,
  commandsListPayload,
  ControlFrameType,
  cwdBasename,
  decisionIsClientSideOnly,
  eventResultArgs,
  eventResultEndpoint,
  filePart,
  fileReferencesEndpoint,
  fileReferencesPayload,
  fileUploadEndpoint,
  fileUploadPayload,
  FollowFrameType,
  followSessionAddress,
  followSubagentAddress,
  hostOfUrl,
  imagePart,
  isKnownProjectionKey,
  isLoopbackUrl,
  isWaterfallFrame,
  normalizePathKey,
  outcomeNext,
  outcomeRejected,
  outcomeResult,
  projectApprovalRequest,
  projectAskUserQuestionRequest,
  projectCommands,
  projectFileReferences,
  projectFileUpload,
  projectHosts,
  projectSessionCreate,
  projectSessionFork,
  projectSessionListWire,
  projectSessionPrompt,
  projectSessionReferences,
  projectSessionPage,
  sessionCursorOf,
  sessionPageEndpoint,
  sessionPagePayload,
  projectQueuedItems,
  queuedItemsOf,
  projectSessionRename,
  projectWorkspaceListing,
  projectWorkspaces,
  projectWorkspaceText,
  projectWorkspaceFailure,
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
  sessionReferencesEndpoint,
  sessionReferencesPayload,
  sessionRenamePayload,
  sessionUpdateQueuePayload,
  textPart,
  TitleSource,
  titleOfSummary,
  UNTITLED_SESSION as WIRE_UNTITLED_SESSION,
  USER_QUESTIONS_REQUEST_EVENT,
  workspaceListEndpoint,
  workspaceListPayload,
  workspaceReadAllEndpoint,
  workspaceReadAllPayload,
  projectWorkspaceBytes,
  workspaceReadEndpoint,
  workspaceReadPayload,
  WORKSPACE_ROOT_REQUEST_PATH
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
  CommandCandidate,
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
  HostProjectionInput,
  OutcomeRejected,
  OutcomeResult,
  ProjectionHints,
  PromptContentPart,
  QueueActionBody,
  QueuedItem,
  QueueTextBlock,
  ReferenceCandidate,
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
  SessionPageRequest,
  SessionPageValue,
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
  WireError,
  WorkspaceEntryWire,
  WorkspaceBytesWire,
  WorkspaceFileRange,
  WorkspaceListingProjection,
  WorkspaceListingWire,
  WorkspaceTextWire
} from './model/Wire';
