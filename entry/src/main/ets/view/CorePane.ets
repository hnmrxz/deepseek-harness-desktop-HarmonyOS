/**
 * 核心页（Core Pane）—— 端侧自足架构下的新一级页面（D6 §2/§6）。
 *
 * 它回答四个问题（每个都必须在界面上有答案，不能靠猜）：
 *   1. 现在是什么状态？（未接线 / 未安装 / 解包中 / 启动中 / 就绪 / 降级 / 失败）
 *   2. 跑的是哪一版核心、哪个 profile、运行时是什么？（运行时事实表）
 *   3. 有哪些版本、能不能切、能不能回滚？（版本列表）
 *   4. 插件能不能装？（纯 JS 可装；含原生 .node 的必须随应用发版——这是鸿蒙的硬约束）
 *
 * 纪律（D3 §4）：本页**没有桩数据**。未探测的事实写"未探测"并给出探测条件；
 * 不可用的动作必须显示原因，不允许静默禁用或点了没反应。
 *
 * 本组件只做呈现：所有判据来自 appstate 的呈现契约（Core.buildCoreView），
 * 因此"某个阶段该显示什么"可以在没有设备的情况下被单测覆盖。
 */

import {
  CoreActionSpec,
  CoreFact,
  CorePhase,
  CoreVersionRow,
  CoreViewState,
  emptyCoreView,
  Fs,
  PluginRow,
  Radius,
  Sp,
  Sz
} from 'appstate';

@Component
export struct CorePane {
  @Prop view: CoreViewState = emptyCoreView();
  /** 动作点击（由宿主决定实现；未实现的动作也必须给出如实提示） */
  onAction: (id: string) => void = () => {
  };
  /** 选择某个版本作为切换目标 */
  onSelectVersion: (version: string) => void = () => {
  };

  build() {
    Scroll() {
      Column({ space: Sp.M }) {
        this.statusCard()
        this.factsCard()
        this.versionsCard()
        this.pluginsCard()
      }
      .width('100%')
      .padding(Sp.M)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart)
  }

  // ── 状态卡 ────────────────────────────────────────────────────────────
  @Builder
  statusCard() {
    Column({ space: Sp.S }) {
      Row({ space: Sp.S }) {
        Text(this.view.badge)
          .fontSize(Fs.CAPTION)
          .fontColor(this.phaseColor())
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor($r('sys.color.background_primary'))
        if (this.view.currentVersion.length > 0) {
          Text(`v${this.view.currentVersion}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_secondary'))
        }
        if (this.view.profileName.length > 0) {
          Text(`profile: ${this.view.profileName}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')

      Text(this.view.title)
        .fontSize(Fs.TITLE_L)
        .fontWeight(FontWeight.Medium)
        .width('100%')

      Text(this.view.detail)
        .fontSize(Fs.SECONDARY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      // 动作行：横排 + 允许换行（不用 LengthMetrics，避免引入额外导入）
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.view.actions, (a: CoreActionSpec) => {
          this.actionButton(a)
        }, (a: CoreActionSpec) => a.id)
      }
      .width('100%')
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_primary'))
  }

  @Builder
  actionButton(a: CoreActionSpec) {
    Column({ space: 2 }) {
      Text(a.label)
        .fontSize(Fs.SECONDARY)
        .fontColor(a.enabled ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
        .padding({ left: Sp.M, right: Sp.M, top: Sp.XS, bottom: Sp.XS })
        .borderRadius(Radius.S)
        .backgroundColor($r('sys.color.background_secondary'))
        .margin({ right: Sp.S, bottom: Sp.XS })
        .onClick(() => {
          if (a.enabled) {
            this.onAction(a.id);
          }
        })
      // 不可用时把原因写在按钮下面——"禁用但不说为什么"是这一页最不能犯的错
      if (!a.enabled && a.reason.length > 0) {
        Text(a.reason)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .constraintSize({ maxWidth: 240 })
      }
    }
  }

  // ── 运行时事实 ────────────────────────────────────────────────────────
  @Builder
  factsCard() {
    Column({ space: Sp.S }) {
      Text('运行时')
        .fontSize(Fs.SECONDARY)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      ForEach(this.view.facts, (f: CoreFact) => {
        Column({ space: 2 }) {
          Row({ space: Sp.S }) {
            Text(f.label)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .layoutWeight(1)
            Text(f.value)
              .fontSize(Fs.CAPTION)
              .fontColor(this.factColor(f.verdict))
          }
          .width('100%')
          if (f.verdict === 'unknown' && f.hint.length > 0) {
            Text(f.hint)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          }
        }
        .width('100%')
      }, (f: CoreFact) => f.label)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_primary'))
  }

  // ── 版本 ──────────────────────────────────────────────────────────────
  @Builder
  versionsCard() {
    Column({ space: Sp.S }) {
      Text('核心版本')
        .fontSize(Fs.SECONDARY)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      if (this.view.versions.length === 0) {
        Text('还没有安装任何核心版本。核心随应用内置，首次启动会自动解包；也可以在这里导入核心包。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      } else {
        ForEach(this.view.versions, (row: CoreVersionRow) => {
          Column({ space: 2 }) {
            Row({ space: Sp.S }) {
              Text(row.version)
                .fontSize(Fs.SECONDARY)
                .layoutWeight(1)
              Text(row.badge)
                .fontSize(Fs.CAPTION)
                .fontColor(row.badge === '当前' ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(6)
                .backgroundColor($r('sys.color.background_secondary'))
              if (row.selectable) {
                Text('切换')
                  .fontSize(Fs.CAPTION)
                  .fontColor($r('sys.color.brand'))
                  .onClick(() => {
                    this.onSelectVersion(row.version);
                  })
              }
            }
            .width('100%')
            .height(Sz.TOUCH_MIN)
            if (!row.selectable && row.reason.length > 0) {
              Text(row.reason)
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
            }
          }
          .width('100%')
        }, (row: CoreVersionRow) => row.version)
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_primary'))
  }

  // ── 插件 ──────────────────────────────────────────────────────────────
  @Builder
  pluginsCard() {
    Column({ space: Sp.S }) {
      Text('插件')
        .fontSize(Fs.SECONDARY)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      Text('纯 JS 插件可以在运行时安装/停用；含原生模块（.node）的插件受鸿蒙签名策略约束，只能随应用发版提供。')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      if (this.view.plugins.length === 0) {
        Text('未读取到插件清单。核心就绪后这里会列出实际安装的插件。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      } else {
        ForEach(this.view.plugins, (p: PluginRow) => {
          Column({ space: 2 }) {
            Row({ space: Sp.S }) {
              Text(p.name)
                .fontSize(Fs.CAPTION)
                .layoutWeight(1)
              Text(p.version)
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
              Text(p.installable ? '可安装' : '需发版')
                .fontSize(Fs.CAPTION)
                .fontColor(p.installable ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
            }
            .width('100%')
            if (!p.installable && p.reason.length > 0) {
              Text(p.reason)
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
            }
          }
          .width('100%')
        }, (p: PluginRow) => p.name)
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_primary'))
  }

  // ── 颜色 ──────────────────────────────────────────────────────────────
  private phaseColor(): ResourceColor {
    if (this.view.phase === CorePhase.READY) {
      return $r('sys.color.brand');
    }
    if (this.view.phase === CorePhase.FAILED) {
      return $r('sys.color.warning');
    }
    return $r('sys.color.font_secondary');
  }

  private factColor(verdict: string): ResourceColor {
    if (verdict === 'ok') {
      return $r('sys.color.brand');
    }
    if (verdict === 'warn') {
      return $r('sys.color.warning');
    }
    return $r('sys.color.font_tertiary');
  }
}
