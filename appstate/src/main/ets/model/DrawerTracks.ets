/**
 * 抽屉轨道几何模型（DSH Full Parity §FR-033）。
 *
 * ## 存在理由
 *
 * 手机端远程模式使用 DSH Mobile 的抽屉交互范式：
 *   - 左侧抽屉 = 会话列表（右滑打开）
 *   - 右侧抽屉 = 会话详情（左滑打开）
 *   - 主区域 = 当前对话
 *
 * 与三栏 `Row` 轨道布局（v1 的 AppShell，T025 已删）不同，抽屉需要 Stack + 手势驱动，
 * 因此几何状态（哪个抽屉开着、宽度、拖拽偏移）需要独立模型。当前消费者只有手机壳
 * `view/shell/RemoteShell.ets` 与宿主 `pages/Index.ets`。
 *
 * ## 设计决策（R&D-008）
 *
 * DrawerTracks 是纯函数几何——与 ShellTracks 并列的概念，
 * 但映射到 Stack + 手势而非 Row + 拖拽。所有计算是确定性的，
 * 可被 fixture 直接钉住。
 */

/** 抽屉轨道状态——值类型，不含行为 */
export interface DrawerTracksState {
  /** 左侧抽屉（会话列表）是否打开 */
  leftOpen: boolean;
  /** 右侧抽屉（会话详情）是否打开 */
  rightOpen: boolean;
  /** 左侧抽屉宽度（vp；默认 280） */
  leftWidth: number;
  /** 右侧抽屉宽度（vp；默认 320） */
  rightWidth: number;
  /** 当前拖拽偏移（vp；0 = 无拖拽） */
  dragOffset: number;
}

/** 左侧抽屉默认宽度（对齐 DSH Mobile 的会话列表宽度） */
export const DRAWER_LEFT_WIDTH: number = 280;

/** 右侧抽屉默认宽度（对齐 DSH Mobile 的详情面板宽度） */
export const DRAWER_RIGHT_WIDTH: number = 320;

/** 创建默认的抽屉状态（两个抽屉都关闭） */
export function createDrawerTracksState(): DrawerTracksState {
  return {
    leftOpen: false,
    rightOpen: false,
    leftWidth: DRAWER_LEFT_WIDTH,
    rightWidth: DRAWER_RIGHT_WIDTH,
    dragOffset: 0
  };
}

/** 打开左侧抽屉（同时关闭右侧——两个抽屉不应同时打开） */
export function openLeftDrawer(state: DrawerTracksState): DrawerTracksState {
  return {
    leftOpen: true,
    rightOpen: false,
    leftWidth: state.leftWidth,
    rightWidth: state.rightWidth,
    dragOffset: 0
  };
}

/** 打开右侧抽屉（同时关闭左侧） */
export function openRightDrawer(state: DrawerTracksState): DrawerTracksState {
  return {
    leftOpen: false,
    rightOpen: true,
    leftWidth: state.leftWidth,
    rightWidth: state.rightWidth,
    dragOffset: 0
  };
}

/** 关闭所有抽屉 */
export function closeAllDrawers(state: DrawerTracksState): DrawerTracksState {
  return {
    leftOpen: false,
    rightOpen: false,
    leftWidth: state.leftWidth,
    rightWidth: state.rightWidth,
    dragOffset: 0
  };
}

/*
 * 【本轮删除的三个导出：`DRAWER_OVERLAY_ALPHA` / `drawerOverlayAlpha` / `mainTranslateX`】
 *
 * 它们服务的是 AppShell 的三轨时代——「遮罩按拖拽偏移渐变」「主区横向平移」。
 * v2 删除 AppShell（T025）后，手机链的抽屉由 `RemoteShell` 自己实现：
 * 遮罩色走 MobileTheme 的 `overlayMask` token（源码 `scrim` 同语义），
 * 开合是"阈值触发即切换、不跟手"（facade 没有 dragOffset 写通道，见 RemoteShell 头注释），
 * 主区不位移（源码 `mainTranslateX` 恒为 0 的语义）。
 * 三者因此全无调用点，且**各自都带一个只服务它们的常量**（`DRAWER_OVERLAY_ALPHA`、
 * `DRAWER_ANIM_DURATION`——后者连函数一起删）：留着就是"已删组件的连带残留"。
 *
 * 保留 `dragOffset` 字段本身：它是 `DrawerTracksState` 的对外形状（值类型快照），
 * 未来接跟手拖拽时要用；删字段会让快照形状与既有 fixture 一起改，收益为零。
 */
