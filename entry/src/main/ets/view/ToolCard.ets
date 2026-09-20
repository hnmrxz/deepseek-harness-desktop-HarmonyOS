/**
 * 工具调用卡（T016：对照 `dshmobile/ui/components/ToolCards.kt` + `DisclosureRow.kt` 复刻）。
 *
 * ## 对照结构
 *
 * 源码是一张 **24dp 披露行头部 + r12 代码块卡体**（codeBlockBg / borderL1，内距 12dp、
 * 子项距 8dp），展开才渲染体。本侧同构：
 *  · 头部走 `DsDisclosureRow`——chevron 旋转、Running 标题扫光、Error/Stopped 换状态点
 *    这些头部行为都收口在基元里；ToolState → 披露态的映射见 `disclosureState()`。
 *  · 体是本文件自绘的代码块卡（源码 content 槽在 ArkTS 侧无安全注入手段，
 *    见 `NativePrimitives.DsDisclosureRow` 头注释）。
 *
 * ## 两条判定仍来自模型（视图不重写）
 *
 *  · 类别与语气：`presentTool(this.item, toolStateLabel(this.item.toolState))`（17 条断言）
 *  · 改动对照：`presentDiff(toolName, toolArgs)`（45 条断言）；
 *    **失败 / 被拒刻意不出对照**（失败时参数只是"意图"，画成对照会误导）。
 *
 * ## 保留 v1 的功能面与签名
 *
 * `@Prop item / @Prop expanded` + `onToggle / onOpenImage` 不动；「预期修改 / 已应用修改」
 * 双区块（§FR-012）、图片缩略图（§FR-013）、技能行（§FR-014）、截断如实提示都保留，
 * 只是换了载体：v1 的 badge / meta / collapsedHint 收进「头部摘要 + 状态点 + 体内状态行」
 * 三处——摘要给增删计数（源码 DiffCard 摘要同款），状态点给终态色，体内状态行给
 * 状态文案 + 时长。
 *
 * ## 展开态为什么是入参
 *
 * 主区的「展开全部 / 收起全部」要一次性控制所有卡（宿主数组是唯一真值），
 * 本组件不自己持有展开态，只吃 `expanded` + 报 `onToggle`；失败/被拒的默认展开
 * 仍由模型说了算（`toolDefaultExpanded`）。
 */

import {
  DiffLineKind, ToolKind, ToolState, TrajectoryItem, formatClock, formatDuration,
  presentDiff, presentTool, previewOutput, toolStateLabel, toolSummaryOf,
  hasAppliedDiff, presentAppliedDiffs,
  imageResultOf, skillNameOf,
  HarmonyBorder, Radius, Sz,
  DsPalette, DsShape, DsSpacing, DsThemePreference, DsType,
  dsPaletteOf,
} from 'appstate';
import type { DiffPresentation, DiffLine, ToolPresentation } from 'appstate';
import { parseJson } from 'connection';
import { DsDisclosureRow, DsDisclosureState, installDsSystemDarkWatch } from './NativePrimitives';

/* ───────── 组件级度量（ToolCards.kt 的 dp 字面量，逐条标注出处） ───────── */

/** ToolCards.kt `DiffLine`：前缀列宽 18dp */
const TOOL_DIFF_PREFIX_WIDTH: number = 18;
/** ToolCards.kt `DiffBody`：行距 spacedBy(2.dp)、路径头 top 6dp / bottom 2dp */
const TOOL_DIFF_LINE_SPACE: number = 2;
const TOOL_DIFF_PATH_TOP: number = 6;
const TOOL_DIFF_PATH_BOTTOM: number = 2;
/** ToolCards.kt 状态 pill：水平内距 8dp、垂直内距 2dp（pillFull + caption11Strong） */
const TOOL_PILL_PAD_H: number = 8;
const TOOL_PILL_PAD_V: number = 2;
/** 等宽/系统字体栈（Type.kt `codeFont` / system UI stack） */
const TOOL_FONT_MONO: string = 'monospace';
const TOOL_FONT_SANS: string = 'sans-serif';

@Component
export struct ToolCard {
  /** 要显示的工具调用条目 */
  @Prop item: TrajectoryItem;
  /** 是否已展开（唯一真值在宿主；见文件头说明） */
  @Prop expanded: boolean = false;

  /** 点卡片展开/收起 */
  onToggle: () => void = () => {
  };
  /** §FR-013：点击图片缩略图打开灯箱查看 */
  onOpenImage: (url: string) => void = () => {
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
      // 头部：24dp 披露行。类别图标 / 展开默认态 / 无障碍文案都来自 `presentTool`
      // （纯模型 + 17 条断言），视图不再各自猜。
      DsDisclosureRow({
        title: this.item.toolName,
        // 参数摘要按类别提炼（终端出命令、读取出路径、搜索出模式+范围）；
        // 有对照时改给增删计数——收起状态下也要一眼看到"改了多少"。
        summary: this.headerSummary(),
        showIcon: true,
        icon: this.toolIcon(presentTool(this.item, toolStateLabel(this.item.toolState)).kind),
        state: this.disclosureState(),
        expanded: this.isExpanded(),
        canToggle: true,
        a11y: presentTool(this.item, toolStateLabel(this.item.toolState)).a11y,
        onToggle: () => {
          this.onToggle();
        }
      })
      // 展开才渲染体（源码 content 槽 = ToolCardBody；本侧在下方自绘）
      if (this.isExpanded()) {
        this.bodyCard()
      }
      // §FR-013：图片类型工具结果渲染为缩略图（保留 v1：始终可见，不折叠进卡体）
      if (this.imageUrl() !== null) {
        Image(this.imageUrl()!)
          .width('100%')
          .height(Sz.THUMBNAIL_H)
          .objectFit(ImageFit.Cover)
          .borderRadius(Radius.S)
          .onClick(() => {
            this.onOpenImage(this.imageUrl()!);
          })
          .accessibilityText(`图片结果：${this.item.toolName}`)
      }
    }
    .width('100%')
  }

  /**
   * 卡体（对照 `ToolCardBody`：fillMaxWidth + clip(block) + codeBlockBg +
   * border(1dp, borderL1) + padding(12dp)、spacedBy(8dp)）。
   */
  @Builder
  bodyCard() {
    Column({ space: DsSpacing.SMALL }) {
      // 顶行状态：状态 pill（源码 TerminalBody 的 exit 状态样式：caption11Strong +
      // pillFull + 语义 tertiary 底）+ 时长（v1 头部 meta 收编于此）。
      Row({ space: DsSpacing.SMALL }) {
        Text(toolStateLabel(this.item.toolState))
          .fontSize(DsType.CAPTION_11_STRONG.size)
          .lineHeight(DsType.CAPTION_11_STRONG.lineHeight)
          .fontWeight(DsType.CAPTION_11_STRONG.weight)
          .fontFamily(TOOL_FONT_SANS)
          .fontColor(this.pillFg())
          .padding({ left: TOOL_PILL_PAD_H, right: TOOL_PILL_PAD_H, top: TOOL_PILL_PAD_V, bottom: TOOL_PILL_PAD_V })
          .borderRadius(DsShape.PILL_FULL)
          .backgroundColor(this.pillBg())
        if (this.item.elapsedMs > 0) {
          Text(this.metaText())
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontWeight(DsType.CAPTION_11.weight)
            .fontFamily(TOOL_FONT_SANS)
            .fontColor(this.palette().labelCaption)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // §FR-012：编辑类工具优先显示改动对照——用户要看的是"改了什么"，
      // 而不是"改成功了"这句话（有对照时不再显示工具的输出确认）。
      if (this.diffOf() !== null) {
        this.diffHeading('预期修改')
        this.presentationBlock(this.diffOf()!)
        if (this.diffOf()!.truncated) {
          this.captionHint('▸ 对照较长，已按上限截断')
        }
        // §FR-012：有预期修改但无已应用修改时显示占位
        if (this.itemHasAppliedDiff() && this.appliedDiffPresentations().length === 0) {
          this.captionHint('（暂无已应用修改）')
        }
      }
      if (this.appliedDiffPresentations().length > 0) {
        this.diffHeading('已应用修改')
        ForEach(this.appliedDiffPresentations(), (p: DiffPresentation) => {
          this.presentationBlock(p)
        }, (p: DiffPresentation, idx: number) => `${idx}:${p.path}`)
      }

      // 无对照才显示输出/技能行（源码各 Body 的互斥分支同款）
      if (this.diffOf() === null) {
        // §FR-014：技能调用行显示技能名称
        if (this.skillName() !== null) {
          Text(`技能：${this.skillName()}`)
            .fontSize(DsType.MD_CODE.size)
            .lineHeight(DsType.MD_CODE.lineHeight)
            .fontWeight(DsType.MD_CODE.weight)
            .fontFamily(TOOL_FONT_MONO)
            .fontColor(this.palette().labelSecondary)
            .width('100%')
        } else {
          Text(previewOutput(this.item.toolOutput).shown)
            .fontSize(DsType.MD_CODE.size)
            .lineHeight(DsType.MD_CODE.lineHeight)
            .fontWeight(DsType.MD_CODE.weight)
            .fontFamily(TOOL_FONT_MONO)
            .fontColor(this.palette().labelPrimary)
            .width('100%')
          if (previewOutput(this.item.toolOutput).truncated) {
            this.captionHint(`▸ 查看完整输出（共 ${previewOutput(this.item.toolOutput).totalLength} 字符）`)
          }
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().codeBlockBg)
    .borderWidth(HarmonyBorder.HAIRLINE)
    .borderColor(this.palette().borderL1)
    .padding(DsSpacing.MEDIUM)
  }

  /** 区块标题（源码 `SectionLabel`：caption11Strong + labelCaption） */
  @Builder
  diffHeading(heading: string) {
    Text(`── ${heading} ──`)
      .fontSize(DsType.CAPTION_11_STRONG.size)
      .lineHeight(DsType.CAPTION_11_STRONG.lineHeight)
      .fontWeight(DsType.CAPTION_11_STRONG.weight)
      .fontFamily(TOOL_FONT_SANS)
      .fontColor(this.palette().labelCaption)
      .margin({ top: DsSpacing.XSMALL })
  }

  /** 弱提示行（截断/占位）：caption11 + labelCaption */
  @Builder
  captionHint(text: string) {
    Text(text)
      .fontSize(DsType.CAPTION_11.size)
      .lineHeight(DsType.CAPTION_11.lineHeight)
      .fontWeight(DsType.CAPTION_11.weight)
      .fontFamily(TOOL_FONT_SANS)
      .fontColor(this.palette().labelCaption)
      .width('100%')
  }

  /**
   * 单个文件的对照块（对照 `DiffBody` 的单 hunk 段）：路径头（small13Strong）+
   * 逐行前缀列对照（源码 `DiffLine`：前缀列 18dp + 内容 layoutWeight(1f)，mdCode）。
   */
  @Builder
  presentationBlock(p: DiffPresentation) {
    Column({ space: TOOL_DIFF_LINE_SPACE }) {
      if (p.path.length > 0) {
        Text(p.path)
          .fontSize(DsType.SMALL_13_STRONG.size)
          .lineHeight(DsType.SMALL_13_STRONG.lineHeight)
          .fontWeight(DsType.SMALL_13_STRONG.weight)
          .fontFamily(TOOL_FONT_SANS)
          .fontColor(this.palette().labelSecondary)
          .margin({ top: TOOL_DIFF_PATH_TOP, bottom: TOOL_DIFF_PATH_BOTTOM })
      }
      ForEach(p.lines, (line: DiffLine) => {
        this.diffLineRow(line)
      }, (line: DiffLine, idx: number) => `${idx}:${line.kind}:${line.text}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 单行对照：+/−/空格 前缀列（18dp）+ 内容；折叠段如实显示"省了多少" */
  @Builder
  diffLineRow(line: DiffLine) {
    if (line.kind === DiffLineKind.SKIPPED) {
      Text(`  ⋯ 省略 ${line.skipped} 行未改动`)
        .fontSize(DsType.CAPTION_11.size)
        .lineHeight(DsType.CAPTION_11.lineHeight)
        .fontWeight(DsType.CAPTION_11.weight)
        .fontFamily(TOOL_FONT_MONO)
        .fontColor(this.palette().labelCaption)
        .width('100%')
    } else {
      Row() {
        Text(this.diffPrefix(line))
          .fontSize(DsType.MD_CODE.size)
          .lineHeight(DsType.MD_CODE.lineHeight)
          .fontWeight(DsType.MD_CODE.weight)
          .fontFamily(TOOL_FONT_MONO)
          .fontColor(this.diffLineColor(line))
          .width(TOOL_DIFF_PREFIX_WIDTH)
        Text(line.text)
          .fontSize(DsType.MD_CODE.size)
          .lineHeight(DsType.MD_CODE.lineHeight)
          .fontWeight(DsType.MD_CODE.weight)
          .fontFamily(TOOL_FONT_MONO)
          .fontColor(this.diffLineColor(line))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }

  /** 展开态：宿主真值 ∨ 模型默认（失败/被拒默认展开，用户要能直接看到错在哪） */
  private isExpanded(): boolean {
    return this.expanded
      || presentTool(this.item, toolStateLabel(this.item.toolState)).defaultExpanded;
  }

  /** ToolState → 披露行状态（终态语义高于字形，见 `DsDisclosureRow` 头注释） */
  private disclosureState(): DsDisclosureState {
    if (this.item.toolState === ToolState.RUNNING) {
      return DsDisclosureState.RUNNING;
    }
    if (this.item.toolState === ToolState.FAILED) {
      return DsDisclosureState.ERROR;
    }
    if (this.item.toolState === ToolState.REJECTED) {
      return DsDisclosureState.STOPPED;
    }
    return DsDisclosureState.IDLE;
  }

  /** 头部摘要：有对照给增删计数（源码 DiffCard 摘要同款），否则给按类别提炼的参数摘要 */
  private headerSummary(): string {
    const diff: DiffPresentation | null = this.diffOf();
    if (diff !== null) {
      return `+${diff.added} −${diff.removed}`;
    }
    const p: ToolPresentation = presentTool(this.item, toolStateLabel(this.item.toolState));
    return toolSummaryOf(p.kind, this.item.toolArgs);
  }

  private metaText(): string {
    if (this.item.elapsedMs > 0) {
      return this.item.at > 0
        ? `${formatClock(this.item.at)} · ${formatDuration(this.item.elapsedMs)}`
        : formatDuration(this.item.elapsedMs);
    }
    return '';
  }

  /** 状态 pill 底色：语义 tertiary；运行中/待定用中性底（源码只有终态 pill） */
  private pillBg(): number {
    const p: DsPalette = this.palette();
    if (this.item.toolState === ToolState.SUCCESS) {
      return p.successTertiary;
    }
    if (this.item.toolState === ToolState.FAILED) {
      return p.errorTertiary;
    }
    if (this.item.toolState === ToolState.REJECTED) {
      return p.warnTertiary;
    }
    return p.bgModulePlatform;
  }

  private pillFg(): number {
    const p: DsPalette = this.palette();
    if (this.item.toolState === ToolState.SUCCESS) {
      return p.success;
    }
    if (this.item.toolState === ToolState.FAILED) {
      return p.error;
    }
    if (this.item.toolState === ToolState.REJECTED) {
      return p.warn;
    }
    return p.labelSecondary;
  }

  private diffPrefix(line: DiffLine): string {
    if (line.kind === DiffLineKind.ADDED) {
      return '+';
    }
    if (line.kind === DiffLineKind.REMOVED) {
      return '-';
    }
    return ' ';
  }

  /** 行色：增=success / 删=error / 上下文=labelSecondary（源码 DiffBody 同款） */
  private diffLineColor(line: DiffLine): number {
    const p: DsPalette = this.palette();
    if (line.kind === DiffLineKind.ADDED) {
      return p.success;
    }
    if (line.kind === DiffLineKind.REMOVED) {
      return p.error;
    }
    return p.labelSecondary;
  }

  private diffOf(): DiffPresentation | null {
    // 【为什么只有一条判定】"失败/被拒 ⇒ 没有对照"已被"必须是成功或运行中"完全包含
    // （FAILED/REJECTED 都不在 SUCCESS/RUNNING 里），语义相同且不必同步两个条件。
    if (this.item.toolState !== ToolState.SUCCESS && this.item.toolState !== ToolState.RUNNING) {
      return null;
    }
    return presentDiff(this.item.toolName, this.item.toolArgs);
  }

  /** §FR-012：toolMeta 里的已应用 diff 数据源 */
  private parsedMeta(): Object | undefined {
    if (this.item.toolMeta.length === 0) {
      return undefined;
    }
    return parseJson(this.item.toolMeta);
  }

  private appliedDiffPresentations(): DiffPresentation[] {
    const meta: Object | undefined = this.parsedMeta();
    if (meta === undefined) {
      return [];
    }
    return presentAppliedDiffs(meta);
  }

  /** 检查当前条目是否有 applied diffs 能力 */
  private itemHasAppliedDiff(): boolean {
    const meta: Object | undefined = this.parsedMeta();
    return hasAppliedDiff(meta);
  }

  /** §FR-013：图片类型工具结果 URL */
  private imageUrl(): string | null {
    return imageResultOf(this.item);
  }

  /** §FR-014：技能名称 */
  private skillName(): string | null {
    return skillNameOf(this.item);
  }

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
    if (kind === ToolKind.SKILL) {
      return $r('sys.symbol.wand_and_stars');
    }
    return $r('sys.symbol.wrench_and_screwdriver');
  }
}
