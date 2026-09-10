/**
 * 应用首屏：三形态导航 + 让步链（D3 §2）。
 *
 * 结构（按窗口宽度档位）：
 *   单栏 SINGLE（< 600vp，手机 / 折叠态）  ：内容区 + 底部标签栏；会话以「列表 → 详情」栈式下钻
 *   双栏 DOUBLE（600–839vp，折叠展开 / 平板竖屏）：左侧图标条（56vp）+ 内容区
 *   三栏 TRIPLE（>= 840vp，平板横屏 / 2in1）    ：左导航面板 + 主区 + 右详情栏（可收）
 *
 * 让步链（空间不足时的收缩顺序，D3 §2.1）：
 *   详情栏收窄 → 详情栏关闭 → 导航收为图标条 → 导航抽屉化
 * 让步只改几何、不改数据；变宽时自行恢复。
 *
 * 形态只由**窗口宽度**判定（D3 §2.2 硬规则）。
 * 数据当前来自桩数据源（方案 2），接入真实连接后仅替换数据来源。
 *
 * 验收工具入口：右上角的「POC」按钮进入 `pages/Poc1`（协议往返验证页）。
 */

import { display, window } from '@kit.ArkUI';
import { router } from '@kit.ArkUI';
import {
  detailPanelAvailable,
  Fs,
  LayoutMode,
  layoutModeOf,
  navTabLabel,
  navTabSymbol,
  NavTab,
  PendingItem,
  Radius,
  SessionListItem,
  Sp,
  stubPending,
  stubSessions,
  Sz
} from 'appstate';
import { ConversationPane } from '../view/ConversationPane';
import { PendingPane } from '../view/PendingPane';
import { PlaceholderPane } from '../view/PlaceholderPane';
import { SessionListPane } from '../view/SessionListPane';

/** 单栏下的页面栈（D3 §2 手机：列表 → 会话） */
enum StackPage {
  MAIN = 'main',
  CONVERSATION = 'conversation'
}

/** 一级导航顺序（三形态共用） */
const TABS: NavTab[] = [NavTab.PENDING, NavTab.SESSIONS, NavTab.WORKSPACES, NavTab.SETTINGS];

@Entry
@Component
struct Index {
  @State mode: LayoutMode = LayoutMode.SINGLE;
  @State tab: NavTab = NavTab.SESSIONS;
  @State selectedSessionId: string = '';
  @State detailOpen: boolean = false;
  @State stackPage: StackPage = StackPage.MAIN;
  @State sessions: SessionListItem[] = [];
  @State pending: PendingItem[] = [];
  /**
   * 待决徽标文本（缓存的派生值）。
   *
   * 存在理由：ArkTS 性能规则禁止在循环体内频繁读取 @State，
   * 而徽标出现在多个 ForEach 中；因此把派生值缓存在一个字段里，
   * 由 recomputeDerived() 在 pending 变化后刷新一次。
   */
  @State pendingBadge: string = '';

  private widthListener?: (size: window.Size) => void;

  aboutToAppear(): void {
    this.sessions = stubSessions();
    this.pending = stubPending();
    this.recomputeDerived();
    this.applyWidth(initialWidthVp());
    this.watchWindowSize();
  }

  /** 刷新派生值（pending 变化后调用一次，避免在循环体内读 @State） */
  private recomputeDerived(): void {
    const n: number = this.pending.length;
    this.pendingBadge = n <= 0 ? '' : (n > 99 ? '99+' : `${n}`);
  }

  aboutToDisappear(): void {
    this.unwatchWindowSize();
  }

  // ───────────────────── 形态判定 ─────────────────────

  private watchWindowSize(): void {
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        this.applyWidth(px2vp(win.getWindowProperties().windowRect.width));
        const listener = (size: window.Size) => {
          this.applyWidth(px2vp(size.width));
        };
        this.widthListener = listener;
        win.on('windowSizeChange', listener);
      }).catch(() => {
        // 拿不到窗口时保留初始档位，不阻断渲染
      });
    } catch (error) {
      // 同上
    }
  }

  private unwatchWindowSize(): void {
    const listener = this.widthListener;
    if (listener === undefined) {
      return;
    }
    this.widthListener = undefined;
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        win.off('windowSizeChange', listener);
      }).catch(() => {
      });
    } catch (error) {
    }
  }

  /** 应用新宽度：切档位 + 修正派生状态（不重载数据，D3 §2） */
  private applyWidth(widthVp: number): void {
    const next: LayoutMode = layoutModeOf(widthVp);
    if (next === this.mode) {
      return;
    }
    this.mode = next;
    if (next !== LayoutMode.SINGLE && this.stackPage === StackPage.CONVERSATION) {
      // 变宽：退出栈式下钻，回到主区，保持已选会话
      this.stackPage = StackPage.MAIN;
    }
    // 只有三栏才展示详情栏（D3 §2.1：空间不足先收详情栏）
    if (!detailPanelAvailable(next)) {
      this.detailOpen = false;
    } else if (this.selectedSessionId.length > 0) {
      this.detailOpen = true;
    }
  }

  // ───────────────────── 交互 ─────────────────────

  private openSession(id: string): void {
    this.selectedSessionId = id;
    this.selectedSessionTitle = this.titleOf(id);
    if (this.mode === LayoutMode.SINGLE) {
      this.stackPage = StackPage.CONVERSATION;
    } else if (this.mode === LayoutMode.TRIPLE) {
      this.detailOpen = true;
    }
  }

  /** 从会话列表取标题（仅在选择时调用一次，不参与渲染循环） */
  private titleOf(id: string): string {
    const list: SessionListItem[] = this.sessions;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return list[i].title;
      }
    }
    return '';
  }

  private selectTab(tab: NavTab): void {
    this.tab = tab;
    this.stackPage = StackPage.MAIN;
    if (tab !== NavTab.SESSIONS) {
      this.selectedSessionId = '';
    }
  }

  private openPoc(): void {
    router.pushUrl({ url: 'pages/Poc1' }).catch(() => {
    });
  }

  private currentSessionTitle(): string {
    // 使用缓存的派生值，避免在遍历 @State 数组时反复读取状态
    // （ArkTS 性能规则 @performance/hp-arkui-no-state-var-access-in-loop）
    return this.selectedSessionTitle.length > 0 ? this.selectedSessionTitle : '会话';
  }

  /** 选中会话的标题缓存（选择会话时刷新一次） */
  @State selectedSessionTitle: string = '';

  private showsConversation(): boolean {
    return this.selectedSessionId.length > 0 && this.tab === NavTab.SESSIONS;
  }

  build() {
    if (this.mode === LayoutMode.SINGLE) {
      this.buildSingle()
    } else if (this.mode === LayoutMode.DOUBLE) {
      this.buildDouble()
    } else {
      this.buildTriple()
    }
  }

  // ───────────────────── 单栏（手机） ─────────────────────

  @Builder
  buildSingle() {
    Column() {
      this.header(this.stackPage === StackPage.CONVERSATION)

      Divider().color($r('sys.color.comp_divider'))

      Column() {
        if (this.stackPage === StackPage.CONVERSATION) {
          ConversationPane({ sessionId: this.selectedSessionId })
        } else {
          this.tabContent()
        }
      }
      .layoutWeight(1)
      .width('100%')

      if (this.stackPage === StackPage.MAIN) {
        this.bottomTabs()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  header(showBack: boolean) {
    Row({ space: Sp.S }) {
      if (showBack) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick(() => {
          this.stackPage = StackPage.MAIN;
        })
      }
      Text(showBack ? this.currentSessionTitle() : navTabLabel(this.tab))
        .fontSize(Fs.TITLE_L)
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Button('POC')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontSize(Fs.CAPTION)
        .onClick(() => {
          this.openPoc();
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: Sp.M, right: Sp.S })
  }

  @Builder
  bottomTabs() {
    Row() {
      ForEach(TABS, (tab: NavTab) => {
        Column({ space: 2 }) {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(navTabSymbol(tab))
              .fontSize(22)
              .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (tab === NavTab.PENDING && this.pendingBadge.length > 0) {
              this.badge(this.pendingBadge)
            }
          }
          Text(navTabLabel(tab))
            .fontSize(Fs.CAPTION)
            .fontColor(this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.selectTab(tab);
        })
      }, (tab: NavTab) => tab)
    }
    .width('100%')
    .height(56)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  // ───────────────────── 双栏（折叠展开 / 平板竖屏） ─────────────────────

  @Builder
  buildDouble() {
    Row() {
      this.navRail()
      Divider().vertical(true).color($r('sys.color.comp_divider'))
      Column() {
        this.header(false)
        Divider().color($r('sys.color.comp_divider'))
        Column() {
          if (this.showsConversation()) {
            ConversationPane({ sessionId: this.selectedSessionId })
          } else {
            this.tabContent()
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  navRail() {
    Column({ space: Sp.S }) {
      ForEach(TABS, (tab: NavTab) => {
        Column() {
          Stack({ alignContent: Alignment.TopEnd }) {
            SymbolGlyph(navTabSymbol(tab))
              .fontSize(22)
              .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
            if (tab === NavTab.PENDING && this.pendingBadge.length > 0) {
              this.badge(this.pendingBadge)
            }
          }
        }
        .width(Sz.NAV_RAIL)
        .height(Sz.TOUCH_MIN)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Radius.S)
        .onClick(() => {
          this.selectTab(tab);
        })
      }, (tab: NavTab) => tab)
    }
    .width(Sz.NAV_RAIL)
    .height('100%')
    .padding({ top: Sp.M })
    .backgroundColor($r('sys.color.background_secondary'))
  }

  // ───────────────────── 三栏（平板横屏 / 2in1） ─────────────────────

  @Builder
  buildTriple() {
    Row() {
      this.navPanel()
      Divider().vertical(true).color($r('sys.color.comp_divider'))
      Column() {
        this.header(false)
        Divider().color($r('sys.color.comp_divider'))
        Column() {
          this.tabContent()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
      if (this.detailOpen && this.showsConversation()) {
        Divider().vertical(true).color($r('sys.color.comp_divider'))
        this.detailPanel()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  navPanel() {
    Column({ space: Sp.XS }) {
      Text('DSH 鸿蒙端')
        .fontSize(Fs.TITLE_S)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: Sp.M, top: Sp.M, bottom: Sp.S })

      ForEach(TABS, (tab: NavTab) => {
        Row({ space: Sp.M }) {
          SymbolGlyph(navTabSymbol(tab))
            .fontSize(20)
            .fontColor([this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
          Text(navTabLabel(tab))
            .fontSize(Fs.SECONDARY)
            .fontColor(this.tab === tab ? $r('sys.color.brand') : $r('sys.color.font_primary'))
            .layoutWeight(1)
          if (tab === NavTab.PENDING && this.pendingBadge.length > 0) {
            Text(this.pendingBadge)
              .fontSize(Fs.CAPTION)
              .fontColor(Color.White)
              .backgroundColor($r('sys.color.alert'))
              .borderRadius(9)
              .padding({ left: 6, right: 6 })
          }
        }
        .width('100%')
        .height(Sz.TOUCH_MIN)
        .padding({ left: Sp.M, right: Sp.M })
        .borderRadius(Radius.S)
        .backgroundColor(this.tab === tab ? $r('sys.color.background_secondary') : Color.Transparent)
        .onClick(() => {
          this.selectTab(tab);
        })
      }, (tab: NavTab) => tab)

      Blank()

      Button('POC 协议验证')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontSize(Fs.CAPTION)
        .width('100%')
        .onClick(() => {
          this.openPoc();
        })
    }
    .width(Sz.NAV_PANEL)
    .height('100%')
    .padding({ left: Sp.S, right: Sp.S, bottom: Sp.S })
    .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  detailPanel() {
    Column() {
      Row({ space: Sp.S }) {
        Text('详情')
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Button() {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(16)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick(() => {
          this.detailOpen = false;
        })
      }
      .width('100%')
      .height(Sz.TOUCH_MIN)
      .padding({ left: Sp.M, right: Sp.S })

      Divider().color($r('sys.color.comp_divider'))

      PlaceholderPane({
        title: '详情栏',
        hint: '工具 / 子代理 / 交付物 / 目标 / 任务在此展示（M2 实现）'
      })
    }
    .width(Sz.DETAIL_PANEL)
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
  }

  // ───────────────────── 共用 ─────────────────────

  @Builder
  tabContent() {
    if (this.tab === NavTab.PENDING) {
      PendingPane({ items: this.pending })
    } else if (this.tab === NavTab.SESSIONS) {
      SessionListPane({
        sessions: this.sessions,
        selectedId: this.selectedSessionId,
        onSelect: (id: string) => {
          this.openSession(id);
        }
      })
    } else if (this.tab === NavTab.WORKSPACES) {
      PlaceholderPane({ title: '工作区', hint: '工作区列表、文件树与文件投喂（M5 实现）' })
    } else {
      PlaceholderPane({ title: '设置', hint: '通用 / 模型 / 凭据 / 设备 / 连接诊断（M6 实现）' })
    }
  }

  @Builder
  badge(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(Color.White)
      .backgroundColor($r('sys.color.alert'))
      .borderRadius(8)
      .padding({ left: 5, right: 5 })
      .margin({ top: -4, right: -10 })
  }

  /**
   * 待决徽标文本。
   *
   * 单独取值再传入 ForEach 的 item builder，避免在循环体内频繁读取 @State
   * （ArkTS 性能规则 @performance/hp-arkui-no-state-var-access-in-loop）。
   * 状态变化时 build 重跑，因此这里每次都是新鲜值。
   */
  private pendingBadgeText(): string {
    const n: number = this.pending.length;
    if (n <= 0) {
      return '';
    }
    return n > 99 ? '99+' : `${n}`;
  }
}

/** 用 display 推导初始窗口宽度（vp）；失败时给一个安全的手机宽度 */
function initialWidthVp(): number {
  try {
    const d: display.Display = display.getPrimaryDisplaySync();
    return px2vp(d.width);
  } catch (error) {
    return 400;
  }
}
