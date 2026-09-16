/**
 * 会话正文的**头部**（P2-5：从 `ConversationPane` 抽出的第一刀）。
 *
 * ## 它拥有什么
 *
 * 1. **视图切换**（对话 / 轨迹）与轨迹工具栏（展开全部 / 收起全部 / 事件计数）；
 * 2. **后台任务条**（官方在会话头；`Jobs` 模型判定，live 任务每秒走字）；
 * 3. **时间总览**（轨迹视图的交互式总览，官方 `timeline.overviewAria`）；
 * 4. **会话内搜索条**（输入框 + 命中计数 + 上/下一条 + 关闭）。
 *
 * ## 为什么"头部"值得单独成组件
 *
 * 这四块的共同点是：**它们都在正文列表之外**，决定"正文要以什么形态呈现"，
 * 而不是正文本身。混在正文组件里时，正文的每一点改动都要绕过这 240 行 chrome；
 * 抽出去之后父组件只剩"列表 + 尾部"。
 *
 * ## 搜索与任务条的**状态为什么仍在父组件**
 *
 * · **搜索**：命中判定要扫整条过程流（`matchTrajectoryIndices`），命中的高亮也要画在
 *   列表项上 ⇒ 状态在父组件，这里只做"显示 + 转发"（输入框的每个字符都会回到父组件）。
 * · **任务条**：live 任务的耗时每秒走字，而"要不要起定时器"由模型 `jobTickerNeeded`
 *   判定、父组件持有定时器 ⇒ 刻度（`jobsTick`）由父组件当 prop 传进来，
 *   **它同时是本组件的真实依赖**（刻度变了才重绘）。
 *
 * 这条分工与 `MessageRow` 的两条边界同源：**跨行的状态留在父组件，行内/块内的留在这里**。
 */

import {
  Fs, JobDot, Radius, SemanticColor, Sp, Sz,
  jobCountLabel, jobDotState, jobDurationText, jobDurationTitle, jobElapsedMs,
  jobListA11y, jobListVisible, jobRowStatusText, liveJobCount, matchCounterText, orderedJobs,
  relativeTime, sessionContextLine
} from 'appstate';
import type { SessionJob, SessionStatsInput, TrajectoryItem } from 'appstate';
import { TimelineOverview } from './TimelineOverview';
import { TrajectoryInspector } from './TrajectoryInspector';

/** 会话头的呈现（视图切换 / 任务条 / 时间总览 / 搜索） */
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
  /** 当前模型名（父组件用 `modelSelectionLabel` 拼好；空 = 不显示） */
  @Prop modelLabel: string = '';

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
  /** 时间总览：聚焦某一格 / 提交（提交 = 滚到聚焦项）/ 拖动状态变化 */
  onFocusCell: (cellId: string) => void = () => {
  };
  onCommitTimeline: () => void = () => {
  };
  onDragChange: (dragging: boolean) => void = () => {
  };

  /**
   * 上下文行：工作区 · 模型 · 最近活动。
   *
   * 【为什么在视图里拼】三段事实都在本组件手边（两个 prop + 父组件拼好的模型名），
   * 而「每段拿不到就不出现」的规则在 `sessionContextLine`（纯模型、有 fixture）。
   * 【为什么要传 now】`relativeTime` 需要「现在」，由调用点给 ⇒ 这一行随时钟自然更新，
   * 不引入第二个定时器（任务条已经有一个每秒刻度）。
   */
  private contextLine(): string {
    const updated: string = this.sessionUpdatedAt > 0
      ? relativeTime(this.sessionUpdatedAt, Date.now())
      : '';
    return sessionContextLine(this.workspaceName, this.modelLabel, updated);
  }

  /** 状态点 → 语义色（模型给语义 `JobDot`，颜色是视图的事） */
  private jobDotColor(status: string): Resource {
    const dot: JobDot = jobDotState(status);
    if (dot === JobDot.ONGOING) {
      return SemanticColor.BRAND;
    }
    if (dot === JobDot.WARNING) {
      return SemanticColor.WARNING;
    }
    if (dot === JobDot.DONE) {
      return SemanticColor.CONFIRM;
    }
    return SemanticColor.ALERT;
  }

  build() {
    Column() {
      /*
       * 对话 / 轨迹 两个视图（E108，与官方 web 一致）。
       *
       * 【为什么分开】同一条会话流里有两种读者需求：
       *   - **对话**：只看问答（人说的话 + 模型的回答，思考折叠在回答上方）——日常使用；
       *   - **轨迹**：看全过程（工具调用、子代理、目标/任务、交付物、错误）——排查与复盘。
       * 官方 web 也是这两个视图；混在一起会让"想安静读答案"的人被工具卡刷屏，
       * 而"想查某次工具参数"的人又要在气泡之间翻找。
       */
      // 上下文行（P2-7，对齐官方 conversation.header 的 Workspace context / Model 两项）：
      // 一段都拿不到时整行不画——空行占位比没有更难读。
      if (this.contextLine().length > 0) {
        Text(this.contextLine())
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: Sp.M, right: Sp.M, top: Sp.XS })
      }

      /*
       * 【为什么这一行也要可换行】轨迹视图下右侧还有三个动作（展开全部 / 收起全部 / N 条事件），
       * 加上左侧两个视图 chip，手机宽度下**加起来超过屏宽**；而这一行里没有任何 `layoutWeight`、
       * 只靠一个 `Blank()` 撑开 ⇒ 超出的部分被**直接裁掉**（`docs/08` P0 §7 点名的那类缺陷：
       * 操作区被挤压时不得静默消失）。官方的行容器用 `flex-wrap: wrap` + `space-between`，
       * 这里照同一结构：放得下时右组靠右，放不下时整组换行，控件一个不少。
       */
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        Row({ space: Sp.S }) {
          this.viewChip('chat', $r('app.string.view_chat'))
          this.viewChip('trajectory', $r('app.string.view_trajectory'))
        }
        .margin({ bottom: Sp.XS })

        if (this.view === 'trajectory') {
          Row({ space: Sp.S }) {
            // E197：官方的"展开/收起所有"（`toolbar.expandTurns`/`collapseTurns`、`expandCalls`/`collapseCalls`）
            Text('展开全部')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.brand'))
              .onClick(() => {
                this.onExpandAll();
              })
            Text('收起全部')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.brand'))
              .onClick(() => {
                this.onCollapseAll();
              })
            /*
             * 触屏搜索入口（单栏才需要：非单栏搜索框本来就常驻）。
             * 图标名已在权威清单里核过（`magnifyingglass`），不是猜的。
             */
            if (this.layoutMode === 'single' && !this.searchOpen) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(Sz.TOUCH_MIN / 2)
                .fontColor([$r('sys.color.brand')])
                .onClick(() => {
                  this.onOpenSearch();
                })
            }
            Text(`${this.items.length} 条事件`)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .margin({ bottom: Sp.XS })
        }
      }
      .width('100%')
      .padding({ left: Sp.M, right: Sp.M, top: Sp.S })

      // 后台任务条（官方在会话头）：有任务才出现，位置在视图切换行下方
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
       * 但补了一个触屏入口（下面那颗放大镜）——所以手机上不再是死路。
       */
      if (this.searchOpen || this.layoutMode !== 'single') {
        this.searchBar()
      }
    }
    .width('100%')
  }

  @Builder
  viewChip(value: string, label: ResourceStr) {
    Text(label)
      .fontSize(Fs.SECONDARY)
      .fontColor(this.view === value ? Color.White : $r('sys.color.font_secondary'))
      .padding({ left: Sp.M, right: Sp.M, top: Sp.XS, bottom: Sp.XS })
      .borderRadius(Radius.L)
      .backgroundColor(this.view === value
        ? $r('sys.color.brand')
        : $r('sys.color.background_secondary'))
      .onClick(() => {
        this.onPickView(value);
      })
  }

  @Builder
  searchBar() {
    Row({ space: Sp.S }) {
      TextInput({ text: this.searchQuery, placeholder: '在本次会话中搜索…' })
        .layoutWeight(1)
        .constraintSize({ minHeight: Sz.TOUCH_MIN - 8 })
        .onChange((value: string) => {
          this.onQueryChange(value);
        })
        .accessibilityText('会话内搜索输入框')
      Text(matchCounterText(this.matchPos, this.hitCount))
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
      Text('↑')
        .fontSize(Fs.SECONDARY)
        .fontColor($r('sys.color.brand'))
        .padding(Sp.XS)
        .onClick(() => {
          this.onStep(-1);
        })
      Text('↓')
        .fontSize(Fs.SECONDARY)
        .fontColor($r('sys.color.brand'))
        .padding(Sp.XS)
        .onClick(() => {
          this.onStep(1);
        })
      Text('×')
        .fontSize(Fs.SECONDARY)
        .fontColor($r('sys.color.font_secondary'))
        .padding(Sp.XS)
        .onClick(() => {
          this.onCloseSearch();
        })
    }
    .width('100%')
    .padding({ left: Sp.M, right: Sp.M, top: Sp.S, bottom: Sp.S })
    .backgroundColor($r('sys.color.background_secondary'))
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

  @Builder
  jobsStrip() {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        // 「有 live 任务」才给状态点（官方 `liveCount > 0` 的条件渲染）
        if (liveJobCount(this.jobs) > 0) {
          SymbolGlyph($r('sys.symbol.circle'))
            .fontSize(Fs.CAPTION_XS)
            .fontColor([this.jobDotColor('running')])
        }
        Text(jobCountLabel(this.jobs))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .layoutWeight(1)
        SymbolGlyph(this.jobsOpen ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(Fs.CAPTION)
          .fontColor([$r('sys.color.font_tertiary')])
      }
      .width('100%')
      .height(Sz.TOUCH_MIN)   // 44vp 命中区（E214 的教训：只挂 onClick 的文字按不准）
      .borderRadius(Radius.S)
      .accessibilityText(jobListA11y(this.jobs))
      .onClick(() => {
        this.jobsOpen = !this.jobsOpen;
      })

      if (this.jobsOpen) {
        ForEach(orderedJobs(this.jobs), (job: SessionJob) => {
          Row({ space: Sp.S }) {
            SymbolGlyph($r('sys.symbol.circle'))
              .fontSize(Fs.CAPTION_XS)
              .fontColor([this.jobDotColor(job.status)])
            // 官方清单里 kind 与 label 是**两列**：kind 说"哪一类任务"，label 说"哪一个"
            Text(job.kind)
              .fontSize(Fs.CAPTION_XS)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
            Text(job.label.length > 0 ? job.label : job.kind)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(job.detail !== undefined && job.detail.length > 0
              ? job.detail
              : jobRowStatusText(job))
              .fontSize(Fs.CAPTION_XS)
              .fontColor($r('sys.color.font_tertiary'))
              .maxLines(1)
            Text(jobDurationText(jobElapsedMs(job, Date.now())))
              .fontSize(Fs.CAPTION_XS)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          .padding({ left: Sp.S, right: Sp.S, top: Sp.XS, bottom: Sp.XS })
          .borderRadius(Radius.S)
          .backgroundColor($r('sys.color.background_secondary'))
          .accessibilityText(jobDurationTitle(job, Date.now()))
          // key 带上"每秒刻度"：live 任务的耗时才会走字（读 `jobsTick` 也让刻度成为本组件的真实依赖）
        }, (job: SessionJob) => `${job.id}:${this.jobsTick}`)
      }
    }
    .width('100%')
    .padding({ left: Sp.M, right: Sp.M, top: Sp.XS })
  }
}
