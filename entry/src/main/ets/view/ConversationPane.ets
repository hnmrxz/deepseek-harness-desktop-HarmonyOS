/**
 * 会话面板（轨迹 + 输入区）。
 *
 * 规格依据 D3 §3.2（轨迹条目类型）、§3.3（工具调用卡片）、§3.6（输入区）。
 *
 * 数据来源：当前由桩数据源提供（方案 2）。接入真实连接后，
 * 只需把 `items` 的来源换成事件流投影，本组件不改动。
 */

import {
  formatBytes,
  formatClock,
  formatDuration,
  Fs,
  Lh,
  previewOutput,
  Radius,
  Sp,
  Speaker,
  Sz,
  ToolState,
  toolStateIsProblem,
  toolStateLabel,
  TrajectoryItem,
  TrajectoryKind,
  stubTrajectory
} from 'appstate';

@Component
export struct ConversationPane {
  @Prop sessionId: string = '';
  @State items: TrajectoryItem[] = [];
  @State draft: string = '';
  /** 展开状态的工具卡片 id 集合 */
  @State expanded: string[] = [];
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.items = stubTrajectory();
  }

  build() {
    Column() {
      // 轨迹
      List({ space: Sp.M, scroller: this.scroller }) {
        ForEach(this.items, (item: TrajectoryItem) => {
          ListItem() {
            this.trajectoryItem(item)
          }
        }, (item: TrajectoryItem) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: Sp.M, right: Sp.M, top: Sp.M })
      .scrollBar(BarState.Auto)

      Divider().color($r('sys.color.comp_divider'))

      // 输入区（D3 §3.6）
      this.composer()
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
        Text(item.speaker === Speaker.USER ? '我' : '助手')
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

      Text(item.body + (item.streaming ? ' ▌' : ''))
        .fontSize(Fs.BODY)
        .lineHeight(Fs.BODY * Lh.BODY)
        .width('100%')
        .textAlign(TextAlign.Start)

      Row({ space: Sp.L }) {
        Text('复制').fontSize(Fs.CAPTION).fontColor($r('sys.color.brand'))
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
        Text(item.elapsedMs > 0 ? `已思考 ${formatDuration(item.elapsedMs)}` : '思考中…')
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
      }
    }
    .width('100%')
    .padding(Sp.S)
    .borderRadius(Radius.S)
    .borderWidth(1)
    .borderColor($r('sys.color.comp_divider'))
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

      // 失败/被拒默认展开（D3 §3.3）
      if (item.toolOutput.length > 0 && (this.isExpanded(item.id) || toolStateIsProblem(item.toolState))) {
        this.outputBlock(item)
      } else if (item.toolOutput.length > 0) {
        Text('▸ 查看结果')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.toggle(item.id);
          })
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .borderWidth(1)
    .borderColor(toolStateIsProblem(item.toolState)
      ? $r('sys.color.alert')
      : $r('sys.color.comp_divider'))
  }

  @Builder
  outputBlock(item: TrajectoryItem) {
    Column({ space: Sp.XS }) {
      Text(previewOutput(item.toolOutput).shown)
        .fontSize(Fs.CAPTION)
        .fontFamily('monospace')
        .width('100%')
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
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .borderWidth(1)
    .borderColor($r('sys.color.comp_divider'))
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
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
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
        Row({ space: Sp.L }) {
          Text('重试').fontSize(Fs.CAPTION).fontColor($r('sys.color.brand'))
          Text('查看诊断').fontSize(Fs.CAPTION).fontColor($r('sys.color.brand'))
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  // ───────────────────── 输入区（D3 §3.6） ─────────────────────

  @Builder
  composer() {
    Column({ space: Sp.S }) {
      Row({ space: Sp.S }) {
        Text('@ 引用').fontSize(Fs.CAPTION).fontColor($r('sys.color.font_secondary'))
        Text('/ 命令').fontSize(Fs.CAPTION).fontColor($r('sys.color.font_secondary'))
        Blank()
        Text('deepseek-v4-flash').fontSize(Fs.CAPTION).fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')

      Row({ space: Sp.S }) {
        TextArea({ text: this.draft, placeholder: '输入消息…（Shift+Enter 换行）' })
          .onChange((value: string) => {
            this.draft = value;
          })
          .layoutWeight(1)
          .constraintSize({ minHeight: Sz.TOUCH_MIN, maxHeight: Sz.TOUCH_MIN * 4 })

        Button() {
          SymbolGlyph($r('sys.symbol.arrow_up'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(Sz.TOUCH_MIN)
        .height(Sz.TOUCH_MIN)
        .enabled(this.draft.trim().length > 0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(Sp.M)
    .backgroundColor($r('sys.color.background_primary'))
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
}
