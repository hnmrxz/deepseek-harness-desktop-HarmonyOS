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
import {
  checkVersion,
  emptyProbeTable,
  SURFACE,
  tableStats
} from 'dshcompat';
import type { VersionCheck } from 'dshcompat';
import type { DiagnosticItem, DiagnosticReport } from 'connection';
import { copyText, PickOutcome, pickDocument } from 'platform';
import type { PickedFile } from 'platform';
import { common } from '@kit.AbilityKit';
import {
  APPROVAL_CHOICE_ALLOW_ALWAYS,
  APPROVAL_CHOICE_DENY,
  CommandCandidate,
  CredentialItem,
  detailPanelAvailable,
  DetailSection,
  DiagEntry,
  DiagReport,
  FileNode,
  FilePreview,
  Fs,
  HostRecord,
  HubPhase,
  LayoutMode,
  layoutModeOf,
  ModelOption,
  ModelSelection,
  NavTab,
  navTabLabel,
  navTabSymbol,
  PendingItem,
  PendingAttachment,
  PluginItem,
  Radius,
  ReferenceCandidate,
  SessionListItem,
  SettingGroup,
  SettingValueType,
  SettingsWriteOutcome,
  parseSettingInput,
  parseStructInput,
  Sp,
  aboutInfo,
  emptyDiagReport,
  mergeSettingsGroups,
  normalizePathKey,
  projectDetailSections,
  projectHosts,
  projectWorkspaces,
  SessionHub,
  Sz,
  TrajectoryItem,
  WorkspaceItem
} from 'appstate';
/**
 * 类型单独用 `import type` 引入。
 *
 * 原因：`HubSnapshot` / `HubSubscriber` 在 appstate 里是 `export type` 导出的类型，
 * 与值导入分开写更贴近 ArkTS 的类型/值导入区分。
 */
import type {
  AttachOutcome,
  CredentialWriteResult,
  HubSnapshot,
  HubSubscriber,
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
import { DetailPane } from '../view/DetailPane';
import { DiagnosticsPane } from '../view/DiagnosticsPane';
import { PendingPane } from '../view/PendingPane';
import { SessionListPane } from '../view/SessionListPane';
import { SettingsPane } from '../view/SettingsPane';
import { WorkspacePane } from '../view/WorkspacePane';

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

/** 单栏下的页面栈 */
enum StackPage {
  MAIN = 'main',
  CONVERSATION = 'conversation',
  DETAIL = 'detail',
  DIAGNOSTICS = 'diagnostics',
  CONNECT = 'connect'
}

/** 一级导航顺序 */
const TABS: NavTab[] = [NavTab.PENDING, NavTab.SESSIONS, NavTab.WORKSPACES, NavTab.SETTINGS];

@Entry
@Component
struct Index {
  // ── 形态 ──
  @State mode: LayoutMode = LayoutMode.SINGLE;
  @State tab: NavTab = NavTab.SESSIONS;
  @State stackPage: StackPage = StackPage.MAIN;
  @State detailOpen: boolean = false;

  // ── 数据（当前来自桩数据源） ──
  @State sessions: SessionListItem[] = [];
  @State pending: PendingItem[] = [];
  @State selectedSessionId: string = '';
  @State selectedSessionTitle: string = '';
  @State trajectoryItems: TrajectoryItem[] = [];
  @State detailSections: DetailSection[] = [];
  @State workspaces: WorkspaceItem[] = [];
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
  /** 自动重连只跑一次（StorageProp 变化会触发，重复跑会反复认证） */
  private autoConnectAttempted: boolean = false;
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
    this.queuedCount = s.outbox;
    // 附件列表由中枢拥有（回执是会话作用域的），这里只跟随
    this.attachments = s.attachments;
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
      this.settings = this.localSettings;
      this.settingsStates = [];
      this.hosts = [];
      this.commands = [];
      this.references = [];
      this.preview = undefined;
      this.attachments = [];
      this.updateHosts();
      this.recomputeDerived();
      return;
    }
    this.sessions = s.sessions;
    this.pending = s.pending;
    this.models = s.models;
    this.plugins = s.plugins;
    this.credentials = s.credentials;
    this.settings = mergeSettingsGroups(s.settings, this.localSettings);
    this.settingsStates = s.settingsStates;
    this.commands = s.commands;
    this.references = s.references;
    // 文件树与预览由中枢持有（它们与会话绑定），这里只跟随：
    // 中枢换了会话就会清空并重列，视图不做任何缓存，避免两边各存一份而后不一致。
    this.fileTree = s.fileNodes;
    this.preview = s.filePreview;
    if (s.defaultSelection !== undefined) {
      this.selection = s.defaultSelection;
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
    this.updateHosts();
    this.recomputeDerived();
    this.applyWidth(initialWidthVp());
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
      return;
    }
    this.autoConnectAttempted = true;
    let waited: number = 0;
    const step: number = 250;
    const limit: number = 4000;
    const timer: number = setInterval(() => {
      waited += step;
      const state: string = this.rememberedTokenState;
      if (state === 'pending' && waited < limit) {
        return;
      }
      clearInterval(timer);
      this.applyRememberedHostOutcome(state);
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
      return;
    }
    if (state === 'found' && this.rememberedToken.length > 0) {
      const hub: SessionHub = SessionHub.shared();
      // 【token 必须拼回 URL】`SessionHub.configure(address, name)` 的第二个参数是
      // **显示名**，不是 token——token 是从地址串里解析出来的（`parseTarget`）。
      // 只传裸 baseUrl 会让认证拿着空 token 去请求，Host 回
      // 「未提供 token」而界面显示「连接失败（HTTP 0）」，看起来像网络问题。
      // 实测踩到过。拼接后走同一条解析路径，与手动粘贴 URL 完全等价。
      const connectUrl: string = composeHostUrl(this.rememberedUrl, this.rememberedToken);
      if (!hub.configure(connectUrl, undefined)) {
        return;
      }
      this.connectBusy = true;
      this.connectResult = `正在自动重连 ${this.rememberedUrl}…`;
      hub.connect().then((ok: boolean) => {
        this.connectBusy = false;
        const snap: HubSnapshot = hub.snapshot();
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
    lines.push(`# DSH 鸿蒙端诊断报告（${new Date().toISOString()}）`);
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
        this.applyWidth(px2vp(win.getWindowProperties().windowRect.width));
        const listener = (size: window.Size) => {
          this.applyWidth(px2vp(size.width));
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
  private applyWidth(widthVp: number): void {
    const next: LayoutMode = layoutModeOf(widthVp);
    if (next === this.mode) {
      return;
    }
    this.mode = next;
    if (next !== LayoutMode.SINGLE
      && (this.stackPage === StackPage.CONVERSATION || this.stackPage === StackPage.DETAIL)) {
      this.stackPage = StackPage.MAIN;
    }
    if (!detailPanelAvailable(next)) {
      this.detailOpen = false;
    } else if (this.selectedSessionId.length > 0) {
      this.detailOpen = true;
    }
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

  private selectTab(tab: NavTab): void {
    this.tab = tab;
    this.stackPage = StackPage.MAIN;
    this.wsDrill = 0;
    if (tab !== NavTab.SESSIONS) {
      this.selectedSessionId = '';
      this.selectedSessionTitle = '';
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

  private showsConversation(): boolean {
    return this.selectedSessionId.length > 0 && this.tab === NavTab.SESSIONS;
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
      if (this.choosing !== undefined) {
        this.choiceSheet()
      }
      if (this.credentialRef.length > 0) {
        this.credentialSheet()
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
    this.writeSetting(key, value as Object, this.choosingLabel);
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
          if (this.stackPage === StackPage.DETAIL) {
            this.stackPage = StackPage.CONVERSATION;
          } else {
            this.stackPage = StackPage.MAIN;
          }
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
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.stackPage = StackPage.DETAIL;
          })
      }
      Button('POC')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontSize(Fs.CAPTION)
        .onClick(() => {
          this.openPoc();
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: Sp.M, right: Sp.S })
  }

  private headerTitle(): string {
    if (this.stackPage === StackPage.CONVERSATION) {
      return this.selectedSessionTitle.length > 0 ? this.selectedSessionTitle : '会话';
    }
    if (this.stackPage === StackPage.DETAIL) {
      return '详情';
    }
    if (this.stackPage === StackPage.DIAGNOSTICS) {
      return '连接诊断';
    }
    if (this.stackPage === StackPage.CONNECT) {
      return '添加 Host';
    }
    return navTabLabel(this.tab);
  }

  @Builder
  bottomTabs() {
    Row() {
      ForEach(TABS, (tab: NavTab) => {
        Column({ space: 2 }) {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(navTabSymbol(tab))
              .fontSize(22)
              .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (tab === NavTab.PENDING && this.pendingBadge.length > 0) {
              this.badge(this.pendingBadge)
            }
          }
          Text(navTabLabel(tab))
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
      ForEach(TABS, (tab: NavTab) => {
        Column() {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(navTabSymbol(tab))
              .fontSize(22)
              .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (tab === NavTab.PENDING && this.pendingBadge.length > 0) {
              this.badge(this.pendingBadge)
            }
          }
        }
        .width(Sz.NAV_RAIL)
        .height(Sz.TOUCH_MIN)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Radius.S)
        .accessibilityText(`${navTabLabel(tab)}标签`)
        .onClick(() => {
          this.selectTab(tab);
        })
      }, (tab: NavTab) => tab)
    }
    .width(Sz.NAV_RAIL)
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
      Text('DSH 鸿蒙端')
        .fontSize(Fs.TITLE_S)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: Sp.M, top: Sp.M, bottom: Sp.S })

      ForEach(TABS, (tab: NavTab) => {
        Row({ space: Sp.M }) {
          SymbolGlyph(navTabSymbol(tab))
            .fontSize(20)
            .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
          Text(navTabLabel(tab))
            .fontSize(Fs.SECONDARY)
            .fontColor(this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_primary'))
            .layoutWeight(1)
          if (tab === NavTab.PENDING && this.pendingBadge.length > 0) {
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

      // 二级入口：诊断 / 添加 Host / POC
      this.navPanelAction('连接诊断', () => {
        this.openDiagnostics();
      })
      this.navPanelAction('添加 Host', () => {
        this.stackPage = StackPage.CONNECT;
      })
      this.navPanelAction('POC 协议验证', () => {
        this.openPoc();
      })
    }
    .width(Sz.NAV_PANEL)
    .height('100%')
    .padding({ left: Sp.S, right: Sp.S, bottom: Sp.S })
    .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  navPanelAction(label: string, action: () => void) {
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
        onLineTap: (section: string, index: number) => {
        }
      })
    }
    .width(Sz.DETAIL_PANEL)
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }

  // ───────────────────── 主内容路由 ─────────────────────

  @Builder
  mainContent(compact: boolean) {
    if (this.stackPage === StackPage.DIAGNOSTICS) {
      DiagnosticsPane({
        report: this.diag,
        running: this.diagRunning,
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
        onSelectHost: (id: string) => {
        },
        onRemoveHost: (id: string) => {
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
    } else if (this.stackPage === StackPage.DETAIL) {
      DetailPane({
        sections: this.detailSections,
        onLineTap: (section: string, index: number) => {
        }
      })
    } else if (this.showsConversation() && this.stackPage === StackPage.CONVERSATION) {
      ConversationPane({
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
        onReferenceQuery: (query: string) => {
          if (this.hubConnected) {
            SessionHub.shared().refreshReferences(query);
          }
        },
        onOpenDetail: () => {
          this.stackPage = StackPage.DETAIL;
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
          .fontSize(10)
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

  @Builder
  tabContent(compact: boolean) {
    if (this.tab === NavTab.PENDING) {
      PendingPane({
        items: this.pending,
        onDecide: (item: PendingItem, choiceId: string, reason: string) => {
          this.decidePending(item, choiceId, reason);
        },
        onAnswer: (item: PendingItem, selected: string[], custom: string) => {
          this.answerPending(item, selected, custom);
        }
      })
    } else if (this.tab === NavTab.SESSIONS) {
      Column() {
        // 连接状态条：**失败必须可见**（D3 §4）。
        // 曾经只把错误存进状态而不渲染，结果是「连上了但列表为空」这种
        // 最容易被误读成「Host 上没有会话」的失败——错误信息被完全吞掉。
        if (this.hubError.length > 0) {
          this.hubBanner()
        }
        SessionListPane({
          sessions: this.sessions,
          pending: this.pending,
          selectedId: this.selectedSessionId,
          onSelect: (id: string) => {
            this.openSession(id);
          },
          onCreate: () => {
            // 不在这里判连接状态：中枢会给出「尚未连接 Host，无法新建会话」
            // 并广播到状态条——单一判定点比在两处各写一遍更不容易走偏
            SessionHub.shared().createSession();
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.tab === NavTab.WORKSPACES) {
      WorkspacePane({
        workspaces: this.workspaces,
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
        groups: this.settings,
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
            this.settingWriteNote = `「${key}」是本机偏好，只在本次运行内生效（尚未做持久化）。`;
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
        onPickModel: () => {
        },
        onPickEffort: (effort: string) => {
          this.selection = {
            provider: this.selection.provider, modelId: this.selection.modelId, effort: effort
          };
        },
        onAuthorizeCredential: (ref: string) => {
          this.openCredentialSheet(ref);
        },
        onPairHost: () => {
          this.stackPage = StackPage.CONNECT;
        },
        onRevokeHost: (id: string) => {
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
      .fontSize(10)
      .fontColor(Color.White)
      .backgroundColor($r('sys.color.alert'))
      .borderRadius(8)
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
