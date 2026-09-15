/**
 * 右栏外壳（P0：AppFrame 的第三条轨道）。
 *
 * ## 它拥有什么
 *
 * 右栏的**面板本体**：标题行 + 关闭入口 + 内容（`DetailPane` 的 sections）+ 自身宽度与底色。
 * 三种呈现都在它内部：
 *
 * | `DetailPresentation` | 呈现 | 由谁提供外壳 |
 * |---|---|---|
 * | `COLUMN` | 三栏下的真右栏（与主内容并排） | 本组件自带标题行与关闭按钮 |
 * | `SIDE_PANEL` | 双栏下的**侧边浅层面板**（压在内容右缘） | 同上（宽度由宿主的夹取规则给） |
 * | `OVERLAY` | 单栏下的半模态 Sheet | **Sheet 自带关闭**（拖拽条 / 点击外部），故这里不再画关闭按钮 |
 *
 * ## 为什么"呈现"由宿主给、不在这里判定
 *
 * 它属于**几何层**（`LayoutController.detailPresentation` / `ui/ShellTracks`），
 * 由窗口宽度与形态决定。外壳只把它映射成实际布局——这与侧栏的处理一致：
 * **信息架构不随设备变，只有几何与呈现变**。
 *
 * ## 边界（本步刻意不做）
 *
 * `PanelRegistry` 里的六个右栏候选面板（文件 / 轨迹 / 工具 / 子代理 / 交付物 / 预览）
 * 目前**还没有各自的视图**——右栏内容仍是"一份 sections"，由宿主投影好传进来。
 * **P3-1 已落地**：这里按 `selectedRightPanel`（`panelId`）分派，标题取 descriptor 的 `label`；
 * 而不是继续吃一份 sections）。
 */

import { DetailPresentation, DetailSection, Fs, HarmonyIconSize, HarmonySpacing, PANEL_RIGHT_DETAIL, Sp, Sz } from 'appstate';
import { DetailPane } from '../DetailPane';
import { NativeSectionTitle } from '../NativePrimitives';

@Component
export struct RightbarShell {
  /** 呈现方式（由 `LayoutController.detailPresentation` 给；这里只映射布局） */
  @Prop presentation: DetailPresentation = DetailPresentation.COLUMN;
  /** 宽度（三栏 = 槽位宽度；侧边面板 = 夹取后的宽度；Sheet 忽略它） */
  @Prop widthVp: number = 0;
  /** 面板内容（宿主投影好的 sections） */
  @Prop sections: DetailSection[] = [];
  /**
   * 当前该显示哪个右栏面板（`NavigationState.selectedRightPanel`）。
   *
   * 【P3-1：这个 prop 让右栏第一次**真的**按面板分派】此前它无条件渲染 `DetailPane`，
   * 于是 `selectedRightPanel` 在模型里躺了好几轮没有消费者（"通道有、没接"）。
   * 现在：可用面板由 `PanelRegistry` 决定（只有「详情」有内容），选择经注册表校验，
   * 视图只按 id 分派 —— 后续把某个候选面板的内容视图做出来，只需把它的 `available` 改成 true。
   */
  @Prop panelId: string = '';
  /** 当前面板的中文名（标题行用；来自 descriptor 的 `label`，找不到时由宿主兜底） */
  @Prop panelLabel: string = '详情';

  onClose: () => void = () => {
  };
  onLineTap: (section: string, text: string) => void = () => {
  };

  /** 并排（真右栏）与侧边浅层面板共用一套带标题行的形态 */
  @Builder
  framedBody() {
    Column() {
      Row({ space: Sp.S }) {
        Text(this.panelLabel)
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Button() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(HarmonyIconSize.INLINE)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .accessibilityText(`关闭${this.panelLabel}面板`)
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .height(Sz.TOUCH_MIN)
      .padding({ left: Sp.M, right: Sp.S })

      Divider().color($r('sys.color.comp_divider'))

      // 按面板 id 分派：目前只有「详情」有内容（其余候选的 available 是 false，选不进来）
      if (this.panelId === PANEL_RIGHT_DETAIL) {
        DetailPane({
          sections: this.sections,
          onLineTap: (section: string, text: string) => {
            this.onLineTap(section, text);
          }
        })
      }
    }
    .width(this.widthVp)
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }

  /** 单栏：Sheet 内容（关闭由原生 Sheet 提供，标题用区块标题而不是自造一行） */
  @Builder
  sheetBody() {
    Column({ space: HarmonySpacing.CONTAINER }) {
      NativeSectionTitle({ text: this.panelLabel, hint: '工具 / 子代理 / 交付物 / 目标 / 任务' })
      if (this.panelId === PANEL_RIGHT_DETAIL) {
        DetailPane({
          sections: this.sections,
          onLineTap: (section: string, text: string) => {
            this.onLineTap(section, text);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding(HarmonySpacing.CONTAINER)
  }

  build() {
    if (this.presentation === DetailPresentation.OVERLAY) {
      this.sheetBody()
    } else {
      this.framedBody()
    }
  }
}
