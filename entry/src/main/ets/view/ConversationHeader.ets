/**
 * 会话正文的**头部**（P2-5：从 `ConversationPane` 抽出的第一刀）。
 *
 * ## v2 T014：按 DSH Mobile 源码级对照重塑（视觉/交互层）
 *
 * 【对照源文件】`.research/deepseek-harness-mobile/app/src/main/java/com/labteto/dshmobile/ui/screens/main/ChatTopBar.kt`
 * （`ChatTopBar` 三行结构、`ModelChip`、`ChatTabRow`）与
 * `ui/components/StateDot.kt`（Running 的 3×3 像素追逐）、`DsSegmented.kt`（轨道 + 拇指）。
 *
 * · **Row 1（连接层）**：`ModelChip`（r∞ pill、`hoverSolid` 底、`borderL2` 发丝边、
 *   `STD_14_STRONG` + `chevron_down` 14，点开模型选择器——源码注释：触屏没有 hover，
 *   裸文字看不出模型可切，所以画成**实底 pill**）+ spacer + `StateDot`
 *   （运行中 = Deepseek450 3×3 像素追逐 / 空闲 = `labelCaption` 圆点）+ 跨会话搜索钮
 *   （单栏才画，见 `sessionSearchOpen` 的说明）+ info 图标钮。
 *   源码行首还有一颗**抽屉**钮（`FeatherIcons.Menu` → `sys.symbol.hamburgers`）。
 *   本仓的 props 链上没有"开抽屉"通道（`MainShell` 的 facade 不放行、`Index` 禁改），
 *   走 **AppStorage 事件信道**：`dsDrawerHostActive`（右抽屉宿主 `RemoteShell` 挂载时
 *   置 true——不在场就不画这颗钮，不放假入口 P7-18）+ `dsOpenLeftDrawerSignal`
 *   （点击发布 `Date.now()` 信号，宿主 `@StorageProp + @Watch` 收到 → 开左抽屉）。
 *   T019/T020 接线完成。
 * · **Row 2（会话层）**：上下文行（工作区 · 最近活动；模型段已上移 ModelChip，
 *   与源码"模型在 Row 1"同一分工）——一段都拿不到时整行不画（源码同判据）。
 * · **Row 3（视图页签）**：`DsSegmented`（对话 / 轨迹）紧凑分段控件——
 *   `hoverSolid` 轨道 + `borderL2` 描边 + 选中段 `accentTertiary` 实底 + `accent` 文字
 *   （源码注释：哪一页在直播是**承重**的——两个视图对同一条消息的画法完全不同）；
 *   底部 1dp `borderL1` 分隔线收尾。
 * · 保留的 v1 chrome（无 Mobile 对应件或属他人领地）：轨迹工具栏（展开/收起/搜索/计数，
 *   仍是**可换行 Flex**）、后台任务条、时间总览（`TimelineOverview`）、事件详情
 *   （`TrajectoryInspector`）、会话内搜索条——一律换用 MobileTheme token。
 * · 明暗色板：`mediaquery('(prefers-color-scheme: dark)')` + `dsPaletteOf(SYSTEM, dark)`。
 *
 * ## 搜索与任务条的**状态为什么仍在父组件**
 *
 * · **搜索**：命中判定要扫整条过程流（`matchTrajectoryIndices`），命中的高亮也要画在
 *   列表项上 ⇒ 状态在父组件，这里只做"显示 + 转发"（输入框的每个字符都会回到父组件）。
 * · **任务条**：live 任务的耗时每秒走字，而"要不要起定时器"由模型 `jobTickerNeeded`
 *   判定、父组件持有定时器 ⇒ 刻度（`jobsTick`）由父组件当 prop 传进来，
 *   **它同时是本组件的真实依赖**（刻度变了才重绘）。
 */

import {
  Border, DsColor, DsPalette, DsShape, DsSpacing, DsThemePreference, DsType, JobDot,
  dsPaletteOf, jobCountLabel, jobDotState, jobDurationText, jobDurationTitle, jobElapsedMs,
  jobListA11y, jobListVisible, jobRowStatusText, liveJobCount, matchCounterText, orderedJobs,
  relativeTime, sessionContextLine
} from 'appstate';
import type { SessionJob, SessionStatsInput, TrajectoryItem } from 'appstate';
import { TimelineOverview } from './TimelineOverview';
import { TrajectoryInspector } from './TrajectoryInspector';
import { mediaquery } from '@kit.ArkUI';

// ───────────── StateDot 几何（对照 StateDot.kt：size = 8.dp 默认档） ─────────────
/** 圆点边长（源码 `size: Dp = 8.dp`） */
const DOT_SIZE: number = 8;
/** 光晕半径 = size × 0.58（源码 `drawHalo`）⇒ 直径 */
const DOT_HALO: number = DOT_SIZE * 0.58 * 2;
/** 追逐矩阵的格子边长 = size / 3（源码 `drawPixelChase`） */
const DOT_CELL: number = DOT_SIZE / 3;
/** 点亮像素边长 = cell × 0.74（源码同值；2vp 尺度上圆角读不出，画成方像素） */
const DOT_PIX: number = DOT_CELL * 0.74;
/** 环形点亮序（源码 `ring = intArrayOf(0, 1, 2, 5, 8, 7, 6, 3, 4)`） */
const CHASE_RING: number[] = [0, 1, 2, 5, 8, 7, 6, 3, 4];
/**
 * 图标几何（vp）。对照 `DsIconButton.kt` / `ChatTopBar.kt` 的 iconSize 字面值：
 * 图标钮 18、ModelChip 尾随 chevron 14——字阶 token（DsType）不表达图标边长，
 * 照抄源码值并在此注明。
 */
const ICON_GLYPH: number = 18;
const ICON_CHEVRON: number = 14;

/** 给 0xRRGGBB 的 token 色加 α（源码 `color.copy(alpha = …)` 的 ArkTS 侧对应物） */
function alphaOf(color: number, alpha: number): number {
  return ((Math.round(alpha * 255) & 0xFF) << 24) | (color & 0x00FFFFFF);
}

/** 会话头的呈现（模型/状态行 / 上下文行 / 视图页签 / 任务条 / 时间总览 / 搜索） */
@Component
export struct ConversationHeader {
  /** 当前视图（`chat` / `trajectory`）——唯一真值在父组件 */
  @Prop view: string = 'chat';
  /** 全量条目（轨迹工具栏的计数 + 时间总览的输入） */
  @Prop items: TrajectoryItem[] = [];
  /** 后台任务（官方会话头的任务条；模型判定"要不要显示"） */
  @Prop jobs: SessionJob[] = [];
  /** 任务条的重绘刻度（live 任务每秒走字；父组件的定时器在推进它） */
  @Prop jobsTick: number = 0;
  /** 任务清单是否展开（官方是"触发器 + 下拉清单"；默认收起，不占会话头的版面） */
  @State jobsOpen: boolean = false;
  /** §FR-049：展开详情的任务 id（空串 = 不展开） */
  @State expandedJobId: string = '';
  /**
   * 时间总览要的统计（数字，不是拼好的字符串）。
   *
   * 【为什么没有默认值】与 `TimelineOverview` 一致：宿主一定给（它就是投影出来的统计事实）。
   * 造一个"全 0 的默认统计"会让"没接到数据"看起来像"这场会话什么也没花"——那是假的读数。
   */
  @Prop stats: SessionStatsInput;
  /** 时间线当前聚焦的格子（父组件持有：滚动时它也跟着走） */
  @Prop focusedCellId: string = '';
  /** 清掉聚焦（详情卡上的「关闭」） */
  onClearFocus: () => void = () => {
  };
  /** 是否正在拖动时间线（拖动期间关掉"滚动→聚焦"这一路） */
  @Prop dragging: boolean = false;
  /** 搜索条是否打开 */
  @Prop searchOpen: boolean = false;
  /** 搜索词（唯一真值在父组件） */
  @Prop searchQuery: string = '';
  /** 命中位置 / 命中总数（父组件算好——它扫的是整条过程流） */
  @Prop matchPos: number = -1;
  @Prop hitCount: number = 0;
  /** 上下文行：工作区名（空 = 不显示这一段） */
  @Prop workspaceName: string = '';
  /** 选中会话的最近活动时间（毫秒；0 = 不显示「多久没动」） */
  @Prop sessionUpdatedAt: number = 0;
  /** 当前模型名（父组件用 `modelSelectionLabel` 拼好；空 = 显示占位） */
  @Prop modelLabel: string = '';
  /** 本会话是否正在生成（Row 1 状态点：Running / Idle） */
  @Prop running: boolean = false;

  /** 切模型（ModelChip；宿主弹出选择器） */
  onPickModel: () => void = () => {
  };
  /** 打开会话详情（info 图标钮；源码 `onOpenDetails` 的对应物） */
  onOpenDetail: () => void = () => {
  };
  /** 切视图（对话 / 轨迹） */
  onPickView: (view: string) => void = () => {
  };
  /** 轨迹工具栏：展开全部 / 收起全部 */
  onExpandAll: () => void = () => {
  };
  onCollapseAll: () => void = () => {
  };
  /** 搜索词变化（父组件重算命中） */
  onQueryChange: (value: string) => void = () => {
  };
  /** 上一条 / 下一条命中 */
  onStep: (delta: number) => void = () => {
  };
  /** 关闭搜索 */
  onCloseSearch: () => void = () => {
  };
  /** 打开搜索（**触屏入口**；手机上按不到 Ctrl/Cmd+F） */
  onOpenSearch: () => void = () => {
  };
  /** 当前档位（`Index` 发布）——只用来决定搜索框是"常驻"还是"按需" */
  @StorageProp('dshLayoutMode') layoutMode: string = 'single';
  /**
   * **跨会话搜索**条是否打开（唯一真值在父组件 `ConversationPane.sessionSearchOpen`；
   * 这里只读它决定钮的着色）。
   *
   * 【为什么这颗钮要有】跨会话搜索的 `SessionSearch` 实例挂在 `ConversationPane` 上，
   * 而它此前**只有关闭路径、没有打开路径**（v1 的打开入口在 PC 侧栏的搜索钮上，
   * 随 PC 原生链一起消失）⇒ 组件已接线但用户够不着。手机的左抽屉里另有一份搜索
   * （`DrawerNav`，对照 `ChatListDrawer.kt` 的抽屉内搜索），两者是**不同的事**：
   * 抽屉那个过滤"会话列表"，这个按内容跨会话命中并直接跳转（§FR-005）。
   */
  @Prop sessionSearchOpen: boolean = false;
  /** 切换跨会话搜索条（父组件持有开合状态） */
  onToggleSessionSearch: () => void = () => {
  };
  /**
   * 抽屉宿主在场（`RemoteShell` 挂载时置 true）——只用来决定 Row 1 行首抽屉钮是否显示。
   * 没有抽屉面的档位（手机单栏）不画点了没反应的假钮（P7-18）。
   */
  @StorageProp('dsDrawerHostActive') drawerHostActive: boolean = false;
  /** 时间总览：聚焦某一格 / 提交（提交 = 滚到聚焦项）/ 拖动状态变化 */
  onFocusCell: (cellId: string) => void = () => {
  };
  onCommitTimeline: () => void = () => {
  };
  onDragChange: (dragging: boolean) => void = () => {
  };

  /** 像素追逐的当前步（0–8；源码 keyframes：每 1000ms 前进一格，9s 一轮） */
  @State private chaseStep: number = 0;
  /** 追逐步进定时器（-1 = 未启动；只在运行中推进） */
  private chaseTimer: number = -1;
  /** 系统是否深色（`prefers-color-scheme`；MobileTheme 色板的解析输入） */
  @State dark: boolean = false;
  /** 深色模式监听（aboutToDisappear 必须注销） */
  private darkQuery: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.darkQuery = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
    this.dark = this.darkQuery.matches;
    this.darkQuery.on('change', (result: mediaquery.MediaQueryResult) => {
      this.dark = result.matches;
    });
    // 离散步进（源码 keyframes 1s/格）：状态驱动重绘，running=false 时空转不推进
    this.chaseTimer = setInterval(() => {
      if (this.running) {
        this.chaseStep = (this.chaseStep + 1) % 9;
      }
    }, 1000);
  }

  aboutToDisappear(): void {
    this.darkQuery?.off('change');
    this.darkQuery = null;
    if (this.chaseTimer >= 0) {
      clearInterval(this.chaseTimer);
      this.chaseTimer = -1;
    }
  }

  /** 当前语义色板（MobileTheme 唯一视觉 token 源；SYSTEM 偏好随系统明暗切换） */
  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.dark);
  }

  /**
   * 追逐格的 α（源码 `drawPixelChase` 的分段：已过 0.45 / 当前 1 / 未到 0.12）。
   */
  private chaseAlpha(cellIndex: number): number {
    const pos: number = CHASE_RING.indexOf(cellIndex);
    if (pos < this.chaseStep) {
      return 0.45;
    }
    if (pos === this.chaseStep) {
      return 1;
    }
    return 0.12;
  }

  /**
   * 上下文行：工作区 · 最近活动。
   *
   * 【为什么在视图里拼】两段事实都在本组件手边（prop + 相对时间），
   * 而「每段拿不到就不出现」的规则在 `sessionContextLine`（纯模型、有 fixture）。
   * 【为什么没有模型段】模型已上移 Row 1 的 ModelChip（源码同一分工：
   * Row 1 管"连接层"的事，Row 2 管"这场会话"的事）。
   * 【为什么要传 now】`relativeTime` 需要「现在」，由调用点给 ⇒ 这一行随时钟自然更新，
   * 不引入第二个定时器（任务条已经有一个每秒刻度）。
   */
  private contextLine(): string {
    const updated: string = this.sessionUpdatedAt > 0
      ? relativeTime(this.sessionUpdatedAt, Date.now())
      : '';
    return sessionContextLine(this.workspaceName, '', updated);
  }

  /** 状态点 → 语义色（模型给语义 `JobDot`，颜色是视图的事） */
  private jobDotColor(status: string): number {
    const dot: JobDot = jobDotState(status);
    if (dot === JobDot.ONGOING) {
      return this.palette().accent;
    }
    if (dot === JobDot.WARNING) {
      return this.palette().warnLabel;
    }
    if (dot === JobDot.DONE) {
      return this.palette().success;
    }
    return this.palette().error;
  }

  /** 当前聚焦的条目（格子 id 就是条目 id，见 `TimelineOverview` 的 `cellIdForListIndex`） */
  private focusedItem(): TrajectoryItem | undefined {
    if (this.focusedCellId.length === 0) {
      return undefined;
    }
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === this.focusedCellId) {
        return this.items[i];
      }
    }
    return undefined;
  }

  build() {
    Column() {
      /*
       * Row 1（对照源码：连接层的控件）——行首抽屉钮（宿主在场才显示，
       * 点击经 AppStorage 信号由 RemoteShell 开左抽屉，见文件头说明）
       * + ModelChip + spacer + StateDot + info。
       */
      Row() {
        if (this.drawerHostActive) {
          this.iconButton($r('sys.symbol.hamburgers'), '打开会话列表', this.palette().labelSecondary,
            () => {
              AppStorage.setOrCreate('dsOpenLeftDrawerSignal', Date.now());
            })
        }
        this.modelChip()
        Blank()
        this.stateDot()
        /*
         * 跨会话搜索入口（§FR-005）。单栏才画：非单栏的搜索框本来就常驻在
         * `ConversationPane` 的轨迹工具栏里，再画一颗会变成同一件事的两个入口。
         */
        if (this.layoutMode === 'single') {
          this.iconButton($r('sys.symbol.magnifyingglass'), '跨会话搜索',
            this.sessionSearchOpen ? this.palette().accent : this.palette().labelTertiary,
            () => {
              this.onToggleSessionSearch();
            })
        }
        this.iconButton($r('sys.symbol.info_circle'), '会话详情', this.palette().labelTertiary,
          () => {
            this.onOpenDetail();
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 48 })   // 源码 heightIn(min = 48.dp)
      .padding({ left: DsSpacing.TINY, right: DsSpacing.TINY })
      .alignItems(VerticalAlign.Center)

      /*
       * Row 2（对照源码：会话层的控件——标题 + chips；我们的对应物是上下文行）。
       * 一段都拿不到时整行不画：空行占位比没有更难读（源码同判据）。
       */
      if (this.contextLine().length > 0) {
        Row() {
          Text(this.contextLine())
            .fontSize(DsType.SMALL_13.size)
            .lineHeight(DsType.SMALL_13.lineHeight)
            .fontColor(this.palette().labelSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({
          left: DsSpacing.MEDIUM,
          right: DsSpacing.MEDIUM,
          top: DsSpacing.TINY,
          bottom: DsSpacing.TINY
        })
        .alignItems(VerticalAlign.Center)
      }

      /*
       * Row 3：视图页签（对照 `ChatTabRow` → `DsSegmented`）。
       *
       * 对话 / 轨迹 两个视图（E108，与官方 web 一致）：
       *   - **对话**：只看问答——日常使用；
       *   - **轨迹**：看全过程（工具调用、子代理、目标/任务、交付物、错误）——排查与复盘。
       *
       * 【为什么是分段控件而不是下划线页签】源码注释：两个短标签浮在全宽下划线上
       * 读作"页标题"还白占一行；28dp 的轨道裹住标签，chrome 到此为止。
       */
      Row() {
        Row({ space: 2 }) {
          this.segment('chat', $r('app.string.view_chat'))
          this.segment('trajectory', $r('app.string.view_trajectory'))
        }
        .padding(2)
        .borderRadius(DsShape.PILL_FULL)
        .backgroundColor(this.palette().hoverSolid)
        .borderWidth(Border.HAIRLINE)
        .borderColor(this.palette().borderL2)
      }
      .width('100%')
      .padding({
        left: DsSpacing.MEDIUM,
        right: DsSpacing.MEDIUM,
        top: DsSpacing.TINY,
        bottom: DsSpacing.TINY
      })
      .alignItems(VerticalAlign.Center)

      // 底部 1dp 分隔线（源码 `Spacer(1.dp).background(borderL1)`）
      Row()
        .height(Border.HAIRLINE)
        .width('100%')
        .backgroundColor(this.palette().borderL1)

      /*
       * 轨迹工具栏（v1 chrome；Mobile 头部无对应件）。
       *
       * 【为什么这一行也要可换行】轨迹视图下这里有三个动作（展开全部 / 收起全部 / N 条事件）
       * 加触屏搜索入口，手机宽度下加起来可能超过屏宽；`docs/08` P0 §7 点名的那类缺陷：
       * 操作区被挤压时不得静默消失。官方的行容器用 `flex-wrap: wrap` + `space-between`，
       * 这里照同一结构：放得下时靠右，放不下时整组换行，控件一个不少。
       */
      if (this.view === 'trajectory') {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End, alignItems: ItemAlign.Center }) {
          Text('展开全部')
            .fontSize(DsType.SMALL_13.size)
            .fontColor(this.palette().accent)
            .onClick(() => {
              this.onExpandAll();
            })
            .margin({ right: DsSpacing.MEDIUM, bottom: DsSpacing.XSMALL })
          Text('收起全部')
            .fontSize(DsType.SMALL_13.size)
            .fontColor(this.palette().accent)
            .onClick(() => {
              this.onCollapseAll();
            })
            .margin({ right: DsSpacing.MEDIUM, bottom: DsSpacing.XSMALL })
          /*
           * 触屏搜索入口（单栏才需要：非单栏搜索框本来就常驻）。
           * 图标名已在权威清单里核过（`magnifyingglass`），不是猜的。
           */
          if (this.layoutMode === 'single' && !this.searchOpen) {
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(ICON_GLYPH)
                .fontColor([this.palette().accent])
            }
            .constraintSize({ minWidth: 32, minHeight: 32 })
            .accessibilityText('打开会话内搜索')
            .onClick(() => {
              this.onOpenSearch();
            })
            .margin({ right: DsSpacing.MEDIUM, bottom: DsSpacing.XSMALL })
          }
          Text(`${this.items.length} 条事件`)
            .fontSize(DsType.SMALL_13.size)
            .fontColor(this.palette().labelTertiary)
            .margin({ bottom: DsSpacing.XSMALL })
        }
        .width('100%')
        .padding({
          left: DsSpacing.MEDIUM,
          right: DsSpacing.MEDIUM,
          top: DsSpacing.XSMALL
        })
      }

      // 后台任务条（官方在会话头）：有任务才出现，位置在页签行下方
      if (jobListVisible(this.jobs)) {
        this.jobsStrip()
      }

      // 轨迹视图的时间总览（P2 §11 的 TrajectoryPresenter）
      if (this.view === 'trajectory') {
        // 时间总览归 TimelineOverview（右栏「轨迹」面板用**同一份**）
        TimelineOverview({
          items: this.items,
          stats: this.stats,
          focusedCellId: this.focusedCellId,
          dragging: this.dragging,
          onFocusCell: (cellId: string) => {
            this.onFocusCell(cellId);
          },
          onCommit: () => {
            this.onCommitTimeline();
          },
          onDragChange: (dragging: boolean) => {
            this.onDragChange(dragging);
          }
        })
      }

      /*
       * 事件详情（P7-4）：点格子/点条目即聚焦，这里给出那一条的字段明细 ——
       * 官方点一条事件也会开出「事件详情」面板。空焦点时整卡不出现。
       */
      if (this.focusedItem() !== undefined) {
        TrajectoryInspector({
          item: this.focusedItem(),
          onClose: () => {
            this.onClearFocus();
          }
        })
      }

      /*
       * 【搜索框的可见性（2026-09-17，对齐官方轨迹页）】
       *
       * 官方轨迹页顶部那个搜索框是**常驻**的；我们此前只在 `searchOpen` 为真时渲染，
       * 而 `searchOpen` 只由 `Ctrl/Cmd+F` 置真 ⇒ ① 非单栏形态与官方不一致；
       * ② 手机上**根本没有任何办法**打开会话内搜索。
       *
       * 现在：**非单栏一律显示**（与官方 1:1）；单栏仍按需（省竖向空间），
       * 但补了一个触屏入口（轨迹工具栏那颗放大镜）——所以手机上不再是死路。
       */
      if (this.searchOpen || this.layoutMode !== 'single') {
        this.searchBar()
      }
    }
    .width('100%')
    .backgroundColor(this.palette().bgBase)
  }

  /**
   * 模型 chip（对照 `ModelChip`）。
   *
   * 【为什么是实底 pill】源码注释：web 上这个入口的示能是 hover 态，而触屏没有 hover——
   * 裸文字浮在正文上方完全看不出"模型可以切"。
   * 【显示名而不是线上 id】`modelLabel` 由父组件用 `modelSelectionLabel` 拼好。
   */
  @Builder
  modelChip() {
    Row({ space: DsSpacing.TINY }) {
      Text(this.modelLabel.length > 0 ? this.modelLabel : '选择模型')
        .fontSize(DsType.STD_14_STRONG.size)
        .lineHeight(DsType.STD_14_STRONG.lineHeight)
        .fontWeight(DsType.STD_14_STRONG.weight)
        .fontColor(this.palette().labelPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(ICON_CHEVRON)
        .fontColor([this.palette().labelSecondary])
    }
    .constraintSize({ minHeight: 28, maxWidth: 240 })   // 源码 heightIn(min=28) / widthIn(max=240)
    .padding({
      left: DsSpacing.COMPACT,
      right: DsSpacing.COMPACT,
      top: DsSpacing.TINY,
      bottom: DsSpacing.TINY
    })
    .borderRadius(DsShape.PILL_FULL)
    .backgroundColor(this.palette().hoverSolid)
    .borderWidth(Border.HAIRLINE)
    .borderColor(this.palette().borderL2)
    .accessibilityText(`当前模型：${this.modelLabel}，点击切换`)
    .onClick(() => {
      this.onPickModel();
    })
  }

  /**
   * 状态点（对照 `StateDot`）。
   *
   * · 空闲：`labelCaption` 圆点 + 10% 光晕；
   * · 运行中：`Ds.Deepseek450` 的 3×3 像素矩阵，环形点亮序、每秒一格、9s 一轮
   *   （离散 keyframes，不是渐变追逐——"discrete 1s steps" 是源码原话）。
   */
  @Builder
  stateDot() {
    if (this.running) {
      Stack() {
        Circle({ width: DOT_HALO, height: DOT_HALO })
          .fill(alphaOf(DsColor.DEEPSEEK_450, 0.10))
        Column() {
          Row() {
            this.chaseCell(0)
            this.chaseCell(1)
            this.chaseCell(2)
          }
          Row() {
            this.chaseCell(3)
            this.chaseCell(4)
            this.chaseCell(5)
          }
          Row() {
            this.chaseCell(6)
            this.chaseCell(7)
            this.chaseCell(8)
          }
        }
      }
      .width(DOT_SIZE)
      .height(DOT_SIZE)
      .accessibilityText('正在生成')
    } else {
      Stack() {
        Circle({ width: DOT_HALO, height: DOT_HALO })
          .fill(alphaOf(this.palette().labelCaption, 0.10))
        Circle({ width: DOT_SIZE, height: DOT_SIZE })
          .fill(this.palette().labelCaption)
      }
      .width(DOT_SIZE)
      .height(DOT_SIZE)
      .accessibilityText('空闲')
    }
  }

  /** 追逐矩阵的一格（9 格铺成 3×3；α 按 `chaseAlpha` 分段） */
  @Builder
  chaseCell(cellIndex: number) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(DOT_PIX)
        .height(DOT_PIX)
        .backgroundColor(DsColor.DEEPSEEK_450)
        .opacity(this.chaseAlpha(cellIndex))
    }
    .width(DOT_CELL)
    .height(DOT_CELL)
  }

  /**
   * 图标钮（对照 `DsIconButton`：48dp 保证触达、图标居中、`labelSecondary`/`labelTertiary`）。
   */
  @Builder
  iconButton(symbol: Resource, a11y: string, tint: number, onTap: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(symbol)
        .fontSize(ICON_GLYPH)
        .fontColor([tint])
    }
    .width(DsSpacing.TOUCH_TARGET)
    .height(DsSpacing.TOUCH_TARGET)
    .accessibilityText(a11y)
    .onClick(() => {
      onTap();
    })
  }

  /** 分段控件的一段（对照 `DsSegmented`：选中 = `accentTertiary` 底 + `accent` 文字） */
  @Builder
  segment(key: string, label: ResourceStr) {
    Text(label)
      .fontSize(DsType.TAB_TEXT.size)
      .lineHeight(DsType.TAB_TEXT.lineHeight)
      .fontWeight(DsType.TAB_TEXT.weight)
      .fontColor(this.view === key ? this.palette().accent : this.palette().labelTertiary)
      .padding({
        left: DsSpacing.MEDIUM,
        right: DsSpacing.MEDIUM,
        top: DsSpacing.TINY,
        bottom: DsSpacing.TINY
      })
      .constraintSize({ minHeight: 24 })   // 源码内联段 heightIn(min = 24.dp)
      .borderRadius(DsShape.PILL_FULL)
      .backgroundColor(this.view === key ? this.palette().accentTertiary : Color.Transparent)
      .accessibilityText(`${label}视图${this.view === key ? '（当前）' : ''}`)
      .onClick(() => {
        this.onPickView(key);
      })
  }

  @Builder
  searchBar() {
    Row({ space: DsSpacing.SMALL }) {
      TextInput({ text: this.searchQuery, placeholder: '在本次会话中搜索…' })
        .layoutWeight(1)
        .fontSize(DsType.STD_14.size)
        .fontColor(this.palette().labelPrimary)
        .placeholderColor(this.palette().labelTertiary)
        .constraintSize({ minHeight: DsSpacing.TOUCH_TARGET - 8 })
        .onChange((value: string) => {
          this.onQueryChange(value);
        })
        .accessibilityText('会话内搜索输入框')
      Text(matchCounterText(this.matchPos, this.hitCount))
        .fontSize(DsType.XSMALL_12.size)
        .fontColor(this.palette().labelTertiary)
      Text('↑')
        .fontSize(DsType.STD_14.size)
        .fontColor(this.palette().accent)
        .padding(DsSpacing.XSMALL)
        .onClick(() => {
          this.onStep(-1);
        })
      Text('↓')
        .fontSize(DsType.STD_14.size)
        .fontColor(this.palette().accent)
        .padding(DsSpacing.XSMALL)
        .onClick(() => {
          this.onStep(1);
        })
      Text('×')
        .fontSize(DsType.STD_14.size)
        .fontColor(this.palette().labelSecondary)
        .padding(DsSpacing.XSMALL)
        .onClick(() => {
          this.onCloseSearch();
        })
    }
    .width('100%')
    .padding({
      left: DsSpacing.MEDIUM,
      right: DsSpacing.MEDIUM,
      top: DsSpacing.SMALL,
      bottom: DsSpacing.SMALL
    })
    .backgroundColor(this.palette().bgModulePlatform)
  }

  /**
   * 后台任务（P2-2；P7-3 按官方结构改成**触发器 + 展开清单**）。
   *
   * 【官方长什么样（读 `@deepseek-ai/dsh-client-ui-jobs` 的源码）】会话头只放一个**按钮**：
   * `StateDot`（**只在有 live 任务时**）+ 计数文案（`{count} 个后台任务运行中` / `{count} 个后台任务`）
   * + 折叠指示；`aria-label` 是 `后台任务`。点开才是一张清单，每行 = 状态点 + `job.kind`
   * + `job.label` + `job.detail ?? 状态文案` + 耗时（`已运行 {d}` / `耗时 {d}` 是 tooltip 文案）。
   * 状态文案逐条对齐官方字典：运行中 / 正在停止 / 已完成 / 已取消 / 已失败。
   *
   * 【为什么改成这样】我们此前是"**常开**的换行任务条 + 一句『展开收起全部任务在轨迹』"：
   * 任务一多就把会话头撑高，而那句提示还把用户指向另一个页面 —— 官方根本没有这个指引。
   * 判定仍全部在 `Jobs` 模型里（`orderedJobs` / `jobRowStatusText` / `jobElapsedMs` /
   * `jobDurationText` / `jobDurationTitle` / `jobListA11y` / `liveJobCount`），视图只做点+字+色。
   */
  @Builder
  jobsStrip() {
    Column({ space: DsSpacing.XSMALL }) {
      Row({ space: DsSpacing.SMALL }) {
        // 「有 live 任务」才给状态点（官方 `liveCount > 0` 的条件渲染）
        if (liveJobCount(this.jobs) > 0) {
          Circle({ width: 8, height: 8 })   // token-exempt: 状态点几何（官方 strip 的圆点同义规格）
            .fill(this.jobDotColor('running'))
        }
        Text(jobCountLabel(this.jobs))
          .fontSize(DsType.XSMALL_12.size)
          .fontColor(this.palette().labelTertiary)
          .layoutWeight(1)
        SymbolGlyph(this.jobsOpen ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(DsType.XSMALL_12.size)
          .fontColor([this.palette().labelTertiary])
      }
      .width('100%')
      .height(DsSpacing.TOUCH_TARGET)   // 48vp 命中区（E214 的教训：只挂 onClick 的文字按不准）
      .borderRadius(DsShape.ROW)
      .accessibilityText(jobListA11y(this.jobs))
      .onClick(() => {
        this.jobsOpen = !this.jobsOpen;
      })

      if (this.jobsOpen) {
        ForEach(orderedJobs(this.jobs), (job: SessionJob) => {
          Column({ space: DsSpacing.XSMALL }) {
            Row({ space: DsSpacing.SMALL }) {
              Circle({ width: 8, height: 8 })   // token-exempt: 状态点几何（同上）
                .fill(this.jobDotColor(job.status))
              // 官方清单里 kind 与 label 是**两列**：kind 说"哪一类任务"，label 说"哪一个"
              Text(job.kind)
                .fontSize(DsType.CAPTION_11.size)
                .fontColor(this.palette().labelTertiary)
                .maxLines(1)
              Text(job.label.length > 0 ? job.label : job.kind)
                .fontSize(DsType.XSMALL_12.size)
                .fontColor(this.palette().labelSecondary)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(job.detail !== undefined && job.detail.length > 0
                ? job.detail
                : jobRowStatusText(job))
                .fontSize(DsType.CAPTION_11.size)
                .fontColor(this.palette().labelTertiary)
                .maxLines(1)
              Text(jobDurationText(jobElapsedMs(job, Date.now())))
                .fontSize(DsType.CAPTION_11.size)
                .fontColor(this.palette().labelTertiary)
              // §FR-049：展开/收起指示器
              SymbolGlyph(this.expandedJobId === job.id
                ? $r('sys.symbol.chevron_down')
                : $r('sys.symbol.chevron_right'))
                .fontSize(DsType.CAPTION_11.size)
                .fontColor([this.palette().labelTertiary])
            }
            .width('100%')
            .padding({
              left: DsSpacing.SMALL,
              right: DsSpacing.SMALL,
              top: DsSpacing.XSMALL,
              bottom: DsSpacing.XSMALL
            })
            .borderRadius(DsShape.ROW)
            .backgroundColor(this.palette().bgModulePlatform)
            .accessibilityText(jobDurationTitle(job, Date.now()))
            .onClick(() => {
              // §FR-049：点击任务条目展开/收起参数和输出
              this.expandedJobId = this.expandedJobId === job.id ? '' : job.id;
            })
            // §FR-049：展开后显示参数和输出
            if (this.expandedJobId === job.id) {
              Column({ space: DsSpacing.XSMALL }) {
                if (job.kind.length > 0) {
                  Row({ space: DsSpacing.SMALL }) {
                    Text('类型')
                      .fontSize(DsType.CAPTION_11.size)
                      .fontColor(this.palette().labelTertiary)
                      .width(40)
                    Text(job.kind)
                      .fontSize(DsType.XSMALL_12.size)
                      .fontColor(this.palette().labelSecondary)
                      .layoutWeight(1)
                  }
                  .width('100%')
                }
                if (job.label.length > 0) {
                  Row({ space: DsSpacing.SMALL }) {
                    Text('标签')
                      .fontSize(DsType.CAPTION_11.size)
                      .fontColor(this.palette().labelTertiary)
                      .width(40)
                    Text(job.label)
                      .fontSize(DsType.XSMALL_12.size)
                      .fontColor(this.palette().labelSecondary)
                      .layoutWeight(1)
                  }
                  .width('100%')
                }
                if (job.detail !== undefined && job.detail.length > 0) {
                  Row({ space: DsSpacing.SMALL }) {
                    Text('详情')
                      .fontSize(DsType.CAPTION_11.size)
                      .fontColor(this.palette().labelTertiary)
                      .width(40)
                    Text(job.detail)
                      .fontSize(DsType.XSMALL_12.size)
                      .fontColor(this.palette().labelSecondary)
                      .layoutWeight(1)
                  }
                  .width('100%')
                }
                Text(jobRowStatusText(job))
                  .fontSize(DsType.CAPTION_11.size)
                  .fontColor(this.palette().labelTertiary)
                  .width('100%')
              }
              .width('100%')
              .padding({
                left: DsSpacing.MEDIUM,
                right: DsSpacing.SMALL,
                top: DsSpacing.XSMALL,
                bottom: DsSpacing.XSMALL
              })
              .borderRadius(DsShape.ROW)
              .backgroundColor(this.palette().bgBase)
            }
          }
          .width('100%')
          // key 带上"每秒刻度"：live 任务的耗时才会走字（读 `jobsTick` 也让刻度成为本组件的真实依赖）
        }, (job: SessionJob) => `${job.id}:${this.jobsTick}`)
      }
    }
    .width('100%')
    .padding({
      left: DsSpacing.MEDIUM,
      right: DsSpacing.MEDIUM,
      top: DsSpacing.XSMALL
    })
  }
}
