/**
 * HarmonyOS 原生原语（P1.5）——视图层共用的最小构件。
 *
 * ## 对照源文件（T017：DSH Mobile 的设计基元层）
 *
 * `.research/deepseek-harness-mobile/app/src/main/java/com/labteto/dshmobile/ui/components/`
 * ——`DsButton.kt` / `DsCard.kt` / `DsPill.kt` / `DsSegmented.kt` / `DsIconButton.kt` /
 * `DsBottomSheet.kt` / `EmptyHero.kt` / `SectionHeader.kt` / `StateDot.kt` / `Shimmer.kt` /
 * `ToggleRow.kt` / `DisclosureRow.kt` / `ContextMeter.kt` / `RelativeTime.kt`；
 * 文字相关取 `ui/theme/Type.kt`（字阶与字体栈）。
 * **每个构件的头注释各自再标一次它对照的那个 `.kt`**——本行只是文件级的索引。
 *
 * ## 为什么要有这一层
 *
 * 在它之前，"一个 chip"在各处被重写了 5 次：字号、内距、圆角、底色、选中色、
 * 无障碍文案每处一套。于是同一个概念在不同面板里长得不一样，而**改一次要改五处**。
 * 本层的目标不是"好看"，是**同一个概念只有一处实现**。
 *
 * ## 与 HarmonyTheme 的分工
 *
 * `HarmonyTheme` 只说"用哪个令牌"，本文件说"这个控件长什么样"。
 * 颜色/尺寸/圆角/动效一律取自 `HarmonyTheme`，**这里不出现裸数字**——
 * `tools/check-design-tokens.mjs` 会盯着这一点（棘轮：裸值只许变少）。
 *
 * ## 交互语义：触控与指针同一套
 *
 * 每个可点构件都做三件事：可点面积 ≥ 触控底线、有按压反馈、有无障碍文案。
 * 不在构件里写 `if (设备是手机)`——设备差异属于布局层（`LayoutController`）与输入层（P3）。
 */

import type { ShadowLevel, DsSpringSpec, DsTweenSpec, DsTypeRole } from 'appstate';
import {
  HarmonyBorder,
  HarmonyColor,
  HarmonyElevation,
  HarmonyIconSize,
  HarmonyMotion,
  HarmonyRadius,
  HarmonySpacing,
  HarmonyTouch,
  HarmonyType,
  DsAnimation,
  DsColor,
  DsPalette,
  DsScale,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  dsPaletteOf
} from 'appstate';
import { curves, mediaquery } from '@kit.ArkUI';

/**
 * 轻量标签/操作构件（官方 Web 叫 chip，鸿蒙侧就用原生观感表达）。
 *
 * 用途：工具行入口（@ 引用 / 命令 / 计划 / 权限 / 模型）、反馈类别、状态标签。
 */
@Component
export struct NativeChip {
  @Prop label: string = '';
  /** 选中态（品牌色文字 + 更实的底） */
  @Prop active: boolean = false;
  /**
   * 实底选中态（T030，仅开关型 chip 使用）：`active && filled` 时品牌**实底** + 反色文字。
   *
   * 【与普通 active 的分工】官方 Web 的 chip 有两种选中观感：
   *   · **瞬时面板型**（命令 / 权限 / 引用）：展开期间高亮，底色变实、文字变品牌色——
   *     就是上面的普通 `active`；
   *   · **开关型**（Plan 这类"打开后持续生效"的切换）：官方用
   *     `--dsw-color-badge-bg`（品牌实底）+ `--dsw-color-badge-text`（反色文字），
   *     即 `HarmonyTheme` 的 WEB_TOKEN_MAP 里 badge 两行的映射。
   * 不分开的话，"面板正开着"和"开关已经开了"长得一模一样，用户分不清
   * 哪个状态会随关闭面板一起消失。
   */
  @Prop filled: boolean = false;
  /** 语气：neutral | alert。只有"需要注意"的才用 alert，避免满屏彩色 */
  @Prop tone: string = 'neutral';
  /** 是否禁用（不可用时也**说明原因**由调用方给 accessibilityText） */
  @Prop disabled: boolean = false;
  /** 无障碍文案（缺省用 label；调用方应给出"点击会发生什么"） */
  @Prop a11y: string = '';
  /** 最宽（长模型名/长路径要截断，而不是把工具栏顶开） */
  @Prop maxWidth: number = 180;
  onTap: () => void = () => {
  };

  private textColor(): Resource {
    if (this.disabled) {
      return HarmonyColor.TEXT_TERTIARY;
    }
    if (this.active) {
      return this.filled ? HarmonyColor.ON_BRAND_TEXT : HarmonyColor.BRAND;
    }
    if (this.tone === 'alert') {
      return HarmonyColor.ALERT;
    }
    return HarmonyColor.TEXT_SECONDARY;
  }

  private chipBgColor(): Resource {
    if (this.active) {
      return this.filled ? HarmonyColor.BRAND : HarmonyColor.SURFACE_TERTIARY;
    }
    return HarmonyColor.SURFACE_RAISED;
  }

  build() {
    Text(this.label)
      .fontSize(HarmonyType.LABEL.size)
      .fontWeight(this.active ? 500 : 400)
      .fontColor(this.textColor())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: this.maxWidth })
      .padding({
        left: HarmonySpacing.CONTROL_INNER,
        right: HarmonySpacing.CONTROL_INNER,
        top: HarmonySpacing.INLINE,
        bottom: HarmonySpacing.INLINE
      })
      .borderRadius(HarmonyRadius.CHIP)
      .backgroundColor(this.chipBgColor())
      .animation({ duration: HarmonyMotion.STATE })
      // 触控底线：文字 chip 的高度由内距撑起，这里确保可点高度不缩水
      .constraintSize({ minHeight: HarmonyTouch.MIN_TARGET })
      .textAlign(TextAlign.Center)
      .accessibilityText(this.a11y.length > 0 ? this.a11y : this.label)
      .enabled(!this.disabled)
      .onClick(() => {
        if (!this.disabled) {
          this.onTap();
        }
      })
  }
}

/**
 * 区块标题（页内小节）。
 *
 * 【为什么要一个构件】此前各面板自己写 `.fontSize(Fs.BODY).fontWeight(Medium)`——
 * 值一样、名字不一样，于是没人能回答"小节标题到底是哪一档"。
 */
@Component
export struct NativeSectionTitle {
  @Prop text: string = '';
  /** 右侧次要说明（可选） */
  @Prop hint: string = '';

  build() {
    Row({ space: HarmonySpacing.INLINE }) {
      Text(this.text)
        .fontSize(HarmonyType.SUBTITLE.size)
        .fontWeight(HarmonyType.SUBTITLE.weight)
        .lineHeight(HarmonyType.SUBTITLE.lineHeight)
        .fontColor(HarmonyColor.TEXT_PRIMARY)
        .layoutWeight(1)
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(HarmonyType.CAPTION.size)
          .fontColor(HarmonyColor.TEXT_TERTIARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
  }
}


/**
 * 半模态 Sheet 的统一参数（P1.5 的 NativeSheet）。
 *
 * 【为什么是"参数助手"而不是包装组件】ArkUI 的 Sheet 是**组件属性**（`.bindSheet(...)`），
 * 不是可以独立摆放的组件；而本项目在真机上踩过「`@BuilderParam` 注入父 Builder 导致 JS 崩溃」
 * （D4 记载，SettingsPane 因此改成直接传属性）。把 Sheet 包成一个需要注入 Builder 的组件，
 * 等于把那个已知的坑重新引入。统一**参数**（高度/拖拽条/关闭按钮/消失回调）同样能拿到
 * "全应用的 Sheet 观感一致"这份收益，且没有那个风险。
 *
 * 【消失回调为什么必填】`bindSheet(isShow, …)` 的 `isShow` 是**单向**的：用户下拉关闭或点关闭按钮时，
 * 组件内部并不会把调用方的状态改回去。不同步的话，调用方的 `show` 会永远停在 true，
 * 于是 **Sheet 再也打不开**（看起来像"点了没反应"）。所以这里强制要求传入状态复位回调。
 */
export function harmonySheetOptions(onGone: () => void, height: SheetSize = SheetSize.MEDIUM): SheetOptions {
  const options: SheetOptions = {
    height: height,
    dragBar: true,
    showClose: true,
    // 关闭路径统一在这里收敛：拖拽/关闭按钮/点击遮罩都会走到它
    shouldDismiss: (dismiss: SheetDismiss) => {
      onGone();
      dismiss.dismiss();
    }
  };
  return options;
}


/**
 * 原生卡片：会话里的"一类事件"（工具调用 / 子代理 / 交付物 / 目标 / 任务）统一用它表达。
 *
 * ## 为什么是**参数驱动**而不是"通用容器 + 内容注入"
 *
 * ArkUI 里给容器注入内容的常规做法是 `@BuilderParam`（尾随闭包）。但本项目在真机上踩过
 * 「`@BuilderParam` 注入父 Builder → 展开该区块时 JS 崩溃」（D4 记载，SettingsPane 因此改成直传属性）。
 * 在**没有真机可验**的阶段，把一个已知会崩的机制铺到会话主视图上是不负责任的。
 * 而这几类卡片的结构其实**高度同构**（图标 + 名称 + 状态 + 次要信息 + 摘要 + 可折叠结果），
 * 于是参数驱动反而得到更清晰的 API：调用方只说"是什么"，不再各写一遍内距/圆角/边框。
 *
 * ## 空间层级（而不是网页卡片堆叠）
 *
 * 鸿蒙侧的层次靠**材质与微阴影**表达，不靠"画一圈边框"。因此：
 *   · 常规/成功：无边框，仅一层浅底 + FLAT 阴影；
 *   · 运行中：品牌色做小面积强调（图标+状态字），并把阴影抬到 RAISED——"正在进行"靠**动势**而不是靠边框；
 *   · 失败/被拒：保留 alert 描边——这是**例外状态**，值得被一眼看到，边框在这里是有信息的。
 * 边框从"每张卡都画"变成"只在异常时出现"，卡片堆叠的噪声就降下来了。
 */
@Component
export struct NativeCard {
  /** 图标（系统符号；调用方按事件类型给） */
  @Prop iconSymbol: Resource = $r('sys.symbol.circle');
  /** 名称（工具名 / 子代理名 / 文件名） */
  @Prop title: string = '';
  /** 状态徽标文字（运行中 / 成功 / 失败 / 被拒…） */
  @Prop badge: string = '';
  /** 语气：neutral | running | success | failed | warning */
  @Prop tone: string = 'neutral';
  /** 次要信息（钟点 · 时长 / 大小 / 路径） */
  @Prop meta: string = '';
  /** 参数摘要（等宽单行，超出省略） */
  @Prop summary: string = '';
  /** 结果正文（已由调用方截断/预览；空串表示没有结果） */
  @Prop bodyText: string = '';
  /**
   * 逐行正文（改动对照用），与 `diffKinds` **按下标一一对应**。
   *
   * 【为什么单独一条通道】改动对照的价值一半在"哪些行加了、哪些行删了"，
   * 而这件事只有**颜色**能在手机上被一眼扫出来（只有 `+`/`-` 前缀很难读）。
   * 单串 `bodyText` 表达不了逐行颜色，故这里给一个可选的行数组；非空时优先于 `bodyText`。
   */
  @Prop diffLines: string[] = [];
  /** 每行的性质（`context` / `added` / `removed` / `skipped`），只用来取色 */
  @Prop diffKinds: string[] = [];
  /** 结果被截断时的提示（如「查看完整输出（共 N 字符）」） */
  @Prop bodyTruncatedHint: string = '';
  /** 折叠时显示的入口文案（如「▸ 查看结果」） */
  @Prop collapsedHint: string = '';
  /** 是否展开结果 */
  @Prop expanded: boolean = false;
  /** 进度百分比（0–100；负数 = 不显示进度条）——目标/任务卡用 */
  @Prop progress: number = -1;
  /** 无障碍的一段话（调用方给"这是什么、什么状态"） */
  @Prop a11y: string = '';

  onToggle: () => void = () => {
  };

  private accent(): Resource {
    if (this.tone === 'failed') {
      return HarmonyColor.ALERT;
    }
    if (this.tone === 'warning') {
      return HarmonyColor.WARNING;
    }
    if (this.tone === 'success') {
      return HarmonyColor.CONFIRM;
    }
    if (this.tone === 'running') {
      return HarmonyColor.BRAND;
    }
    return HarmonyColor.TEXT_SECONDARY;
  }

  /**
   * 对照行的颜色：加行绿、减行红、上下文次色、折叠提示三级色。
   *
   * 语义色由系统给（`sys.color.confirm` / `sys.color.alert`），**不写死红绿**——
   * 否则深色模式与高对比模式下会不对。
   */
  private diffColorOf(index: number): Resource {
    const kind: string = index < this.diffKinds.length ? this.diffKinds[index] : 'context';
    if (kind === 'added') {
      return HarmonyColor.CONFIRM;
    }
    if (kind === 'removed') {
      return HarmonyColor.ALERT;
    }
    if (kind === 'skipped') {
      return HarmonyColor.TEXT_TERTIARY;
    }
    return HarmonyColor.TEXT_SECONDARY;
  }

  /** 只有"异常"才画描边（边框在这里是信息，不是装饰） */
  private borderRes(): Resource | undefined {
    if (this.tone === 'failed') {
      return HarmonyColor.ALERT;
    }
    return undefined;
  }

  private shadowOf(): ShadowLevel {
    if (this.tone === 'running') {
      return HarmonyElevation.RAISED;
    }
    return HarmonyElevation.FLAT;
  }

  /** 摘要是否并进标题行（折叠态 = 一行；展开态仍走等宽那一段，便于读路径/命令） */
  private inlineSummary(): boolean {
    return this.summary.length > 0 && !this.expanded
      && this.diffLines.length === 0 && this.bodyText.length === 0;
  }

  /** `▸ 查看结果` 是否并进标题行（同样只在折叠态并） */
  private inlineHint(): boolean {
    return this.collapsedHint.length > 0 && this.inlineSummary()
      && (this.bodyText.length > 0 || this.diffLines.length > 0);
  }

  build() {
    Column({ space: HarmonySpacing.INLINE }) {
      /*
       * 【折叠态 = **一行**（2026-09-17，对齐官方客户端）】
       *
       * 官方会话页里，思考/读取/编辑/命令**每条只占一行**：`[图标] 动作名 · 一行摘要…`，
       * 点开才看全文。我们此前是"标题行 + 摘要行（等宽）"两行——手机上每个过程条目
       * 白吃一行高度，一屏看不到几步。现在折叠时把摘要并进同一行（标题不再抢剩余宽度、
       * 摘要占住余下空间、超出省略），`▸ 查看结果` 也挪到行尾。
       * 展开后仍然是原来的分块呈现（等宽摘要 + 结果/改动对照），密度与可读性各自归位。
       */
      Row({ space: HarmonySpacing.CONTROL_INNER }) {
        SymbolGlyph(this.iconSymbol)
          .fontSize(HarmonyIconSize.INLINE)
          .fontColor([this.accent()])
        Text(this.title)
          .fontSize(HarmonyType.CAPTION.size)
          .fontWeight(HarmonyType.CAPTION.weight + 100)
          .fontColor(HarmonyColor.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(this.inlineSummary() ? 0 : 1)
        if (this.inlineSummary()) {
          Text(this.summary)
            .fontSize(HarmonyType.LABEL.size)
            .fontFamily('monospace')
            .fontColor(HarmonyColor.TEXT_TERTIARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        if (this.badge.length > 0) {
          Text(this.badge)
            .fontSize(HarmonyType.LABEL.size)
            .fontColor(this.accent())
        }
        if (this.meta.length > 0) {
          Text(this.meta)
            .fontSize(HarmonyType.LABEL.size)
            .fontColor(HarmonyColor.TEXT_TERTIARY)
            .maxLines(1)
        }
        if (this.inlineHint()) {
          Text(this.collapsedHint)
            .fontSize(HarmonyType.LABEL.size)
            .fontColor(HarmonyColor.BRAND)
            .maxLines(1)
            .onClick(() => {
              this.onToggle();
            })
        }
      }
      .width('100%')

      if (this.progress >= 0) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
      }

      if (this.summary.length > 0 && !this.inlineSummary()) {
        Text(this.summary)
          .fontSize(HarmonyType.LABEL.size)
          .fontFamily('monospace')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (this.diffLines.length > 0 || this.bodyText.length > 0) {
        if (this.expanded) {
          Column({ space: HarmonySpacing.INLINE }) {
            if (this.diffLines.length > 0) {
              Column({ space: 0 }) {
                ForEach(this.diffLines, (line: string, index: number) => {
                  Text(line)
                    .fontSize(HarmonyType.LABEL.size)
                    .fontFamily('monospace')
                    .fontColor(this.diffColorOf(index))
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .copyOption(CopyOptions.LocalDevice)
                }, (line: string, index: number) => `${index}:${line}`)
              }
              .width('100%')
            } else {
              Text(this.bodyText)
                .fontSize(HarmonyType.LABEL.size)
                .fontFamily('monospace')
                .width('100%')
                .textAlign(TextAlign.Start)
                .copyOption(CopyOptions.LocalDevice)
            }
            if (this.bodyTruncatedHint.length > 0) {
              Text(this.bodyTruncatedHint)
                .fontSize(HarmonyType.LABEL.size)
                .fontColor(HarmonyColor.BRAND)
            }
          }
          .width('100%')
          .padding(HarmonySpacing.CONTROL_INNER)
          .borderRadius(HarmonyRadius.CONTROL)
          .backgroundColor(HarmonyColor.SURFACE)
        } else if (this.collapsedHint.length > 0 && !this.inlineHint()) {
          Text(this.collapsedHint)
            .fontSize(HarmonyType.LABEL.size)
            .fontColor(HarmonyColor.BRAND)
            .onClick(() => {
              this.onToggle();
            })
        }
      }
    }
    .width('100%')
    .padding(HarmonySpacing.CONTAINER)
    .borderRadius(HarmonyRadius.SURFACE)
    .backgroundColor(HarmonyColor.SURFACE_RAISED)
    .borderWidth(this.borderRes() === undefined ? 0 : HarmonyBorder.HAIRLINE)
    .borderColor(this.borderRes() === undefined ? HarmonyColor.SURFACE_RAISED : this.borderRes())
    .shadow({
      radius: this.shadowOf().radius,
      color: HarmonyColor.SURFACE,
      offsetY: this.shadowOf().offsetY
    })
    .animation({ duration: HarmonyMotion.TRANSITION })
    .accessibilityText(this.a11y.length > 0 ? this.a11y : `${this.title}，${this.badge}`)
  }
}


/**
 * 原生按钮（P1.5）。
 *
 * ## 四档强调（emphasis）与四种语气（tone）
 *
 * 强调决定"这个动作有多重"，语气决定"它是哪一类"。两者分开，是因为
 * "主要动作"与"危险动作"是两个独立维度——危险的主选（如审批里的「拒绝」）本该
 * **既是主要、又是危险**，把它们合成一个枚举就表达不了这个组合（D3 §3.4 的
 * "危险动作把主按钮权重反转"正是这种组合）。
 *
 *   emphasis: solid（实底）> tonal（浅底）> outline（描边）> text（纯文字）
 *   tone:     brand | danger | warning | success | neutral
 *
 * 【为什么用 `Button({type, stateEffect}) { … }` 而不是自定义 Row】按压实效、焦点框、
 * 键盘可达性由 ArkUI 的 Button 提供；自己拿 Row 拼一个"看起来像按钮"的东西，
 * 就得把这些系统行为逐个补回来，而且必然补不全（键盘用户第一个受影响）。
 */
@Component
export struct NativeButton {
  @Prop label: string = '';
  /** 可选图标（与 label 二选一或同时给） */
  @Prop iconSymbol: Resource = $r('sys.symbol.circle');
  @Prop showIcon: boolean = false;
  /** 强调：solid | tonal | outline | text */
  @Prop emphasis: string = 'solid';
  /** 语气：brand | danger | warning | success | neutral */
  @Prop tone: string = 'brand';
  @Prop disabled: boolean = false;
  @Prop a11y: string = '';
  /** 是否为方形图标按钮（如发送键：图标居中、不给文字） */
  @Prop square: boolean = false;
  @Prop iconSize: number = HarmonyIconSize.INLINE;

  onTap: () => void = () => {
  };

  private toneColor(): Resource {
    if (this.tone === 'danger') {
      return HarmonyColor.ALERT;
    }
    if (this.tone === 'warning') {
      return HarmonyColor.WARNING;
    }
    if (this.tone === 'success') {
      return HarmonyColor.CONFIRM;
    }
    if (this.tone === 'neutral') {
      return HarmonyColor.TEXT_SECONDARY;
    }
    return HarmonyColor.BRAND;
  }

  private backgroundRes(): Resource {
    if (this.disabled) {
      return HarmonyColor.SURFACE_TERTIARY;
    }
    if (this.emphasis === 'solid') {
      return this.toneColor();
    }
    if (this.emphasis === 'tonal') {
      return HarmonyColor.SURFACE_TERTIARY;
    }
    if (this.emphasis === 'outline') {
      return HarmonyColor.SURFACE_RAISED;
    }
    return HarmonyColor.SURFACE_RAISED;
  }

  /** 实底上必须用"底色之上"的前景色（系统语义；此前发送键写死 Color.White） */
  private foregroundRes(): Resource {
    if (this.disabled) {
      return HarmonyColor.TEXT_TERTIARY;
    }
    if (this.emphasis === 'solid') {
      return this.showIcon && this.label.length === 0 ? HarmonyColor.ON_BRAND_ICON : HarmonyColor.ON_BRAND_TEXT;
    }
    return this.toneColor();
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: !this.disabled }) {
      Row({ space: HarmonySpacing.INLINE }) {
        if (this.showIcon) {
          SymbolGlyph(this.iconSymbol)
            .fontSize(this.iconSize)
            .fontColor([this.foregroundRes()])
        }
        if (this.label.length > 0) {
          Text(this.label)
            .fontSize(HarmonyType.LABEL.size)
            .fontWeight(500)
            .fontColor(this.foregroundRes())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
    }
    // 方形（图标按钮）固定正方；否则交给内容自适应（`'auto'` 是 SDK 文档支持的取值）
    .width(this.square ? HarmonyTouch.MIN_TARGET : 'auto')
    .height(this.square ? HarmonyTouch.MIN_TARGET : HarmonyTouch.MIN_TARGET)
    .padding(this.square ? 0 : {
      left: HarmonySpacing.SECTION,
      right: HarmonySpacing.SECTION
    })
    .backgroundColor(this.backgroundRes())
    .borderRadius(HarmonyRadius.CONTROL)
    .borderWidth(this.emphasis === 'outline' ? HarmonyBorder.HAIRLINE : 0)
    .borderColor(this.toneColor())
    .enabled(!this.disabled)
    .accessibilityText(this.a11y.length > 0 ? this.a11y : this.label)
    .onClick(() => {
      if (!this.disabled) {
        this.onTap();
      }
    })
  }
}

/** 动作条里的一项 */
export interface NativeAction {
  /** 稳定键（用于 ForEach 与回传） */
  id: string;
  label: string;
  /** 选中态（如已评的"有帮助"） */
  active?: boolean;
  /** 语气：neutral | alert */
  tone?: string;
  disabled?: boolean;
  a11y?: string;
}

/**
 * 动作条（P1.5）：把"一行操作"从各处的 Row+若干 Text 收成一处。
 *
 * 【为什么用数据数组而不是若干子组件】动作条的内容（复制/评价/撤回、保存/分享…）
 * 是**可枚举的一行按钮**，用数组表达后：间距、换行、禁用与选中样式只实现一次；
 * 而且"这一行到底有哪些动作"变成了可读的数据（review 时一眼看得完）。
 * 不用 `@BuilderParam` 的理由与 `NativeCard` 同：本项目真机上踩过它的崩溃（D4 记载）。
 */
@Component
export struct NativeActionBar {
  @Prop actions: NativeAction[] = [];
  /** 是否把动作推到左侧并留出弹性空间（右侧放别的） */
  @Prop leading: boolean = true;
  onAction: (id: string) => void = () => {
  };

  build() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: this.leading ? FlexAlign.Start : FlexAlign.End }) {
      ForEach(this.actions, (a: NativeAction) => {
        Row() {
          NativeChip({
            label: a.label,
            active: a.active === true,
            tone: a.tone === undefined ? 'neutral' : a.tone,
            disabled: a.disabled === true,
            a11y: a.a11y === undefined ? a.label : a.a11y,
            onTap: () => {
              this.onAction(a.id);
            }
          })
        }
        .margin({ right: HarmonySpacing.INLINE, bottom: HarmonySpacing.INLINE })
      }, (a: NativeAction) => a.id)
    }
    .width('100%')
  }
}

/* ═══════════════════════════════════════════════════════════════════════════
 * DSH Mobile 设计基元族（v2 T017）
 *
 * ## 对照源码（只读基准）
 *
 * `.research/deepseek-harness-mobile/app/src/main/java/com/labteto/dshmobile/ui/components/`：
 * DsButton.kt / DsCard.kt / DsPill.kt / DsSegmented.kt / DsIconButton.kt / DsBottomSheet.kt /
 * EmptyHero.kt / SectionHeader.kt / StateDot.kt / Shimmer.kt / ToggleRow.kt / DisclosureRow.kt /
 * ContextMeter.kt——每个构件的头注释都标注了对应的 `.kt` 文件。
 *
 * ## 与上半段（Native* 族）的分工
 *
 * 上半段是 v1「鸿蒙原观感」基元，token 取 `HarmonyTheme`；本段是 DSH Mobile 复刻基元，
 * token **只**取 `MobileTheme`（`DsSpacing`/`DsShape`/`DsType`/`DsAnimation`/`dsPaletteOf`）。
 * 两族并存、互不引用——v2 手机链逐步切换到本段，v1 面板链继续用上半段。
 *
 * ## 深色解析：一个监听器 + AppStorage 广播
 *
 * `MobileTheme` 的色板解析需要"系统是否深色"这个输入（`dsPaletteOf(SYSTEM, dark)`）。
 * 本段基元会被同时实例化几十个，每个组件各挂一个 `mediaquery` 监听是浪费——
 * 所以 `installDsSystemDarkWatch()` 只装**一次**监听（模块级哨兵保证幂等），
 * 结果发布到 AppStorage 的 `dsSystemDark` 键，各基元用 `@StorageProp` 订阅。
 *
 * ## 内容注入：刻意不做 `@BuilderParam`
 *
 * 本项目真机上踩过「父组件 @Builder 注入子 Builder → JS 崩溃」（E118/D4 记载）。
 * 因此源码里的容器型构件（DsCard / DsBottomSheet 的 content / DisclosureRow 的 content）
 * 在本仓要么收敛为**样式参数助手**（`dsCardStyle` / `dsSheetOptions`），要么做成
 * **纯头部行**（DsDisclosureRow，展开体由消费方自绘）——与 `harmonySheetOptions` 同一先例。
 * ═══════════════════════════════════════════════════════════════════════ */

/** 系统深色状态的 AppStorage 键（`@StorageProp` 装饰器参数须为字面量，此处只是文档锚点） */
export const DS_SYSTEM_DARK_KEY: string = 'dsSystemDark';

/** 幂等哨兵：监听器只装一次 */
let dsSystemDarkWatchInstalled: boolean = false;

/**
 * 安装「系统深色」监听（幂等）：`(prefers-color-scheme: dark)` 变化 → 写 AppStorage。
 * 每个基元的 `aboutToAppear` 都会调它；重复调用是空操作。监听器**故意不注销**——
 * 它属于进程级主题状态，与任何一个组件实例的生命周期都不同长。
 */
export function installDsSystemDarkWatch(): void {
  if (dsSystemDarkWatchInstalled) {
    return;
  }
  dsSystemDarkWatchInstalled = true;
  const query: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
  AppStorage.setOrCreate<boolean>('dsSystemDark', query.matches);
  query.on('change', (result: mediaquery.MediaQueryResult) => {
    AppStorage.setOrCreate<boolean>('dsSystemDark', result.matches);
  });
}

/**
 * 弹簧动效参数 → ArkUI 曲线。
 * 对照：Compose `spring(dampingRatio, stiffness)`（质量取 1，ω=√stiffness）。
 * ArkUI `curves.springMotion(response, dampingFraction)` 的 response = 2π/ω。
 * token（`DsSpringSpec`）保持唯一权威，本函数只做单位换算。
 */
export function dsSpringCurve(spec: DsSpringSpec): ICurve {
  const response: number = (2 * Math.PI) / Math.sqrt(spec.stiffness);
  return curves.springMotion(response, spec.dampingRatio);
}

/**
 * 时长补间参数 → ArkUI 曲线。`DsAnimation` 词表里所有 tween 都用 `FastOutSlowInEasing`
 * （`DS_EASING_FAST_OUT_SLOW_IN`），与 ArkUI `Curve.FastOutSlowIn` 同名同义，直接查表。
 */
export function dsTweenCurve(spec: DsTweenSpec): Curve {
  return Curve.FastOutSlowIn;
}

/** 给语义色叠加透明度（`0xAARRGGBB` 数值运算；对照 Compose `Color.copy(alpha=)`） */
export function dsWithAlpha(color: number, alpha: number): number {
  const clamped: number = Math.min(1, Math.max(0, alpha));
  const a: number = Math.round(clamped * 255);
  return ((a << 24) | (color & 0x00FFFFFF)) >>> 0;
}

/* ───────────── 组件级度量常量（源码里的 dp/ms 字面量，逐条标注出处） ───────────── */

/** DsButton.kt：Normal h36 / Small h28 */
const DS_BUTTON_HEIGHT_NORMAL: number = 36;
const DS_BUTTON_HEIGHT_SMALL: number = 28;
/** DsButton.kt：小号按钮图标 14dp（普通 16dp 复用 DS_LEADING_ICON_SIZE） */
const DS_ICON_SIZE_SMALL: number = 14;
/** DisclosureRow.kt：行最小高 24dp、chevron 14dp、leading 槽 16dp */
const DS_DISCLOSURE_ROW_MIN_HEIGHT: number = 24;
const DS_DISCLOSURE_CHEVRON_SIZE: number = 14;
const DS_LEADING_ICON_SIZE: number = 16;
/** DisclosureRow.kt TwoByTwoDots：2dp 格点 */
const DS_DOT_GRID_CELL: number = 2;
/** StateDot.kt：非 Running 态核心圆的 halo 直径系数 0.58、halo 透明度 0.10；追逐步进 1s */
const DS_STATEDOT_HALO_SCALE: number = 0.58;
const DS_STATEDOT_HALO_ALPHA: number = 0.10;
const DS_STATEDOT_STEP_MS: number = 1000;
/** DsPill.kt：h24、水平内距 10dp */
const DS_PILL_HEIGHT: number = 24;
const DS_PILL_PAD_H: number = 10;
/** DsIconButton.kt：默认图标 20dp */
const DS_ICONBUTTON_ICON_SIZE: number = 20;
/** DsSegmented.kt：轨道内距/段间距 2dp、拉伸段高 36dp（内联段高复用 DS_PILL_HEIGHT） */
const DS_SEGMENT_TRACK_PAD: number = 2;
const DS_SEGMENT_STRETCH_HEIGHT: number = 36;
/** DsBottomSheet.kt：grabber 高 4dp */
const DS_SHEET_GRABBER_HEIGHT: number = 4;
/** EmptyHero.kt：品牌圆盘 64dp、logo 100dp、Preview pill 垂直内距 4dp */
const DS_HERO_DISC_SIZE: number = 64;
const DS_HERO_LOGO_SIZE: number = 100;
const DS_HERO_PILL_PAD_V: number = 4;
/** Shimmer.kt：扫光带 300dp / 2600ms；骨架带 220dp / 1400ms */
const DS_SHIMMER_BAND_WIDTH: number = 300;
const DS_SHIMMER_DURATION: number = 2600;
const DS_SKELETON_BAND_WIDTH: number = 220;
const DS_SKELETON_DURATION: number = 1400;
/** ContextMeter.kt：条高 6dp、紧凑条宽 44dp */
const DS_METER_HEIGHT: number = 6;
const DS_METER_BAR_WIDTH: number = 44;
/** 骨架块缺省高度（调用方按内容高度给；缺省为一行正文的近似高度） */
const DS_SKELETON_DEFAULT_HEIGHT: number = 16;
/** Compose `Color.Transparent` 的数值形态 */
const DS_COLOR_TRANSPARENT_NUM: number = 0x00000000;
/** 透明边（`.borderWidth(0)` 会命中裸值门禁；0 也是"无边框"这个决策的一部分） */
const DS_BORDER_NONE: number = 0;
/** 扫光渐变端点（Shimmer.kt：`Color.Transparent → Color.White.copy(0.5f) → Color.Transparent`） */
const DS_GRADIENT_TRANSPARENT: string = '#00000000';
const DS_GRADIENT_GLARE: string = '#80FFFFFF';
/** 等宽/系统字体栈（Type.kt `codeFont` / system UI stack） */
const DS_FONT_MONO: string = 'monospace';
const DS_FONT_SANS: string = 'sans-serif';

function dsFontOf(role: DsTypeRole): string {
  return role.mono ? DS_FONT_MONO : DS_FONT_SANS;
}

/* ═══════════════════ DsStateDot（对照 StateDot.kt） ═══════════════════ */

/** 对照：StateDot.kt `enum class StateDotState { Idle, Running, Done, Warning, Error }` */
export enum DsStateDotState {
  IDLE = 'idle',
  RUNNING = 'running',
  DONE = 'done',
  WARNING = 'warning',
  ERROR = 'error'
}

/**
 * 状态点（对照 `ui/components/StateDot.kt`）。
 *
 * Idle=labelCaption / Running=Ds.Deepseek450 / Done=success / Warning=warn / Error=error。
 * Running 态是 **3x3 像素矩阵追逐**：1s 一步、9 步循环（ring 序 0,1,2,5,8,7,6,3,4），
 * 当前格全亮、已过格 0.45、未到格 0.12；其余状态画 0.10 透明度的 halo + 实心核心圆。
 */
@Component
export struct DsStateDot {
  @Prop @Watch('onStateChanged') state: DsStateDotState = DsStateDotState.IDLE;
  /** 直径 vp（源码默认 8dp；DisclosureRow 里也是 8dp）。不叫 size——那是 CustomComponent 保留名 */
  @Prop dotSize: number = 8;
  @State private step: number = 0;
  @StorageProp('dsSystemDark') systemDark: boolean = false;
  private chaseTimer: number = -1;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
    this.startChaseIfNeeded();
  }

  aboutToDisappear(): void {
    this.stopChase();
  }

  onStateChanged(): void {
    this.stopChase();
    this.startChaseIfNeeded();
  }

  private startChaseIfNeeded(): void {
    if (this.state !== DsStateDotState.RUNNING) {
      return;
    }
    this.chaseTimer = setInterval(() => {
      this.step = (this.step + 1) % 9;
    }, DS_STATEDOT_STEP_MS);
  }

  private stopChase(): void {
    if (this.chaseTimer >= 0) {
      clearInterval(this.chaseTimer);
      this.chaseTimer = -1;
    }
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  private coreColor(): number {
    const p: DsPalette = this.palette();
    if (this.state === DsStateDotState.IDLE) {
      return p.labelCaption;
    }
    if (this.state === DsStateDotState.RUNNING) {
      return DsColor.DEEPSEEK_450;
    }
    if (this.state === DsStateDotState.DONE) {
      return p.success;
    }
    if (this.state === DsStateDotState.WARNING) {
      return p.warn;
    }
    return p.error;
  }

  /** 9 格的透明度表（ring 序：index<step → 0.45；==step → 1；其余 → 0.12） */
  private chaseAlphas(): number[] {
    const ring: number[] = [0, 1, 2, 5, 8, 7, 6, 3, 4];
    const out: number[] = [];
    for (let i = 0; i < 9; i++) {
      out.push(0.12);
    }
    for (let ringPos = 0; ringPos < ring.length; ringPos++) {
      const cellIndex: number = ring[ringPos];
      const a: number = ringPos < this.step ? 0.45 : (ringPos === this.step ? 1 : 0.12);
      out[cellIndex] = a;
    }
    return out;
  }

  build() {
    if (this.state === DsStateDotState.RUNNING) {
      // 3x3 追逐矩阵：格宽 dotSize/3，点 = 格×0.74，圆角 = 点×0.25（StateDot.kt drawPixelChase）
      Stack({ alignContent: Alignment.Center }) {
        Circle({
          width: this.dotSize * DS_STATEDOT_HALO_SCALE * 2,
          height: this.dotSize * DS_STATEDOT_HALO_SCALE * 2
        }).fill(dsWithAlpha(this.coreColor(), DS_STATEDOT_HALO_ALPHA))
        Column() {
          ForEach([0, 1, 2], (row: number) => {
            Row() {
              ForEach([0, 1, 2], (col: number) => {
                Column() {
                  Column()
                    .width(this.dotSize / 3 * 0.74)
                    .height(this.dotSize / 3 * 0.74)
                    .borderRadius(this.dotSize / 3 * 0.74 * 0.25)
                    .backgroundColor(dsWithAlpha(this.coreColor(), this.chaseAlphas()[row * 3 + col]))
                }
                .width(this.dotSize / 3)
                .height(this.dotSize / 3)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }, (col: number) => `${col}`)
            }
          }, (row: number) => `${row}`)
        }
        .width(this.dotSize)
        .height(this.dotSize)
      }
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Circle({
          width: this.dotSize * DS_STATEDOT_HALO_SCALE * 2,
          height: this.dotSize * DS_STATEDOT_HALO_SCALE * 2
        }).fill(dsWithAlpha(this.coreColor(), DS_STATEDOT_HALO_ALPHA))
        Circle({ width: this.dotSize, height: this.dotSize }).fill(this.coreColor())
      }
    }
  }
}

/* ═══════════════════ DsShimmerText（对照 Shimmer.kt `Modifier.shimmer`） ═══════════════════ */

/**
 * 流光扫过的文字（对照 `ui/components/Shimmer.kt` 的 `Modifier.shimmer(runningBrush)`——
 * DisclosureRow 的 Running 标题用它表达"这一行还在动"）。
 *
 * 源码用 `BlendMode.SrcAtop` 把扫光带**只画在文字像素上**。ArkUI 的 `blendMode`
 * 以整个画布底景为混合目标，会连背景一起染出一条带子；这里改用**双层文字 + 反向平移**
 * 达到同一效果：底层是原色文字，上层是与底层**同宽同排版**的白色 50% 文字副本，
 * 装在一个 300vp 宽、`clip(true)` 的窗口里扫过（窗口右移、内层文字左移 → 字形静止）。
 * 视觉等效且不污染背景。
 */
@Component
export struct DsShimmerText {
  @Prop text: string = '';
  /** 字阶角色（MobileTheme 常量；普通成员：构造时固定，无需响应式） */
  role: DsTypeRole = DsType.STD_14;
  @Prop color: number = 0xFF000000;
  @State private glareX: number = -DS_SHIMMER_BAND_WIDTH;
  @State @Watch('onBoxLaidOut') private boxWidth: number = 0;
  private glareStarted: boolean = false;

  private startGlare(): void {
    if (this.glareStarted) {
      return;
    }
    this.glareStarted = true;
    this.glareX = -DS_SHIMMER_BAND_WIDTH;
    this.getUIContext().animateTo({
      duration: DS_SHIMMER_DURATION,
      curve: Curve.Linear,
      iterations: -1,
      playMode: PlayMode.Normal
    }, () => {
      this.glareX = this.boxWidth + DS_SHIMMER_BAND_WIDTH;
    });
  }

  onBoxLaidOut(): void {
    this.startGlare();
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Text(this.text)
        .fontSize(this.role.size)
        .lineHeight(this.role.lineHeight)
        .fontWeight(this.role.weight)
        .fontFamily(dsFontOf(this.role))
        .fontColor(this.color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      // 扫光窗口：clip 到带宽，内层文字反向平移保持字形静止（见组件头注释）
      Column() {
        Text(this.text)
          .fontSize(this.role.size)
          .lineHeight(this.role.lineHeight)
          .fontWeight(this.role.weight)
          .fontFamily(dsFontOf(this.role))
          .fontColor(DS_GRADIENT_GLARE)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(this.boxWidth)
          .translate({ x: -this.glareX })
      }
      .width(DS_SHIMMER_BAND_WIDTH)
      .height('100%')
      .clip(true)
      .translate({ x: this.glareX })
    }
    .width('100%')
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.boxWidth = newArea.width as number;
    })
  }
}

/* ═══════════════════ DsSkeletonBlock（对照 Shimmer.kt `Modifier.skeleton`） ═══════════════════ */

/**
 * 加载骨架块（对照 `ui/components/Shimmer.kt` 的 `Modifier.skeleton(base, highlight)`）。
 *
 * 与扫光不同，骨架**自己画底**再扫带——空盒子上的扫光什么也留不下，骨架块才是
 * "内容在路上"的占位（Shimmer.kt 头注释的原话：reads as coming, not broken）。
 * 底色/高亮缺省取 `bgModulePlatform`/`hoverSolid`，调用方可用 props 覆盖。
 */
@Component
export struct DsSkeletonBlock {
  /** 块宽（百分比串或 vp 串；不叫 width——CustomComponent 保留名） */
  @Prop blockWidth: string = '100%';
  @Prop blockHeight: number = DS_SKELETON_DEFAULT_HEIGHT;
  /** 圆角（缺省 r8 = DsShape.ROW，源码 `RoundedCornerShape(8.dp)`） */
  @Prop radius: number = DsShape.ROW;
  /** 底色；< 0 时用语义 `bgModulePlatform` */
  @Prop baseColor: number = -1;
  /** 扫带高亮；< 0 时用语义 `hoverSolid` */
  @Prop highlightColor: number = -1;
  @StorageProp('dsSystemDark') systemDark: boolean = false;
  @State private bandX: number = -DS_SKELETON_BAND_WIDTH;
  @State @Watch('onBoxLaidOut') private boxWidth: number = 0;
  private sweepStarted: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private startSweep(): void {
    if (this.sweepStarted) {
      return;
    }
    this.sweepStarted = true;
    this.bandX = -DS_SKELETON_BAND_WIDTH;
    this.getUIContext().animateTo({
      duration: DS_SKELETON_DURATION,
      curve: Curve.Linear,
      iterations: -1,
      playMode: PlayMode.Normal
    }, () => {
      this.bandX = this.boxWidth + DS_SKELETON_BAND_WIDTH;
    });
  }

  onBoxLaidOut(): void {
    this.startSweep();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Column()
        .width(DS_SKELETON_BAND_WIDTH)
        .height('100%')
        .linearGradient({
          angle: 0,
          colors: [[DS_GRADIENT_TRANSPARENT, 0], [this.highlightResolved(), 0.5], [DS_GRADIENT_TRANSPARENT, 1]]
        })
        .translate({ x: this.bandX })
    }
    .width(this.blockWidth)
    .height(this.blockHeight)
    .borderRadius(this.radius)
    .clip(true)
    .backgroundColor(this.baseResolved())
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.boxWidth = newArea.width as number;
    })
  }

  private baseResolved(): number {
    return this.baseColor >= 0 ? this.baseColor : this.palette().bgModulePlatform;
  }

  private highlightResolved(): string {
    const v: number = this.highlightColor >= 0 ? this.highlightColor : this.palette().hoverSolid;
    return `#${(v >>> 0).toString(16).padStart(8, '0')}`;
  }
}

/* ═══════════════════ DsDisclosureRow（对照 DisclosureRow.kt） ═══════════════════ */

/** 对照：DisclosureRow.kt `enum class DisclosureState { Idle, Running, Error, Stopped }` */
export enum DsDisclosureState {
  IDLE = 'idle',
  RUNNING = 'running',
  ERROR = 'error',
  STOPPED = 'stopped'
}

/**
 * 24dp 披露行（对照 `ui/components/DisclosureRow.kt`）：chevron、leading 图标/状态点、
 * 标题、2x2 点分隔符、摘要。
 *
 * ## 刻意做成"纯头部行"
 *
 * 源码 content 槽接展开体；本仓因 E118（@BuilderParam 真机崩溃）不做内容注入——
 * **展开体由消费方自绘**（ToolCard 就是这么用的），chevron 旋转、Running 标题扫光、
 * 状态点替换图标这些头部行为在这里收口。
 *
 * ## 状态语义（源码注释照录要义）
 *
 * 终态语义高于字形：Error/Stopped 时 leading 槽换成状态点；Running 保留图标，
 * 因为标题的扫光已经在传达"在跑"。`canToggle=false`（源码 onToggle==null）不出
 * chevron，且无图标时补 16dp 缩进——一列行才对得齐。
 */
@Component
export struct DsDisclosureRow {
  @Prop title: string = '';
  /** 摘要（空串 = 无摘要，不出点分隔符） */
  @Prop summary: string = '';
  @Prop showIcon: boolean = false;
  @Prop icon: Resource = $r('sys.symbol.circle');
  @Prop state: DsDisclosureState = DsDisclosureState.IDLE;
  @Prop expanded: boolean = false;
  /** 是否可切换（源码 onToggle != null；false 时不出 chevron） */
  @Prop canToggle: boolean = true;
  @Prop a11y: string = '';
  onToggle: () => void = () => {
  };
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Row() {
      if (this.canToggle) {
        // chevron 常驻（源码：hover 才显的做法在触摸屏上等于不可见）
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(DS_DISCLOSURE_CHEVRON_SIZE)
          .fontColor([this.palette().labelTertiary])
          .rotate({ angle: this.expanded ? 90 : 0 })
          .animation({ duration: DsAnimation.CHEVRON.durationMs, curve: dsTweenCurve(DsAnimation.CHEVRON) })
          .margin({ right: DsSpacing.TINY })
      }
      // leading 槽：固定 16dp，图标与状态点占同一列
      Stack({ alignContent: Alignment.Center }) {
        if (this.state === DsDisclosureState.ERROR) {
          DsStateDot({ state: DsStateDotState.ERROR, dotSize: 8 })
        } else if (this.state === DsDisclosureState.STOPPED) {
          DsStateDot({ state: DsStateDotState.WARNING, dotSize: 8 })
        } else if (this.showIcon) {
          SymbolGlyph(this.icon)
            .fontSize(DS_LEADING_ICON_SIZE)
            .fontColor([this.palette().labelSecondary])
        } else if (!this.canToggle) {
          // 无图标也无 chevron 的行仍要缩进，否则整列对不齐（源码同款规则）
          Column().width(DS_LEADING_ICON_SIZE).height(DS_LEADING_ICON_SIZE)
        }
      }
      .width(DS_LEADING_ICON_SIZE)
      .height(DS_LEADING_ICON_SIZE)
      .margin({ right: DsSpacing.SMALL })
      if (this.state === DsDisclosureState.RUNNING) {
        // Running 标题走扫光（源码 titleModifier = Modifier.shimmer(...)）
        DsShimmerText({ text: this.title, role: DsType.STD_14, color: this.palette().labelSecondary })
          .flexShrink(1)
      } else {
        Text(this.title)
          .fontSize(DsType.STD_14.size)
          .lineHeight(DsType.STD_14.lineHeight)
          .fontWeight(DsType.STD_14.weight)
          .fontFamily(dsFontOf(DsType.STD_14))
          .fontColor(this.palette().labelSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
      }
      if (this.summary.length > 0) {
        // 2x2 点分隔符（TwoByTwoDots）
        Column({ space: 1 }) {
          Row({ space: 1 }) {
            Column().width(DS_DOT_GRID_CELL).height(DS_DOT_GRID_CELL)
              .borderRadius(DS_DOT_GRID_CELL / 2).backgroundColor(this.palette().labelDimmed)
            Column().width(DS_DOT_GRID_CELL).height(DS_DOT_GRID_CELL)
              .borderRadius(DS_DOT_GRID_CELL / 2).backgroundColor(this.palette().labelDimmed)
          }
          Row({ space: 1 }) {
            Column().width(DS_DOT_GRID_CELL).height(DS_DOT_GRID_CELL)
              .borderRadius(DS_DOT_GRID_CELL / 2).backgroundColor(this.palette().labelDimmed)
            Column().width(DS_DOT_GRID_CELL).height(DS_DOT_GRID_CELL)
              .borderRadius(DS_DOT_GRID_CELL / 2).backgroundColor(this.palette().labelDimmed)
          }
        }
        .alignItems(HorizontalAlign.Center)
        .margin({ left: DsSpacing.XSMALL, right: DsSpacing.XSMALL })
        Text(this.summary)
          .fontSize(DsType.STD_14.size)
          .lineHeight(DsType.STD_14.lineHeight)
          .fontWeight(DsType.STD_14.weight)
          .fontFamily(dsFontOf(DsType.STD_14))
          .fontColor(this.palette().labelTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: DS_DISCLOSURE_ROW_MIN_HEIGHT })
    .padding({
      left: DsSpacing.TINY,
      right: DsSpacing.TINY,
      top: DsSpacing.TINY,
      bottom: DsSpacing.TINY
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.canToggle) {
        this.onToggle();
      }
    })
    .accessibilityText(this.a11y.length > 0 ? this.a11y
      : `${this.title}${this.summary.length > 0 ? `，${this.summary}` : ''}${this.canToggle ? '，点按展开或收起' : ''}`)
  }
}

/* ═══════════════════ DsButton（对照 DsButton.kt） ═══════════════════ */

/** 对照：DsButton.kt `enum class DsButtonVariant { Primary, Info, Ghost, Outline, Danger }` */
export enum DsButtonVariant {
  PRIMARY = 'primary',
  INFO = 'info',
  GHOST = 'ghost',
  OUTLINE = 'outline',
  DANGER = 'danger'
}

/** 对照：DsButton.kt `enum class DsButtonSize { Normal, Small }`——Normal h36 r18，Small h28 r14 */
export enum DsButtonSize {
  NORMAL = 'normal',
  SMALL = 'small'
}

/**
 * 按钮变体族（对照 `ui/components/DsButton.kt`）：墨色主按钮 / 品牌信息按钮 / 幽灵 / 描边 / 危险。
 *
 * · 高度与圆角成对：Normal h36 r18（胶囊）、Small h28 r14（胶囊）。
 * · 按压 0.95 缩放（`DsAnimation.pressScale` 弹簧）。
 * · 源码的 hover 分支不移植——触摸屏没有 hover。
 * · 禁用：Ghost/Outline 铺 `bgLayer2`，其余铺 40% 透明度的本色；文字降到 50% 透明度。
 */
@Component
export struct DsButton {
  @Prop text: string = '';
  @Prop variant: DsButtonVariant = DsButtonVariant.PRIMARY;
  /** 档位（不叫 size——CustomComponent 保留名） */
  @Prop buttonSize: DsButtonSize = DsButtonSize.NORMAL;
  @Prop disabled: boolean = false;
  @Prop showIcon: boolean = false;
  @Prop icon: Resource = $r('sys.symbol.circle');
  @Prop a11y: string = '';
  @State private pressed: boolean = false;
  @StorageProp('dsSystemDark') systemDark: boolean = false;
  onTap: () => void = () => {
  };

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  private isNormal(): boolean {
    return this.buttonSize === DsButtonSize.NORMAL;
  }

  private fillColor(): number {
    const p: DsPalette = this.palette();
    if (this.variant === DsButtonVariant.PRIMARY) {
      return p.brandPrimary;
    }
    if (this.variant === DsButtonVariant.INFO) {
      return p.buttonInfoFill;
    }
    if (this.variant === DsButtonVariant.DANGER) {
      return p.error;
    }
    return DS_COLOR_TRANSPARENT_NUM; // Ghost / Outline
  }

  private contentColor(): number {
    const p: DsPalette = this.palette();
    if (this.variant === DsButtonVariant.PRIMARY) {
      return p.onBrandPrimary;
    }
    if (this.variant === DsButtonVariant.INFO) {
      return p.onAccent;
    }
    if (this.variant === DsButtonVariant.DANGER) {
      return DsColor.BLUISH_00; // 源码：Color.White
    }
    return p.labelPrimary; // Ghost / Outline
  }

  private bgFill(): number {
    const p: DsPalette = this.palette();
    if (this.disabled) {
      if (this.variant === DsButtonVariant.GHOST || this.variant === DsButtonVariant.OUTLINE) {
        return p.bgLayer2;
      }
      return dsWithAlpha(this.fillColor(), 0.4);
    }
    return this.fillColor();
  }

  private contentResolved(): number {
    if (this.disabled) {
      return dsWithAlpha(this.contentColor(), 0.5);
    }
    return this.contentColor();
  }

  private pressScale(): number {
    return this.pressed && !this.disabled ? DsScale.PRESSED : DsScale.NORMAL;
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: !this.disabled }) {
      Row({ space: DsSpacing.TINY }) {
        if (this.showIcon) {
          SymbolGlyph(this.icon)
            .fontSize(this.isNormal() ? DS_LEADING_ICON_SIZE : DS_ICON_SIZE_SMALL)
            .fontColor([this.contentResolved()])
        }
        if (this.text.length > 0) {
          Text(this.text)
            .fontSize(this.isNormal() ? DsType.STD_14_STRONG.size : DsType.SMALL_13_STRONG.size)
            .lineHeight(this.isNormal() ? DsType.STD_14_STRONG.lineHeight : DsType.SMALL_13_STRONG.lineHeight)
            .fontWeight(this.isNormal() ? DsType.STD_14_STRONG.weight : DsType.SMALL_13_STRONG.weight)
            .fontFamily(this.isNormal() ? dsFontOf(DsType.STD_14_STRONG) : dsFontOf(DsType.SMALL_13_STRONG))
            .fontColor(this.contentResolved())
            .maxLines(1)
        }
      }
      .height('100%')
    }
    .height(this.isNormal() ? DS_BUTTON_HEIGHT_NORMAL : DS_BUTTON_HEIGHT_SMALL)
    .padding({
      left: this.isNormal() ? DsSpacing.COMFORTABLE : DsSpacing.MEDIUM,
      right: this.isNormal() ? DsSpacing.COMFORTABLE : DsSpacing.MEDIUM
    })
    .backgroundColor(this.bgFill())
    .borderRadius(this.isNormal() ? DsShape.BUTTON_CAPSULE : DsShape.BUTTON_SMALL)
    .borderWidth(this.variant === DsButtonVariant.OUTLINE ? HarmonyBorder.HAIRLINE : DS_BORDER_NONE)
    .borderColor(this.palette().borderL2)
    .enabled(!this.disabled)
    .scale({ x: this.pressScale(), y: this.pressScale() })
    .animation({ curve: dsSpringCurve(DsAnimation.PRESS_SCALE) })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .accessibilityText(this.a11y.length > 0 ? this.a11y : this.text)
    .onClick(() => {
      if (!this.disabled) {
        this.onTap();
      }
    })
  }
}

/* ═══════════════════ DsIconButton（对照 DsIconButton.kt） ═══════════════════ */

/**
 * 图标按钮（对照 `ui/components/DsIconButton.kt`）：**保证 48dp 触控目标**，
 * 按压时底色铺 `hover`、图标 0.95 缩放。
 *
 * 图标本体装在自己的 48dp 槽里且尺寸不随槽继承——源码用 `requiredSize` 修
 * "Material Surface 把最小尺寸传给子节点、图标被顶回 48dp"的坑；本仓对应做法是
 * 槽（Stack 定尺寸）与图标（fontSize 定尺寸）分层。
 */
@Component
export struct DsIconButton {
  @Prop icon: Resource = $r('sys.symbol.circle');
  /** 无障碍说明（源码 contentDescription；图标按钮没有文字，这里是唯一的语义通道） */
  @Prop a11y: string = '';
  @Prop disabled: boolean = false;
  /** 图标尺寸（源码默认 20dp） */
  @Prop iconSize: number = DS_ICONBUTTON_ICON_SIZE;
  /** 前景色；< 0 时用语义 labelSecondary（源码 tint 的默认值） */
  @Prop tint: number = -1;
  @State private pressed: boolean = false;
  @StorageProp('dsSystemDark') systemDark: boolean = false;
  onTap: () => void = () => {
  };

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  private tintResolved(): number {
    if (this.disabled) {
      return dsWithAlpha(this.palette().labelSecondary, 0.4);
    }
    return this.tint >= 0 ? this.tint : this.palette().labelSecondary;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(this.icon)
        .fontSize(this.iconSize)
        .fontColor([this.tintResolved()])
    }
    .width(DsSpacing.TOUCH_TARGET)
    .height(DsSpacing.TOUCH_TARGET)
    .borderRadius(DsShape.PILL_FULL)
    .backgroundColor(this.pressed && !this.disabled ? this.palette().hover : DS_COLOR_TRANSPARENT_NUM)
    .scale({
      x: this.pressed && !this.disabled ? DsScale.PRESSED : DsScale.NORMAL,
      y: this.pressed && !this.disabled ? DsScale.PRESSED : DsScale.NORMAL
    })
    .animation({ curve: dsSpringCurve(DsAnimation.PRESS_SCALE) })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .accessibilityText(this.a11y)
    .onClick(() => {
      if (!this.disabled) {
        this.onTap();
      }
    })
  }
}

/* ═══════════════════ DsCard（对照 DsCard.kt） ═══════════════════ */

/**
 * DsCard 的样式参数（对照 `ui/components/DsCard.kt`）。
 *
 * 源码是"容器 + content 槽"；本仓因 E118 不做 Builder 注入，DsCard 收敛为
 * **样式助手**（与 `harmonySheetOptions` 同一先例）：消费方拿这组值自绘 Column。
 * 边框不是装饰——浅色主题里 bgBase 与 bgLayer1 同为纯白，没有边框卡片就不可见
 * （源码头注释照录要义）。
 */
export interface DsCardStyle {
  radius: number;
  background: number;
  borderColor: number;
  borderWidth: number;
  paddingH: number;
  paddingV: number;
  /** 卡内子项纵向间距（源码 verticalArrangement 默认 spacedBy(tiny)） */
  space: number;
}

export function dsCardStyle(palette: DsPalette): DsCardStyle {
  return {
    radius: DsShape.BLOCK,
    background: palette.bgLayer1,
    borderColor: palette.borderL2,
    borderWidth: HarmonyBorder.HAIRLINE,
    paddingH: DsSpacing.MEDIUM,
    paddingV: DsSpacing.SMALL,
    space: DsSpacing.TINY
  };
}

/* ═══════════════════ DsPill（对照 DsPill.kt） ═══════════════════ */

/**
 * h24 紧凑标签（对照 `ui/components/DsPill.kt`）：静息是徽标，接上 onTap 就是触发器。
 *
 * · 静息底色是 `bgModulePlatform` 而非 `bgLayer2`——浅色主题三层 bg 都是纯白，
 *   白上白不成其为 pill（源码注释照录要义，这是有意的忠实度偏离）。
 * · 可点的 pill 加一条 hairline——都有底色之后，边框是唯一还说"我能点"的东西。
 * · warn → warnTertiary 底 + 胶囊形；selected → accentTertiary 底 + accent 字。
 */
@Component
export struct DsPill {
  @Prop text: string = '';
  @Prop selected: boolean = false;
  @Prop warn: boolean = false;
  /** 是否可点（源码 onClick != null：出 hairline、可按压） */
  @Prop clickable: boolean = false;
  @Prop a11y: string = '';
  @State private pressed: boolean = false;
  @StorageProp('dsSystemDark') systemDark: boolean = false;
  onTap: () => void = () => {
  };

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  private bgFill(): number {
    const p: DsPalette = this.palette();
    if (this.warn) {
      return p.warnTertiary;
    }
    if (this.selected) {
      return p.accentTertiary;
    }
    return p.bgModulePlatform;
  }

  private contentColor(): number {
    const p: DsPalette = this.palette();
    if (this.warn) {
      return p.warnLabel;
    }
    if (this.selected) {
      return p.accent;
    }
    return p.labelSecondary;
  }

  private pressScale(): number {
    return this.pressed && this.clickable ? DsScale.PRESSED : DsScale.NORMAL;
  }

  build() {
    Row() {
      Text(this.text)
        .fontSize(DsType.XSMALL_12.size)
        .lineHeight(DsType.XSMALL_12.lineHeight)
        .fontWeight(DsType.XSMALL_12.weight)
        .fontFamily(dsFontOf(DsType.XSMALL_12))
        .fontColor(this.contentColor())
        .maxLines(1)
    }
    .height(DS_PILL_HEIGHT)
    .padding({ left: DS_PILL_PAD_H, right: DS_PILL_PAD_H })
    .alignItems(VerticalAlign.Center)
    .borderRadius(this.warn ? DsShape.PILL_FULL : DsShape.PILL)
    .backgroundColor(this.bgFill())
    .borderWidth(this.clickable && !this.warn && !this.selected ? HarmonyBorder.HAIRLINE : DS_BORDER_NONE)
    .borderColor(this.palette().borderL2)
    .scale({ x: this.pressScale(), y: this.pressScale() })
    .animation({ curve: dsSpringCurve(DsAnimation.PRESS_SCALE) })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .accessibilityText(this.a11y.length > 0 ? this.a11y : this.text)
    .onClick(() => {
      if (this.clickable) {
        this.onTap();
      }
    })
  }
}

/* ═══════════════════ DsSegmented（对照 DsSegmented.kt） ═══════════════════ */

/** 对照：DsSegmented.kt `data class DsSegment(val key: String, val label: String)` */
export interface DsSegmentData {
  key: string;
  label: string;
}

/**
 * 分段控件（对照 `ui/components/DsSegmented.kt`）：胶囊轨道里互斥的几个选择。
 *
 * 轨道与选中块一起才有"控件"的样子（源码把这条教训写进了头注释：只有文字深浅的
 * 第一版在触屏上读作说明文字）。轨道 `hoverSolid` 底 + hairline 边；选中段
 * `accentTertiary` 实底 + accent 字；`stretch=true` 时段高 36、平分轨道宽。
 */
@Component
export struct DsSegmented {
  @Prop segments: DsSegmentData[] = [];
  @Prop selectedKey: string = '';
  @Prop disabled: boolean = false;
  @Prop stretch: boolean = false;
  onSelect: (key: string) => void = () => {
  };
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  private segColor(selected: boolean): number {
    const p: DsPalette = this.palette();
    if (this.disabled) {
      return p.labelDimmed;
    }
    return selected ? p.accent : p.labelTertiary;
  }

  build() {
    Row({ space: DS_SEGMENT_TRACK_PAD }) {
      ForEach(this.segments, (seg: DsSegmentData) => {
        Column() {
          Text(seg.label)
            .fontSize(DsType.TAB_TEXT.size)
            .lineHeight(DsType.TAB_TEXT.lineHeight)
            .fontWeight(DsType.TAB_TEXT.weight)
            .fontFamily(dsFontOf(DsType.TAB_TEXT))
            .fontColor(this.segColor(seg.key === this.selectedKey))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .constraintSize({ minHeight: this.stretch ? DS_SEGMENT_STRETCH_HEIGHT : DS_PILL_HEIGHT })
        .layoutWeight(this.stretch ? 1 : 0)
        .justifyContent(FlexAlign.Center)
        .padding({
          left: DsSpacing.MEDIUM,
          right: DsSpacing.MEDIUM,
          top: DsSpacing.TINY,
          bottom: DsSpacing.TINY
        })
        .borderRadius(DsShape.PILL_FULL)
        .backgroundColor(seg.key === this.selectedKey
          ? this.palette().accentTertiary : DS_COLOR_TRANSPARENT_NUM)
        .animation({ duration: DsAnimation.TAB_SWAP.durationMs, curve: dsTweenCurve(DsAnimation.TAB_SWAP) })
        .onClick(() => {
          if (!this.disabled) {
            this.onSelect(seg.key);
          }
        })
        .accessibilityText(seg.key === this.selectedKey ? `${seg.label}，已选中` : seg.label)
      }, (seg: DsSegmentData) => seg.key)
    }
    .borderRadius(DsShape.PILL_FULL)
    .backgroundColor(this.palette().hoverSolid)
    .borderWidth(HarmonyBorder.HAIRLINE)
    .borderColor(this.palette().borderL2)
    .padding(DS_SEGMENT_TRACK_PAD)
  }
}

/* ═══════════════════ DsBottomSheet（对照 DsBottomSheet.kt） ═══════════════════ */

/**
 * Sheet 参数助手（对照 `ui/components/DsBottomSheet.kt` 的 ModalBottomSheet 实参）：
 * `dragBar:false`（grabber 由 DsSheetHeader 自绘）、遮罩 `overlayMask`、面板底 `bgLayer2`。
 * 与 `harmonySheetOptions` 同款：ArkUI 的 Sheet 是组件属性而非组件，参数助手 +
 * 强制消失回调（否则调用方状态停在 true，Sheet 再也打不开）。
 */
export function dsSheetOptions(onGone: () => void, palette: DsPalette,
  height: SheetSize = SheetSize.MEDIUM): SheetOptions {
  return {
    height: height,
    dragBar: false,
    showClose: true,
    maskColor: palette.overlayMask,
    backgroundColor: palette.bgLayer2,
    shouldDismiss: (dismiss: SheetDismiss) => {
      onGone();
      dismiss.dismiss();
    }
  };
}

/**
 * Sheet 头部（对照 `ui/components/DsBottomSheet.kt` 的 grabber + title 布局）：
 * 12% 宽、4dp 高的 borderL3 胶囊 grabber，large20 标题、caption11 副题。
 * 源码 trailing 槽收敛为 `actionLabel` 文字按钮（E118：不做 Builder 注入）。
 */
@Component
export struct DsSheetHeader {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop actionLabel: string = '';
  onAction: () => void = () => {
  };
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Column({ space: DsSpacing.SMALL }) {
      Row() {
        Column()
          .width('12%')
          .height(DS_SHEET_GRABBER_HEIGHT)
          .borderRadius(DsShape.PILL_FULL)
          .backgroundColor(this.palette().borderL3)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      if (this.title.length > 0) {
        Row() {
          Column() {
            Text(this.title)
              .fontSize(DsType.LARGE_20.size)
              .lineHeight(DsType.LARGE_20.lineHeight)
              .fontWeight(DsType.LARGE_20.weight)
              .fontFamily(dsFontOf(DsType.LARGE_20))
              .fontColor(this.palette().labelPrimary)
            if (this.subtitle.length > 0) {
              Text(this.subtitle)
                .fontSize(DsType.CAPTION_11.size)
                .lineHeight(DsType.CAPTION_11.lineHeight)
                .fontWeight(DsType.CAPTION_11.weight)
                .fontFamily(dsFontOf(DsType.CAPTION_11))
                .fontColor(this.palette().labelTertiary)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          if (this.actionLabel.length > 0) {
            Text(this.actionLabel)
              .fontSize(DsType.CAPTION_11_STRONG.size)
              .lineHeight(DsType.CAPTION_11_STRONG.lineHeight)
              .fontWeight(DsType.CAPTION_11_STRONG.weight)
              .fontFamily(dsFontOf(DsType.CAPTION_11_STRONG))
              .fontColor(this.palette().accent)
              .padding(DsSpacing.TINY)
              .onClick(() => {
                this.onAction();
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({
      left: DsSpacing.LARGE,
      right: DsSpacing.LARGE,
      top: DsSpacing.COMFORTABLE,
      bottom: DsSpacing.SMALL
    })
  }
}

/* ═══════════════════ DsEmptyHero（对照 EmptyHero.kt） ═══════════════════ */

/**
 * 居中空态（对照 `ui/components/EmptyHero.kt`）：品牌圆盘、hero26 大标题、可选副题、
 * mono "Preview" 胶囊、建议 chips。
 *
 * 圆盘标记复刻 WhaleMark：64dp `accentTertiary` 圆盘 + 超尺寸 launcher 前景图
 * （源码用 100dp 的 `ic_launcher_foreground` 填 64dp 圆盘——启动器矢量把图形收在
 * 安全区里，不放大就只剩一圈底色；本仓对应资源是 `app.media.foreground`）。
 */
@Component
export struct DsEmptyHero {
  @Prop headline: string = '';
  @Prop subtitle: string = '';
  @Prop chips: string[] = [];
  onChipClick: (chip: string) => void = () => {
  };
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Column({ space: DsSpacing.COMFORTABLE }) {
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.foreground'))
          .width(DS_HERO_LOGO_SIZE)
          .height(DS_HERO_LOGO_SIZE)
          .objectFit(ImageFit.Contain)
      }
      .width(DS_HERO_DISC_SIZE)
      .height(DS_HERO_DISC_SIZE)
      .borderRadius(DsShape.PILL_FULL)
      .backgroundColor(this.palette().accentTertiary)
      .clip(true)
      Text(this.headline)
        .fontSize(DsType.HERO_26.size)
        .lineHeight(DsType.HERO_26.lineHeight)
        .fontWeight(DsType.HERO_26.weight)
        .fontFamily(dsFontOf(DsType.HERO_26))
        .fontColor(this.palette().labelPrimary)
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(DsType.BASE_16.size)
          .lineHeight(DsType.BASE_16.lineHeight)
          .fontWeight(DsType.BASE_16.weight)
          .fontFamily(dsFontOf(DsType.BASE_16))
          .fontColor(this.palette().labelSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      // mono "Preview" 胶囊（源码文案原样保留——它是预览版产品位的专用标记）
      Text('Preview')
        .fontSize(DsType.XSMALL_12.size)
        .lineHeight(DsType.XSMALL_12.lineHeight)
        .fontWeight(DsType.XSMALL_12.weight)
        .fontFamily(DS_FONT_MONO)
        .fontColor(this.palette().accent)
        .padding({ left: DS_PILL_PAD_H, right: DS_PILL_PAD_H, top: DS_HERO_PILL_PAD_V, bottom: DS_HERO_PILL_PAD_V })
        .borderRadius(DsShape.PILL_FULL)
        .backgroundColor(this.palette().accentTertiary)
      if (this.chips.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.chips, (chip: string) => {
            DsPill({
              text: chip,
              clickable: true,
              onTap: () => {
                this.onChipClick(chip);
              }
            })
              .margin({ right: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
          }, (chip: string) => chip)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(DsSpacing.XXLARGE)
    .alignItems(HorizontalAlign.Center)
  }
}

/* ═══════════════════ DsSectionHeader（对照 SectionHeader.kt） ═══════════════════ */

/**
 * 小节标题行（对照 `ui/components/SectionHeader.kt`）：std14Strong 标题 +
 * 可选的右对齐 accent 动作（caption11Strong）。
 */
@Component
export struct DsSectionHeader {
  @Prop title: string = '';
  /** 右侧动作文案（空串 = 无动作） */
  @Prop action: string = '';
  onAction: () => void = () => {
  };
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Row() {
      Text(this.title)
        .fontSize(DsType.STD_14_STRONG.size)
        .lineHeight(DsType.STD_14_STRONG.lineHeight)
        .fontWeight(DsType.STD_14_STRONG.weight)
        .fontFamily(dsFontOf(DsType.STD_14_STRONG))
        .fontColor(this.palette().labelSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.action.length > 0) {
        Text(this.action)
          .fontSize(DsType.CAPTION_11_STRONG.size)
          .lineHeight(DsType.CAPTION_11_STRONG.lineHeight)
          .fontWeight(DsType.CAPTION_11_STRONG.weight)
          .fontFamily(dsFontOf(DsType.CAPTION_11_STRONG))
          .fontColor(this.palette().accent)
          .padding(DsSpacing.TINY)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/* ═══════════════════ DsToggleRow（对照 ToggleRow.kt） ═══════════════════ */

/**
 * 带标签的开关行（对照 `ui/components/ToggleRow.kt`）。
 *
 * **整行**都是点击目标，不只开关本身——32dp 的拇指在手机边角是糟糕的靶子，
 * 用户瞄的本来就是标签（源码注释照录要义）。为此开关本体 `HitTestMode.None`，
 * 只做受控显示；状态翻转统一走行的 onClick。
 */
@Component
export struct DsToggleRow {
  @Prop label: string = '';
  @Prop hint: string = '';
  @Prop checked: boolean = false;
  onChange: () => void = () => {
  };
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Row() {
      Column() {
        Text(this.label)
          .fontSize(DsType.STD_14.size)
          .lineHeight(DsType.STD_14.lineHeight)
          .fontWeight(DsType.STD_14.weight)
          .fontFamily(dsFontOf(DsType.STD_14))
          .fontColor(this.palette().labelSecondary)
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontWeight(DsType.CAPTION_11.weight)
            .fontFamily(dsFontOf(DsType.CAPTION_11))
            .fontColor(this.palette().labelCaption)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .borderRadius(DsShape.ROW)
    .clip(true)
    .padding({ top: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
    .onClick(() => {
      this.onChange();
    })
    .accessibilityText(`${this.label}，${this.checked ? '开' : '关'}`)
  }
}

/* ═══════════════════ DsContextMeter（对照 ContextMeter.kt） ═══════════════════ */

/**
 * 上下文占用条（对照 `ui/components/ContextMeter.kt`）：h6 胶囊轨道（bgModulePlatform），
 * 按 system/tools/messages 三段染色（`Ds.Meter*`，缺省回退 accent 单段）。
 * 源码 `ContextMeterDetail` 的图例是 Details 面板的职责，不进基元。
 */
@Component
export struct DsContextMeter {
  /** 已用比例 0..1；< 0 = 无压力数据 → 整条不渲染（源码 `pressure?.usedRatio ?: return`） */
  @Prop usedRatio: number = -1;
  /** 总 token；<= 0 或三段皆 0 → 无分段，回退 accent 单段 */
  @Prop total: number = 0;
  @Prop systemTokens: number = 0;
  @Prop toolsTokens: number = 0;
  @Prop messageTokens: number = 0;
  /** 紧凑条宽（源码默认 44dp；传 0 表示交给父容器定宽） */
  @Prop barWidth: number = DS_METER_BAR_WIDTH;
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  private hasBreakdown(): boolean {
    return this.total > 0
      && (this.systemTokens > 0 || this.toolsTokens > 0 || this.messageTokens > 0);
  }

  build() {
    if (this.usedRatio >= 0) {
      // 轨道（h6 胶囊、bgModulePlatform 底）→ 内嵌按比例填充的分段行
      Row() {
        Row() {
          if (this.hasBreakdown()) {
            Column().backgroundColor(DsColor.METER_SYSTEM).layoutWeight(this.systemTokens)
            Column().backgroundColor(DsColor.METER_TOOLS).layoutWeight(this.toolsTokens)
            Column().backgroundColor(DsColor.METER_MESSAGES).layoutWeight(this.messageTokens)
          } else {
            Column().backgroundColor(this.palette().accent).layoutWeight(1)
          }
        }
        .width(`${(Math.min(1, this.usedRatio) * 100).toFixed(2)}%`)
        .height('100%')
        .animation({ duration: DsAnimation.FADE.durationMs, curve: dsTweenCurve(DsAnimation.FADE) })
        .clip(true)
      }
      .width(this.barWidth > 0 ? this.barWidth : '100%')
      .height(DS_METER_HEIGHT)
      .borderRadius(DsShape.PILL_FULL)
      .backgroundColor(this.palette().bgModulePlatform)
      .clip(true)
    }
  }
}
