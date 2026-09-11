/**
 * 输入区（Composer）—— D3 §3.6。
 *
 * 覆盖：多行输入、@ 引用弹层、斜杠命令弹层、附件、模型与推理强度 chip、
 * 发送/停止、草稿持久化（由宿主负责存储，本组件只上报变更）、
 * 离线排队提示、无障碍标签。
 *
 * 本组件不直接调用协议层：所有动作通过回调上报给宿主，便于接入真实连接时只改宿主。
 */

import {
  CommandCandidate,
  Fs,
  formatBytes,
  ModelSelection,
  modelSelectionLabel,
  ModelOption,
  PendingAttachment,
  QueuedItem,
  Radius,
  ReferenceCandidate,
  Sp,
  Sz
} from 'appstate';

/**
 * 附件条目的展示文本：`名字 · 大小`。
 *
 * 【为什么必须带大小】附件是「先上传、后随消息发出」两步。
 * 只显示文件名时，用户无法确认选中的到底是哪个文件（同名文件很常见），
 * 也无法察觉自己选错了版本。大小是最便宜的可辨识信息。
 */
function attachmentLabel(item: PendingAttachment): string {
  return item.bytes > 0 ? `${item.name} · ${formatBytes(item.bytes)}` : item.name;
}

/**
 * 排队项位置的展示文本。
 *
 * 【为什么未知位置要原样显示，而不是归到某一类】`placement` 的取值
 * （`queued` / `steering` / `context`）决定这条消息**会在什么时候**被处理：
 * 普通排队要等当前轮次结束，插话会打断当前轮次，context 是补充上下文。
 * 猜错会让用户以为点下"插话"才生效，而它其实已经会插话了。
 * 因此未知取值一律**原样带上**，让用户与日志都能看到真实值。
 */
function placementLabel(placement: string): string {
  if (placement === 'queued') {
    return '轮次结束后发送';
  }
  if (placement === 'steering') {
    return '插话（已在打断中）';
  }
  if (placement === 'context') {
    return '作为上下文';
  }
  return placement.length > 0 ? placement : '位置未知';
}

@Component
export struct Composer {
  @Prop draft: string = '';
  @Prop running: boolean = false;
  @Prop offline: boolean = false;
  @Prop queuedCount: number = 0;
  @Prop attachments: PendingAttachment[] = [];
  /** 当前会话在 Host 侧的排队项（`session/control` 驱动；与会话一一对应） */
  @Prop queued: QueuedItem[] = [];
  @Prop models: ModelOption[] = [];
  @Prop selection: ModelSelection = { provider: '', modelId: '', effort: '' };
  @Prop references: ReferenceCandidate[] = [];
  @Prop commands: CommandCandidate[] = [];
  /**
   * 一次性提示（能力缺失说明等）。
   *
   * 【为什么需要它】D3 §4 要求「能力缺失时对应的入口置灰 + 说明原因（不隐藏）」。
   * 隐藏入口会让用户以为客户端没有这个功能；而入口点了没反应是**静默失败**，
   * 用户只会反复点。两者都劣于「点了之后明确告诉你为什么现在不能用」。
   */
  @Prop notice: string = '';

  /** 文本变化 */
  onDraftChange: (text: string) => void = () => {
  };
  /** 发送 */
  onSend: () => void = () => {
  };
  /** 停止当前轮次 */
  onStop: () => void = () => {
  };
  /** 添加附件（宿主负责拉起相册/文件选择器） */
  onAddAttachment: () => void = () => {
  };
  /**
   * 移除附件（参数是**回执 id**，不是文件名）。
   *
   * 为什么用回执而不是文件名：同名文件可以加两次，按名字移除会一次删掉两个，
   * 而用户只点了一个「×」。回执是这次上传的唯一身份。
   */
  onRemoveAttachment: (receiptId: string) => void = () => {
  };
  /** 切换模型（宿主弹出选择器） */
  onPickModel: () => void = () => {
  };
  /**
   * 把排队项**取回输入框**编辑（宿主实现为：移除该队列项 + 把正文填进草稿）。
   *
   * 【为什么不做"就地编辑"】就地编辑需要一个行内输入框 + 提交按钮，
   * 在手机上会与软键盘、弹层、滚动位置互相干扰；而"取回草稿"复用了已有的输入区，
   * 用户还能顺带改附件、改引用。代价是多一步（取回后要再点发送），
   * 换来的是**一条**编辑路径而不是两条各自有边界情况的路径。
   */
  onPullQueued: (itemId: string, text: string) => void = () => {
  };
  /** 移除一个排队项 */
  onRemoveQueued: (itemId: string) => void = () => {
  };
  /** 把排队项提前为插话（打断当前轮次立即处理） */
  onSteerQueued: (itemId: string) => void = () => {
  };
  /**
   * `@` 引用的查询词变化（宿主据此**向 Host 拉候选**）。
   *
   * 【为什么候选必须问 Host，而不是本地过滤一份固定清单】
   *   文件候选是「这个会话的工作区里有哪些路径」，只有 Host 知道；
   *   本地过滤一份固定清单只能给出编造的候选，用户选中一个不存在的路径后
   *   提示词会在 Host 侧静静失败（或退化成一个普通文本 `@xxx`）。
   *   因此这里把**查询串**交给宿主，由宿主去问 Host。
   */
  onReferenceQuery: (query: string) => void = () => {
  };

  /** 当前激活的弹层：'' / 'ref' / 'cmd'（避免与 ArkUI 基类属性重名，故用 panel） */
  @State panel: string = '';
  /** 弹层过滤词 */
  @State filter: string = '';

  build() {
    Column({ space: Sp.S }) {
      if (this.offline) {
        this.offlineNotice()
      }

      if (this.notice.length > 0) {
        this.capabilityNotice()
      }

      if (this.queued.length > 0) {
        this.queuePanel()
      }

      if (this.attachments.length > 0) {
        this.attachmentRow()
      }

      if (this.panel.length > 0) {
        this.overlayPanel()
      }

      this.toolRow()

      Row({ space: Sp.S }) {
        TextArea({ text: this.draft, placeholder: '输入消息…（Enter 发送，Shift+Enter 换行）' })
          .onChange((value: string) => {
            this.onDraftChange(value);
            this.updateOverlay(value);
          })
          .layoutWeight(1)
          .constraintSize({ minHeight: Sz.TOUCH_MIN, maxHeight: Sz.TOUCH_MIN * 5 })
          .accessibilityText('消息输入框')

        this.sendButton()
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(Sp.M)
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  offlineNotice() {
    Row({ space: Sp.S }) {
      SymbolGlyph($r('sys.symbol.wifi_slash'))
        .fontSize(14)
        .fontColor([$r('sys.color.warning')])
      Text(this.queuedCount > 0
        ? `离线中：已排队 ${this.queuedCount} 条，连接恢复后按序发送`
        : '离线中：发送的消息将在连接恢复后按序发送')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.warning'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding(Sp.S)
    .borderRadius(Radius.S)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  queuePanel() {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        Text(`待发队列 ${this.queued.length} 条`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .layoutWeight(1)
        Text('由 Host 维护')
          .fontSize(10)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')

      ForEach(this.queued, (item: QueuedItem) => {
        Column({ space: Sp.XS }) {
          Text(item.text)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row({ space: Sp.L }) {
            Text('取回编辑')
              .fontSize(10)
              .fontColor($r('sys.color.brand'))
              .onClick(() => {
                this.onPullQueued(item.id, item.text);
              })
            Text(placementLabel(item.placement))
              .fontSize(10)
              .fontColor($r('sys.color.font_tertiary'))
            Blank()
            Text('插话')
              .fontSize(10)
              .fontColor($r('sys.color.brand'))
              .onClick(() => {
                this.onSteerQueued(item.id);
              })
            Text('移除')
              .fontSize(10)
              .fontColor($r('sys.color.alert'))
              .onClick(() => {
                this.onRemoveQueued(item.id);
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(Sp.S)
        .borderRadius(Radius.S)
        .backgroundColor($r('sys.color.background_secondary'))
      }, (item: QueuedItem) => item.id)
    }
    .width('100%')
  }

  @Builder
  capabilityNotice() {
    Row({ space: Sp.S }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(14)
        .fontColor([$r('sys.color.font_secondary')])
      Text(this.notice)
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding(Sp.S)
    .borderRadius(Radius.S)
    .backgroundColor($r('sys.color.background_secondary'))
    .accessibilityText(this.notice)
  }

  @Builder
  attachmentRow() {
    Scroll() {
      Row({ space: Sp.S }) {
        ForEach(this.attachments, (item: PendingAttachment) => {
          Row({ space: Sp.XS }) {
            SymbolGlyph($r('sys.symbol.paperclip')).fontSize(12)
              .fontColor([$r('sys.color.font_secondary')])
            Text(attachmentLabel(item))
              .fontSize(Fs.CAPTION)
              .maxLines(1)
              .constraintSize({ maxWidth: 160 })
            Text('×')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.alert'))
              .onClick(() => {
                // 以**回执**为键移除，而不是文件名：同名文件可以加两次，
                // 按名字移除会一次删掉两个（用户以为只删了一个）。
                this.onRemoveAttachment(item.receiptId);
              })
          }
          .padding({ left: Sp.S, right: Sp.S, top: Sp.XS, bottom: Sp.XS })
          .borderRadius(Radius.S)
          .backgroundColor($r('sys.color.background_secondary'))
        }, (item: PendingAttachment) => item.receiptId)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  /** 工具行：@ / / / 附件 / 模型 chip */
  @Builder
  toolRow() {
    Row({ space: Sp.S }) {
      Text('@ 引用')
        .fontSize(Fs.CAPTION)
        .fontColor(this.panel === 'ref' ? $r('sys.color.brand') : $r('sys.color.font_secondary'))
        .padding({ left: Sp.S, right: Sp.S, top: Sp.XS, bottom: Sp.XS })
        .borderRadius(Radius.S)
        .backgroundColor($r('sys.color.background_secondary'))
        .onClick(() => {
          this.panel = this.panel === 'ref' ? '' : 'ref';
          this.filter = '';
        })

      Text('/ 命令')
        .fontSize(Fs.CAPTION)
        .fontColor(this.panel === 'cmd' ? $r('sys.color.brand') : $r('sys.color.font_secondary'))
        .padding({ left: Sp.S, right: Sp.S, top: Sp.XS, bottom: Sp.XS })
        .borderRadius(Radius.S)
        .backgroundColor($r('sys.color.background_secondary'))
        .onClick(() => {
          this.panel = this.panel === 'cmd' ? '' : 'cmd';
          this.filter = '';
        })

      Button() {
        SymbolGlyph($r('sys.symbol.paperclip')).fontSize(16)
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .accessibilityText('添加附件')
      .onClick(() => {
        this.onAddAttachment();
      })

      Blank()

      Text(this.modelLabel())
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .constraintSize({ maxWidth: 160 })
        .padding({ left: Sp.S, right: Sp.S, top: Sp.XS, bottom: Sp.XS })
        .borderRadius(Radius.S)
        .backgroundColor($r('sys.color.background_secondary'))
        .accessibilityText(`当前模型：${this.modelLabel()}，点击切换`)
        .onClick(() => {
          this.onPickModel();
        })
    }
    .width('100%')
  }

  @Builder
  overlayPanel() {
    Column() {
      Text(this.panel === 'ref' ? '插入引用' : '运行命令')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
        .padding({ bottom: Sp.XS })

      List({ space: Sp.XS }) {
        if (this.panel === 'ref') {
          ForEach(this.filteredReferences(), (c: ReferenceCandidate) => {
            ListItem() {
              Column({ space: 2 }) {
                Row({ space: Sp.S }) {
                  Text(`@${c.kind}`)
                    .fontSize(Fs.CAPTION)
                    .fontColor($r('sys.color.brand'))
                  Text(c.label)
                    .fontSize(Fs.SECONDARY)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                if (c.detail.length > 0) {
                  Text(c.detail)
                    .fontSize(Fs.CAPTION)
                    .fontColor($r('sys.color.font_tertiary'))
                    .width('100%')
                }
              }
              .width('100%')
              .padding(Sp.S)
              .borderRadius(Radius.S)
              .onClick(() => {
                this.onDraftChange(`${this.draft}${c.insert} `);
                this.panel = '';
              })
            }
          }, (c: ReferenceCandidate) => `${c.kind}:${c.label}`)
        } else {
          ForEach(this.filteredCommands(), (c: CommandCandidate) => {
            ListItem() {
              Row({ space: Sp.S }) {
                Text(c.name)
                  .fontSize(Fs.SECONDARY)
                  .fontColor($r('sys.color.brand'))
                if (c.args.length > 0) {
                  Text(c.args)
                    .fontSize(Fs.CAPTION)
                    .fontColor($r('sys.color.font_tertiary'))
                }
                Text(c.detail)
                  .fontSize(Fs.CAPTION)
                  .fontColor($r('sys.color.font_secondary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding(Sp.S)
              .borderRadius(Radius.S)
              .onClick(() => {
                this.onDraftChange(`${c.name} `);
                this.panel = '';
              })
            }
          }, (c: CommandCandidate) => c.name)
        }
      }
      .height(180)
      .width('100%')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .padding(Sp.S)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  sendButton() {
    Button() {
      SymbolGlyph(this.running ? $r('sys.symbol.xmark') : $r('sys.symbol.arrow_up'))
        .fontSize(18)
        .fontColor([Color.White])
    }
    .width(Sz.TOUCH_MIN)
    .height(Sz.TOUCH_MIN)
    .enabled(this.running || this.draft.trim().length > 0)
    .accessibilityText(this.running ? '停止当前轮次' : '发送消息')
    .onClick(() => {
      if (this.running) {
        this.onStop();
      } else {
        this.onSend();
      }
    })
  }

  /** 依据输入内容自动切换弹层（输入 @ 开引用，输入 / 开头开命令） */
  private updateOverlay(value: string): void {
    const trimmed: string = value.trimStart();
    const lastAt: number = trimmed.lastIndexOf('@');
    const atTail: boolean = lastAt >= 0 && trimmed.indexOf(' ') < lastAt && trimmed.indexOf('\n') < lastAt;
    if (trimmed.startsWith('/') && trimmed.indexOf(' ') < 0 && trimmed.indexOf('\n') < 0) {
      this.panel = 'cmd';
      this.filter = trimmed.substring(1);
      return;
    }
    if (atTail) {
      this.panel = 'ref';
      const tail: string = trimmed.substring(lastAt + 1);
      const next: string = tail.indexOf(' ') < 0 && tail.indexOf('\n') < 0 ? tail : '';
      const changed: boolean = next !== this.filter;
      this.filter = next;
      // 只有查询词真的变了才去问 Host：每次按键都发一次会在长查询上打出成串 RPC，
      // 而 Host 的候选端点本身就是**按 query 过滤**的（服务端筛选），本地不再二次筛。
      if (changed) {
        this.onReferenceQuery(this.filter);
      }
      return;
    }
    this.filter = '';
  }

  /**
   * 引用候选。
   *
   * **不再本地过滤**：候选由 Host 按查询词返回（见 `onReferenceQuery` 的说明），
   * 本地再筛一遍会与 Host 的匹配/排序规则不一致——表现为「Host 明明返回了 3 条，
   * 界面只显示 1 条」，而且这种分歧只在特定字符上出现，极难复现。
   */
  private filteredReferences(): ReferenceCandidate[] {
    return this.references;
  }

  private filteredCommands(): CommandCandidate[] {
    if (this.filter.length === 0) {
      return this.commands;
    }
    const q: string = this.filter.toLowerCase();
    const out: CommandCandidate[] = [];
    for (let i = 0; i < this.commands.length; i++) {
      const c: CommandCandidate = this.commands[i];
      if (c.name.toLowerCase().indexOf(q) >= 0 || c.detail.toLowerCase().indexOf(q) >= 0) {
        out.push(c);
      }
    }
    return out;
  }

  private modelLabel(): string {
    const label: string = modelSelectionLabel(this.selection, this.models);
    return this.selection.effort.length > 0 ? `${label} · ${this.selection.effort}` : label;
  }
}
