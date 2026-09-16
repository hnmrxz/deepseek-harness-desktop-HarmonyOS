/**
 * 导航状态机（P1：把「导航决策」从 `Index.ets` 搬出来，计划 §7 拆分第 2 步）。
 *
 * 【为什么必须是独立模块】导航有两处**优先级阶梯**，此前都写在 4600 行的 `Index.ets` 里：
 *   1. **返回键**：浮层 → 二级页 → 详情 → 工作区下钻 → 文件预览 → 回首页签 → 交给系统（7 级）；
 *   2. **点页签**：归一化（待决并入工作区、核心并入设置）→ 清栈 → 清空会话选择 → 决定要不要重读静态事实。
 * 这两处都是**纯决策**（输入是状态，输出是"该做什么"），却与渲染和副作用缠在一起，
 * 于是既没法单独测试，也没法在别处复用。搬到这里之后：
 *   - `tools/check-layout-fixtures.mjs` 能在**本机直接执行**它们（无需真机）；
 *   - `Index.ets` 只负责"照做 + 打日志"，不再自己排优先级。
 *
 * 【设计取舍：为什么返回"动作令牌"而不是直接改状态】副作用（日志、刷新、清空草稿）
 * 只有视图层知道怎么做。控制器只回答"**该发生哪一件事**"，视图负责执行。
 * 这样优先级可以被穷举测试，而执行路径仍然只有一条。
 */

import { NavTab } from './Breakpoints';

/**
 * 下钻页（单栏形态下逐级进入；多栏形态下这些内容并排显示，不占栈）。
 *
 * 【为什么没有 `DETAIL`（P1.5 移除）】详情此前是一条全屏栈页。但鸿蒙的
 * `bindSheet` 语义正是"非全屏、**保留父视图环境**"——把会话内容留在下面、
 * 详情盖一半，比整页替换更贴合"我要边看对话边看详情"的真实意图。
 * 因此详情改成**半模态 Sheet**，不属于栈；栈里只留真正逐级下钻的页。
 */
export enum StackPage {
  MAIN = 'main',
  CONVERSATION = 'conversation',
  DIAGNOSTICS = 'diagnostics',
  CONNECT = 'connect'
}

/** 导航状态（视图层持有，控制器只读） */
export interface NavState {
  /** 当前一级页签 */
  tab: NavTab;
  /** 单栏形态下的栈位置 */
  stackPage: StackPage;
  /** 工作区目录下钻层数 */
  wsDrill: number;
  /** 是否选中了会话（用布尔而不是 id：控制器不该关心 id 从哪来） */
  hasSession: boolean;
  /** 详情栏/详情抽屉是否打开 */
  detailOpen: boolean;
  /**
   * 主区此刻是不是**"某个会话的整页"**（手机单栏形态）。
   *
   * 【为什么这是一个导航事实，而不是视图细节】多栏形态下会话是主区里的内容，旁边/旁边栏里
   * 始终能看到会话列表 ⇒ 会话**不是一层**，返回键在根层交给系统是对的。
   * 单栏（手机）形态下恰恰相反：会话盖住了列表（`openSession` 在 SINGLE 下把 `stackPage`
   * 设成 `CONVERSATION`），它就是**一层**。缺了这个事实，返回键会落进"回主列表"分支而
   * `selectedMainPanel` 仍是会话 ⇒ 屏幕上什么都不变（一次白按），再按一次直接退出应用。
   */
  conversationIsPage: boolean;
  /**
   * 手机侧栏抽屉是否打开（单栏形态；它是**盖在页面上的导航面**，故返回键第一优先级要关它）。
   *
   * 【为什么放在 `NavState` 而不是 `OverlayState`】`OverlayState` 那一组是"编辑态/模态"
   * （凭据、草稿、搜索、选择器、详情浮层），它们的共性是"有一个待提交的编辑"；
   * 抽屉只是导航面的另一种呈现，不持有编辑态。
   */
  drawerOpen: boolean;
}

/** 会"盖在页面上"的浮层与编辑态（返回键第一优先级要关掉它们） */
export interface OverlayState {
  credentialOpen: boolean;
  settingDraftOpen: boolean;
  searchOpen: boolean;
  choosingOpen: boolean;
  /** 详情半模态 Sheet（P1.5）：它与"盖在页面上"的浮层同类，故排在浮层段 */
  /**
   * 详情是否以浮层形式打开（P3：单栏 = 半模态 Sheet、双栏 = 侧边浅层面板）。
   *
   * 原名 `detailSheetOpen`——双栏改成侧边面板后那个名字会骗人，故一并改。
   */
  detailOverlayOpen: boolean;
  previewOpen: boolean;
}

/**
 * 返回键要执行的动作。
 *
 * `EXIT` 的含义是「**不消费**这次返回」——即交给系统（最小化应用）。
 * 把它显式列出来，是为了避免"忘了 return false 于是按返回没反应"这种假入口：
 * 该交给系统时必须明确交给系统。
 */
export enum BackAction {
  CLOSE_CREDENTIAL = 'close-credential',
  CLOSE_SETTING_DRAFT = 'close-setting-draft',
  CLOSE_SEARCH = 'close-search',
  CLOSE_CHOICE = 'close-choice',
  /** 收起手机侧栏抽屉（第一优先级：它是盖在整页上的导航面） */
  CLOSE_DRAWER = 'close-drawer',
  CLOSE_DETAIL_OVERLAY = 'close-detail-overlay',
  /** 手机单栏：从"会话整页"退回它下面的列表（**保留会话**，不丢上下文） */
  BACK_TO_LIST = 'back-to-list',
  STACK_TO_MAIN = 'stack-to-main',
  CLOSE_DETAIL = 'close-detail',
  DRILL_UP = 'drill-up',
  CLOSE_PREVIEW = 'close-preview',
  TAB_TO_SESSIONS = 'tab-to-sessions',
  EXIT = 'exit'
}

/**
 * 单栏形态下「文件预览」所占的下钻层数。
 *
 * 【这个常量是布局事实，不是偏好】`WorkspacePane.buildStacked` 的窄屏栈式布局是：
 * 0 = 工作区列表、1 = 文件树、≥2 = 预览（`drillLevel` 一档一屏）。
 * 所以"预览在屏幕上"在单栏下等价于"下钻到了第 2 层"。
 */
export const PREVIEW_DRILL_LEVEL: number = 2;

/**
 * 预览此刻是不是**盖在页面上的整页层**（而不是并排的右栏/侧栏面板）。
 *
 * 【为什么需要这个判定】同一个 `previewOpen` 事实在两种形态下是两种东西：
 *   · 单栏（`WorkspacePane.buildStacked`）：预览是**一整屏内容**，它盖住了文件树 ⇒ 属"最上层"；
 *   · 多栏（`WorkspacePane.buildColumns` / 右栏面板）：预览是与文件树并排的一栏 ⇒ 不盖任何东西。
 * 返回键的语义是"关掉最上面那层"，所以只有前者能在"下钻退一层"**之前**轮到它。
 */
export function previewIsLayer(nav: NavState): boolean {
  return nav.tab === NavTab.WORKSPACES
    && nav.stackPage === StackPage.MAIN
    && nav.wsDrill >= PREVIEW_DRILL_LEVEL;
}

/**
 * 关掉预览后应当回到哪一层下钻（P8-1）。
 *
 * 【为什么关预览要动下钻】单栏下预览就是第 2 层：只清 `preview` 会留下**一个看不见、却还在屏幕上"占位"的层**——
 * 下一次返回键会被它白吃一次（用户看到"按返回没反应"），而文件树也回不来。
 * 关掉预览 = 回到文件树，所以层数必须同时退回 1。
 */
export function drillAfterPreviewClosed(nav: NavState): number {
  return previewIsLayer(nav) ? PREVIEW_DRILL_LEVEL - 1 : nav.wsDrill;
}

/**
 * 返回键的优先级阶梯（与迁移前的 `Index.onBackPress` **逐级一致**）。
 *
 * 【顺序不是随意的】浮层在视觉上盖在页面上，所以先关浮层；二级页比"详情抽屉"更外一层；
 * 只有真的在根层（首页签、无浮层、无下钻）才把返回交还系统。
 *
 * 【P8-1：预览有两处判断点，不是重复】单栏下预览是整页层 ⇒ 排在"下钻退一层"之前（③）；
 * 多栏下它是并排的一栏 ⇒ 排在详情之后（⑦）。两处用的是**同一个事实 + 同一个可见性判定**
 * （`previewIsLayer`），因此不会各说各话：可见时它先关，不可见时不占返回键。
 */
export function decideBack(nav: NavState, overlay: OverlayState): BackAction {
  // ⓪ 手机侧栏抽屉：它是"盖在整页之上"的导航面，比任何浮层都靠上——**先关它**。
  // 【为什么必须是第一优先级】抽屉打开时页面被它盖住（手机上占 2/3 宽），
  // 这时按返回的意图一定是"收起抽屉"；若落到后面的分支，用户会看到"返回把下面那层也退了"。
  if (nav.drawerOpen) {
    return BackAction.CLOSE_DRAWER;
  }
  // ① 浮层/编辑态最先关
  if (overlay.credentialOpen) {
    return BackAction.CLOSE_CREDENTIAL;
  }
  if (overlay.settingDraftOpen) {
    return BackAction.CLOSE_SETTING_DRAFT;
  }
  if (overlay.searchOpen) {
    return BackAction.CLOSE_SEARCH;
  }
  if (overlay.choosingOpen) {
    return BackAction.CLOSE_CHOICE;
  }
  // 详情 Sheet 也是"盖在页面上"的一层：它排在其它浮层之后（那些是真正的模态编辑态），
  // 但排在二级页之前——用户心理上"关掉盖着的东西"优先于"退回上一层"。
  if (overlay.detailOverlayOpen) {
    return BackAction.CLOSE_DETAIL_OVERLAY;
  }
  // ③ 文件预览——**仅当它是整页层时**（单栏下钻到第 2 层）。它必须排在"下钻退一层"之前：
  //    此刻屏幕上最上面的东西就是预览，用户按返回的意图是"从预览退回文件树"。
  if (overlay.previewOpen && previewIsLayer(nav)) {
    return BackAction.CLOSE_PREVIEW;
  }
  // ④ 手机单栏：会话是"盖在列表上的一层" ⇒ 退回列表。
  //    【为什么排在二级页之前】单栏下 `openSession` 会把 `stackPage` 也设成 `CONVERSATION`，
  //    两个分支同时成立；而 `STACK_TO_MAIN` 只改 `stackPage`、不改主区面板 ⇒ 屏幕上什么都不变
  //    （一次"按了没反应"），再按一次就退出应用。退会话必须**同时**把主区切回列表。
  if (nav.conversationIsPage) {
    return BackAction.BACK_TO_LIST;
  }
  // ⑤ 二级页 → 回主列表
  if (nav.stackPage !== StackPage.MAIN) {
    return BackAction.STACK_TO_MAIN;
  }
  // ⑥ 会话详情
  if (nav.detailOpen) {
    return BackAction.CLOSE_DETAIL;
  }
  // ⑦ 工作区目录下钻（只在工作区页签下有意义）
  if (nav.tab === NavTab.WORKSPACES && nav.wsDrill > 0) {
    return BackAction.DRILL_UP;
  }
  // ⑧ 文件预览——并排呈现（多栏右栏/侧栏面板）：它不盖任何东西，故排在页面层级之后
  if (overlay.previewOpen) {
    return BackAction.CLOSE_PREVIEW;
  }
  // ⑨ 不在首页签 → 回会话（首页）
  if (nav.tab !== NavTab.SESSIONS) {
    return BackAction.TAB_TO_SESSIONS;
  }
  // ⑩ 已在根层：不消费，交给系统
  return BackAction.EXIT;
}

/**
 * 页签归一化：历史别名落到真正的页签上。
 *
 * - `PENDING` → `WORKSPACES`：待决不占页签，它属于"当前正在跑的那次对话"（E108）；
 * - `CORE` → `SETTINGS`：核心页并入设置（E110），历史调用点（"启动核心后跳过去看"）照旧能用。
 */
export function normalizeTab(tab: NavTab): NavTab {
  if (tab === NavTab.PENDING) {
    return NavTab.WORKSPACES;
  }
  if (tab === NavTab.CORE) {
    return NavTab.SETTINGS;
  }
  return tab;
}

/** 点页签的结果：新状态 + 需要视图执行的副作用（用数据表达，视图只照做） */
export interface TabSelection {
  tab: NavTab;
  stackPage: StackPage;
  wsDrill: number;
  /** 是否清空当前会话选择（离开会话页签时） */
  clearSession: boolean;
  /**
   * 是否需要重读"静态事实"（核心阶段视图 + 技能清单 + Agent 预设 + 提供方目录）。
   *
   * 【为什么每次进非工作区页签都要重读】会话页与设置页的空态文案由**核心阶段**决定，
   * 而首启时序是"页面先渲染、核心后解包就绪"。不重读会出现自相矛盾的读数：
   * 核心页写着「就绪 · 已安装 1 个版本」，会话页却写着「还没有安装核心」。
   */
  refreshStaticFacts: boolean;
}

/** 页签点击的决策（迁移前是 `Index.selectTab` 的前半段） */
export function selectTab(nav: NavState, requested: NavTab): TabSelection {
  const tab: NavTab = normalizeTab(requested);
  return {
    tab: tab,
    stackPage: StackPage.MAIN,
    wsDrill: 0,
    clearSession: tab !== NavTab.SESSIONS,
    refreshStaticFacts: tab !== NavTab.WORKSPACES
  };
}

/**
 * 是否正在看某个会话（决定详情栏能不能并排显示）。
 *
 * `SESSIONS` 在枚举里是 `WORKSPACES` 的别名（E108 合并），所以这里的判断同时覆盖两者。
 */
export function showsConversation(nav: NavState): boolean {
  return nav.hasSession && nav.tab === NavTab.SESSIONS;
}

/** 一级页签的顺序（视图层据此渲染；顺序属于导航，不该由某个 Builder 自己写） */
export function navTabs(): NavTab[] {
  return [NavTab.WORKSPACES, NavTab.SETTINGS];
}
