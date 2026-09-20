# Deletion Manifest — PC 组件可达性终裁清单（T006）

**Feature**: dsh-full-parity（v2 官方 UI 复刻转向）
**Produced by**: T006 静态引用分析（2026-09-20）
**分析基准**: **v2 路由后的渲染树**——`Index.ets` 按 T003 的 formFactor 条件渲染：`DESKTOP_LIKE` → WebShell（Web 直载官方 UI，本文件分析时以「只渲染 WebShell 及其等待/错误态」为假设基准）；`PHONE` → RemoteShell（DSH Mobile 范式）。
**判定规则**: 以 **import 实证**为终裁（R&D-004：「删除的判定必须以可达性为终裁而非直觉」）。手机链可达 ⇒ 保留；仅 PC 链可达 ⇒ 删除候选。

---

## 1. 渲染分叉点实证（v1 现状）

`entry/src/main/ets/pages/Index.ets` build()（L2697–2705）：

```text
Stack() {
  if (this.runMode === RunMode.REMOTE && this.mode === LayoutMode.SINGLE) {
    RemoteShell({ f: this.buildRemoteShellFacade() })   // ← v1 手机链（仅「远程+单栏」）
  } else {
    AppShell({ f: this.buildShellFacade() })            // ← v1 PC 链（含本机手机单栏！）
  }
}
```

- v1 的分叉维度是 `runMode × LayoutMode`：**手机本机模式当前走 AppShell（buildSingle 分支）**。
- v2（T005）改为 `formFactor`：`DESKTOP_LIKE`（平板/2in1/折叠展开）→ WebShell；`PHONE`（手机/折叠闭合，本机与远程均）→ RemoteShell。
- **v2 路由后 AppShell 分支整体不可达** ⇒ AppShell 及其独占子树成为删除候选。
- Index 根节点另挂形态无关的**浮层门户**（bindSheet，L2776–2780）：ChoiceSheet / CredentialSheet / FolderPicker / SettingTextSheet / SettingStructSheet / detailSheet(RightbarShell OVERLAY)——门户语义（「portal 挂在页面根、不属于任何 pane」），v2 后继续服务手机链设置页/权限/凭据/详情浮层。

---

## 2. 手机链可达集合（47 个 view 组件）

从 `RemoteShell.ets` 出发递归追踪 import（含类型门面引用的组件）：

| 层级 | 组件 |
|---|---|
| L0 | **RemoteShell** |
| L1 | MainShell（compact）、RightbarShell（右抽屉 SIDE_PANEL）、DrawerNav（左抽屉）、LatticeDock（底部 dock）、HubBanner（断连横幅） |
| L2（经 MainShell） | CommandList、ConnectPane、ConversationPane、DiagnosticsPane、GoalBar、SessionModelPicker、TabContentView |
| L2（经 RightbarShell） | DetailPane、FilePreviewPane、DeliverableCard、TrajectoryInspector、FileTreePane、SubagentCard、TimelineOverview、ToolCard、NativePrimitives |
| L2（经 DrawerNav） | WorkspaceBrowser |
| L3（经 ConversationPane） | TurnView、Composer、MessageRow、DeliverableCard、SubagentCard、ToolCard、ReasoningRow、ConversationHeader、PendingPane |
| L3（经 TabContentView） | SettingsPane、WorkspacePane |
| L3（经 WorkspaceBrowser） | HubBanner、PendingPane |
| L4（经 TurnView） | CommandRow、RetryRow、ProducedFilesRow |
| L4（经 MessageRow） | MarkdownRenderer、MessageFeedback、MessageImages |
| L4（经 ConversationHeader） | TimelineOverview、TrajectoryInspector |
| L4（经 PendingPane） | QuestionGroupCard |
| L4（经 SettingsPane） | SettingsGeneral、SettingsDevice、SettingsModels、SettingsPlugins、SettingsPresets、SettingsSkills、SettingsCore |
| L4（经 WorkspacePane） | FilePreviewPane、FileTreePane |
| L5（经 Settings*） | SettingRow（×3 消费点）、CorePane（经 SettingsCore） |

合计 **47** 个（去重）。加上 Index 根浮层门户 5 个（FolderPicker/ChoiceSheet/CredentialSheet/SettingTextSheet/SettingStructSheet）= **52 个保留**。

---

## 3. 终裁删除清单（5 个候选）

### 3.1 无条件删除（4 个，第一批/T025）

| # | 组件 | 被谁引用（import 链） | 判定依据 | 删除后需同步清理的引用点 |
|---|---|---|---|---|
| D1 | `view/shell/AppShell.ets` | 仅 `pages/Index.ets`（L54–55 值+类型 import；L2703 渲染） | PC 三栏轨道壳（buildSingle/buildDouble/buildTriple + navPanel + detailColumn）。v2 后 DESKTOP_LIKE 走 WebShell、PHONE 走 RemoteShell，两个分支都不再渲染它 | ① Index L54–55 import；② Index build() else 分支 L2703；③ Index `buildShellFacade()` L2599–2646（AppShellFacade 构造）；④ Index 内 AppShellFacade 类型引用（`RightbarFacade` 类型保留——RightbarShell 存续）；⑤ **tools/check-feature-wiring.mjs L349–353**：FORBIDDEN 规则 `files: ['entry/src/main/ets/view/shell/AppShell.ets']`（文件消失后门禁报「受检文件不存在」） |
| D2 | `view/shell/MainHeaderShell.ets` | 仅 `AppShell.ets`（L25 import；header chrome） | 主区页头是 PC 轨道 chrome；手机链页头 = ConversationHeader（T014 对照 ChatTopBar.kt），RemoteShell 不渲染它 | 仅 AppShell 内部 import，随 D1 一起消失；无独立清理点 |
| D3 | `view/shell/SidebarShell.ets` | 仅 `AppShell.ets`（L31 import；navPanel rail/panel surface） | PC 侧栏轨道表面；手机链左抽屉 = DrawerNav（T019 对照 ChatListDrawer.kt），直接渲染 WorkspaceBrowser，不经 SidebarShell | 仅 AppShell 内部 import；注意它 import 的 WorkspaceBrowser（L 内 `../WorkspaceBrowser`）是保留件，删除不动后者 |
| D4 | `view/shell/TrackResizer.ets` | 仅 `AppShell.ets`（L32 import；detailResizer 轨间把手） | 三栏/双栏右栏拖宽把手，纯 PC 几何；手机链无此交互（DSH Mobile 右抽屉定宽） | ① AppShell 内部 import；② Index 拖拽方法群：`beginDetailDrag/endDetailDrag/updateDetailDrag`、`dragStartWidth`、`detailWidthDesired` + `clampDetailDesired/dragDetailWidth` 消费；③ appstate `LayoutController.dragDetailWidth` 纯函数随之零消费 → T027 一并清理 |

### 3.2 条件删除（1 个，第二批/T026）

| # | 组件 | 被谁引用 | 判定依据 | 前置条件 |
|---|---|---|---|---|
| D5 | `view/ShortcutKeys.ets` | 仅 `pages/Index.ets`（L66–67 `hitOfKeyEvent` + `ShortcutHit` 类型；根节点 8 个 `.keyboardShortcut` L2740–2763 + `onKeyEvent` L2764–2775 + `runShortcut/dispatchKeyHit`） | **非 AppShell 链**——挂在页面根、形态无关；但语义是桌面快捷键（Ctrl+N/K/F/B/J、Ctrl+Shift+P/C、Ctrl+,、Enter/Esc/F5/Alt+方向）。v2 后：DESKTOP_LIKE 官方 Web UI 自带全套快捷键（原生全局快捷键会与其**双触发**，如 Ctrl+N 同时开原生会话与 web 会话）；PHONE 无外接键盘快捷键范式（DSH Mobile 对照源无此交互） | **条件**：T018 手机化完成后确认 Composer 的 Enter 发送分流不依赖根级 `dispatchKeyHit`（软键盘 Enter 由输入组件自理；物理键盘场景若有依赖，则保留 `hitOfKeyEvent` 的 Enter/Esc 两条、删桌面 8 键）。删除时联动清理：Index 根 `.keyboardShortcut`×8、`onKeyEvent`、`runShortcut/dispatchKeyHit`；appstate `ui/Shortcuts.ets` 的 `SHORTCUTS/keyEventSpecs/keyboardShortcutSpecs` 随之 entry 零消费（audit-unused-exports 会点名 → T027 裁决） |

**删除候选合计：5**（4 无条件 + 1 条件式）。

---

## 4. 共用保留（9 个，手机链 ∧ PC 链/Index 双侧消费）

| 组件 | 手机侧消费点 | PC 侧消费点（v2 后退役） | 备注 |
|---|---|---|---|
| `shell/MainShell.ets` | RemoteShell L87 `MainShell({ f, compact: true })`（主区内容分派器） | AppShell 渲染 | **plan.md 原标注「[删除] PC 主壳」与实证不符**：它是主区内容分派（诊断/连接/会话/兜底 TabContentView），非三栏壳；v2 后成为手机链主区唯一分派器，T018 对照 MainScreen.kt 在其上映射 PanelState |
| `shell/RightbarShell.ets` | RemoteShell 右抽屉（SIDE_PANEL，L131–139）+ Index `detailSheet()`（OVERLAY 半模态，L2587–2596） | AppShell 三栏右栏（COLUMN） | 三种 presentation 内聚；v2 后只剩手机链两个挂载点。T020 对照 DetailsPanel.kt 修正右抽屉内容 |
| `WorkspaceBrowser.ets` | DrawerNav（左抽屉会话列表）、TabContentView（工作区页签）、RemoteShellFacade.browser | AppShell 侧栏 PANEL 呈现、SidebarShell | 会话/工作区浏览核心，多挂载点共用同一 facade |
| `HubBanner.ets` | RemoteShell 断连横幅、WorkspaceBrowser 内嵌 | （经 WorkspaceBrowser 间接双链） | T011 要在 WebShell 外层复用 |
| `FolderPicker.ets` | Index 根 bindSheet 门户（工作区选目录；browserFacade `openFolderPicker` L4728/4817） | 同一门户（形态无关） | 手机链创建工作区依赖 |
| `ChoiceSheet.ets` | Index 根门户（权限单选浮层） | 同一门户 | ConversationPane 权限 chip 入口 |
| `CredentialSheet.ets` | Index 根门户（凭据编辑） | 同一门户 | SettingsModels 凭据入口 |
| `SettingTextSheet.ets` | Index 根门户（文本/数字设置编辑） | 同一门户 | SettingsGeneral 等入口 |
| `SettingStructSheet.ets` | Index 根门户（结构化设置整值编辑） | 同一门户 | Settings* 复杂项入口 |

> 严格意义的「双壳共用」是前 4 个（MainShell/RightbarShell/WorkspaceBrowser/HubBanner——直接被 AppShell 子树或 Index PC 装配消费）；后 5 个是 Index 根门户件（v1 即形态无关）。v2 删除 AppShell 后这 9 个全部转为纯手机链服务。

---

## 5. 手机链保留（其余 43 个）

ConversationPane、TurnView、MessageRow、MarkdownRenderer、MessageFeedback、MessageImages、ReasoningRow、Composer、ConversationHeader、ToolCard、DeliverableCard、SubagentCard、ProducedFilesRow、CommandRow、RetryRow、QuestionGroupCard、PendingPane、DrawerNav、LatticeDock、CommandList、ConnectPane、DiagnosticsPane、GoalBar、SessionModelPicker、NativePrimitives、SettingsPane、SettingsGeneral、SettingsDevice、SettingsModels、SettingsPlugins、SettingsPresets、SettingsSkills、SettingsCore、SettingRow、CorePane、TabContentView、WorkspacePane、FileTreePane、FilePreviewPane、DetailPane、TrajectoryInspector、TimelineOverview、RemoteShell。

全部经 §2 的手机链 import 闭环可达，**均为保留**；其中对照修正目标见 tasks.md T013–T024。

---

## 6. 关键归属裁定（任务点名的疑难组件）

| 组件 | 归属 | 实证依据 |
|---|---|---|
| **TrajectoryInspector** | **保留（US4 T022 将手机化）** | 双消费点：ConversationHeader（会话头轨迹视图切换）+ RightbarShell（PANEL_RIGHT_TRAJECTORY 面板分派）。两者均在手机链 ⇒ 当前就不是「仅 PC 链可达」；T022 对照 TrajectoryTab.kt 修正。**不得列入删除** |
| **TimelineOverview** | **保留（US4 T022 将手机化）** | 双消费点：ConversationHeader + RightbarShell（轨迹面板顶部统计）。同上；另被 check-feature-wiring REQUIRED_IN_FILE 锚定（L382–385，FlexWrap.Wrap 手机防裁切）——删除会直接打破门禁 |
| **GoalBar** | 保留 | MainShell 命令面板内 + Composer 内嵌，双消费点均在手机链 |
| **DetailPane** | 保留 | 仅 RightbarShell 分派（PANEL_RIGHT_DETAIL）；RightbarShell 是手机链右抽屉本体。plan.md「[删除候选]」标注**不成立** |
| **PendingPane** | 保留 | ConversationPane（会话内审批）+ WorkspaceBrowser，双消费点均手机链 |
| **DiagnosticsPane** | 保留 | MainShell `StackPage.DIAGNOSTICS` 分派；手机链入口 = HubBanner `onOpenDiagnostics` |
| **WorkspacePane** | 保留 | TabContentView 工作区页签（手机链经 MainShell 兜底可达） |
| **TabContentView** | 保留 | MainShell 兜底分支（E343）；check-feature-wiring「主区兜底」锚点（L208 `TabContentView\(\{ f: this\.f\.tabFacade` ≥1）钉住它 |
| **CorePane** | 保留 | SettingsCore 分派（设置页「核心」分区），设置页在手机链 |
| **FileTreePane / FilePreviewPane** | 保留 | 双路径：WorkspacePane（工作区→文件树→预览下钻）+ RightbarShell（PANEL_RIGHT_FILES / PANEL_RIGHT_PREVIEW）。均在手机链 |
| **FolderPicker** | 保留 | Index 根门户 + browserFacade `openFolderPicker`（手机链建工作区） |
| **ShortcutKeys** | **条件删除（D5）** | 见 §3.2 |
| **SessionSearch** | **保留（文件尚不存在，T023 需新建）** | 见 §8 意外发现② |

---

## 7. Index.ets 装配清理点汇总（T025/T026 执行参考）

| 清理点 | 位置 | 批次 |
|---|---|---|
| AppShell 值/类型 import | L54–55 | 第一批 |
| build() else 分支 `AppShell({ f: ... })` | L2703 | 第一批（T005 路由改造时已先行移除分支，此为兜底核查） |
| `buildShellFacade()`（AppShellFacade 构造） | L2599–2646 | 第一批 |
| 侧栏装配状态：`sidebarStored`、`sidebarExpandedForMode`、`toggleSidebarExpanded`、`selectSidebarPanel`、`sidebarTrackWidthOf` 消费 | L299 等 | 第一批 |
| 拖拽几何：`detailWidthDesired`、`dragStartWidth`、`beginDetailDrag/endDetailDrag/updateDetailDrag`、`clampDetailDesired/dragDetailWidth`、`gripHitWidth` | L288/302 等 | 第一批 |
| `detailOpen` / `detailPresentationNow` / `sidePanelWidthVp` 等 AppShell 门面专用字段 | L213 等 | 第一批（`detailOverlayOpen` 与 `detailSheet` **保留**——手机链 ConversationPane `onOpenDetail` 依赖） |
| `MainShell` 死值导入（Index 从不直接渲染 `MainShell({...})`，只用类型） | L53 | 第二批 |
| ShortcutKeys import + 根 `.keyboardShortcut`×8 + `onKeyEvent` + `runShortcut/dispatchKeyHit` | L66–67、L2740–2775 | 第二批（条件成立时） |
| appstate 联动：`LayoutController.dragDetailWidth`、`ui/Shortcuts.ets` 快捷键表、`TrackPresentation`/`ShellTracks` 中侧栏轨道判定、`HarmonyTheme` 中仅 PC 链消费 token | appstate 模块 | T027（token 与基线收敛） |

> 每批删除后：hvigor 构建 + `check-dead-code.mjs`（残余死引用由其规则①③④点名）+ 全门禁套件。**禁止盲删**（tasks.md Notes）。

## 8. 门禁脚本锚点同步清单（T028）

| 脚本 | 锚点 | 处置 |
|---|---|---|
| `tools/check-feature-wiring.mjs` L349–353 | FORBIDDEN「侧栏呈现判定不得被硬编码」`files: ['.../AppShell.ets']` | **必须移除**（文件消失即报错）；守护的缺陷场景随组件消亡 |
| `tools/check-feature-wiring.mjs` L204–208 | FEATURES「主区兜底」`TabContentView\(\{ f: this\.f\.tabFacade` ≥1、`tabFacade` ≥2（MainShell.ets 内） | 不动（组件保留） |
| `tools/check-feature-wiring.mjs` L368–386 | REQUIRED_IN_FILE：Composer / ConversationHeader / TimelineOverview 的 `FlexWrap.Wrap` | 不动（组件保留） |
| `tools/check-builder-recursion.mjs` L9–12/39/193/271 | MainShell/TabContentView/WorkspacePane（注释与样例） | 不动（组件保留；样例为自检注入文本） |
| `tools/check-dead-code.mjs` | 死码判定门禁（规则①③④⑤） | 删除安全网：删除后跑它找 Index 残余死引用；AppShellFacade 字段零读者会被点名 |
| `tools/check-parity.mjs` / `check-design-tokens.mjs` / `design-token-baseline.json` | 无 PC 组件路径级锚点（grep 实证零命中） | baseline 裸值计数随删除只降不升（T027 棘轮收紧） |

## 9. 与 plan.md 的偏差（实证修正）

plan.md「Project Structure」中以下标注**与 import 实证不符**，本清单为终裁（R&D-004 授权「以可达性为终裁而非直觉」）：

| plan.md 标注 | 实证结论 |
|---|---|
| `MainShell.ets [删除] PC 主壳` | **保留**——RemoteShell L87 直接渲染（compact），是手机链主区分派器 |
| `RightbarShell.ets [删除] PC 右栏壳` | **保留**——RemoteShell 右抽屉 + Index detailSheet 两个手机链挂载点 |
| `SidebarShell.ets [删除]` | 维持删除 ✓（仅 AppShell 消费） |
| `TabContentView`（T026 候选） | **保留**——MainShell 兜底分支 + feature-wiring 锚点 |
| `DetailPane/PendingPane/DiagnosticsPane/WorkspacePane/CorePane`（T026 候选） | **全部保留**——均手机链可达（见 §6） |
| `TimelineOverview`（R&D-004 候选） | **保留**——手机链双消费点 + T022 手机化目标 |

## 10. 意外发现

1. **v1 手机本机模式走的是 AppShell**（`runMode===REMOTE && mode===SINGLE` 才渲染 RemoteShell）——即 v1 的「手机链」只覆盖远程模式；v2 把本机手机也切到 RemoteShell 后，AppShell 才真正全退役。T018 对照 MainScreen.kt 修正 RemoteShell 时须补齐本机模式差异（v1 RemoteShell 从未服务过本机模式）。
2. **`SessionSearch.ets` 文件不存在**——tasks.md T023 把它列为对照复刻目标，但 v1 从未交付该组件（grep 实证：全仓仅消费 appstate 的 `SessionSearchRow` 类型，搜索结果行由 ConversationPane L979 与 WorkspaceBrowser L106 内联 ForEach 渲染）。T023 需**新建**该组件（对照 SessionSearch.kt），并决定是否把两处内联渲染收编进去。
3. **Index L53 `import { MainShell }` 为死值导入**（仅类型被使用）；check-dead-code 规则①本应点名，删除批次顺带清理。
4. **无循环引用**：56+1 个 view 组件的 import 图为 DAG；唯一历史自递归（MainShell mainContent 兜底，E343 真机栈溢出）已修复并有 `check-builder-recursion.mjs` 门禁看守。
5. **快捷键双触发风险**（D5 依据）：v2 Web 直载后若保留根级 `.keyboardShortcut`，Ctrl+N 会同时触发原生 `SessionHub.createSession()` 与官方 Web UI 的新建会话——必须二选一（建议原生侧全删，官方 UI 自带）。

## 11. 删除分批建议（对齐 T025/T026）

- **第一批（T025，shell 类，4 个文件）**：`AppShell.ets`、`MainHeaderShell.ets`、`SidebarShell.ets`、`TrackResizer.ets` + Index.ets 对应装配清理（§7 第一批行）+ feature-wiring AppShell FORBIDDEN 锚点移除。一批全删的原因：四者构成一条封闭子树（后三者仅被 AppShell 消费），拆开删没有任何中间态收益。删后构建 + check-dead-code 验证零死引用。
- **第二批（T026，装配层，1 个文件 + 残余）**：`ShortcutKeys.ets`（条件成立时）+ Index 残余死引用（§7 第二批行：MainShell 死值导入、runShortcut/dispatchKeyHit、AppShell 门面遗留字段被 check-dead-code 点名的部分）。
- **随后 T027**：appstate 侧联动清理（`LayoutController.dragDetailWidth`、`Shortcuts.ets` 快捷键表、HarmonyTheme 仅 PC 链 token）+ design-token baseline 棘轮收紧。
- **随后 T028**：门禁锚点终验（§8 清单）。

---

## 12. 统计

| 口径 | 数量 |
|---|---|
| view 组件总数 | 57（view/ 50 + view/shell/ 7） |
| **删除候选** | **5**（无条件 4：AppShell/MainHeaderShell/SidebarShell/TrackResizer；条件 1：ShortcutKeys） |
| 共用保留（双壳/根门户） | 9（MainShell/RightbarShell/WorkspaceBrowser/HubBanner + 5 Sheets·Picker） |
| 手机链保留 | 43（含 TrajectoryInspector/TimelineOverview 两个 T022 手机化目标） |
| 待新建（非删除对象） | 1（SessionSearch.ets，T023） |
