/**
 * 回合尾部的**产出文件行**（P7-21，对齐官方 `dsh-client-ui-deliverables` 的 turn-tail 槽位）。
 *
 * ## 它解决什么
 *
 * 官方把"这一回合产出了哪些文件"作为**回合尾部的一行可点条目**渲染
 * （`conversation.chat.turnTail` 槽位，`ProducedFiles` 组件）。规则见
 * `appstate/model/ProducedFiles.ets` 的文件头（来源是成功的写类工具调用，
 * **不是**回答正文里有没有提到文件名）。
 *
 * 我们此前只有 `deliverables/presented` 事件（取决于模型是否上报）与右栏那份按条目筛的清单 ⇒
 * agent 改了 5 个文件但没上报时，用户在界面上**看不到产出了什么**，只能一条条翻工具卡。
 *
 * ## 点击必须真的到得了文件（否则就是又一个假入口）
 *
 * 点一枚 chip 做两件事：① 中枢 `openFile()` 把内容读进 `filePreview`；
 * ② 宿主把主导航切到**工作区页**（文件预览就在那里可见）。只做 ① 在手机上会"点了没反应"
 * ——右栏在单栏形态下并不在屏幕上。
 *
 * ## 宽度与条数
 *
 * 官方为这一行写了 `fitProducedFiles()`（按可用宽度决定显示几个 chip，余量用"N 个"占位）。
 * 我们在 ArkUI 里交给 `Scroll` 横滑 + 一个上限（`PRODUCED_MAX_CHIPS`），
 * 并把总数写在文案里（`producedRowText`）——**不假装知道可用宽度**，也不用测量回调去猜
 * （本仓在 `MarkdownRenderer` 上吃过"猜几何"的亏）。
 */

import { Fs, HarmonyColor, producedRowText, ProducedFile, Radius, Sp } from 'appstate';
import { Border } from 'appstate';
import { NativeChip } from './NativePrimitives';

/** 一行里最多显示几枚 chip（超出的部分由文案交代总数） */
const PRODUCED_MAX_CHIPS: number = 6;

/** 一个回合的产出文件行（0 个文件时整行不渲染） */
@Component
export struct ProducedFilesRow {
  /** 该回合产出的文件（顺序即首次出现顺序） */
  @Prop files: ProducedFile[] = [];
  /** 点一枚 chip：宿主负责打开预览并切到能看见它的页面 */
  onOpen: (path: string, name: string) => void = () => {
  };

  /** 要画出来的那几枚 */
  private shown(): ProducedFile[] {
    return this.files.length > PRODUCED_MAX_CHIPS
      ? this.files.slice(0, PRODUCED_MAX_CHIPS)
      : this.files;
  }

  build() {
    if (this.files.length > 0) {
      Column({ space: Sp.XS }) {
        Text(producedRowText(this.files.length, PRODUCED_MAX_CHIPS))
          .fontSize(Fs.CAPTION_XS)
          .fontColor(HarmonyColor.TEXT_TERTIARY)
          .width('100%')
        Scroll() {
          Row({ space: Sp.XS }) {
            ForEach(this.shown(), (file: ProducedFile) => {
              NativeChip({
                label: file.name,
                active: false,
                a11y: `打开 ${file.path}`,
                onTap: () => {
                  this.onOpen(file.path, file.name);
                }
              })
            }, (file: ProducedFile) => file.path)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
      .padding({ left: Sp.M, right: Sp.M, top: Sp.XS, bottom: Sp.XS })
      .borderRadius(Radius.S)
      .borderWidth(Border.HAIRLINE)
      .borderColor(HarmonyColor.DIVIDER)
      .accessibilityText(producedRowText(this.files.length, PRODUCED_MAX_CHIPS))
    }
  }
}
