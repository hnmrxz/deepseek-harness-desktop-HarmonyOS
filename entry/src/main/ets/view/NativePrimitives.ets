/**
 * HarmonyOS 原生原语（P1.5）——视图层共用的最小构件。
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

import { HarmonyColor, HarmonyMotion, HarmonyRadius, HarmonySpacing, HarmonyTouch, HarmonyType } from 'appstate';

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
      return HarmonyColor.BRAND;
    }
    if (this.tone === 'alert') {
      return HarmonyColor.ALERT;
    }
    return HarmonyColor.TEXT_SECONDARY;
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
      .backgroundColor(this.active ? HarmonyColor.SURFACE_TERTIARY : HarmonyColor.SURFACE_RAISED)
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
