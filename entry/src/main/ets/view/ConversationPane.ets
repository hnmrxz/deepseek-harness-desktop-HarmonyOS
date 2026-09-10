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
  ModelOption,
  ModelSelection,
  previewOutput,
  Radius,
  ReferenceCandidate,
  Sp,
  Speaker,
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
  @Prop attachments: string[] = [];
  @Prop models: ModelOption[] = [];
  @Prop selection: ModelSelection = { provider: '', modelId: '', effort: '' };
  @Prop references: ReferenceCandidate[] = [];
  @Prop commands: CommandCandidate[] = [];

  onDraftChange: (text: string) => void = () => {
  };
  onSend: () => void = () => {
  };
  onStop: () => void = () => {
  };
  onAddAttachment: () => void = () => {
  };
  onRemoveAttachment: (name: string) => void = () => {
  };
  onPickModel: () => void = () => {
  };
  /** 打开详情栏（单栏/双栏下没有并排详情栏时使用） */
  onOpenDetail: () => void = () => {
  };

  @State expanded: string[] = [];
  private scroller: Scroller = new Scroller();

  build() {
    Column() {
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

      Composer({
        draft: this.draft,
        running: this.running,
        offline: this.offline,
        queuedCount: this.queuedCount,
        attachments: this.attachments,
        models: this.models,
        selection: this.selection,
        references: this.references,
        commands: this.commands,
        onDraftChange: this.onDraftChange,
        onSend: this.onSend,
        onStop: this.onStop,
        onAddAttachment: this.onAddAttachment,
        onRemoveAttachment: this.onRemoveAttachment,
        onPickModel: this.onPickModel
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
