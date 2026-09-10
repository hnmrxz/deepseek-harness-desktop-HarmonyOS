/**
 * 断点与布局档位（D3 §2）。
 *
 * 只用**窗口**宽度判定顶层形态（D3 §2.2 硬规则）；
 * 组件级自适应由组件自身按容器尺寸处理（如 onAreaChange），不读窗口宽度。
 */

import { Breakpoint } from './Tokens';

/** 形态档位 */
export enum LayoutMode {
  /** 单栏（手机 / 折叠屏折叠态）：< 600vp */
  SINGLE = 'single',
  /** 双栏（折叠屏展开态 / 平板竖屏）：600–839vp */
  DOUBLE = 'double',
  /** 三栏（折叠屏悬停 / 平板横屏 / 2in1）：>= 840vp */
  TRIPLE = 'triple'
}

/** 由窗口宽度推导档位 */
export function layoutModeOf(widthVp: number): LayoutMode {
  if (widthVp >= Breakpoint.LG) {
    return LayoutMode.TRIPLE;
  }
  if (widthVp >= Breakpoint.MD) {
    return LayoutMode.DOUBLE;
  }
  return LayoutMode.SINGLE;
}

/** 一级导航项 */
export enum NavTab {
  PENDING = 'pending',
  SESSIONS = 'sessions',
  WORKSPACES = 'workspaces',
  SETTINGS = 'settings'
}

/** 导航项文案 */
export function navTabLabel(tab: NavTab): string {
  if (tab === NavTab.PENDING) {
    return '待决';
  }
  if (tab === NavTab.SESSIONS) {
    return '会话';
  }
  if (tab === NavTab.WORKSPACES) {
    return '工作区';
  }
  return '设置';
}

/** 导航项图标（用系统符号，避免自造资源） */
export function navTabSymbol(tab: NavTab): Resource {
  if (tab === NavTab.PENDING) {
    return $r('sys.symbol.bell');
  }
  if (tab === NavTab.SESSIONS) {
    return $r('sys.symbol.message');
  }
  if (tab === NavTab.WORKSPACES) {
    return $r('sys.symbol.folder');
  }
  return $r('sys.symbol.gearshape');
}

/** 详情栏是否在该档位下可用（单栏时详情以全屏下钻呈现） */
export function detailPanelAvailable(mode: LayoutMode): boolean {
  return mode === LayoutMode.TRIPLE;
}

/** 导航栏在该档位下的呈现方式 */
export enum NavPresentation {
  /** 底部标签栏（单栏，手机） */
  BOTTOM_TABS = 'bottom',
  /** 左侧图标条 + 可展开面板（双栏） */
  RAIL = 'rail',
  /** 左侧完整面板（三栏） */
  PANEL = 'panel'
}

export function navPresentation(mode: LayoutMode): NavPresentation {
  if (mode === LayoutMode.SINGLE) {
    return NavPresentation.BOTTOM_TABS;
  }
  if (mode === LayoutMode.DOUBLE) {
    return NavPresentation.RAIL;
  }
  return NavPresentation.PANEL;
}
