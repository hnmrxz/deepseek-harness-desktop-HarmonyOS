/**
 * 对话里的**斜杠命令**条目（P7-13）。
 *
 * ## 它替代了什么
 *
 * 上游把命令的生命周期写成两帧（`command/run` → `command/done`，靠 `commandId` 配对），
 * 并在对话里渲染成一个**持久的过程节点**（`dsh-client-ui-commands`："the host executor
 * durably logged the lifecycle … and the outcome renders as a persistent flow node"）。
 * 我们此前把这两帧当成"内部事件"隐掉，于是：**执行一条命令后，对话里什么也不会出现**
 * ——回执在输入区一闪而过，用户无法回看"刚才那条命令到底做了什么"。
 *
 * ## 一条命令的三个状态
 *
 * | `commandKind` | 显示 | 为什么 |
 * |---|---|---|
 * | `'running'`（只有 `command/run`） | 「进行中」中性徽标 | 还没收到 `done`；**不预判成功** |
 * | `'success'` | 「已完成」品牌色徽标 | 上游 `kind: 'success'` |
 * | `'error'` | 「失败」警示色徽标 + 文本 | 上游 `kind: 'error'`，`text` 就是错误说明 |
 *
 * `commandKind` 为空（老 Host 没给 `kind`）时显示「已结束」——**如实说明"没告诉我们结局"**，
 * 而不是替它填一个"成功"。
 *
 * ## 命令原文可能不含参数
 *
 * 上游按 `recordInput === false` **省略** `args`（含敏感参数的命令）⇒ 这时只显示命令名，
 * 不补任何占位（"（有参数但没显示）"这类话在界面上是噪音）。
 */

import { Fs, HarmonyColor, Radius, Sp, TrajectoryItem } from 'appstate';
import { Border } from 'appstate';

/** 一条斜杠命令的卡片：命令原文 + 结局徽标 + 结局文本 */
@Component
export struct CommandRow {
  /** 要显示的命令条目 */
  @Prop item: TrajectoryItem;

  /** 命令原文（`/name args`）；`title` 空时退回 id，绝不显示空白行 */
  private line(): string {
    if (this.item.title.length > 0) {
      return this.item.title;
    }
    return this.item.commandId.length > 0 ? `命令 ${this.item.commandId}` : '命令';
  }

  /** 结局文案（三种已知结局 + 一种"没告诉我们"） */
  private stateLabel(): string {
    if (this.item.commandKind === 'running') {
      return '进行中';
    }
    if (this.item.commandKind === 'success') {
      return '已完成';
    }
    if (this.item.commandKind === 'error') {
      return '失败';
    }
    return '已结束';
  }

  /** 结局颜色（中性 / 品牌 / 警示） */
  private stateColor(): Resource {
    if (this.item.commandKind === 'success') {
      return HarmonyColor.BRAND;
    }
    if (this.item.commandKind === 'error') {
      return HarmonyColor.ALERT;
    }
    return HarmonyColor.TEXT_TERTIARY;
  }

  build() {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        // 命令原文用等宽感更强的小字号：它是**要照抄的东西**，不是叙事
        Text(this.line())
          .fontSize(Fs.CAPTION)
          .fontColor(HarmonyColor.TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.stateLabel())
          .fontSize(Fs.CAPTION_XS)
          .fontColor(this.stateColor())
      }
      .width('100%')

      // 结局文本（失败时上游给的就是错误说明；成功时可能没有 ⇒ 不显示空行）
      if (this.item.body.length > 0) {
        Text(this.item.body)
          .fontSize(Fs.CAPTION)
          .fontColor(this.item.commandKind === 'error' ? HarmonyColor.ALERT : HarmonyColor.TEXT_SECONDARY)
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding(Sp.S)
    .borderRadius(Radius.S)
    .backgroundColor(HarmonyColor.SURFACE_TERTIARY)
    .borderWidth(Border.HAIRLINE)
    .borderColor(HarmonyColor.DIVIDER)
    .accessibilityText(`命令 ${this.line()}：${this.stateLabel()}`
      + (this.item.body.length > 0 ? `，${this.item.body}` : ''))
  }
}
