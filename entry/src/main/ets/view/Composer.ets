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
import { appendPick, applyPick, detectTrigger, TriggerToken } from 'appstate';
import { NativeButton, NativeChip } from './NativePrimitives';

/**
 * 附件缩略图边长（vp）。
 *
 * 取值与设计令牌里的 `Sz.TOUCH_MIN`（44）无关：这里是**图片预览**，不是命中目标
 * （删除按钮才是）。32 是"看得清是什么图"与"不把输入区撑高"之间的折中。
 */
const THUMB_SIDE: number = 32;

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
 * 图片草稿的**预览 URL**（`data:` 形式；空串 = 这条不是图片）。
 *
 * 【为什么在视图里现拼】图片草稿的 base64 只在内存里、发出去就清空（见
 * `PendingAttachment.data`），没有持久 URL 可缓存；ArkUI 的 `Image()` 直接吃
 * `data:` URL，现拼是零成本的。中枢那套图片缓存（`imageUrlOf`）是给**历史**图片用的
 * （那些要走 `session/attachment` 读字节）——两者不是一回事，不要混用。
 */
function attachmentPreview(item: PendingAttachment): string {
  if (item.kind !== 'image' || item.data.length === 0 || item.mediaType.length === 0) {
    return '';
  }
  return `data:${item.mediaType};base64,${item.data}`;
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
  /**
   * 计划模式的**生效**状态（官方 `ui-plan` 的一级 chip，E202）。
   *
   * `planPending` 表示"刚切换、等宿主确认"——此时生效值要取反，与官方判据一致：
   * `pending ? !active : active`。把这条判据放在 Composer 里，是因为**chip 显示的就是它**。
   */
  @Prop planActive: boolean = false;
  @Prop planPending: boolean = false;
  /**
   * 当前会话的权限模式（只读展示）。
   *
   * 官方把它做成输入区的 `/permission` 弹层；本仓的**切换**端点尚未接线（见矩阵
   * `permission-presets` 行），所以这里**如实只显示当前生效值**——不做一个点了没反应的假入口。
   * 空串表示中枢还没读到，此时不显示该 chip（而不是显示一个"未知"）。
   */
  /**
   * 权限 chip 的**显示文案**（宿主用 `permissionChipLabel` 算好：有值给值，
   * 没能力给官方那句「不可用」）——视图不自己判，只读结论。
   */
  @Prop permissionLabel: string = '';
  /** 这台 Host 能不能切权限（宿主用 `permissionSwitchable(permissionsOptions)` 算） */
  @Prop permissionSwitchableNow: boolean = false;
  /** 不能切时的原因（写进无障碍文案） */
  @Prop permissionHint: string = '';
  /** 点权限 chip（宿主开单选浮层 → `/permission <id>`） */
  onPickPermission: () => void = () => {
  };

  /** 文本变化 */
  onDraftChange: (text: string) => void = () => {
  };
  /** 发送 */
  onSend: () => void = () => {
  };
  /** 停止当前轮次 */
  onStop: () => void = () => {
  };
  /** 添加**文件**附件（宿主拉起文件选择器 → 上传拿回执） */
  onAddAttachment: () => void = () => {
  };
  /**
   * 添加**图片**（P0-4：宿主拉起图库 → **内联**进下一条消息，不走上传）。
   *
   * 【为什么要与「附件」分成两个入口】两条路的线上语义不同：文件先上传拿**会话作用域**
   * 的回执，再把回执放进 `file` 片段；图片直接内联 base64（官方 `serializeImages()`）。
   * 合成一个按钮就意味着"选了图之后才知道走哪条路"，而失败时的原因也说不清。
   */
  onAddImage: () => void = () => {
  };
  /**
   * 移除附件（参数是**行身份 `key`**，不是文件名）。
   *
   * 文件的行身份是上传回执，图片是客户端草稿 id（它没有回执）。按名字移除会
   * 一次删掉两个同名附件，而用户只点了一个「×」。
   */
  onRemoveAttachment: (key: string) => void = () => {
  };
  /** 切换模型（宿主弹出选择器） */
  onPickModel: () => void = () => {
  };

  /** 切换计划模式（执行 `/plan` 命令，宿主把它做成了一条命令） */
  onTogglePlan: () => void = () => {
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
        // E123：占位文案改用官方措辞（「发消息或创建任务, / 调用指令, @ 文件或对话」），
        // 走资源 ⇒ 跟随系统语言，默认中文
        TextArea({
          text: this.draft,
          placeholder: this.offline
            ? $r('app.string.composer_placeholder_offline')
            : $r('app.string.composer_placeholder')
        })
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
          .fontSize(Fs.CAPTION_XS)
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
              .fontSize(Fs.CAPTION_XS)
              .fontColor($r('sys.color.brand'))
              .onClick(() => {
                this.onPullQueued(item.id, item.text);
              })
            Text(placementLabel(item.placement))
              .fontSize(Fs.CAPTION_XS)
              .fontColor($r('sys.color.font_tertiary'))
            Blank()
            Text('插话')
              .fontSize(Fs.CAPTION_XS)
              .fontColor($r('sys.color.brand'))
              .onClick(() => {
                this.onSteerQueued(item.id);
              })
            Text('移除')
              .fontSize(Fs.CAPTION_XS)
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
            /*
             * 图片给**缩略图**、文件给回形针（P0-4）。
             *
             * 【为什么不都用回形针】图片最常见的问题是"选错了一张"——缩略图是唯一
             * 能在发出前看出来的信息；文件名（`IMG_20240101_120000.jpg`）对人几乎无用。
             * 官方输入区的附件槽位同样给预览。
             */
            if (attachmentPreview(item).length > 0) {
              Image(attachmentPreview(item))
                .width(THUMB_SIDE)
                .height(THUMB_SIDE)
                .objectFit(ImageFit.Cover)
                .borderRadius(Radius.XS)
                .accessibilityText(`图片预览：${item.name}`)
            } else {
              SymbolGlyph($r('sys.symbol.paperclip')).fontSize(12)
                .fontColor([$r('sys.color.font_secondary')])
            }
            Text(attachmentLabel(item))
              .fontSize(Fs.CAPTION)
              .maxLines(1)
              .constraintSize({ maxWidth: 160 })
            Text('×')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.alert'))
              .onClick(() => {
                // 以**行身份 `key`** 移除，而不是文件名：同名文件可以加两次，
                // 按名字移除会一次删掉两个（用户以为只删了一个）。
                // 图片没有回执，它的 key 是客户端草稿 id（P0-4）。
                this.onRemoveAttachment(item.key);
              })
          }
          .padding({ left: Sp.S, right: Sp.S, top: Sp.XS, bottom: Sp.XS })
          .borderRadius(Radius.S)
          .backgroundColor($r('sys.color.background_secondary'))
        }, (item: PendingAttachment) => item.key)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  /** 计划模式的**生效**值（官方判据：`pending ? !active : active`） */
  private planOn(): boolean {
    return this.planPending ? !this.planActive : this.planActive;
  }

  /**
   * 工具行：@ / / / 附件 / 图片 / 计划 / 权限 || 模型（全部走 P1.5 的原生原语）。
   *
   * ## 为什么是**可换行的 Flex**，而不是一行 `Row` + `Blank()`
   *
   * 一行 `Row` 里不放 `layoutWeight` 的子元素**不会缩**：手机上（360vp）这一行的固定宽度加起来
   * 已经超过屏宽（两个 chip + 两个图标按钮 + 计划 + 权限 chip + 模型 chip），
   * 于是**最右边的「模型」chip 被挤出屏幕**——它偏偏是手机上最常用的控件之一。
   * 这正是 `docs/08` 的 P0 §7 点名的那类缺陷：「操作区被内容挤压时不得静默消失」。
   *
   * 官方 Web 的输入区这一行就是 `flex-wrap: wrap; justify-content: space-between`
   * （`dsh-client-ui-conversation` 的 composer CSS：`.W5Twba_row{flex-wrap:wrap;justify-content:space-between;…}`），
   * 并且把"模型/发送"那一组放在 `.trailing{margin-left:auto}` 里。
   * 这里照同一结构：**外层可换行 + 两个组**（左组工具、右组模型）——
   * 放得下时模型靠右，放不下时整组换到第二行，**没有任何控件被裁掉**。
   *
   * 间距用子元素的 margin（本仓 `NativeActionBar` 已是这个写法）：换行之后
   * `space` 只在主轴方向生效，跨行间距得靠 margin 才一致。
   */
  @Builder
  toolRow() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
      // ── 左组：输入类工具（自身也可换行：权限 chip 最长，手机上常换到第二行）──
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Row() {
          NativeChip({
            label: '@ 引用',
            active: this.panel === 'ref',
            a11y: '插入文件或会话引用',
            onTap: () => {
              this.panel = this.panel === 'ref' ? '' : 'ref';
              this.filter = '';
            }
          })
        }
        .margin({ right: Sp.XS, bottom: Sp.XS })

        Row() {
          NativeChip({
            label: '/ 命令',
            active: this.panel === 'cmd',
            a11y: '运行命令',
            onTap: () => {
              this.panel = this.panel === 'cmd' ? '' : 'cmd';
              this.filter = '';
            }
          })
        }
        .margin({ right: Sp.XS, bottom: Sp.XS })

        Row() {
          Button() {
            SymbolGlyph($r('sys.symbol.paperclip')).fontSize(Sz.TOUCH_MIN / 2)
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('添加附件')
          .onClick(() => {
            this.onAddAttachment();
          })
        }
        .margin({ right: Sp.XS, bottom: Sp.XS })

        /*
         * ── 图片（P0-4）──
         *
         * 【为什么单独一个按钮】两条路的线上语义不同（文件=先上传拿会话作用域回执；
         * 图片=内联 base64，官方 `serializeImages()`），失败原因也不同 ⇒ 分开才说得清。
         * 图标用 `sys.symbol.picture`（**已在本机 CLT 的 `sysResource.js` 的 symbol 段里核对过**：
         * `paperclip` 与 `picture` 都在；猜一个名字会换来一个空白按钮，这是 E-symbol 的教训）。
         */
        Row() {
          Button() {
            SymbolGlyph($r('sys.symbol.picture')).fontSize(Sz.TOUCH_MIN / 2)
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('添加图片（随消息一起发送，不需要先上传）')
          .onClick(() => {
            this.onAddImage();
          })
        }
        .margin({ right: Sp.XS, bottom: Sp.XS })

        // ── 计划模式（官方 ui-plan：输入区的一级 chip；E202 的判据）──
        Row() {
          NativeChip({
            label: '计划',
            active: this.planOn(),
            a11y: `计划模式：${this.planOn() ? '已开启' : '已关闭'}，点击切换`,
            onTap: () => {
              this.onTogglePlan();
            }
          })
        }
        .margin({ right: Sp.XS, bottom: Sp.XS })

        /*
         * ── 权限模式：**能切就切，不能切就说"不可用"**（P7-6，对齐官方 permission-presets）──
         *
         * 官方把 `/permission` 装饰成 `popupSelect`：选中后执行 `/permission <presetId>`；
         * 而这台 Host 没有这个能力时，它显示的是官方字典里的 `unavailable`（「不可用」），
         * 连入口都不给。我们此前一律 `disabled: true` 挂着「权限：X（只读…）」——
         * 有能力的 Host 上白白少一个功能，没能力的 Host 上又看不出为什么点不了。
         *
         * 现在按 `permissionSwitchable(permissionsOptions)` 分两种呈现：
         *   · 有能力 ⇒ 可点的 chip，点了开单选浮层（复用既有 `ChoiceSheet`），选中后走
         *     `/permission <id>` 命令通道；
         *   · 没能力 ⇒ 仍然不可点，但文案是官方那句「不可用」，无障碍里写清"这台 Host 没有"。
         */
        if (this.permissionLabel.length > 0) {
          Row() {
            NativeChip({
              label: `权限：${this.permissionLabel}`,
              active: false,
              disabled: !this.permissionSwitchableNow,
              maxWidth: 160,
              a11y: this.permissionSwitchableNow
                ? `当前权限模式：${this.permissionLabel}，点击切换`
                : `权限：${this.permissionLabel}。${this.permissionHint}`,
              onTap: () => {
                if (this.permissionSwitchableNow) {
                  this.onPickPermission();
                }
              }
            })
          }
          .margin({ right: Sp.XS, bottom: Sp.XS })
        }
      }
      .layoutWeight(1)

      // ── 右组（官方的 `.trailing`）：模型。窄屏时会整组换到下一行，而不是被裁掉 ──
      Row() {
        NativeChip({
          label: this.modelLabel(),
          maxWidth: 160,
          a11y: `当前模型：${this.modelLabel()}，点击切换`,
          onTap: () => {
            this.onPickModel();
          }
        })
      }
      .margin({ bottom: Sp.XS })
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
                // 替换触发词区间（不是追加）；目录引用的未闭合引号不补空格，见 InputTrigger 的说明
                this.onDraftChange(this.draftAfterPick(c.insert));
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
                // 命令同理：替换掉正在输入的 `/co`，而不是把它留在前面
                this.onDraftChange(this.draftAfterPick(c.name));
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
    // 主操作按钮走 P1.5 原语：按下实效/焦点框/键盘可达性由 ArkUI 的 Button 提供；
    // 图标色用系统"底色之上"的语义色（此前写死 Color.White，换品牌色/深色模式就不一定对）。
    NativeButton({
      showIcon: true,
      iconSymbol: this.running ? $r('sys.symbol.xmark') : $r('sys.symbol.arrow_up'),
      iconSize: 18,
      square: true,
      emphasis: 'solid',
      tone: this.running ? 'danger' : 'brand',
      disabled: !(this.running || this.draft.trim().length > 0),
      a11y: this.running ? '停止当前轮次' : '发送消息',
      onTap: () => {
        if (this.running) {
          this.onStop();
        } else {
          this.onSend();
        }
      }
    })
  }

  /**
   * 依据输入内容自动切换弹层（输入 @ 开引用，输入 / 开头开命令）。
   *
   * 【P7-14：词法搬进了 `appstate/model/InputTrigger`】判据原先写在这里（三处内联判断），
   * 既测不到、又在"选中候选"那一侧需要**同一套**判据（否则插入位置与面板口径不一致）。
   * 现在识别与替换都由那个纯模型给结论，视图只负责开合面板与转发查询词。
   */
  private updateOverlay(value: string): void {
    const token: TriggerToken | undefined = detectTrigger(value);
    if (token !== undefined && token.kind === 'command') {
      this.panel = 'cmd';
      this.filter = token.query;
      return;
    }
    if (token !== undefined && token.kind === 'reference') {
      this.panel = 'ref';
      const changed: boolean = token.query !== this.filter;
      this.filter = token.query;
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
   * 选中一个候选 → 得到新的草稿。
   *
   * 【为什么必须替换而不是追加】P7-14 修的就是这个：`draft + insert` 会把用户已经敲出的
   * 半截查询词留在正文里（`@src/fo` + `@src/foo.ts` ⇒ `@src/fo@src/foo.ts `），
   * 而它长得像一条引用、会被 Host 当成引用去解析。官方的输入触发管线是**替换当前 token**
   * （`slash/input-consume-token` 带 `{kind:'span', span}`）。
   */
  private draftAfterPick(insert: string): string {
    const token: TriggerToken | undefined = detectTrigger(this.draft);
    return token === undefined ? appendPick(this.draft, insert) : applyPick(this.draft, token, insert);
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
