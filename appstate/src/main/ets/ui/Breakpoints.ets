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

/**
 * 一级导航项（E108：收敛为三项）。
 *
 * 【为什么删掉「待决」与「会话」两个页签】官方 web 的侧栏就是**工作区为组、会话挂在组下**：
 * 会话天然属于某个工作区，单独一个"会话"页签会让同一批数据出现两次、还要用户自己想
 * "这两个列表什么关系"。待决（审批/提问）更不该占一个页签——它属于**当前正在跑的那次对话**，
 * 官方把它显示在对话里。于是：
 *   - `SESSIONS` **别名**到 `'workspaces'`：`selectTab(NavTab.SESSIONS)` 这类既有调用
 *     （建完会话要跳过去）自动落到合并后的工作区视图，不必逐处改；
 *   - `PENDING` 只保留常量（历史调用点会归一化到 WORKSPACES），不再出现在页签栏。
 */
export enum NavTab {
  PENDING = 'pending',
  SESSIONS = 'workspaces',
  WORKSPACES = 'workspaces',
  /** 端侧 DSH 核心：运行状态、版本切换/回滚、插件、运行时诊断（D6 §2/§6） */
  CORE = 'core',
  SETTINGS = 'settings'
}

/*
 * 【本轮删除：`sidebarPanelSymbol` / `sidebarPanelLabelRes`】
 *
 * 两者是 **PC 侧栏席位**的图标/文案映射（v1 的 AppShell 侧栏轨道按面板 id 取 `$r`）。
 * T025 删除 AppShell/SidebarShell 后，侧栏这条呈现路径整体退役：
 *   · 手机链的会话列表是 `DrawerNav`（自己持有 `SessionSearch` 与本组件的行文案，不走侧栏席位）；
 *   · 设置分区的文案走**保留的** `settingsSectionLabelRes`（下面这个函数）。
 * 于是两者在整仓零消费点，随组件一起消亡——留着只会让人以为"侧栏还在"。
 */

/**
 * 设置分区 → 文案资源（按分区 id；P4-1）。
 *
 * 【为什么与侧栏同一套做法】分区名要跟随系统语言（E117），而 `$r` 只能字面量 ⇒
 * 资源映射只能放在编译期函数里。视图拿 descriptor 决定"有哪些分区、什么顺序"，
 * 拿这个函数决定"叫什么"（与侧栏的入口完全同构）。
 */
export function settingsSectionLabelRes(sectionId: string): Resource {
  if (sectionId === 'settings.general') {
    return $r('app.string.settings_general');
  }
  if (sectionId === 'settings.models') {
    return $r('app.string.settings_models');
  }
  if (sectionId === 'settings.plugins') {
    return $r('app.string.settings_plugins');
  }
  if (sectionId === 'settings.core') {
    return $r('app.string.settings_core');
  }
  if (sectionId === 'settings.presets') {
    return $r('app.string.settings_presets');
  }
  if (sectionId === 'settings.skills') {
    return $r('app.string.settings_skills');
  }
  return $r('app.string.settings_device');
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

// ───────────────────────── 运行模式 ─────────────────────────

/**
 * 运行模式：本机运行 vs 连接远程主机（DSH Full Parity §FR-032）。
 *
 * 【为什么合入 Breakpoints 而不是单列文件】
 *   RunMode 与 LayoutMode 同属「顶层形态决定因子」——
 *   Index.ets 根据两者共同决定渲染 AppShell 还是 RemoteShell，
 *   合在一处便于审查"形态判定全在一处"这条纪律。
 */
export enum RunMode {
  /** 本机运行（HDSH 端侧自足范式） */
  LOCAL = 'local',
  /** 连接远程主机（DSH Mobile 抽屉范式） */
  REMOTE = 'remote'
}
