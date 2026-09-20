/**
 * 消息反馈面板（T023：对照 `dshmobile/ui/screens/main/FeedbackDialog.kt` 复刻）。
 *
 * ## 对照结构（FeedbackDialog.kt）
 *
 * 源码是 AlertDialog：取向标题 + 说明输入（`feedback_note`）+ 错误行（error 色）+
 * 「移除」按钮（**已有评价时才出现**：`current != null`）+ 发送（busy/loaded 才可点）+ 取消。
 * 本侧保留 v1 的**内嵌面板**形态（`MessageRow` 在消息下方展开，改弹窗会破坏宿主接线），
 * 但把三块语义搬齐：① 错误行用 error 色如实透出；② **新增可选** `hasExisting` +
 * `onRemove`——宿主接上后显示「撤回评价」（源码的 Remove 分支）；③ busy/loaded 门控
 * 在本仓由宿主持有（提交期间宿主自会忽略重复提交），面板不重复建状态。
 *
 * ## 类别 chips（v1 功能面，保留）
 *
 * 源码对话框没有类别（上游契约只要 note）；本仓契约给了 7 个类别
 * （`FEEDBACK_CATEGORIES`，不自己发明）。未选即"未分类"——契约里 `category` 可选，
 * 所以**不强迫分类**。视觉换成设计系统的 `DsPill`（可点 + 选中态）。
 *
 * ## 与宿主的边界（保留 v1）
 *
 *  · 初值（已存的类别/说明）由宿主在**打开那一刻**给；之后编辑过程中的变化不再回灌
 *    （否则用户打字打到一半会被覆盖）。
 *  · 提交只报"用户选了什么"（`onSubmit(category, note)`）；**调中枢是宿主的副作用**。
 */

import {
  FEEDBACK_CATEGORIES,
  DsPalette,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  HarmonyBorder,
  dsPaletteOf,
} from 'appstate';
import type { FeedbackCategory } from 'appstate';
import { DsPill, installDsSystemDarkWatch } from './NativePrimitives';

/* ───────── 组件级度量（FeedbackDialog.kt 的字面量，逐条标注出处） ───────── */

/** 等宽/系统字体栈（Type.kt system UI stack） */
const FEEDBACK_FONT_SANS: string = 'sans-serif';

@Component
export struct MessageFeedback {
  /** 打开那一刻的已存类别（''=未分类） */
  @Prop initialCategory: string = '';
  /** 打开那一刻的已存说明 */
  @Prop initialNote: string = '';
  /** 宿主回执（空串 = 不显示；失败原因原样透出，见宿主的 `feedbackNoticeText`） */
  @Prop notice: string = '';
  /**
   * 该消息已有评价（新增**可选**：对照源码 `current != null` 分支——已有评价时给
   * 「撤回评价」入口；宿主不接 = 不显示，不破坏既有调用）。
   */
  @Prop hasExisting: boolean = false;

  /** 提交：只报"用户选了什么"，调用中枢是宿主的副作用 */
  onSubmit: (category: string, note: string) => void = () => {
  };
  /** 撤回已有评价（新增**可选**；`hasExisting` 为 true 时显示） */
  onRemove: () => void = () => {
  };
  onCancel: () => void = () => {
  };

  @State category: string = '';
  @State note: string = '';

  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
    this.category = this.initialCategory;
    this.note = this.initialNote;
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Column({ space: DsSpacing.SMALL }) {
      Text('为什么？可留空')
        .fontSize(DsType.CAPTION_11.size)
        .lineHeight(DsType.CAPTION_11.lineHeight)
        .fontWeight(DsType.CAPTION_11.weight)
        .fontFamily(FEEDBACK_FONT_SANS)
        .fontColor(this.palette().labelTertiary)
        .width('100%')

      // 类别 chips（v1 契约功能；视觉 = DsPill 选中态）
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(FEEDBACK_CATEGORIES, (c: FeedbackCategory) => {
          Column() {
            DsPill({
              text: c.label,
              selected: this.category === c.id,
              clickable: true,
              a11y: `评价原因：${c.label}`,
              onTap: () => {
                // 再点一次取消选择 ⇒ 回到"未分类"（契约里 category 可选，不强迫分类）
                this.category = this.category === c.id ? '' : c.id;
              }
            })
          }
          .margin({ right: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
        }, (c: FeedbackCategory) => `${c.id}:${this.category === c.id ? 1 : 0}`)
      }
      .width('100%')

      // 说明输入（对照源码 OutlinedTextField + feedback_note；键盘直输，宿主不回灌）
      TextInput({ text: this.note, placeholder: '补充说明（可选）' })
        .fontSize(DsType.STD_14.size)
        .fontFamily(FEEDBACK_FONT_SANS)
        .fontColor(this.palette().labelPrimary)
        .placeholderColor(this.palette().labelTertiary)
        .placeholderFont({ size: DsType.STD_14.size })
        .height(DsSpacing.TOUCH_TARGET)
        .width('100%')
        .onChange((v: string) => {
          this.note = v;
        })

      // 错误/回执行（对照源码 `error?.let { Text(it, color = error) }`）
      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(FEEDBACK_FONT_SANS)
          .fontColor(this.palette().error)
          .width('100%')
      }

      // 动作行（对照源码三个 TextButton 的排列：移除（已有评价）/ 发送 / 取消）
      Row({ space: DsSpacing.MEDIUM }) {
        if (this.hasExisting) {
          Text('撤回评价')
            .fontSize(DsType.STD_14.size)
            .lineHeight(DsType.STD_14.lineHeight)
            .fontWeight(DsType.STD_14.weight)
            .fontFamily(FEEDBACK_FONT_SANS)
            .fontColor(this.palette().warnLabel)
            .onClick(() => {
              this.onRemove();
            })
            .accessibilityText('撤回已提交的评价')
        }
        Text('提交')
          .fontSize(DsType.STD_14_STRONG.size)
          .lineHeight(DsType.STD_14_STRONG.lineHeight)
          .fontWeight(DsType.STD_14_STRONG.weight)
          .fontFamily(FEEDBACK_FONT_SANS)
          .fontColor(this.palette().accent)
          .onClick(() => {
            this.onSubmit(this.category, this.note);
          })
          .accessibilityText('提交评价')
        Text('取消')
          .fontSize(DsType.STD_14.size)
          .lineHeight(DsType.STD_14.lineHeight)
          .fontWeight(DsType.STD_14.weight)
          .fontFamily(FEEDBACK_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
          .onClick(() => {
            this.onCancel();
          })
          .accessibilityText('取消评价')
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(DsSpacing.MEDIUM)
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().bgLayer1)
    .borderWidth(HarmonyBorder.HAIRLINE)
    .borderColor(this.palette().borderL2)
    .alignItems(HorizontalAlign.Start)
    .accessibilityText('消息反馈：选择原因后可提交，也可留空')
  }
}
