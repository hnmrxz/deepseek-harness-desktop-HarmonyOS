/**
 * 子代理卡（T023：对照 `dshmobile/ui/screens/main/SheetSubagents.kt` 复刻）。
 *
 * ## 对照结构（SheetSubagents.kt）
 *
 * 源码 `SubagentRow`：`StateDot`（Running/Idle）+ 名字 `small13` labelPrimary（weight 1）+
 * 模式 pill；点击行打开该子代理的转录。转录内：continuable 才有输入行 + 发送（Info），
 * 运行中给「中断」（`DsButton` **Danger Small**），one-shot 只读并说明。
 * 本侧同构：状态点 + 名字 + 状态 pill 的一行；点卡片开转录（§FR-045）；
 * 动作行给「追问 / 中断」（§FR-046/047），中断用 Danger Small。
 *
 * ## 状态点映射（SubagentStatus → StateDotState）
 *
 * 运行中=RUNNING（3x3 追逐矩阵）/ 完成=DONE / 中断=WARNING / 失败=ERROR——
 * 源码只有 Running/Idle 两态，本仓的四种终态是**既有数据面**（`subagentStatusLabel`），
 * 映射到状态点语义色，不发明第五种读法。
 *
 * ## 为什么它只吃 `item`（保留 v1）
 *
 * 组件要的是"条目自身"的投影：钟点用 `item.at > 0` + `formatClock`（模型纯函数），
 * 不往组件里塞 `meta` 字符串（少一个 prop，也少一处"两边格式可能不一致"）。
 *
 * ## §FR-045/046/047：子代理交互能力（保留 v1）
 *
 * 点击卡片可打开子代理转录视图；转录视图内可追问（`promptSubagent`）和中断（`interruptSubagent`）。
 */

import {
  DsPalette,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  HarmonyBorder,
  SubagentStatus,
  TrajectoryItem,
  formatClock,
  formatDuration,
  subagentCanInterrupt,
  subagentCanPrompt,
  subagentStatusLabel,
  dsPaletteOf,
} from 'appstate';
import { DsButton, DsButtonSize, DsButtonVariant, DsPill, DsStateDot, DsStateDotState, installDsSystemDarkWatch } from './NativePrimitives';

/* ───────── 组件级度量（SheetSubagents.kt 的 dp 字面量，逐条标注出处） ───────── */

/** 正文预览最多 4 行（源码转录区无限行；卡内预览是 v1 形态，行数取"两屏内可扫完"） */
const SUBAGENT_BODY_MAX_LINES: number = 4;
/** 等宽/系统字体栈（Type.kt system UI stack） */
const SUBAGENT_FONT_SANS: string = 'sans-serif';

@Component
export struct SubagentCard {
  /** 要显示的子代理条目 */
  @Prop item: TrajectoryItem;
  /** §FR-045：点击卡片打开子代理转录视图 */
  onOpenTranscript: () => void = () => {
  };
  /** §FR-047：中断子代理 */
  onInterruptSubagent: () => void = () => {
  };

  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  /** 从 item.subagentStatus 字符串解析为枚举（空串默认 RUNNING） */
  private statusOf(): SubagentStatus {
    const s: string = this.item.subagentStatus;
    if (s === SubagentStatus.RUNNING) {
      return SubagentStatus.RUNNING;
    }
    if (s === SubagentStatus.COMPLETED) {
      return SubagentStatus.COMPLETED;
    }
    if (s === SubagentStatus.INTERRUPTED) {
      return SubagentStatus.INTERRUPTED;
    }
    if (s === SubagentStatus.FAILED) {
      return SubagentStatus.FAILED;
    }
    // 有名字但没状态 = 还在运行
    return SubagentStatus.RUNNING;
  }

  /** 状态点映射（见文件头：四种终态是本仓既有数据面） */
  private dotState(): DsStateDotState {
    const s: SubagentStatus = this.statusOf();
    if (s === SubagentStatus.RUNNING) {
      return DsStateDotState.RUNNING;
    }
    if (s === SubagentStatus.COMPLETED) {
      return DsStateDotState.DONE;
    }
    if (s === SubagentStatus.INTERRUPTED) {
      return DsStateDotState.WARNING;
    }
    return DsStateDotState.ERROR;
  }

  /** 失败/中断的状态 pill 用 warn 底（源码 warn pill 同款） */
  private statusWarn(): boolean {
    const s: SubagentStatus = this.statusOf();
    return s === SubagentStatus.FAILED || s === SubagentStatus.INTERRUPTED;
  }

  build() {
    Column({ space: DsSpacing.SMALL }) {
      // 头行（对照 SubagentRow：StateDot + small13 名字 + 状态 pill）
      Row({ space: DsSpacing.SMALL }) {
        DsStateDot({ state: this.dotState() })
        Text(`子代理 ${this.item.subagentName}`)
          .fontSize(DsType.SMALL_13.size)
          .lineHeight(DsType.SMALL_13.lineHeight)
          .fontWeight(DsType.SMALL_13.weight)
          .fontFamily(SUBAGENT_FONT_SANS)
          .fontColor(this.palette().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        DsPill({ text: subagentStatusLabel(this.statusOf()), warn: this.statusWarn() })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 正文预览（v1 功能面保留；卡内截断，全文在转录视图）
      if (this.item.body.length > 0) {
        Text(this.item.body)
          .fontSize(DsType.STD_14.size)
          .lineHeight(DsType.STD_14.lineHeight)
          .fontWeight(DsType.STD_14.weight)
          .fontFamily(SUBAGENT_FONT_SANS)
          .fontColor(this.palette().labelSecondary)
          .maxLines(SUBAGENT_BODY_MAX_LINES)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      // 钟点/时长（v1 meta 收编于此；caption11 + labelCaption）
      if (this.metaText().length > 0) {
        Text(this.metaText())
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(SUBAGENT_FONT_SANS)
          .fontColor(this.palette().labelCaption)
          .width('100%')
      }

      // 动作行（§FR-046/047；中断 = Danger Small，对照源码 interrupt 按钮）
      if (this.canPrompt() || this.canInterrupt()) {
        Row({ space: DsSpacing.SMALL }) {
          if (this.canPrompt()) {
            DsButton({
              text: '追问',
              variant: DsButtonVariant.GHOST,
              buttonSize: DsButtonSize.SMALL,
              a11y: `追问子代理 ${this.item.subagentName}`,
              onTap: () => {
                // 追问需要输入框，这里打开转录视图（转录视图内有输入行，源码同款）
                this.onOpenTranscript();
              }
            })
          }
          if (this.canInterrupt()) {
            DsButton({
              text: '中断',
              variant: DsButtonVariant.DANGER,
              buttonSize: DsButtonSize.SMALL,
              a11y: `中断子代理 ${this.item.subagentName}`,
              onTap: () => {
                this.onInterruptSubagent();
              }
            })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: DsSpacing.MEDIUM, right: DsSpacing.MEDIUM, top: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
    .borderRadius(DsShape.MENU)
    .backgroundColor(this.palette().bgModulePlatform)
    .borderWidth(HarmonyBorder.HAIRLINE)
    .borderColor(this.palette().borderL2)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onOpenTranscript();
    })
    .accessibilityText(`子代理 ${this.item.subagentName}，${subagentStatusLabel(this.statusOf())}，点击打开转录`)
  }

  private canPrompt(): boolean {
    return subagentCanPrompt(this.statusOf());
  }

  private canInterrupt(): boolean {
    return subagentCanInterrupt(this.statusOf());
  }

  private metaText(): string {
    if (this.item.elapsedMs > 0) {
      return this.item.at > 0
        ? `${formatClock(this.item.at)} · ${formatDuration(this.item.elapsedMs)}`
        : formatDuration(this.item.elapsedMs);
    }
    return '';
  }
}
