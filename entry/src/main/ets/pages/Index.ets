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
 * 数据当前全部来自 appstate 的桩数据源（方案 2）。接入真实连接时，
 * 只需把这里的赋值换成连接层的结果，所有视图组件无需改动。
 */

import { display, router, window } from '@kit.ArkUI';
import { demoTraceLines } from 'dshcompat';
import {
  APPROVAL_CHOICE_ALLOW_ALWAYS,
  APPROVAL_CHOICE_DENY,
  CommandCandidate,
  CredentialItem,
  detailPanelAvailable,
  DetailSection,
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
  PluginItem,
  Radius,
  ReferenceCandidate,
  SessionListItem,
  SettingGroup,
  SettingsWriteOutcome,
  Sp,
  aboutInfo,
  mergeSettingsGroups,
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
  stubTrajectory,
  stubWorkspaces,
  stubSessions,
  stubPending,
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
  HubSnapshot,
  HubSubscriber,
  SettingChoice,
  SettingItem,
  SettingsNamespaceState,
  SettingsWriteResult
} from 'appstate';
import { ConnectPane } from '../view/ConnectPane';
import { ConversationPane } from '../view/ConversationPane';
import { DetailPane } from '../view/DetailPane';
import { DiagnosticsPane } from '../view/DiagnosticsPane';
import { PendingPane } from '../view/PendingPane';
import { SessionListPane } from '../view/SessionListPane';
import { SettingsPane } from '../view/SettingsPane';
import { WorkspacePane } from '../view/WorkspacePane';

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
  @State credentials: CredentialItem[] = [];
  @State plugins: PluginItem[] = [];
  @State hosts: HostRecord[] = [];
  @State models: ModelOption[] = [];
  @State selection: ModelSelection = { provider: '', modelId: '', effort: '' };
  @State diag: DiagReport = {
    entries: [], healthy: false, generatedAt: 0, versionVerdict: '',
    versionMessage: '', versionAdvice: '', tableStats: '', surface: ''
  };
  @State references: ReferenceCandidate[] = [];
  @State commands: CommandCandidate[] = [];

  // ── 交互状态 ──
  @State draft: string = '';
  @State attachments: string[] = [];
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
   * 设计取舍：**只在「已连上」时覆盖桩数据**（判据是 `s.connected`，不是 `s.phase`）。
   * 未连接时保留桩数据，是为了让「没有 Host」的新用户也能看到完整的界面结构
   * （D3 §4 要求空态有说明）；一旦连上，列表与待决就以 Host 为准——
   * 此时若 Host 上确实没有会话，界面就应当显示空列表，而不是继续显示桩数据
   * （否则用户会以为连上了却看到不存在的会话，是更糟的误导）。
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
    if (!s.connected) {
      this.offline = s.phase === HubPhase.DEGRADED;
      return;
    }
    // 已连上但事件流断了：数据是真的，只是实时性降级，如实标注为离线提示
    this.offline = s.phase === HubPhase.DEGRADED;
    this.sessions = s.sessions;
    this.pending = s.pending;
    // 模型目录与插件清单是「静态事实」：连上后由中枢拉一次。
    // 只在非空时覆盖桩数据——能力缺失（老 Host 没有这些端点）时保留桩数据会让用户
    // 以为 Host 真有这些模型，所以这里反过来：**已连上就以真实结果为准，哪怕为空**。
    this.models = s.models;
    this.plugins = s.plugins;
    this.credentials = s.credentials;
    // Host 设置在前、本地偏好在后。**已连上就以真实结果为准**（哪怕为空），
    // 不再保留桩数据里的「Host 设置」——那会让用户改到并不存在的项。
    this.settings = mergeSettingsGroups(s.settings, this.localSettings);
    this.settingsStates = s.settingsStates;
    if (s.defaultSelection !== undefined) {
      this.selection = s.defaultSelection;
    }
    this.selectedSessionTitle = s.selectedTitle;
    if (s.selectedSessionId === this.selectedSessionId) {
      this.trajectoryItems = s.trajectory;
      this.running = s.running;
    }
    this.recomputeDerived();
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
    this.sessions = stubSessions();
    this.pending = stubPending();
    this.detailSections = stubDetailSections();
    this.workspaces = stubWorkspaces();
    this.fileTree = stubFileTree();
    this.localSettings = stubSettings();
    this.settings = this.localSettings;
    this.credentials = stubCredentials();
    this.plugins = stubPlugins();
    this.hosts = stubHosts();
    this.models = stubModels();
    this.selection = stubModelSelection();
    this.diag = stubDiagnostics();
    this.references = stubReferences();
    this.commands = stubCommands();
    this.recomputeDerived();
    this.applyWidth(initialWidthVp());
    this.watchWindowSize();
    // 订阅中枢：多窗口下每个窗口各自订阅，但共用同一个连接与会话状态
    const listener: HubSubscriber = (s: HubSnapshot) => {
      this.applyHubSnapshot(s);
    };
    this.hubListener = listener;
    SessionHub.shared().subscribe(listener);
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
    const live: boolean = this.hubConnected;
    // 未连接时用桩轨迹让界面可读；连上后清空并由中枢的 session/follow 推真实轨迹
    // （若不清空，真实轨迹会追加在桩数据后面，看起来像「会话里混进了别人的内容」）
    this.trajectoryItems = live ? [] : stubTrajectory();
    this.running = live ? false : true;
    if (live) {
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

  private toggleDirectory(path: string): void {
    const next: FileNode[] = [];
    for (let i = 0; i < this.fileTree.length; i++) {
      const node: FileNode = this.fileTree[i];
      next.push(node.path === path
        ? {
          name: node.name, path: node.path, kind: node.kind, size: node.size,
          modifiedAt: node.modifiedAt, loaded: !node.loaded, children: node.children,
          deliverable: node.deliverable
        }
        : node);
    }
    this.fileTree = next;
  }

  private openFile(node: FileNode): void {
    this.preview = stubPreview(node.path, node.name);
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
        this.stackPage = StackPage.DIAGNOSTICS;
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
        running: false,
        traceEnabled: this.traceEnabled,
        traceLines: this.traceLines,
        onRerun: () => {
          this.diag = stubDiagnostics();
        },
        onToggleTrace: (on: boolean) => {
          this.traceEnabled = on;
          // 演示行来自兼容面（UI 不得自行拼写上游端点名，D5 §1）
          this.traceLines = on ? demoTraceLines() : [];
        },
        onExportLog: () => {
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
          });
        },
        onSelectHost: (id: string) => {
        },
        onRemoveHost: (id: string) => {
        },
        onStartDiscovery: () => {
        },
        onOpenDiagnostics: () => {
          this.stackPage = StackPage.DIAGNOSTICS;
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
          this.attachments = this.attachments.concat(['screenshot.png']);
        },
        onRemoveAttachment: (name: string) => {
          const next: string[] = [];
          for (let i = 0; i < this.attachments.length; i++) {
            if (this.attachments[i] !== name) {
              next.push(this.attachments[i]);
            }
          }
          this.attachments = next;
        },
        onPickModel: () => {
          this.selectTab(NavTab.SETTINGS);
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
    this.attachments = [];
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
        Text('诊断')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.stackPage = StackPage.DIAGNOSTICS;
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
        onSelectWorkspace: (id: string) => {
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
          this.attachments = this.attachments.concat([node.name]);
          this.selectTab(NavTab.SESSIONS);
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
            // 没有枚举分支的字段（如自由文本 / 数字）：不猜一个编辑器，
            // 而是说明当前能力边界，避免用户以为点了没反应
            this.settingWriteNote = `「${item.label}」需要输入值，本客户端暂未提供该编辑器；`
              + `可在 Host 的设置文档里直接修改 ${key}。`;
            return;
          }
          this.choosingKey = key;
          this.choosingLabel = item.label;
          this.choosingCurrent = current;
          this.choosing = item.choices;
        },
        onPickModel: () => {
        },
        onPickEffort: (effort: string) => {
          this.selection = {
            provider: this.selection.provider, modelId: this.selection.modelId, effort: effort
          };
        },
        onAuthorizeCredential: (ref: string) => {
        },
        onPairHost: () => {
          this.stackPage = StackPage.CONNECT;
        },
        onRevokeHost: (id: string) => {
        },
        onOpenDiagnostics: () => {
          this.stackPage = StackPage.DIAGNOSTICS;
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
