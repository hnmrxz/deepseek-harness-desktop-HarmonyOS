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
  /**
   * 本回合改动量（官方那张卡上的 `+86 -9`）。
   *
   * 官方把它和"已编辑 N 个文件"放在同一行；我们此前只有文件数。
   * 传空串表示"没有可说的行数"（没有写类调用，或增删都是 0）⇒ 这一格不渲染。
   * **由父组件算好传进来**（判据在纯模型 `turnChangeStatOf/changeStatText`），
   * 视图不自己扫一遍过程条目。
   */
  @Prop changeText: string = '';
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
        Row({ space: Sp.S }) {
          Text(producedRowText(this.files.length, PRODUCED_MAX_CHIPS))
            .fontSize(Fs.CAPTION_XS)
            .fontColor(HarmonyColor.TEXT_TERTIARY)
            .layoutWeight(1)
          // 官方把 `+86 -9` 与文件数放在同一行的右端
          if (this.changeText.length > 0) {
            Text(this.changeText)
              .fontSize(Fs.CAPTION_XS)
              .fontColor(HarmonyColor.TEXT_TERTIARY)
          }
        }
        .width('100%')
        Scroll() {
          Row({ space: Sp.XS }) {
            ForEach(this.shown(), (file: ProducedFile) => {
              NativeChip({
                label: file.name,
                active: false,
                /*
                 * 逐文件 ±（官方卡里每个文件后面跟 `+15 -2`）走**无障碍文案**而不是 chip 正文：
                 * chip 在手机上本来就是省地方的形态，塞进 `名称 +15 -2` 会把它撑成两三倍宽，
                 * 而这一行的左端已经给了"本回合总共多少"。读屏用户在这里拿到的是完整信息，
                 * 看得见的用户拿到的是"总共多少"——**不是丢掉，是分层**。
                 * （可视呈现等一个支持尾随计数的 chip 变体，登记在方案里。）
                 */
                a11y: `打开 ${file.path}，本次改动 +${file.added} −${file.removed}`,
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
