/**
 * 会话面板（轨迹 + 输入区）—— D3 §3.2 / §3.3 / §3.6。
 *
 * 轨迹条目类型（D3 §3.2）：用户/助手消息、思考折叠、工具调用卡、子代理、交付物、
 * 目标、任务、错误。工具调用卡按 §3.3 的徽标与默认展开规则呈现。
 *
 * 数据来源：宿主注入（当前为桩数据源）。本组件不直接调用协议层，
 * 所有动作通过回调上报宿主，便于接入真实连接时只改宿主。
 */

import {
  CommandCandidate,
  formatBytes,
  formatClock,
  formatDuration,
  Fs,
  Lh,
  matchCounterText,
  matchTrajectoryIndices,
  ModelOption,
  ModelSelection,
  PendingAttachment,
  PendingItem,
  QueuedItem,
  previewOutput,
  Radius,
  ReferenceCandidate,
  Sp,
  Speaker,
  stepMatch,
  Sz,
  ToolState,
  toolStateIsProblem,
  toolStateLabel,
  TrajectoryItem,
  TrajectoryKind,
  SessionHub,
  chatVisibleItems,
  FEEDBACK_CATEGORIES,
  FeedbackRow,
  groupTurns,
  Border,
  defaultExpanded,
  hasProcessGroup,
  processSummary,
  HarmonyColor,
  HarmonyType,
  followTimerShouldRun,
  FollowSignal,
  nextFollowing,
  shouldJumpOnNewItems,
  HarmonyRadius,
  HarmonySpacing,
  contextMenuGestures,
  contextMenuHintLabel,
  hoverEnabled,
  MenuGesture,
  presentTool,
  presentDiff,
  ToolKind,
  toolSummaryOf
} from 'appstate';
/** 类型单独 import type（本仓约定：值与类型分开写） */
import type { ActionNotice, DiffPresentation, FeedbackCategory, InputModality, ToolPresentation, Turn } from 'appstate';
import type { NativeAction } from './NativePrimitives';
import { NativeActionBar, NativeCard, NativeChip } from './NativePrimitives';
import { Composer } from './Composer';
import { PendingPane } from './PendingPane';

@Component
export struct ConversationPane {
  @Prop @Watch('onSessionChanged') sessionId: string = '';
  @Prop items: TrajectoryItem[] = [];
  @Prop running: boolean = false;
  @Prop offline: boolean = false;
  @Prop queuedCount: number = 0;
  @Prop draft: string = '';
  @Prop attachments: PendingAttachment[] = [];
  /** 当前会话在 Host 侧的排队项 */
  @Prop queued: QueuedItem[] = [];
  @Prop models: ModelOption[] = [];
  @Prop selection: ModelSelection = { provider: '', modelId: '', effort: '' };
  @Prop references: ReferenceCandidate[] = [];
  @Prop commands: CommandCandidate[] = [];
  /** 能力缺失的一次性提示（透传给输入区） */
  @Prop notice: string = '';
  /**
   * 本轮待决的审批/提问（E115：直接弹在会话里，方便一次点击放行）。
   *
   * 【为什么放在输入区上方而不是顶部】它卡住的是"这一轮还能不能继续"，
   * 用户的注意力在对话末尾与输入框之间；摆在顶部会让人以为"跟我现在做的无关"。
   */
  @Prop pending: PendingItem[] = [];
  onDecidePending: (item: PendingItem, choiceId: string, reason: string) => void = () => {
  };
  onAnswerPending: (item: PendingItem, selected: string[], custom: string) => void = () => {
  };

  onDraftChange: (text: string) => void = () => {
  };
  onSend: () => void = () => {
  };
  onStop: () => void = () => {
  };
  onAddAttachment: () => void = () => {
  };
  /** 移除附件（参数是上传回执 id，见 `Composer` 的说明） */
  onRemoveAttachment: (receiptId: string) => void = () => {
  };
  onPickModel: () => void = () => {
  };
  /** 计划模式（官方 ui-plan 的输入区 chip）与权限模式（只读展示） */
  @Prop planActive: boolean = false;
  @Prop planPending: boolean = false;
  @Prop permissionLabel: string = '';

  onTogglePlan: () => void = () => {
  };
  /** `@` 引用查询词变化（转发给宿主去问 Host） */
  onReferenceQuery: (query: string) => void = () => {
  };
  /** 排队项：取回编辑 / 移除 / 插话（三者都转发给宿主的真实调用） */
  onPullQueued: (itemId: string, text: string) => void = () => {
  };
  onRemoveQueued: (itemId: string) => void = () => {
  };
  onSteerQueued: (itemId: string) => void = () => {
  };
  /** 打开详情栏（单栏/双栏下没有并排详情栏时使用） */
  onOpenDetail: () => void = () => {
  };

  @State expanded: string[] = [];

  /**
   * 消息操作条（§10）的反馈面板状态。
   *
   * 【为什么要有"面板"这一步】契约里 `messageFeedback/put` 除了 `rating` 还有可选的
   * `category` 与 `note`（D2b §6.7）。只发 rating 等于把官方那套"类别 → 可选说明 → 提交"
   * 砍成两个文字按钮——那正是 §10 明确不允许的形态。
   */
  /**
   * 上下文菜单（§10 的「更多」与 P3 输入语义）。
   *
   * 【为什么用"受控形式"而不是 `bindContextMenu(builder, ResponseType.X)`】
   * 后者一次只能绑一种手势，且其 builder **不带参数** ⇒ 无法表达"每条消息各自的菜单"。
   * 受控形式（`bindContextMenu(isShown, content, options)`）把显隐交给我们，
   * 于是"长按 ≡ 右键 → 同一个菜单"是**显式实现**的（手势集合由 `contextMenuGestures` 决定），
   * 而不是靠两套绑定碰巧长得一样。
   */
  @State menuForId: string = '';
  @State menuShown: boolean = false;
  /** 输入模态（宿主从设备事实派生后传入；视图不认识 deviceInfo） */
  @Prop hasPointer: boolean = false;
  @Prop hasKeyboard: boolean = false;
  /** 当前被指针悬停的消息 id（有指针设备时才有值） */
  @State hoveredId: string = '';

  @State fbFor: string = '';
  @State fbRating: string = '';
  @State fbCategory: string = '';
  @State fbNote: string = '';
  /** 面板内的结果/失败提示（写入成功后面板关闭，故这里只承载失败与"撤回不可用"两类） */
  @State fbNote2: string = '';

  /** 复制消息正文（剪贴板是平台能力，由宿主传入回调——视图层不直接依赖 platform） */
  onCopyMessage: (text: string) => void = () => {
  };
  /** 引用到输入框 / 重发（都由宿主执行：草稿与发送都在宿主手里） */
  onQuoteMessage: (item: TrajectoryItem) => void = () => {
  };
  onResendMessage: (item: TrajectoryItem) => void = () => {
  };

  /**
   * 毫秒时间戳 → **钟点**（E204，官方 `ui-trajectory` 的 `toolbar.actualTime`「实际时间」）。
   *
   * 【为什么不做一个开关】官方那三项里，"实际时长/等宽操作"控制的是**时间轴条宽**——
   * 我们没有时间轴，照搬就是点了没效果的开关（§13.3 的结论）；而"实际时间"提供的是
   * **信息**（这件事发生在几点），对列表同样有意义 ⇒ 直接**与时长并列显示**：
   * 少一份状态、少一个入口，信息一点不少。
   */
  private clockOf(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d: Date = new Date(ms);
    const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
    const mm: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
    return `${hh}:${mm}`;
  }

  /**
   * 展开/收起**全部**条目（E197，官方轨迹工具栏的 `expandTurns`/`collapseTurns` 与
   * `expandCalls`/`collapseCalls`）。
   *
   * 【为什么合并成一个"全部"而不是四颗按钮】官方把"轮次"和"调用"分成两组开关；
   * 我们的轨迹把消息、思考、工具调用、子代理、交付物都放在**同一条时间线**里，
   * 逐组区分反而不如"全部"直观——这是**形态差异**，不是能力缺失，所以如实做成两颗：
   * 需要更细的粒度时再按 `TrajectoryKind` 拆分即可（`expanded` 存的是条目 id）。
   */
  private expandAllItems(): void {
    const next: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      next.push(this.items[i].id);
    }
    this.expanded = next;
  }

  /** 收起全部（清空展开集合） */
  private collapseAllItems(): void {
    this.expanded = [];
  }
  /**
   * 会话内搜索状态（D3 §5.1 的 `Ctrl/Cmd + F`）。
   *
   * 【为什么状态放在本组件而不是宿主】搜索框就在轨迹上方，命中的滚动目标也是这条 List，
   * 放在持有 List/Scroller 的组件里最直接。宿主只负责**触发**（Ctrl+F 把 `searchOpen` 置真）。
   */
  @Prop searchOpen: boolean = false;
  /** 关闭搜索（`searchOpen` 是 `@Prop`，子组件不能可靠地写回，因此由宿主关闭） */
  onCloseSearch: () => void = () => {
  };
  /** 搜索关键词（本组件自己维护；宿主不需要知道用户搜了什么） */
  @State searchQuery: string = '';
  /** 当前选中的命中在**命中数组**里的位置（-1 = 未选中） */
  @State matchPos: number = -1;
  private scroller: Scroller = new Scroller();

  /**
   * 是否**跟随最新**（E113）。
   *
   * 【为什么需要它】官方 web 的行为是"贴底跟随"，而朴素做法（每条新消息都 `scrollEdge`）
   * 会在用户**正在往上翻历史**时把他拽回底部——那是最令人恼火的一类交互缺陷。
   * 规则三条：
   *   1. 默认跟随：进入会话、发消息、模型流式输出时都停在最新；
   *   2. 用户手动上翻 ⇒ **解除跟随**，新内容只追加不抢焦点；
   *   3. 用户自己拉回底部 ⇒ **恢复跟随**，此后新内容继续自动滚。
   * 判定用可见区间（`onScrollIndex` 的 `end` 是否覆盖最后一条），它对"手滑一下又停住"
   * 这种情况也稳：只要最后一条重新可见，就认为用户回到了底部。
   */
  @State stickToBottom: boolean = true;
  /** 渲染条数（宿主传入；@Watch 用于"有新条目就贴底"） */
  @Prop @Watch('onItemsChanged') itemCount: number = 0;
  private followTimer: number = -1;

  /** 可见区间变化：最后一条可见 ⇔ 用户在底部 ⇒ 恢复跟随；否则解除跟随 */
  private onVisibleRange(start: number, end: number): void {
    const last: number = this.rowCount() - 1;
    const atBottom: boolean = last < 0 || end >= last;
    // 几何只回答"在不在底部"；**是否跟随**由跟随模型按信号决定（§8 的独立管理）
    this.stickToBottom = nextFollowing(this.stickToBottom,
      atBottom ? FollowSignal.AT_BOTTOM : FollowSignal.SCROLLED_AWAY);
  }

  /**
   * 会话切换（§8 缺的那条意图信号）。
   *
   * 【修的是什么】此前"在会话 A 上翻过历史"会让跟随保持 false，切到会话 B 时
   * **新会话不在底部**——用户看到的是 B 的中间某处。切换会话的意图显然是"看最新"。
   */
  private onSessionChanged(): void {
    this.stickToBottom = nextFollowing(this.stickToBottom, FollowSignal.SESSION_CHANGED);
    this.scrollToLatest();
  }

  private onItemsChanged(): void {
    if (shouldJumpOnNewItems(this.stickToBottom)) {
      this.scrollToLatest();
    }
  }

  /** 贴到底部；失败不该让页面崩（列表未就绪/尺寸为 0 时会抛） */
  private scrollToLatest(): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (err) {
      // 忽略：下一次内容变化会再试
    }
  }

  /**
   * 运行中定时贴底：流式输出时**条目数不变而正文在长**，只靠 `itemCount` 会停在半截。
   * 只在自己跟随（`stickToBottom`）时定时；用户上翻时立刻停。
   */
  private syncFollowTimer(): void {
    const shouldRun: boolean = followTimerShouldRun(this.stickToBottom, this.running);
    if (shouldRun && this.followTimer < 0) {
      this.followTimer = setInterval(() => {
        this.scrollToLatest();
      }, 900);
    } else if (!shouldRun && this.followTimer >= 0) {
      clearInterval(this.followTimer);
      this.followTimer = -1;
    }
  }

  aboutToAppear(): void {
    // 进入会话先贴到底部（用户要看到的是最新一条，而不是最老一条）
    this.scrollToLatest();
  }

  aboutToDisappear(): void {
    if (this.followTimer >= 0) {
      clearInterval(this.followTimer);
      this.followTimer = -1;
    }
  }

  /** 当前命中集合（每次渲染按关键词算一次；轨迹长度是几十到几百条，代价可忽略） */
  private hits(): number[] {
    return matchTrajectoryIndices(this.items, this.searchQuery);
  }

  /** 某一条是否在命中集合里（`isHit` 只用于左侧色条） */
  private isHit(item: TrajectoryItem): boolean {
    const list: number[] = this.hits();
    for (let i = 0; i < list.length; i++) {
      if (this.items[list[i]] !== undefined && this.items[list[i]].id === item.id) {
        return true;
      }
    }
    return false;
  }

  /** 跳到第 `pos` 个命中（越界时不动作） */
  private jumpTo(pos: number): void {
    const list: number[] = this.hits();
    if (pos < 0 || pos >= list.length) {
      return;
    }
    this.matchPos = pos;
    // `scrollToIndex` 失败（索引越界/列表未就绪）不该让整页崩：搜索只是导航辅助。
    try {
      this.scroller.scrollToIndex(list[pos], true, ScrollAlign.CENTER);
    } catch (err) {
      // 忽略：下一次按键会再试一次
    }
  }

  /** 关键词变化：重算命中并把光标移到第一个命中上 */
  private onQueryChange(value: string): void {
    this.searchQuery = value;
    const list: number[] = this.hits();
    this.matchPos = list.length > 0 ? 0 : -1;
    if (list.length > 0) {
      this.jumpTo(0);
    }
  }

  /** 上一个 / 下一个命中（环绕，见 `stepMatch` 的语义说明） */
  private step(delta: number): void {
    const list: number[] = this.hits();
    this.jumpTo(stepMatch(this.matchPos, list.length, delta));
  }

  /**
   * 视图模式（E108）：`chat` = 只看问答；`trajectory` = 全过程（工具/子代理/目标…）。
   *
   * 默认落在 `chat`：日常是"读答案"，把工具卡默认糊在脸上会淹没对话。
   */
  @State view: string = 'chat';

  /**
   * 当前视图下要渲染的条目。
   *
   * `chat` 只留**用户可见的对话**：消息与错误（错误必须留在这里——它是"为什么没有回答"的唯一说明）。
   * `trajectory` 保留全部条目：工具、子代理、目标/任务、交付物都在这里可查。
   */
  /**
   * 对话视图的回合列表（§8）。
   *
   * 【为什么对话视图要以**回合**为单位渲染】§8 要求"已完成的回合可折叠、进行中的回合展开"——
   * 折叠的单位是回合。此前对话视图根本**不显示**过程条目（工具/思考被整段过滤掉），
   * 与 D3 §3.2「思考默认折叠为一行、可展开」也不符：用户看不到"模型做过什么"。
   * 现在改成"每个回合 = 用户消息 + 折叠的过程分组 + 回答"，与官方语义一致。
   */
  private chatTurns(): Turn[] {
    return groupTurns(this.items, this.running);
  }

  /**
   * 列表的行数（sticky-follow 的判据）。
   *
   * 【为什么单独一个函数】`onVisibleRange` 拿可见区间的 **end** 和"最后一行"比较来决定是否贴底。
   * 两个视图的行单位不同（轨迹=条目，对话=回合），若两处各写一遍必然错位——
   * 错位的症状是"明明在底部却不跟随"或"上翻了还被拽回去"，都属于难查的体感缺陷。
   */
  private rowCount(): number {
    return this.view === 'trajectory' ? this.items.length : this.chatTurns().length;
  }

  private visibleItems(): TrajectoryItem[] {
    if (this.view === 'trajectory') {
      return this.items;
    }
    /*
     * 对话视图的可见集合由**回合模型**回答（§8），不再由视图层自己写过滤规则。
     *
     * 【为什么必须搬走】此前这段逻辑里藏着两条判断："什么算对话内容"（只留消息与错误）
     * 与"系统消息不显示"。换个视图（或换个入口）就得再答一次，而两处必然漂移。
     * 现在它们与回合分组**同处一地**（`appstate/model/Turns.ets`），并有 15 条断言覆盖——
     * 其中"错误必须留在对话视图"是 E134 的教训（它是"为什么没有回答"的唯一说明）。
     */
    return chatVisibleItems(groupTurns(this.items, this.running));
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
        this.view = value;
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
      Text(matchCounterText(this.matchPos, this.hits().length))
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
      Text('↑')
        .fontSize(Fs.SECONDARY)
        .fontColor($r('sys.color.brand'))
        .padding(Sp.XS)
        .onClick(() => {
          this.step(-1);
        })
      Text('↓')
        .fontSize(Fs.SECONDARY)
        .fontColor($r('sys.color.brand'))
        .padding(Sp.XS)
        .onClick(() => {
          this.step(1);
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
      Row({ space: Sp.S }) {
        this.viewChip('chat', $r('app.string.view_chat'))
        this.viewChip('trajectory', $r('app.string.view_trajectory'))
        Blank()
        if (this.view === 'trajectory') {
        // E197：官方的"展开/收起所有"（`toolbar.expandTurns`/`collapseTurns`、`expandCalls`/`collapseCalls`）
        Text('展开全部')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.expandAllItems();
          })
        Text('收起全部')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.collapseAllItems();
          })
          Text(`${this.items.length} 条事件`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')
      .padding({ left: Sp.M, right: Sp.M, top: Sp.S })

      if (this.searchOpen) {
        this.searchBar()
      }

      List({ space: Sp.M, scroller: this.scroller }) {
        if (this.view === 'trajectory') {
          // 轨迹视图 = 全量台账：条目级扁平列表（工具、子代理、目标/任务、交付物都在这里可查）
          ForEach(this.visibleItems(), (item: TrajectoryItem) => {
            ListItem() {
              this.trajectoryItem(item)
            }
            // 命中项加一条左侧色条：**不改变正文**（正文里做高亮要拆 span，
            // 而拆 span 会让 Markdown/代码块的渲染路径多一条分支，风险大于收益）。
            .border({ width: { left: this.isHit(item) ? 3 : 0 },
              color: $r('sys.color.brand') })
          }, (item: TrajectoryItem) => item.id)
        } else {
          // 对话视图 = 按**回合**渲染（§8）：用户消息 + 过程分组（折叠）+ 回答
          ForEach(this.chatTurns(), (turn: Turn) => {
            ListItem() {
              this.turnBlock(turn)
            }
            .border({ width: { left: this.turnIsHit(turn) ? 3 : 0 },
              color: $r('sys.color.brand') })
          }, (turn: Turn) => turn.id)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: Sp.M, right: Sp.M, top: Sp.M })
      // E113：可见区间决定"是否跟随最新"；贴底跟随由 `stickToBottom` + 定时器实现
      .onScrollIndex((start: number, end: number) => {
        this.onVisibleRange(start, end);
        this.syncFollowTimer();
      })
      .scrollBar(BarState.Auto)

      Divider().color($r('sys.color.comp_divider'))

      /*
       * 【审批弹在会话里（E115）】以前审批/提问只在「待决」页签里，用户得先切页签再点，
       * 而它恰恰是"卡住当前这一轮"的东西——官方 web 就是把它直接摆在对话流里。
       * 这里放在**输入区正上方**：眼睛在对话上，手指就在按钮附近，一次点击即可放行。
       * 只在这一轮真的有待决时出现，平时不占一行。
       */
      if (this.pending.length > 0) {
        Column({ space: Sp.XS }) {
          Row({ space: Sp.S }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(14)
              .fontColor([$r('sys.color.warning')])
            Text(`待你决定 · ${this.pending.length}`)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.warning'))
              .layoutWeight(1)
          }
          .width('100%')

          PendingPane({
            items: this.pending,
            onDecide: (item: PendingItem, choiceId: string, reason: string) => {
              this.onDecidePending(item, choiceId, reason);
            },
            onAnswer: (item: PendingItem, selected: string[], custom: string) => {
              this.onAnswerPending(item, selected, custom);
            }
          })
        }
        .width('100%')
        .constraintSize({ maxHeight: 300 })
        .padding({ left: Sp.M, right: Sp.M, bottom: Sp.S })
      }

      Composer({
        draft: this.draft,
        running: this.running,
        offline: this.offline,
        queuedCount: this.queuedCount,
        attachments: this.attachments,
        queued: this.queued,
        models: this.models,
        selection: this.selection,
        references: this.references,
        commands: this.commands,
        notice: this.notice,
        onDraftChange: this.onDraftChange,
        onSend: () => {
          // 用户发消息 = 他在等回答 ⇒ 恢复跟随（否则上翻过历史时，回答会出现在看不到的地方）
          this.stickToBottom = nextFollowing(this.stickToBottom, FollowSignal.USER_SENT);
          this.scrollToLatest();
          this.onSend();
        },
        onStop: this.onStop,
        onAddAttachment: this.onAddAttachment,
        onRemoveAttachment: this.onRemoveAttachment,
        planActive: this.planActive,
        planPending: this.planPending,
        permissionLabel: this.permissionLabel,
        onPickModel: this.onPickModel,
        onTogglePlan: this.onTogglePlan,
        onReferenceQuery: this.onReferenceQuery,
        onPullQueued: this.onPullQueued,
        onRemoveQueued: this.onRemoveQueued,
        onSteerQueued: this.onSteerQueued
      })
    }
    .width('100%')
    .height('100%')
  }

  // ───────────────────── 轨迹条目 ─────────────────────

  /**
   * 一个回合（§8 的渲染单位）：用户消息 → 过程分组 → 回答 → 通知。
   *
   * 顺序即阅读顺序，且**不做"智能排序"**：官方也是这个次序。
   */
  @Builder
  turnBlock(turn: Turn) {
    Column({ space: Sp.M }) {
      if (turn.user !== undefined) {
        this.trajectoryItem(turn.user)
      }
      if (hasProcessGroup(turn)) {
        this.processGroup(turn)
      }
      // ArkTS 规定：`@Builder` 内只能写 UI 语法，循环必须用 `ForEach`
      ForEach(turn.answers, (it: TrajectoryItem) => {
        this.trajectoryItem(it)
      }, (it: TrajectoryItem) => `ans-${it.id}`)
      ForEach(turn.notices, (it: TrajectoryItem) => {
        this.trajectoryItem(it)
      }, (it: TrajectoryItem) => `note-${it.id}`)
    }
    .width('100%')
  }

  /**
   * 过程分组（思考 / 工具 / 子代理 / 进度 / 交付物）。
   *
   * 折叠默认态由**模型**决定（`defaultExpanded`：进行中展开、已完成折叠），
   * 用户点开才覆盖——而不是"记着用户上次点过什么"当作初值。
   */
  @Builder
  processGroup(turn: Turn) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.XS }) {
        NativeChip({
          label: `${this.processExpanded(turn) ? '▾' : '▸'} ${processSummary(turn)}`,
          active: this.processExpanded(turn),
          a11y: `${processSummary(turn)}，${this.processExpanded(turn) ? '点击收起' : '点击展开'}`,
          onTap: () => {
            this.toggle(turn.id);
          }
        })
        if (turn.running) {
          Text('进行中')
            .fontSize(HarmonyType.LABEL.size)
            .fontColor(HarmonyColor.BRAND)
        }
        Blank()
      }
      .width('100%')

      if (this.processExpanded(turn)) {
        ForEach(turn.process, (it: TrajectoryItem) => {
          this.trajectoryItem(it)
        }, (it: TrajectoryItem) => `proc-${it.id}`)
      }
    }
    .width('100%')
  }

  /** 过程分组是否展开（模型给默认态，用户点击覆盖） */
  private processExpanded(turn: Turn): boolean {
    return defaultExpanded(turn, this.isExpanded(turn.id));
  }

  /** 该回合内是否有搜索命中（用于对话视图的命中色条） */
  private turnIsHit(turn: Turn): boolean {
    if (turn.user !== undefined && this.isHit(turn.user)) {
      return true;
    }
    for (let i = 0; i < turn.answers.length; i++) {
      if (this.isHit(turn.answers[i])) {
        return true;
      }
    }
    for (let i = 0; i < turn.process.length; i++) {
      if (this.isHit(turn.process[i])) {
        return true;
      }
    }
    return false;
  }

  @Builder
  trajectoryItem(item: TrajectoryItem) {
    if (item.kind === TrajectoryKind.MESSAGE) {
      this.messageItem(item)
    } else if (item.kind === TrajectoryKind.REASONING) {
      this.reasoningItem(item)
    } else if (item.kind === TrajectoryKind.TOOL) {
      this.toolItem(item)
    } else if (item.kind === TrajectoryKind.SUBAGENT) {
      this.subagentItem(item)
    } else if (item.kind === TrajectoryKind.DELIVERABLE) {
      this.deliverableItem(item)
    } else if (item.kind === TrajectoryKind.GOAL || item.kind === TrajectoryKind.JOB) {
      this.goalItem(item)
    } else if (item.kind === TrajectoryKind.ERROR) {
      this.errorItem(item)
    }
  }

  @Builder
  messageItem(item: TrajectoryItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        Text(item.speaker === Speaker.USER ? '我'
          : (item.speaker === Speaker.SYSTEM ? '系统' : '助手'))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
        Text(formatClock(item.at))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
        if (item.elapsedMs > 0) {
          // E204：钟点 + 时长并列（官方"实际时间"的信息，不额外做开关）
          Text(this.clockOf(item.at).length > 0
            ? `${this.clockOf(item.at)} · ${formatDuration(item.elapsedMs)}`
            : formatDuration(item.elapsedMs))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
        Blank()
        if (item.model.length > 0) {
          Text(item.model)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')

      if (item.speaker === Speaker.ASSISTANT) {
        this.messageActions(item)
      }

      /*
       * 【思考单独成块（E107）】助手消息常把"思考"与"正文"作为两个内容块一起发来。
       * 这里照做：思考块在上、默认收起、点击展开；正文保持主字号。
       */
      if (item.reasoning.length > 0) {
        Column({ space: Sp.XS }) {
          Row({ space: Sp.S }) {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(14)
              .fontColor([$r('sys.color.font_tertiary')])
            Text(`思考过程 · ${item.reasoning.length} 字`)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .layoutWeight(1)
            Text(this.isExpanded(`${item.id}:r`) ? '收起' : '展开')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.brand'))
          }
          .width('100%')

          if (this.isExpanded(`${item.id}:r`)) {
            Text(item.reasoning)
              .fontSize(Fs.SECONDARY)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .textAlign(TextAlign.Start)
              .copyOption(CopyOptions.LocalDevice)
          }
        }
        .width('100%')
        .padding(Sp.S)
        .borderRadius(Radius.S)
        .borderWidth(Border.HAIRLINE)
        .borderColor($r('sys.color.comp_divider'))
        .onClick(() => {
          this.toggle(`${item.id}:r`);
        })
      }

      Text(item.body + (item.streaming ? ' ▌' : ''))
        .fontSize(Fs.BODY)
        .lineHeight(Fs.BODY * Lh.BODY)
        .width('100%')
        .textAlign(TextAlign.Start)
        .copyOption(CopyOptions.LocalDevice)
        .accessibilityText(this.speakableText(item))

    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor(this.isHovered(item)
      ? HarmonyColor.SURFACE_TERTIARY
      : (item.speaker === Speaker.USER
        ? HarmonyColor.SURFACE_RAISED
        : HarmonyColor.SURFACE))
    // 悬停反馈：只有指针设备才有"悬停"这个概念（策略模型回答，视图不自己判断）
    .onHover((isHover: boolean) => {
      if (!hoverEnabled(this.inputModality())) {
        return;
      }
      this.hoveredId = isHover ? item.id : '';
    })
    .accessibilityText(`${item.speaker === Speaker.USER ? '我' : '助手'}的消息，${contextMenuHintLabel(this.inputModality())}打开操作菜单`)
    // 触控：长按；指针：右键。**两者唤起同一个菜单**（§P3「同一套交互语义」）——
    // 手势集合由输入策略模型决定（`contextMenuGestures`），此处只做映射。
    .gesture(LongPressGesture().onAction(() => {
      this.openMessageMenu(item);
    }))
    .onMouse((e: MouseEvent) => {
      if (this.rightClickMenuEnabled() && e.button === MouseButton.Right) {
        this.openMessageMenu(item);
      }
    })
    .bindContextMenu(this.menuShown, this.messageMenu(), {
      placement: Placement.BottomLeft,
      // 原生关闭（点空白/返回）时要复位，否则菜单再也打不开（与 Sheet 同一个坑）
      onDisappear: () => {
        this.menuShown = false;
      }
    })
  }

  @Builder
  reasoningItem(item: TrajectoryItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(14)
          .fontColor([$r('sys.color.font_tertiary')])
        Text(item.streaming ? '思考中…'
          : (item.elapsedMs > 0 ? `已思考 ${formatDuration(item.elapsedMs)}` : '思考过程'))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .layoutWeight(1)
        Text(this.isExpanded(item.id) ? '收起' : '展开')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
      }
      .width('100%')

      if (this.isExpanded(item.id)) {
        Text(item.body)
          .fontSize(Fs.SECONDARY)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .padding(Sp.S)
    .borderRadius(Radius.S)
    .borderWidth(Border.HAIRLINE)
    .borderColor($r('sys.color.comp_divider'))
    .accessibilityText('思考过程，点击展开或收起')
    .onClick(() => {
      this.toggle(item.id);
    })
  }

  /** 工具调用卡片（D3 §3.3） */
  /**
   * 一条消息的**动作清单**（操作条与上下文菜单**共用这一份**）。
   *
   * 【为什么必须是同一份】§10 要的是"统一消息操作"：同一条消息在行内操作条与
   * 长按菜单里必须是同样几项、同样顺序。写成两处必然漂移——一处加了"撤回"，另一处没有，
   * 而用户会在两个入口得到不同答案。
   */
  private messageActionsOf(item: TrajectoryItem): NativeAction[] {
    const out: NativeAction[] = [];
    out.push({ id: 'copy', label: '复制', a11y: '复制这条消息的正文' });
    out.push({
      id: 'like',
      label: '有帮助',
      active: this.myRating(item.id) === 'positive',
      a11y: '评价为有帮助，可选择原因'
    });
    out.push({
      id: 'dislike',
      label: '没帮助',
      active: this.myRating(item.id) === 'negative',
      a11y: '评价为没帮助，可选择原因'
    });
    out.push({ id: 'quote', label: '引用', a11y: '把这条消息引用到输入框' });
    if (item.speaker === Speaker.USER) {
      // 【为什么只给用户消息】"重发"对用户消息是**把同一句再发一次**（有真实协议面：
      // `session/prompt`）；对助手消息则是"重跑那一轮"，本仓没有对应端点 ⇒ 不给，避免假入口。
      out.push({ id: 'resend', label: '重发', a11y: '重新发送这条消息' });
    }
    // 已评才给"撤回"：没评就没有可撤的（按钮不该假装有事可做）
    if (this.myRating(item.id).length > 0) {
      out.push({ id: 'withdraw', label: '撤回评价', a11y: '撤回这条消息的反馈' });
    }
    return out;
  }

  /** 动作的统一处理（两个入口都走这里） */
  private onMessageAction(item: TrajectoryItem, id: string): void {
    if (id === 'copy') {
      this.onCopyMessage(item.body);
    } else if (id === 'like') {
      this.openFeedback(item, 'positive');
    } else if (id === 'dislike') {
      this.openFeedback(item, 'negative');
    } else if (id === 'quote') {
      this.onQuoteMessage(item);
    } else if (id === 'resend') {
      this.onResendMessage(item);
    } else if (id === 'withdraw') {
      SessionHub.shared().clearFeedback(item.id).then((n: ActionNotice) => {
        this.fbNote2 = this.feedbackNoticeText(n);
      });
    }
  }

  /** 打开上下文菜单（长按/右键都走这里；手势集合来自输入策略） */
  /** 输入模态快照（策略模型的输入；本文件只做映射，不做判断） */
  private inputModality(): InputModality {
    return { hasKeyboard: this.hasKeyboard, hasPointer: this.hasPointer };
  }

  /** 该消息是否处于悬停态（只有指针设备才可能有） */
  private isHovered(item: TrajectoryItem): boolean {
    return hoverEnabled(this.inputModality()) && this.hoveredId === item.id;
  }

  /** 是否支持右键唤起菜单（手势集合来自策略模型，不在视图里散落判断） */
  private rightClickMenuEnabled(): boolean {
    return contextMenuGestures(this.inputModality()).indexOf(MenuGesture.RIGHT_CLICK) >= 0;
  }

  private openMessageMenu(item: TrajectoryItem): void {
    this.menuForId = item.id;
    this.menuShown = true;
  }

  private menuItem(): TrajectoryItem | undefined {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === this.menuForId) {
        return this.items[i];
      }
    }
    return undefined;
  }

  /** 上下文菜单内容：与行内操作条同一份动作清单 */
  @Builder
  messageMenu() {
    Column({ space: Sp.XS }) {
      ForEach(this.messageActionsOf2(), (a: NativeAction) => {
        Text(a.active === true ? `✓ ${a.label}` : a.label)
          .fontSize(HarmonyType.CAPTION.size)
          .fontColor(a.active === true ? HarmonyColor.BRAND : HarmonyColor.TEXT_PRIMARY)
          .width('100%')
          .padding(HarmonySpacing.CONTROL_INNER)
          .borderRadius(HarmonyRadius.CONTROL)
          .onClick(() => {
            const it: TrajectoryItem | undefined = this.menuItem();
            this.menuShown = false;
            if (it !== undefined) {
              this.onMessageAction(it, a.id);
            }
          })
      }, (a: NativeAction) => a.id)
    }
    .width(200)
    .padding(HarmonySpacing.CONTROL_INNER)
  }

  /** 菜单用当前归属消息的动作清单（找不到就空——菜单不显示空气泡） */
  private messageActionsOf2(): NativeAction[] {
    const it: TrajectoryItem | undefined = this.menuItem();
    return it === undefined ? [] : this.messageActionsOf(it);
  }

  /**
   * 消息操作条（计划 §10：Copy / Retry / Edit / Like / Dislike / More 统一在一处）。
   *
   * 【本仓已接的三类】复制（剪贴板）、好评/差评（`messageFeedback/put`，含类别与说明）、
   * 撤回（`messageFeedback/delete`，用读到的 `version` 做 CAS）。
   * **Retry / Edit 尚未接**：它们需要"重跑某一轮/改完再发"的协议面，本仓没有对应端点——
   * 与其放两个点了没反应的按钮（本项目明令禁止的假入口），不如让缺口显式留在台账里。
   */
  @Builder
  messageActions(item: TrajectoryItem) {
    Column({ space: Sp.XS }) {
      NativeActionBar({
        actions: this.messageActionsOf(item),
        onAction: (id: string) => {
          this.onMessageAction(item, id);
        }
      })

      .width('100%')

      if (this.fbFor === item.id) {
        this.feedbackPanel(item)
      }
      if (this.fbNote2.length > 0 && this.fbFor === item.id) {
        Text(this.fbNote2)
          .fontSize(Fs.CAPTION_XS)
          .fontColor($r('sys.color.alert'))
          .width('100%')
      }
    }
    .width('100%')
  }

  /**
   * 反馈面板：类别 → 可选说明 → 提交（契约 D2b §6.7 的 `category` / `note`）。
   *
   * 类别取值就是契约给出的那 7 个（不自己发明），未选即"未分类"——契约里 `category` 可选，
   * 所以**不强迫分类**，这与官方"可选说明"的语义一致。
   */
  @Builder
  feedbackPanel(item: TrajectoryItem) {
    Column({ space: Sp.XS }) {
      Text('为什么？可留空')
        .fontSize(Fs.CAPTION_XS)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(FEEDBACK_CATEGORIES, (c: FeedbackCategory) => {
          Row() {
            NativeChip({
              label: c.label,
              active: this.fbCategory === c.id,
              a11y: `评价原因：${c.label}`,
              onTap: () => {
                // 再点一次取消选择 ⇒ 回到"未分类"（契约里 category 可选，不强迫分类）
                this.fbCategory = this.fbCategory === c.id ? '' : c.id;
              }
            })
          }
          .margin({ right: Sp.XS, bottom: Sp.XS })
        }, (c: FeedbackCategory) => c.id)
      }
      .width('100%')

      TextInput({ text: this.fbNote, placeholder: '补充说明（可选）' })
        .fontSize(Fs.CAPTION)
        .height(Sz.TOUCH_MIN)
        .onChange((v: string) => {
          this.fbNote = v;
        })

      Row({ space: Sp.L }) {
        Text('提交')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.submitFeedback(item);
          })
        Text('取消')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .onClick(() => {
            this.fbFor = '';
            this.fbNote2 = '';
          })
        Blank()
      }
      .width('100%')
    }
    .width('100%')
    .padding(Sp.S)
    .borderRadius(Radius.S)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  /** 打开反馈面板：带上该条当前的类别/说明，便于"改主意"而不是从零填 */
  private openFeedback(item: TrajectoryItem, rating: string): void {
    const row: FeedbackRow | undefined = SessionHub.shared().feedbackOf(item.id);
    this.fbFor = item.id;
    this.fbRating = rating;
    this.fbCategory = row === undefined ? '' : row.category;
    this.fbNote = row === undefined ? '' : row.note;
    this.fbNote2 = '';
  }

  private submitFeedback(item: TrajectoryItem): void {
    SessionHub.shared().putFeedback(item.id, this.fbRating, this.fbNote, this.fbCategory)
      .then((n: ActionNotice) => {
        this.fbNote2 = this.feedbackNoticeText(n);
        if (n.code === 'feedback.saved') {
          this.fbFor = '';
        }
      });
  }

  /** 该条消息**宿主记录的**评价（不是"我以为点了什么"） */
  private myRating(messageId: string): string {
    const row: FeedbackRow | undefined = SessionHub.shared().feedbackOf(messageId);
    return row === undefined ? '' : row.rating;
  }

  /**
   * 反馈回执 → 一句话。
   *
   * 【为什么不走 Index 的 noticeText】那是全局回执表，键来自各功能；反馈这几条要贴着面板显示，
   * 且**失败原因必须原样透出**（`friendlyFailure` 已把宿主错误码翻成人话）。
   */
  private feedbackNoticeText(n: ActionNotice): string {
    if (n.code === 'feedback.saved') {
      return '';
    }
    if (n.code === 'feedback.withdrawn') {
      return '';
    }
    if (n.code === 'feedback.failed') {
      return '评价未保存：' + n.params.reason;
    }
    if (n.code === 'feedback.no-version') {
      return '无法撤回：没读到该评价的版本（不猜版本号去删）。';
    }
    if (n.code === 'offline') {
      return '未连接：评价需要连上 Host 才能保存。';
    }
    if (n.code === 'feedback.needs-session') {
      return '先打开一个会话。';
    }
    return n.code;
  }

  @Builder
  toolItem(item: TrajectoryItem) {
    // 卡片本体走 P1.5 的原语（NativeCard）；**工具类别**由 `ToolPresenter` 判定
    // （纯模型 + 17 条断言）：图标、语气、展开默认态、无障碍文案都不再由视图各自猜。
    NativeCard({
      iconSymbol: this.toolIcon(presentTool(item, toolStateLabel(item.toolState)).kind),
      title: item.toolName,
      badge: this.toolBadge(item),
      tone: presentTool(item, toolStateLabel(item.toolState)).tone,
      meta: item.elapsedMs > 0
        ? (this.clockOf(item.at).length > 0
          ? `${this.clockOf(item.at)} · ${formatDuration(item.elapsedMs)}`
          : formatDuration(item.elapsedMs))
        : '',
      // 参数摘要**按类别提炼**（§11 的 path summary）：终端出命令、读取出路径、搜索出模式+范围；
      // 提炼不到再退回清理后的原文——不再把整段 JSON 糊在卡片第一行。
      summary: toolSummaryOf(presentTool(item, toolStateLabel(item.toolState)).kind, item.toolArgs),
      // 编辑类工具优先显示**改动对照**（有对照时不再显示工具的输出确认）：
      // 用户要看的是"改了什么"，而不是"改成功了"这句话。
      diffLines: this.diffTextLines(item),
      diffKinds: this.diffKindLines(item),
      bodyText: this.diffTextLines(item).length > 0
        ? ''
        : ((this.isExpanded(item.id)
          || presentTool(item, toolStateLabel(item.toolState)).defaultExpanded)
          ? previewOutput(item.toolOutput).shown
          : ''),
      bodyTruncatedHint: this.diffTextLines(item).length > 0
        ? (this.diffOf(item) !== null && this.diffOf(item)!.truncated
          ? '▸ 对照较长，已按上限截断' : '')
        : (previewOutput(item.toolOutput).truncated
          ? `▸ 查看完整输出（共 ${previewOutput(item.toolOutput).totalLength} 字符）`
          : ''),
      collapsedHint: this.diffOf(item) !== null
        ? `▸ 查看改动 +${this.diffOf(item)!.added} −${this.diffOf(item)!.removed}`
        : (item.toolOutput.length > 0 ? '▸ 查看结果' : ''),
      expanded: this.isExpanded(item.id)
        || presentTool(item, toolStateLabel(item.toolState)).defaultExpanded,
      a11y: presentTool(item, toolStateLabel(item.toolState)).a11y,
      onToggle: () => {
        this.toggle(item.id);
      }
    })
  }

  /**
   * 取这次工具调用的改动对照（没有则 null）。
   *
   * 【失败态刻意不出对照卡】官方渲染器对 `isError` 的块直接返回 null——
   * 因为失败时参数只是"意图"，真正的结果在输出里；此时把意图画成对照会误导
   * （看起来"改了"，其实没改成）。我们照此：失败/被拒一律走原输出视图。
   */
  private diffOf(item: TrajectoryItem): DiffPresentation | null {
    if (item.toolState === ToolState.FAILED || item.toolState === ToolState.REJECTED) {
      return null;
    }
    if (item.toolState !== ToolState.SUCCESS && item.toolState !== ToolState.RUNNING) {
      return null;
    }
    return presentDiff(item.toolName, item.toolArgs);
  }

  /** 对照的行文本（带 +/-/空格前缀——这是 diff 的通用读法） */
  private diffTextLines(item: TrajectoryItem): string[] {
    const p: DiffPresentation | null = this.diffOf(item);
    const out: string[] = [];
    if (p === null) {
      return out;
    }
    for (let i = 0; i < p.lines.length; i++) {
      const kind: string = p.lines[i].kind;
      if (kind === 'added') {
        out.push('+ ' + p.lines[i].text);
      } else if (kind === 'removed') {
        out.push('- ' + p.lines[i].text);
      } else if (kind === 'skipped') {
        out.push(`  ⋯ 省略 ${p.lines[i].skipped} 行未改动`);
      } else {
        out.push('  ' + p.lines[i].text);
      }
    }
    return out;
  }

  /** 对照每行的性质（与原语里的取色按下标对应） */
  private diffKindLines(item: TrajectoryItem): string[] {
    const p: DiffPresentation | null = this.diffOf(item);
    const out: string[] = [];
    if (p === null) {
      return out;
    }
    for (let i = 0; i < p.lines.length; i++) {
      out.push(p.lines[i].kind);
    }
    return out;
  }

  /** 徽标：非通用类别时带上类别名（"读取 · 成功"比单说"成功"有用） */
  private toolBadge(item: TrajectoryItem): string {
    const p: ToolPresentation = presentTool(item, toolStateLabel(item.toolState));
    const state: string = toolStateLabel(item.toolState);
    return p.kind === ToolKind.GENERIC ? state : `${p.kindLabel} · ${state}`;
  }

  /**
   * 类别 → 系统符号。
   *
   * 【符号名不是猜的】每个名字都用编译器验过（不存在会 `Unknown resource name`）——
   * 例如 `terminal`/`globe`/`photo`/`pencil` 在本 SDK **都不存在**，实测后改用 `code`/`link`/`picture`/`pencil_line`。
   *
   * 【为什么图标映射留在视图层】`$r(...)` 是 ArkUI 资源引用，模型层（appstate）刻意不认识它——
   * 那条边界让模型可以在本机直接执行。所以"哪一类画哪个图标"是视图的决定，类别判定才是模型的。
   */
  private toolIcon(kind: ToolKind): Resource {
    if (kind === ToolKind.TERMINAL) {
      return $r('sys.symbol.code');
    }
    if (kind === ToolKind.READ) {
      return $r('sys.symbol.doc_text');
    }
    if (kind === ToolKind.WRITE) {
      return $r('sys.symbol.square_and_pencil');
    }
    if (kind === ToolKind.EDIT) {
      return $r('sys.symbol.pencil_line');
    }
    if (kind === ToolKind.SEARCH) {
      return $r('sys.symbol.magnifyingglass');
    }
    if (kind === ToolKind.WEB) {
      return $r('sys.symbol.link');
    }
    if (kind === ToolKind.IMAGE) {
      return $r('sys.symbol.picture');
    }
    if (kind === ToolKind.ASK) {
      return $r('sys.symbol.questionmark_circle');
    }
    return $r('sys.symbol.wrench_and_screwdriver');
  }


  @Builder
  subagentItem(item: TrajectoryItem) {
    NativeCard({
      iconSymbol: $r('sys.symbol.person_2'),
      title: `子代理 ${item.subagentName}`,
      tone: 'brand',
      meta: item.elapsedMs > 0
        ? (this.clockOf(item.at).length > 0
          ? `${this.clockOf(item.at)} · ${formatDuration(item.elapsedMs)}`
          : formatDuration(item.elapsedMs))
        : '',
      bodyText: item.body,
      expanded: true,
      a11y: `子代理 ${item.subagentName}`
    })
  }

  /**
   * 交付物的动作行（数据化：review 时一眼看得完"这一行有哪些动作"）。
   *
   * 保存/分享都交给宿主（文件系统与系统分享面板是平台能力，视图层不直接依赖 platform），
   * 与 Composer 的复制同一条约定。
   */
  private fileActions(item: TrajectoryItem): NativeAction[] {
    const out: NativeAction[] = [];
    /*
     * 【为什么这两个动作是"可见但禁用"，而不是可点】
     *
     * 它们此前是**两个不可点的 Text 标签**（看着像入口、点了没反应）——那正是本项目禁止的假入口形态。
     * 本轮查清了平台能力后确认：`platform` 只提供 `shareText`（**文本**，不是文件本体）
     * 与 `pickFolder/pickDocument`（选择，不是保存），**没有"另存为"** ⇒ 现在**无法**把
     * "保存 / 分享文件"做成真动作。
     *
     * 因此按纪律改成：动作**留在原位**（用户能看见这条卡具备这些能力）、
     * 但**禁用**并把原因写在无障碍文案里（读屏用户点不到也知道为什么）。
     * 真接线要等文件保存/分享能力就位——缺口已登记在矩阵 `deliverables` 行。
     */
    out.push({
      id: 'save',
      label: '保存',
      disabled: true,
      a11y: '保存到本地：尚未接线（当前平台未提供文件保存能力）'
    });
    out.push({
      id: 'share',
      label: '分享',
      disabled: true,
      a11y: '分享文件：尚未接线（当前平台只支持分享文本，不支持文件本体）'
    });
    return out;
  }

  @Builder
  deliverableItem(item: TrajectoryItem) {
    Row({ space: Sp.M }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(20)
        .fontColor([$r('sys.color.brand')])
      Column({ space: 2 }) {
        Text(item.fileName)
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(formatBytes(item.fileSize))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .accessibilityText(`交付物 ${item.fileName}`)
    // 动作行统一交给原语：间距/换行/语气只实现一次（此前是两个手写 Text）
    Row() {
      NativeActionBar({
        actions: this.fileActions(item)
      })
    }
    .width('100%')
  }

  @Builder
  goalItem(item: TrajectoryItem) {
    NativeCard({
      iconSymbol: item.kind === TrajectoryKind.GOAL
        ? $r('sys.symbol.checkmark_circle')
        : $r('sys.symbol.list_bullet'),
      title: item.title,
      badge: item.kind === TrajectoryKind.GOAL ? '目标' : '任务',
      tone: 'brand',
      summary: item.progress,
      progress: item.percent,
      a11y: `${item.kind === TrajectoryKind.GOAL ? '目标' : '任务'} ${item.title}`
    })
  }

  @Builder
  errorItem(item: TrajectoryItem) {
    Row({ space: Sp.S }) {
      Divider().vertical(true).color($r('sys.color.alert')).height('100%')
      Column({ space: 2 }) {
        Text('出错了')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.alert'))
          .width('100%')
        Text(item.body)
          .fontSize(Fs.SECONDARY)
          .width('100%')
          .textAlign(TextAlign.Start)
        Row({ space: Sp.L }) {
          Text('重试').fontSize(Fs.CAPTION).fontColor($r('sys.color.brand'))
          Text('查看诊断')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              this.onOpenDetail();
            })
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .accessibilityText(`错误：${item.body}`)
  }

  // ───────────────────── 辅助 ─────────────────────

  private isExpanded(id: string): boolean {
    return this.expanded.indexOf(id) >= 0;
  }

  private toggle(id: string): void {
    const out: string[] = [];
    let found: boolean = false;
    for (let i = 0; i < this.expanded.length; i++) {
      if (this.expanded[i] === id) {
        found = true;
      } else {
        out.push(this.expanded[i]);
      }
    }
    if (!found) {
      out.push(id);
    }
    this.expanded = out;
  }


  private speakableText(item: TrajectoryItem): string {
    const who: string = item.speaker === Speaker.USER ? '我说' : '助手回复';
    const head: string = item.body.length > 60 ? `${item.body.substring(0, 60)}…` : item.body;
    return `${who}：${head}（共 ${item.body.length} 字）`;
  }
}
