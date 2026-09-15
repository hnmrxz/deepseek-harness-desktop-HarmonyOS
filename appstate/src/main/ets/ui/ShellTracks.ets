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

/**
 * 侧栏**实际**用哪种呈现：形态给默认，用户的"展开 / 收起"给偏好。
 *
 * ## 为什么需要它（`sidebarExpanded` 此前是一个没有控制点的字段）
 *
 * `NavigationState.sidebarExpanded` 早就存在（初始 `true`、`copyOf` 会拷、还有
 * `setSidebarExpand`），但**没有任何消费者**：侧栏呈现完全由形态决定
 * （`shellTracksOf(mode)`）。于是官方 AppFrame 那个"收起侧栏腾出宽度"的动作在本仓**做不到** ——
 * 三栏窄窗口下想多看主区一点，没有任何办法（这是一个功能缺口，不是一个状态字段的冗余）。
 *
 * ## 规则（两条，都很保守）
 *
 * 1. **单栏一律浮层**：手机竖屏下"展开的侧栏"会盖住主区，用户要的是抽屉 ⇒
 *    `expanded` 在单栏下**不生效**（不是忽略用户，而是那个档位本来就没有第二个选项）。
 * 2. **其余形态跟随偏好**：双栏默认 rail（600–839vp 放不下两条展开轨道），
 *    用户展开就是 PANEL；三栏默认 PANEL，收起就是 rail（腾出 ⌈200vp⌉ 给主区）。
 *    宽度不够时**不阻止**用户——`LayoutController` 的档位判定已经保证了"能到这个形态
 *    就有基本空间"，而"我要不要这 200vp"是用户的判断。
 */
export function sidebarPresentationOf(mode: LayoutMode, expanded: boolean): TrackPresentation {
  if (mode === LayoutMode.SINGLE) {
    return TrackPresentation.OVERLAY;
  }
  if (expanded) {
    return TrackPresentation.PANEL;
  }
  return TrackPresentation.RAIL;
}

/** 侧栏在该形态（与该展开状态）下是否占布局宽度（浮层形态不占） */
export function sidebarOccupiesLayout(mode: LayoutMode, expanded: boolean): boolean {
  const presentation: TrackPresentation = sidebarPresentationOf(mode, expanded);
  return presentation === TrackPresentation.PANEL || presentation === TrackPresentation.RAIL;
}
