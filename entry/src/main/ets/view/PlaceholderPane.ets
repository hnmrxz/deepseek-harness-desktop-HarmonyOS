/**
 * 占位面板：用于尚未实现的一级页面（工作区 / 设置 / 详情栏）。
 *
 * 有意的设计：明确写出「将实现什么」，避免出现空白的"点了没反应"页面
 * （D3 §4 文案纪律：错误与空态都要说明「可以做什么」）。
 */

import { Fs, Sp } from 'appstate';

@Component
export struct PlaceholderPane {
  @Prop title: string = '';
  @Prop hint: string = '';

  build() {
    Column({ space: Sp.M }) {
      SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
        .fontSize(36)
        .fontColor([$r('sys.color.font_tertiary')])
      Text(this.title)
        .fontSize(Fs.TITLE_S)
        .fontColor($r('sys.color.font_secondary'))
      Text(this.hint)
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: Sp.XL, right: Sp.XL })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
