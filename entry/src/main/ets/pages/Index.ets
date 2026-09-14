/**
 * 应用首屏：三形态导航 + 让步链 + 全部页面装配（D3 §2 / §1）。
 *
 * 形态（按**窗口宽度**判定，D3 §2.2 硬规则）：
 *   单栏 SINGLE（< 600vp，手机 / 折叠态）  ：内容区 + 底部标签栏；会话栈式下钻
 *   双栏 DOUBLE（600–839vp，折叠展开 / 平板竖屏）：左侧图标条 + 内容区
 *   三栏 TRIPLE（>= 840vp，平板横屏 / 2in1）    ：导航面板 + 主区 + 详情栏
 *
 * 让步链（D3 §2.1）：详情栏收窄 → 详情栏关闭 → 导航收为图标条 → 导航抽屉化。
 * 让步只改几何、不改数据；变宽时自行恢复。
 *
 * 页面装配（D3 §1 信息架构全覆盖）：
 *   待决 / 会话（+轨迹+输入区+详情栏）/ 工作区（工作区→文件树→预览）/
 *   设置（通用·模型·凭据·插件·设备）/ 连接诊断 / 添加 Host
 *
 * 数据全部来自 `SessionHub`（真实连接）或**空态**。这里**不再有任何桩数据**：
 * 桩数据曾把「功能没接上」伪装成「功能正常」，也曾在设备页编造一条
 * 「本机 Host · 已授权」——那是安全陈述，编造它比空列表危险得多。
 */

import { display, router, window } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  checkVersion,
  emptyProbeTable,
  SURFACE,
  tableStats
} from 'dshcompat';
import type { VersionCheck } from 'dshcompat';
import type { DiagnosticItem, DiagnosticReport } from 'connection';
import { applyThemeMode, copyText, LocalPrefs, PickOutcome, pickDocument, pickFolder, localizedOr, themeModeOf } from 'platform';
import type { NotifyRoute, PickedFile, PickedFolder } from 'platform';
import { common } from '@kit.AbilityKit';
import {
  APPROVAL_CHOICE_ALLOW_ALWAYS,
  APPROVAL_CHOICE_DENY,
  CommandCandidate,
  CredentialItem,
  DetailSection,
  DiagEntry,
  DiagReport,
  FileNode,
  FilePreview,
  Fs,
  HostRecord,
  HubPhase,
  BackAction,
  decideBack,
  HarmonyColor,
  HarmonyRadius,
  HarmonySpacing,
  HarmonyType,
  LayoutMode,
  decideLayout,
  navTabs,
  selectTab as decideTabSelection,
  showsConversation,
  StackPage,
  ModelOption,
  ModelSelection,
  NavTab,
  navTabLabel,
  navTabSymbol,
  PendingItem,
  PendingAttachment,
  PluginItem,
  QueuedItem,
  Radius,
  ReferenceCandidate,
  SessionListItem,
  SettingGroup,
  SettingKind,
  SettingOrigin,
  SettingValueType,
  SettingsWriteOutcome,
  parseSettingInput,
  parseStructInput,
  parseNotifyRoute,
  Sp,
  aboutInfo,
  buildCoreView,
  classifyPlugin,
  CoreFact,
  CorePhase,
  CoreViewState,
  corePhaseOfHostState,
  emptyCoreView,
  emptyDiagReport,
  DiagMode,
  diagHintOf,
  diagModeOf,
  diagTitleOf,
  filterDiagEntries,
  fact,
  sessionEmptyCopy,
projectGeneralGroups,
formatClock,
relativeTime,
  unknownFact,
  mergeSettingsGroups,
  normalizePathKey,
  projectDetailSections,
  projectHosts,
  projectWorkspaces,
  pluginNativeOf,
  PluginNative,
  SessionHub,
  Sz,
  TrajectoryItem,
  WorkspaceItem,
  WorkspaceRow,
  SkillRow,
  AgentPresetRow,
  ActionNotice
} from 'appstate';
/**
 * 类型单独用 `import type` 引入。
 *
 * 原因：`HubSnapshot` / `HubSubscriber` 在 appstate 里是 `export type` 导出的类型，
 * 与值导入分开写更贴近 ArkTS 的类型/值导入区分。
 */
import type {
  AttachOutcome,
  NavState,
  OverlayState,
  TabSelection,
  LayoutDecision,
  LayoutInput,
  CredentialWriteResult,
  HubSnapshot,
  HubSubscriber,
  PluginRow,
  SettingChoice,
  SettingInputResult,
  SettingItem,
  SettingsNamespaceState,
  SettingsWriteResult
} from 'appstate';
import { emitter } from '@kit.BasicServicesKit';
import { extractToken, parseJson } from 'connection';
import { EVENT_HOST_CONNECTED, EVENT_KEY_HOST_TOKEN, EVENT_KEY_HOST_URL } from 'platform';
import { ConnectPane } from '../view/ConnectPane';
import { ConversationPane } from '../view/ConversationPane';
import { CorePane } from '../view/CorePane';
import { DetailPane } from '../view/DetailPane';
import { DiagnosticsPane } from '../view/DiagnosticsPane';
import { PendingPane } from '../view/PendingPane';
import { NodeRuntime } from '../runtime/NodeRuntime';
import { SessionListPane } from '../view/SessionListPane';
import { SettingsPane } from '../view/SettingsPane';
import { WorkspacePane } from '../view/WorkspacePane';
import { hitOfKeyEvent } from '../view/ShortcutKeys';
import type { ShortcutHit } from '../view/ShortcutKeys';
import { harmonySheetOptions, NativeSectionTitle } from '../view/NativePrimitives';
// 端侧核心运行层（D6）：核心版本仓库与激活事务。运行时载体尚未接线，
// 因此这里现在只用它的"仓库/状态"部分，不声称任何"已启动"。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ActivationAction, ActivationDecision, BundledInstallResult, DshHost, HostPluginReport, HostStartResult, HostStatus, OpResult, RuntimeProbe, hostStateIsTransient } from 'hostruntime';

/**
 * 把紧凑 JSON 美化以便人读写；失败时原样返回。
 *
 * 【为什么要自己缩进而不是用 `JSON.stringify(v, null, 2)`】整值编辑的对象是
 * **已经解析过的文本**，而 `JSON.stringify` 的缩进参数只对「对象」生效——
 * 我们手上是字符串，必须先 parse。失败（旧数据里存了非法 JSON）时原样返回，
 * 让用户在编辑器里直接看到原文并自己修，而不是显示一个空白框。
 */
function prettyJson(compact: string): string {
  if (compact.length === 0) {
    return '';
  }
  const parsed: Object | undefined = parseJson(compact);
  if (parsed === undefined) {
    return compact;
  }
  return JSON.stringify(parsed, null, 2) ?? compact;
}

/**
 * 把「刚刚连上的 Host」报告给能力层，由它落盘（地址明文、token 加密）。
 *
 * 【为什么页面不自己存】页面拿不到 `UIAbilityContext`（`preferences` / Asset Store
 * 都需要它），而且「零 UI 依赖」是本工程的纪律——视图层不该认识存储细节。
 * 页面只报告事实，怎么记由能力层决定。
 *
 * 【为什么只报告成功的连接】失败的地址/token 不该被记住：否则下次启动会拿一个
 * 已知无效的 token 去自动重连，用户看到「自动重连失败」；而正确行为是回到「添加 Host」。
 */
function reportConnectedHost(baseUrl: string, token: string): void {
  if (baseUrl.length === 0) {
    return;
  }
  const payload: Record<string, Object> = {};
  payload[EVENT_KEY_HOST_URL] = baseUrl;
  payload[EVENT_KEY_HOST_TOKEN] = token;
  emitter.emit({ eventId: EVENT_HOST_CONNECTED }, { data: payload });
}

/**
 * 把 connection 的真实诊断报告投影成诊断页的呈现模型。
 *
 * 【为什么不在这里再跑一次版本判定】`Connection.diagnose()` 已经产出
 * 「端点 / TLS / 认证 / 协议 / Host」五项判定，**其中就包含 Host 版本判定**。
 * 在这里用 `checkVersion()` 再算一次不但重复，还需要一份运行时 `ProbeTable`——
 * 而那份探测结果正是 connection 内部的产物，从外面拿不到，硬凑只会得到错误结论。
 * 因此这里只做两件事：
 *   1. 逐项搬运**已实测**的判定；
 *   2. 附上 `dshcompat` 的**静态兼容面事实**（受支持版本矩阵、上表规模）——
 *      UI 不得自行拼写上游版本号或端点名（D5 §1）。
 */
function projectDiagnostics(report: DiagnosticReport): DiagReport {
  const entries: DiagEntry[] = [];
  for (let i = 0; i < report.items.length; i++) {
    const item: DiagnosticItem = report.items[i];
    entries.push({
      name: item.name,
      passed: item.passed,
      detail: item.detail,
      advice: item.advice === undefined ? '' : item.advice
    });
  }
  const stats = tableStats();
  // 版本判定走 `dshcompat.checkVersion`，**不能**把「受支持矩阵」当成判定结论：
  // 诊断页按 `versionVerdict` 的三态（supported/unverified/incompatible）分支渲染，
  // 塞进一个版本号字符串会让三个分支**全部落空**——界面既没有图标也没有文案，
  // 而它看起来只是「这里没内容」，比报错更难发现。
  //
  // 这里传空版本号是**如实**的：上游没有任何端点或帧给出 Host 核心包版本
  // （`$events` 的 ready 帧实测只有 clientId 与 host.home，D2 §8.7.12），
  // 所以结论必然是 unverified，且必须把原因写清楚。
  const verdict: VersionCheck = checkVersion('', emptyProbeTable());
  return {
    entries: entries,
    healthy: report.healthy,
    generatedAt: report.generatedAt,
    versionVerdict: verdict.verdict,
    versionMessage: verdict.message,
    versionAdvice: verdict.advice,
    tableStats: `${stats.endpoints} 个端点 / ${stats.streamEndpoints} 个流式 / ${stats.capabilities} 个能力`,
    // 接口面必须来自载体常量：写死字符串会在上游改路径后继续显示旧路径，
    // 而这一行正是用来判断「是不是漏注入/走错路由」的。
    surface: `${SURFACE.apiChannel} · ${SURFACE.muxPath} · ${SURFACE.eventsEndpoint}`
  };
}

/**
 * 应用名（**唯一来源**）。
 *
 * 【为什么要有这个常量】应用名此前散落在四处：`AppScope` 的 `app_name`、
 * `entry` 的三个 string 资源、以及本文件里的一处字面量。它们各不相同
 * （「DSH 鸿蒙端」「DeepSeek Harness 鸿蒙客户端」），于是桌面图标、任务卡片、
 * 侧栏标题**互相不一致**——用户会以为是两个应用。
 *
 * 资源文件里的 `app_name`/`EntryAbility_label` 是系统读取的（改名要同步改资源），
 * 这里的常量供**应用内**渲染使用；两处必须字面一致，改名时一起改。
 */
const APP_NAME: string = 'HDSH';

/** 本机偏好「主题模式」的 key 与取值（与 `platform/LocalPrefs` 的 `ThemeMode` 一致） */
const LOCAL_THEME_KEY: string = 'local.themeMode';
const LOCAL_THEME_SYSTEM: string = 'system';
const LOCAL_THEME_LIGHT: string = 'light';
const LOCAL_THEME_DARK: string = 'dark';

/** 单栏下的页面栈 */
/**
 * 一级页签的**本地化**文案（E117：跟随系统语言，默认中文）。
 *
 * 【为什么标签必须留在视图层】`navTabLabel` 在 appstate 里，那是个纯 TS 模块——
 * `$r('app.string.*')` 是 ArkUI 资源引用，只有视图层能用。资源本体放在
 * `resources/base/element/string.json`（中文，即默认）与 `resources/en_US/...`（英文），
 * 由系统按当前语言自动选择；这里只做"页签 → 资源"的映射。
 */
function navTabLabelRes(tab: NavTab): Resource {
  if (tab === NavTab.WORKSPACES) {
    return $r('app.string.tab_workspaces');
  }
  return $r('app.string.tab_settings');
}

/** 一级导航顺序 */
// 「核心」放在工作区与设置之间：它属于"能力/运维"一类，紧邻设置但不与设置混在一起
// E110：收敛为两项——核心并入设置（它是"这台设备上 DSH 怎么跑"的配置，不该另开一级）

/** 自动连接路径的诊断日志（前缀 HDSH-CONN）：端侧只有 hilog 可看，而这条路径
 *  "既不发请求也不报错"的失败模式极难从外部定位（见 E55/E56）。 */
const DOMAIN: number = 0x0000;
const TAG: string = 'HDSH-Index';

// 【本轮移除】阶段一 Electron 运行时宿主（`RuntimeHost` + `MOUNT_ELECTRON_RUNTIME_HOST`）
// 连同它对 `web_engine` 的依赖一起删掉了：那条通道依赖 JIT、不可上架，
// 且它在模拟器（x86_64）上因缺少 `libadapter.so` 会把应用直接打崩（见 AppAbilityStage 的说明）。
// 端侧运行时现在只有一条路径：`libdshhost.so` → `libnode.so.127`（D6 §4.1）。

@Entry
@Component
struct Index {
  // ── 形态 ──
  @State mode: LayoutMode = LayoutMode.SINGLE;
  @State tab: NavTab = NavTab.SESSIONS;
  @State stackPage: StackPage = StackPage.MAIN;
  @State detailOpen: boolean = false;
  /**
   * 当前窗口尺寸（vp）。形态与几何**不再由本文件各算一遍**，
   * 统一交给 `appstate/ui/LayoutController.decideLayout()`（P1：布局决策出栈）。
   * 两者在 `applySize()` 里同时写入，因此 `mode !== SINGLE` 时它们必定有效。
   */
  @State winWidthVp: number = 0;
  @State winHeightVp: number = 0;
  /**
   * 详情**半模态 Sheet**（P1.5）。
   *
   * 【为什么不再是一条栈页】鸿蒙 `bindSheet` 的语义是"非全屏弹窗、底层父视图部分可见"，
   * 正好对应"边看对话边看详情"的真实意图；整页替换会把对话顶掉，用户还得再退回来。
   * 三栏形态不走这条（`mode === TRIPLE` 时用真正的右栏，可调宽、可记忆）。
   */
  @State detailSheetOpen: boolean = false;

  // ── 数据（当前来自桩数据源） ──
  @State sessions: SessionListItem[] = [];
  @State pending: PendingItem[] = [];
  @State selectedSessionId: string = '';
  @State selectedSessionTitle: string = '';
  @State trajectoryItems: TrajectoryItem[] = [];
  @State detailSections: DetailSection[] = [];
  /** 端侧核心的呈现模型（D6）。初始为「运行时未接线」的如实状态，不含任何桩数据 */
  @State coreView: CoreViewState = emptyCoreView();
  /** 核心页的一次性提示（动作未接线/进行中等），显示后由用户下次操作覆盖 */
  @State coreNotice: string = '';
  /** 端侧核心的生命周期句柄（懒建；只有一个，与"单一状态机"的纪律一致） */
  private host: DshHost | null = null;
  /** 本机沙箱里可写的工作区目录（E98：连接后注册进 Host，建会话带上 workspaceId） */
  private localWorkspaceDir: string = '';
  /** 插件启停操作的即时反馈（重启后生效这类事实必须让用户看到） */
  @State pluginNotice: string = '';
  @State workspaces: WorkspaceItem[] = [];
  /** 宿主报告的权限组合（E124：`currentValue` + `options`；空串=宿主没投影，界面不显示） */
  @State permissionCurrent: string = '';
  @State permissionOptions: string[] = [];
  /** 会话统计行（E125：官方措辞「N 轮 M 步 · 缓存命中 X%」；空串=没有可显示的统计） */
  @State statsLine: string = '';
  /** 会话的 Agent 预设（E129：官方显示在会话标题上；创建后固定，只读） */
  @State agentPreset: string = '';
  /** 工作区注册表（E132：带 workspaceId；删除需要它） */
  @State workspaceRows: WorkspaceRow[] = [];
  /** 注册表全局归档集合（E132）：常规列表按它过滤 */
  @State archivedSessionIds: string[] = [];
  /** 技能清单与其读取结论（E135） */
  @State skills: SkillRow[] = [];
  @State skillNote: string = '';
  /** Agent 预设名单与其读取结论（E161：预设 = 会话的 Agent 插件组装） */
  @State presets: AgentPresetRow[] = [];
  @State presetNote: string = '';
  /** 已按过一次「删除」、等待确认的工作区路径（两步确认） */
  @State confirmingDeletePath: string = '';
  /**
   * 归档分组是否展开（E165，用户反馈②）。
   *
   * 用户原话："归档后的会话不应该在工作区显示。" 归档集本身是对的（真机读数 `archived=3/4`），
   * 问题在于我把「归档 · N」**平铺在工作区页里** ⇒ 看起来像"归档了还留在工作区"。
   * 默认**折叠**：只留一行「归档 · N」作为入口，点开才展开——既不再"显示在工作区里"，
   * 也没有把已归档的会话变得找不到。
   */
  @State archiveOpen: boolean = false;
  @State fileTree: FileNode[] = [];
  /** 文件预览结果；undefined = 未选择文件（@State 必须给默认值） */
  @State preview: FilePreview | undefined = undefined;
  @State settings: SettingGroup[] = [];
  /**
   * 本客户端本地偏好（通知 / 离线缓存等）。
   *
   * 与 `settings`（最终渲染的合并结果）分开保存的理由：这些偏好**不存在于上游**，
   * 连上 Host 后不能被 Host 设置顶掉——否则用户会以为功能消失了。
   * 见 `mergeSettingsGroups` 的说明。
   */
  @State localSettings: SettingGroup[] = [];
  /**
   * Host 设置分组（`settings/describe` 的那一份）。
   *
   * 与 `localSettings` **分开存**：界面用到的 `settings` 是两者合并的结果，
   * 而"本机偏好改了要重新合并"时必须有一份没被覆盖的 Host 分组可用。
   * 只存合并结果的话，第二次合并会把上一次的本机组再叠一遍。
   */
  @State hostSettings: SettingGroup[] = [];
  /** 设置命名空间的写状态（含 revision）；用于诊断「界面值与 Host 版本是否一致」 */
  @State settingsStates: SettingsNamespaceState[] = [];
  /** 设置写入的结果回显（成功/失败/冲突都如实显示，不做乐观更新） */
  @State settingWriteNote: string = '';
  /**
   * 正在选择的枚举设置项。
   *
   * 【为什么用浮层而不是「点一下轮换到下一个值」】枚举可能有 3–4 个取值，
   * 轮换要求用户记住顺序并反复点击才能到达目标值，而且**每一跳都会写一次 Host**——
   * 中途的每一次都是真实副作用。浮层让用户一次选中目标值，只写一次。
   */
  @State choosing: SettingChoice[] | undefined = undefined;
  @State choosingKey: string = '';
  @State choosingLabel: string = '';
  @State choosingCurrent: string = '';
  /**
   * 正在编辑的凭据引用（空串 = 没有在编辑）。
   *
   * 【为什么先起编辑态再写】写凭据是**破坏性**操作（`credentials/unset` 会删掉
   * Host 侧的值，依赖它的功能立刻失效）。要求用户先明确进入编辑态再提交，
   * 比「点一下就直接写」多一道有意的摩擦。
   */
  @State credentialRef: string = '';
  /** 待写入的凭据明文。**只在这里存在**：提交后立刻清空，不进任何持久状态。 */
  @State credentialDraft: string = '';
  /**
   * 凭据浮层自己的结果/进度文案。
   *
   * 【为什么不用共享的 `settingWriteNote`】那个字段被列表上方的回显与设置写入共用，
   * 而浮层盖住了列表——把结果写进一个**看不见**的地方，失败就变成了静默失败。
   * 实测踩到过：写入没有到达 Host，而界面上没有任何提示。
   * 每个会盖住内容的界面都必须有自己的结果出口。
   */
  @State credentialNote: string = '';
  /** 凭据请求进行中（防重复提交；不复用 `connectBusy`，那是连接的状态） */
  @State credentialBusy: boolean = false;
  /**
   * 正在编辑的文本/数字设置项 key（空串 = 没有在编辑）。
   *
   * 与凭据浮层复用同一个模式：先进入编辑态，再提交。
   */
  @State textSettingKey: string = '';
  @State textSettingLabel: string = '';
  @State textSettingDraft: string = '';
  /** 编辑中的设置项（提交时要按它的 `valueType` 与约束解析输入） */
  private textSettingItem: SettingItem | undefined = undefined;
  /**
   * 正在整值编辑的结构化设置项 key（数组 / 嵌套对象 / 复杂 union）。
   *
   * 【为什么必须整值编辑】实测数组元素**无法按路径寻址**
   * （字符串下标 → `settings/rejected`；数字下标 → `gateway/input-invalid`），
   * 详见 `SettingKind.STRUCT` 的说明。唯一可行的写法是读整个值、本地改、整值写回。
   */
  @State structSettingKey: string = '';
  @State structSettingLabel: string = '';
  @State structSettingDraft: string = '';
  private structSettingItem: SettingItem | undefined = undefined;
  @State credentials: CredentialItem[] = [];
  @State plugins: PluginItem[] = [];
  @State hosts: HostRecord[] = [];
  @State models: ModelOption[] = [];
  @State selection: ModelSelection = { provider: '', modelId: '', effort: '' };
  /** 诊断是否在跑（驱动「重新检测」按钮的忙碌态） */
  @State diagRunning: boolean = false;
  @State diag: DiagReport = {
    entries: [], healthy: false, generatedAt: 0, versionVerdict: '',
    versionMessage: '', versionAdvice: '', tableStats: '', surface: ''
  };
  @State references: ReferenceCandidate[] = [];
  @State commands: CommandCandidate[] = [];
  /**
   * 计划模式状态（E202，来自 `plan` 投影）。
   *
   * 官方 chip 的判据是"**生效目标**是计划模式"= `pending ? !active : active`
   * （`pending` = 刚切换、等宿主确认）⇒ 我们照这条公式推导显示，不自己发明状态。
   * 切换没有专用端点：执行 `plan` 命令（E190 的命令面板已能执行）。
   */
  @State planActive: boolean = false;
  @State planPending: boolean = false;
  /** 命令面板是否打开（E190：短命令面板的可见状态） */
  @State paletteOpen: boolean = false;
  /** 能力缺失的一次性提示（透传给输入区；如附件上传尚未接线） */
  @State attachNotice: string = '';
  /** 用户是否已经点过一个工作区（决定文件树空态该说哪一句） */
  @State pendingWorkspacePick: boolean = false;
  /** 文件树空态标题与说明（由交互状态算出，见 `updateTreeEmptyText`） */
  @State treeEmptyTitle: string = '该工作区暂无文件';
  @State treeEmptyHint: string = '选择一个工作区以浏览它的文件';

  // ── 交互状态 ──
  @State draft: string = '';
  @State attachments: PendingAttachment[] = [];
  /** Host 侧待发队列（与会话一一对应，由 `session/control` 驱动） */
  @State queued: QueuedItem[] = [];
  @State running: boolean = false;
  @State offline: boolean = false;
  @State queuedCount: number = 0;
  @State wsDrill: number = 0;
  @State traceEnabled: boolean = false;
  @State traceLines: string[] = [];
  @State connectAddress: string = '';
  @State connectToken: string = '';
  @State connectBusy: boolean = false;
  @State connectResult: string = '';
  @State connectOk: boolean = false;
  @State connectAdvice: string = '';

  /** 派生值：避免在循环体内读取 @State（ArkTS 性能规则） */
  @State pendingBadge: string = '';

  // ── 真实连接状态（来自 SessionHub；未连接时保持桩数据） ──
  /** 中枢阶段；只有 LIVE 时才用中枢的数据覆盖桩数据 */
  @State hubPhase: HubPhase = HubPhase.IDLE;
  /** 已连接 Host 的 authority（供诊断与状态条显示） */
  @State hubAuthority: string = '';
  /** 中枢最近一次错误（用户可见文案，已含「可以做什么」） */
  @State hubError: string = '';
  /** `$events` 是否已就绪（D1 §7.7.5b 的验收点之一） */
  @State hubEventsReady: boolean = false;
  /** 控制流是否已收到 baseline */
  @State hubControlReady: boolean = false;
  /** 当前 mux 活动逻辑流数（正常为 2 或 3） */
  @State hubStreams: number = 0;
  /**
   * 是否已连上 Host（一元可用）。
   *
   * **与 `hubPhase === LIVE` 不是一回事**：`phase` 会因 `$events` 流终止而降级为
   * `DEGRADED`，而那一刻一元调用（会话列表、新建会话、发送…）仍然是真实可用的。
   * 视图判断「用真实数据还是桩数据」必须用本字段——用 `phase` 会让
   * 「连上了但事件流恰好断了」的时刻又退回桩数据，等于给用户看假会话。
   */
  @State hubConnected: boolean = false;
  /**
   * 上次连上的 Host（能力层从存储读出来后经 AppStorage 发布）。
   *
   * 三个键对应三种**不同**的处置，不能合成一个：
   *   - `rememberedUrl` 非空且可自动重连 → 直接连；
   *   - `rememberedTokenState === 'absent'` → 首次使用，显示「添加 Host」；
   *   - `rememberedTokenState === 'unavailable'` → **有记录但读不到**
   *     （锁屏策略变化 / 存储故障）。此时提示「请重新粘贴 token」是错的：
   *     token 还在，只是这次读不出来。两种情况的文案必须不同。
   */
  @StorageProp('dshLastHostUrl') rememberedUrl: string = '';
  @StorageProp('dshLastHostToken') rememberedToken: string = '';
  @StorageProp('dshLastHostTokenState') rememberedTokenState: string = 'pending';
  @StorageProp('dshHostAutoConnect') shouldAutoConnect: boolean = false;
  /**
   * 是否已经**结束过一次**连接尝试（E111）。
   *
   * 【为什么需要】启动时应用要先等本机核心就绪，再完成 token→cookie 兑换；
   * 这几十秒里中枢的 `lastError` 可能带着"尚未连接"这类中间态文本，而状态条是无条件渲染的
   * ⇒ 用户看到「无法连接核心」**闪一下再消失**（真机反馈）。判据不能是"有没有错误文本"，
   * 只能是"有没有真的试过并且失败了"。
   */
  @State connectSettled: boolean = false;
  /**
   * 内置核心是否正在解包（EntryAbility 广播；E99）。
   * 首启时它必须让页面显示「正在解包核心」而不是「还没有安装核心」。
   */
  @StorageProp('hdsh.core.installing') coreInstalling: boolean = false;
  /**
   * 启动参数里的**路由**（通知点击直达的那一半）。
   *
   * 【为什么必须有它】`NotificationCenter` 会给通知挂一个携带 `dshRoute` 的 WantAgent，
   * 能力层把它解析后发布到 `dshLaunchRouteJson`；如果页面**不读**这个键，
   * 用户点通知的结果就只是"应用到了前台"——而通知的全部价值恰恰是"点了就到那件事上"。
   * 这条链路的平台半段早已就位（`buildAgent`），此前缺的就是这里的消费。
   */
  @StorageProp('dshLaunchRouteJson') launchRouteJson: string = '';
  /**
   * 本机偏好「主题模式」（能力层从 preferences 读出后发布）。
   *
   * 三种取值的界面呈现由 `localPreferenceGroup()` 负责；这里只做只读订阅。
   */
  @StorageProp('dshThemeMode') themeMode: string = 'system';
  /** 主题上次应用是否成功（能力层写入；失败时设置页要如实说明） */
  @StorageProp('dshThemeApplied') themeApplied: boolean = true;
  /** 会话内搜索条是否打开（D3 §5.1 的 Ctrl/Cmd+F；由快捷键打开、由搜索条自己关闭） */
  @State searchOpen: boolean = false;
  /** 自动重连只跑一次（StorageProp 变化会触发，重复跑会反复认证） */
  private autoConnectAttempted: boolean = false;
  /**
   * 最近一次自动连接用的 `(url, token)` 组合。
   *
   * 【为什么不能用布尔量表示"已连过"】**dsh 每次启动都会生成新 token**（真机读数：
   * 上一轮落盘的 token 在这一轮启动 250 ms 时就被页面读到并拿去连接，而新 token 要到
   * `BOOT_65_AUTH_URL`（约 2.2 秒）才发布）⇒ 只有记录"用的是哪一对"才能在 token 刷新后
   * 再连一次。用布尔量会让刷新后的新 token 永远没有机会被使用（E57）。
   */
  private lastConnectKey: string = '';
  /** 自动连接尝试上限：为"先用旧 token、随后 token 刷新"这一正常序列留出余量。 */
  private connectAttempts: number = 0;
  /** 未识别的上游事件类型数量（真机跑一次即可据此回填事件表） */
  @State hubUnknownEvents: number = 0;
  /** 协议旁路日志（取尾部若干行展示，用于区分「列表为空」与「调用失败」） */
  @State hubTrace: string[] = [];

  private widthListener?: (size: window.Size) => void;
  /**
   * 中枢订阅者（在 `aboutToAppear` 里构造）。
   *
   * 为什么不在字段上直接写字面量：ArkTS 禁止「无类型对象字面量」
   * （`arkts-no-untyped-obj-literals`），即使是带类型标注的类字段也不接受。
   * 用「局部变量 + 具名接口标注」再赋值即可满足约束。
   *
   * 注意语义：**每个窗口各自订阅、但共享同一个中枢**——
   * 中枢（`SessionHub.shared()` 模块级单例）持有唯一连接，窗口只是视图。
   * 这正是 D1 §7.7.5b 要求的归属关系：视图可以有很多份，连接与会话状态只有一份。
   */
  private hubListener?: HubSubscriber;

  /**
   * 把中枢快照落到页面状态。
   *
   * 判据是 `s.connected`（认证与载体就绪），**不是** `s.phase`：
   * `phase` 会因事件流终止而降级为 `DEGRADED`，那时一元调用仍然可用，
   * 用 `phase` 会让「连上了但事件流恰好断了」的时刻退回空态，
   * 等于把已经拿到的真实数据丢掉。
   */
  private applyHubSnapshot(s: HubSnapshot): void {
    this.hubPhase = s.phase;
    this.hubAuthority = s.authority;
    this.hubError = s.lastError;
    this.hubEventsReady = s.eventsReady;
    this.hubControlReady = s.controlReady;
    this.hubStreams = s.activeStreams;
    this.hubUnknownEvents = s.unknownEventTypes.length;
    this.hubTrace = s.trace;
    this.hubConnected = s.connected;
    // E124：宿主报告的权限组合（真实事实，不是我们写死的默认值）
    this.permissionCurrent = s.permissionsCurrent;
    this.permissionOptions = s.permissionsOptions;
    /*
     * E125：官方在会话里显示「{turns} 轮 {steps} 步」「缓存命中 {percent}%」。
     * 这里在应用快照时**算成一行**（把 13 个数字塞进 13 个 @State 只会让状态面变大，
     * 而界面需要的本来就是这一行字）。缓存命中率 = 缓存读取 /（未缓存输入 + 缓存读取）。
     */
    {
      const turns: number = s.statsTurns;
      const steps: number = s.statsSteps;
      const cached: number = s.tokensCacheRead;
      const totalIn: number = s.tokensUncachedInput + cached;
      const percent: number = totalIn > 0 ? Math.round((cached / totalIn) * 100) : 0;
      const counts: string = turns > 0 ? `${turns} 轮 ${steps} 步` : '';
      const hit: string = totalIn > 0 ? `缓存命中 ${percent}%` : '';
      /*
       * E129：把 Agent 预设挂进这一行（官方把它显示在**会话标题**上：「在会话标题中查看当前 preset」）。
       * 预设**在会话创建时即固定**，所以它是状态而不是控件——只显示，不给"改当前会话"的入口。
       */
      const preset: string = s.agentPreset.length > 0 ? `预设 ${s.agentPreset}` : '';
      const parts: string[] = [];
      if (counts.length > 0) {
        parts.push(counts);
      }
      if (hit.length > 0) {
        parts.push(hit);
      }
      if (preset.length > 0) {
        parts.push(preset);
      }
      this.statsLine = parts.join(' · ');
    }
    // E132：工作区注册表与归档集合（删除/归档的依据）
    this.workspaceRows = s.workspaceRows;
    this.archivedSessionIds = s.archivedSessionIds;
    this.skills = s.skills;
    this.skillNote = s.skillNote;
    this.presets = s.presets;
    this.presetNote = s.presetNote;
    this.queuedCount = s.outbox;
    // 附件列表由中枢拥有（回执是会话作用域的），这里只跟随
    this.attachments = s.attachments;
    this.queued = s.queued;
    this.offline = s.phase === HubPhase.DEGRADED;
    if (!s.connected) {
      // 断开后**清空**上一段连接的数据，而不是留着当「缓存」：
      // 留着的会话列表会让用户以为还能点开会话，点下去全是失败。
      this.sessions = [];
      this.pending = [];
      this.trajectoryItems = [];
      this.workspaces = [];
      this.fileTree = [];
      this.detailSections = [];
      this.models = [];
      this.plugins = [];
      this.credentials = [];
      // 断连后 Host 设置没了，但**本机偏好仍然有效**（它本来就与 Host 无关）
      this.hostSettings = [];
      this.settings = this.localSettings;
      this.settingsStates = [];
      this.hosts = [];
      this.commands = [];
      this.references = [];
      this.preview = undefined;
      this.attachments = [];
      this.queued = [];
      this.updateHosts();
      this.recomputeDerived();
      return;
    }
    this.sessions = s.sessions;
    this.pending = s.pending;
    this.models = s.models;
    this.plugins = s.plugins;
    this.credentials = s.credentials;
    this.hostSettings = s.settings;
    this.settings = mergeSettingsGroups(this.hostSettings, this.localSettings);
    this.settingsStates = s.settingsStates;
    this.commands = s.commands;
    this.planActive = s.planActive;
    this.planPending = s.planPending;
    this.references = s.references;
    // 文件树与预览由中枢持有（它们与会话绑定），这里只跟随：
    // 中枢换了会话就会清空并重列，视图不做任何缓存，避免两边各存一份而后不一致。
    this.fileTree = s.fileNodes;
    this.preview = s.filePreview;
    if (s.defaultSelection !== undefined) {
      /*
       * E167（用户反馈⑤）：**宿主默认里没有推理强度**。
       * 实测 `session/modelCatalog` 的 `default` 只有 `{provider, model}`（没有 effort）
       * ⇒ `selection.effort` 为空 ⇒ 推理强度一排档位**没有任何一个被选中**，
       * 用户看到"默认 high 却没被选中"。用**目录里该模型的 `defaultEffort`** 兜底：
       * 它同样是宿主给的事实（模型自己的能力默认），不是我们编的。
       */
      const selection: ModelSelection = s.defaultSelection;
      if (selection.effort.length === 0) {
        for (let i = 0; i < this.models.length; i++) {
          const m: ModelOption = this.models[i];
          if (m.provider === selection.provider && m.modelId === selection.modelId
            && m.defaultEffort.length > 0) {
            this.selection = {
              provider: selection.provider, modelId: selection.modelId, effort: m.defaultEffort
            };
            break;
          }
        }
      }
      this.selection = this.selection.effort.length > 0 ? this.selection : selection;
    }
    this.selectedSessionTitle = s.selectedTitle;
    if (s.selectedSessionId === this.selectedSessionId) {
      this.trajectoryItems = s.trajectory;
      this.running = s.running;
    }
    // 工作区与详情分区是**派生量**：从真实会话与真实轨迹算出来，
    // 因此只要底料变了就重算，不需要 Host 另发一份。
    this.workspaces = projectWorkspaces(this.sessions);
    this.detailSections = projectDetailSections(this.trajectoryItems);
    this.updateHosts();
    this.recomputeDerived();
  }

  /**
   * 刷新「已配置 Host」列表。
   *
   * 数据源只有两个真实事实：**上次记住的地址**（能力层存储）与**当前连接状态**。
   * 这里绝不编造条目——这个列表上的「已授权」是一条安全陈述。
   */
  private updateHosts(): void {
    this.hosts = projectHosts({
      url: this.rememberedUrl,
      connected: this.hubConnected,
      authority: this.hubAuthority,
      authorized: this.hubConnected || this.rememberedTokenState === 'present',
      // 上游**没有**任何端点或帧给出 Host 核心包版本（`$events` 的 ready 帧
      // 实测只有 `clientId` 与 `host.home`，见 D2 §8.7.12），因此这里只能诚实留空，
      // 设备页显示「核心包版本 未知」。不能拿「受支持版本矩阵」冒充 Host 的版本。
      version: ''
    });
  }

  /**
   * 在当前设置分组里找一项。
   *
   * 返回 `undefined` 说明这个 key 不属于 Host 设置——即**本机偏好**。
   * 两条路径的处置完全不同（Host 项可以写、本机项没有上游写路径），
   * 所以必须先分清，而不是一律当 Host 项去写（那会对不存在的命名空间发起 RPC）。
   */
  private settingItemOf(key: string): SettingItem | undefined {
    for (let i = 0; i < this.settings.length; i++) {
      const items: SettingItem[] = this.settings[i].items;
      for (let j = 0; j < items.length; j++) {
        if (items[j].key === key) {
          return items[j];
        }
      }
    }
    return undefined;
  }

  aboutToAppear(): void {
    // 初始值 = 空态。所有真实数据都在 `applyHubSnapshot` 到达时落地；
    // 连接建立前界面显示的是各视图自己的空态文案（D3 §4），而不是编造的示例数据。
    this.diag = emptyDiagReport();
    // 核心页先落地一次"未接线/仓库实况"的呈现（D6）。它不依赖连接，因此一开始就能读。
    this.refreshCoreView();
    // 本机偏好是**端侧**的，与连接无关，因此一开始就要有（否则设置页会缺一组）。
    // 当前值来自能力层（它从 preferences 读出后发布到 AppStorage）。
    this.localSettings = this.localPreferenceGroup();
    this.settings = this.localSettings;
    this.updateHosts();
    this.recomputeDerived();
    this.applySize(initialWidthVp(), initialHeightVp());
    this.watchWindowSize();
    // 订阅中枢：多窗口下每个窗口各自订阅，但共用同一个连接与会话状态
    const listener: HubSubscriber = (s: HubSnapshot) => {
      this.applyHubSnapshot(s);
    };
    this.hubListener = listener;
    SessionHub.shared().subscribe(listener);

    // 自动重连：能力层从（加密）存储里读「上次的 Host」是异步的，
    // 可能晚于本页就绪。这里**轮询等待**而不是「读一次就下结论」——
    // 读一次就下结论会让用户看到「请添加 Host」，而他上次明明连过。
    this.waitForRememberedHost();
    // 冷启动时也可能是"从通知进来"的（应用被杀后点通知 → onCreate 带参数）
    this.applyLaunchRoute();
  }

  /**
   * 本机偏好分组（D1 §7.6.5 P0：主题「跟随系统深浅色」，且 D3 §8 要求「设置可覆盖」）。
   *
   * 【为什么这一组是"真的"而不再是桩数据】此前它是被删掉的桩项之一——
   * 删得对（那些项点了没有任何效果），但**功能本身是指定要有的**：
   * 主题模式必须能覆盖系统。现在它由 `platform/LocalPrefs` 持久化、
   * 由能力层在启动时应用、由这里写回并立即生效。
   *
   * 【为什么 key 用 `local.` 前缀】`settingItemOf()` 用"能不能在 Host 设置分组里找到"
   * 来判定一项是不是本机偏好；前缀让来源一眼可辨，也避免与 Host 的命名空间撞名
   * （Host 侧不存在 `local.*` 命名空间）。
   */
  private localPreferenceGroup(): SettingGroup[] {
    const choices: SettingChoice[] = [];
    const options: string[] = [LOCAL_THEME_SYSTEM, LOCAL_THEME_LIGHT, LOCAL_THEME_DARK];
    const labels: string[] = ['跟随系统', '浅色', '深色'];
    for (let i = 0; i < options.length; i++) {
      choices.push({ value: options[i], label: labels[i] });
    }
    const items: SettingItem[] = [{
      key: LOCAL_THEME_KEY,
      label: '主题模式',
      hint: this.themeApplied
        ? '本机偏好：覆盖系统深浅色，只在端侧生效（Host 设置里没有这一项）'
        : '本机偏好：覆盖系统深浅色。**上次应用未成功**（系统拒绝或当前窗口模式不支持）',
      kind: SettingKind.CHOICE,
      boolValue: false,
      textValue: this.themeMode,
      options: options,
      choices: choices,
      readOnly: false,
      hostWritable: false,
      appliesLive: true,
      origin: SettingOrigin.LOCAL,
      userSet: this.themeMode !== LOCAL_THEME_SYSTEM,
      credentialRef: false,
      valueType: SettingValueType.STRING,
      minValue: 0, maxValue: 0, stepValue: 0, hasMin: false, hasMax: false,
      pattern: '', required: false, rawJson: '', structType: ''
    }];
    const out: SettingGroup[] = [];
    out.push({ title: '本机偏好', items: items });
    return out;
  }

  /**
   * 写入本机偏好并**立即应用**主题。
   *
   * 三步的顺序有意义：先落盘（失败要能说出来）→ 再应用（D1 判据：1 秒内生效）→
   * 最后把新值放回 AppStorage 让界面跟着变。任何一步失败都要在 `settingWriteNote`
   * 里如实说明，而不是让用户对着一个没生效的开关反复点。
   */
  private async writeLocalTheme(mode: string): Promise<void> {
    const prefs: LocalPrefs = new LocalPrefs();
    await prefs.attach(getContext(this) as common.UIAbilityContext);
    const saved: boolean = await prefs.saveThemeMode(themeModeOf(mode));
    const applied: boolean = applyThemeMode(getContext(this) as common.UIAbilityContext, themeModeOf(mode));
    AppStorage.setOrCreate<string>('dshThemeMode', mode);
    AppStorage.setOrCreate<boolean>('dshThemeApplied', applied);
    this.localSettings = this.localPreferenceGroup();
    this.settings = mergeSettingsGroups(this.hostSettings, this.localSettings);
    if (!saved || !applied) {
      this.settingWriteNote = !saved
        ? '主题已切换，但**没能保存**：下次启动会回到上次的值。'
        : '主题已保存，但**本次应用未成功**（系统拒绝或当前窗口模式不支持）。';
      return;
    }
    this.settingWriteNote = '主题模式已保存并在本次生效。';
  }

  /**
   * 页面每次变为可见时消费一次路由。
   *
   * 【为什么用 `onPageShow` 而不是 `@Watch`】`@StorageProp` 的 `@Watch` 在本项目里
   * 不被信任（见 `waitForRememberedHost` 的说明）。而通知点击的场景是
   * "应用被切到前台"，`onPageShow` 正是这个时刻——由生命周期驱动比轮询可靠，
   * 也不会在页面已经可见时反复触发。
   */
  onPageShow(): void {
    this.applyLaunchRoute();
  }

  /**
   * 系统返回键（E94）：**有东西可退就先消费，真的到根了才交给系统**。
   *
   * 【为什么要自己处理】本页的导航是**自绘状态机**（`tab` / `stackPage` / `wsDrill` /
   * 各种浮层），不经过 router 栈 ⇒ 系统返回事件没有任何人消费，默认行为是
   * **直接把应用退回桌面**。用户实测报告："许多页面用系统返回会直接退回桌面"。
   *
   * 【顺序 = 从最上面那层往回退】返回键的语义是"关掉当前这一层"，所以：
   *   浮层/编辑态 → 二级页 → 会话详情 → 工作区下钻 → 文件预览 → 非首页签 → 交给系统。
   * 只有**确实停在首页、且没有任何浮层**时才返回 false——那时系统把应用切到后台
   * 才是正确行为，不该被应用吞掉（吞掉会变成"按返回没反应"）。
   *
   * 每一步都写 hilog：真机上核对"到底哪一层没退掉"时，这行日志就是答案。
   */
  onBackPress(): boolean {
    // 优先级阶梯（浮层 → 二级页 → 详情 → 下钻 → 预览 → 首页签 → 交给系统）全部在
    // `appstate/ui/NavigationController.decideBack` 里，并有 fixture 逐级断言；
    // 这里只做**执行 + 日志**，不再自己排顺序。
    const action: BackAction = decideBack(this.navState(), this.overlayState());
    switch (action) {
      case BackAction.CLOSE_CREDENTIAL:
        this.credentialRef = '';
        this.credentialDraft = '';
        this.credentialNote = '';
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 关闭凭据编辑浮层');
        return true;
      case BackAction.CLOSE_SETTING_DRAFT:
        this.textSettingDraft = '';
        this.structSettingDraft = '';
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 关闭设置编辑浮层');
        return true;
      case BackAction.CLOSE_SEARCH:
        this.searchOpen = false;
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 关闭搜索');
        return true;
      case BackAction.CLOSE_CHOICE:
        this.choosing = undefined;
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 关闭选择浮层');
        return true;
      case BackAction.CLOSE_DETAIL_SHEET:
        // 交给 Sheet 自己收起（`shouldDismiss` 里会复位状态）
        this.detailSheetOpen = false;
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 关闭详情半模态');
        return true;
      case BackAction.STACK_TO_MAIN: {
        const from: string = this.stackPage;
        this.stackPage = StackPage.MAIN;
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 二级页回主列表：%{public}s', from);
        return true;
      }
      case BackAction.CLOSE_DETAIL:
        this.detailOpen = false;
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 关闭会话详情');
        return true;
      case BackAction.DRILL_UP:
        this.wsDrill -= 1;
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 工作区上退一层，drill=%{public}d', this.wsDrill);
        return true;
      case BackAction.CLOSE_PREVIEW:
        this.preview = undefined;
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 关闭文件预览');
        return true;
      case BackAction.TAB_TO_SESSIONS:
        this.selectTab(NavTab.SESSIONS);
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 回首页签（会话）');
        return true;
      default:
        // EXIT：**不消费**，交给系统（最小化）。写成 false 是刻意的——
        // "按返回没反应"的假入口都是在这里 return true 造成的。
        hilog.info(DOMAIN, TAG, 'HDSH-BACK 已在根层，交给系统');
        return false;
    }
  }

  /** 导航状态快照（视图持有真实状态，控制器只读） */
  private navState(): NavState {
    return {
      tab: this.tab,
      stackPage: this.stackPage,
      wsDrill: this.wsDrill,
      hasSession: this.selectedSessionId.length > 0,
      detailOpen: this.detailOpen
    };
  }

  /** 浮层状态快照（返回键的第一优先级） */
  private overlayState(): OverlayState {
    return {
      credentialOpen: this.credentialRef.length > 0 || this.credentialDraft.length > 0,
      settingDraftOpen: this.textSettingDraft.length > 0 || this.structSettingDraft.length > 0,
      searchOpen: this.searchOpen,
      choosingOpen: this.choosing !== undefined,
      detailSheetOpen: this.detailSheetOpen,
      previewOpen: this.preview !== undefined
    };
  }

  /**
   * 消费通知点击携带的路由。
   *
   * 【为什么消费后要清掉它】不清掉的话，用户此后每次把应用切到前台
   * （甚至只是切回来）都会被重新导航一次——他正在看别的地方，界面却跳走。
   * 清掉用的是 `AppStorage.setOrCreate`（`@StorageProp` 的赋值只改本地副本）。
   */
  private applyLaunchRoute(): void {
    const json: string = this.launchRouteJson;
    if (json.length === 0) {
      return;
    }
    AppStorage.setOrCreate<string>('dshLaunchRouteJson', '');
    const route: NotifyRoute | undefined = parseNotifyRoute(json);
    if (route === undefined) {
      // 解析不出来就**不跳转**：宁可停在当前页面，也不要跳到一个猜出来的位置。
      // （能走到这里通常意味着通知是旧版本写下的，参数形状已经变了。）
      return;
    }
    // `hostId` 目前不使用：本客户端只保存一个 Host（多 Host 管理未落地），
    // 因此"切回正确连接"这一步无对象可切。等多 Host 落地后在这里接。
    if (route.page === 'pending') {
      this.selectTab(NavTab.PENDING);
      return;
    }
    if (route.page === 'diagnostics') {
      this.openDiagnostics();
      return;
    }
    // 默认：会话页；带 sessionId 时直接下钻到那个会话
    this.selectTab(NavTab.SESSIONS);
    const sessionId: string | undefined = route.sessionId;
    if (sessionId !== undefined && sessionId.length > 0) {
      this.openSession(sessionId);
    }
  }

  /**
   * 等待并尝试自动重连（D1 §7.1：记住上次的 Host）。
   *
   * 【为什么轮询而不是订阅】`@StorageProp` 会在 AppStorage 变化时刷新界面，
   * 但**不会通知一段命令式代码**（ArkTS 的 `@Watch` 不保证可用于 `@StorageProp`）。
   * 与其依赖一个不确定的机制，不如用一个有界、可读的等待：
   * 每 250 ms 看一次，最多等 4 秒（存储打开 + 解密读取的正常量级）。
   * 超时后**不再自动重连**，但保留 UI 上的「添加 Host」——用户不会卡住。
   *
   * 【为什么只跑一次】`StorageProp` 的任何变化都会重进这个函数时，
   * 多次认证会在 Host 侧产生多次 token 兑换，也会让界面反复闪「连接中」。
   */
  private waitForRememberedHost(): void {
    if (this.autoConnectAttempted) {
      hilog.info(DOMAIN, TAG, 'HDSH-CONN 已安排过等待，跳过重复安排');
      return;
    }
    this.autoConnectAttempted = true;
    hilog.info(DOMAIN, TAG,
      'HDSH-CONN 开始等待记住的 Host：url=%{public}s tokenLen=%{public}d state=%{public}s auto=%{public}s',
      this.rememberedUrl, this.rememberedToken.length, this.rememberedTokenState,
      this.shouldAutoConnect ? 'true' : 'false');
    let waited: number = 0;
    const step: number = 250;
    /*
     * 【窗口为什么是 45 秒】本端自起 Host 要先解包核心再让 dsh 启动，实测 15~20 秒才把
     * token 发布到 AppStorage。窗口太短（原 4 秒）会让页面**从未发出认证请求**。
     *
     * 【为什么不在第一次连接后就停】因为**先到的那份凭据通常是过期的**：`persistConnectedHost`
     * 会把上一轮的 baseUrl+token 落盘，页面在 250 ms 就能读到，而 **dsh 每次启动都换新 token**
     * （本轮实测：新 token 在 +2238 ms 才由 `adoptLocalHost` 发布）。所以轮询要**一直跑到预算用完**，
     * 只在 `(url, token)` 这一对**变化**时重连（最多 3 次）——这既覆盖"首次连接"，
     * 也覆盖"旧 token 失败 → 新 token 到达后重连"这个正常序列。
     */
    const limit: number = 45000;
    const maxAttempts: number = 3;
    const timer: number = setInterval(() => {
      waited += step;
      const state: string = this.rememberedTokenState;
      const ready: boolean = state === 'found'
        && this.rememberedUrl.length > 0
        && this.rememberedToken.length > 0;
      if (ready) {
        const key: string = `${this.rememberedUrl}\u0000${this.rememberedToken}`;
        if (key !== this.lastConnectKey && this.connectAttempts < maxAttempts) {
          this.lastConnectKey = key;
          this.connectAttempts += 1;
          hilog.info(DOMAIN, TAG, 'HDSH-CONN 第 %{public}d 次自动连接：url=%{public}s tokenLen=%{public}d',
            this.connectAttempts, this.rememberedUrl, this.rememberedToken.length);
          this.applyRememberedHostOutcome(state);
        }
      }
      if (waited >= limit || this.connectAttempts >= maxAttempts) {
        clearInterval(timer);
        hilog.info(DOMAIN, TAG, 'HDSH-CONN 等待结束：waited=%{public}dms attempts=%{public}d state=%{public}s',
          waited, this.connectAttempts, state);
      }
    }, step);
  }

  /**
   * 按 token 的读取结果决定下一步，并给出**如实的**说明。
   *
   * 三种状态对应三种不同的用户动作，绝不能用同一句「请重新粘贴 token」糊过去：
   *   - `found`：直接重连；
   *   - `absent`：首次使用（或用户清过数据），引导添加 Host；
   *   - `unavailable`：**记录还在但这次读不到**（设备锁屏策略变化、存储系统故障）。
   *     让用户重新粘贴 token 是错的建议——token 并没有丢。
   */
  private applyRememberedHostOutcome(state: string): void {
    if (this.rememberedUrl.length === 0) {
      hilog.info(DOMAIN, TAG, 'HDSH-CONN 无记住的地址：不自动连接（等待本端 Host 或用户添加）');
      return;
    }
    if (state === 'found' && this.rememberedToken.length > 0) {
      const hub: SessionHub = SessionHub.shared();
      /*
       * 【E98】把入口脚本准备好的**可写工作区**交给中枢：建会话时它会被当成 `cwd` 传下去。
       *
       * 真机证据：不设它时，设备上建出来的会话 `cwd` 是 `/`（宿主进程工作目录继承自应用进程），
       * 于是打开会话时轨迹流抛 `gateway/internal …reading 'kind'`、文件列表 `cannot list`。
       * 取不到就**不设**（回到 Host 默认行为），绝不猜一个路径。
       */
      try {
        const wsCtx = getContext(this) as common.UIAbilityContext;
        const wsHost: DshHost = this.coreHost(wsCtx.filesDir, wsCtx.resourceDir, wsCtx.cacheDir);
        const ws: string = wsHost.localHostWorkspace();
        if (ws.length > 0) {
          hub.setDefaultWorkspace(ws);
          this.localWorkspaceDir = ws;
          hilog.info(DOMAIN, TAG, 'HDSH-CONN 默认工作区：%{public}s', ws);
        }
      } catch (e) {
        const err = e as Error;
        hilog.warn(DOMAIN, TAG, 'HDSH-CONN 读默认工作区失败（不设 cwd）：%{public}s', err.message);
      }
      // 【token 必须拼回 URL】`SessionHub.configure(address, name)` 的第二个参数是
      // **显示名**，不是 token——token 是从地址串里解析出来的（`parseTarget`）。
      // 只传裸 baseUrl 会让认证拿着空 token 去请求，Host 回
      // 「未提供 token」而界面显示「连接失败（HTTP 0）」，看起来像网络问题。
      // 实测踩到过。拼接后走同一条解析路径，与手动粘贴 URL 完全等价。
      const connectUrl: string = composeHostUrl(this.rememberedUrl, this.rememberedToken);
      if (!hub.configure(connectUrl, undefined)) {
        hilog.warn(DOMAIN, TAG, 'HDSH-CONN configure 被拒（地址形态不合法？）：%{public}s', this.rememberedUrl);
        return;
      }
      this.connectBusy = true;
      this.connectResult = `正在自动重连 ${this.rememberedUrl}…`;
      this.connectSettled = false;
      hub.connect().then((ok: boolean) => {
        this.connectBusy = false;
        // 尝试已结束（成功或失败都算"结束"）：从这里开始，错误文本才是**结论**而不是中间态
        this.connectSettled = true;
        const snap: HubSnapshot = hub.snapshot();
        /*
         * 【为什么这里一定要打日志（E62/E63）】`connect()` 内部会先做 token→cookie 兑换
         * （`SessionHub.connect` 无条件调 `authenticate()`，失败即 `DEGRADED` 返回），
         * 而端侧实测到 3120 的流量只有"就绪探测 401 + 8 次 POST 400"、**没有兑换请求**。
         * 失败原因就在 `snap.lastError`（例如"未提供 token"）——不打出来，外面只能看到
         * "端口通了但界面没连上"，与真实原因隔着一层。
         */
        hilog.info(DOMAIN, TAG, 'HDSH-AUTH connect 结果：ok=%{public}s sessions=%{public}d err=%{public}s',
          ok ? 'true' : 'false', snap.sessions.length,
          snap.lastError.length > 0 ? snap.lastError : '(none)');
        this.connectResult = ok
          ? `已自动重连 ${snap.authority}，收到 ${snap.sessions.length} 个会话`
          : '自动重连失败，请检查 Host 是否仍在运行。';
        if (!ok) {
          this.hubError = snap.lastError.length > 0
            ? snap.lastError
            : '自动重连失败。若 Host 已重启，它的 token 会重新生成，请重新粘贴启动链接。';
        } else {
          // 自动重连也报告一次：地址可能没变但 token 被轮换过（Host 重启），
          // 报告让存储里始终是**最近一次真正有效的**token。
          reportConnectedHost(this.rememberedUrl, this.rememberedToken);
          // 【连上就重读核心阶段（E83）】核心起来与"页面渲染完"是两件事，先后不定：
          // 首启时页面往往先渲染（阶段"未安装"），核心随后才 READY。会话页的空态文案
          // 由阶段决定，所以连上的这一刻必须把阶段刷新一次，否则空态会一直停留在
          // 「还没有安装核心」，把用户指向一个完全错误的方向。
          this.refreshCoreView();
          // 【连上就把沙箱工作区注册进 Host（E98）】注册后建会话会带上 `workspaceId`：
          // 真机上只传 cwd 而不注册时，打开会话会抛 `…reading 'kind'`（轨迹流失败）、
          // 文件列表也 `cannot list`。这一步是"能真正在某个目录里干活"的前提。
          if (this.localWorkspaceDir.length > 0) {
            hub.ensureWorkspace(this.localWorkspaceDir).then((note: string) => {
              hilog.info(DOMAIN, TAG, 'HDSH-CONN 工作区注册：%{public}s', note);
            }).catch((e: Object) => {
              const err = e as Error;
              hilog.warn(DOMAIN, TAG, 'HDSH-CONN 工作区注册异常：%{public}s', err.message);
            });
          }
        }
      });
      return;
    }
    if (state === 'unavailable') {
      // 关键区别：token 还在，只是这次取不出来
      this.connectResult = `已记住 Host ${this.rememberedUrl}，但这次的访问令牌读不出来`
        + '（通常是设备锁屏状态或存储策略变化导致的）。令牌没有被删除，'
        + '解锁设备后重启应用通常即可恢复；也可以现在重新粘贴启动链接覆盖它。';
      return;
    }
    // absent：首次使用
    this.connectResult = `已记住 Host ${this.rememberedUrl}，但没有可用的访问令牌。`
      + '请在 Host 上重新获取带 token 的启动链接并粘贴到下方。';
  }

  aboutToDisappear(): void {
    this.unwatchWindowSize();
    // 只退订本窗口；**不得**在此断开连接——关掉一个窗口不能让其他窗口掉线
    // （D1 §7.7.5b：「关任一窗口不影响其他窗口与连接」）
    const listener: HubSubscriber | undefined = this.hubListener;
    if (listener !== undefined) {
      SessionHub.shared().unsubscribe(listener);
      this.hubListener = undefined;
    }
  }

  /**
   * 跑一次**真实**连接诊断并把结果接到界面。
   *
   * 【为什么必须用真实报告】此前诊断页整页显示的是 `stubDiagnostics()` 的桩数据，
   * 于是连上真实 Host 后仍然显示 `home=D:/work`、`74 个端点（0.1.2-rc.1）`——
   * 与真正连着的 Host（`home=C:\Users\aotian`、48 个设置项的 0.1.5-rc.1）**完全不同**。
   * 一个「诊断页」报出与事实不符的主机信息，比没有诊断页更糟：
   * 用户会据此判断「连错了 Host」或「版本不匹配」，而两者都不成立。
   * （本轮就是这么被误导过一次。）
   *
   * 结论行仍由 `dshcompat` 提供（UI 不得自行拼写上游端点名，D5 §1），
   * 五项的判定值来自 `SessionHub.diagnose()` → `Connection.diagnose()`。
   */
  /** 打开诊断页：先跑一次**真实**诊断再进入，避免显示上一次或桩的结果 */
  private openDiagnostics(): void {
    this.stackPage = StackPage.DIAGNOSTICS;
    this.runDiagnostics();
  }

  private async runDiagnostics(): Promise<void> {
    this.diagRunning = true;
    const hub: SessionHub = SessionHub.shared();
    const report: DiagnosticReport = await hub.diagnose();
    this.diag = projectDiagnostics(report);
    this.diagRunning = false;
  }

  /**
   * 导出诊断报告到剪贴板。
   *
   * 只包含判定结论与旁路日志，**不含**消息内容、token、cookie（D1 §11.5 S4）。
   */
  private exportDiagnostics(): void {
    const lines: string[] = [];
    lines.push(`# ${APP_NAME} 诊断报告（${new Date().toISOString()}）`);
    lines.push(`Host: ${this.hubAuthority.length > 0 ? this.hubAuthority : '未配置'}`);
    lines.push(`阶段: ${this.hubPhase} · 连接=${this.hubConnected}`);
    lines.push('');
    for (let i = 0; i < this.diag.entries.length; i++) {
      const e: DiagEntry = this.diag.entries[i];
      lines.push(`${e.passed ? '通过' : '失败'}  ${e.name}: ${e.detail}`);
      if (e.advice.length > 0) {
        lines.push(`      建议: ${e.advice}`);
      }
    }
    lines.push('');
    lines.push(`版本判定: ${this.diag.versionVerdict} — ${this.diag.versionMessage}`);
    lines.push(`端点上表: ${this.diag.tableStats}`);
    if (this.traceEnabled) {
      lines.push('');
      lines.push('## 协议旁路日志');
      for (let j = 0; j < this.traceLines.length; j++) {
        lines.push(this.traceLines[j]);
      }
    }
    const text: string = lines.join('\n');
    copyText(text).then((ok: boolean) => {
      this.hubError = ok
        ? '诊断报告已复制到剪贴板（已剔除凭据与消息内容）。'
        : '复制失败：剪贴板不可用。';
    });
  }

  private recomputeDerived(): void {
    const n: number = this.pending.length;
    this.pendingBadge = n <= 0 ? '' : (n > 99 ? '99+' : `${n}`);
  }

  // ───────────────────── 形态判定（D3 §2.2） ─────────────────────

  private watchWindowSize(): void {
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        const rect = win.getWindowProperties().windowRect;
        this.applySize(px2vp(rect.width), px2vp(rect.height));
        const listener = (size: window.Size) => {
          this.applySize(px2vp(size.width), px2vp(size.height));
        };
        this.widthListener = listener;
        win.on('windowSizeChange', listener);
      }).catch(() => {
      });
    } catch (error) {
    }
  }

  private unwatchWindowSize(): void {
    const listener = this.widthListener;
    if (listener === undefined) {
      return;
    }
    this.widthListener = undefined;
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        win.off('windowSizeChange', listener);
      }).catch(() => {
      });
    } catch (error) {
    }
  }

  /** 切档位并修正派生状态（不重载数据，D3 §2） */
  private applySize(widthVp: number, heightVp: number): void {
    this.winWidthVp = widthVp;
    this.winHeightVp = heightVp;
    // 档位与详情栏可用性都来自**一处**决策（appstate/ui/LayoutController），
    // 本文件不再自己拼断点判断——否则"什么宽度显示什么"会有两份实现，破版时两处都要查。
    const decision: LayoutDecision = this.layoutDecision();
    const next: LayoutMode = decision.mode;
    if (next === this.mode) {
      return;
    }
    this.mode = next;
    if (next !== LayoutMode.SINGLE && this.stackPage === StackPage.CONVERSATION) {
      this.stackPage = StackPage.MAIN;
    }
    // 变宽到三栏时，详情改由右栏承担 ⇒ 关掉 Sheet（否则两处同时显示详情）
    if (next === LayoutMode.TRIPLE) {
      this.detailSheetOpen = false;
    }
    if (!decision.detailAvailable) {
      this.detailOpen = false;
    } else if (this.selectedSessionId.length > 0) {
      this.detailOpen = true;
    }
  }

  /**
   * 当前窗口尺寸下的布局决策。
   *
   * 输入模态（键鼠/指针）此处置 `false`：`LayoutDecision.pointerRich` 目前**没有任何消费点**，
   * 与其编一个来源不明的 `true`，不如如实传 false —— 接 P3 输入模态时改为读
   * `platform` 的 `readDeviceFacts()`（它已给出 `keyboardLikely`），并在那一步统一。
   */
  private layoutDecision(): LayoutDecision {
    const input: LayoutInput = {
      widthVp: this.winWidthVp,
      heightVp: this.winHeightVp,
      hasKeyboard: false,
      hasPointer: false
    };
    return decideLayout(input);
  }

  /** 导航侧栏宽度（唯一来源：布局决策） */
  private navWidthVp(): number {
    return this.layoutDecision().navWidthVp;
  }

  /** 详情栏宽度（唯一来源：布局决策，含让步链的收窄结果） */
  private detailWidthVp(): number {
    return this.layoutDecision().detailWidthVp;
  }

  // ───────────────────── 交互 ─────────────────────

  private titleOf(id: string): string {
    const list: SessionListItem[] = this.sessions;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return list[i].title;
      }
    }
    return '';
  }

  private openSession(id: string): void {
    this.selectedSessionId = id;
    this.selectedSessionTitle = this.titleOf(id);
    // 先清空再由中枢的 `session/follow` 推真实轨迹。
    // 不清空会让新会话的轨迹追加在旧会话后面（看起来像「会话里混进了别人的内容」）。
    this.trajectoryItems = [];
    this.running = false;
    if (this.hubConnected) {
      // 中枢会在切会话后重拉命令目录、文件树与引用候选（三者都是会话作用域的）
      SessionHub.shared().selectSession(id);
    }
    if (this.mode === LayoutMode.SINGLE) {
      this.stackPage = StackPage.CONVERSATION;
    } else if (this.mode === LayoutMode.TRIPLE) {
      this.detailOpen = true;
    }
  }

  /**
   * 切换一级页签（E108：待决已并入工作区，这里做一次归一化）。
   *
   * `NavTab.PENDING` 还留在枚举里（历史调用点仍会传它，例如"有待决时跳过去看"），
   * 但页签栏里已经没有它——统一落到工作区视图，那里有内联的待决区。
   */
  /**
   * 切换一级页签。
   *
   * 归一化（待决→工作区、核心→设置）、清栈、是否清空会话选择、是否重读静态事实，
   * 全部来自 `appstate/ui/NavigationController.selectTab`（纯函数，有 fixture 覆盖）；
   * 本方法只负责把决策**落到状态**并执行副作用。
   */
  private selectTab(tab: NavTab): void {
    const d: TabSelection = decideTabSelection(this.navState(), tab);
    this.tab = d.tab;
    this.stackPage = d.stackPage;
    this.wsDrill = d.wsDrill;
    if (d.clearSession) {
      this.selectedSessionId = '';
      this.selectedSessionTitle = '';
    }
    if (d.refreshStaticFacts) {
      // 空态文案由核心阶段决定，而首启时序是"页面先渲染、核心后就绪" ⇒ 每次进
      // 非工作区页签都重读，避免出现"核心页说就绪、会话页说没装"的自相矛盾读数。
      this.refreshCoreView();
      if (this.hubConnected) {
        // 技能/预设/提供方目录都是会话无关的静态事实，进设置页时一并刷新
        SessionHub.shared().refreshSkills();
        SessionHub.shared().refreshAgentPresets();
        SessionHub.shared().refreshProviderCatalog();
      }
    }
  }

  private openPoc(): void {
    router.pushUrl({ url: 'pages/Poc1' }).catch(() => {
    });
  }

  /**
   * 把工作区里的一个文件投喂成附件（读整文件字节 → 上传 → 拿回执）。
   *
   * 投喂后**跳回会话页**：附件是「下一条消息的附件」，用户需要看到它挂在输入区上。
   * 停在文件树页会让人以为投喂没发生（那条上传成功的 trace 只有诊断页能看到）。
   */
  private async attachWorkspaceFileToComposer(node: FileNode): Promise<void> {
    if (!this.hubConnected) {
      this.attachNotice = '当前离线：无法读取与上传 Host 侧文件。';
      return;
    }
    this.attachNotice = `正在读取并上传「${node.name}」…`;
    const outcome: AttachOutcome = await SessionHub.shared()
      .attachWorkspaceFile(node.path, node.name, node.size);
    this.attachNotice = outcome.ok ? '' : `投喂「${node.name}」失败：${outcome.reason}`;
    if (outcome.ok) {
      this.selectTab(NavTab.SESSIONS);
    }
  }

  /**
   * 抬起系统文件选择器，并把选中的文件上传成附件回执。
   *
   * 三种非成功结果**必须分开提示**（见 `platform.PickOutcome`）：
   *   - 用户取消 → **什么都不提示**（提示「失败」会让人以为操作出错了）；
   *   - 文件过大 → 说明大小与上限（这是可修复的选择）；
   *   - 选择/读取失败 → 给出原因与建议。
   * 合并成一句「附件添加失败」会让用户重试同一个动作。
   */
  private async pickAndAttach(): Promise<void> {
    const picked: PickedFile = await pickDocument(getContext(this) as common.Context);
    if (picked.outcome === PickOutcome.CANCELLED) {
      return;
    }
    if (picked.outcome === PickOutcome.TOO_LARGE) {
      this.attachNotice = picked.reason;
      return;
    }
    if (picked.outcome === PickOutcome.FAILED) {
      this.attachNotice = picked.reason;
      return;
    }
    this.attachNotice = '正在上传附件…';
    const outcome: AttachOutcome =
      await SessionHub.shared().attachLocalFile(picked.name, picked.base64, picked.bytes, picked.mediaType);
    // 上传结果必须覆盖掉「正在上传」——否则失败时界面会一直停在「正在上传…」，
    // 而用户以为它还在传（实际早就失败了）。
    this.attachNotice = outcome.ok ? '' : `附件「${picked.name}」添加失败：${outcome.reason}`;
  }

  /**
   * 取一个 cwd 属于该工作区的会话 id，作为文件浏览的作用域。
   *
   * 文件端点的作用域是会话级（`workspaceFileScopeId` = sessionId，D2b §2.0），
   * 而工作区只是一个目录，本身不是端点参数。因此「浏览某个工作区」必须落实到
   * 「用某个 cwd 落在该目录里的会话去列目录」。没有这样的会话时返回空串，
   * 由调用方保持空态并说明原因（而不是拿别的会话去列，那会列出**错误目录**的内容）。
   */
  private sessionForWorkspace(workspaceId: string): string {
    for (let i = 0; i < this.sessions.length; i++) {
      const item: SessionListItem = this.sessions[i];
      if (item.cwd.length > 0 && normalizePathKey(item.cwd) === workspaceId) {
        return item.id;
      }
    }
    return '';
  }

  /**
   * 展开/折叠文件树节点。
   *
   * 真实数据在枢纽里（目录内容要发 `workspaceFiles/list`），因此这里只转发。
   * 文件树**没有本地副本**——两份必然不同步，而「展开了一个不存在的子节点」
   * 这种不一致在界面上看起来完全正常。
   */
  private toggleDirectory(path: string): void {
    SessionHub.shared().toggleDirectory(path);
  }

  private openFile(node: FileNode): void {
    SessionHub.shared().openFile(node.path, node.name);
    if (this.mode === LayoutMode.SINGLE) {
      this.wsDrill = 2;
    }
  }

  /**
   * 切换计划模式（官方 `ui-plan` 的一级 chip，E202）。
   *
   * 【为什么走命令而不是端点】切换没有专用端点——宿主把"进入或退出计划模式"做成了一条
   * `plan` 命令（见 `ui-commands` 的 `description.plan`），所以这里执行 `/plan`。
   * 判据（生效值 = `pending ? !active : active`）在 Composer 与这里各用一次，
   * 但**只由中枢的投影驱动**，不缓存派生值。
   */
  private togglePlan(): void {
    SessionHub.shared().executeCommand('/plan').then((n: ActionNotice) => {
      this.settingWriteNote = this.noticeText(n);
    }).catch((e: Object) => {
      this.settingWriteNote = '切换计划模式失败：' + (e as Error).message;
    });
  }

  private showsConversation(): boolean {
    // 判据在控制器里（`NavTab.SESSIONS` 是 `WORKSPACES` 的别名这事只该写在那一处）
    return showsConversation(this.navState());
  }

  /**
   * 详情半模态内容（P1.5：手机上详情不再整页替换会话）。
   *
   * 复用既有的 `DetailPane`（它本就有 `onLineTap` 的"复制该行"行为），
   * 所以这不是新功能，而是把**同一份内容换一种更合适的呈现**。
   */
  @Builder
  detailSheet() {
    Column({ space: HarmonySpacing.CONTAINER }) {
      NativeSectionTitle({ text: '详情', hint: '工具 / 子代理 / 交付物 / 目标 / 任务' })
      DetailPane({
        sections: this.detailSections,
        onLineTap: (section: string, text: string) => {
          // E130：详情行看起来可点，就得真的做一件事——复制该行
          if (text.length > 0) {
            copyText(text);
          }
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding(HarmonySpacing.CONTAINER)
  }

  build() {
    // 用 `Stack` 承载「主内容 + 选项浮层」：枚举选择的浮层必须能盖在任意一栏之上，
    // 所以放在三形态**之外**，而不是在每个 build* 里各写一遍（写三遍必然走样）。
    Stack() {
      if (this.mode === LayoutMode.SINGLE) {
        this.buildSingle()
      } else if (this.mode === LayoutMode.DOUBLE) {
        this.buildDouble()
      } else {
        this.buildTriple()
      }
      // 端侧运行时不再由界面元素启动：Node 由 CMake 构建的 `libdshhost` 里
      // 直接 `dlopen(libnode.so.127)` + `node::Start` 拉起（D6 §4.1 / E30/E31），
      // 不需要 XComponent，也不需要 Electron 的 nativeContext。
      // 阶段一那个 1×1 的 RuntimeHost 已随 web_engine 依赖一起移除。
      if (this.choosing !== undefined) {
        this.choiceSheet()
      }
      if (this.credentialRef.length > 0) {
        this.credentialSheet()
      }
      if (this.folderOpen) {
        this.folderSheet()
      }
      if (this.textSettingKey.length > 0) {
        this.textSettingSheet()
      }
      if (this.structSettingKey.length > 0) {
        this.structSettingSheet()
      }
    }
    .width('100%')
    .height('100%')
    /**
     * 2in1 / 平板（外接键盘）快捷键：**声明式**那 8 个规格。
     *
     * 【为什么在这里声明而不是在各自的按钮上】这些动作是**全局**的（新建、切页签、
     * 重连…），挂在某个按钮上会随该按钮的可见性一起失效（例如"新建会话"按钮只在
     * 会话页存在，于是别的页面上 Ctrl+N 不生效）。挂在根容器上语义才是对的。
     *
     * 【为什么只有 8 个】另外 5 个（Enter / Esc / Alt+↑↓ / F5）`keyboardShortcut`
     * 表达不了（见 `ShortcutKeys.ets` 的说明），走下面的 `onKeyEvent`。
     *
     * 【为什么不做形态门控】D3 §5.1 那一节的适用对象是"有外接键盘"的设备，
     * 但**绑定本身在无键盘设备上无害**（手机没有 Ctrl 键，按不出来）。
     * 真正需要按形态过滤的是"把它展示给用户看"（帮助浮层/设置页），
     * 那部分用 `shortcutsForDesktop()`——目前尚无该浮层，故不在此假装。
     */
    .keyboardShortcut('n', [ModifierKey.CTRL], () => {
      this.runShortcut('new-session');
    })
    .keyboardShortcut('k', [ModifierKey.CTRL], () => {
      this.runShortcut('command-palette');
    })
    .keyboardShortcut('f', [ModifierKey.CTRL], () => {
      this.runShortcut('search-in-session');
    })
    .keyboardShortcut('b', [ModifierKey.CTRL], () => {
      this.runShortcut('toggle-nav');
    })
    .keyboardShortcut('j', [ModifierKey.CTRL], () => {
      this.runShortcut('toggle-detail');
    })
    .keyboardShortcut('p', [ModifierKey.CTRL, ModifierKey.SHIFT], () => {
      this.runShortcut('pending-inbox');
    })
    .keyboardShortcut('c', [ModifierKey.CTRL, ModifierKey.SHIFT], () => {
      this.runShortcut('copy-code-block');
    })
    .keyboardShortcut(',', [ModifierKey.CTRL], () => {
      this.runShortcut('open-settings');
    })
    .onKeyEvent((event: KeyEvent) => {
      // 只取「按下」那一次：抬起时再分发会执行两遍（`sendDraft` 会被调用两次）
      if (event.type !== KeyType.Down) {
        return;
      }
      const shift: boolean = event.getModifierKeyState !== undefined
        && event.getModifierKeyState(['shift']);
      const alt: boolean = event.getModifierKeyState !== undefined
        && event.getModifierKeyState(['alt']);
      const hit: ShortcutHit = hitOfKeyEvent(event.keyCode, shift, alt);
      this.dispatchKeyHit(hit);
    })
  }

  /**
   * 按键判定 → 动作。
   *
   * 【为什么单独抽出来】声明式绑定与 `onKeyEvent` 两条路都要落到同一处分发；
   * 分散写会让"某个 id 忘了接"成为一件没有提示的事（而 `ShortcutKeys` 只能保证
   * id 来自表，保证不了"每个 id 都有人处理"）。
   */
  private runShortcut(id: string): void {
    if (id === 'new-session') {
      SessionHub.shared().createSession();
      return;
    }
    if (id === 'toggle-detail') {
      this.detailOpen = !this.detailOpen;
      return;
    }
    if (id === 'pending-inbox') {
      this.selectTab(NavTab.PENDING);
      return;
    }
    if (id === 'open-settings') {
      this.selectTab(NavTab.SETTINGS);
      return;
    }
    if (id === 'reconnect') {
      SessionHub.shared().reconnect();
      return;
    }
    if (id === 'stop-turn') {
      this.escapePressed();
      return;
    }
    if (id === 'send-message') {
      this.sendDraft();
      return;
    }
    if (id === 'search-in-session') {
      // D3 §5.1 的 Ctrl/Cmd+F：打开会话内搜索条（仅会话页有意义）
      if (this.showsConversation()) {
        this.searchOpen = true;
      } else {
        this.attachNotice = '会话内搜索需要先打开一个会话。';
      }
      return;
    }
    if (id === 'command-palette') {
      this.paletteOpen = true;
      SessionHub.shared().refreshCommands();
      // E243：面板同时读目标（官方 ui-goal 的目标栏数据源；未选会话/未连接时中枢会如实说明）
      SessionHub.shared().refreshGoal();
      return;
    }
    if (id === 'toggle-nav') {
      this.attachNotice = '导航栏的显隐当前由窗口宽度自动决定（让步链），手动折叠尚未实现。';
      return;
    }
    if (id === 'copy-code-block') {
      this.attachNotice = '「复制选中代码块」需要消息内的选中状态，尚未实现。';
      return;
    }
    if (id === 'prev-next-message') {
      this.attachNotice = '「上一条 / 下一条消息」跳转尚未实现。';
      return;
    }
  }

  /** `Enter`（无 Shift）与 `Shift+Enter` 的分流 */
  private dispatchKeyHit(hit: ShortcutHit): void {
    if (hit.id.length === 0) {
      return;
    }
    if (hit.id === 'send-message' && hit.delta < 0) {
      // Shift+Enter = 换行：交给输入框自己处理，页面**不**拦截
      return;
    }
    this.runShortcut(hit.id);
  }

  /**
   * `Esc`：先关浮层，再停轮次（D3 §5.1「停止当前轮次（弹二次确认）/ 关闭弹层」）。
   *
   * 顺序不能反：有浮层时按 Esc 的意图是"关掉它"，而不是把正在跑的轮次停掉——
   * 后者是有副作用的破坏性动作，绝不能被"我只是想关个弹窗"触发。
   */
  private escapePressed(): void {
    if (this.choosing !== undefined) {
      this.choosing = undefined;
      return;
    }
    if (this.credentialRef.length > 0) {
      this.credentialRef = '';
      return;
    }
    if (this.textSettingKey.length > 0) {
      this.textSettingKey = '';
      return;
    }
    if (this.structSettingKey.length > 0) {
      this.structSettingKey = '';
      return;
    }
    if (this.running && this.hubConnected) {
      SessionHub.shared().cancelTurn();
    }
    this.running = false;
  }

  // ───────────────────── 枚举选择浮层 ─────────────────────

  @Builder
  choiceSheet() {
    Column() {
      Column({ space: Sp.S }) {
        Text(`选择「${this.choosingLabel}」`)
          .fontSize(Fs.BODY)
          .width('100%')
        Text(`上游设置项 ${this.choosingKey}`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
        ForEach(this.choosing, (choice: SettingChoice) => {
          Row() {
            Text(choice.label)
              .fontSize(Fs.BODY)
              .fontColor(choice.value === this.choosingCurrent
                ? $r('sys.color.brand') : $r('sys.color.font_primary'))
              .layoutWeight(1)
            if (choice.value === this.choosingCurrent) {
              Text('当前')
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.brand'))
            }
          }
          .width('100%')
          .padding(Sp.M)
          .borderRadius(Radius.M)
          .backgroundColor(choice.value === this.choosingCurrent
            ? $r('sys.color.background_primary') : $r('sys.color.background_secondary'))
          .onClick(() => {
            this.applyChoice(choice.value);
          })
        }, (choice: SettingChoice) => choice.value)
        Button('取消')
          .width('100%')
          .backgroundColor($r('sys.color.background_secondary'))
          .fontColor($r('sys.color.font_primary'))
          .onClick(() => {
            this.choosing = undefined;
          })
      }
      .width('86%')
      .padding(Sp.L)
      .borderRadius(Radius.L)
      .backgroundColor($r('sys.color.background_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // 半透明遮罩：明确这是模态，点击空白处不关闭（避免误触丢失选择上下文）
    .backgroundColor('rgba(0,0,0,0.35)')
  }

  /**
   * 写入一个 Host 设置项并把结果如实告诉用户。
   *
   * 【为什么必须把结果回显，而不是乐观更新界面】
   *   乐观更新在这里特别危险：设置项的值会影响**后续所有请求**（模型、超时、重试策略）。
   *   界面显示「已改」而 Host 没改，用户会基于一个假状态继续工作，
   *   而且下次打开设置页才发现值回去了——那时已经很难判断是哪一步出的问题。
   *   所以这里一律等 Host 答复，并按结果给出**可执行**的一句话。
   */
  private async writeSetting(key: string, value: Object, label: string): Promise<void> {
    this.settingWriteNote = `正在写入 ${key}…`;
    const hub: SessionHub = SessionHub.shared();
    const result: SettingsWriteResult = await hub.writeSetting(key, value);
    this.settingWriteNote = result.message;
    // 【不要在这里再套一层 applyHubSnapshot(hub.snapshot())】
    //   中枢在写成功/冲突/被拒时都已经 `notify()` 过，订阅回调会带着
    //   **已与本地偏好合并**的视图刷新界面。手动再套一次快照不但多余，
    //   还会在「快照比 notify 更旧」时把刚刷新的值盖回旧值——
    //   那正是「Host 说写入成功、界面却没变」的成因（实测踩到过）。
    if (result.outcome !== SettingsWriteOutcome.OK) {
      this.hubError = result.message;
    }
  }

  private applyChoice(value: string): void {
    const key: string = this.choosingKey;
    this.choosing = undefined;
    // 本机偏好走端侧持久化 + 立即生效；Host 项走 `settings/mutate`。
    // 分流判据是"这一项在不在 Host 分组里"——与本机偏好分组的存在无关，
    // 因为 Host 分组在未连接时本来就是空的。
    if (this.settingItemOf(key) === undefined) {
      this.writeLocalChoice(key, value);
      return;
    }
    this.writeSetting(key, value as Object, this.choosingLabel);
  }

  /** 在本机偏好分组里找一项 */
  private localItemOf(key: string): SettingItem | undefined {
    for (let i = 0; i < this.localSettings.length; i++) {
      const items: SettingItem[] = this.localSettings[i].items;
      for (let j = 0; j < items.length; j++) {
        if (items[j].key === key) {
          return items[j];
        }
      }
    }
    return undefined;
  }

  /** 写入本机偏好（目前只有主题模式；新增项时在这里加分支并说明它的生效路径） */
  private writeLocalChoice(key: string, value: string): void {
    if (key === LOCAL_THEME_KEY) {
      this.writeLocalTheme(value);
      return;
    }
    // 防御：本机偏好表里出现了没有写入路径的项。如实说明，而不是静默丢弃这次点击。
    this.settingWriteNote = `本机偏好「${key}」尚未实现写入路径（选项已选中，但没有生效）。`;
  }

  // ───────────────────── 选择文件夹（工作区，E100）─────────────────────

  /** 浏览浮层是否打开 */
  @State folderOpen: boolean = false;
  /** 当前浏览目录（绝对路径） */
  @State folderPath: string = '';
  /** 当前目录下的子目录名（已排序） */
  @State folderDirs: string[] = [];
  /** 浏览提示/错误（空串不显示） */
  @State folderNote: string = '';

  private filesDirOf(): string {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      return ctx.filesDir;
    } catch (e) {
      return '';
    }
  }

  /**
   * 打开「选择文件夹」。
   *
   * 【端侧的现实，先说清楚】应用只申请了 INTERNET / GET_NETWORK_INFO / KEEP_BACKGROUND_RUNNING
   * 三项权限，**没有公共存储权限**，所以"选本地文件夹"的范围是**沙箱内可读写目录**——
   * 入口脚本已准备好 `<filesDir>/workspace`，用户可以进去、建子目录、挑一个作为工作区。
   * 这不是降级：端侧核心本来也只能在沙箱里读写；把范围写在界面上，比给一个点了没反应的
   * 「添加」强（原实现正是那样一个死入口）。
   */
  private openFolderPicker(): void {
    /*
     * 【先试系统文件夹选择器（E102）】2in1/平板支持"选真实文件夹"（SDK：
     * `DocumentSelectMode` 仅 2in1），那是"选择本地项目"的正路；手机不支持，
     * 此时**如实说明原因**再回退到沙箱浏览（而不是让入口点了没反应）。
     */
    const ctx = getContext(this) as common.UIAbilityContext;
    pickFolder(ctx).then((picked: PickedFolder) => {
      if (picked.outcome === PickOutcome.PICKED && picked.path.length > 0) {
        this.folderUsePath(picked.path);
        return;
      }
      if (picked.outcome === PickOutcome.CANCELLED) {
        return; // 用户主动取消：不打扰
      }
      // 失败（手机上的常态）：回退到沙箱浏览，并把原因写在浮层顶部
      this.openSandboxFolderPicker(picked.reason);
    }).catch((e: Object) => {
      const err = e as Error;
      this.openSandboxFolderPicker(`文件夹选择器异常：${err.message}`);
    });
  }

  /** 选定一个真实路径作为工作区（注册 + 就地开会话） */
  private folderUsePath(path: string): void {
    const hub: SessionHub = SessionHub.shared();
    hub.setDefaultWorkspace(path);
    this.settingWriteNote = `正在把 ${path} 设为工作区…`;
    hilog.info(DOMAIN, TAG, 'HDSH-WS 选择工作区：%{public}s', path);
    hub.ensureWorkspace(path).then((note: string) => {
      this.settingWriteNote = note;
      hilog.info(DOMAIN, TAG, 'HDSH-WS 注册结果：%{public}s', note);
      return hub.createSession();
    }).then((sid: string | undefined) => {
      if (sid !== undefined) {
        this.settingWriteNote = `已在这里开始工作：${path}`;
        this.selectTab(NavTab.SESSIONS);
      }
    }).catch((e: Object) => {
      const err = e as Error;
      this.settingWriteNote = `选择文件夹失败：${err.message}`;
      hilog.warn(DOMAIN, TAG, 'HDSH-WS 失败：%{public}s', err.message);
    });
  }

  private openSandboxFolderPicker(reason: string): void {
    const root: string = this.localWorkspaceDir.length > 0
      ? this.localWorkspaceDir
      : `${this.filesDirOf()}/workspace`;
    this.folderPath = root;
    this.folderNote = reason;
    this.folderOpen = true;
    this.folderList();
  }

  private folderList(): void {
    try {
      if (!fs.accessSync(this.folderPath)) {
        fs.mkdirSync(this.folderPath);
      }
      const names: string[] = fs.listFileSync(this.folderPath);
      const dirs: string[] = [];
      for (const name of names) {
        try {
          if (fs.statSync(`${this.folderPath}/${name}`).isDirectory()) {
            dirs.push(name);
          }
        } catch (e) {
          // 单个条目读不到不该让整页失败：跳过它
        }
      }
      dirs.sort();
      this.folderDirs = dirs;
      this.folderNote = '';
    } catch (e) {
      const err = e as Error;
      this.folderDirs = [];
      this.folderNote = `读目录失败：${err.message}`;
    }
  }

  private folderGoInto(name: string): void {
    this.folderPath = `${this.folderPath}/${name}`;
    this.folderList();
  }

  /** 上一级；到沙箱根（filesDir）就不再往上，避免走到不可读区域。 */
  private folderGoUp(): void {
    const root: string = this.filesDirOf();
    if (root.length === 0) {
      return;
    }
    if (this.folderPath === root || this.folderPath.length <= root.length) {
      this.folderNote = '已经在沙箱根目录（不能走到沙箱外：没有公共存储权限）。';
      return;
    }
    const cut: number = this.folderPath.lastIndexOf('/');
    if (cut <= root.length) {
      this.folderPath = root;
    } else {
      this.folderPath = this.folderPath.substring(0, cut);
    }
    this.folderList();
  }

  /** 新建子目录并进入（不弹输入框：端侧输入成本高，且名字只是为了区分）。 */
  private folderCreate(): void {
    const now: Date = new Date();
    const name: string = `文件夹-${now.getHours()}${now.getMinutes()}${now.getSeconds()}`;
    try {
      fs.mkdirSync(`${this.folderPath}/${name}`);
      this.folderGoInto(name);
    } catch (e) {
      const err = e as Error;
      this.folderNote = `新建文件夹失败：${err.message}`;
    }
  }

  /**
   * 选定当前目录作为工作区：注册给 Host，并**立刻在这里开一个会话**。
   *
   * 【为什么要顺带建会话】界面的"工作区列表"是由**会话**派生出来的
   * （`projectWorkspaces(sessions)`）。只注册不建会话的话，用户选完目录会看不到任何变化，
   * 又变成一个"点了没反应"的入口。开一个会话，工作区与文件树才真正落在它上面。
   */
  private folderChoose(): void {
    const chosen: string = this.folderPath;
    const hub: SessionHub = SessionHub.shared();
    hub.setDefaultWorkspace(chosen);
    this.folderOpen = false;
    this.settingWriteNote = `正在把 ${chosen} 设为工作区…`;
    hilog.info(DOMAIN, TAG, 'HDSH-WS 选择工作区：%{public}s', chosen);
    hub.ensureWorkspace(chosen).then((note: string) => {
      this.settingWriteNote = note;
      hilog.info(DOMAIN, TAG, 'HDSH-WS 注册结果：%{public}s', note);
      return hub.createSession();
    }).then((sid: string | undefined) => {
      if (sid !== undefined) {
        this.settingWriteNote = `已在这里开始工作：${chosen}`;
        this.selectTab(NavTab.SESSIONS);
      }
    }).catch((e: Object) => {
      const err = e as Error;
      this.settingWriteNote = `选择文件夹失败：${err.message}`;
      hilog.warn(DOMAIN, TAG, 'HDSH-WS 失败：%{public}s', err.message);
    });
  }

  @Builder
  folderSheet() {
    Column() {
      Column({ space: Sp.S }) {
        Text('选择工作区文件夹')
          .fontSize(Fs.BODY)
          .width('100%')
        Text('范围是应用的沙箱目录（未申请公共存储权限）：可以进入子目录、新建文件夹、挑一个作为工作区；选定后会在这里开一个新会话。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
        Text(this.folderPath)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Scroll() {
          Column({ space: Sp.XS }) {
            if (this.folderDirs.length === 0) {
              Text('（这一层没有子目录）')
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
            }
            ForEach(this.folderDirs, (name: string) => {
              Row({ space: Sp.S }) {
                SymbolGlyph($r('sys.symbol.folder')).fontSize(16)
                  .fontColor([$r('sys.color.brand')])
                Text(name)
                  .fontSize(Fs.SECONDARY)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14)
                  .fontColor([$r('sys.color.font_tertiary')])
              }
              .width('100%')
              .padding(Sp.S)
              .borderRadius(Radius.S)
              .backgroundColor($r('sys.color.background_primary'))
              .onClick(() => {
                this.folderGoInto(name);
              })
            }, (name: string) => name)
          }
          .width('100%')
        }
        .height(220)
        .width('100%')

        if (this.folderNote.length > 0) {
          Text(this.folderNote)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.warning'))
            .width('100%')
        }

        Row({ space: Sp.S }) {
          Button('上一级')
            .layoutWeight(1)
            .backgroundColor($r('sys.color.background_primary'))
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => {
              this.folderGoUp();
            })
          Button('新建文件夹')
            .layoutWeight(1)
            .backgroundColor($r('sys.color.background_primary'))
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => {
              this.folderCreate();
            })
        }
        .width('100%')

        Row({ space: Sp.S }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor($r('sys.color.background_secondary'))
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => {
              this.folderOpen = false;
            })
          Button('就选这个文件夹')
            .layoutWeight(1)
            .onClick(() => {
              this.folderChoose();
            })
        }
        .width('100%')
      }
      .width('86%')
      .constraintSize({ maxHeight: '82%' })
      .padding(Sp.L)
      .borderRadius(Radius.L)
      .backgroundColor($r('sys.color.background_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.35)')
  }

  // ───────────────────── 凭据写入浮层 ─────────────────────

  /**
   * 凭据编辑浮层。
   *
   * 三条刻意的设计：
   *   1. **输入框是密码型**（`InputType.Password`）：凭据值不该在有人旁观时明文显示，
   *      也不该被输入法学习/记录（`enableAutoFill(false)` 关掉自动填充联想）。
   *   2. **明确写出「明文只在本机内存里存在一次」**：用户有权知道他们的密钥
   *      去了哪里——写到 Host 的凭据存储，本客户端不留副本（D1 §11.5 S3/S4）。
   *      不写这句，用户会合理地担心自己的密钥被留在了手机上。
   *   3. **清除是单独的、二次确认的动作**：删除凭据会让依赖它的功能立刻失效，
   *      不该和「保存」长得一样。
   */
  @Builder
  credentialSheet() {
    Column() {
      Column({ space: Sp.S }) {
        Text(`配置 ${this.credentialRef}`)
          .fontSize(Fs.BODY)
          .width('100%')
        Text('值会写入 Host 的凭据存储；本客户端只在这一次请求里持有明文，不会保存副本。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        TextInput({ placeholder: '粘贴凭据值', text: this.credentialDraft })
          .type(InputType.Password)
          .enableAutoFill(false)
          .width('100%')
          // 【显式高度（E95）】不给高度时，输入框会跟着父级约束变化；真机上出现过
          // "凭据值铺满整屏"的观感。44vp 是单行输入的标准高度，明确写出来最省事。
          .height(44)
          .onChange((v: string) => {
            this.credentialDraft = v;
          })

        Row({ space: Sp.S }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor($r('sys.color.background_secondary'))
            .fontColor($r('sys.color.font_primary'))
            .enabled(!this.credentialBusy)
            .onClick(() => {
              this.closeCredentialSheet();
            })
          Button(this.credentialBusy ? '写入中…' : '保存到 Host')
            .layoutWeight(1)
            .enabled(this.credentialDraft.length > 0 && !this.credentialBusy)
            .onClick(() => {
              this.submitCredential();
            })
        }
        .width('100%')

        if (this.credentialConfigured) {
          Button('清除 Host 上的这项凭据')
            .width('100%')
            .enabled(!this.credentialBusy)
            .backgroundColor($r('sys.color.background_secondary'))
            .fontColor($r('sys.color.warning'))
            .onClick(() => {
              this.clearCredential();
            })
        }

        if (this.credentialNote.length > 0) {
          Text(this.credentialNote)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
      }
      .width('86%')
      // 浮层自身也不该铺满：最多占屏高 80%（凭据浮层通常很短；这条是防止
      // "某个字段把面板撑开"这类观感再次发生）
      .constraintSize({ maxHeight: '80%' })
      .padding(Sp.L)
      .borderRadius(Radius.L)
      .backgroundColor($r('sys.color.background_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.35)')
  }

  private closeCredentialSheet(): void {
    this.credentialRef = '';
    // 清掉草稿：明文不该因为「关掉了浮层」而继续留在状态里
    this.credentialDraft = '';
    this.credentialNote = '';
    this.credentialBusy = false;
  }

  /** 当前编辑的凭据是否已配置（决定是否显示「清除」） */
  private credentialConfigured: boolean = false;

  private openCredentialSheet(ref: string): void {
    for (let i = 0; i < this.credentials.length; i++) {
      if (this.credentials[i].ref === ref) {
        this.credentialConfigured = this.credentials[i].configured;
      }
    }
    this.credentialDraft = '';
    this.credentialNote = '';
    this.credentialBusy = false;
    this.credentialRef = ref;
  }

  private async submitCredential(): Promise<void> {
    const ref: string = this.credentialRef;
    const value: string = this.credentialDraft;
    // 先清草稿再发请求：请求发出后明文就不再需要留在内存里，
    // 也避免用户重复点击导致重复写入。
    this.credentialDraft = '';
    this.credentialBusy = true;
    this.credentialNote = `正在写入 ${ref}…`;
    const hub: SessionHub = SessionHub.shared();
    const result: CredentialWriteResult = await hub.setCredential(ref, value);
    this.credentialBusy = false;
    if (result.ok) {
      // 【成功时必须关掉浮层】`HubSnapshot` 里没有凭据写入的结果字段，
      // 而浮层盖住了凭据列表——用户看不到状态已经变成「已配置」，
      // 会以为写入没生效（实测踩到：Host 已经 configured=true，
      // 而界面还停在浮层上）。
      // 关掉浮层让列表回到视野，成功信息写到列表上方那条回显里。
      this.settingWriteNote = result.message;
      this.closeCredentialSheet();
      this.applyHubSnapshot(hub.snapshot());
      return;
    }
    // 失败留在浮层里：用户需要就地改值重试，而不是被赶回列表
    this.credentialNote = result.message;
  }

  private async clearCredential(): Promise<void> {
    const ref: string = this.credentialRef;
    this.credentialBusy = true;
    this.credentialNote = `正在清除 ${ref}…`;
    const hub: SessionHub = SessionHub.shared();
    const result: CredentialWriteResult = await hub.unsetCredential(ref);
    this.credentialBusy = false;
    if (result.ok) {
      this.settingWriteNote = result.message;
      this.closeCredentialSheet();
      this.applyHubSnapshot(hub.snapshot());
      return;
    }
    this.credentialNote = result.message;
  }

  // ───────────────────── 文本 / 数字设置编辑浮层 ─────────────────────

  /**
   * 文本与数字设置项的编辑浮层。
   *
   * 【为什么用文本输入而不是数字步进器】实测设置里的数字项跨度极大
   * （`llm-deepseek.maxTokens` 的默认值是 256000，上界 9007199254740991），
   * 步进器要点几万次；而数量级不同的项又需要不同的步进。文本输入 + 客户端校验
   * （`parseSettingInput`：类型、min/max、step、pattern）更实用。
   *
   * 【为什么用 `InputType.Normal` 而不是 Password】这是配置项不是秘密；
   * 而且用户需要看见自己输的数字有没有多一个 0——`maxTokens: 2560000` 与
   * `256000` 的差别在这里是实打实的后果。
   */
  @Builder
  textSettingSheet() {
    Column() {
      Column({ space: Sp.S }) {
        Text(`编辑「${this.textSettingLabel}」`)
          .fontSize(Fs.BODY)
          .width('100%')
        Text(this.textSettingHint())
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
        Text(`上游设置项 ${this.textSettingKey}`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        TextInput({ placeholder: this.textSettingPlaceholder(), text: this.textSettingDraft })
          .type(InputType.Normal)
          .width('100%')
          .onChange((v: string) => {
            this.textSettingDraft = v;
          })

        Row({ space: Sp.S }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor($r('sys.color.background_secondary'))
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => {
              this.closeTextSettingSheet();
            })
          Button('写入 Host')
            .layoutWeight(1)
            .enabled(this.textSettingDraft.length > 0 && !this.credentialBusy)
            .onClick(() => {
              this.submitTextSetting();
            })
        }
        .width('100%')

        if (this.credentialNote.length > 0) {
          Text(this.credentialNote)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
      }
      .width('86%')
      .padding(Sp.L)
      .borderRadius(Radius.L)
      .backgroundColor($r('sys.color.background_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.35)')
  }

  /** 编辑浮层里的约束说明（把服务端约束在**输入前**讲清楚） */
  private textSettingHint(): string {
    const item: SettingItem | undefined = this.textSettingItem;
    if (item === undefined) {
      return '';
    }
    const parts: string[] = [];
    if (item.valueType === SettingValueType.NUMBER) {
      parts.push('请输入数字');
      if (item.hasMin || item.hasMax) {
        parts.push(`范围 ${item.hasMin ? item.minValue : '不限'} – ${item.hasMax ? item.maxValue : '不限'}`);
      }
      if (item.stepValue > 1) {
        parts.push(`须为 ${item.stepValue} 的整数倍`);
      }
    } else {
      parts.push('请输入文本');
      if (item.pattern.length > 0) {
        parts.push(`须匹配 ${item.pattern}`);
      }
    }
    if (item.required) {
      parts.push('必填');
    }
    return parts.join('；');
  }

  private textSettingPlaceholder(): string {
    const item: SettingItem | undefined = this.textSettingItem;
    if (item === undefined) {
      return '';
    }
    return item.textValue.length > 0 ? `当前：${item.textValue}` : '当前未设置';
  }

  private closeTextSettingSheet(): void {
    this.textSettingKey = '';
    this.textSettingDraft = '';
    this.textSettingItem = undefined;
    this.credentialNote = '';
    this.credentialBusy = false;
  }

  private openTextSettingSheet(item: SettingItem): void {
    this.textSettingKey = item.key;
    this.textSettingLabel = item.label;
    // 预填当前值：改一个长数字串时，让用户从现值改起比从空开始可靠得多
    this.textSettingDraft = item.textValue;
    this.textSettingItem = item;
    this.credentialNote = '';
    this.credentialBusy = false;
  }

  private async submitTextSetting(): Promise<void> {
    const item: SettingItem | undefined = this.textSettingItem;
    if (item === undefined) {
      return;
    }
    // 客户端先校验：Host 的拒绝文案是给开发者看的（「不符合 schema」），
    // 而用户需要的是「不能大于 17」这类具体原因（见 parseSettingInput 的说明）。
    const parsed: SettingInputResult = parseSettingInput(item, this.textSettingDraft);
    if (!parsed.ok || parsed.value === undefined) {
      this.credentialNote = parsed.message;
      return;
    }
    const key: string = item.key;
    this.credentialBusy = true;
    this.credentialNote = `正在写入 ${key}…`;
    const hub: SessionHub = SessionHub.shared();
    const result: SettingsWriteResult = await hub.writeSetting(key, parsed.value);
    this.credentialBusy = false;
    if (result.outcome === SettingsWriteOutcome.OK) {
      this.settingWriteNote = result.message;
      this.closeTextSettingSheet();
      return;
    }
    // 冲突/被拒/失败都留在浮层里：用户需要就地看到原因并改值重试
    this.credentialNote = result.message;
  }

  // ───────────────────── 结构化值（数组 / 对象）整值编辑浮层 ─────────────────────

  /**
   * 结构化设置的**整值**编辑浮层。
   *
   * 设计取舍：
   *   1. **多行 `TextArea`**：实测 `llm-deepseek.models` 的 JSON 约 820 字符、
   *      `providers` 更大；单行输入框在这里不可用。
   *   2. **打开时美化（缩进 2 空格）**，写回时用紧凑形式：
   *      人读写需要缩进，而对 Host 来说空白无意义——紧凑形式也能让「值是否变化」
   *      的比较不受无关空白干扰。
   *   3. **给出「恢复为当前值」按钮**：整值编辑最容易出的事故是
   *      改坏了一个大 JSON 又退不回去。有了它，用户永远能回到进入编辑器时的状态。
   *   4. 明确写出「整值替换」：用户必须知道写回是**替换整个字段**，
   *      不是合并——否则会以为没提到的部分会被保留。
   */
  @Builder
  structSettingSheet() {
    Column() {
      Column({ space: Sp.S }) {
        Text(`编辑「${this.structSettingLabel}」`)
          .fontSize(Fs.BODY)
          .width('100%')
        Text('写回是**逐键合并**：这里没提到的键会保留 Host 上已有的值，不会被删除。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
        Text('本客户端暂不提供「删除某个键」的入口（那需要 unset 操作；实测顶层与嵌套路径都可用）。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
        Text(`上游设置项 ${this.structSettingKey}`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        TextArea({ placeholder: 'JSON', text: this.structSettingDraft })
          .width('100%')
          .height(320)
          .onChange((v: string) => {
            this.structSettingDraft = v;
          })

        Row({ space: Sp.S }) {
          Button('恢复为当前值')
            .layoutWeight(1)
            .backgroundColor($r('sys.color.background_secondary'))
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => {
              this.resetStructDraft();
            })
          Button('取消')
            .layoutWeight(1)
            .backgroundColor($r('sys.color.background_secondary'))
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => {
              this.closeStructSettingSheet();
            })
        }
        .width('100%')

        Button('写入 Host')
          .width('100%')
          .enabled(!this.credentialBusy)
          .onClick(() => {
            this.submitStructSetting();
          })

        // 「恢复默认」= `unset`：移除该项在 Host 用户层的取值，值回落到 schema 默认。
        // 【文案必须说成「恢复默认」而不是「清空」】实测 `unset` 的语义是回落默认；
        // 而「把值设为 null」是另一回事（`null` 在若干 schema 里是合法取值）。
        // 两者混为一谈会让用户以为自己清空了、实际只是回到默认（或反过来）。
        // 只有**已被用户覆盖**的项才显示这个入口——对继承默认的项执行 unset 是无操作，
        // 给它一个按钮等于让用户白点一次。
        if (this.structSettingItem !== undefined && this.structSettingItem.userSet) {
          Button('恢复默认（移除这里的设置）')
            .width('100%')
            .enabled(!this.credentialBusy)
            .backgroundColor($r('sys.color.background_secondary'))
            .fontColor($r('sys.color.warning'))
            .onClick(() => {
              this.unsetStructSetting();
            })
        }

        if (this.credentialNote.length > 0) {
          Text(this.credentialNote)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
        }
      }
      .width('92%')
      .padding(Sp.L)
      .borderRadius(Radius.L)
      .backgroundColor($r('sys.color.background_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.35)')
  }

  /** 把草稿恢复为进入编辑器时的值（整值编辑的安全网） */
  private resetStructDraft(): void {
    const item: SettingItem | undefined = this.structSettingItem;
    if (item === undefined) {
      return;
    }
    this.structSettingDraft = prettyJson(item.rawJson);
    this.credentialNote = '已恢复为 Host 上的当前值（尚未写回）。';
  }

  private closeStructSettingSheet(): void {
    this.structSettingKey = '';
    this.structSettingDraft = '';
    this.structSettingItem = undefined;
    this.credentialNote = '';
    this.credentialBusy = false;
  }

  private openStructSettingSheet(item: SettingItem): void {
    this.structSettingKey = item.key;
    this.structSettingLabel = item.label;
    this.structSettingDraft = prettyJson(item.rawJson);
    this.structSettingItem = item;
    this.credentialNote = '';
    this.credentialBusy = false;
  }

  private async submitStructSetting(): Promise<void> {
    const item: SettingItem | undefined = this.structSettingItem;
    if (item === undefined) {
      return;
    }
    const parsed: SettingInputResult = parseStructInput(item, this.structSettingDraft);
    if (!parsed.ok || parsed.value === undefined) {
      this.credentialNote = parsed.message;
      return;
    }
    const key: string = item.key;
    this.credentialBusy = true;
    this.credentialNote = `正在写入 ${key}…`;
    const hub: SessionHub = SessionHub.shared();
    // 整值写回：`parsed.value` 已经是完整的新值（见 SettingKind.STRUCT 的说明）
    const result: SettingsWriteResult = await hub.writeSetting(key, parsed.value);
    this.credentialBusy = false;
    if (result.outcome === SettingsWriteOutcome.OK) {
      this.settingWriteNote = result.message;
      this.closeStructSettingSheet();
      return;
    }
    this.credentialNote = result.message;
  }

  /**
   * 「恢复默认」：移除该项在 Host 用户层的取值。
   *
   * 与「写入」分开是刻意的：`unset` 是**破坏性**的（用户层的值会消失，
   * 值回落到 schema 默认，可能与用户当前看到的不同），
   * 不该和「保存」长得一样、也不该顺手就点到。
   */
  private async unsetStructSetting(): Promise<void> {
    const item: SettingItem | undefined = this.structSettingItem;
    if (item === undefined) {
      return;
    }
    const key: string = item.key;
    this.credentialBusy = true;
    this.credentialNote = `正在恢复 ${key} 的默认值…`;
    const hub: SessionHub = SessionHub.shared();
    const result: SettingsWriteResult = await hub.unsetSetting(key);
    this.credentialBusy = false;
    if (result.outcome === SettingsWriteOutcome.OK) {
      this.settingWriteNote = result.message;
      this.closeStructSettingSheet();
      return;
    }
    this.credentialNote = result.message;
  }

  // ───────────────────── 单栏（手机） ─────────────────────

  @Builder
  buildSingle() {
    Column() {
      this.header()
      Divider().color($r('sys.color.comp_divider'))
      Column() {
        this.mainContent(true)
      }
      .layoutWeight(1)
      .width('100%')
      if (this.stackPage === StackPage.MAIN) {
        this.bottomTabs()
      }
    }
    .width('100%')
    .height('100%')
    /* 详情半模态：`isShow` 是单向的，故必须给消失回调复位状态，
       否则下拉关闭后 show 永远停在 true、再也打不开（看起来像点了没反应）。 */
    .bindSheet(this.detailSheetOpen, this.detailSheet(),
      harmonySheetOptions(() => {
        this.detailSheetOpen = false;
      }))
  }

  @Builder
  header() {
    Row({ space: Sp.S }) {
      if (this.stackPage !== StackPage.MAIN) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .accessibilityText('返回')
        .onClick(() => {
          this.stackPage = StackPage.MAIN;
        })
      }
      Text(this.headerTitle())
        .fontSize(Fs.TITLE_L)
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.stackPage === StackPage.CONVERSATION && this.mode !== LayoutMode.TRIPLE) {
        Text('详情')
          .fontSize(HarmonyType.LABEL.size)
          .fontColor(HarmonyColor.BRAND)
          .padding({ left: Sp.S, right: Sp.S, top: Sp.XS, bottom: Sp.XS })
          .borderRadius(HarmonyRadius.CHIP)
          .backgroundColor(HarmonyColor.SURFACE_RAISED)
          .accessibilityText('打开详情面板（半模态，会话内容保持可见）')
          .onClick(() => {
            this.detailSheetOpen = true;
          })
      }
      /*
       * 【页头的 POC 入口已移除（E102）】协议往返验证并入「设置 → 通用 → 本地调试」：
       * 顶部常驻一个 POC 按钮会让它看起来像一个产品功能，而它其实是排障工具；
       * 更重要的是"连接诊断（结论）+ POC（逐步证据）"必须**在同一处**，
       * 否则用户要在两个入口之间来回走。入口保留在诊断页里的「协议往返验证」按钮。
       */
    }
    .width('100%')
    .height(52)
    .padding({ left: Sp.M, right: Sp.S })
  }

  private headerTitle(): string {
    if (this.stackPage === StackPage.CONVERSATION) {
      return this.selectedSessionTitle.length > 0 ? this.selectedSessionTitle : '会话';
    }
    if (this.stackPage === StackPage.DIAGNOSTICS) {
      return '连接诊断';
    }
    if (this.stackPage === StackPage.CONNECT) {
      // 新架构下"连接一台远程 Host"是**可选能力**（D7 §3 第 1 项），
      // 因此标题不再叫"添加 Host"——那会让用户以为这是必经步骤。
      return '远程 Host（可选）';
    }
    return navTabLabel(this.tab);
  }

  @Builder
  bottomTabs() {
    Row() {
      ForEach(navTabs(), (tab: NavTab) => {
        Column({ space: 2 }) {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(navTabSymbol(tab))
              .fontSize(22)
              .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (tab === NavTab.WORKSPACES && this.pendingBadge.length > 0) {
              this.badge(this.pendingBadge)
            }
          }
          Text(navTabLabelRes(tab))
            .fontSize(Fs.CAPTION)
            .fontColor(this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityText(`${navTabLabel(tab)}标签`)
        .onClick(() => {
          this.selectTab(tab);
        })
      }, (tab: NavTab) => tab)
    }
    .width('100%')
    .height(56)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  // ───────────────────── 双栏 ─────────────────────

  @Builder
  buildDouble() {
    Row() {
      this.navRail()
      Divider().vertical(true).color($r('sys.color.comp_divider'))
      Column() {
        this.header()
        Divider().color($r('sys.color.comp_divider'))
        Column() {
          this.mainContent(true)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  navRail() {
    Column({ space: Sp.S }) {
      ForEach(navTabs(), (tab: NavTab) => {
        Column() {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(navTabSymbol(tab))
              .fontSize(22)
              .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (tab === NavTab.WORKSPACES && this.pendingBadge.length > 0) {
              this.badge(this.pendingBadge)
            }
          }
        }
        .width(this.navWidthVp())
        .height(Sz.TOUCH_MIN)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Radius.S)
        .accessibilityText(`${navTabLabel(tab)}标签`)
        .onClick(() => {
          this.selectTab(tab);
        })
      }, (tab: NavTab) => tab)
    }
    .width(this.navWidthVp())
    .height('100%')
    .padding({ top: Sp.M })
    .backgroundColor($r('sys.color.background_secondary'))
  }

  // ───────────────────── 三栏 ─────────────────────

  @Builder
  buildTriple() {
    Row() {
      this.navPanel()
      Divider().vertical(true).color($r('sys.color.comp_divider'))
      Column() {
        this.header()
        Divider().color($r('sys.color.comp_divider'))
        Column() {
          this.mainContent(false)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
      if (this.detailOpen && this.showsConversation()) {
        Divider().vertical(true).color($r('sys.color.comp_divider'))
        this.detailColumn()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  navPanel() {
    Column({ space: Sp.XS }) {
      Text(APP_NAME)
        .fontSize(Fs.TITLE_S)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: Sp.M, top: Sp.M, bottom: Sp.S })

      ForEach(navTabs(), (tab: NavTab) => {
        Row({ space: Sp.M }) {
          SymbolGlyph(navTabSymbol(tab))
            .fontSize(20)
            .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
          Text(navTabLabel(tab))
            .fontSize(Fs.SECONDARY)
            .fontColor(this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_primary'))
            .layoutWeight(1)
          if (tab === NavTab.WORKSPACES && this.pendingBadge.length > 0) {
            Text(this.pendingBadge)
              .fontSize(Fs.CAPTION)
              .fontColor(Color.White)
              .backgroundColor($r('sys.color.alert'))
              .borderRadius(9)
              .padding({ left: 6, right: 6 })
          }
        }
        .width('100%')
        .height(Sz.TOUCH_MIN)
        .padding({ left: Sp.M, right: Sp.M })
        .borderRadius(Radius.S)
        .backgroundColor(this.tab === tab ? $r('sys.color.background_secondary') : Color.Transparent)
        .onClick(() => {
          this.selectTab(tab);
        })
      }, (tab: NavTab) => tab)

      Blank()

      /*
       * 二级入口：**本地调试**（原「连接诊断」与「POC 协议验证」合并，E96）。
       *
       * 【为什么合并】两者回答的是同一个问题——"这台设备上的核心到底通不通"：
       *   · 连接诊断：跑五项判定并给出可执行结论（面向"哪里断了"）；
       *   · POC：把 token→cookie→`/api`→WS 的往返逐步打出来（面向"哪一步错了"）。
       * 分成两个入口时，用户会先点一个、发现信息不够、再退出去点另一个；合并后进一个页面
       * 就能从"结论"下钻到"逐步证据"。它们本来就都是**给本地调试用的**，不是产品功能。
       */
      this.navPanelAction($r('app.string.settings_local_debug'), () => {
        this.openDiagnostics();
      })
    }
    .width(Sz.NAV_PANEL)
    .height('100%')
    .padding({ left: Sp.S, right: Sp.S, bottom: Sp.S })
    .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  navPanelAction(label: ResourceStr, action: () => void) {
    Text(label)
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .height(Sz.TOUCH_MIN - 8)
      .padding({ left: Sp.M })
      .textAlign(TextAlign.Start)
      .onClick(() => {
        action();
      })
  }

  @Builder
  detailColumn() {
    Column() {
      Row({ space: Sp.S }) {
        Text('详情')
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Button() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(16)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .accessibilityText('关闭详情栏')
        .onClick(() => {
          this.detailOpen = false;
        })
      }
      .width('100%')
      .height(Sz.TOUCH_MIN)
      .padding({ left: Sp.M, right: Sp.S })

      Divider().color($r('sys.color.comp_divider'))

      DetailPane({
        sections: this.detailSections,
        onLineTap: (section: string, text: string) => {
          // E130：详情行看起来可点，就得真的做一件事——复制该行
          if (text.length > 0) {
            copyText(text);
          }
        }
      })
    }
    .width(this.detailWidthVp())
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }

  // ───────────────────── 主内容路由 ─────────────────────

  @Builder
  mainContent(compact: boolean) {
    // E190：命令面板（列表来自宿主：CommandCandidate 的 name/args/detail；选中即执行）
    if (this.paletteOpen) {
      Column({ space: Sp.XS }) {
        Row({ space: Sp.S }) {
          Text('命令面板')
            .fontSize(Fs.BODY)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              this.paletteOpen = false;
            })
        }
        .width('100%')
        /*
         * E243：**长期目标**（官方 `ui-goal` 的目标栏）。
         *
         * 直接读中枢快照（与"可添加提供方"同一先例：打开面板时会重新渲染，届时读到最新值）——
         * 少穿两层状态，且不会出现"状态与中枢不一致"。
         * 三种情况分得很清，**不把"没读到"说成"没有目标"**：
         *   · 有目标 ⇒ 显示目标文本；
         *   · 中枢说没有（`goalNote` = 该会话当前没有长期目标）⇒ 如实显示；
         *   · 形状未识别/失败 ⇒ 显示中枢给的原因（含真实顶层键）。
         */
        Row({ space: Sp.S }) {
          Text('长期目标')
            .fontSize(Fs.CAPTION)
            .layoutWeight(1)
          Text(SessionHub.shared().snapshot().goalText.length > 0
            ? SessionHub.shared().snapshot().goalText
            : (SessionHub.shared().snapshot().goalNote.length > 0
              ? SessionHub.shared().snapshot().goalNote
              : '未读取'))
            .fontSize(Fs.CAPTION)
            .fontColor(SessionHub.shared().snapshot().goalText.length > 0
              ? $r('sys.color.font_secondary')
              : $r('sys.color.font_tertiary'))
            .layoutWeight(2)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        /*
         * E195（§13 第 3 项）：**本会话的模型**。
         *
         * 官方把它做成会话输入区的选择器（`dsh-client-ui-model-selection`，写 `session/selectModel`）。
         * 这里放在同一个面板里而不是再造入口：面板本就是"会话操作"的地方、快捷键已绑定
         * ⇒ **可发现、不新增状态**。选中即调 `hub.selectSessionModel`（E194）；
         * 未选会话时如实说明（那条端点也要会话）。
         */
        Text('本会话的模型')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
        if (this.selectedSessionId.length === 0) {
          Text('请先在工作区里选中一个会话，再切换模型。')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        } else {
          ForEach(this.models, (m: ModelOption) => {
            Row({ space: Sp.S }) {
              Text(m.modelId)
                .fontSize(Fs.CAPTION)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(m.provider)
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .padding(Sp.S)
            .borderRadius(Radius.S)
            .backgroundColor(this.selection.modelId === m.modelId
              ? $r('sys.color.background_secondary')
              : $r('sys.color.background_primary'))
            .onClick(() => {
              this.paletteOpen = false;
              SessionHub.shared().selectSessionModel(m.provider, m.modelId, m.defaultEffort)
                .then((n: ActionNotice) => {
                  this.settingWriteNote = this.noticeText(n);
                }).catch((e: Object) => {
                  this.settingWriteNote = '切换会话模型失败：' + (e as Error).message;
                });
            })
          }, (m: ModelOption) => m.provider + '/' + m.modelId)
        }
        if (this.commands.length === 0) {
          Text(this.selectedSessionId.length === 0
            ? '命令取决于具体会话：请先在工作区里选中一个会话。'
            : '宿主没有报告该会话可用的命令（或尚未读取）。')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        } else {
          ForEach(this.commands, (c: CommandCandidate) => {
            Column({ space: 2 }) {
              Text(c.name)
                .fontSize(Fs.SECONDARY)
                .width('100%')
              if (c.detail.length > 0 || c.args.length > 0) {
                Text(c.detail.length > 0 ? c.detail : c.args)
                  .fontSize(Fs.CAPTION)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
              }
            }
            .width('100%')
            .padding(Sp.M)
            .borderRadius(Radius.S)
            .backgroundColor($r('sys.color.background_secondary'))
            .onClick(() => {
              this.paletteOpen = false;
              SessionHub.shared().executeCommand(c.name).then((n: ActionNotice) => {
                this.settingWriteNote = this.noticeText(n);
              }).catch((e: Object) => {
                this.settingWriteNote = '命令执行失败：' + (e as Error).message;
              });
            })
          }, (c: CommandCandidate) => c.name)
        }
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_primary'))
    }
    if (this.stackPage === StackPage.DIAGNOSTICS) {
      DiagnosticsPane({
        report: this.diag,
        running: this.diagRunning,
        // 判定项按模式裁剪（D7 §3 第 4 项）：本地核心模式下 TLS / 认证不适用
        entries: filterDiagEntries(this.diagMode(), this.diag.entries),
        modeTitle: diagTitleOf(this.diagMode()),
        modeHint: diagHintOf(this.diagMode()),
        traceEnabled: this.traceEnabled,
        traceLines: this.traceLines,
        onRerun: () => {
          this.runDiagnostics();
        },
        onToggleTrace: (on: boolean) => {
          this.traceEnabled = on;
          // 打开时显示**中枢的真实旁路日志**，而不是演示行。
          // 演示行只在未连接时作为布局示例出现（见 `applyHubSnapshot`）。
          this.traceLines = on
            ? SessionHub.shared().snapshot().trace
            : [];
        },
        onExportLog: () => {
          this.exportDiagnostics();
        },
        onClearCache: () => {
          // E130：此前是空实现（点了没反应）。清理的是**我们自己缓存的东西**：
          // 旁路日志 / 未识别事件清单 / 缓存的会话与轨迹。
          // **不碰 Host 上的任何数据**——诊断页不该有"顺手删远端东西"的按钮。
          SessionHub.shared().clearLocalCache();
          hilog.info(DOMAIN, TAG, 'HDSH-DIAG 已清理本机缓存');
        },
        onOpenPoc: () => {
          this.openPoc();
        },
        onBack: () => {
          this.stackPage = StackPage.MAIN;
        }
      })
    } else if (this.stackPage === StackPage.CONNECT) {
      ConnectPane({
        hosts: this.hosts,
        address: this.connectAddress,
        token: this.connectToken,
        busy: this.connectBusy,
        resultText: this.connectResult,
        resultOk: this.connectOk,
        resultAdvice: this.connectAdvice,
        discoveryAvailable: false,
        onAddressChange: (v: string) => {
          this.connectAddress = v;
        },
        onTokenChange: (v: string) => {
          this.connectToken = v;
        },
        onSubmit: () => {
          this.connectBusy = true;
          this.connectResult = '';
          this.connectAdvice = '';
          const hub: SessionHub = SessionHub.shared();
          const url: string = composeHostUrl(this.connectAddress, this.connectToken);
          if (!hub.configure(url, undefined)) {
            this.connectOk = false;
            this.connectBusy = false;
            this.connectResult = '地址无法解析';
            this.connectAdvice = '请填形如 http://主机:端口 的地址；token 可单独填，也可直接粘贴完整启动链接（含 ?token=…）。';
            return;
          }
          hub.connect().then((ok: boolean) => {
            this.connectBusy = false;
            this.connectOk = ok;
            const snap: HubSnapshot = hub.snapshot();
            this.connectResult = ok
              ? `已连接 ${snap.authority}，收到 ${snap.sessions.length} 个会话`
              : (snap.lastError.length > 0 ? snap.lastError : '连接未建立');
            this.connectAdvice = ok
              ? '真实数据已接管会话列表与待决；可在「连接诊断」页查看五项判定。'
              : '请确认 Host 已启动且令牌有效；模拟器/真机访问宿主回环需先做端口转发（hdc fport）。';
            if (ok) {
              // 只报告**成功的**连接：失败的地址/token 不该被记住，
              // 否则下次启动会拿一个已知无效的 token 去自动重连，用户看到的是
              // 「自动重连失败」——而正确行为是回到「添加 Host」。
              //
              // token 来自**解析后的 URL**，而不是 token 输入框：
              // 用户用的是「① 粘贴启动 URL」这条路径，token 输入框是空的。
              // 曾因此把空串当 token 存进去，表现为「保存失败 + 下次读不到 token」。
              reportConnectedHost(storageBaseUrl(url), extractToken(url) ?? this.connectToken.trim());
            }
          });
        },
        onStartDiscovery: () => {
        },
        onOpenDiagnostics: () => {
          this.openDiagnostics();
        },
        onBack: () => {
          this.stackPage = StackPage.MAIN;
        }
      })
    } else if (this.showsConversation() && this.stackPage === StackPage.CONVERSATION) {
      // E125：会话统计行（官方措辞），贴在会话页头部——数据来自投影，没有就不占位置
      if (this.statsLine.length > 0) {
        Text(this.statsLine)
          .fontSize(Fs.CAPTION)
          .fontColor(('sys.color.font_tertiary'))
          .width('100%')
          .padding({ left: Sp.M, right: Sp.M, top: Sp.XS })
      }
      ConversationPane({
        itemCount: this.trajectoryItems.length,
        // E115：审批/提问直接弹在会话里（官方 web 的形态），一次点击即可放行
        pending: this.pending,
        onDecidePending: (item: PendingItem, choiceId: string, reason: string) => {
          this.decidePending(item, choiceId, reason);
        },
        onAnswerPending: (item: PendingItem, selected: string[], custom: string) => {
          this.answerPending(item, selected, custom);
        },
        sessionId: this.selectedSessionId,
        items: this.trajectoryItems,
        running: this.running,
        offline: this.offline,
        queuedCount: this.queuedCount,
        draft: this.draft,
        attachments: this.attachments,
        models: this.models,
        selection: this.selection,
        references: this.references,
        commands: this.commands,
        notice: this.attachNotice,
        planActive: this.planActive,
        planPending: this.planPending,
        permissionLabel: this.permissionCurrent,
        onDraftChange: (text: string) => {
          this.draft = text;
        },
        onSend: () => {
          this.sendDraft();
        },
        onStop: () => {
          // 连上后停止 = 真的取消当前轮次；未连接时只熄灭本地指示
          if (this.hubConnected) {
            SessionHub.shared().cancelTurn();
          }
          this.running = false;
        },
        onAddAttachment: () => {
          this.pickAndAttach();
        },
        onRemoveAttachment: (receiptId: string) => {
          SessionHub.shared().removeAttachment(receiptId);
        },
        onPickModel: () => {
          this.selectTab(NavTab.SETTINGS);
        },
        onTogglePlan: () => {
          this.togglePlan();
        },
        // 消息操作条的「复制」：剪贴板是平台能力，回调由宿主提供（视图层不依赖 platform）
        onCopyMessage: (text: string) => {
          if (text.length === 0) {
            this.attachNotice = '这条消息没有可复制的正文。';
            return;
          }
          copyText(text).then((ok: boolean) => {
            this.attachNotice = ok ? '已复制到剪贴板。' : '复制失败：剪贴板不可用。';
          });
        },
        onReferenceQuery: (query: string) => {
          if (this.hubConnected) {
            SessionHub.shared().refreshReferences(query);
          }
        },
        onPullQueued: (itemId: string, text: string) => {
          // 「取回编辑」= 移除该队列项 + 把正文放回草稿。
          // 移除走 Host（否则用户会在界面上看不到它、而它仍会被发送），
          // 放回草稿是本地动作。**先放回再移除**：即使移除失败，
          // 用户也已经拿回了文本，不会丢内容。
          this.draft = text;
          SessionHub.shared().removeQueuedItem(itemId).then((ok: boolean) => {
            if (!ok) {
              this.attachNotice = '已把内容取回输入框，但队列项移除失败——它仍可能被 Host 发送，请检查诊断页。';
            }
          });
        },
        onRemoveQueued: (itemId: string) => {
          SessionHub.shared().removeQueuedItem(itemId);
        },
        onSteerQueued: (itemId: string) => {
          SessionHub.shared().steerQueuedItem(itemId);
        },
        onOpenDetail: () => {
          this.detailSheetOpen = true;
        },
        searchOpen: this.searchOpen,
        onCloseSearch: () => {
          this.searchOpen = false;
        }
      })
    } else {
      this.tabContent(compact)
    }
  }

  /**
   * 答复审批。
   *
   * 上游的审批结果词表是封闭四值（`dshcompat.APPROVAL_OUTCOMES`），**没有「始终允许」**。
   * 因此「本次会话内均允许」被映射为 `allowed-once` 发送，只在本客户端记住「不再打扰」——
   * 绝不为了满足 UI 而去伪造一个上游不认识的词（那会让 Host 直接拒绝或静默误解）。
   * 当前 `always` 标记只写进协议旁路日志，供用户排查时看到「这条其实是逐次询问的」。
   *
   * 未连接时不发任何请求、也不把卡片移除：卡片消失会让用户以为已经答复成功。
   */
  private decidePending(item: PendingItem, choiceId: string, reason: string): void {
    if (!this.hubConnected) {
      return;
    }
    // 【已知缺口】拒绝理由目前**无法随审批应答上传**：上游的审批 outcome 只是一个
    // 封闭词汇里的字符串（`allowed-once | rejected | cancelled | unavailable`），
    // 没有承载理由的字段。用户填的理由因此只能留在本地。
    // 不走「把理由塞进 waterfall 的 rejected 错误」这条歪路——那表达的是
    // 「本应答者处理失败」，会让 Host 转问下一个应答者并最终 fail-closed 成
    // `unavailable`，与「用户明确拒绝」语义完全不同，会把一次明确拒绝变成一次失败。
    // 已作为能力缺口登记在 D2 §8.7.5 与 D3 §3.4 的偏离记录里。
    const allow: boolean = choiceId !== APPROVAL_CHOICE_DENY;
    const always: boolean = choiceId === APPROVAL_CHOICE_ALLOW_ALWAYS;
    SessionHub.shared().decideApproval(item.id, allow, always);
  }

  /** 答复提问（`selected` 是选项 label 原文，符合上游 `AskUserQuestionAnswerItem`）。 */
  private answerPending(item: PendingItem, selected: string[], custom: string): void {
    if (!this.hubConnected) {
      return;
    }
    SessionHub.shared().answerQuestion(item.id, selected, custom);
  }

  /**
   * 发送当前草稿。
   *
   * 连上 Host 时交给中枢（它负责构造兼容面要求的 prompt 载荷、
   * 维护乐观回显对账用的 requestId，以及离线时进待发队列）。
   * 未连接时只清空输入框——**不伪造成功**，否则用户会以为消息发出去了。
   */
  private sendDraft(): void {
    const text: string = this.draft.trim();
    if (text.length === 0) {
      return;
    }
    this.draft = '';
    // 【附件列表**不在这里**清空】它由中枢拥有：回执只在 Host 确认接受这次提示词后
    // 才会被回收，那时中枢清空并广播。在这里乐观清空会让「发送失败」时
    // 附件条目凭空消失——用户既发不出去，也看不到自己加过什么。
    if (this.hubConnected) {
      SessionHub.shared().sendPrompt(text);
    }
  }

  /** 旁路日志尾部（最多 4 行）：状态条只展示最近发生的几步，完整日志在诊断页 */
  private hubTraceTail(): string[] {
    const all: string[] = this.hubTrace;
    if (all.length <= 4) {
      return all;
    }
    return all.slice(all.length - 4);
  }

  @Builder
  hubBanner() {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(16)
          .fontColor([$r('sys.color.warning')])
        Column({ space: 2 }) {
          Text(this.hubError)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          Text(`Host ${this.hubAuthority.length > 0 ? this.hubAuthority : '未配置'} · 连接 ${this.hubPhase} · 逻辑流 ${this.hubStreams}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
        .layoutWeight(1)
        // 「手动重连」是 D3 §4 对断连横幅的**必需**动作：
        // 自动重试有终点（走到「重试已耗尽」就是终态），没有手动入口时
        // 用户在 Host 刚重启、网络刚恢复这类可恢复场景下只能重启应用。
        //
        // 只在确实可以重试时才显示：`idle` 是「还没配置过 Host」，
        // 此时该做的是「添加 Host」而不是重连（否则按钮点了必然失败）。
        if (this.hubPhase === HubPhase.DEGRADED) {
          Text('重连')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              SessionHub.shared().reconnect();
            })
        }
        Text('诊断')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.openDiagnostics();
          })
      }
      .width('100%')

      // 协议旁路日志尾部：把「连上了但列表为空」这类无法从界面区分的症状
      // 变成可读的原始轨迹（D3 §7.8）
      ForEach(this.hubTraceTail(), (line: string) => {
        Text(line)
          .fontSize(Fs.CAPTION_XS)
          .fontFamily('monospace')
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }, (line: string) => line)
    }
    .width('100%')
    .padding(Sp.S)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  /** 诊断模式（D7 §3 第 4 项）：本机核心 / 远程 Host / 未接线 */
  private diagMode(): DiagMode {
    const ready: boolean = this.coreView.phase === CorePhase.READY
      || this.coreView.phase === CorePhase.DEGRADED;
    return diagModeOf(ready, this.hosts.length > 0);
  }

  // ── 端侧核心页（D6）────────────────────────────────────────────────────
  /**
   * 刷新核心页的呈现模型。
   *
   * 【为什么现在只读"版本仓库"、不报任何"就绪"】运行时载体（阶段一的 Electron-on-鸿蒙
   * 运行时 / 阶段二的 libnode.so）**尚未接线**，因此任何"已启动 / 就绪"的说法都是假的。
   * 这里只做两件真实的事：
   *   1. 读沙箱里的核心仓库（已经装了哪些版本、当前/上一版是谁）；
   *   2. 把还没探测到的事实如实写成「未探测 + 探测条件」——而不是编一个值。
   * 这条纪律与项目"界面不说谎"的要求一致（D3 §4）。
   */
  private refreshCoreView(): void {
    this.refreshCoreViewAsync().catch(() => {
    });
  }

  /**
   * 端侧核心的生命周期入口。
   *
   * 【载体已换成阶段二】此前这里用 `NotWiredRuntime`（如实报告"未接线"）。现在运行时门
   * 已在真机通过（D6 E31：`libnode 版本 = 22.23.2`），所以默认载体换成 `NodeRuntime`
   * ——它 import 的 `libdshhost.so` 由 hvigor/CMake 构建（E30：手工放 `.so` 绑不上）。
   *
   * 【入口脚本路径怎么来】`resourceDir` 是 HAP 资源目录，入口脚本随包放在
   * `resources/app/main.js` 下（由 `tools/electron-runtime/place-host-app.ps1` 放置）。
   * 它**不属于任何一版核心树**：核心树可切换/回滚，入口脚本随应用发版
   * （见 `hostruntime` 里 `buildHostArgv` 的说明）。
   */
  private coreHost(filesDir: string, resourceDir: string, cacheDir: string): DshHost {
    if (this.host === null) {
      this.host = new DshHost(filesDir, new NodeRuntime(`${resourceDir}/resources/app/main.js`, filesDir));
    }
    return this.host;
  }

  /**
   * 刷新核心页的呈现模型。
   *
   * 【为什么状态从 DshHost 来，而不是在这里写死】阶段的判断（未接线/未安装/待启动/就绪/失败）
   * 与"为什么"必须只有一个来源，否则核心页与诊断页迟早会给出互相矛盾的结论。
   * 这里只做**映射**：hostruntime 的事实 → appstate 的呈现契约。
   */
  private async refreshCoreViewAsync(): Promise<void> {
    let status: HostStatus | null = null;
    let repoNote: string = '';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const host: DshHost = this.coreHost(ctx.filesDir, ctx.resourceDir, ctx.cacheDir);
      status = await host.status();
      repoNote = `核心树目录：${host.store_().coresDir()}`;
    } catch (e) {
      repoNote = '读取核心树目录失败（详见 hilog）';
    }
    if (status === null) {
      this.coreView = emptyCoreView();
      return;
    }

    const probe: RuntimeProbe = status.probe;
    const facts: CoreFact[] = [
      probe.nodeVersion.length > 0
        ? fact('Node 运行时', probe.nodeVersion, 'ok', '')
        : unknownFact('Node 运行时', '运行时载体接线后显示实际版本（要求 ≥ 22.17.0）'),
      probe.zstd === null
        ? unknownFact('zlib zstd 能力', '会话持久化依赖 node:zlib 的 zstd，接线后自动探测')
        : fact('zlib zstd 能力', probe.zstd ? '可用' : '不可用', probe.zstd ? 'ok' : 'warn',          probe.zstd ? '' : '缺少 zstd 会让会话持久化不可用'),
      probe.jitless === null
        ? unknownFact('JIT 状态', '本项目统一按 jitless 运行，不申请任何特殊权限')
        : fact('JIT 状态', probe.jitless ? '未启用' : '已启用', probe.jitless ? 'ok' : 'warn',
          probe.jitless ? '' : '本项目要求 jitless：不申请特殊权限以保证顺利上架（D6 §4.4）'),
      this.nativeFact(probe),
      probe.listenAddress.length > 0
        ? fact('监听地址', probe.listenAddress,
          probe.listenAddress.startsWith('127.0.0.1') ? 'ok' : 'warn',
          probe.listenAddress.startsWith('127.0.0.1') ? '' : '端侧核心只应监听回环地址')
        : unknownFact('监听地址', '核心起来后应只监听 127.0.0.1'),
      fact('核心仓库',
        status.installed.length > 0 ? `已安装 ${status.installed.length} 个版本` : '空',
        status.installed.length > 0 ? 'ok' : 'warn',
        repoNote),
      this.pluginInventoryFact(status.plugins)
    ];

    /*
     * 【首启阶段：解包中优先于"未安装"（E99）】内置核心的解包发生在 EntryAbility 的
     * `DshHost` 实例里，而页面用的是另一个实例 ⇒ `transient` 看不到，`installed` 又还是空，
     * 于是首启时会话页显示「还没有安装核心」——事实正相反。用 AppStorage 里那个
     * 跨实例标志把阶段纠正为 EXTRACTING（空态文案随之变成「正在解包核心」）。
     */
    const phase: CorePhase = (this.coreInstalling && status.installed.length === 0)
      ? CorePhase.EXTRACTING
      : corePhaseOfHostState(status.state);

    this.coreView = buildCoreView({
      phase: phase,
      title: this.coreInstalling && status.installed.length === 0
        ? '正在解包内置核心（首次启动只需一次）'
        : status.note,
      detail: probe.available
        ? ''
        : '版本仓库与运行时事实现在就能看；载体接线后即可在这里起 Host。',
      busy: this.coreInstalling || hostStateIsTransient(status.state),
      installed: status.installed,
      currentVersion: status.currentVersion,
      previousVersion: status.previousVersion,
      profileName: status.profile,
      facts: facts,
      plugins: this.corePluginRows(status.plugins)
    });
  }

  /**
   * 插件清单的**来源与统计**，作为核心页的一条事实。
   *
   * 【为什么要有这一行】清单是"某个已安装版本"的属性，且它由**打包时**写进树里
   * （端侧不遍历目录现算，见 D6 §6.2.1）。所以用户必须能看出清单来自哪一版；
   * 装的是没有清单的旧包时，也要说清"是这个包没带清单"，而不是让他以为插件为零。
   */
  private pluginInventoryFact(report: HostPluginReport): CoreFact {
    if (report.note.length > 0) {
      return unknownFact('插件清单', report.note);
    }
    const t = report.totals;
    return fact('插件清单',
      `${t.pluginRows} 行 · 纯 JS ${t.pureJs} · 依赖原生 ${t.native}`
        + (t.disabled > 0 ? ` · 默认禁用 ${t.disabled}` : ''),
      t.native > 0 ? 'warn' : 'ok',
      `来自核心 ${report.version}；含原生模块的包 ${report.nativePackages.length} 个。`
        + '「依赖原生」的插件受签名策略约束，只能随应用发版。');
  }

  /**
   * 树内插件清单 → 核心页的行。
   *
   * 端侧的 nativeKind 来自打包时沿**依赖闭包**的判定（D6 §6.2.1），所以这里的分类是
   * **真实取值**，正常情况不会出现「待确认」。
   * `version` 留空：清单描述的是"包内的行"，行本身没有独立版本，编一个版本号比留空更糟。
   */
  private corePluginRows(report: HostPluginReport): PluginRow[] {
    const rows: PluginRow[] = [];
    for (const r of report.rows) {
      rows.push(classifyPlugin(r.name, '', pluginNativeOf(r.nativeKind), r.id, r.disabled));
    }
    // 排序：**先看该看的**。端侧核心实测 152 行里 146 行是"可安装"的普通插件；
    // 按清单原顺序铺开，真正需要用户注意的 6 行（依赖原生、运行时装不了）与
    // 3 行（默认禁用）会被淹掉。
    // **只排序、不隐藏**：插件清单的价值恰恰在于"到底装了什么"能被查全，
    // 藏掉 146 行会让这个问题无法回答。sort 是稳定的，同档内保持清单原顺序。
    const rank = (p: PluginRow): number => {
      if (p.nativeKind === PluginNative.NATIVE) {
        return 0;
      }
      return p.disabled ? 1 : 2;
    };
    rows.sort((a: PluginRow, b: PluginRow) => rank(a) - rank(b));
    return rows;
  }

  /**
   * 安装随应用内置的核心包（首启解包）。
   *
   * 与"启动核心"的区别：这一步**不需要运行时载体**，所以运行时还没接上时也能先把核心装好。
   * 诚实性要求：解压 API 没有进度回调，因此这里**不编造百分比**，只说明"正在解包"与量级。
   */
  private installBundledCore(): void {
    this.installBundledCoreAsync().catch(() => {
    });
  }

  private async installBundledCoreAsync(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const host: DshHost = this.coreHost(ctx.filesDir, ctx.resourceDir, ctx.cacheDir);
      this.coreNotice = '正在安装内置核心：解包约 2.5 万个文件，请勿退出应用……';
      const result: BundledInstallResult = await host.installBundled(ctx.resourceDir, ctx.cacheDir);
      this.coreNotice = result.note;
    } catch (e) {
      const err = e as Error;
      this.coreNotice = `安装内置核心失败：${err.message}`;
    }
    await this.refreshCoreViewAsync();
  }

  /** 原生件加载事实。没有数据时如实写"未探测"，不写 0/N 这种看起来像结论的值。 */  private nativeFact(probe: RuntimeProbe): CoreFact {
    if (probe.natives.length === 0) {
      return unknownFact('原生件加载', 'koffi / node-pty / sharp 三个鸿蒙移植件的加载结果');
    }
    let loaded: number = 0;
    for (let i = 0; i < probe.natives.length; i++) {
      if (probe.natives[i].loaded) {
        loaded++;
      }
    }
    const all: boolean = loaded === probe.natives.length;
    /*
     * 【2/3 到底是谁没加载（E121）】此前只写"2/3 已加载"，用户（和排查的人）无法知道
     * 缺的是哪一件、为什么缺——而"哪一个"直接决定受影响的能力：
     * koffi → 进程/沙箱链，node-pty → 终端，sharp → 图片处理。
     * 这里把**未加载者的名字与原因**一并写出来，原因取自 Host 的探测记录（原生 require 的真实报错）。
     */
    const missing: string[] = [];
    for (let i = 0; i < probe.natives.length; i++) {
      const n = probe.natives[i];
      if (!n.loaded) {
        const why: string = n.note === undefined || n.note.length === 0 ? '原因未记录' : n.note;
        missing.push(`${n.name}：${why}`);
      }
    }
    /*
     * 【E121 修正：缺失件必须写进**值**，不能只放 note】
     * 真机验收时发现：`fact()` 的第三个参数（note）在核心页这一版式里**不渲染**，
     * 于是"2/3 已加载"照旧，缺的是谁、为什么缺，用户仍然看不到——等于没改。
     * 与"界面不撒谎"同一条纪律：**信息要出现在真正被渲染的位置**。
     * 值里只放名字（短），完整原因仍留在 note 里供将来有版式时使用。
     */
    const names: string[] = [];
    for (let i = 0; i < probe.natives.length; i++) {
      const n = probe.natives[i];
      if (!n.loaded) {
        names.push(n.name);
      }
    }
    const value: string = names.length === 0
      ? `${loaded}/${probe.natives.length} 已加载`
      : `${loaded}/${probe.natives.length} 已加载 · 缺 ${names.join(' / ')}`;
    return fact('原生件加载', value,
      all ? 'ok' : 'warn',
      all ? '' : `未加载：${missing.join('；')}`);
  }

  /**
   * 核心页的动作。
   *
   * 【接线原则】能在今天真实执行的，就接真实实现，而不是统一回一句"尚未接线"。
   * 因为"尚未接线"这句话必须**只用于真的没实现的东西**——否则等载体接上以后，
   * 这些按钮还会继续说不接线，而没人会想起来改。具体：
   *   - install  ：解包内置核心包，**不依赖运行时**，早已接线；
   *   - start/stop/restart：`DshHost` 上已实现的真实调用。未接载体时它返回的是
   *                 **真实原因**（运行时探测结果），载体一接上同一段代码就直接可用；
   *   - rollback ：`CoreStore.rollback()` 是真实状态事务，且**不要求健康检查**
   *                （回滚的语义就是退回已知可用的上一版），所以今天就能做；
   *   - import   ：需要文件选择器 + 包校验 + 签名检查，确实还没做；
   *   - diagnose ：需要运行时事实，确实还没做。
   */
  private onCoreAction(id: string): void {
    if (id === 'install') {
      this.installBundledCore();
      return;
    }
    if (id === 'start' || id === 'restart' || id === 'stop') {
      this.coreLifecycleAction(id);
      return;
    }
    if (id === 'rollback') {
      this.rollbackCore();
      return;
    }
    if (id === 'import') {
      this.coreNotice = '「导入核心包」尚未接线：需要文件选择器、容器校验与签名检查'
        + '（校验规则见 hostcore/README.md 的容器契约），现在导入无法保证包可用。';
      return;
    }
    this.coreNotice = '「诊断导出」尚未接线：运行时接上后，这里会导出运行时事实与核心状态。';
  }

  /** 起停核心。restart = 先停再起（stop 是幂等的）。 */
  private coreLifecycleAction(id: string): void {
    this.coreLifecycleActionAsync(id).catch(() => {
      this.coreNotice = '核心操作失败（详见 hilog）';
    });
  }

  private async coreLifecycleActionAsync(id: string): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const host: DshHost = this.coreHost(ctx.filesDir, ctx.resourceDir, ctx.cacheDir);
    const notes: string[] = [];
    if (id === 'stop' || id === 'restart') {
      const stopped: OpResult = await host.stop();
      notes.push(stopped.ok ? '核心已停止' : stopped.message);
    }
    if (id !== 'stop') {
      const started: HostStartResult = await host.start();
      // start() 失败时给的是真实原因（例如运行时未接线的探测结论），不要改写成"请稍后"
      notes.push(started.ok ? started.note : `未启动：${started.note}`);
    }
    this.coreNotice = notes.join('；');
    await this.refreshCoreViewAsync();
  }

  /**
   * 回滚到上一版。
   *
   * `CoreStore.rollback()` 要求 previous 存在且仍是已安装版本（判据在 Types.decideRollback，
   * 可单测），不满足就 REFUSE 且**不动状态**。这里如实区分三种结果：
   * 拒绝、写盘失败、成功。成功后还要说清"核心并未随之重启"——
   * 状态指向变了 ≠ 有东西在跑，这句话不能省。
   */
  /**
   * 回滚到上一版本（E92）：停 → 事务 → 起回滚后的版本 → 重新接入。
   *
   * 【为什么不能只改状态】早先这里只调 `rollback()` 写状态，提示语还写着"核心并未随之重启"——
   * 那是运行时未接线时的旧事实。现在运行时是通的：只改状态会让界面显示的版本与**正在跑的**
   * 版本不一致，那种不一致比回滚失败更难查。所以这里做完整的"停 → 回滚 → 起 → 重连"。
   */
  private rollbackCore(): void {
    this.rollbackCoreAsync().catch(() => {
      this.coreNotice = '回滚失败（详见 hilog）';
    });
  }

  private async rollbackCoreAsync(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const host: DshHost = this.coreHost(ctx.filesDir, ctx.resourceDir, ctx.cacheDir);
    this.coreNotice = '正在回滚：先停当前核心，再把上一版本起回来…';
    this.refreshCoreView();
    const res: OpResult = await host.rollbackTo();
    this.coreNotice = res.message;
    hilog.info(DOMAIN, TAG, 'HDSH-CORE 回滚结果：ok=%{public}s note=%{public}s',
      res.ok ? 'true' : 'false', res.message);
    if (res.ok) {
      this.adoptLocalHostAfterRestart(host);
    }
    this.refreshCoreViewAsync().catch(() => {
    });
  }

  /**
   * 选择某个已安装版本作为**切换目标**。
   *
   * 「切换」走的是 `activate(candidate, health, …)`，而它的判据要求健康检查为 PASS
   * （`Types.decideActivation`：宁可停在旧版本，也不要把没验证过的核心设为当前）。
   * 健康检查必须先把候选版本起一次，因此运行时未接线时这一步**做不了**；
   * 这里不写任何状态，只说明原因。
   */
  /**
   * 写入**默认模型**（E96）：provider / model / reasoningEffort 三个字段一起落到
   * `agent-default-model` 命名空间，由 `SessionHub.setDefaultModel` 负责逐个 set 并处理
   * revision 冲突。结果（含失败原因）通过 `settingWriteNote` 就地回显——设置页顶部那行
   * 就是用户唯一能看到"Host 到底接受了没有"的地方。
   */
  /**
   * 重置一项设置为**部署默认**（E114：对齐官方"重置"）。
   *
   * 走 `settings/unset`（删掉用户层的那一项，值立刻回落到基线/默认），
   * 结果（含冲突/被拒的原因）与写入一样回显在设置页顶部——用户唯一能看到
   * "Host 到底接受了没有"的地方。
   */
  private resetSetting(key: string): void {
    this.settingWriteNote = `正在重置 ${key}…`;
    SessionHub.shared().unsetSetting(key).then((result: SettingsWriteResult) => {
      this.settingWriteNote = result.message;
      hilog.info(DOMAIN, TAG, 'HDSH-SET 重置 %{public}s：%{public}s', key, result.outcome);
    }).catch((e: Object) => {
      const err = e as Error;
      this.settingWriteNote = `重置失败：${err.message}`;
    });
  }

  /**
   * 取本地化字符串（E140：**运行时状态字符串**不能用 `$r`）。
   *
   * 【为什么需要这个函数】`Text('…')` 这类**渲染绑定**直接写 `$r('app.string.x')` 即可，
   * 系统按语言解析；但 `this.settingWriteNote = …` 这类 **string 字段**不行——
   * ArkTS 不会把资源引用解析成文本（塞进去要么编译不过，要么在别处以对象形态露馅）。
   * 正确做法是经**资源管理器**取值。取不到（资源缺失/上下文不可用）时返回空串，
   * 由调用方决定回落到什么文案——**不抛**，因为文案取不到不该让操作失败。
   */
  private localized(id: Resource): string {
    try {
      // E147：取值实现只留一份（platform/system/Strings），页面只负责提供上下文
      const ctx = getContext(this) as common.UIAbilityContext;
      return localizedOr(ctx, id, '');
    } catch (e) {
      return '';
    }
  }

  /**
   * 忘记当前 Host（E137）。
   *
   * 【为什么是"忘记"而不是"吊销"】官方那套是"设备配对 + 逐设备吊销密钥"，而本应用
   * **没有配对模型**：它只记**一个** Host（`rememberedUrl` + token），默认还是本机核心。
   * 所以按钮的真实语义是"忘掉这个地址与令牌"——改了名字才对得上它实际做的事。
   *
   * 【忘记之后会怎样】清掉记住的地址/令牌并断开；下次启动会重新走"本机核心自启 + 自动接入"，
   * 也就是说**不会把用户留在无 Host 的空白状态**。
   */
  private forgetHost(): void {
    AppStorage.setOrCreate<string>('dshLastHostUrl', '');
    AppStorage.setOrCreate<string>('dshLastHostToken', '');
    AppStorage.setOrCreate<string>('dshLastHostTokenState', 'none');
    AppStorage.setOrCreate<boolean>('dshHostAutoConnect', false);
    this.rememberedUrl = '';
    this.rememberedToken = '';
    this.rememberedTokenState = 'none';
    this.shouldAutoConnect = false;
    SessionHub.shared().disconnect();
    this.settingWriteNote = '已忘记这个 Host；下次启动会重新接入本机核心，也可以现在粘贴新的启动链接。';
    hilog.info(DOMAIN, TAG, 'HDSH-CONN 已忘记 Host');
  }

  private applyDefaultModel(provider: string, model: string, effort: string): void {    this.settingWriteNote = `正在写入默认模型 ${provider} / ${model}…`;
    SessionHub.shared().setDefaultModel(provider, model, effort).then((note: string) => {
      this.settingWriteNote = note;
      hilog.info(DOMAIN, TAG, 'HDSH-MODEL 默认模型写入结果：%{public}s', note);
    }).catch((e: Object) => {
      const err = e as Error;
      this.settingWriteNote = `写入默认模型失败：${err.message}`;
      hilog.warn(DOMAIN, TAG, 'HDSH-MODEL 默认模型写入异常：%{public}s', err.message);
    });
  }

  /**
   * 插件行启停（E91）。
   *
   * 【这件事在端侧的真实边界】安装/卸载插件做不到（上游经 pnpm 创建进程，鸿蒙不允许），
   * 但"启停随包发版的行"是纯文件操作：写 `$DSH_HOME/profiles/<profile>/.hdsh-plugin-rows.yml`，
   * 由入口脚本在下次启动时拼进 profile 的 `cordis.patch.yml`。所以这里的结果话术必须带
   * **"重启核心后生效"**——插件树是启动时挂载的，不重启就改了也不生效。
   */
  private onTogglePlugin(id: string, disabled: boolean): void {
    const host: DshHost | null = this.host;
    if (host === null) {
      this.pluginNotice = '核心尚未接线，无法保存插件启停';
      return;
    }
    const res: OpResult = host.setPluginDisabled(id, disabled);
    this.pluginNotice = res.message;
    hilog.info(DOMAIN, TAG, 'HDSH-PLUGIN 设置启停：id=%{public}s disabled=%{public}s ok=%{public}s note=%{public}s',
      id, disabled ? 'true' : 'false', res.ok ? 'true' : 'false', res.message);
    // 清单里的 disabled 会叠加用户行，刷新一次让界面显示"重启后会生效的状态"
    this.refreshCoreView();
  }

  /** 恢复默认启停（清空用户行文件；核心包自带的启停不受影响）。 */
  private onResetPluginRows(): void {
    const host: DshHost | null = this.host;
    if (host === null) {
      this.pluginNotice = '核心尚未接线，无法恢复默认';
      return;
    }
    const res: OpResult = host.resetPluginRows();
    this.pluginNotice = res.ok ? `${res.message}；重启核心后生效` : res.message;
    hilog.info(DOMAIN, TAG, 'HDSH-PLUGIN 恢复默认：ok=%{public}s note=%{public}s',
      res.ok ? 'true' : 'false', res.message);
    this.refreshCoreView();
  }

  /**
   * 选择某个已安装版本作为**切换目标**（E92）。
   *
   * 走 `DshHost.switchTo`：停当前 → 起候选做健康检查 → 通过才激活；候选起不来就把它停掉、
   * 把旧版本起回来并如实报告。健康检查之所以只能是"真的起一次"，见 `Types.decideActivation`
   * 的判据（宁可停在旧版本，也不要把没验证过的核心设为当前）。
   */
  private onCoreSelectVersion(version: string): void {
    this.switchCoreAsync(version).catch(() => {
      this.coreNotice = '切换核心失败（详见 hilog）';
    });
  }

  private async switchCoreAsync(version: string): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const host: DshHost = this.coreHost(ctx.filesDir, ctx.resourceDir, ctx.cacheDir);
    this.coreNotice = `正在切换到 ${version}：先停当前核心，再起候选做健康检查…`;
    this.refreshCoreView();
    const res: OpResult = await host.switchTo(version);
    this.coreNotice = res.message;
    hilog.info(DOMAIN, TAG, 'HDSH-CORE 切换结果：ok=%{public}s note=%{public}s',
      res.ok ? 'true' : 'false', res.message);
    if (res.ok) {
      this.adoptLocalHostAfterRestart(host);
    }
    this.refreshCoreViewAsync().catch(() => {
    });
  }

  /**
   * 核心重启后**重新接入本机 Host**（E92）。
   *
   * 【为什么必须做】切换/回滚都会重启宿主，而 dsh 每个进程都会重新生成启动 token
   * （cookie 也绑进程）⇒ 旧 token 立刻作废。若只重启不重连，界面会停在
   * "刚切完就掉线"，看起来像"切换把连接弄坏了"；而真相是"凭据换了，需要重新取一次"。
   * 取不到新的启动链接时**如实说**，不静默装作没事。
   */
  private adoptLocalHostAfterRestart(host: DshHost): void {
    const url: string = host.localHostReadyUrl();
    if (url.length === 0) {
      this.hubError = '核心已重启，但没能读到新的启动链接（host-ready.json）；请到「设置」页重新接入本机 Host。';
      return;
    }
    const hub: SessionHub = SessionHub.shared();
    if (!hub.configure(url, undefined)) {
      this.hubError = '核心已重启，但新的启动链接形态不合法，未能自动接入。';
      return;
    }
    this.connectBusy = true;
    hub.connect().then((ok: boolean) => {
      this.connectBusy = false;
      const snap: HubSnapshot = hub.snapshot();
      hilog.info(DOMAIN, TAG, 'HDSH-CORE 重启后接入：ok=%{public}s sessions=%{public}d err=%{public}s',
        ok ? 'true' : 'false', snap.sessions.length,
        snap.lastError.length > 0 ? snap.lastError : '(none)');
      if (ok) {
        this.hubError = '';
      } else if (snap.lastError.length > 0) {
        this.hubError = snap.lastError;
      }
    });
  }

  // ───────────────────── 工作区视图（E108：会话与待决并入）─────────────────────

  /** 某个工作区下的会话（按 `cwd` 归一化匹配：工作区本来就是由会话的 cwd 归并出来的） */
  /** 已归档的会话（E134：按注册表归档集过滤；用于归档分组） */
  private archivedSessions(): SessionListItem[] {
    const out: SessionListItem[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const s: SessionListItem = this.sessions[i];
      if (this.archivedSessionIds.indexOf(s.id) >= 0) {
        out.push(s);
      }
    }
    return out;
  }

  /**
   * 工作区 → 注册表 id（E132）。
   *
   * 【为什么按路径匹配】我们的工作区列表由会话 `cwd` 归并而来（没有 id），
   * 而注册表行带 `workspaceId`——两者之间**唯一**可靠的共同键是目录路径。
   * 匹配不到就返回空串：调用方据此**不显示**删除入口，而不是给一个点了没反应的按钮。
   */
  /**
   * 在**指定工作区**里新建会话（E163，用户反馈①）。
   *
   * 【为什么要先注册工作区】会话归属由宿主按 `workspaceId`（注册表 id）记账，
   * 而列表里的工作区是由会话目录归并出来的、本身没有 id。所以顺序是：
   * ①`ensureWorkspace(w.path)` 把该目录注册/解析成工作区并拿到 id，
   * ②`createSession()` 便会带上这个 `workspaceId`（E98 已实现）⇒ 新会话**确实落在这个工作区**，
   * 而不是像以前那样落在"当前默认工作区"（用户看不出是给谁加的）。
   *
   * 未连接时如实提示，不做乐观动作。
   */
  private createSessionIn(w: WorkspaceItem): void {
    const hub: SessionHub = SessionHub.shared();
    if (!this.hubConnected) {
      this.settingWriteNote = '尚未连接 Host，无法新建会话。';
      return;
    }
    this.settingWriteNote = `正在把 ${w.path} 设为当前工作区…`;
    hub.setDefaultWorkspace(w.path);
    hub.ensureWorkspace(w.path).then((note: string) => {
      hilog.info(DOMAIN, TAG, 'HDSH-WS 目标工作区：%{public}s', note);
      return hub.createSession();
    }).then((sid: string | undefined) => {
      this.settingWriteNote = sid === undefined
        ? '新建会话失败：见状态条上的原因。'
        : `已在 ${w.name.length > 0 ? w.name : w.path} 里新建会话。`;
    }).catch((e: Object) => {
      const err = e as Error;
      this.settingWriteNote = `新建会话失败：${err.message}`;
    });
  }

  private registryIdOf(w: WorkspaceItem): string {
    const key: string = normalizePathKey(w.path);
    for (let i = 0; i < this.workspaceRows.length; i++) {
      const row: WorkspaceRow = this.workspaceRows[i];
      if (normalizePathKey(row.path) === key) {
        return row.id;
      }
    }
    return '';
  }

  /** 删除工作区注册（E132）：只删登记，不动磁盘；结果回显在设置页那条提示上 */
  private deleteWorkspaceByPath(w: WorkspaceItem): void {
    const id: string = this.registryIdOf(w);
    if (id.length === 0) {
      this.settingWriteNote = this.localized($r('app.string.note_no_workspace_id'));
      return;
    }
    SessionHub.shared().deleteWorkspace(id).then((n: ActionNotice) => {
      this.settingWriteNote = this.noticeText(n);
      hilog.info(DOMAIN, TAG, 'HDSH-WS 删除工作区：%{public}s', n.code);
    }).catch((e: Object) => {
      const err = e as Error;
      this.settingWriteNote = `${this.localized($r('app.string.note_workspace_delete_failed'))}${err.message}`;
    });
  }

  /**
   * 把中枢的**结构化回执**渲染成本地化文案（E143 方案①）。
   *
   * 【兜底纪律】不认识的码**必须显示"码 + 数据"，而不是空白**——空白会让人以为操作没发生，
   * 而这正是本项目反复清理的那类"界面撒谎"。Host 侧给的原因（`params.reason`）**原样透传**：
   * 它是上游文案，不是我们的 UI 文案，不翻译。
   */
  private noticeText(n: ActionNotice): string {
    if (n.code === 'workspace.deleted') {
      return this.localized($r('app.string.note_workspace_deleted'));
    }
    if (n.code === 'session.archived') {
      return this.localized($r('app.string.note_session_archived'));
    }
    if (n.code === 'workspace.no-id') {
      return this.localized($r('app.string.note_no_workspace_id'));
    }
    if (n.code === 'archive.no-session') {
      return this.localized($r('app.string.note_archive_no_session'));
    }
    if (n.code === 'offline') {
      return this.localized($r('app.string.note_offline'));
    }
    if (n.code === 'contract.missing') {
      return `${this.localized($r('app.string.note_contract_missing'))}${n.params.endpoint}`;
    }
    if (n.code === 'workspace.delete.failed') {
      return `${this.localized($r('app.string.note_workspace_delete_failed'))}${n.params.reason}`;
    }
    // E170：预设的复制/删除回执（宿主原因原样透传；随附预设的只读由宿主强制）
    if (n.code === 'preset.copied') {
      return `已复制为预设「${n.params.id}」。会话创建时固定用哪一份，改默认只影响此后新建的会话。`;
    }
    if (n.code === 'preset.deleted') {
      return `已删除预设「${n.params.id}」；已据它组装的会话继续运行。`;
    }
    /*
     * E220：命令与模型选择的回执文案。
     * 这两批码在 E188/E194 引入时**只写了中枢、没接文案**（会落到"码 + 数据"的兜底显示）——
     * 兜底本身是对的（不撒谎），但能说人话就该说人话。
     */
    if (n.code === 'command.executed') {
      return `已执行「${n.params.name}」。`;
    }
    if (n.code === 'command.failed') {
      return `命令执行失败：${n.params.reason}`;
    }
    if (n.code === 'command.not-loaded') {
      return '命令目录尚未加载（需要先选中一个会话让宿主报告命令），请稍后重试。';
    }
    if (n.code === 'command.no-name') {
      return '未选择要执行的命令。';
    }
    if (n.code === 'model.selected') {
      return `本会话已改用「${n.params.model}」。`;
    }
    if (n.code === 'model.select.failed') {
      return `切换本会话模型失败：${n.params.reason}`;
    }
    if (n.code === 'model.needs-session') {
      return '请先在工作区里选中一个会话，再切换模型。';
    }
    if (n.code === 'model.incomplete') {
      return '切换模型需要提供方与模型名两者。';
    }
    if (n.code === 'preset.copy.failed') {
      return `复制预设失败：${n.params.reason}`;
    }
    if (n.code === 'preset.delete.failed') {
      return `删除预设失败：${n.params.reason}`;
    }
    if (n.code === 'preset.copy.missing') {
      return '复制预设需要"来源 + 新标识 + 名称"三项，缺一不可（宿主 schema 如此）。';
    }
    if (n.code === 'preset.delete.missing') {
      return '未指定要删除的预设。';
    }
    if (n.code === 'archive.failed') {
      return `${this.localized($r('app.string.note_archive_failed'))}${n.params.reason}`;
    }
    // 兜底：显示码与数据本身（绝不显示空白）
    return `${n.code} ${JSON.stringify(n.params)}`;
  }

  private sessionsOf(w: WorkspaceItem): SessionListItem[] {
    const key: string = normalizePathKey(w.path);
    const out: SessionListItem[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const s: SessionListItem = this.sessions[i];
      if (s.cwd.length > 0 && normalizePathKey(s.cwd) === key) {
        // E132：已归档的会话从常规分组隐去（归档集是注册表全局的）
        if (this.archivedSessionIds.indexOf(s.id) >= 0) {
          continue;
        }
        out.push(s);
      }
    }
    return out;
  }

  /**
   * 打开某个工作区的**文件**视图（下钻一层）。
   *
   * 文件接口的作用域是**会话级**（`workspaceFileScopeId` = 会话 id），所以必须先在这个目录下
   * 有会话才看得到文件——这就是原实现里那条空态文案的由来。这里直接取该工作区的第一个会话当作用域。
   */
  private openWorkspaceFiles(w: WorkspaceItem): void {
    const scope: SessionListItem[] = this.sessionsOf(w);
    this.pendingWorkspacePick = true;
    if (scope.length === 0) {
      this.treeEmptyTitle = '该工作区下还没有会话';
      this.treeEmptyHint = '文件浏览的作用域是会话级（workspaceFileScopeId = 会话 id），请先在这个目录里新建一个会话。';
      this.wsDrill = 1;
      return;
    }
    this.treeEmptyTitle = '该目录暂无文件';
    this.treeEmptyHint = '目录确实为空，或 Host 拒绝列出它的内容（详见连接诊断）。';
    if (this.hubConnected) {
      SessionHub.shared().openWorkspace(scope[0].id);
    }
    this.wsDrill = 1;
  }

  /**
   * 工作区视图：动作行 → 待决（若有）→ 工作区分组（组内列会话）。
   *
   * 【为什么把待决放在最上面】它属于"现在就需要你动手"的东西，藏在别处等于拖延；
   * 而官方 web 也是把审批/提问直接摆在对话流里，不另开页签。
   */
  @Builder
  workspaceHub(compact: boolean) {
    Column({ space: Sp.S }) {
      // 连接状态条（E111）：**先区分"正在连"与"连不上"**。
      // 启动时要等本机核心就绪（几十秒），这段时间中枢的 lastError 可能带着中间态文本；
      // 无条件渲染它，用户就会看到「无法连接核心」闪一下——那是假报错。
      if (this.connectBusy || !this.connectSettled) {
        Text($r('app.string.connecting_local_core'))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding(Sp.S)
          .borderRadius(Radius.S)
          .backgroundColor($r('sys.color.background_secondary'))
      } else if (this.hubError.length > 0) {
        this.hubBanner()
      }

      Row({ space: 4 }) {
        /*
         * E163（用户反馈①）：**顶层不再放「新建会话」**。
         * 用户原话："新建会话应当在工作区文件夹上点击，而不是处在顶层外围，不然不知是给哪个工作区加会话。"
         * 现在入口在每个工作区组头（见 `workspaceGroup`），建会话时会把该工作区注册成目标 ⇒
         * "给哪个工作区加会话"从"猜"变成"看得见"。
         */
        Text('选择工作区后，在其组头点「+ 会话」')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height(Sz.TOUCH_MIN)
      Blank()
      Text($r('app.string.action_choose_folder'))
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.brand'))
        .onClick(() => {
          this.openFolderPicker();
        })
      .width('100%')
      .height(Sz.TOUCH_MIN)

      if (this.pending.length > 0) {
        Column({ space: Sp.XS }) {
          Text(`待你决定 · ${this.pending.length}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.warning'))
            .width('100%')
          PendingPane({
            items: this.pending,
            onDecide: (item: PendingItem, choiceId: string, reason: string) => {
              this.decidePending(item, choiceId, reason);
            },
            onAnswer: (item: PendingItem, selected: string[], custom: string) => {
              this.answerPending(item, selected, custom);
            }
          })
        }
        .width('100%')
        .constraintSize({ maxHeight: 320 })
      }

      /*
       * E134：归档列表（官方语义：注册表全局归档集）。
       *
       * 【为什么是只读】线协议只给了 `workspace/archiveSession`，**没有反向端点**——
       * 所以这里列出它们、可以点开看，但不提供"恢复"（那会是个点不动的按钮）。
       * 归档集为空时整段不出现，不占版面。
       */
      if (this.archivedSessionIds.length > 0) {
        /*
         * E165：归档**默认折叠**（反馈②）。这一行是入口；点开才列出已归档会话。
         * 说明文字写清语义，避免"归档了为什么还在这里"的误解。
         */
        Row({ space: Sp.S }) {
          Text(`${$r('app.string.section_archive')} · ${this.archivedSessionIds.length}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .layoutWeight(1)
          Text(this.archiveOpen ? '收起' : '展开')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
        }
        .width('100%')
        .padding(Sp.M)
        .borderRadius(Radius.S)
        .backgroundColor($r('sys.color.background_secondary'))
        .onClick(() => {
          this.archiveOpen = !this.archiveOpen;
        })

        if (this.archiveOpen) {
        Column({ space: Sp.XS }) {
          Text(`${$r('app.string.section_archive')} · ${this.archivedSessionIds.length}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
          ForEach(this.archivedSessions(), (s: SessionListItem) => {
            Row({ space: Sp.S }) {
              SymbolGlyph($r('sys.symbol.archivebox')).fontSize(16)
                .fontColor([$r('sys.color.font_secondary')])
              Text(s.title.length > 0 ? s.title : $r('app.string.label_unnamed_session'))
                .fontSize(Fs.SECONDARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(formatClock(s.updatedAt))
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .padding(Sp.M)
            .borderRadius(Radius.S)
            .backgroundColor($r('sys.color.background_primary'))
            .onClick(() => {
              this.openSession(s.id);
            })
          }, (s: SessionListItem) => s.id)
        }
        .width('100%')
        .padding(Sp.M)
        .borderRadius(Radius.M)
        .backgroundColor($r('sys.color.background_secondary'))
        }
      }

      if (this.workspaces.length === 0) {
        // 空态按核心阶段分档（D7 §3 第 7 项）：把"看不到会话"引向正确的排查方向
        Column({ space: Sp.S }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(36)
            .fontColor([$r('sys.color.font_tertiary')])
          Text(sessionEmptyCopy(this.coreView.phase).title)
            .fontSize(Fs.BODY)
            .fontColor($r('sys.color.font_secondary'))
          Text(sessionEmptyCopy(this.coreView.phase).hint)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: Sp.M }) {
          ForEach(this.workspaces, (w: WorkspaceItem) => {
            ListItem() {
              this.workspaceGroup(w)
            }
          }, (w: WorkspaceItem) => w.path)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding(Sp.M)
  }

  /** 一个工作区：组头（名字/路径/会话数/文件入口）+ 组内会话行 */
  @Builder
  workspaceGroup(w: WorkspaceItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        SymbolGlyph($r('sys.symbol.folder')).fontSize(16)
          .fontColor([w.primary ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
        Column({ space: 2 }) {
          Text(w.name.length > 0 ? w.name : w.path)
            .fontSize(Fs.BODY)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${w.path} · ${w.sessionCount} 会话`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        // E163：**在该工作区里建会话**（反馈①：入口挂在工作区上，用户看得见"给谁加"）
        Text('+ 会话')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.createSessionIn(w);
          })
        Text($r('app.string.action_files'))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.openWorkspaceFiles(w);
          })
        /*
         * E132：删除工作区（只删**注册**，不删目录）。
         *
         * 【为什么要两步确认】它虽然不动磁盘文件，但会让"这个目录在这里出现过、以及它下面
         * 那些会话的归属"消失——一次误触的代价不小，而 ArkUI 的 Row 里塞不下一个说得清楚的
         * 确认弹窗。所以同一位置先变成「确认删除 / 取消」，用户看清了再按。
         * 【为什么有时不显示】删除需要**注册表 id**；列表里的工作区是由会话 cwd 归并出来的，
         * 只有注册表里登记过的才有 id。没有 id 就**不显示**这个入口（而不是给一个点了没反应的）。
         */
        if (this.registryIdOf(w).length > 0) {
          Text(this.confirmingDeletePath === w.path
            ? $r('app.string.action_delete_confirm')
            : $r('app.string.action_delete'))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.alert'))
            .onClick(() => {
              if (this.confirmingDeletePath === w.path) {
                this.confirmingDeletePath = '';
                this.deleteWorkspaceByPath(w);
              } else {
                this.confirmingDeletePath = w.path;
                // E140：状态字符串经资源管理器取值；并附上名字——确认框必须指名道姓
                const note: string = this.localized($r('app.string.confirm_delete_workspace_note'));
                this.settingWriteNote = note.length > 0
                  ? `${note}（${w.name.length > 0 ? w.name : w.path}）`
                  : `再按一次「确认删除」即移除该工作区的登记；磁盘上的目录与文件不会被删除。（${w.name.length > 0 ? w.name : w.path}）`;
              }
            })
        }
      }
      .width('100%')

      ForEach(this.sessionsOf(w), (s: SessionListItem) => {
        Column({ space: 2 }) {
          Row({ space: Sp.S }) {
            Text(s.title.length > 0 ? s.title : $r('app.string.label_unnamed_session'))
              .fontSize(Fs.SECONDARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (s.running) {
              Text($r('app.string.status_running'))
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.brand'))
            }
            /*
             * E134：归档会话（官方语义是"注册表全局归档集"）。
             * 【为什么没有"取消归档"】线协议里只有 `workspace/archiveSession`，
             * **没有反向端点**——所以这里只提供归档，不造一个点不动的"恢复"。
             */
            Text($r('app.string.action_archive'))
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .onClick(() => {
                SessionHub.shared().archiveSession(s.id).then((n: ActionNotice) => {
                  this.settingWriteNote = this.noticeText(n);
                }).catch((e: Object) => {
                  const err = e as Error;
                  this.settingWriteNote = `${this.localized($r('app.string.note_archive_failed'))}${err.message}`;
                });
              })
          }
          .width('100%')
          Text(s.blank ? $r('app.string.status_not_started')
            : `${relativeTime(s.updatedAt, Date.now())} · ${formatClock(s.updatedAt)}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .maxLines(1)
        }
        .width('100%')
        .padding({ left: Sp.L, right: Sp.M, top: Sp.S, bottom: Sp.S })
        .borderRadius(Radius.S)
        .backgroundColor(this.selectedSessionId === s.id
          ? $r('sys.color.background_secondary')
          : $r('sys.color.background_primary'))
        .onClick(() => {
          this.openSession(s.id);
        })
      }, (s: SessionListItem) => s.id)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  /**
   * 核心页内容（E110：原「核心」页签并入设置，作为设置页的第一个页签）。
   *
   * 【为什么合并】核心不是"另一个世界"，它就是这台设备上 DSH 的运行配置：版本、插件、运行时事实。
   * 与"设置"并列成两个一级页签，会让用户在两个地方找同一类东西（官方 web 也没有独立的"核心"页，
   * 它是设置里的一个分区）。内容原样搬过来，能力一个不少。
   */
  @Builder
  coreTabContent() {
    Column({ space: Sp.S }) {
      if (this.coreNotice.length > 0) {
        Text(this.coreNotice)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding(Sp.S)
          .borderRadius(Radius.S)
          .backgroundColor($r('sys.color.background_secondary'))
      }
      CorePane({
        view: this.coreView,
        onAction: (id: string) => {
          this.onCoreAction(id);
        },
        onSelectVersion: (version: string) => {
          this.onCoreSelectVersion(version);
        },
        onTogglePlugin: (id: string, disabled: boolean) => {
          this.onTogglePlugin(id, disabled);
        },
        onResetPluginRows: () => {
          this.onResetPluginRows();
        },
        pluginNotice: this.pluginNotice
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tabContent(compact: boolean) {
    /*
     * E108：工作区视图（合并了原来的「会话」与「待决」两个页签）。
     * 官方 web 的侧栏就是"工作区为组、会话挂在组下"；待决属于**当前这次对话**，显示在列表顶部。
     * 文件浏览仍是工作区里的下钻（`wsDrill > 0`，见下一个分支）。
     */
    if (this.tab === NavTab.WORKSPACES && this.wsDrill === 0) {
      this.workspaceHub(compact)
    } else if (this.tab === NavTab.WORKSPACES) {
      WorkspacePane({
        workspaces: this.workspaces,
        onPickFolder: () => {
          this.openFolderPicker();
        },
        tree: this.fileTree,
        selectedPath: this.preview === undefined ? '' : this.preview.path,
        preview: this.preview,
        compact: compact && this.mode === LayoutMode.SINGLE,
        drillLevel: this.wsDrill,
        treeEmptyTitle: this.treeEmptyTitle,
        treeEmptyHint: this.treeEmptyHint,
        onSelectWorkspace: (id: string) => {
          const scope: string = this.sessionForWorkspace(id);
          // 空态文案按「为什么空」分档（D3 §4：空态要说明可以做什么）
          this.pendingWorkspacePick = true;
          if (scope.length === 0) {
            this.treeEmptyTitle = '该工作区下还没有会话';
            this.treeEmptyHint = '文件浏览的作用域是会话级（workspaceFileScopeId = 会话 id），请先在这个目录里新建一个会话。';
          } else {
            this.treeEmptyTitle = '该目录暂无文件';
            this.treeEmptyHint = '目录确实为空，或 Host 拒绝列出它的内容（详见连接诊断）。';
            if (this.hubConnected) {
              SessionHub.shared().openWorkspace(scope);
            }
          }
          if (this.mode === LayoutMode.SINGLE) {
            this.wsDrill = 1;
          }
        },
        onToggleDirectory: (path: string) => {
          this.toggleDirectory(path);
        },
        onOpenFile: (node: FileNode) => {
          this.openFile(node);
        },
        onAttachFile: (node: FileNode) => {
          this.attachWorkspaceFileToComposer(node);
        },
        onBack: () => {
          this.wsDrill = this.wsDrill > 0 ? this.wsDrill - 1 : 0;
        }
      })
    } else {
      SettingsPane({
        // E118：核心分区的内容直接由属性传入（不再用 @BuilderParam 注入父 Builder——
        // 真机上点开该分区会 JS 崩溃）
        coreView: this.coreView,
        permissionCurrent: this.permissionCurrent,
        permissionOptions: this.permissionOptions,
        coreNotice: this.coreNotice,
        onCoreAction: (id: string) => {
          this.onCoreAction(id);
        },
        onCoreSelectVersion: (version: string) => {
          this.onCoreSelectVersion(version);
        },
        onTogglePluginRow: (id: string, disabled: boolean) => {
          this.onTogglePlugin(id, disabled);
        },
        onResetPluginRowsAction: () => {
          this.onResetPluginRows();
        },
        // E114：官方「通用」分区承载的是**用户面向的功能包设置**（外观/语言/会话…），
        // 引擎参数不在其中。这里做同样的策展：白名单命名空间整组显示，
        // 其余命名空间里**用户改过**的项收进「其他已修改项」，既不占版面又撤得回。
        groups: projectGeneralGroups(this.settings),
        // E128：模型页要能编辑提供方的设置分区（baseURL / 模型目录），所以另传全量
        allGroups: this.settings,
        // E135：技能清单（数据层已就绪；形状未识别时界面如实显示结论）
        skills: this.skills,
        skillNote: this.skillNote,
        // E161：预设名单（数据层已按真机实测契约接线）
        presets: this.presets,
        presetNote: this.presetNote,
        /*
         * E170：预设的**复制**（官方唯一创建入口）与**删除**（仅自定义项）。
         * 【为什么自动命名而不弹输入框】官方用复制对话框让我们填"标识 + 名称"；
         * 端侧先做**一步完成**的版本（`<id>-copy` / `<名称> 副本`）——它是一个完整可用的动作，
         * 而不是半成品表单；需要改名时再走查看/编辑那条线（`read` 已就绪）。
         */
        onPresetCopy: (from: string, name: string) => {
          const id: string = `${from}-copy`;
          SessionHub.shared().copyAgentPreset(from, id, `${name.length > 0 ? name : from} 副本`)
            .then((n: ActionNotice) => {
              this.settingWriteNote = this.noticeText(n);
            }).catch((e: Object) => {
              this.settingWriteNote = `复制预设失败：${(e as Error).message}`;
            });
        },
        onPresetDelete: (id: string) => {
          SessionHub.shared().deleteAgentPreset(id)
            .then((n: ActionNotice) => {
              this.settingWriteNote = this.noticeText(n);
            }).catch((e: Object) => {
              this.settingWriteNote = `删除预设失败：${(e as Error).message}`;
            });
        },
        credentials: this.credentials,
        plugins: this.plugins,
        hosts: this.hosts,
        models: this.models,
        selection: this.selection,
        about: aboutInfo(),
        writeNote: this.settingWriteNote,
        states: this.settingsStates,
        onToggleSetting: (key: string, value: boolean) => {
          if (this.settingItemOf(key) === undefined) {
            // 本地偏好：本客户端自己的开关，没有上游写路径。
            // 如实说明它只在本机生效，而不是假装写成功了。
            this.settingWriteNote = `「${key}」是本机偏好，只在本次运行内生效（尚未做持久化）。`;
            return;
          }
          this.writeSetting(key, value as Object, key);
        },
        onPickChoice: (key: string, current: string) => {
          const item: SettingItem | undefined = this.settingItemOf(key);
          if (item === undefined) {
            // 本机偏好：没有上游写路径，但**有端侧持久化路径**（`platform/LocalPrefs`）。
            // 仍然复用同一个选中浮层（选项来源换成端侧那一组），提交时由 `applyChoice` 分流。
            const local: SettingItem | undefined = this.localItemOf(key);
            if (local === undefined) {
              this.settingWriteNote = `「${key}」既不属于 Host 设置、也不在本机偏好表里。`;
              return;
            }
            this.choosingKey = key;
            this.choosingLabel = local.label;
            this.choosingCurrent = current;
            this.choosing = local.choices;
            return;
          }
          if (item.choices.length === 0) {
            // 防御分支：列表里的 TEXT 项已直接走 `onEditText`，不会走到这里。
            this.openTextSettingSheet(item);
            return;
          }
          this.choosingKey = key;
          this.choosingLabel = item.label;
          this.choosingCurrent = current;
          this.choosing = item.choices;
        },
        onEditText: (item: SettingItem) => {
          this.openTextSettingSheet(item);
        },
        onEditStruct: (item: SettingItem) => {
          this.openStructSettingSheet(item);
        },
        onResetSetting: (key: string) => {
          this.resetSetting(key);
        },
        onPickEffort: (effort: string) => {
          this.selection = {
            provider: this.selection.provider, modelId: this.selection.modelId, effort: effort
          };
        },
        onSelectModel: (provider: string, model: string, effort: string) => {
          this.applyDefaultModel(provider, model, effort);
        },
        onAuthorizeCredential: (ref: string) => {
          this.openCredentialSheet(ref);
        },
        onPairHost: () => {
          this.stackPage = StackPage.CONNECT;
        },
        onRevokeHost: (id: string) => {
          this.forgetHost();
        },
        onOpenDiagnostics: () => {
          this.openDiagnostics();
        }
      })
    }
  }

  @Builder
  badge(text: string) {
    Text(text)
      .fontSize(Fs.CAPTION_XS)
      .fontColor(Color.White)
      .backgroundColor($r('sys.color.alert'))
      .borderRadius(Radius.S)
      .padding({ left: 5, right: 5 })
      .margin({ top: -4, right: -10 })
  }
}

/** 用 display 推导初始窗口宽度（vp）；失败时给一个安全的手机宽度 */
function initialWidthVp(): number {
  try {
    const d: display.Display = display.getPrimaryDisplaySync();
    return px2vp(d.width);
  } catch (error) {
    return 400;
  }
}

/** 初始窗口高度（vp）。与 initialWidthVp 同款：读不到就给一个安全默认值 */
function initialHeightVp(): number {
  try {
    const d: display.Display = display.getPrimaryDisplaySync();
    return px2vp(d.height);
  } catch (error) {
    return 800;
  }
}

/**
 * 把「地址」与「令牌」两个输入合成一个启动链接。
 *
 * 为什么需要它：`ConnectPane` 给用户两个输入框（地址 / 令牌），而连接层的
 * `configure()` 只接受**一个**启动链接（token 由它从链接里解析）。
 * 在 UI 与连接层之间做这个合成，比让连接层同时容忍两种输入形态更简单：
 * 连接层的职责是解析一种确定的形态，而不是猜测用户的意图。
 *
 * 三种输入都被正确处理：
 *   1. 只有地址            → 补 `http://` 前缀
 *   2. 地址 + 令牌         → 合成 `http://地址/?token=令牌`
 *   3. 粘贴的完整启动链接   → 原样返回（已含 token，不重复拼接）
 */
/**
 * 从「启动 URL」里剥出可用于存储的 base URL（**去掉凭据部分**）。
 *
 * 【为什么必须剥掉 query / fragment】用户粘贴的是
 * `http://127.0.0.1:3111/?token=xxxx`，而 `token=` 是**凭据**（D2 §2.1：
 * 持有它就等于持有 Host 的完整会话权限）。把整串地址直接当 `baseUrl` 存进
 * 明文 `preferences`，等于把 token 落到明文——D1 §6.4 明确禁止。
 *
 * 实测踩到过：真机连上后 `preferences` 里存的就是带 token 的整串。
 * 这条路径上还有一个连环故障：token 别名是按 `baseUrl` 算的，存进去的
 * 却是带 query 的地址，于是「保存 token」与「读取 token」用了**两个不同的别名**，
 * 表现为下次启动读不到 token（状态 `absent`），自动重连永远不工作。
 *
 * 因此：**存储只保留 scheme://authority**，凭据一律不进这条路径
 * （token 单独走加密存储）。
 */
function storageBaseUrl(url: string): string {
  const cut: number = url.search(/[?#]/);
  return cut < 0 ? url : url.substring(0, cut);
}

function composeHostUrl(address: string, token: string): string {
  let url: string = address.trim();
  if (url.length === 0) {
    return '';
  }
  if (url.indexOf('://') < 0) {
    url = `http://${url}`;
  }
  const trimmedToken: string = token.trim();
  if (trimmedToken.length === 0 || url.indexOf('token=') >= 0) {
    return url;
  }
  return url.indexOf('?') >= 0 ? `${url}&token=${trimmedToken}` : `${url}/?token=${trimmedToken}`;
}
