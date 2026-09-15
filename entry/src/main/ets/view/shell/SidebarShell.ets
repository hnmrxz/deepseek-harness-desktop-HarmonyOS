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
 * 顺序即官方顺序：**Brand → New Session → 工作区树 → Panel 清单 → Settings（沉底）**。
 *
 * | 官方职责 | 这里如何表达 |
 * |---|---|
 * | Brand | 顶部品牌行（文案由宿主给：`brand`） |
 * | New Session | 品牌行下方的 `＋ 新建会话`（回调 `onNewSession`；与 Ctrl+N 走同一条路） |
 * | Workspace 浏览器 | `WorkspaceBrowser`（**P1-3**：树挂进侧栏；此前长在主区的「工作区」页签里） |
 * | Panel 清单 | **面板注册表驱动**（P1-4：`sidebarEntries(registry)`，视图不再遍历 `navTabs()`） |
 * | 待决徽标 | 只挂在工作区那一项上（`pendingBadge` 非空才显示） |
 * | 二级入口 | 本地调试（原「连接诊断 + POC」合并，E96） |
 * | Settings **固定在底部** | `sidebarPinnedEntries(registry)`（`order ≥ SIDEBAR_PINNED_ORDER`）——**规则在模型里**，视图不写"settings 要沉底"这种特例 |
 *
 * 【P1-4 的实质】入口的**存在与顺序**归注册表，**长什么样**（图标/文案）归
 * `sidebarPanelSymbol` / `sidebarPanelLabelRes`（按面板 id 取的编译期映射），
 * **哪一项高亮**归宿主（`selectedPanelId`，由"选中的主区面板"经桥反查）。
 * 视图因此不再依赖 `NavTab`——一级导航不再是"三个页签"。
 *
 * ## 三种呈现（信息架构不变，只变几何）
 *
 * `TrackPresentation.PANEL` = 三栏左侧完整面板；`RAIL` = 双栏收窄图标条；
 * `OVERLAY` = 单栏（**当前仍是底部标签栏**，手机抽屉待做——它出现时内容就是同一份入口清单）。
 *
 * 【为什么把"呈现"与"栏目"分开】四形态共享同一套信息架构，变的只有几何与呈现；
 * 若按设备写三套栏目，就回到"四套 UI"了。
 */

import {
  Fs,
  HarmonyColor,
  HarmonyIconSize,
  PanelDescriptor,
  PanelLocation,
  PanelRegistry,
  Radius,
  sidebarEntries,
  sidebarPanelLabelRes,
  sidebarPanelSymbol,
  sidebarPinnedEntries,
  Sp,
  Sz,
  TrackPresentation,
} from 'appstate';
import { WorkspaceBrowser } from '../WorkspaceBrowser';
import type { WorkspaceBrowserFacade } from '../WorkspaceBrowser';

@Component
export struct SidebarShell {
  /** 品牌文案（宿主给；侧栏不该自己知道应用叫什么） */
  @Prop brand: string = '';
  /**
   * 当前高亮的**侧栏席位 id**（空串 = 什么都不高亮）。
   *
   * 【为什么是 id 而不是页签】P1-4：入口清单由 `PanelRegistry` 决定，视图只按 id 比高亮。
   * 判据由宿主给（`sidebarPanelOfMainPanel(选中的主区面板)`）——会话/诊断/连接没有侧栏席位，
   * 那时应当**没有**哪一项高亮，而不是随便高亮一项。
   */
  @Prop selectedPanelId: string = '';
  /** 待决徽标文案（空串 = 不显示） */
  @Prop pendingBadge: string = '';
  /** 侧栏占位宽度（rail 与 panel 两种呈现都用它） */
  @Prop navWidthVp: number = 0;
  /** 呈现方式（由 `ui/ShellTracks` 按形态算出；这里只映射几何） */
  @Prop presentation: TrackPresentation = TrackPresentation.PANEL;
  /**
   * 工作区→会话浏览器（P1：官方 `ui-workspace` 的座位就在 Sidebar 里）。
   *
   * 【为什么侧栏拿它而不是自己造】树本身（工作区分组、会话归属、待决、归档）归 `WorkspaceBrowser`；
   * 侧栏只决定"这条轨道里放不放它、放多宽"——窄版行由 `compact: true` 触发。
   */
  @Prop browser: WorkspaceBrowserFacade;

  /**
   * 面板注册表（由 `Index` `@Provide`）。
   *
   * 【为什么侧栏需要它】"哪些入口可用"是**面板的属性**，不是页面的 if 分支
   * （见 `model/PanelRegistry` 的说明）。侧栏据此过滤：不可用的面板不该占位置。
   */
  @Consume('panelRegistry') panelRegistry: PanelRegistry;

  /** 选中某个侧栏席位（宿主把它翻译成"切到哪个主区面板"，并做注册表校验） */
  onSelectPanel: (panelId: string) => void = () => {
  };
  /** 新建会话（官方侧栏在品牌行下方就有这个一级入口） */
  onNewSession: () => void = () => {
  };
  onOpenDiagnostics: () => void = () => {
  };

  /**
   * 待决徽标挂在哪个席位上。
   *
   * 官方把"待决"归到当前会话/工作区这一侧，不单列入口 ⇒ 只有工作区席位带徽标。
   */
  private badgeFor(panelId: string): string {
    return panelId === 'sidebar.workspaces' ? this.pendingBadge : '';
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

  /**
   * 三栏：完整面板。
   *
   * 顺序即官方 Sidebar 的顺序：**Brand → New Session → 工作区树 → Panel 清单 → Settings（沉底）**。
   * 入口清单与沉底规则都来自 `PanelRegistry`（`sidebarEntries` / `sidebarPinnedEntries`），
   * 视图不再自己判断"哪些入口该出现、谁该在底部"。
   */
  @Builder
  panelBody() {
    Column({ space: Sp.XS }) {
      Text(this.brand)
        .fontSize(Fs.TITLE_S)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: Sp.M, top: Sp.M, bottom: Sp.S })

      // New Session：官方侧栏的一级入口（放在品牌行下面，不藏在某个工作区里）
      Row({ space: Sp.S }) {
        SymbolGlyph($r('sys.symbol.plus_circle'))
          .fontSize(HarmonyIconSize.NAV)
          .fontColor([$r('sys.color.brand')])
        Text($r('app.string.action_new_session'))
          .fontSize(Fs.SECONDARY)
          .fontColor($r('sys.color.brand'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(Sz.TOUCH_MIN)
      .padding({ left: Sp.M, right: Sp.M })
      .borderRadius(Radius.S)
      .onClick(() => {
        this.onNewSession();
      })

      /*
       * P1：工作区→会话树摆在**品牌行下面、面板入口上面**（官方 Sidebar 的顺序）。
       * P0 时它长在主区的「工作区」页签里，现由侧栏承载（三栏档位），
       * 主区那份改成一句说明（见 `TabContentView`）。
       */
      Column() {
        WorkspaceBrowser({ f: this.browser, compact: true })
      }
      .width('100%')
      .layoutWeight(1)

      ForEach(sidebarEntries(this.panelRegistry), (d: PanelDescriptor) => {
        this.panelEntry(d)
      }, (d: PanelDescriptor) => d.id)

      Blank()

      // 沉底项（设置）：官方固定在底部，不随面板清单浮动
      ForEach(sidebarPinnedEntries(this.panelRegistry), (d: PanelDescriptor) => {
        this.panelEntry(d)
      }, (d: PanelDescriptor) => d.id)

      // 二级入口放在最底部：它是排障用的，不该和产品入口抢位置
      this.secondaryEntry()
    }
    .width('100%')
    .height('100%')
    .padding({ left: Sp.S, right: Sp.S, bottom: Sp.S })
  }

  /** 面板呈现里的一行入口（图标 + 文案 + 可选徽标 + 选中态） */
  @Builder
  panelEntry(d: PanelDescriptor) {
    Row({ space: Sp.M }) {
      SymbolGlyph(sidebarPanelSymbol(d.id))
        .fontSize(HarmonyIconSize.NAV)
        .fontColor([this.selectedPanelId === d.id ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
      Text(sidebarPanelLabelRes(d.id))
        .fontSize(Fs.SECONDARY)
        .fontColor(this.selectedPanelId === d.id ? $r('sys.color.brand') : $r('sys.color.font_primary'))
        .layoutWeight(1)
      if (this.badgeFor(d.id).length > 0) {
        Text(this.badgeFor(d.id))
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
    .backgroundColor(this.selectedPanelId === d.id
      ? $r('sys.color.background_secondary')
      : Color.Transparent)
    .onClick(() => {
      this.onSelectPanel(d.id);
    })
  }

  /** 双栏：收窄图标条 */
  @Builder
  railBody() {
    Column({ space: Sp.S }) {
      ForEach(this.panelRegistry.descriptors(PanelLocation.SIDEBAR), (d: PanelDescriptor) => {
        Column() {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(sidebarPanelSymbol(d.id))
              .fontSize(HarmonyIconSize.NAV_RAIL)
              .fontColor([this.selectedPanelId === d.id ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (this.badgeFor(d.id).length > 0) {
              this.cornerBadge(this.badgeFor(d.id))
            }
          }
        }
        .width(this.navWidthVp)
        .height(Sz.TOUCH_MIN)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Radius.S)
        .accessibilityText(`${d.label}标签`)
        .onClick(() => {
          this.onSelectPanel(d.id);
        })
      }, (d: PanelDescriptor) => d.id)
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
      ForEach(this.panelRegistry.descriptors(PanelLocation.SIDEBAR), (d: PanelDescriptor) => {
        Column({ space: 2 }) {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(sidebarPanelSymbol(d.id))
              .fontSize(HarmonyIconSize.NAV_RAIL)
              .fontColor([this.selectedPanelId === d.id ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (this.badgeFor(d.id).length > 0) {
              this.cornerBadge(this.badgeFor(d.id))
            }
          }
          Text(sidebarPanelLabelRes(d.id))
            .fontSize(Fs.CAPTION)
            .fontColor(this.selectedPanelId === d.id ? $r('sys.color.brand') : $r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityText(`${d.label}标签`)
        .onClick(() => {
          this.onSelectPanel(d.id);
        })
      }, (d: PanelDescriptor) => d.id)
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
