# 阶段重定义：官方信息架构对齐（Web Information Architecture Parity）

> 本文是**当前阶段的正式工作令**，取代"缺一个功能 → 加一个组件"的做法。
> 它由项目所有者于 2026-09-14 提出并作为下一步的开发阶段。

## 0. 为什么改变阶段

现在的状态是**功能不少、页面还是不像官方**。原因不是"少了几个按钮"，而是**信息架构没落地**：

```
功能 = 很多      栏目 = 很少      框架 = 不完整      层级 = 混在一起
```

用户实际看到的是"一个很大的页面，里面塞了很多按钮、卡片、面板"；而官方是
`AppFrame → 导航层 → 工作区层 → 会话层 → 内容层 → 上下文面板层`。
**视觉好不好，很大程度上是信息架构决定的**：框架错，间距再漂亮也错；栏目错，颜色再漂亮也错；
内容层错，Markdown 再漂亮也错。所以**精修排在最后**。

## 1. 目标架构

```text
AppFrame
├── Sidebar ── Brand / New Session / WorkspaceBrowser / Panel Entries / Settings（固定在底部）
├── Main ───── ConversationShell（ConversationHeader / Content / ProcessGroup / Answer / Composer）
└── Rightbar ─ PanelRegistry（Files / Preview / Trajectory / Tool Details / Subagent / Deliverables）
```

四形态**共享同一套信息架构**，只有 `geometry / input / panel presentation` 不同：

| 形态 | Sidebar | Main | Rightbar |
|---|---|---|---|
| 手机 | Drawer / Sheet | 全屏 | Sheet / 全屏 |
| 平板竖屏 | Rail | 主区 | Sheet / 浅层面板 |
| 平板横屏 | 面板 | 主区 | 真右栏 |
| PC / 2-in-1 | 面板 | 主区 | 真右栏 |

## 2. 当前事实（已核对仓库，不是印象）

| 项 | 现状 |
|---|---|
| 一级导航 | `NavTab` = `WORKSPACES(工作区)` / `CORE(核心)` / `SETTINGS(设置)`；`SESSIONS` 是 `WORKSPACES` 的**别名**，`PENDING` 保留常量但**不占页签**（`Breakpoints.ets`） |
| 页面装配 | `Index.ets`（约 5000 行）同时负责：页面判断 / 导航判断 / 布局判断 / Pane 装配 / Overlay / Sheet / Back / 会话内容 |
| 工作区 | `WorkspacePane` + `SessionListPane` **两个并列 Pane**，而不是一个 WorkspaceBrowser |
| 右栏 | `LayoutController` 已有可用空间/夹取/拖拽/宽度记忆；但仍是"主页面旁边放一个详情组件"，没有 `PanelRegistry → selectedPanel → PanelOwner` |
| 设置 | 单一 `SettingsPane.ets`，没有 General / Models / Plugins / Plugin Inventory 的域划分 |
| 面板体系 | **没有** `PanelId` / `PanelDescriptor` / `PanelOwner` |

## 3. 分步计划（每步 <500 LOC，门禁全绿，如实区分实现完成与真机待验收）

### P0 页面框架（AppFrame）

**进度（2026-09-15）**：纯逻辑层已完成，视图层未开始。

| 子项 | 状态 |
|---|---|
| `appstate/model/PanelRegistry.ets` | ✅ 已落地（`PanelId`/`PanelLocation`/`PanelDescriptor` + `register`/`unregister`/`descriptors`/`find`/`select`/`canSelect`/`firstAvailable`） |
| `appstate/model/NavigationState.ets` | ✅ 已落地（**页面 ≠ 选中的面板**：`selectedMainPanel` / `selectedRightPanel` / `settingsSection` / `sidebarExpanded` / `mobileDrawer` / `activeOverlay`；转移全部经注册表校验） |
| `appstate/ui/ShellTracks.ets` | ✅ 已落地（四形态下三条轨道**怎么呈现**；只变几何，不变信息架构） |
| 与既有导航的迁移桥 | ✅ 已落地（`mainPanelOfLegacyTab` / `legacyTabOfMainPanel`，含往返断言）——**迁移期间行为不变** |
| fixture | ✅ 46 条（注册表 12 / 导航状态 16 / 迁移桥含往返 10 / 四形态轨道 8） |
| `view/shell/SidebarShell.ets` | ✅ 已落地：**侧栏内容归它所有**（品牌行 / 面板清单 / 待决徽标 / 二级入口 / Settings 固定底部），三种呈现（PANEL / RAIL / 底部标签）都在它内部 |
| `Index` 的三段侧栏 builder | ✅ 已改为委托（只保留"这条轨道的 surface"：宽度与底色） |
| `view/shell/RightbarShell.ets` | ✅ 已落地：右栏**面板本体**归它所有（标题行 / 关闭入口 / sections / 宽度与底色），三种呈现（真右栏 / 侧边浅层面板 / Sheet）都在它内部 |
| `@Provide/@Consume` 机制 | ✅ **已小范围验证并在真实用途上用起来**：`Index` `@Provide('panelRegistry')`、`SidebarShell` `@Consume` 并按注册表可用性过滤入口（编译通过）。⚠️ 运行时行为**必须真机确认**（`@BuilderParam` 编译通过但真机崩过，D4）⇒ 见 `docs/device-validation.md` **D9** |
| `NavigationState` 成为视图唯一真值 | ✅ **已落地**：`Index` 的 `@State tab: NavTab` 已删除，页面选择改由 `nav.selectedMainPanel` 决定；`NavTab` 退化为**迁移期别名**（经 `legacyTabOfMainPanel` / `mainPanelOfLegacyTab` 双向桥，往返有断言）。切页签同样**经注册表校验**（不可用的面板切不过去） |
| 主区"此刻显示哪个面板" | ✅ **已收进纯模型**（`activeMainPanelOf`：下钻页 > 会话页（须有会话）> 选中的面板），视图只按一个值分派 |
| `view/shell/MainHeaderShell.ets` | ✅ 已落地：主轨道的**页头**归它所有（返回 / 标题 / 详情入口），只认三个 props + 两个回调——导航与几何事实留在宿主 |
| 命令面板拆解 | ✅ 已完成：`GoalBar`（零 props）→ `SessionModelPicker`（3 props + 1 回调）→ `CommandList`（2 props + 1 回调）。呈现归组件、判定与副作用归宿主 |
| 连接横幅 | ✅ `view/HubBanner.ets`（6 props；保留"重连仅在 DEGRADED 出现"与协议旁路日志尾部两条语义） |
| **主区搬迁的真实规模** | 已勘清：`tabContent` 182 + `workspaceHub` 158 + `workspaceGroup` 119 + 其余分支 ≈ 230 ⇒ **约 690 行 + 40 余个门面成员**；且确认体内**只有 1 个 `@Builder` 调用**（`tabContent`），故门面方案成立 |
| 面板组件清单 | `view/GoalBar.ets`、`view/SessionModelPicker.ets`、`view/CommandList.ets`、`view/shell/{SidebarShell,MainHeaderShell,RightbarShell,TrackResizer}.ets` |
| `view/shell/TrackResizer.ets` | ✅ 已落地：**轨间把手**（不属于任何一条轨道）；命中区域按输入模态放宽、拖动策略仍在纯模型里。⇒ AppFrame 的 chrome 四位各有其主 |
| `AppShell` / `MainShell` | ❌ **下一步，且是 P0 唯一剩下的大块**：主区**内容**（六个 Pane）搬迁，只能走显式 props（E118/D9 约束）|

**AppShell 不能用"注入 Builder"那条路（有真机实证）**

`docs/50` 的 **E118** 记录了本仓一次真机崩溃：`@BuilderParam coreSlot`（把父组件的 `@Builder`
注入子组件再调用）⇒ 真机点按即 `JsError` 杀进程；修复办法是**显式传 6 个属性**。
所以"`AppShell` 接收三条轨道的内容"这条路**在本仓真机不可用**——`@BuilderParam` 编译能过，
真机不认。可行的两条路：

1. **显式 props**（E118 已验证的形态）：`MainShell` 接收主区所需的数据与回调。P0 剩下的量在于
   主区六个面板的 props 面（约 100 项），机械但可观。
2. **`@Provide/@Consume`**（本轮已在侧栏验证编译通过；**运行时待真机确认**，见 D9）：
   可以显著缩小 props 面——但按 D9 的闸门，**D9 通过前不用于主区**。

**主区内容搬迁：量化结论（2026-09-15，脚本实测）**

| 项 | 数字 |
|---|---|
| 需搬的 builder | `mainContent` 276 行 + `tabContent` 182 + `workspaceHub` 158 + `workspaceGroup` 119 = **735 行** |
| 门面成员 | **108 个**外部引用（值 + 方法），其中 4 个（`attachWorkspaceFileToComposer`/`pickAndAttach`/`runDiagnostics`/`writeSetting`）的声明形式不是单行，需单独处理 |
| 阻碍脚本化的点 | 108 个方法包装需要精确签名（部分多行）；且**体内有 1 个 `@Builder` 调用**（`tabContent`）⇒ 那一段必须作为组件自己的 builder 一起搬 |

⇒ **不靠一次性脚本**。执行顺序（每步跑全门禁）：① 先搬 `tabContent` + `workspaceHub` + `workspaceGroup`（459 行，它们互相调用、自成一束）② 再搬 `mainContent` 的四个分支 ③ 最后搬分派骨架。
**门面按"搬一束、生成一束"增量长出来**，而不是一次生成 108 个成员——这样每步的编译修复面都可控。

**⚠️ 第一束实操后的关键发现（2026-09-15，本轮实测）：门面必须带 setter**

本轮真去搬了第一束（`tabContent` + `workspaceHub` + `workspaceGroup`，459 行），一路修到只剩 4 类错误时，
发现一个**比编译错误严重得多**的问题：

> 被搬走的代码**会写宿主状态**——`this.treeEmptyTitle = '…'`、`this.pendingWorkspacePick = true`、
> `this.treeEmptyHint = '…'` 等等。门面的成员若是**普通属性**，这些赋值只会写进**门面副本**，
> 宿主永远收不到 ⇒ 不是编译错误，而是**静默行为错误**（界面看着正常，状态没变）。

**因此门面的每一类成员都要按语义分型**：

| 成员 | 门面里应是 |
|---|---|
| 只读值 | `x: T`（快照） |
| 只读方法 | `x(...): R`（闭包） |
| **被写的值** | **必须 `setX(v: T): void`**，并把搬走代码里的 `this.f.x = v` 改写成 `this.f.setX(v)` |
| 被调用的组件/其它 builder | 它们**已经是组件**（如 `hubBanner` → `HubBanner`）⇒ 直接渲染组件，不走门面 |

**生成脚本已留档**：`dist/scratch/mig.py`（已含两次实操修掉的全部坑：括号配平、装饰器同搬、导入差集、
深度扫赋值、setter 生成、委托保参、`build()`、子组件与纯函数导入）。**下一轮直接改它**，不要重写。
（放在 `dist/` 下——它已被 gitignore，属工具而非产物；`/tmp` 会被别的进程干扰。）

**⚠️ 第二次实操的收敛结果（2026-09-15）：只剩 4 个"UI 组件语法"错误**

按修正后的顺序（写点分析 → setter → 生成）**真的把第一束搬完了**，编译从 100+ 错误收敛到 **4 个**，
且它们同型：

```
'HubBanner({ … })'    does not meet UI component syntax   ← 在 @Builder workspaceHub 里
'PendingPane({ … })'  does not meet UI component syntax   ← 在 @Builder workspaceHub 里
'WorkspacePane({ … })' does not meet UI component syntax  ← 在 @Builder tabContent 里
'SettingsPane({ … })' does not meet UI component syntax   ← 在 @Builder tabContent 里
```

也就是说：**"在被搬进组件的 `@Builder` 里实例化别的 `@Component`"这条写法没通过 ArkUI 检查**。
已排除的猜想：导入路径（已从 `'../X'` 改成 `'./X'`，错误不变）、缺 `build()`（已加）、
`@Prop` 门面类型（编译器没有就此报错）。

**下一轮先从这 4 个错误入手**，候选排查方向（按可能性排序）：
1. `@Builder` **带参数**时（`tabContent(compact: boolean)` / `workspaceHub(compact: boolean)`）
   其内部是否允许实例化自定义组件 —— 试着把这些子组件挪到一个**无参 `@Builder`** 或直接放进 `build()`；
2. 自定义组件调用是否必须**独占一行**或以 `})` 结束语句（当前是 `})` 后无分号，样式与 Index 一致）；
3. 把 `HubBanner`/`PendingPane`/`WorkspacePane`/`SettingsPane` 从"组件"改成**通过门面渲染**的形态
   （即它们也走 `@Builder`？—— 但那条路已被 E118 否掉）⇒ 更可能是 1。

**本轮同样回退**（保住绿灯）。但两次实操把可变因素收敛到"一处 ArkUI 约束"，不是"整条路线不成立"。

**下一轮的执行顺序**（已按本轮踩到的坑修正）：
1. 用脚本先做**写点分析**（列出 `this.X = …` 的目标），据此把成员分成"读 / 写 / 方法"三类；
2. 生成门面时：写成员生成 `setX`，搬走的代码里把赋值改写成 setter 调用；
3. 再走本轮已验证通过的其余步骤（装饰器连同方法一起搬、括号配平切段、值导入与类型导入分别取差集、
   组件依赖（`WorkspacePane`/`SettingsPane`/`PendingPane`/`HubBanner`）与纯函数（`formatClock`/`relativeTime`/`sessionEmptyCopy`）
   一并导入）。

本轮**已回退**（保住绿灯）：证明这条路可行但需要 setter 那一层，不在预算中途留破损。

**主区内容搬迁的可行方案（已勘明，下一轮按此机械执行）**

`mainContent()` 345 行、依赖宿主约 100 个 `@State`。逐 `this.x` → `props.x` 重写既慢又易错，
故采用**门面（facade）**方案：

1. 定义 `MainShellFacade`（`view/shell/` 内的接口）：成员名与宿主字段/方法**同名**
   （`stackPage`、`selectedSessionId`、`hubConnected`、`showsConversation()`…）。
2. `Index` 提供 `private buildShellFacade(): MainShellFacade`——**每次渲染重建**
   （值型成员是快照、方法型成员是 `() => this.xxx()` 闭包）。⚠️ 必须每次重建：
   门面若被缓存，"中枢变了但界面不更新"就回来了。
3. 把整段内容**原样搬进** `MainShell`，只做一次机械替换：块内 `this.` → `this.f.`。
4. `Index` 侧变成 `MainShell({ f: this.buildShellFacade() })`。

**为什么可行**：它不碰 E118 那条禁令（没有 builder 注入），也不用等 D9（不依赖 `@Provide`），
只是把"父组件读自己的状态"换成"子组件读传来的门面"。
**风险与纪律**：一次只搬一个面板分支（诊断 → 连接 → 会话 → 其余），每搬一块跑全门禁；
`mainContent()` 的**分派骨架留在最后**搬，否则中间态会出现两处分派。

**因此下一步的次序是**：先做 `AppShell` 的**不含内容注入**部分（根容器、overlay/sheet 宿主、
返回处理、快捷键与输入证据采集挂在同一处），再按上面两条路之一逐步把主区搬出去。
每搬一块跑一次全门禁。

**下一步的做法（写下来避免走偏）**

1. **先抽 `SidebarShell`**（最小、最自足：`navPanel` 56 行 + `navRail` 28 行 + 底部标签），
   用显式 props（导航状态 + 面板清单 + 回调）——**这一步不需要新机制**，也是 shell 模式的真实证明。
   抽完后 `Index` 不再自己写侧栏的两个 builder。
2. `AppShell`/`MainShell`/`RightbarShell` 的瓶颈是**状态归属**：主区内容（Conversation/Workspace/Core/
   Settings/Diagnostics/Connect 六个面板）现在直接读 `Index` 的 ~100 个 `@State`。把这 5000 行状态
   搬进 shell 组件、或改成 `@Provide/@Consume`（本仓**尚无先例**），是一个**要单独决策**的步骤——
   先在一个最小范围内验证该机制能编译、能在真机跑（`@BuilderParam` 曾导致真机 JS 崩溃，D4），
   再全量迁移。**不要一次性重写 Index。**
3. 每搬一块职责跑一次全门禁；`Index.ets` 的验收标准是"不再直接负责页面级 Pane 选择"。

新增：`view/shell/AppShell.ets`、`SidebarShell.ets`、`MainShell.ets`、`RightbarShell.ets`；
`appstate/model/PanelRegistry.ets`、`appstate/model/NavigationState.ets`。
**验收**：`Index.ets` 只做装配与状态订阅；三栏骨架由 shell 组件承担；纯逻辑（面板注册表、导航状态）有 fixture。
**这一阶段的实质是"把 Index 的职责拆出来"，不是加功能。**

### P1 Sidebar
`Brand` / `NewSession` / `WorkspaceTree`（`WorkspaceRow` + `SessionRow`）/ `GlobalPanelList` / `SettingsEntry`（固定底部）。
**验收**：`WorkspacePane` 与 `SessionListPane` 合并为 `WorkspaceBrowser`；一级导航不再是"三个页签"。

### P2 Main 会话框架
`ConversationShell`（`ConversationHeader` / `Content` / `ProcessGroup` / `Answer` / `Composer`）。
在这一阶段处理：**Markdown**、**Prompt 隐藏的收尾**、Message Action、Tool Card。
`ConversationHeader` 的官方字段：Session title / Agent preset / Goal / Jobs / Schedule / Open in App / Workspace context / Rightbar access。
Composer 的官方字段：Model / Reasoning effort / Permission / Plan / @ Reference / Skill / Attachment / Command / Send。

### P3 Rightbar
`PanelId` / `PanelDescriptor` / `PanelOwner` + `selectedPanel`；
面板：Files / Preview / Trajectory / Tool Details / Subagent / Deliverables。
**验收**：右栏内容由注册表驱动（不是 `DetailPane` 里的一串 `if`）；宽度/让步链沿用既有 `LayoutController`。

### P4 Settings 域
`SettingsShell`（General / Models / Plugins / Plugin Inventory / …）。**不再往 `SettingsPane.ets` 里堆内容。**

### P5 视觉精修
只有在此阶段才做间距/颜色/动效的对齐。

## 4. 已完成的相邻工作（不重复做）

| 项 | 状态 |
|---|---|
| Host / 协议 / 会话状态 | 🟢（`docs/50` 的 E 系列证据链） |
| 多形态几何决策 | 🟢（`LayoutController` + 69 条 fixture；拖拽与宽度记忆已落） |
| 输入模态事实 | 🟢（设备枚举 + 事件证据 + 形态猜测三级链） |
| **Prompt 泄漏（P0-1）** | 🟢 **本轮关闭**：`internal` 结构字段 + `conversationAudienceOf` 单一判据 + 搜索按视图作用域。此前两条路径都通（直接显示 / 被搜到并计数） |
| Conversation 数据模型（回合） | 🟢（`groupTurns` / `Follow` / `chatVisibleItems`） |
| Markdown | 🔴 **未做**（当前是 `Text(item.body)`） |
| Sidebar 信息架构 / AppFrame / Panel Registry / Settings 域 | 🔴 **本阶段要做的** |

## 5. 纪律（沿用既有约定）

- 每步一个可编译、可测、可回滚的小改动；**先做纯逻辑模型与 fixture，再接视图**。
- 严禁为了"看起来像官方"而写死内容或造无协议支持的后端。
- **无真机/模拟器时：不宣称视觉验收完成**；结构、状态与渲染规则必须可自动验证。
- 拆 `Index.ets` 的过程中，**同一时刻只搬一块职责**，每搬一块跑一次全门禁。
