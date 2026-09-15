/**
 * 轨迹条目的**事件详情**卡（P7-4）。
 *
 * ## 它对应官方的什么
 *
 * 官方 `dsh-client-ui-trajectory` 点一条事件会开出「事件详情」面板（`details.event`），
 * 里面是成对字段（状态 / 模型 / 工具调用 / 结果 / 错误 / 来源 …），可关闭。
 * 我们做**同一件事的等价物**：类别与状态、名字或模型、参数、结果/正文、耗时 ——
 * **有数据的行才出现**（判定在 `appstate/model/TrajectoryDetail`，有 fixture 钉住）。
 *
 * ## 挂载点（两处共用这一份）
 *
 *   · 会话头的轨迹视图里（时间线下面，点格子即聚焦）；
 *   · 右栏「轨迹」面板里（与时间线同屏）。
 * 单栏手机上右栏是 Sheet ⇒ 同一份组件在三种形态下都在场。
 */

import { Fs, Radius, Sp, Sz, TRAJECTORY_DETAIL_TITLE, trajectoryDetailRows } from 'appstate';
import type { DetailRow, TrajectoryItem } from 'appstate';

@Component
export struct TrajectoryInspector {
  /** 聚焦的条目；`undefined` = 没有聚焦（整卡不渲染，由挂载点判断） */
  @Prop item: TrajectoryItem | undefined = undefined;
  /** 关闭（清掉聚焦）。空实现 = 不显示关闭入口（右栏那种"一直有焦点"的场景） */
  onClose: () => void = () => {
  };

  /** 构建一次行数组（`@Builder` 内联表达式里不调用方法：本仓实测过它不重算） */
  private rows(): DetailRow[] {
    return this.item === undefined ? [] : trajectoryDetailRows(this.item);
  }

  build() {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        Text(TRAJECTORY_DETAIL_TITLE)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .layoutWeight(1)
        Text('关闭')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .height(Sz.TOUCH_MIN)
          .padding({ left: Sp.S, right: Sp.S })
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')

      ForEach(this.rows(), (row: DetailRow) => {
        Column({ space: 2 }) {
          Text(row.label)
            .fontSize(Fs.CAPTION_XS)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
          Text(row.value)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .maxLines(6)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }, (row: DetailRow) => row.label)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
  }
}
