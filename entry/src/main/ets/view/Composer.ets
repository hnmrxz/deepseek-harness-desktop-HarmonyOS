/**
 * 输入区（Composer）—— D3 §3.6。
 *
 * ## v2 T015：按 DSH Mobile 源码级对照重塑（视觉/交互层）
 *
 * 【对照源文件】`.research/deepseek-harness-mobile/app/src/main/java/com/labteto/dshmobile/ui/screens/main/Composer.kt`
 * （`Composer` 卡片、`AttachmentStrip` / `FileAttachmentChip`、`PermissionChip`、`CircleAction`）。
 *
 * · **卡片形态**：`Surface(shape = DsShapes.composer, color = composerCard, border = 1dp borderL1)`
 *   → r22 圆角卡 + `composerCard` 填充 + `borderL1` 发丝边；内边距 `DsSpacing.MEDIUM`、
 *   内部间距 `DsSpacing.SMALL`（源码同值）。
 * · **输入框**：全宽多行（`maxLines = 8`）、`STD_14` 字阶、占位 `labelTertiary`、透明底
 *   （源码 `TextFieldDefaults.colors(…Transparent…)`）。
 * · **附件条**：图片 = 56dp 方块（`bgModulePlatform` 底 + r12）+ 右上 18dp 移除徽（`toastBg`）；
 *   文件 = 高 56、宽 120–200 的 chip（图标 + 名字 + 大小/状态），失败时 `error` 描边。
 * · **底行**：`+` 30dp（`hoverSolid`）→ 命令面板；权限 chip（`lock_shield` 14 + `SMALL_13` +
 *   `chevron_down` 12；「完全权限」时图标转 `warnLabel`，源码同判据）；spacer；
 *   **Send 常驻** 36dp（可发 → `buttonInfoFill` + 白箭头；不可发 → `buttonPrimaryDimmed`）；
 *   **运行中 Stop 并存** 36dp（`error` 底 + 白 11dp r3 方块）——源码注释明确：两者共槽
 *   会让运行中的会话无法排队/插话，所以发送常驻、停止加入而非替换。
 * · **模型 chip 已移除**（源码注释："The model selector is deliberately *not* here —
 *   it moved to the top bar"）→ 归 `ConversationHeader` 的 ModelChip（T014）。
 * · 无 Mobile 对应件的 v1 功能**全部保留接线**：@ 引用与 / 命令弹层、附件上传回执、
 *   图片内联、计划模式横幅、离线/能力提示、排队项管理、草稿触发词替换
 *   （`detectTrigger`/`applyPick`）；工具行保持**可换行 Flex**（门禁要求，防控件被裁掉）。
 * · 明暗色板：`mediaquery('(prefers-color-scheme: dark)')` + `dsPaletteOf(SYSTEM, dark)`。
 *
 * 本组件不直接调用协议层：所有动作通过回调上报给宿主，便于接入真实连接时只改宿主。
 */

import { Border, CommandCandidate, DsPalette, DsShape, DsSpacing, DsThemePreference, DsType, PendingAttachment, QueuedItem, ReferenceCandidate, dsPaletteOf, formatBytes, referenceQueryOf } from 'appstate';
import {
  COMMAND_PICK_RUN, appendPick, applyPick, commandPickAction, detectTrigger, referenceAgeLine, referenceCrumbs,
  referenceDrillQuery,
  referenceFileRowDetail, referenceFileRowName, referenceSessionRowDetail, referenceSessionRowName, TriggerToken
} from 'appstate';
import { GoalBar } from './GoalBar';
import { mediaquery } from '@kit.ArkUI';

/**
 * 附件平铺的**边长 / 徽标**（vp）。对照 `Composer.kt` `AttachmentStrip`：
 * `size(56.dp)` 方块 + 18dp 移除徽 + 12dp 徽内 `xmark`——DsSpacing 无 56/18/12* 档
 * （12 有 XSMALL_12 字阶但不是间距），照抄源码值并在此注明出处。
 */
const ATT_TILE: number = 56;
const ATT_BADGE: number = 18;
const ATT_BADGE_ICON: number = 12;
/** 文件 chip 的宽度区间（源码 `widthIn(min = 120.dp, max = 200.dp)`） */
const ATT_FILE_MIN_W: number = 120;
const ATT_FILE_MAX_W: number = 200;
/** 移除徽 / Stop 方块的图标白（源码字面 `Color.White`；ArkUI 侧以 0xAARRGGBB 常量承载） */
const WHITE_TINT: number = 0xFFFFFFFF;
/** Stop 方块的边长与圆角（源码 `size(11.dp)` + `RoundedCornerShape(3.dp)`） */
const STOP_SQUARE: number = 11;
const STOP_RADIUS: number = 3;
/**
 * 图标几何（vp）。对照 `Composer.kt` / `DsIconButton.kt` 的 iconSize 字面值：
 * `doc_text` 18、`paperclip`/`picture`/`arrow_up` 16、`plus`/`lock_shield` 14、
 * `chevron_down` 12——字阶 token（DsType）不表达图标边长，照抄源码值并在此注明。
 */
const ICON_DOC: number = 18;
const ICON_TOOL: number = 16;
const ICON_SMALL: number = 14;
const ICON_CHEVRON: number = 12;
/** 圆形动作钮直径（源码 `CircleAction` 30dp、Send/Stop 36dp；圆角 = 直径一半 → 全圆） */
const ACTION_PLUS: number = 30;
const ACTION_SEND: number = 36;

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
   * 当前档位（`Index` 发布到 AppStorage）。
   *
   * 产品口径：**手机端适度优化调整，其他端与官方 100% 一致**。
   * 权限 chip 的收窄与可见性**只在单栏生效**；平板/折叠展开/2in1 上保持带文字的完整形态。
   */
  @StorageProp('dshLayoutMode') layoutMode: string = 'single';
  /**
   * 当前会话的权限模式。
   *
   * 官方把它做成输入区的 `/permission` 弹层；本仓同款——切换走 `/permission <id>` 命令
   * （`onPickPermission` → 宿主开单选浮层）。Host 没这个能力时 chip 只读并显示官方
   * 字典的「不可用」，不做一个点了没反应的假入口。
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
  /**
   * 当前这份引用列表是**钻孔钻出来的**还是用户自己敲出来的（P9-5）。
   *
   * 官方 `crumbsFor` 的注释写明了这个区别的用途：钻孔是界面替用户换了路径，
   * 所以要给面包屑"还他一条回得去的路"；自己敲的路径上下文就在草稿里，不需要面包屑。
   */
  @State drilled: boolean = false;
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
  }

  aboutToDisappear(): void {
    this.darkQuery?.off('change');
    this.darkQuery = null;
  }

  /** 当前语义色板（MobileTheme 唯一视觉 token 源；SYSTEM 偏好随系统明暗切换） */
  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.dark);
  }

  /**
   * 发送是否可用。对照源码 `canSend`：
   * `enabled && !preparing && (draft.isNotBlank || attachments.isNotEmpty) && attachmentsSettled`。
   *
   * · `enabled` / `preparing`：本仓没有"输入区整体禁用"与"图片处理中"两个事实 ⇒ 恒真；
   * · `attachmentsSettled`：我们的文件附件**上传完成才入列**（`key` 就是回执），
   *   不存在源码那种 Uploading/Failed 中间态 ⇒ 恒真；
   * · 剩下的正文/附件判据照抄。
   */
  private canSend(): boolean {
    return this.draft.trim().length > 0 || this.attachments.length > 0;
  }

  /** 计划模式的**生效**值（官方判据：`pending ? !active : active`） */
  private planOn(): boolean {
    return this.planPending ? !this.planActive : this.planActive;
  }

  build() {
    Column({ space: DsSpacing.SMALL }) {
      /*
       * 【目标栏挂在这里，而不是挂在会话面板里（2026-09-17，第 50 轮换挂法）】
       *
       * 官方把「进行中的目标」放在**输入区正上方**。我们此前把它挂在 `ConversationPane`
       * 的 Composer 旁边（同级），结果**一行都不渲染**——而两边数据都是对的。
       * 换挂法的依据很直接：**Composer 每一帧都在重绘**（敲一个字、草稿变、附件变都会），
       * 而它自己渲染得好好的；目标栏挂在它内部，就搭上了这条确定的刷新路径。
       * 位置也仍然是"输入区上方"——与官方一致（没有目标时它整段不占位，见 D38 §5）。
       */
      GoalBar()

      if (this.offline) {
        this.offlineNotice()
      }

      if (this.notice.length > 0) {
        this.capabilityNotice()
      }

      if (this.planOn()) {
        this.planBanner()
      }

      if (this.queued.length > 0) {
        this.queuePanel()
      }

      /*
       * 卡片本体（对照 `Composer.kt` 的 `Surface`）：
       * r22（`DsShape.COMPOSER`）+ `composerCard` 填充 + `borderL1` 发丝边。
       */
      Column({ space: DsSpacing.SMALL }) {
        /*
         * 多行输入（对照源码 `TextField(minLines = 1, maxLines = 8, textStyle = std14)`）：
         * 全宽、透明底、占位 `labelTertiary`。E123：占位文案走资源 ⇒ 跟随系统语言。
         * 源码注释：字段是多行的，屏幕上的回车键就是换行——发送键是按钮，不在这里抢。
         */
        TextArea({
          text: this.draft,
          placeholder: this.offline
            ? $r('app.string.composer_placeholder_offline')
            : $r('app.string.composer_placeholder')
        })
          .onChange((value: string) => {
            this.onDraftChange(value);
            // 自己敲的字 ⇒ 不是钻孔（面包屑只服务"界面替你换了路径"那种情况）
            this.drilled = false;
            this.updateOverlay(value);
          })
          .fontSize(DsType.STD_14.size)
          .fontColor(this.palette().labelPrimary)
          .placeholderColor(this.palette().labelTertiary)
          .backgroundColor(Color.Transparent)
          .padding(0)
          // maxLines 8（源码同值）：上限高度 = 行高 × 8
          .constraintSize({
            minHeight: DsType.STD_14.lineHeight,
            maxHeight: DsType.STD_14.lineHeight * 8
          })
          .width('100%')
          .accessibilityText('消息输入框')

        if (this.attachments.length > 0) {
          this.attachmentStrip()
        }

        this.toolRow()

        this.actionRow()
      }
      .width('100%')
      .padding(DsSpacing.MEDIUM)
      .backgroundColor(this.palette().composerCard)
      .borderRadius(DsShape.COMPOSER)
      .borderWidth(Border.HAIRLINE)
      .borderColor(this.palette().borderL1)

      if (this.panel.length > 0) {
        this.overlayPanel()
      }
    }
    .width('100%')
    // 源码 Surface 外距：horizontal = medium, vertical = small
    .padding({
      left: DsSpacing.MEDIUM,
      right: DsSpacing.MEDIUM,
      top: DsSpacing.SMALL,
      bottom: DsSpacing.SMALL
    })
  }

  @Builder
  offlineNotice() {
    Row({ space: DsSpacing.SMALL }) {
      SymbolGlyph($r('sys.symbol.wifi_slash'))
        .fontSize(DsType.SMALL_13.size)
        .fontColor([this.palette().warnLabel])
      Text(this.queuedCount > 0
        ? `离线中：已排队 ${this.queuedCount} 条，连接恢复后按序发送`
        : '离线中：发送的消息将在连接恢复后按序发送')
        .fontSize(DsType.SMALL_13.size)
        .fontColor(this.palette().warnLabel)
        .layoutWeight(1)
    }
    .width('100%')
    .padding(DsSpacing.SMALL)
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().warnTertiary)
  }

  @Builder
  queuePanel() {
    Column({ space: DsSpacing.XSMALL }) {
      Row({ space: DsSpacing.SMALL }) {
        Text(`待发队列 ${this.queued.length} 条`)
          .fontSize(DsType.SMALL_13.size)
          .fontColor(this.palette().labelTertiary)
          .layoutWeight(1)
        Text('由 Host 维护')
          .fontSize(DsType.CAPTION_11.size)
          .fontColor(this.palette().labelTertiary)
      }
      .width('100%')

      ForEach(this.queued, (item: QueuedItem) => {
        Column({ space: DsSpacing.XSMALL }) {
          Text(item.text)
            .fontSize(DsType.SMALL_13.size)
            .fontColor(this.palette().labelPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row({ space: DsSpacing.MEDIUM }) {
            Text('取回编辑')
              .fontSize(DsType.CAPTION_11.size)
              .fontColor(this.palette().accent)
              .onClick(() => {
                this.onPullQueued(item.id, item.text);
              })
            Text(placementLabel(item.placement))
              .fontSize(DsType.CAPTION_11.size)
              .fontColor(this.palette().labelTertiary)
            Blank()
            Text('插话')
              .fontSize(DsType.CAPTION_11.size)
              .fontColor(this.palette().accent)
              .onClick(() => {
                this.onSteerQueued(item.id);
              })
            Text('移除')
              .fontSize(DsType.CAPTION_11.size)
              .fontColor(this.palette().error)
              .onClick(() => {
                this.onRemoveQueued(item.id);
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(DsSpacing.SMALL)
        .borderRadius(DsShape.BLOCK)
        .backgroundColor(this.palette().bgModulePlatform)
      }, (item: QueuedItem) => item.id)
    }
    .width('100%')
  }

  @Builder
  capabilityNotice() {
    Row({ space: DsSpacing.SMALL }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(DsType.SMALL_13.size)
        .fontColor([this.palette().labelSecondary])
      Text(this.notice)
        .fontSize(DsType.SMALL_13.size)
        .fontColor(this.palette().labelSecondary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding(DsSpacing.SMALL)
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().bgModulePlatform)
    .accessibilityText(this.notice)
  }

  /**
   * 计划模式**生效中**的横幅（T030，FR-010 / spec 场景 4）。
   *
   * 【为什么 chip 之外还要一条横幅】spec 的场景 4 要求"输入区整体进入计划模式的
   * 视觉状态"，而不只是一个高亮的 chip：开关打开意味着**接下来的消息会走另一条
   * 流程**（先出计划、等确认再执行），这件事不写出来，第一次用的用户只会看到
   * "回复变奇怪了"。chip 的实底回答"开关开着没"，横幅回答"开了会发生什么"。
   *
   * 【如实登记】官方 Web **没有**这条横幅的先例（输入区只有 chip）——这是我们按
   * FR-010 主动补的告知，文案只陈述 plan-review 的实际语义（"先给出计划，待你确认
   * 后再执行"），不承诺官方没有的按钮；差异应登记在 parity 矩阵的 plan 行。
   */
  @Builder
  planBanner() {
    Row({ space: DsSpacing.SMALL }) {
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(DsType.SMALL_13.size)
        .fontColor([this.palette().accent])
      Text('计划模式已开启：发送后助手会先给出计划，待你确认后再执行。')
        .fontSize(DsType.SMALL_13.size)
        .fontColor(this.palette().labelSecondary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding(DsSpacing.SMALL)
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().accentTertiary)
    .accessibilityText('计划模式已开启：发送后助手会先给出计划，待你确认后再执行。')
  }

  /**
   * 附件条（对照 `AttachmentStrip` / `FileAttachmentChip`）：
   * 图片 = 56dp 方块缩略图；文件 = 56dp 高的 chip（图标 + 名字 + 大小）。
   * 两者右上角同款 18dp 移除徽（`toastBg` 底 + 白 `xmark`）——源码让移除位置
   * 在**每一种**附件上都在同一个地方，手指不用重新找。
   */
  @Builder
  attachmentStrip() {
    Scroll() {
      Row({ space: DsSpacing.SMALL }) {
        ForEach(this.attachments, (item: PendingAttachment) => {
          Stack({ alignContent: Alignment.TopEnd }) {
            if (attachmentPreview(item).length > 0) {
              Image(attachmentPreview(item))
                .width(ATT_TILE)
                .height(ATT_TILE)
                .objectFit(ImageFit.Cover)
                .borderRadius(DsShape.BLOCK)
                .backgroundColor(this.palette().bgModulePlatform)
                .accessibilityText(`图片预览：${item.name}`)
            } else {
              Row({ space: DsSpacing.SMALL }) {
                SymbolGlyph($r('sys.symbol.doc_text'))
                  .fontSize(ICON_DOC)
                  .fontColor([this.palette().labelSecondary])
                Column() {
                  Text(item.name)
                    .fontSize(DsType.SMALL_13.size)
                    .fontColor(this.palette().labelPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(attachmentLabel(item))
                    .fontSize(DsType.CAPTION_11.size)
                    .fontColor(this.palette().labelTertiary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
              }
              .height(ATT_TILE)
              .constraintSize({ minWidth: ATT_FILE_MIN_W, maxWidth: ATT_FILE_MAX_W })
              .padding({ left: 10, right: 22 })
              .borderRadius(DsShape.BLOCK)
              .backgroundColor(this.palette().bgModulePlatform)
              .borderWidth(Border.HAIRLINE)
              .borderColor(this.palette().borderL3)
              .alignItems(VerticalAlign.Center)
            }
            // 移除徽（两种附件同一个位置、同一个形状）
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(ATT_BADGE_ICON)
                .fontColor([WHITE_TINT])
            }
            .width(ATT_BADGE)
            .height(ATT_BADGE)
            .borderRadius(ATT_BADGE / 2)
            .backgroundColor(this.palette().toastBg)
            .accessibilityText(item.kind === 'file' ? '移除文件附件' : '移除图片')
            .onClick(() => {
              // 以**行身份 `key`** 移除，而不是文件名：同名文件可以加两次，
              // 按名字移除会一次删掉两个（用户以为只删了一个）。
              // 图片没有回执，它的 key 是客户端草稿 id（P0-4）。
              this.onRemoveAttachment(item.key);
            })
          }
        }, (item: PendingAttachment) => item.key)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  /**
   * 工具行：@ / / / 附件 / 图片 / 计划。
   *
   * 【与 Mobile 源码的关系】`Composer.kt` 把这些收进 `+` 弹层（底行那颗 30dp 的 +）；
   * 我们的 `+` 只开**命令**面板，引用/附件/图片/计划保留为显式入口——这是 v1 功能
   * 接线的保留（任务约束：附件上传、Plan、@引用、popupSelect 命令一个不少），
   * 差异登记 parity 矩阵。
   *
   * ## 为什么是**可换行的 Flex**，而不是一行 `Row` + `Blank()`
   *
   * 一行 `Row` 里不放 `layoutWeight` 的子元素**不会缩**：手机上（360vp）这一行的固定宽度
   * 加起来可能超过屏宽，于是最右边的控件被挤出屏幕。这正是 `docs/08` P0 §7 点名的
   * 那类缺陷：「操作区被内容挤压时不得静默消失」。放不下时整组换行，控件一个不少。
   *
   * 间距用子元素的 margin（`space` 只在主轴方向生效，跨行间距得靠 margin 才一致）。
   */
  @Builder
  toolRow() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text(this.layoutMode === 'single' ? '@' : '@ 引用')
        .fontSize(DsType.SMALL_13.size)
        .fontColor(this.panel === 'ref' ? this.palette().accent : this.palette().labelTertiary)
        .padding({
          left: DsSpacing.SMALL,
          right: DsSpacing.SMALL,
          top: DsSpacing.TINY,
          bottom: DsSpacing.TINY
        })
        .borderRadius(DsShape.PILL)
        .backgroundColor(this.panel === 'ref' ? this.palette().accentTertiary : Color.Transparent)
        .accessibilityText('插入文件或会话引用')
        .onClick(() => {
          this.panel = this.panel === 'ref' ? '' : 'ref';
          this.filter = '';
        })
        .margin({ right: DsSpacing.XSMALL, bottom: DsSpacing.XSMALL })

      Text(this.layoutMode === 'single' ? '/' : '/ 命令')
        .fontSize(DsType.SMALL_13.size)
        .fontColor(this.panel === 'cmd' ? this.palette().accent : this.palette().labelTertiary)
        .padding({
          left: DsSpacing.SMALL,
          right: DsSpacing.SMALL,
          top: DsSpacing.TINY,
          bottom: DsSpacing.TINY
        })
        .borderRadius(DsShape.PILL)
        .backgroundColor(this.panel === 'cmd' ? this.palette().accentTertiary : Color.Transparent)
        .accessibilityText('运行命令')
        .onClick(() => {
          this.panel = this.panel === 'cmd' ? '' : 'cmd';
          this.filter = '';
        })
        .margin({ right: DsSpacing.XSMALL, bottom: DsSpacing.XSMALL })

      /*
       * ── 附件（文件）── 图标名 `paperclip` 已在 sysResource.js 核对过（E-symbol 教训：
       * 猜一个名字会换来一个空白按钮）。
       */
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.paperclip'))
          .fontSize(ICON_TOOL)
          .fontColor([this.palette().labelSecondary])
      }
      .constraintSize({ minWidth: 32, minHeight: 32 })
      .accessibilityText('添加附件')
      .onClick(() => {
        this.onAddAttachment();
      })
      .margin({ right: DsSpacing.XSMALL, bottom: DsSpacing.XSMALL })

      /*
       * ── 图片（P0-4）──
       *
       * 【为什么单独一个按钮】两条路的线上语义不同（文件=先上传拿会话作用域回执；
       * 图片=内联 base64，官方 `serializeImages()`），失败原因也不同 ⇒ 分开才说得清。
       */
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(ICON_TOOL)
          .fontColor([this.palette().labelSecondary])
      }
      .constraintSize({ minWidth: 32, minHeight: 32 })
      .accessibilityText('添加图片（随消息一起发送，不需要先上传）')
      .onClick(() => {
        this.onAddImage();
      })
      .margin({ right: DsSpacing.XSMALL, bottom: DsSpacing.XSMALL })

      /*
       * ── 计划模式（官方 ui-plan：输入区的一级 chip；E202 的判据）──
       * 开启 = `accentTertiary` 实底 + `accent` 文字：开关型 chip 与命令/引用那类
       * 瞬时面板 chip 在观感上可分。
       */
      Text('计划')
        .fontSize(DsType.SMALL_13.size)
        .fontColor(this.planOn() ? this.palette().accent : this.palette().labelTertiary)
        .padding({
          left: DsSpacing.SMALL,
          right: DsSpacing.SMALL,
          top: DsSpacing.TINY,
          bottom: DsSpacing.TINY
        })
        .borderRadius(DsShape.PILL)
        .backgroundColor(this.planOn() ? this.palette().accentTertiary : Color.Transparent)
        .accessibilityText(`计划模式：${this.planOn() ? '已开启' : '已关闭'}，点击切换`)
        .onClick(() => {
          this.onTogglePlan();
        })
        .margin({ bottom: DsSpacing.XSMALL })
    }
    .width('100%')
    .accessibilityText(this.permissionSwitchableNow
      ? `工具行：引用、命令、附件、图片、计划、权限${this.permissionLabel}`
      : `工具行：引用、命令、附件、图片、计划。${this.permissionHint}`)
  }

  /**
   * 底行（对照源码的 `Row(CircleAction(+), PermissionChip, Spacer, ContextMeter, Send, Stop)`）：
   * `+` 开命令面板；权限 chip；右侧 **Send 常驻** + **运行中 Stop 并存**。
   *
   * ContextMeter（源码 44×6 的上下文计量条）无对应数据源，跳过——没有 `contextBreakdown`
   * 投影可画，画一根假条比不画更糟。
   */
  @Builder
  actionRow() {
    Row({ space: DsSpacing.COMPACT }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(ICON_SMALL)
          .fontColor([this.palette().labelPrimary])
      }
      .width(ACTION_PLUS)
      .height(ACTION_PLUS)
      .borderRadius(ACTION_PLUS / 2)
      .backgroundColor(this.palette().hoverSolid)
      .accessibilityText('命令面板')
      .onClick(() => {
        this.panel = this.panel === 'cmd' ? '' : 'cmd';
        this.filter = '';
      })

      /*
       * ── 权限 chip（对照 `PermissionChip`）──
       *
       * 可见性沿用 v1 判定：**只有真能切的时候才出现**（单栏）——"这台 Host 没有权限预设"
       * 这件事在设置里已有一行如实说明，没必要在输入区再占一格；非单栏与官方一致，
       * 有值就显示。
       */
      if (this.permissionLabel.length > 0
        && (this.layoutMode !== 'single' || this.permissionSwitchableNow)) {
        Row({ space: DsSpacing.TINY }) {
          /*
           * 「完全权限」转警示色（源码判据：`effective == FULL_ACCESS_PRESET` 时图标
           * `warnLabel`）——我们的 label 是宿主拼好的显示文案，取值里含「完全权限」
           * 即视为同一档（启发式，注释如源码一样写明）。
           */
          SymbolGlyph($r('sys.symbol.lock_shield'))
            .fontSize(ICON_SMALL)
            .fontColor([this.permissionLabel.indexOf('完全权限') >= 0
              ? this.palette().warnLabel : this.palette().labelTertiary])
          Text(this.permissionLabel)
            .fontSize(DsType.SMALL_13.size)
            .fontColor(this.palette().labelSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: this.layoutMode === 'single' ? 84 : 160 })
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(ICON_CHEVRON)
            .fontColor([this.palette().labelTertiary])
        }
        .padding({
          left: DsSpacing.SMALL,
          right: DsSpacing.SMALL,
          top: DsSpacing.TINY,
          bottom: DsSpacing.TINY
        })
        .borderRadius(DsShape.CUBE)
        .accessibilityText(this.permissionSwitchableNow
          ? `当前权限模式：${this.permissionLabel}，点击切换`
          : `权限：${this.permissionLabel}。${this.permissionHint}`)
        .onClick(() => {
          if (this.permissionSwitchableNow) {
            this.onPickPermission();
          }
        })
      }

      Blank()

      /*
       * Send 常驻（源码注释：与 Stop 共槽会让运行中的会话**没有任何发送途径**——
       * Host 本来就允许 `mode: queue|steer` 的中途提示词）。
       * 可发 → `buttonInfoFill` + 白箭头；不可发 → `buttonPrimaryDimmed` + `labelTertiary`。
       */
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.arrow_up'))
          .fontSize(ICON_TOOL)
          .fontColor([this.canSend() ? WHITE_TINT : this.palette().labelTertiary])
      }
      .width(ACTION_SEND)
      .height(ACTION_SEND)
      .borderRadius(ACTION_SEND / 2)
      .backgroundColor(this.canSend()
        ? this.palette().buttonInfoFill : this.palette().buttonPrimaryDimmed)
      .accessibilityText('发送消息')
      .onClick(() => {
        if (this.canSend()) {
          this.onSend();
        }
      })

      /*
       * Stop 只在运行中出现，且**不占 Send 的位置**（源码注释：停止的手势永远在
       * 老地方，发送出现在它旁边而不是已经在按停的那根拇指下面）。
       */
      if (this.running) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(STOP_SQUARE)
            .height(STOP_SQUARE)
            .borderRadius(STOP_RADIUS)
            .backgroundColor(WHITE_TINT)
        }
        .width(ACTION_SEND)
        .height(ACTION_SEND)
        .borderRadius(ACTION_SEND / 2)
        .backgroundColor(this.palette().error)
        .accessibilityText('停止当前轮次')
        .onClick(() => {
          this.onStop();
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  overlayPanel() {
    Column() {
      /*
       * 面板标题：钻孔时显示**面包屑**（官方 `header()` 只对钻孔列表给 crumbs，
       * 根标签逐字取官方字典的 `crumb.root` = 工作区），否则显示原来的动作名。
       *
       * §FR-007：面包屑可点击回溯——点击面包屑的任意一级可导航回该层级。
       */
      if (this.panel === 'ref' && this.drilled) {
        Row({ space: 2 }) {
          ForEach(referenceCrumbs(this.filter, this.drilled), (crumb: string, idx: number) => {
            if (idx > 0) {
              Text(' › ')
                .fontSize(DsType.SMALL_13.size)
                .fontColor(this.palette().labelTertiary)
            }
            Text(crumb)
              .fontSize(DsType.SMALL_13.size)
              .fontColor(idx === referenceCrumbs(this.filter, this.drilled).length - 1
                ? this.palette().labelPrimary
                : this.palette().accent)
              .onClick(() => {
                // 点击非末级面包屑 → 回退到该层级（重新查询）
                if (idx < referenceCrumbs(this.filter, this.drilled).length - 1) {
                  this.drilled = idx === 0 ? false : true;
                  // 回到工作区根级
                  if (idx === 0) {
                    this.filter = '';
                  }
                }
              })
          }, (crumb: string, idx: number) => `${idx}`)
        }
        .width('100%')
        .padding({ bottom: DsSpacing.XSMALL })
      } else {
        Text(this.panel !== 'ref' ? '运行命令' : '插入引用')
          .fontSize(DsType.SMALL_13.size)
          .fontColor(this.palette().labelTertiary)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ bottom: DsSpacing.XSMALL })
      }

      List({ space: DsSpacing.XSMALL }) {
        if (this.panel === 'ref') {
          ForEach(this.filteredReferences(), (c: ReferenceCandidate) => {
            ListItem() {
              Column({ space: 2 }) {
                Row({ space: DsSpacing.SMALL }) {
                  Text(`@${c.kind}`)
                    .fontSize(DsType.SMALL_13.size)
                    .fontColor(this.palette().accent)
                  Text(this.refRowName(c))
                    .fontSize(DsType.STD_14.size)
                    .fontColor(this.palette().labelPrimary)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                if (this.refRowDetail(c).length > 0) {
                  Text(this.refRowDetail(c))
                    .fontSize(DsType.SMALL_13.size)
                    .fontColor(this.palette().labelTertiary)
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .width('100%')
              .padding(DsSpacing.SMALL)
              .borderRadius(DsShape.ROW)
              .onClick(() => {
                // 替换触发词区间（不是追加）；目录引用的未闭合引号不补空格，见 InputTrigger 的说明
                const next: string = this.draftAfterPick(c.insert);
                this.onDraftChange(next);
                /*
                 * 【P9-5：选中目录 = **钻孔**，菜单不关】官方 `onPick` 对目录返回
                 * `{text, continue: true}`：菜单接着列这个目录的内容。我们此前一律 `panel = ''`
                 * ⇒ 选一个文件夹之后菜单就关了，"目录可钻取"在界面上等于没有。
                 */
                if (c.kind === 'directory') {
                  this.panel = 'ref';
                  this.drilled = true;
                  const query: string = referenceDrillQuery(next);
                  this.filter = query;
                  this.onReferenceQuery(query);
                  return;
                }
                this.panel = '';
                this.drilled = false;
              })
            }
          }, (c: ReferenceCandidate) => `${c.kind}:${c.label}`)
        } else {
          ForEach(this.filteredCommands(), (c: CommandCandidate) => {
            ListItem() {
              Row({ space: DsSpacing.SMALL }) {
                Text(c.name)
                  .fontSize(DsType.STD_14.size)
                  .fontColor(this.palette().accent)
                if (c.args.length > 0) {
                  Text(c.args)
                    .fontSize(DsType.SMALL_13.size)
                    .fontColor(this.palette().labelTertiary)
                }
                Text(c.detail)
                  .fontSize(DsType.SMALL_13.size)
                  .fontColor(this.palette().labelSecondary)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding(DsSpacing.SMALL)
              .borderRadius(DsShape.ROW)
              .onClick(() => {
                /*
                 * 【F24/D51 §4·§5：输入区斜杠菜单要与命令面板**同一套判定**】
                 *
                 * 此前这里只做一件事——把命令名填进草稿（`/export` 留在输入框里不动）。
                 * 于是"选中一条**免参**命令"什么都不会发生，用户只能自己再按一次发送；
                 * 而按了发送，命令又会被当成提示词发给模型（那一条已在 `sendDraft()` 里修掉）。
                 *
                 * 现在按宿主给的权威信号分流（`CommandDescriptor.input` → `CommandCandidate.args`）：
                 *   · 需要参数 ⇒ 只填草稿（用户接着打参数），与面板一致；
                 *   · 不需要参数 ⇒ 填草稿后**立刻走发送那条路**——`sendDraft()` 已经会识别
                 *     "整条草稿是一条命令"并改道 `commands/execute`，所以这里不必再引一套执行通道
                 *     （少一条通道就少一处会跑偏的地方）。
                 */
                const next: string = this.draftAfterPick(c.name);
                this.panel = '';
                this.onDraftChange(next);
                if (commandPickAction(c.args) === COMMAND_PICK_RUN) {
                  this.onSend();
                }
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
    .padding(DsSpacing.SMALL)
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().bgModulePlatform)
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
      /*
       * 查询词要**规范化**（剥掉 `@"` 的引号，见 `referenceQueryOf` 的说明）：
       * 官方把"带不带引号"作为单独标志传给候选源，query 里没有引号；
       * 而我们的词法把引号留在了 query 里 ⇒ 直接发给 Host 会匹配不上（带空格的路径必须用引号写法，
       * 于是菜单恰好在那最需要它的场景下空着）。
       */
      const query: string = referenceQueryOf(token.query);
      const changed: boolean = query !== this.filter;
      this.filter = query;
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

  /** 引用行的主文案（官方 `fileCandidate` 的 `name`：目录名带尾斜杠） */
  private refRowName(c: ReferenceCandidate): string {
    if (c.kind === 'session') {
      // F15：Host 对**还没有标题**的会话给的 `label` 就是 sessionId ⇒ 回落「未命名会话」，
      // 判据在纯模型里（`referenceSessionRowName`），视图不自己写判断
      return referenceSessionRowName(c.label);
    }
    return referenceFileRowName(c.label, c.kind === 'directory');
  }

  /**
   * 引用行的次要文案（官方 `fileCandidate` 的父目录 / `sessionCandidate` 的「位置 · 时间」）。
   *
   * 文件：**只有未钻孔时**显示父目录（钻孔之后用户已经在那个目录里，再写一遍是噪声）。
   * 会话：位置（同工作区不显示、没有 cwd 写「无工作目录」）+ 相对时间（官方 `{n}分钟` 那套措辞）。
   */
  private refRowDetail(c: ReferenceCandidate): string {
    if (c.kind === 'session') {
      const age: string = referenceAgeLine(c.createdAt, Date.now());
      return referenceSessionRowDetail(c.detail, c.sameWorkspace, age);
    }
    return referenceFileRowDetail(c.label, !this.drilled);
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
}
