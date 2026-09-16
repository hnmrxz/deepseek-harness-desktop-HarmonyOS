/**
 * 状态层对外入口（HAR 模块 appstate）。
 *
 * 上层（entry 页面与视图）只应通过本入口导入。
 */

// ── 会话列表 ──
export { isSubagentSession, projectSessionList, sessionListEndpoint } from './model/SessionList';
export type { SessionListItem, SessionListPage } from './model/SessionList';

// ── 轨迹与待决的呈现层契约 ──
export {
  APPROVAL_CHOICE_ALLOW,
  APPROVAL_CHOICE_DENY,
  PendingKind,
  RiskLevel,
  Speaker,
  ToolState,
  TrajectoryKind,
  indexOfItem,
  makeItem,
  mergeTrajectoryItem,
  retryItemId,
  RETRY_STATE_CANCELLED,
  RETRY_STATE_SCHEDULED,
  RETRY_STATE_STARTED,
  itemsOfKind,
  deliverablesOf
} from './model/Trajectory';
export type { PendingChoice, PendingItem, TrajectoryItem } from './model/Trajectory';

// ── 呈现层纯函数 ──
export {
  formatBytes,
  formatClock,
  formatDate,
  formatDuration,
  LARGE_OUTPUT_PREVIEW,
  pendingSortKey,
  previewOutput,
  relativeTime,
  RETRY_DELAY_LABEL,
  RETRY_FAILURE_LABEL,
  RETRY_LABEL_ACTIVE,
  RETRY_LABEL_CANCELLED,
  RETRY_LABEL_SCHEDULED,
  RETRY_LABEL_STARTED,
  retrySecondsOf,
  retryStatusLine,
  riskLabel,
  sortPending,
  toolStateLabel
} from './model/Present';
export type { OutputPreview } from './model/Present';
// 失败码 → 用户文案（P7-19：把散在中枢里的特例与兜底收成一张可对账的表）
export { failureText, hasFailureText, untranslatedFailure, CLIENT_FAILURE_TEXT_TABLE, FAILURE_TEXT_TABLE, REACHABLE_FAILURE_CODES } from './model/FailureText';
export type { FailureTextEntry } from './model/FailureText';
// 目标栏的可判定状态（P7-20，对齐官方 ui-goal 的 GoalBar）
export { goalBarStateOf, goalPhaseLabel, GOAL_PHASE_ACTIVE, GOAL_PHASE_BLOCKED, GOAL_PHASE_COMPLETE, GOAL_PHASE_PAUSED } from './model/GoalBar';
export type { GoalBarState } from './model/GoalBar';
// 回合产出的文件（P7-21，对齐官方 ui-deliverables 的 turn-tail 规则）
export {
  baseNameOf,
  deliverableShareTarget,
  MENTION_TOKEN_MAX,
  changeStatText,
  producedFilesOf,
  turnChangeStatOf,
  producedRowText,
  resolveProducedMention,
  SHARE_TARGET_FILE,
  SHARE_TARGET_NONE,
  SHARE_TARGET_TEXT,
  shareActionLabel
} from './model/ProducedFiles';
export type { ShareTarget } from './model/ProducedFiles';
export type { ProducedFile, TurnChangeStat } from './model/ProducedFiles';

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
/** E132：工作区注册表行（带 workspaceId；声明在 SessionHub，这里对外转出） */
export type { WorkspaceRow } from './store/SessionHub';
/** E160：Agent 预设名单行与其"随附只读"判定 */
export type { AgentPresetRow } from './store/SessionHub';
/** E253：消息反馈行（供界面按 messageId 取用） */
export type { FeedbackCategory, FeedbackRow } from './store/SessionHub';
export { presetIsBundled } from './store/SessionHub';
/** E135：技能清单行 */
export type { SkillRow } from './store/SessionHub';
/** E145：结构化操作回执（中枢产出码+参数，视图层本地化） */
export type { ActionNotice } from './store/SessionHub';

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
  projectGeneralGroups,
  GENERAL_NAMESPACES,
  projectSettingsNamespace,
  parseSettingInput,
  parseStructInput,
  SettingKind,
  SettingOrigin,
  SettingValueType,
  DEFAULT_MODEL_NS,
  settingsDomainOfNs,
  settingsMutateArgs,
  settingsUnsetArgs,
  splitSettingKey,
  SettingsWriteOutcome
} from './model/Settings';
export { sessionContextLine, workspaceNameOf } from './model/SessionContext';
// 轨迹条目的事件详情（P7-4，对齐官方 details.* 的字段对）
export { TRAJECTORY_DETAIL_TITLE, INTERNAL_BODY_HIDDEN_PREFIX, itemKindLabel, trajectoryDetailRows } from './model/TrajectoryDetail';
export type { DetailRow } from './model/TrajectoryDetail';
// 应用内隐私与权限说明（P7-11；与 module.json5 由 tools/check-compliance.mjs 对账）
export { DATA_PRACTICES, PERMISSION_DISCLOSURES, PRIVACY_STATEMENT_DATE, PRIVACY_STATEMENT_VERSION, privacySummaryLine } from './model/PrivacyDisclosure';
export type { PermissionDisclosure, PrivacyPoint } from './model/PrivacyDisclosure';
// 消息图片的几何判定（P0-3，对齐官方 ui-attachment 的 singleFit / 64px tile 规则）
export {
  galleryVariantOf,
  hiddenImageCount,
  IMAGE_GALLERY_GAP,
  IMAGE_GALLERY_MAX,
  IMAGE_MIN_HIT,
  IMAGE_RATIO_MAX,
  IMAGE_RATIO_MIN,
  SINGLE_IMAGE_BOX,
  singleImageFit,
  TILE_IMAGE_SIDE,
  visibleImageCount,
  IMAGE_CLOSE_PREVIEW,
  IMAGE_OPEN_ORIGINAL,
  IMAGE_PREVIEW_DIALOG,
  imageOpenOriginalLabel,
  LIGHTBOX_MAX_WIDTH,
  LIGHTBOX_PADDING,
  lightboxFit
} from './model/MessageImage';
export type { SingleImageFit } from './model/MessageImage';
// 输入区附件的判定与拼装（P0-4：图片内联、官方顺序与类型白名单）
export {
  AttachmentKind,
  attachmentPlanFor,
  formatBytesOf,
  hasInlineImage,
  imageDraftRejection,
  MAX_INLINE_IMAGE_BYTES,
  resolveImageMediaType,
  sniffImageMediaType,
  SUPPORTED_IMAGE_TYPES
} from './model/InputAttachment';
export type { AttachmentDraftInput, AttachmentPartPlan } from './model/InputAttachment';
// 输入触发管线（P7-14：`@` 引用与 `/` 命令的词法——识别 token、替换而不是追加）
export {
  COMMAND_PICK_DRAFT,
  COMMAND_PICK_RUN,
  REFERENCE_CRUMB_ROOT,
  REFERENCE_NO_CWD,
  referenceAgeLine,
  referenceAgeText,
  referenceCrumbs,
  referenceDrillQuery,
  referenceFileRowDetail,
  referenceFileRowName,
  referenceQueryOf,
  referenceSessionRowDetail,
  TriggerKind,
  appendPick,
  applyPick,
  commandDraftText,
  commandInputNotice,
  commandNeedsInput,
  commandPickAction,
  detectTrigger,
  needsTrailingSpace
} from './model/InputTrigger';
export type { TriggerToken } from './model/InputTrigger';
// 提交失败后的草稿恢复规则（P7-15，对齐官方 sink 的 "restored only while untouched"）
export { shouldRestoreDraft } from './model/ComposerSend';

// 权限预设的呈现与切换规则（P7-6，对齐官方 permission-presets）
export { PERMISSION_UNAVAILABLE, PERMISSION_UNSET, permissionChipLabel, permissionChoices, permissionCommand, permissionSwitchable, permissionUnavailableHint } from './model/Permissions';
export type { PermissionChoice } from './model/Permissions';
// 提问组（P7-5）：整组题目 + 逐题草稿 + 官方提交拦阻文案
export { answerableDrafts, draftAnswered, encodeQuestionAnswers, parseOptionLabel, planReviewOf, questionIndexStep, questionNavLabel, submitBlockedText } from './model/Trajectory';
export type { OptionLabelDisplay, PendingAnswerDraft, PendingQuestion, PlanReview, QuestionAnswerPayload } from './model/Trajectory';
// 会话搜索（官方 sidebar 的 search：Host 内容命中 + 本地标题命中合并成扁平结果）
// 输入区接管的焦点规则（P7-2，对齐官方 approval/user-questions 的 composer takeover）
export { pendingElsewhere, pendingForSession, takeoverCommand, takeoverHeadline, takeoverStripText } from './model/PendingFocus';

export { SESSION_SEARCH_LIMIT, localOnlySearchNote, mergeSessionSearch } from './model/SessionSearch';
export type { SessionSearchHit, SessionSearchLocal, SessionSearchRow } from './model/SessionSearch';
export {
  SHEET_NOTE_CREDENTIAL,
  SHEET_NOTE_NONE,
  SHEET_NOTE_STRUCT,
  SHEET_NOTE_TEXT,
  sheetDiscardNotice,
  sheetNoteText,
  sheetNoteVisible
} from './model/Sheets';
export { placeholderOf, structSettingEditorHints, textSettingEditorHints } from './model/SettingEditors';
export type { EditorHints } from './model/SettingEditors';
export type {
  AboutInfo,
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

// ── 错误状态的生命周期（P8-6c：连上了才清连接级，动作成了就清动作级） ──
export {
  ERROR_SCOPE_ACTION,
  ERROR_SCOPE_CONNECTION,
  ERROR_TRIGGER_CONNECTED,
  ERROR_TRIGGER_PROMPT_ACCEPTED,
  ERROR_TRIGGER_TURN_ENDED_OK,
  errorClearedBy,
  errorIsConnectionLevel
} from './model/ErrorLifecycle';

// ── 每会话输入草稿（P8-3：草稿是**会话视图状态的一部分**，官方 views.d.ts 逐字） ──
export {
  COMPOSER_DRAFT_MAX,
  draftCount,
  draftOf,
  dropDraft,
  emptyComposerDrafts,
  parseDrafts,
  putDraft,
  serializeDrafts
} from './model/ComposerDrafts';
export type { ComposerDrafts } from './model/ComposerDrafts';
// 诊断模式（D7 §3 第 4 项）：本地核心 / 远程 Host 分流
export { DiagMode, diagHintOf, diagModeOf, diagTitleOf, filterDiagEntries } from './model/Diag';

// ── 会话内搜索（D3 §5.1 的 Ctrl/Cmd + F） ──
export {
  chatRowOfItemIndex,
  matchConversationIndices,
  matchCounterText,
  matchTrajectoryIndices,
  stepMatch
} from './model/Search';

// ── 详情栏分区（从真实轨迹派生，D3 §3.6） ──
export { projectDetailSections } from './model/Detail';
export type { DetailSection } from './model/Detail';

// ── 端侧核心的呈现契约（D6 §2/§6）：阶段、运行时事实、版本行、插件分类、动作可用性 ──
export {
  CorePhase,
  PluginNative,
  buildCoreView,
  classifyPlugin,
  corePhaseLabel,
  corePhaseOfHostState,
  fact,
  pluginNativeOf,
  sessionEmptyCopy,
  unknownFact,
  emptyCoreView
} from './model/Core';
export type {
  CoreActionSpec,
  CoreFact,
  CoreVersionRow,
  CoreViewInput,
  CoreViewState,
  EmptyCopy,
  PluginRow
} from './model/Core';

// ── 核心页投影（宿主报告的结构子集 → 事实与行） ──
export { pluginInventoryFact, pluginRowOf, rankPluginRows } from './model/CoreProjection';
export type { PluginInventoryTotals } from './model/CoreProjection';

// ── 断点与导航模型 ──
export {
  detailPanelAvailable,
  layoutModeOf,
  navPresentation,
  NavPresentation,
  NavTab,
  LayoutMode,
  settingsSectionLabelRes,
  sidebarPanelLabelRes,
  sidebarPanelSymbol
} from './ui/Breakpoints';

// ── 设计令牌 ──
export { Border, Breakpoint, Dur, Fs, Lh, Radius, SemanticColor, Sp, Sz } from './ui/Tokens';

// ── 工具呈现（P2 §11：按工具类别区分呈现；纯函数，可本机直接测） ──
export {
  presentTool,
  toolA11y,
  toolDefaultExpanded,
  ToolKind,
  toolKindLabel,
  toolKindOf,
  toolSummaryOf,
  toolToneOf
} from './model/ToolPresentation';
export { parseMarkdown, parseInline, plainTextOf, MdBlock, MdBlockKind, MdSpan } from './model/Markdown';
export type { ToolPresentation } from './model/ToolPresentation';

// ── 改动对照（P2 §11：编辑类工具出"改了什么"；纯函数，可本机直接测） ──
export { collapseContext, diffLines, diffStatOf, DiffLineKind, intendedDiffOf, presentDiff } from './model/ToolDiff';
export type { DiffLine, DiffPresentation, DiffStat, ToolDiff } from './model/ToolDiff';

// ── 输入模态策略（P1/P3：触控+鼠标+键盘同一套语义；纯函数，可本机直接测） ──
export { contextMenuGestures, contextMenuHintLabel, hoverEnabled, MenuGesture } from './model/InputPolicy';
export type { InputModality } from './model/InputPolicy';

// ── 页面框架：面板注册表与导航状态（P0：官方信息架构对齐；纯逻辑，可本机直接测） ──
export {
  createPanelRegistry,
  PanelLocation,
  PanelRegistry,
  rightbarPanels,
  sidebarPanels,
  sidebarEntries,
  sidebarPinnedEntries,
  SIDEBAR_PINNED_ORDER,
  settingsSections,
  PANEL_RIGHT_DELIVERABLES,
  PANEL_RIGHT_DETAIL,
  PANEL_RIGHT_FILES,
  PANEL_RIGHT_PREVIEW,
  PANEL_RIGHT_SUBAGENT,
  PANEL_RIGHT_TOOL,
  PANEL_RIGHT_TRAJECTORY,
  PANEL_SIDEBAR_CORE,
  PANEL_SIDEBAR_SETTINGS,
  PANEL_SIDEBAR_WORKSPACES
} from './model/PanelRegistry';
export type { PanelDescriptor } from './model/PanelRegistry';
export {
  activeMainPanelOf,
  mainPanelOfSidebarPanel,
  sidebarPanelOfMainPanel,
  copyOf,
  defaultRightPanel,
  DrawerState,
  enterSession,
  initialNavigationState,
  legacyTabOfMainPanel,
  mainPanelOfLegacyTab,
  mainPanels,
  navigateToMain,
  openSettings,
  selectRightPanel,
  setDrawer,
  sidebarPanelIdOfTab,
  MAIN_CONNECT,
  MAIN_CONVERSATION,
  MAIN_CORE,
  MAIN_DIAGNOSTICS,
  MAIN_SETTINGS,
  MAIN_WORKSPACES,
  SETTINGS_GENERAL,
  SETTINGS_MODELS
} from './model/NavigationState';
export type { NavigationState } from './model/NavigationState';

// ── 三条轨道在四形态下的呈现（P0：AppFrame 的几何层） ──
export {
  shellTracksOf,
  sidebarExpandedForMode,
  sidebarPresentationOf,
  sidebarTrackWidthOf,
  TrackPresentation
} from './ui/ShellTracks';
export type { ShellTracks } from './ui/ShellTracks';

// ── 后台任务（P2：会话头部的任务注册表；纯函数，可本机直接测） ──
export {
  jobCountLabel,
  jobDotState,
  jobDurationText,
  jobDurationTitle,
  jobElapsedMs,
  jobIsLive,
  jobListA11y,
  jobListVisible,
  jobRowStatusText,
  jobStatusLabel,
  jobTickerNeeded,
  liveJobCount,
  orderedJobs,
  JobDot
} from './model/Jobs';

// ── 轨迹时间线（P2 §11：交互式时间总览；纯函数，可本机直接测） ──
export {
  cellIdAtRatio,
  cellIdForListIndex,
  listIndexForCell,
  segmentOrdinalOf,
  statsLinesOf,
  timelineCellsOf,
  timelineKindLabel,
  timelineKindOf,
  timelineScaleOf,
  timelineStartedLabel,
  timelineTotalLabel,
  TimelineKind,
  StatsUnit
} from './model/Timeline';
export type { SessionStatsInput, StatsLine, TimelineCell, TimelineScale, TimelineSegment } from './model/Timeline';

// ── 输入模态事实（P3：形态猜测 / 系统枚举 / 事件证据三者按优先级合成；纯函数，可本机直接测） ──
export {
  flattenSources,
  guessFromKeyboardForm,
  modalityFromSources,
  modalityOf,
  modalityTrace,
  noModality,
  sourceIsKeyboard,
  sourceIsPointer,
  unionModality
} from './model/InputFacts';
export type { ModalityEvidence } from './model/InputFacts';

// ── 贴底跟随模型（P1 §8：sticky-follow 独立管理；纯函数，可本机直接测） ──
export {
  emptyScrollSpot,
  followTimerShouldRun,
  FollowSignal,
  nextFollowing,
  rememberScrollSpot,
  scrollRestoreTarget,
  shouldJumpOnNewItems
} from './model/Follow';
export type { ScrollSpot } from './model/Follow';

// ── 回合模型（P1 §8：Turn → ProcessGroup + Answer；纯函数，可本机直接测） ──
export {
  chatVisibleItems,
  conversationAudienceOf,
  ConversationAudience,
  defaultExpanded,
  groupTurns,
  hasProcessGroup,
  needsInternalIsolation,
  processSummary,
  userFacingBodyOf
} from './model/Turns';
export type { Turn } from './model/Turns';
export type { SessionJob } from './model/Jobs';

// ── HarmonyTheme（P1.5：Web 语义 → HarmonyOS 视觉的映射层） ──
export {
  HarmonyBorder,
  HarmonyColor,
  HarmonyElevation,
  HarmonyIconSize,
  HarmonyMotion,
  HarmonyRadius,
  HarmonySpacing,
  HarmonyTouch,
  HarmonyType,
  WEB_TOKEN_MAP
} from './ui/HarmonyTheme';
export type { ShadowLevel, TypeRole, WebTokenMapping } from './ui/HarmonyTheme';

// ── 布局决策（P1：形态/几何决策的唯一落点，见 LayoutController 的说明） ──
export {
  clampDetailDesired,
  concedeDetail,
  decideLayout,
  decideLayoutWithDetail,
  detailPresentationOf,
  detailRoomOf,
  detailWidthOf,
  dragDetailWidth,
  DetailPresentation,
  MAIN_MIN_VP,
  navWidthOf,
  ConcessionStep
} from './ui/LayoutController';
export type { DetailCapacity, LayoutDecision, LayoutInput } from './ui/LayoutController';

// ── 导航状态机（P1：返回键优先级阶梯与页签归一化，见 NavigationController 的说明） ──
export {
  BackAction,
  decideBack,
  drillAfterPreviewClosed,
  navTabs,
  normalizeTab,
  selectTab,
  showsConversation,
  StackPage
} from './ui/NavigationController';
export type { NavState, OverlayState, TabSelection } from './ui/NavigationController';

// ── 会话中枢（D1 §7.7.5b：全应用单一连接池 + 单一会话状态机 + 单一待发队列） ──
export {
  FEEDBACK_CATEGORIES,
  HubPhase,
  projectWireRecord,
  SessionHub,
  notice,
  noticeWith,
  put
} from './store/SessionHub';
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
  DEFAULT_DETAIL_LIMIT,
  dedupeKeyOf,
  groupOf,
  NOTIFY_POLICIES,
  NOTIFY_PAGES,
  NotifyKind,
  notificationFor,
  notifyInputForPending,
  notifyInputForTurn,
  NotifyTarget,
  parseNotifyRoute,
  policyOf,
  QUESTION_DETAIL_LIMIT,
  routeOf,
  sanitizeDetail,
  UNTITLED_SESSION,
  withdrawalKeysFor,
  withdrawalKeysForPending
} from './model/Notify';
export type { NotifyInput, NotifyPolicy } from './model/Notify';

// ── 内容脱敏（P8-5：所有用户可达出口共用的唯一真值；零依赖，故 fixture 可直接执行） ──
export {
  collapseWhitespace,
  looksSensitive,
  REDACTED,
  scrubCredentials,
  SENSITIVE_PATTERNS
} from './model/Redact';

// ── 2in1 快捷键表（D3 §5.1：规范 11 行 → 13 个规格；数据 + 纯函数） ──
export {
  findShortcut,
  keyboardShortcutSpecs,
  keyEventSpecs,
  SHORTCUTS,
  ShortcutModifier,
  shortcutsForDesktop
} from './ui/Shortcuts';
export type { ShortcutSpec } from './ui/Shortcuts';

// ── 真实连接接线契约（请求构造器 + 回复投影；端点名一律来自 dshcompat） ──
export {
  APPROVAL_REQUEST_EVENT,
  authorityOfUrl,
  basenameOf,
  commandsListEndpoint,
  commandsListPayload,
  ControlFrameType,
  cwdBasename,
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
  USER_QUESTIONS_REQUEST_EVENT,
  workspaceListEndpoint,
  workspaceListPayload,
  workspaceReadAllEndpoint,
  workspaceReadAllPayload,
  projectWorkspaceBytes,
  workspaceReadEndpoint,
  workspaceReadPayload,
  WORKSPACE_ROOT_REQUEST_PATH,
  UNTITLED_SESSION as WIRE_UNTITLED_SESSION
} from './model/Wire';
export type {
  AskUserQuestionAnswer,
  AskUserQuestionAnswerItem,
  AskUserQuestionIntent,
  AskUserQuestionItem,
  AskUserQuestionOption,
  AskUserQuestionRequest,
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
  ImageAttachmentRefValue,
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
  WorkspaceTextWire,
  questionCancelledError
} from './model/Wire';
