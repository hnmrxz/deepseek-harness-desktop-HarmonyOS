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
  TrajectoryKind
} from 'appstate';
import { Composer } from './Composer';

@Component
export struct ConversationPane {
  @Prop sessionId: string = '';
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
    const last: number = this.visibleItems().length - 1;
    this.stickToBottom = last < 0 || end >= last;
  }

  private onItemsChanged(): void {
    if (this.stickToBottom) {
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
    const shouldRun: boolean = this.running && this.stickToBottom;
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
  private visibleItems(): TrajectoryItem[] {
    if (this.view === 'trajectory') {
      return this.items;
    }
    const out: TrajectoryItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: TrajectoryItem = this.items[i];
      if (item.kind === TrajectoryKind.MESSAGE || item.kind === TrajectoryKind.ERROR) {
        // 系统消息（系统提示词等内部上下文）不进对话视图：官方 web 也不显示，
        // 它会让用户以为模型在自言自语（真机截图里出现过）。轨迹视图里仍可查。
        if (item.speaker === Speaker.SYSTEM) {
          continue;
        }
        out.push(item);
      }
    }
    return out;
  }

  @Builder
  viewChip(value: string, label: string) {
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
        this.viewChip('chat', '对话')
        this.viewChip('trajectory', '轨迹')
        Blank()
        if (this.view === 'trajectory') {
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
        ForEach(this.visibleItems(), (item: TrajectoryItem) => {
          ListItem() {
            this.trajectoryItem(item)
          }
          // 命中项加一条左侧色条：**不改变正文**（正文里做高亮要拆 span，
          // 而拆 span 会让 Markdown/代码块的渲染路径多一条分支，风险大于收益）。
          .border({ width: { left: this.isHit(item) ? 3 : 0 },
            color: $r('sys.color.brand') })
        }, (item: TrajectoryItem) => item.id)
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
        onSend: this.onSend,
        onStop: this.onStop,
        onAddAttachment: this.onAddAttachment,
        onRemoveAttachment: this.onRemoveAttachment,
        onPickModel: this.onPickModel,
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
          Text(formatDuration(item.elapsedMs))
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

      /*
       * 【思考单独成块（E107）】助手消息常把"思考"与"正文"作为两个内容块一起发来。
       * 官方 web 把思考收进**折叠块**（标题给字数/耗时，默认收起），正文单独成段。
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
        .borderWidth(1)
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

      Row({ space: Sp.L }) {
        Text('复制')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .copyOption(CopyOptions.LocalDevice)
        Text('引用').fontSize(Fs.CAPTION).fontColor($r('sys.color.brand'))
        if (item.speaker === Speaker.USER) {
          Text('重发').fontSize(Fs.CAPTION).fontColor($r('sys.color.brand'))
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor(item.speaker === Speaker.USER
      ? $r('sys.color.background_secondary')
      : $r('sys.color.background_primary'))
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
    .borderWidth(1)
    .borderColor($r('sys.color.comp_divider'))
    .accessibilityText('思考过程，点击展开或收起')
    .onClick(() => {
      this.toggle(item.id);
    })
  }

  /** 工具调用卡片（D3 §3.3） */
  @Builder
  toolItem(item: TrajectoryItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
          .fontSize(14)
          .fontColor([this.toolColor(item.toolState)])
        Text(item.toolName)
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(toolStateLabel(item.toolState))
          .fontSize(Fs.CAPTION)
          .fontColor(this.toolColor(item.toolState))
        if (item.elapsedMs > 0) {
          Text(formatDuration(item.elapsedMs))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')

      if (item.toolArgs.length > 0) {
        Text(item.toolArgs)
          .fontSize(Fs.CAPTION)
          .fontFamily('monospace')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (item.toolOutput.length > 0) {
        if (this.isExpanded(item.id) || toolStateIsProblem(item.toolState)) {
          this.outputBlock(item)
        } else {
          Text('▸ 查看结果')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              this.toggle(item.id);
            })
        }
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .borderWidth(1)
    .borderColor(toolStateIsProblem(item.toolState) ? $r('sys.color.alert') : $r('sys.color.comp_divider'))
    .accessibilityText(`工具 ${item.toolName}，状态 ${toolStateLabel(item.toolState)}`)
  }

  @Builder
  outputBlock(item: TrajectoryItem) {
    Column({ space: Sp.XS }) {
      Text(previewOutput(item.toolOutput).shown)
        .fontSize(Fs.CAPTION)
        .fontFamily('monospace')
        .width('100%')
        .textAlign(TextAlign.Start)
        .copyOption(CopyOptions.LocalDevice)
      if (previewOutput(item.toolOutput).truncated) {
        Text(`▸ 查看完整输出（共 ${previewOutput(item.toolOutput).totalLength} 字符）`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
      }
    }
    .width('100%')
    .padding(Sp.S)
    .borderRadius(Radius.S)
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  subagentItem(item: TrajectoryItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        SymbolGlyph($r('sys.symbol.person_2'))
          .fontSize(14)
          .fontColor([$r('sys.color.brand')])
        Text(`子代理 ${item.subagentName}`)
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        if (item.elapsedMs > 0) {
          Text(formatDuration(item.elapsedMs))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')
      Text(item.body)
        .fontSize(Fs.SECONDARY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .borderWidth(1)
    .borderColor($r('sys.color.comp_divider'))
    .accessibilityText(`子代理 ${item.subagentName}`)
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
      Text('保存')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.brand'))
      Text('分享')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.brand'))
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .accessibilityText(`交付物 ${item.fileName}`)
  }

  @Builder
  goalItem(item: TrajectoryItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        SymbolGlyph(item.kind === TrajectoryKind.GOAL
          ? $r('sys.symbol.checkmark_circle')
          : $r('sys.symbol.list_bullet'))
          .fontSize(14)
          .fontColor([$r('sys.color.brand')])
        Text(item.title)
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(item.kind === TrajectoryKind.GOAL ? '目标' : '任务')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')

      if (item.percent >= 0) {
        Progress({ value: item.percent, total: 100, type: ProgressType.Linear })
          .width('100%')
      }

      Text(item.progress)
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .borderWidth(1)
    .borderColor($r('sys.color.comp_divider'))
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

  private toolColor(state: ToolState): ResourceColor {
    if (state === ToolState.SUCCESS) {
      return $r('sys.color.confirm');
    }
    if (state === ToolState.FAILED) {
      return $r('sys.color.alert');
    }
    if (state === ToolState.REJECTED) {
      return $r('sys.color.warning');
    }
    if (state === ToolState.RUNNING) {
      return $r('sys.color.brand');
    }
    return $r('sys.color.font_tertiary');
  }

  /** 无障碍朗读文本（D3 §7） */
  private speakableText(item: TrajectoryItem): string {
    const who: string = item.speaker === Speaker.USER ? '我说' : '助手回复';
    const head: string = item.body.length > 60 ? `${item.body.substring(0, 60)}…` : item.body;
    return `${who}：${head}（共 ${item.body.length} 字）`;
  }
}
