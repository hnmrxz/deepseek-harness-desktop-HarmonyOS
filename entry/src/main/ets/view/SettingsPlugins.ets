/**
 * 设置 · 插件（P4-2：从 1878 行的 `SettingsPane` 拆出的**第一个域组件**）。
 *
 * ## 这一个域回答什么
 *
 * "我要改什么"：随包发版的插件清单 + **可安装性三态徽标**（纯 JS / 需发版 / 待确认，取值来自
 * `appstate` 的 `classifyPlugin` 契约）。只读清单是另一个域（`SettingsInventory`）——
 * 官方把两者分成两个分区（`settings-plugins` / `settings-plugin-inventory`），
 * 因为"改什么"（有风险）与"有什么"（只查证）不是同一件事。
 *
 * ## 一条硬边界写在界面上（不是藏在文档里）
 *
 * 端侧**无法创建进程**（上游 `dsh plugin add` 走 `spawnSync("pnpm")`，见 D6 E15/E86）⇒
 * 插件只能随核心包发版。所以这里**不提供任何安装/市场入口**（此前那个「市场」文字点了没反应，
 * 是假入口），并把原因写在卡片上方。
 */

import { Fs, PluginItem, Radius, Sp, classifyPlugin, pluginSummary } from 'appstate';
import { PluginNative } from 'appstate';
import type { PluginRow } from 'appstate';

@Component
export struct SettingsPlugins {
  /** 插件清单（随包发版 + 用户行叠加，宿主投影后传入） */
  @Prop plugins: PluginItem[] = [];

  build() {
    // 【ArkUI 约束】组件的 build() 只能有一个根节点 ⇒ 多段内容包进 Column
    Column({ space: Sp.S }) {
      Row({ space: Sp.S }) {
        Text(pluginSummary(this.plugins))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .layoutWeight(1)
      }
      .width('100%')

      // 【为什么这里只有说明、没有"市场"按钮】原实现有个「市场」文字，点了没有任何反应——
      // 它是个假入口。而"能不能运行时安装插件"在端侧有一个**硬边界**（E86）：
      // 上游 `dsh plugin add` 的实现是 `spawnSync("pnpm", …)`（`dsh/lib/plugin-Ddi42qoW.js:109`），
      // 而鸿蒙不允许应用创建进程（D6 E15）⇒ 纯 JS 插件同样装不了，"只有原生插件装不了"是**错**的。
      // 所以：不提供任何安装/市场入口，只如实列出随包发版的插件与启停状态。
      // 另外上游清单不含「是否含原生模块」，因此下方一律标「待确认」——不给会失败的承诺（D6 §6.2）。
      Text('端侧无法创建进程（上游安装通道 `dsh plugin add` 经 `spawnSync("pnpm")`，见 D6 E15/E86），因此插件只能随核心包发版，这里不提供安装或市场入口。上游插件清单也不含「是否含原生模块」，故一律标注「待确认」。')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')

      ForEach(this.plugins, (p: PluginItem) => {
        Row({ space: Sp.M }) {
          Circle({ width: 8, height: 8 })   // token-exempt: 状态点几何（与插件行原样一致，搬迁不改视觉）
            .fill(p.phase === 'active' ? $r('sys.color.confirm') : $r('sys.color.font_tertiary'))
          Column({ space: 2 }) {
            Text(p.moduleName)
              .fontSize(Fs.SECONDARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(`${p.entryId} · ${p.enabled ? '已启用' : '已禁用'}${p.phase.length > 0 ? ` · ${p.phase}` : ''}`)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          }
          .layoutWeight(1)
          if (p.firstParty) {
            Text('第一方')
              .fontSize(Fs.CAPTION_XS)
              .fontColor($r('sys.color.font_tertiary'))
              .padding({ left: 5, right: 5 })   // token-exempt: 徽标药丸内边距
              .borderRadius(5)   // token-exempt: 徽标药丸圆角
              .backgroundColor($r('sys.color.background_primary'))
          }
          // 可安装性徽标：取值由 appstate 的三态契约给出（纯 JS / 需发版 / 待确认）
          Text(this.pluginRowOf(p).badge)
            .fontSize(Fs.CAPTION_XS)
            .fontColor($r('sys.color.font_tertiary'))
            .padding({ left: 5, right: 5 })   // token-exempt: 徽标药丸内边距
            .borderRadius(5)   // token-exempt: 徽标药丸圆角
            .backgroundColor($r('sys.color.background_primary'))
        }
        .width('100%')
        .padding(Sp.M)
        .borderRadius(Radius.M)
        .backgroundColor($r('sys.color.background_secondary'))
      }, (p: PluginItem) => p.entryId)

      Text('插件的安装与卸载由 Host 侧执行；端侧只展示状态与触发操作（D1 §7.6.4）。')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
    .width('100%')
  }

  private pluginRowOf(p: PluginItem): PluginRow {
    return classifyPlugin(p.moduleName, '', PluginNative.UNKNOWN);
  }
}
