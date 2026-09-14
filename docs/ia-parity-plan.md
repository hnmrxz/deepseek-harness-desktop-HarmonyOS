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
| `AppShell` / `MainShell` | ❌ **下一步**。阻塞点已查明（见下）|

**AppShell 不能用"注入 Builder"那条路（有真机实证）**

`docs/50` 的 **E118** 记录了本仓一次真机崩溃：`@BuilderParam coreSlot`（把父组件的 `@Builder`
注入子组件再调用）⇒ 真机点按即 `JsError` 杀进程；修复办法是**显式传 6 个属性**。
所以"`AppShell` 接收三条轨道的内容"这条路**在本仓真机不可用**——`@BuilderParam` 编译能过，
真机不认。可行的两条路：

1. **显式 props**（E118 已验证的形态）：`MainShell` 接收主区所需的数据与回调。P0 剩下的量在于
   主区六个面板的 props 面（约 100 项），机械但可观。
2. **`@Provide/@Consume`**（本轮已在侧栏验证编译通过；**运行时待真机确认**，见 D9）：
   可以显著缩小 props 面——但按 D9 的闸门，**D9 通过前不用于主区**。

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
