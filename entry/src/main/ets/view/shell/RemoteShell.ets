/**
 * 手机形态外壳（T018：对照 `dshmobile/ui/screens/main/MainScreen.kt` 的 Discord 式抽屉范式；
 * T020：右侧抽屉内容对照 `DetailsPanel.kt`）。
 *
 * ## 与 AppShell / Index 路由的关系
 *
 * AppShell 是 PC/平板的三栏 Row 布局；本壳是手机的 Stack + 抽屉布局，
 * **LOCAL 与 REMOTE 都渲染**（Index 的形态路由按窗口尺寸选壳，不再按运行模式）：
 *   - 主区域 = 断连横幅（HubBanner）+ 当前对话（MainShell compact）+ 底部目标 Dock
 *   - 左侧抽屉 = 会话列表（DrawerNav，从左缘右滑打开；T019 复刻 ChatListDrawer.kt）
 *   - 右侧抽屉 = 会话详情（detailsPanelBody，从右缘左滑打开；T020 复刻 DetailsPanel.kt）
 * 抽屉开合映射 `DrawerTracksState`（唯一真值在宿主 Index；本壳只读状态 + 报回调）。
 *
 * ## 对照 MainScreen.kt 的手势语义（T018，本版不动）
 *
 *  · 左缘 28dp 透明带右滑 → 打开会话抽屉（对照源码 ModalNavigationDrawer 的内建
 *    手势；源码"内容区任意位置右滑打开"在 ArkUI 侧会饿死内层横向滚动，收敛为
 *    边带——忠实度偏离，记录于此）。
 *  · 右缘左滑 → 打开详情抽屉（对照源码 awaitEachGesture 只认右缘带内的左拖）；
 *    抽屉面板上反向滑 → 关闭。
 *  · 开/关判定阈值 = 屏宽 × 0.12（源码 `width * 0.12f` 同款；拖拽不做实时跟手——
 *    facade 没有 dragOffset 的写通道，阈值触发即切换）。
 *  · scrim 点按 → 全关；遮罩色用 `overlayMask`（源码 scrim 同语义 token）。
 *  · 抽屉滑入 220ms（`DsAnimation.PANEL_SLIDE`；源码注释：平台默认 300ms
 *    跟不上拖拽，故显式提速）。
 *
 * ## T020：右侧抽屉 = 会话详情面板（对照 `DetailsPanel.kt`）
 *
 * 源码把详情面板组织成**可折叠的卡**（而不是一堵平铺的标题墙——手机宽的面板上，
 * 平铺意味着你要的那一节永远在第三屏之后；源码头注释原话）。本壳的
 * `detailsPanelBody` 逐卡对照：
 *   · `HeaderRow`（返回钮 + 「会话详情」）
 *   · 会话卡（SessionCard：标题 = 会话名，摘要 = cwd 末段；模型 pill（点开模型选择）；
 *     运行状态点；归档动作）
 *   · 统计卡（ContextCard 的对应物：中枢的 `statsLine` + `statsLinesOf` 的时间四项）
 *   · 计划卡（PlanCard：**一个开关说一件事**——源码把"标题写当前态、pill 写反态"
 *     的自相矛盾版改成了 ToggleRow）
 *   · 后台任务卡（JobsCard：状态点 + label/kind + 走字耗时——live 任务的耗时由
 *     本壳的秒级刻度驱动，源码 LaunchedEffect ticker 同理）
 *   · 队列卡（QueueCard：逐行 = 预览文本 + placement + 「移除」；T-D 接上 `queuedItems` 后
 *     与源码 `DetailsPanel.kt` 的 `QueueCard` 同构，此前只给计数）
 *   · 过程台账卡 × 5（`detailSections`：工具调用 / 子代理 / 交付物 / 目标 / 任务；
 *     行点按 = 行内复制，通道是 `rightbar.onLineTap`）
 *   · 主机卡（HostCard：连接地址 + 运行模式）
 *
 * 与源码的刻意偏离（缺通道，不放假入口）：
 *   · 导出 / 复制会话链接按钮（无导出通道）；重命名 / fork（无写通道）；
 *   · ContextMeter 与 token/cache 的分项（`SessionStatsInput` 没建模 pressure/
 *     breakdown，已有的数字走统计卡）；GoalCard 的阶段 pill（目标文本只有 Dock
 *     那一份字符串，阶段无通道；台账的「目标」卡覆盖同域事实）；
 *   · `BackHandler`（系统返回键的最终裁决在宿主 Index 的 consumeBack，本壳不抢）。
 *
 * ## 抽屉触发钮的宿主信道（ChatTopBar 行首 Menu 钮的接线）
 *
 * `ConversationHeader`（会话头 Row 1）在源码里有一颗抽屉触发钮，但 props 链
 * （ConversationPane → MainShell → 本壳）中间隔着 **MainShell 的门面**，而那份门面
 * 由宿主 Index 构建——本壳改不动它 ⇒ 走 **AppStorage 事件信道**（全部落在本壳与
 * ConversationHeader 两个文件内）：
 *   · 本壳挂载时置 `dsDrawerHostActive=true`（卸载置 false）——头部的钮只在手机壳
 *     在场时渲染，桌面路由不会出现一颗点了没人应的假钮；
 *   · 头部的钮点按 → `dsOpenLeftDrawerSignal` 写入新值（Date.now()）；
 *   · 本壳 `@StorageProp + @Watch` 收到信号 → `f.onOpenLeftDrawer()`。
 *
 * ## 门面模式
 *
 * 与 AppShell 同口径：值型快照 + 写型 setter + 方法型闭包；门面由宿主每次渲染重建。
 */

import {
  DrawerTracksState,
  DetailSection,
  DsAnimation,
  DsPalette,
  DsSpacing,
  DsThemePreference,
  DsType,
  HubPhase,
  JobDot,
  RunMode,
  SessionListItem,
  StatsLine,
  StatsUnit,
  baseNameOf,
  dsPaletteOf,
  formatDuration,
  jobDotState,
  jobDurationText,
  jobElapsedMs,
  liveJobCount,
  modelSelectionLabel,
  orderedJobs,
  sessionDisplayTitle,
  statsLinesOf,
} from 'appstate';
import type { QueuedItem, SessionJob } from 'appstate';
import type { MainShellFacade } from './MainShell';
import type { RightbarFacade } from './RightbarShell';
import type { WorkspaceBrowserFacade } from '../WorkspaceBrowser';
import { HubBanner } from '../HubBanner';
import { MainShell } from './MainShell';
import { DrawerNav } from '../DrawerNav';
import { LatticeDock } from '../LatticeDock';
import {
  DsButton,
  DsButtonSize,
  DsButtonVariant,
  DsDisclosureRow,
  DsIconButton,
  DsPill,
  DsStateDot,
  DsStateDotState,
  DsToggleRow,
  dsTweenCurve,
  installDsSystemDarkWatch,
} from '../NativePrimitives';

/* ───────── 组件级度量（源码 dp 字面量，逐条标注出处） ───────── */

/** MainScreen.kt `edgeBandPx = 28.dp.toPx()`：缘带宽度 */
const REMOTE_EDGE_BAND_WIDTH: number = 28;
/** MainScreen.kt `width * 0.12f`：抽屉开/关的横向拖拽阈值比例 */
const REMOTE_SWIPE_THRESHOLD_RATIO: number = 0.12;
/** DetailsPanel.kt `Card`：卡内容的缩进与行距（`padding(start=24.dp, top=4, bottom=4)` + `spacedBy(4.dp)`） */
const CARD_CONTENT_INSET: number = 24;
const CARD_CONTENT_SPACE: number = 4;

/** 卡片的展开键（三态表用；三态=显式展开/显式收起/跟默认） */
const CARD_SESSION: string = 'session';
const CARD_STATS: string = 'stats';
const CARD_PLAN: string = 'plan';
const CARD_JOBS: string = 'jobs';
const CARD_QUEUE: string = 'queue';
const CARD_HOST: string = 'host';

export interface RemoteShellFacade {
  /** 主区的门面 */
  mainShell: MainShellFacade;
  /** 右栏门面 */
  rightbar: RightbarFacade;
  /** 会话浏览器门面 */
  browser: WorkspaceBrowserFacade;
  /** 抽屉状态 */
  drawerState: DrawerTracksState;
  /** 打开左侧抽屉 */
  onOpenLeftDrawer: () => void;
  /** 打开右侧抽屉 */
  onOpenRightDrawer: () => void;
  /** 关闭所有抽屉 */
  onCloseDrawers: () => void;
  /** 详情面板内容 */
  detailSections: DetailSection[];
  /**
   * 会话的待发队列（T-D：宿主 `Index.queued`，中枢按 `session/control` 投影）。
   *
   * 【为什么是 `QueuedItem[]` 而不是 `Object[]`】详情面板的队列卡要逐行画
   * "预览文本 + placement + 移除"（对照 `DetailsPanel.kt` 的 `QueueCard`）；
   * `Object[]` 让视图只能转而自己从原始消息里抠文本，而那正是 `QueuedItem`
   * 这个投影类型存在的理由（见 `appstate/model/Wire.ets` 的说明）。
   */
  queuedItems: QueuedItem[];
  /** 移除一条待发队列项（走中枢 `SessionHub.removeQueuedItem`，与主区队列条同一动作） */
  onRemoveQueued: (itemId: string) => void;
  /** 目标文本 */
  goalText: string;
}

@Component
export struct RemoteShell {
  @Prop f: RemoteShellFacade;

  /** 壳层宽度（onAreaChange 实测；手势阈值的分母） */
  @State stackWidth: number = 0;
  @StorageProp('dsSystemDark') systemDark: boolean = false;
  /**
   * 抽屉触发信号（ConversationHeader 的 Menu 钮 → AppStorage → 这里）。
   * 值本身无意义，变一次就是"开一次抽屉"——Date.now() 保证每次都不同。
   */
  @StorageProp('dsOpenLeftDrawerSignal') @Watch('onOpenLeftDrawerSignal') openLeftDrawerSignal: number = 0;
  /** 详情面板卡片折叠的显式选择（true=显式收起；默认跟随卡的 initiallyExpanded） */
  @State cardForceCollapsed: string[] = [];
  /** 详情面板卡片展开的显式选择（源码 Card 的 `expanded` 是 remember 三态，这里拆两张表） */
  @State cardForceExpanded: string[] = [];
  /**
   * 后台任务卡的秒级刻度：live 任务的耗时必须走字——在不会重组的组件里读钟，
   * 计时器会冻在第一个读数上（源码 JobsCard 的 LaunchedEffect ticker 同理）。
   */
  @State jobsTick: number = 0;
  private jobsTimer: number = -1;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
    // 抽屉宿主标记：会话头的 Menu 钮只在手机壳在场时渲染（见文件头「宿主信道」）
    AppStorage.setOrCreate('dsDrawerHostActive', true);
    this.jobsTimer = setInterval(() => {
      if (liveJobCount(this.f.mainShell.jobs) > 0) {
        this.jobsTick++;
      }
    }, 1000);
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate('dsDrawerHostActive', false);
    if (this.jobsTimer >= 0) {
      clearInterval(this.jobsTimer);
      this.jobsTimer = -1;
    }
  }

  /** 会话头 Menu 钮的信号落点 */
  onOpenLeftDrawerSignal(): void {
    this.f.onOpenLeftDrawer();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  /** 横向拖拽阈值（屏宽 × 0.12；MainScreen.kt 同款） */
  private swipeThreshold(): number {
    return this.stackWidth * REMOTE_SWIPE_THRESHOLD_RATIO;
  }

  /* ═══════════════ 详情面板的派生数据 ═══════════════ */

  /** 是否有打开的会话（源码 DetailsPanel 的 `conversation == null` 判据的对应物） */
  private hasSession(): boolean {
    return this.f.mainShell.selectedSessionId.length > 0;
  }

  /** 在浏览器门面里找当前会话（工作区树 + 归档集；找不到返回 undefined） */
  private findSelectedSession(): SessionListItem | undefined {
    const id: string = this.f.mainShell.selectedSessionId;
    if (id.length === 0) {
      return undefined;
    }
    const workspaces = this.f.browser.workspaces;
    for (let i = 0; i < workspaces.length; i++) {
      const list: SessionListItem[] = this.f.browser.sessionsOf(workspaces[i]);
      for (let j = 0; j < list.length; j++) {
        if (list[j].id === id) {
          return list[j];
        }
      }
    }
    const archived: SessionListItem[] = this.f.browser.archivedSessions();
    for (let i = 0; i < archived.length; i++) {
      if (archived[i].id === id) {
        return archived[i];
      }
    }
    return undefined;
  }

  /** 当前会话的显示标题（会话名 → cwd 末段 → id；源码 SessionCard 同兜底链） */
  private sessionTitleText(): string {
    const found: SessionListItem | undefined = this.findSelectedSession();
    if (found !== undefined) {
      const title: string = sessionDisplayTitle(found);
      if (title.length > 0) {
        return title;
      }
      const folder: string = found.cwd.length > 0 ? baseNameOf(found.cwd) : '';
      if (folder.length > 0) {
        return folder;
      }
      return found.id;
    }
    // 找不到列表项（尚未同步）时退到门面给的工作区名，不编标题
    return this.f.mainShell.sessionWorkspaceName;
  }

  /** 卡片是否展开（显式选择优先；默认=源码 Card 的 initiallyExpanded） */
  private isCardExpanded(key: string, initiallyExpanded: boolean): boolean {
    if (this.cardForceCollapsed.indexOf(key) >= 0) {
      return false;
    }
    if (this.cardForceExpanded.indexOf(key) >= 0) {
      return true;
    }
    return initiallyExpanded;
  }

  private toggleCard(key: string, initiallyExpanded: boolean): void {
    const next: boolean = !this.isCardExpanded(key, initiallyExpanded);
    if (next) {
      this.cardForceCollapsed = removeFrom(this.cardForceCollapsed, key);
      this.cardForceExpanded = addTo(this.cardForceExpanded, key);
    } else {
      this.cardForceExpanded = removeFrom(this.cardForceExpanded, key);
      this.cardForceCollapsed = addTo(this.cardForceCollapsed, key);
    }
  }

  /** 统计行文案（与 `TimelineOverview.statsLineText` 同一口径：MS→时长，TPS→一位小数） */
  private statsLineText(line: StatsLine): string {
    if (line.unit === StatsUnit.MS) {
      return `${line.label} ${formatDuration(Math.round(line.value))}`;
    }
    if (line.unit === StatsUnit.TPS) {
      return `${line.label} ${line.value.toFixed(1)}`;
    }
    return `${line.label} ${line.value}`;
  }

  /** 任务状态 → 状态点（语义在 `Jobs` 模型的 `jobDotState`，颜色是 DsStateDot 的事） */
  private jobDotToState(status: string): DsStateDotState {
    const dot: JobDot = jobDotState(status);
    if (dot === JobDot.ONGOING) {
      return DsStateDotState.RUNNING;
    }
    if (dot === JobDot.WARNING) {
      return DsStateDotState.WARNING;
    }
    if (dot === JobDot.DONE) {
      return DsStateDotState.DONE;
    }
    return DsStateDotState.ERROR;
  }

  /** 统计卡是否有东西可说（源码 ContextCard 的四判据全空的对应物） */
  private statsVisible(): boolean {
    return this.f.mainShell.statsLine.length > 0 || statsLinesOf(this.f.mainShell.sessionStats).length > 0;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ① 主区域：断连横幅 + 会话主面 + 底部目标 Dock。
      Column() {
        /*
         * §FR-037：断连横幅——横幅组件归 HubBanner，这里只决定"壳层里它出现在
         * 主区顶部"。LOCAL / REMOTE 同一套：相位由中枢驱动，不按运行模式区别。
         * hubConnected 用来区分「连上过才断」与「从未连上」：后者的失败结论由
         * 连接页（ConnectPane）的回执块负责，不在这里重复播报。
         * 自动重试由连接层 ReconnectController 持续进行（耗尽后仍按固定节奏重连），
         * 横幅只呈现状态与手动入口。
         */
        if (this.f.mainShell.hubPhase === HubPhase.DEGRADED && this.f.mainShell.hubConnected) {
          HubBanner({
            errorText: this.f.mainShell.hubError,
            authority: this.f.mainShell.hubAuthority,
            phase: this.f.mainShell.hubPhase,
            streams: this.f.mainShell.hubStreams,
            traceTail: this.f.mainShell.hubTraceTail(),
            runMode: this.f.mainShell.runMode,
            onOpenDiagnostics: () => {
              this.f.mainShell.openDiagnostics();
            }
          })
        }
        Column() {
          MainShell({ f: this.f.mainShell, compact: true })
        }
        .width('100%')
        .layoutWeight(1)
        // ⑤ 底部 Dock（目标条；目标为空时自渲染为空，不占位）。
        LatticeDock({
          goalText: this.f.goalText
        })
      }
      .width('100%')
      .height('100%')

      // ② 遮罩层（抽屉打开时覆盖在主区上方；点按全关）
      if (this.f.drawerState.leftOpen || this.f.drawerState.rightOpen) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.palette().overlayMask)
          .transition(TransitionEffect.OPACITY.animation({
            duration: DsAnimation.PANEL_SLIDE.durationMs,
            curve: dsTweenCurve(DsAnimation.PANEL_SLIDE)
          }))
          .onClick(() => {
            this.f.onCloseDrawers();
          })
      }

      // ③ 左侧抽屉（会话列表；贴左缘，左滑关闭）
      if (this.f.drawerState.leftOpen) {
        Column() {
          DrawerNav({
            f: this.f.browser,
            onSelectSession: (id: string) => {
              this.f.browser.openSession(id);
              this.f.onCloseDrawers();
            },
            onNewSession: () => {
              this.f.browser.workspaces[0] !== undefined
                ? this.f.browser.createSessionIn(this.f.browser.workspaces[0])
                : null;
              this.f.onCloseDrawers();
            }
          })
        }
        .width(this.f.drawerState.leftWidth)
        .height('100%')
        .backgroundColor(this.palette().sidebar)
        .transition(TransitionEffect.move(TransitionEdge.START).animation({
          duration: DsAnimation.PANEL_SLIDE.durationMs,
          curve: dsTweenCurve(DsAnimation.PANEL_SLIDE)
        }))
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionEnd((event: GestureEvent) => {
              // 抽屉内容上左滑超过阈值 → 关闭（对照源码 swipe-left-on-drawer 关闭）
              if (event.offsetX < -this.swipeThreshold()) {
                this.f.onCloseDrawers();
              }
            })
        )
      }

      // ④ 右侧抽屉（会话详情；T020 对照 DetailsPanel.kt）。v1 直接把 320 宽的 Row 放在
      //    TopStart 的 Stack 里，结果贴在**左**缘——这里用全宽 Row + End 对齐把面板送到右缘；
      //    包装层 HitTestMode.None，面板左侧的空白区点按透传给 scrim（点按全关）。
      if (this.f.drawerState.rightOpen) {
        Row() {
          Column() {
            this.detailsPanelBody()
          }
          .width(this.f.drawerState.rightWidth)
          .height('100%')
          .backgroundColor(this.palette().bgLayer1)
          .transition(TransitionEffect.move(TransitionEdge.END).animation({
            duration: DsAnimation.PANEL_SLIDE.durationMs,
            curve: dsTweenCurve(DsAnimation.PANEL_SLIDE)
          }))
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionEnd((event: GestureEvent) => {
                // 面板上右滑超过阈值 → 关闭（对照源码 swipe-right-on-details 关闭）
                if (event.offsetX > this.swipeThreshold()) {
                  this.f.onCloseDrawers();
                }
              })
          )
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .hitTestBehavior(HitTestMode.None)
      }

      // ⑥ 缘带手势（最后渲染 = 最上层；透明带透传纵向滚动给下层内容）
      this.edgeBand(true)
      this.edgeBand(false)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.stackWidth = newArea.width as number;
    })
  }

  /* ═══════════════ 右侧抽屉：会话详情面板（对照 DetailsPanel.kt） ═══════════════ */

  /**
   * 面板本体：竖向滚动的卡列（源码：verticalScroll + padding(medium) + spacedBy(small)）。
   * 没有打开的会话时，会话相关的卡整段不出现（源码 conv==null 只给一句话）。
   */
  @Builder
  detailsPanelBody() {
    Scroll() {
      Column({ space: DsSpacing.SMALL }) {
        this.detailsHeader()
        if (!this.hasSession()) {
          Text('还没有打开的会话')
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontColor(this.palette().labelTertiary)
        } else {
          this.sessionCard()
          if (this.statsVisible()) {
            this.statsCard()
          }
          this.planCard()
          this.jobsCard()
          this.queueCard()
          ForEach(this.f.detailSections, (section: DetailSection) => {
            this.sectionCard(section)
          }, (section: DetailSection) => section.title)
        }
        this.hostCard()
      }
      .width('100%')
      .padding(DsSpacing.MEDIUM)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  /** 源码 `HeaderRow`：返回钮 + 「会话详情」 */
  @Builder
  detailsHeader() {
    Row() {
      DsIconButton({
        icon: $r('sys.symbol.chevron_left'),
        a11y: '关闭会话详情',
        onTap: () => {
          this.f.onCloseDrawers();
        }
      })
      Text('会话详情')
        .fontSize(DsType.LARGE_20.size)
        .lineHeight(DsType.LARGE_20.lineHeight)
        .fontWeight(DsType.LARGE_20.weight)
        .fontColor(this.palette().labelPrimary)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 会话卡（源码 `SessionCard`，initiallyExpanded=true——它是用户进这个面板
   * 最常来看的两件事之一）。模型 pill 点按 = 关抽屉 + 打开命令面板里的模型选择
   * （源码开 ModelsSheet 的对应通道）。重命名/fork 无写通道，省略。
   */
  @Builder
  sessionCard() {
    Column() {
      DsDisclosureRow({
        title: this.sessionTitleText(),
        summary: this.selectedCwdBasename(),
        expanded: this.isCardExpanded(CARD_SESSION, true),
        onToggle: () => {
          this.toggleCard(CARD_SESSION, true);
        }
      })
      if (this.isCardExpanded(CARD_SESSION, true)) {
        Column({ space: CARD_CONTENT_SPACE }) {
          if (this.selectedSessionCwd().length > 0) {
            Text(this.selectedSessionCwd())
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontColor(this.palette().labelCaption)
          }
          Row({ space: DsSpacing.XSMALL }) {
            // 模型 pill：可点是它看起来可点的前提（源码注释）；点击 = 关抽屉开模型选择
            if (modelSelectionLabel(this.f.mainShell.selection, this.f.mainShell.models).length > 0) {
              DsPill({
                text: modelSelectionLabel(this.f.mainShell.selection, this.f.mainShell.models),
                clickable: true,
                a11y: '切换本会话模型',
                onTap: () => {
                  this.f.onCloseDrawers();
                  this.f.mainShell.setPaletteOpen(true);
                }
              })
            }
          }
          .width('100%')
          if (this.sessionRunning()) {
            Row({ space: DsSpacing.XSMALL }) {
              DsStateDot({ state: DsStateDotState.RUNNING })
              Text('运行中')
                .fontSize(DsType.CAPTION_11.size)
                .lineHeight(DsType.CAPTION_11.lineHeight)
                .fontColor(this.palette().labelSecondary)
            }
            .alignItems(VerticalAlign.Center)
          }
          Row({ space: DsSpacing.SMALL }) {
            DsButton({
              text: '归档',
              variant: DsButtonVariant.GHOST,
              buttonSize: DsButtonSize.SMALL,
              a11y: '归档当前会话',
              onTap: () => {
                this.f.browser.archiveSession(this.f.mainShell.selectedSessionId);
              }
            })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: CARD_CONTENT_INSET, top: CARD_CONTENT_SPACE, bottom: CARD_CONTENT_SPACE })
      }
    }
    .width('100%')
  }

  /** 会话卡的 cwd 整行（源码 SessionCard 的 cwd 展示；空 = 不渲染） */
  private selectedSessionCwd(): string {
    const found: SessionListItem | undefined = this.findSelectedSession();
    return found !== undefined ? found.cwd : '';
  }

  /** 会话卡摘要：cwd 末段（源码 `summary = session.cwd?.let { basename(it) }`） */
  private selectedCwdBasename(): string {
    const found: SessionListItem | undefined = this.findSelectedSession();
    if (found !== undefined && found.cwd.length > 0) {
      return baseNameOf(found.cwd);
    }
    return '';
  }

  /** 运行中：优先列表项自己的 running，列表项不在手边时退到主区门面的 running */
  private sessionRunning(): boolean {
    const found: SessionListItem | undefined = this.findSelectedSession();
    if (found !== undefined) {
      return found.running;
    }
    return this.f.mainShell.running;
  }

  /**
   * 统计卡（源码 `ContextCard` 的对应物，initiallyExpanded=true）：中枢拼好的
   * 一行事实（轮次/速度/累计/缓存命中/预设）+ 时间四项（`statsLinesOf`）。
   * token 压力/分解（ContextMeterDetail）在 `SessionStatsInput` 里没有建模，不画。
   */
  @Builder
  statsCard() {
    Column() {
      DsDisclosureRow({
        title: '统计',
        expanded: this.isCardExpanded(CARD_STATS, true),
        onToggle: () => {
          this.toggleCard(CARD_STATS, true);
        }
      })
      if (this.isCardExpanded(CARD_STATS, true)) {
        Column({ space: CARD_CONTENT_SPACE }) {
          if (this.f.mainShell.statsLine.length > 0) {
            Text(this.f.mainShell.statsLine)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontColor(this.palette().labelTertiary)
          }
          ForEach(statsLinesOf(this.f.mainShell.sessionStats), (line: StatsLine) => {
            Text(this.statsLineText(line))
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontColor(this.palette().labelTertiary)
          }, (line: StatsLine) => line.key)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: CARD_CONTENT_INSET, top: CARD_CONTENT_SPACE, bottom: CARD_CONTENT_SPACE })
      }
    }
    .width('100%')
  }

  /**
   * 计划卡（源码 `PlanCard`）：一个开关说一件事。默认展开——别的卡是信息，
   * 这张是**控件**，要先展开才够得着的控件等于没有（源码注释原话）。
   */
  @Builder
  planCard() {
    Column() {
      DsDisclosureRow({
        title: '计划模式',
        summary: this.f.mainShell.planActive ? '已开启' : '已关闭',
        expanded: this.isCardExpanded(CARD_PLAN, true),
        onToggle: () => {
          this.toggleCard(CARD_PLAN, true);
        }
      })
      if (this.isCardExpanded(CARD_PLAN, true)) {
        Column() {
          DsToggleRow({
            label: '计划模式',
            hint: '开启后助手先给方案，确认后再动手',
            checked: this.f.mainShell.planActive,
            onChange: () => {
              this.f.mainShell.togglePlan();
            }
          })
        }
        .width('100%')
        .padding({ left: CARD_CONTENT_INSET, top: CARD_CONTENT_SPACE, bottom: CARD_CONTENT_SPACE })
      }
    }
    .width('100%')
  }

  /**
   * 后台任务卡（源码 `JobsCard`）：状态点 + label/kind + 耗时。
   * live 任务的耗时由 `jobsTick` 驱动走字（key 带上刻度，刻度才是本卡的真实依赖）。
   */
  @Builder
  jobsCard() {
    Column() {
      DsDisclosureRow({
        title: '后台任务',
        summary: this.f.mainShell.jobs.length > 0 ? `${this.f.mainShell.jobs.length}` : '',
        expanded: this.isCardExpanded(CARD_JOBS, false),
        onToggle: () => {
          this.toggleCard(CARD_JOBS, false);
        }
      })
      if (this.isCardExpanded(CARD_JOBS, false)) {
        Column({ space: CARD_CONTENT_SPACE }) {
          if (this.f.mainShell.jobs.length === 0) {
            Text('没有后台任务')
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontColor(this.palette().labelTertiary)
          } else {
            ForEach(orderedJobs(this.f.mainShell.jobs), (job: SessionJob) => {
              Row({ space: DsSpacing.SMALL }) {
                DsStateDot({ state: this.jobDotToState(job.status) })
                Column() {
                  Text(job.label.length > 0 ? job.label : job.kind)
                    .fontSize(DsType.SMALL_13.size)
                    .lineHeight(DsType.SMALL_13.lineHeight)
                    .fontColor(this.palette().labelPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(job.detail !== undefined && job.detail.length > 0
                    ? `${job.kind} · ${job.detail}` : job.kind)
                    .fontSize(DsType.CAPTION_11.size)
                    .lineHeight(DsType.CAPTION_11.lineHeight)
                    .fontColor(this.palette().labelCaption)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Text(jobDurationText(jobElapsedMs(job, Date.now())))
                  .fontSize(DsType.CAPTION_11.size)
                  .lineHeight(DsType.CAPTION_11.lineHeight)
                  .fontColor(this.palette().labelCaption)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              // key 带上每秒刻度：live 任务的耗时才会走字
            }, (job: SessionJob) => `${job.id}:${this.jobsTick}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: CARD_CONTENT_INSET, top: CARD_CONTENT_SPACE, bottom: CARD_CONTENT_SPACE })
      }
    }
    .width('100%')
  }

  /**
   * 队列卡（源码 `DetailsPanel.kt` 的 `QueueCard`，L540–576）：
   * 逐行 = 预览文本（`small13` / `labelPrimary` / 最多 2 行）+ `placement`（`caption11` / `labelCaption`）
   * + 一颗 Ghost/Small 的「移除」（源码 `DsButtonVariant.Ghost` + `DsButtonSize.Small` →
   * `store.updateQueue(id, "remove")`）。
   *
   * 【为什么现在能逐行画了】此前 `queuedItems` 恒为空数组（Index 写死 `[]`），
   * 而中枢早就在投影 `QueuedItem[]`（`Wire.ets`：id / placement / text）⇒
   * 队列卡只能给一个计数。接线后行数据来自宿主，行内动作走**既有的**
   * `SessionHub.removeQueuedItem`（与主区队列条同一个动作，不是第二条写通道）。
   */
  @Builder
  queueCard() {
    Column() {
      DsDisclosureRow({
        title: '队列',
        summary: this.f.mainShell.queuedCount > 0 ? `${this.f.mainShell.queuedCount}` : '',
        expanded: this.isCardExpanded(CARD_QUEUE, false),
        onToggle: () => {
          this.toggleCard(CARD_QUEUE, false);
        }
      })
      if (this.isCardExpanded(CARD_QUEUE, false)) {
        Column({ space: CARD_CONTENT_SPACE }) {
          if (this.f.queuedItems.length === 0) {
            Text('队列为空')
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontColor(this.palette().labelTertiary)
          } else {
            ForEach(this.f.queuedItems, (item: QueuedItem) => {
              Row({ space: DsSpacing.COMPACT }) {
                Column() {
                  Text(item.text)
                    .fontSize(DsType.SMALL_13.size)
                    .lineHeight(DsType.SMALL_13.lineHeight)
                    .fontColor(this.palette().labelPrimary)
                    .maxLines(2)                                   // 源码 maxLines = 2
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.placement)
                    .fontSize(DsType.CAPTION_11.size)
                    .lineHeight(DsType.CAPTION_11.lineHeight)
                    .fontColor(this.palette().labelCaption)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                DsButton({
                  text: '移除',
                  variant: DsButtonVariant.GHOST,
                  buttonSize: DsButtonSize.SMALL,
                  onTap: () => {
                    this.f.onRemoveQueued(item.id);
                  }
                })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }, (item: QueuedItem) => item.id)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: CARD_CONTENT_INSET, top: CARD_CONTENT_SPACE, bottom: CARD_CONTENT_SPACE })
      }
    }
    .width('100%')
  }

  /**
   * 过程台账卡（`detailSections`：工具调用 / 子代理 / 交付物 / 目标 / 任务）。
   * 源码把台账挪出了详情面板（"一个事实一个家"）；本仓的数据通道就是这份 sections
   * 投影，作为卡留在面板里。行点按 = 行内复制（`rightbar.onLineTap`）。
   */
  @Builder
  sectionCard(section: DetailSection) {
    Column() {
      DsDisclosureRow({
        title: section.title,
        summary: `${section.count}`,
        expanded: this.isCardExpanded(`sec:${section.title}`, false),
        onToggle: () => {
          this.toggleCard(`sec:${section.title}`, false);
        }
      })
      if (this.isCardExpanded(`sec:${section.title}`, false)) {
        Column({ space: CARD_CONTENT_SPACE }) {
          if (section.lines.length === 0) {
            // 空态说明"可以做什么"（D3 §4 文案纪律）
            Text(section.emptyHint)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontColor(this.palette().labelTertiary)
          } else {
            ForEach(section.lines, (line: string) => {
              Text(line)
                .fontSize(DsType.CAPTION_11.size)
                .lineHeight(DsType.CAPTION_11.lineHeight)
                .fontColor(this.palette().labelSecondary)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  this.f.rightbar.onLineTap(section.title, line);
                })
            }, (line: string, index: number) => `${section.title}-${index}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: CARD_CONTENT_INSET, top: CARD_CONTENT_SPACE, bottom: CARD_CONTENT_SPACE })
      }
    }
    .width('100%')
  }

  /** 主机卡（源码 `HostCard`）：连得上才有；摘要说运行模式，内容给连接地址 */
  @Builder
  hostCard() {
    if (this.f.mainShell.hubAuthority.length > 0) {
      Column() {
        DsDisclosureRow({
          title: '主机',
          summary: this.f.mainShell.runMode === RunMode.REMOTE ? '远程模式' : '本机模式',
          expanded: this.isCardExpanded(CARD_HOST, false),
          onToggle: () => {
            this.toggleCard(CARD_HOST, false);
          }
        })
        if (this.isCardExpanded(CARD_HOST, false)) {
          Column() {
            Text(this.f.mainShell.hubAuthority)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontColor(this.palette().labelCaption)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: CARD_CONTENT_INSET, top: CARD_CONTENT_SPACE, bottom: CARD_CONTENT_SPACE })
        }
      }
      .width('100%')
    }
  }

  /**
   * 缘带（对照 MainScreen.kt：左缘带右滑开会话抽屉 / 右缘带左滑开详情抽屉）。
   * Transparent：带子上的纵向手势继续交给下层（列表滚动、面板内容），
   * 只有横向拖拽由本带的 PanGesture 认领。
   */
  @Builder
  edgeBand(left: boolean) {
    Row() {
      if (left) {
        Column()
          .width(REMOTE_EDGE_BAND_WIDTH)
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionEnd((event: GestureEvent) => {
                // 右滑超过阈值 → 打开会话抽屉
                if (event.offsetX > this.swipeThreshold() && !this.f.drawerState.leftOpen) {
                  this.f.onOpenLeftDrawer();
                }
              })
          )
      } else {
        Column()
          .width(REMOTE_EDGE_BAND_WIDTH)
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionEnd((event: GestureEvent) => {
                // 左滑超过阈值 → 打开详情抽屉
                if (event.offsetX < -this.swipeThreshold() && !this.f.drawerState.rightOpen) {
                  this.f.onOpenRightDrawer();
                }
              })
          )
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(left ? FlexAlign.Start : FlexAlign.End)
    .hitTestBehavior(HitTestMode.None)
  }
}

/* ───────── 小工具（string[] 的三态表操作） ───────── */

function addTo(list: string[], id: string): string[] {
  if (list.indexOf(id) >= 0) {
    return list;
  }
  const out: string[] = list.slice(0);
  out.push(id);
  return out;
}

function removeFrom(list: string[], id: string): string[] {
  const at: number = list.indexOf(id);
  if (at < 0) {
    return list;
  }
  return list.slice(0, at).concat(list.slice(at + 1));
}
