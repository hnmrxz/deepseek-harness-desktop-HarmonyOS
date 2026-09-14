/**
 * 三条轨道在四形态下**怎么呈现**（P0：AppFrame 的几何层）。
 *
 * 【为什么单独一个文件、放在 ui 层】它回答的是几何/呈现问题（与 `LayoutController` 的
 * `detailPresentation` 同族），**不是**导航问题：导航状态关心"选中了哪个面板"，
 * 这里关心"这条轨道摆在哪"。分开之后，`NavigationState` 不必依赖 `LayoutMode`——
 * 这也让两个模型各自都能在最扁平的编译环境里被测（门禁会把纯逻辑文件摊平到一个目录，
 * 跨目录相对路径会解析不了；这条约束反过来帮我们把分层的边界划清了）。
 *
 * 【最要紧的一条语义】这里**只**回答"轨道怎么摆"，**绝不**回答"这个形态要显示哪些栏目"。
 * 后者若随设备变，四形态就成了四套 UI——而官方 `ui-layout` 是同一套 AppFrame +
 * 面板选择跨设备，变的只有几何与呈现。
 */

import { LayoutMode } from './Breakpoints';

/** 某形态下各条轨道如何呈现 */
export enum TrackPresentation {
  /** 不占位（收进抽屉或浮层） */
  HIDDEN = 'hidden',
  /** 收窄的图标条 */
  RAIL = 'rail',
  /** 完整面板 */
  PANEL = 'panel',
  /** 并排的栏 */
  COLUMN = 'column',
  /** 浮层（Sheet / 侧边浅层面板） */
  OVERLAY = 'overlay',
}

export interface ShellTracks {
  sidebar: TrackPresentation;
  main: TrackPresentation;
  rightbar: TrackPresentation;
}

/**
 * 形态 → 三条轨道的呈现。
 *
 * - 单栏（手机）：侧栏与右栏都是浮层，主区全屏
 * - 双栏（平板竖屏 / 手机横屏 / 2in1 拖窄）：侧栏收成 rail；右栏是**侧边浅层面板**
 *   （与 `LayoutController` 的 `detailPresentation` 语义一致：不并排但可以看到）
 * - 三栏：三条轨道都在
 */
export function shellTracksOf(mode: LayoutMode): ShellTracks {
  if (mode === LayoutMode.SINGLE) {
    return { sidebar: TrackPresentation.OVERLAY, main: TrackPresentation.COLUMN,
      rightbar: TrackPresentation.OVERLAY };
  }
  if (mode === LayoutMode.DOUBLE) {
    return { sidebar: TrackPresentation.RAIL, main: TrackPresentation.COLUMN,
      rightbar: TrackPresentation.OVERLAY };
  }
  return { sidebar: TrackPresentation.PANEL, main: TrackPresentation.COLUMN,
    rightbar: TrackPresentation.COLUMN };
}

/** 侧栏在该形态下是否占布局宽度（浮层形态不占） */
export function sidebarOccupiesLayout(mode: LayoutMode): boolean {
  const tracks: ShellTracks = shellTracksOf(mode);
  return tracks.sidebar === TrackPresentation.PANEL || tracks.sidebar === TrackPresentation.RAIL;
}
