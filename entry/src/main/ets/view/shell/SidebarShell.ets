/**
 * 侧栏外壳（P0：AppFrame 的第一条轨道）。
 *
 * ## 为什么先抽它
 *
 * 三条轨道里侧栏**最小、最自足**：它需要的东西（当前页签、待决徽标、宽度、回调）
 * 用一个显式 props 面就能表达完，**不需要新机制**。所以它是"shell 模式"的第一个真实证明——
 * 在动 `AppShell`/`MainShell`（那三个要面对 `Index` 的约 100 个 `@State`）之前，
 * 先用它把 shell 的边界立起来。
 *
 * ## 它拥有什么（官方 Sidebar 的语义）
 *
 * | 官方职责 | 这里如何表达 |
 * |---|---|
 * | Brand | 顶部品牌行（文案由宿主给：`brand`） |
 * | 主入口列表 | 面板清单（当前来自 `navTabs()`，P1 会改为**面板注册表**驱动） |
 * | 待决徽标 | 只挂在工作区那一项上（`pendingBadge` 非空才显示） |
 * | 二级入口 | 本地调试（原「连接诊断 + POC」合并，E96） |
 * | Settings **固定在底部** | 由面板顺序保证（`PanelRegistry` 里 Settings 的 `order` 最大） |
 *
 * ## 三种呈现（信息架构不变，只变几何）
 *
 * `TrackPresentation.PANEL` = 三栏左侧完整面板；`RAIL` = 双栏收窄图标条；
 * `OVERLAY` = 单栏（当前是**底部标签栏**，P1 会改成抽屉——这一步只搬代码不改观感）。
 *
 * 【为什么把"呈现"与"栏目"分开】四形态共享同一套信息架构，变的只有几何与呈现；
 * 若按设备写三套栏目，就回到"四套 UI"了。
 */

import {
  Fs,
  HarmonyColor,
  HarmonyIconSize,
  NavTab,
  navTabLabel,
  navTabLabelRes,
  navTabs,
  navTabSymbol,
  Radius,
  Sp,
  Sz,
  TrackPresentation,
} from 'appstate';

/** 侧栏里一个主入口的徽标（当前只有"待决"用它） */
interface SidebarBadge {
  tab: NavTab;
  text: string;
}

@Component
export struct SidebarShell {
  /** 品牌文案（宿主给；侧栏不该自己知道应用叫什么） */
  @Prop brand: string = '';
  /** 当前选中的页签 */
  @Prop tab: NavTab = NavTab.WORKSPACES;
  /** 待决徽标文案（空串 = 不显示） */
  @Prop pendingBadge: string = '';
  /** 侧栏占位宽度（rail 与 panel 两种呈现都用它） */
  @Prop navWidthVp: number = 0;
  /** 呈现方式（由 `ui/ShellTracks` 按形态算出；这里只映射几何） */
  @Prop presentation: TrackPresentation = TrackPresentation.PANEL;

  onSelectTab: (tab: NavTab) => void = () => {
  };
  onOpenDiagnostics: () => void = () => {
  };

  /** 待决徽标挂在哪个页签上（官方把"待决"归到当前会话/工作区这一侧，不单列页签） */
  private badgeFor(tab: NavTab): string {
    return tab === NavTab.WORKSPACES ? this.pendingBadge : '';
  }

  /** 收窄图标条上的角标 */
  @Builder
  cornerBadge(text: string) {
    Text(text)
      .fontSize(Fs.CAPTION_XS)
      .fontColor(HarmonyColor.ON_BRAND_TEXT)
      .backgroundColor($r('sys.color.alert'))
      .borderRadius(Radius.S)
      .padding({ left: 5, right: 5 })
      .margin({ top: -Sp.XS, right: -Sp.S })   // 角标压在图标右上角：负偏移是几何微调，不是间距节奏
  }

  /** 二级入口（本地调试）：面板呈现下是一行文字，其它呈现下不显示（空间不够） */
  @Builder
  secondaryEntry() {
    Text($r('app.string.settings_local_debug'))
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .height(Sz.TOUCH_MIN - 8)
      .padding({ left: Sp.M })
      .textAlign(TextAlign.Start)
      .onClick(() => {
        this.onOpenDiagnostics();
      })
  }

  /** 三栏：完整面板 */
  @Builder
  panelBody() {
    Column({ space: Sp.XS }) {
      Text(this.brand)
        .fontSize(Fs.TITLE_S)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: Sp.M, top: Sp.M, bottom: Sp.S })

      ForEach(navTabs(), (tab: NavTab) => {
        Row({ space: Sp.M }) {
          SymbolGlyph(navTabSymbol(tab))
            .fontSize(HarmonyIconSize.NAV)
            .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
          Text(navTabLabel(tab))
            .fontSize(Fs.SECONDARY)
            .fontColor(this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_primary'))
            .layoutWeight(1)
          if (this.badgeFor(tab).length > 0) {
            Text(this.badgeFor(tab))
              .fontSize(Fs.CAPTION)
              .fontColor(HarmonyColor.ON_BRAND_TEXT)
              .backgroundColor($r('sys.color.alert'))
              .borderRadius(Radius.S)
              .padding({ left: Sp.S, right: Sp.S })
          }
        }
        .width('100%')
        .height(Sz.TOUCH_MIN)
        .padding({ left: Sp.M, right: Sp.M })
        .borderRadius(Radius.S)
        .backgroundColor(this.tab === tab ? $r('sys.color.background_secondary') : Color.Transparent)
        .onClick(() => {
          this.onSelectTab(tab);
        })
      }, (tab: NavTab) => tab)

      Blank()

      // 二级入口放在最底部：它是排障用的，不该和产品入口抢位置
      this.secondaryEntry()
    }
    .width('100%')
    .height('100%')
    .padding({ left: Sp.S, right: Sp.S, bottom: Sp.S })
  }

  /** 双栏：收窄图标条 */
  @Builder
  railBody() {
    Column({ space: Sp.S }) {
      ForEach(navTabs(), (tab: NavTab) => {
        Column() {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(navTabSymbol(tab))
              .fontSize(HarmonyIconSize.NAV_RAIL)
              .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (this.badgeFor(tab).length > 0) {
              this.cornerBadge(this.badgeFor(tab))
            }
          }
        }
        .width(this.navWidthVp)
        .height(Sz.TOUCH_MIN)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Radius.S)
        .accessibilityText(`${navTabLabel(tab)}标签`)
        .onClick(() => {
          this.onSelectTab(tab);
        })
      }, (tab: NavTab) => tab)
    }
    .width(this.navWidthVp)
    .height('100%')
    .padding({ top: Sp.M })
  }

  /**
   * 单栏：底部标签栏。
   *
   * 【这是过渡呈现，不是终点】官方在手机上把 Sidebar 收成**抽屉**。当前仍用底部标签栏是为了
   * "只搬代码不改观感"；改成抽屉属 P1（届时这里换成抽屉内容，主区不变）。
   */
  @Builder
  tabsBody() {
    Row() {
      ForEach(navTabs(), (tab: NavTab) => {
        Column({ space: 2 }) {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(navTabSymbol(tab))
              .fontSize(HarmonyIconSize.NAV_RAIL)
              .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (this.badgeFor(tab).length > 0) {
              this.cornerBadge(this.badgeFor(tab))
            }
          }
          Text(navTabLabelRes(tab))
            .fontSize(Fs.CAPTION)
            .fontColor(this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityText(`${navTabLabel(tab)}标签`)
        .onClick(() => {
          this.onSelectTab(tab);
        })
      }, (tab: NavTab) => tab)
    }
    .width('100%')
    .height(Sz.NAV_RAIL)
  }

  build() {
    if (this.presentation === TrackPresentation.RAIL) {
      this.railBody()
    } else if (this.presentation === TrackPresentation.OVERLAY) {
      this.tabsBody()
    } else {
      this.panelBody()
    }
  }
}
