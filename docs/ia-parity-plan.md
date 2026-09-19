# 阶段重定义：官方信息架构对齐（Web Information Architecture Parity）

> 本文档于 2026-09-19 精简（保留被代码/门禁引用的锚点结论）；完整版见 git 历史。

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

## 2. 被代码引用的架构结论（锚点，原文级保留）

- **轨道布局归 AppShell：AppShell 拥有『窗口宽度 → 几条轨道』这件事**。`view/shell/AppShell.ets` 拥有 `buildSingle`/`buildDouble`/`buildTriple` 的轨道拼装、`navPanel`/`navRail`/`bottomTabs`、`detailColumn`/`detailResizer`、`sidebarPresentation`；浮层门户（`bindSheet` 同一节点只能绑一个）有意留在页面根 `Index.build()`——官方 Web 的 portal 也在 App 根，这是语义正确的分层，不是妥协。
- **侧栏该用哪种呈现是几何层判定、栏目不随形态变**。三种呈现（PANEL / RAIL / 底部标签）都在 `SidebarShell` 内部；侧栏**内容**（品牌行 / 面板清单 / 待决徽标 / 二级入口 / Settings 固定底部）四形态一致。

## 3. 三个纯模型的职责

- **PanelRegistry**（`appstate/model/PanelRegistry.ets`）：`PanelId`/`PanelLocation`/`PanelDescriptor` + `register`/`unregister`/`descriptors`/`find`/`select`/`canSelect`/`firstAvailable`——面板体系与"入口的存在与顺序"归它；`available: () => false` 的席位不进选择集（E110 口径）。
- **NavigationState**（`appstate/model/NavigationState.ets`）：视图唯一真值，**页面 ≠ 选中的面板**——`selectedMainPanel`/`selectedRightPanel`/`settingsSection`/`sidebarExpanded`/`mobileDrawer`；切换全部经注册表校验（不可用的面板切不过去）。
- **ShellTracks**（`appstate/ui/ShellTracks.ets`）：四形态下三条轨道**怎么呈现**；只变几何，不变信息架构。

## 4. 两条硬事实

- **E118（真机实证）**：`@BuilderParam` 注入（父组件的 `@Builder` 注入子组件再调用）**编译通过但真机点按即 JsError 杀进程**；修复形态 = **显式传 props**。⇒ shell 组件接收内容一律走显式 props / 门面，不走 builder 注入。
- **D9（待真机）**：`@Provide/@Consume` 已小范围验证编译通过（侧栏入口按注册表可用性过滤）并真实使用，但**运行时行为必须真机确认**（见 `docs/device-validation.md`）；**D9 通过前不用于主区**。

## 5. 各阶段最终状态

- **P0 AppFrame**：✅ 已落地——注册表 / 导航状态 / 轨道三模型 + 迁移桥（`NavTab` 退化为迁移期别名，双向桥往返有断言）；`SidebarShell`/`MainHeaderShell`/`RightbarShell`/`MainShell`/`AppShell`/`TrackResizer` 各有其主；`Index` 不再负责页面级 Pane 选择与轨道 chrome。主区搬迁用**门面（facade）**方案：每次渲染重建；被写的值必须 `setX` setter——否则只写进门面副本 = 静默行为错误。缺：主区六面板的 props 面仍大。
- **P1 Sidebar**：✅ 已落地——`WorkspaceBrowser`（树挂进侧栏 PANEL 呈现；窄版行"改行不改树"；窄版动作**不**收进 `⋯` 菜单是有意：不能真机验证悬停/菜单态前不藏唯一入口）；一级导航由注册表驱动（`SidebarShell` 再无 `NavTab`；E110 核心席位 `available:false`）；手机抽屉接上 `mobileDrawer`（返回键第一优先级收抽屉）。缺：会话搜索、RAIL 上的 `NewSession`、真机确认（D11）。
- **P2 Main**：✅ 主体已落地——`MessageFeedback`/`MessageRow`/`ConversationHeader`/`TurnView`/`ReasoningRow` 拆出；Markdown（模型 + `MarkdownRenderer`，流式未闭合围栏不算错误）；后台任务条；会话头上下文行（Workspace context / Model / 最近活动）；浮层成组件（`FolderPicker`/`SettingTextSheet`/`SettingStructSheet`/`CredentialSheet`/`ChoiceSheet`）；`RightbarFacade` 门面；单栏 Sheet 切换器；侧栏可收起 + 持久化；新建会话入口补全；删掉平行状态机 `activeOverlay`。缺：宿主处理器按域收口、右栏滑入动画与拖拽调宽（须真机）、会话头 Agent preset / Schedule / Open in App（缺协议面，不猜）。
- **P3 Rightbar**：✅ 已落地——官方六个候选（文件 / 预览 / 轨迹 / 工具 / 子代理 / 交付物）全部接上 + 本仓「详情」= 七个可用面板；`selectedRightPanel` 有消费者；切换器只在可用面板 ≥2 时出现；每个面板与另一挂载点**共用同一份组件**；右栏轨迹只放总览、聚焦只高亮不跳转。缺：侧边面板滑入动画、面板自身拖拽调宽（登记在案）。
- **P4 Settings**：✅ 已落地——分区进注册表（官方四段在前，本仓特有四段 `owner: 'hdsh'`，不冒充官方分区名）；按域拆出 `SettingsGeneral/Models/Plugins/Inventory/Skills/Presets/Device/Core` + `SettingRow`；设置回执带归属域（E347 修复：工作区/会话回执改走 `attachNotice`）；E343 真机冷启自递归崩溃已修并补门禁 `check-builder-recursion.mjs`。缺：设置项写入的统一事务与失败回执按域收口、四形态观感（D17 真机）。
- **P5 视觉精修**：未开始（有意排最后：框架错，间距再漂亮也错）。

## 6. 纪律

- 每步一个可编译、可测、可回滚的小改动；先做纯逻辑模型与 fixture，再接视图。
- 严禁为了"看起来像官方"而写死内容或造无协议支持的后端。
- 无真机/模拟器时不宣称视觉验收完成；拆 `Index.ets` 同一时刻只搬一块职责，每搬一块跑一次全门禁。
