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
