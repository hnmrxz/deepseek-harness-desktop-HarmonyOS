<div align="center">

<img src="docs/brand/hdsh-icon.png" alt="HDSH" width="112" />

# HDSH

**在 HarmonyOS 上自足运行 DeepSeek Harness 的应用**

</div>

HDSH 把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）的**运行本体**装进一个鸿蒙应用：HAP 内自带 Node 运行时与 dsh 核心树，核心在本机 `127.0.0.1` 上起 Host，应用内的原生 ArkUI 页面就是这个本地 Host 的客户端。

**它不是 PC 上 dsh 的遥控器**，也不需要在电脑上常驻任何服务：装上即用，数据只在本机应用沙箱内。

支持 HarmonyOS 手机 / 折叠屏 / 平板 / 2in1。

---

## 能力

| 领域 | 说明 |
|---|---|
| **本地核心** | 内置 Node 运行时（自建、`jitless`）与 dsh 核心树；Host 仅监听 `127.0.0.1`，随应用生命周期起停 |
| **对话与轨迹** | 对话视图（问答，思考过程折叠在回答上方）与轨迹视图（工具调用、子代理、目标/任务、交付物、错误）分开呈现 |
| **工作区** | 工作区为组、会话挂在组下；可在设备上选择文件夹作为工作区（系统文件夹选择器），并在其中浏览文件 |
| **模型与密钥** | 按提供方管理：API 密钥（只写）、`baseURL` 与模型目录；默认模型与推理强度可选 |
| **插件** | 查看随包插件清单与运行阶段；按行启用/禁用，并可恢复部署默认 |
| **核心版本** | 同时安装多个核心版本，一键**切换 / 回滚**（停旧起新，逐版本校验后激活） |
| **多语言** | 界面文案跟随系统语言，默认中文 |
| **上架友好** | 不申请 JIT 等特殊权限，全部按 `jitless` 运行；权限仅网络相关三项 |

## 架构

```text
┌─ HDSH（一个 HAP）──────────────────────────────────────────────┐
│  ArkUI 原生页面（客户端）                                       │
│        │  HTTP /api/*        WebSocket /api/remote.mux          │
│        ▼                                                        │
│  端侧 dsh Host（Node 运行时运行在**本应用进程内**）              │
│        │  DSH_HOME = <应用沙箱>/dsh/home（跨版本共享的唯一数据）  │
│        ▼                                                        │
│  核心版本仓库（多个版本可并存，切换 = 停旧 + 起新 + 校验）        │
└─────────────────────────────────────────────────────────────────┘
```

同进程带来的是**安全语义的简化**：客户端与 Host 走回环，不需要把服务暴露到局域网，也不需要跨设备转发。

### 端侧运行时的硬约束：`jitless` ⇒ 没有 WASM

不申请 JIT 权限意味着 Host 全程以 `--jitless` 运行，而 V8 的 `--jitless` 与 `--expose_wasm` **互斥**
（启动即打印 `disabling flag --expose_wasm`），因此端侧 `typeof WebAssembly === 'undefined'`——这是恒定的，
不是配置问题。由此推出一条对上游代码的判据：

> **凡是上游直接 `import('undici')` 的功能，在端侧都会失败**，因为 undici 的 HTTP 解析器是 WASM
> （`lib/llhttp/llhttp-wasm.js`）。

已实测证实的一个实例：`dsh-web-fetch-http` 不用全局 `fetch`，而是 `await import('undici')` 自建 `Agent`
再传 `dispatcher`，于是 `web_fetch` 打不开任何网页和 IP，而走本仓纯 JS `node:http` 垫片的 `web_search` 照常工作。
同一核心树、同一个本地 HTTP 服务下，只有 `--jitless` 一个变量就能复现两组结果（有 WASM → 200；
无 WASM → `fetch failed / WebAssembly is not defined`）。细节与在飞修复见 `docs/parity-matrix.md` §3.2。

因此新增/升级核心版本时，除了跑既有门禁，还要**搜一遍核心树里对 `undici` 的直接依赖**，并把垫片覆盖率当作一项验收项。

对付它需要**两层**，缺一层就会出现"Host 起来了、模型也能回话，但某个工具静默坏掉"：

| 层 | 做什么 | 不做的后果 |
|---|---|---|
| 全局 fetch 垫片（`fetch-shim.js`） | 用 `node:http/https`（原生 llhttp）重写 `fetch/Request/Response/Headers/FormData` | 调模型就走不通（dsh 调模型就是用 fetch） |
| `undici` **模块名**解析钩子（`undici-shim.mjs` + `undici-loader.mjs`） | 让上游的 `await import("undici")` 拿到同一个垫片，并把 `dispatcher` 翻译成 `lookup` | **`web_fetch` 打不开任何网页**（`web_search` 却正常，因为后者走第一层） |

第二层由 `main.js` 的 `installUndiciNameHook()` 在 `WebAssembly` 不可用时注册；**不改上游源码、不改核心树**。
这条路径由 `tools/check-web-fetch-jitless.mjs` 守着——它自带对照实验：不注册钩子时必须失败（并给出
WASM 因果证据），注册后必须全过，且**跨源跳转仍须被拒**。

## 构建

前置：DevEco Command Line Tools（含 hvigor / ohpm / codelinter / SDK）、JDK 17、Node.js
（仅用于仓库内的构建与检查脚本）。

> **SDK 版本口径**：`compatibleSdkVersion` / `targetSdkVersion` 固定为 **`6.1.1(24)`**（决策，2026-09-14）。
> 代价是**不能用 API 26 的「沉浸光感」材质**（官方要求 `targetAPIVersion ≥ 26`）——
> 界面层次当前由系统阴影表达；升级路径与要改的几处列在 `appstate/ui/HarmonyTheme.ets` 的 `HarmonyMaterial`。

**不入库的产物（新克隆必须先备齐，否则编不过）**：

| 产物 | 路径 | 说明 |
|---|---|---|
| Node 头文件 | `entry/src/main/cpp/node-headers/` | 编 `libdshhost` 只需要它（`libnode` **不参与链接**） |
| 原生库 | `entry/libs/<abi>/` | 运行期需要（含 `libnode.so.127`）；也是"编不编 koffi/flock"的门 |
| 核心包 | `entry/src/main/resources/resfile/*.zip` | 首启解包出端侧核心树 |
| 入口脚本 | `entry/src/main/resources/resfile/resources/app/` | 由 `node tools/place-host-app.mjs` 从 `hostcore/app/` 生成 |

```bash
# 1) 打完整体（HAP + 原生库 + 内置核心资源）
devecocli build

# 2) 需要重新打包核心树时（素材来自 dist/core/，产物落到应用资源目录）
node tools/pack-core.mjs --skip-install --place-in-app
node tools/place-host-app.mjs

# 3) 安装到已连接设备（注意：产物是 **unsigned**；签名材料不在库内）
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

## 设计体系（P1.5：Web 语义 + HarmonyOS 原生表达）

**产品语义对齐官方 Web，视觉与交互用 HarmonyOS 原生表达**——不是把 Web 的 CSS 机械翻译成 ArkUI：

| 层 | 落点 | 作用 |
|---|---|---|
| 尺度原语 | `appstate/ui/Tokens.ets` | `Sp` / `Radius` / `Border` / `Fs` / `Sz` / `Dur`（"有哪些档位"） |
| 语义令牌 | `appstate/ui/HarmonyTheme.ets` | 角色 → 系统语义资源（`sys.color.*`）+ 排版成套角色 + 层级/动效/触控；**`WEB_TOKEN_MAP`** 逐条映射官方 `--dsw-*` |
| 原生原语 | `entry/src/main/ets/view/NativePrimitives.ets` | `NativeChip` / `NativeCard` / `NativeButton` / `NativeActionBar` / `NativeSectionTitle` + Sheet 参数助手 |

**四条已经定下来的规则**（都是踩过或查证后写的，不是偏好）：

1. **浮层用系统形态**：半模态一律 `bindSheet`（`NativePrimitives.harmonySheetOptions` 统一参数），
   不再手写"整屏 Column + 自制遮罩"。原因：原生 Sheet 自带"非全屏、底层父视图可见"、拖拽关闭、
   遮罩与键盘避让——手写那套要逐个补回来，且必然补不全。
   > 注意 `bindSheet` 是**组件属性**，同一节点只能绑一个。本项目因此用**单一浮层宿主**：
   > 全应用只在根节点挂一次 `bindSheet`，由 `sheetKind()`（**从既有状态派生**，不另立字段）
   > 决定显示哪个浮层、`closeSheet()` 一处复位。这样结构上**不可能同时开出两个浮层**，
   > 复位逻辑也只写一次。
2. **遮罩交给系统**：不再手写 `rgba(...)` 遮罩（35% 黑在深色主题下观感就是错的），全部由原生 Sheet 提供。
3. **图标用系统符号**：`SymbolGlyph` 只支持系统预置资源，**不引入 Web SVG**（这条是 API 约束，不是偏好）。
4. **裸值只许变少**：`tools/check-design-tokens.mjs` 是棘轮门禁，管的是
   `fontSize`/圆角/描边/颜色字面量（含 `rgb()/rgba()/hsl()`——首版漏检过，已补）。

## 仓库结构

| 目录 | 作用 |
|---|---|
| `entry/` | 鸿蒙应用入口：ArkUI 页面与视图（含**原生原语** `view/NativePrimitives.ets`）、原生桥（`libdshhost`）、随包资源（核心包与原生库） |
| `hostcore/` | 端侧 Host 的入口脚本与 profile（`cordis.patch.yml`）、`fetch` 垫片，以及为绕开"端侧无 WASM"而做的 `undici` 模块名解析钩子（后者已接线并端到端验证，见矩阵 §3.2） |
| `hostruntime/` | 核心版本仓库、激活事务、运行时载体（`RuntimePort` → `NodeRuntime`） |
| `appstate/` | 客户端状态中枢与投影（会话、轨迹、工作区、设置、凭据、插件、核心视图）；**设计令牌与布局/导航决策**（`ui/Tokens`、`ui/HarmonyTheme`、`ui/Breakpoints`、`ui/LayoutController`、`ui/NavigationController`；**回合模型** `model/Turns`、**贴底跟随模型** `model/Follow`、**输入模态策略** `model/InputPolicy`（长按/右键/悬停的差异收敛成策略）、**输入模态事实** `model/InputFacts`（设备枚举 / 事件证据 / 形态猜测三者的优先级）、**轨迹时间线** `model/Timeline`（官方七种类标签 / 累计比例 / 拖动聚焦 / 会话统计四项）——纯逻辑，可在本机直接测，
**工具呈现** `model/ToolPresentation`（按工具类别判定图标/语气/展开态）、**改动对照** `model/ToolDiff`（编辑类工具出"改了什么"，规则逐条对齐官方渲染器）、`tools/check-layout-fixtures.mjs` 对它们共 440 条断言） |
| `platform/` | 系统能力封装（文件选择、剪贴板、通知、窗口记忆等） |
| `dshcompat/` | 与上游协议有关的**全部**事实：端点、参数形状、事件类型与投影键 |
| `tools/` | 构建与检查脚本（核心打包、依赖闭包、上架红线、协议往返、死按钮扫描等） |
| `docs/` | 文档基线，索引见 [`docs/README.md`](docs/README.md) |

## 当前阶段：官方信息架构对齐

本阶段（2026-09-14 重定义）**不再"缺一个功能就加一个组件"**，而是先把页面框架搭正确：
`AppFrame → Sidebar → Main → Rightbar → Settings 域`，四形态共享同一套信息架构（只有几何/输入/面板呈现不同）。
分步计划与验收见 `docs/ia-parity-plan.md`；判断依据与现状对照见 `docs/parity-matrix.md` §5.1。

**进度**：纯逻辑层（`PanelRegistry` / `NavigationState` / `ShellTracks`，46 条断言）、**侧栏外壳**
（`view/shell/SidebarShell.ets`：品牌行 / 面板清单 / 徽标 / 三种呈现）、**右栏外壳**
（`view/shell/RightbarShell.ets`：面板本体 / 三种呈现）、**主区页头**（`view/shell/MainHeaderShell.ets`）与**轨间把手**（`view/shell/TrackResizer.ets`）已完成
—— AppFrame 的 chrome 已各有其主；命令面板已拆成 `GoalBar` / `SessionModelPicker` / `CommandList` 三块，连接横幅拆出 `HubBanner`
（呈现归组件、副作用归宿主）；
`@Provide/@Consume` 机制已在侧栏上真实验证（侧栏按面板注册表过滤入口）；
**主区内容已搬出**：`view/TabContentView.ets`（459 行）+ `view/shell/MainShell.ets`（409 行），
且 **`Index` 不再负责页面级 Pane 选择**（P0 验收达成）；
**AppFrame 三形态轨道已搬出**（`view/shell/AppShell.ets`：单栏/双栏/三栏的轨道拼装 + 页头 + 三种侧栏 surface + 右栏 surface + 把手，
25 个门面成员）⇒ **`Index.ets` 5040 → 4290 行**，页面根只剩「浮层门户 + 全局输入证据 + 快捷键」；
顺带修掉一个真实缺陷：浮层门户原先挂在单栏布局的根节点上 ⇒ **双栏/三栏下模型选择、凭据、目录、整值编辑浮层够不着**，
现在门户挂在页面根、与形态无关（官方 Web 的 portal 语义）；
**页面选择已收成唯一真值**（`NavigationState.selectedMainPanel`，`NavTab` 退化为迁移期别名），
"此刻显示哪个面板"的组合逻辑也已收进纯模型（`activeMainPanelOf`）；
**P0 到此完成**，**P1（Sidebar）已推进三步**：① 工作区→会话那棵树抽成 `view/WorkspaceBrowser.ets`
（可挂主区、也可挂侧栏；`TabContentView` 595 → 341 行），并删掉一个**长期没人渲染的死 Pane**
（`SessionListPane`，221 行）——顺带把设计令牌棘轮调紧（53 → 40 处）；② 为 240vp 侧栏做**窄版行**
（名字一行、动作一行；动作**不收进菜单**——菜单在真机打不开就等于功能不可达，见 `docs/50` E301）；
③ 树挂进侧栏 PANEL 轨道（品牌行下方，官方顺序），**三栏下主区不再重复一份**（判据取自 `ShellTracks`，
与轨道选择同源）。
④ 侧栏入口改由**面板注册表**驱动（P1-4）：入口的存在/顺序归 `sidebarEntries` / `sidebarPinnedEntries`
（"沉底"是清单属性）、图标与文案归按面板 id 的编译期映射、高亮归宿主 —— `SidebarShell` 里**再无 `NavTab`**，
一级导航不再是"三个页签"；`NewSession` 成为品牌行下方的一级入口，Settings 沉底，核心席位按 E110 标为不可用。
⑤ 单栏（手机）侧栏改成**抽屉**（P1-5）：页头根页给导航入口、抽屉叠在整页之上（点外部收起）、
返回键**第一优先级**收抽屉（`BackAction.CLOSE_DRAWER`）、从抽屉里选入口或会话都自动收起
（`navigateToMain` / `enterSession`）——顺带接上两条此前"有通道没消费点"的模型状态。
底部标签栏**暂时保留**（过渡，见 `docs/50` E306）。
**P2（Main / 会话）已开工**：会话正文的 **Markdown** 已落地（P2-1）——
解析是纯模型 `appstate/model/Markdown`（**31 条 fixture 断言**：围栏含未闭合、未配对标记原样保留），
渲染是 `entry/view/MarkdownRenderer.ets`（`Text > Span` 行内富文本），
正文/思考/过程三处已从 `Text(item.body)` 原文照显换成渲染；链接走真实系统能力 `openLink`
（`platform/system/OpenLink.ets`，只放行 http/https），无障碍文案改为去标记文本。
**P2-2 已落地**：会话头的**后台任务条** —— `Jobs` 模型 40 条断言与中枢 `jobs` 字段一直都在，
但视图零消费者（又一次"通道有、没接"）；现已接成 中枢 → `Index` → `MainShell` → 会话头任务条
（live 任务每秒走字、无障碍整段取自模型），并把这条接线登记进功能接线门禁（第 16 条）。
**P0 回归修复（E343）**：真机（Mate 70 Pro+）冷启后点一下界面即被系统杀进程——
`RangeError: Stack overflow!`，栈里成对出现 `MainShell.ets:405` 与 `:404`。根因是主区分派的**兜底分支写成了自递归**
（`else { this.mainContent(this.compact) }`）：`MainShell` 只分派「诊断 / 连接 / 会话」，剩下工作区 / 核心 / 设置
三类面板本应由**主区第二束** `TabContentView` 渲染，搬迁时这一束忘了接上；而 `MainShellFacade.tabFacade`
一直由宿主造着却**零消费者**（第 7 例"通道有、没消费者"）——正是它掩盖了这个空洞。
修复 = 兜底渲染 `TabContentView({ f: this.f.tabFacade, compact: this.compact })`。**并补一道门禁**
`tools/check-builder-recursion.mjs`：`@Builder` 体内不许出现自己的名字（剥注释后判定，5 条注入式自检，
且**对修前的提交归真命中**——门禁必须先在已知坏版本上红过一次才算证明）；功能接线门禁同步新增「主区兜底」项（16 → 17）。
⚠️ 该项**真机复验仍待做**：无真机时不得宣称设备验收完成。
**顺带清掉搬迁的尾巴（E345）**：查这件事时又查出 `Index.ets` 里**三个零调用的 `@Builder`**
（`hubBanner` / `coreTabContent` / `tabContent`——内容都已在 AppShell 与两束组件里，只剩宿主这份壳；
`@Entry` 组件不会渲染它们）与**全仓 22 个零使用 import**（`Index` 12 个、`MainShell` 9 个、其余 6 文件各 1 个）。
`Index.ets` 4460 → **4384 行**，全仓零使用 import 归零。
**排队项的良性竞态被当成"失败"（P7-16）**。同一条审计路径，这次轮到待发队列。上游有两个码，触发条件都能在源码里读到（`dsh-api-session-controller`）：`session/queue-item-not-found`（"queued item is no longer pending"——这一行已被 Agent 取走或已被删掉）与 `session/steer-unavailable`（"current turn no longer accepts steering"——轮次刚好结束）。官方客户端的注释写明这两种情况应当**静默收敛**：`"A turn closing mid-way (steer-unavailable) or a row already claimed by the agent (queue-item-not-found) converges silently, while a genuine failure surfaces as one composer notice."` 同一段还解释了为什么必须这样——重复触发**本来就依赖**这个收敛（界面快照可能还列着一行 Host 已经插话过的消息）。而我们把**任何**失败都写成红色横幅「修改待发队列失败：…」⇒ **连点两下「插话」**第二下必然撞第一个码、**轮次刚结束去点「插话」**必然撞第二个码（而用户正是看到轮次停了才去点的），屏幕上就出现"失败"——真相是"无事可做"，用户却会去重试、去怀疑网络。现在两个码在 `dshcompat` 里成为**具名常量**（附触发条件与出处），判定与文案在零依赖 `appstate/src/main/ets/model/QueueRace.ets`；命中即记一行旁路日志（**静默 ≠ 不留痕**）→ 返回"已收敛"→ **不设红色横幅**，其余任何码照旧报错（fixture 反向钉住 `session/attachment-invalid`、`gateway/arguments-invalid`、空码、大小写变体都不算良性）。fixture **828 → 840 条**；接线门禁 27 → **28 项**；真机判据新增 **D35**（顺带记一笔被门禁挡回的弯路：两个码第一版写进了 appstate，`arch-check` 判红——上游字面量只许住 `dshcompat`）。
**发送失败后草稿凭空消失（P7-15）**。继续按"拿现有功能去对官方源码"核对，这次轮到提交路径。官方的语义写在 `dsh-client-ui-conversation` 的 `sink()` 注释里：**乐观清空 + 乐观发送**，失败时走普通错误横幅，而且**"draft restored only while untouched"** —— 只有在用户还没动过输入框时才把原文还回去。我们此前是"清了就不管"：`Index.sendDraft()` 第一件事就是 `this.draft = ''`，之后不看结果 ⇒ 发送失败（宿主拒绝、参数不符、连接刚断）时用户的长消息**凭空消失**，只能重敲一遍，而失败原因往往只是"某次参数被拒"，改一改就能发。现在按官方语义补上恢复，并把规则做成零依赖纯模型 `appstate/src/main/ets/model/ComposerSend.ets` 的 `shouldRestoreDraft(sendOk, queued, currentDraft, submitted)`：成功不还、**已进待发队列不还**、输入框非空（哪怕只剩空格）不还、原文为空不还。**"离线已排队不还"是必须单独判的一条**：离线时中枢会把消息放进待发队列并返回 false，若照搬"失败就还回去"，就变成"既排队又留在输入框"，用户再按一次发送同一句话会**发两遍**——为此中枢新增 `HubSnapshot.lastSendQueued` 明确告知（让视图去解析 `lastError` 文案来猜是脆弱的）。顺带：连 Host 都没配时不再"清空后什么都不做"，而是**不发送就把草稿还回去**。fixture **822 → 828 条**；接线门禁 26 → **27 项**；真机判据新增 **D34**。
**`@`/`/` 插入：追加改替换（P7-14）**。继续按"拿现有功能去对官方源码"的做法核对输入区，撞上的是输入触发管线。官方的语义是**替换当前 token**（`dsh-client-ui-reference` 的 `onPick` 返回 `{insert:{ref:<mention>}}`，由 `dsh-client-ui-input-trigger` 消费；`dsh-client-ui-commands` 里的消费动作写得很清楚：`slash/input-consume-token` 带 `{kind:'span', span}`），而我们两处候选点击都是 `this.draft + insert + ' '`：用户敲 `@src/fo` 再点候选，输入框里得到 **`@src/fo@src/foo.ts `** —— 半截查询词留在正文里，**而且它长得像一条引用**，Host 会去解析一个不存在的 `@src/fo`（提示词就这么带上了错误引用，而用户以为只是点了候选）。现在把词法搬进零依赖纯模型 `appstate/src/main/ets/model/InputTrigger.ets`：`detectTrigger`（命令：行首 `/` 且尚无空白；引用：行内最后一个 `@` 且其后无空白；`\@` 转义不算）、`applyPick`（**替换** token 区间、保留前后正文）、`appendPick`（先点按钮再选候选的兜底）、`needsTrailingSpace`（对齐官方 `formatFileMention`：**目录引用写 `@"dir/`，引号故意不闭合**，好让补全继续往下钻 ⇒ 这种插入**不补尾随空格**，补了下次补全就接不上）。顺带更正一行状态注水：矩阵的 `input-trigger` 早标 DONE，而"选中即替换"一直没做对 —— 状态行不变（功能现在确实做完），缺陷与修法记进变更记录 v1.45。fixture **799 → 822 条**；接线门禁 25 → **26 项**；真机判据新增 **D33**。
**斜杠命令：修掉"界面无反应"与"假成功"（P7-13）**。核对命令执行时发现两个用户能直接撞上的问题。① **界面无反应**：上游把命令的生命周期写成两帧（`command/run{commandId,name,args?}` → `command/done{commandId,kind,text?}`，**靠 `commandId` 配对**），并在对话里渲染成一个**持久过程节点**；而我们把 `command/done` 标成 `standalone:false`（这一帧被**直接丢弃**）、把 `command/run` 留在"内部事件"里（不显示）⇒ 用户执行一条命令后，界面上**什么也不会发生**。② **假成功**：`executeCommand` 只看 `result.ok`、**从不读回执里的 `result`** ⇒ "命令没解析出来 / 处理器报错"两种情况**全部显示「已执行」**。现在：命令有自己的族（`EventFamily.COMMAND`）与自己的条目类型（`TrajectoryKind.COMMAND`），两帧按 `commandId` 落成**一条**命令卡（`view/CommandRow.ets`：命令原文 + **进行中/已完成/失败** 三态徽标 + 结局文本，失败时把宿主原文直接显示）；`executeCommand` 读 `result.kind`：**受理=成功**（官方判定：生命周期已入日志、结局作为过程节点呈现）、`error`=「命令被拒绝：<宿主原文>」、`value===undefined`=「宿主不认识这条命令」（官方 `unknown or malformed command` 语义，并**保留输入**让用户改）。**真 Host 取证**：核心闭环新增 M2g，真跑一条**只读**命令（白名单外就 SKIP，不拿会话冒险），本机执行 `/feedback`（缺参数）⇒ 回执 **`command.rejected`** + 宿主原话 `Feedback text is required. Usage: /feedback <text>`，轨迹里出现 **1 条已兑现的命令条目（`kind=error`）** —— 旧代码在这里会显示「已执行」。**门禁抓到一个坑**：两帧可能乱序（`done` 先到、`run` 后到），我第一版合并规则"非空就取新值"会把已成功的命令改回"进行中"（界面上永远转圈），fixture 的"乱序合并"那条当场红；现在 `'running'` 不能覆盖已兑现的结局。**仍缺（已登记）**：三种命令 UI 类型尤其 `popupSelect`（宿主让客户端弹选项列表）未细分；命令节点在对话里的**位置精度**（官方是发生处的独立节点，我们走回合的 NOTICE 槽位——信息相同、位置粗一点）。fixture **788 → 799 条**；核心闭环 21/21 → **22/22**；接线门禁 24 → **25 项**；真机判据新增 **D32**。
**上架这一步也变成可核对的了：AGC 提审预检 + 可照抄的提交步骤（P7-12）**。`docs/70` 早就写清了权限最小化与 release 打包，但"提审要看的字段与资源"一直只是散文——而这些字段**错了不会构建失败**：`deviceTypes` 少写一个，那种设备**装不上**（上架后才发现，还看起来像"不兼容"）；`abilities[].skills` 少了桌面入口，装上了但**桌面没有图标**；`$string:app_name` 指向空串，应用名就是空白；图标指向一个**存在却非法**的文件同样不报错。这一轮把第 10 道门禁（`tools/check-compliance.mjs`）扩成"权限对账 + **包元数据与资源预检**"两段（合在一道门禁里是因为这个项目的教训正是"少跑的那个等于不存在"）：bundleName 反向域名 / vendor 非空 / versionCode 正整数 / versionName `x.y.z` / `runtimeOS=HarmonyOS` / target 与 compatible SDK 都在 / buildModeSet 含 release / `type=entry` / **deviceTypes 含 phone·tablet·2in1** / `deliveryWithInstall` / 桌面入口 `entity.system.home` + `ohos.want.action.home` / ability 四个资源字段都是资源引用 / **每个资源引用都能解析**（AppScope 与 entry 两处）/ 应用名与 ability 名**非空** / 三个图标是**合法 PNG**（顺带打印尺寸：1024×1024、1024×1024、144×144）。**归真验证三处**：去掉 `tablet` ⇒ 红；`foreground.png` 换成文本 ⇒ 红；`app_name` 置空串 ⇒ 红；还原 ⇒ 绿。`docs/70` 同时补上 **§6.4 提交步骤（照抄即可）**：AGC 每个字段填什么（应用名/包名/分类/支持设备/版本/隐私政策/权限说明）、发布签名材料怎么来（AGC 生成 `.cer`/`.p7b` + DevEco 新建 release 配置 + **不要把密钥库提交进仓库**）、出包怎么确认（**已签名** + `可疑内容：无`）、以及商店材料谁提供（216×216 图标、三形态截图、描述、**审核说明里必须写清"怎么得到一个可连的 Host"**）。
**把那个桩换成真件：E384 修完（图片能力的前置）**。上一段查出"随包核心 zip 里的 `sharp.impl` 是 E79 的 602 字节桩"之后，这一轮把修法走完：`node tools/pack-core.mjs`（**不带** `--skip-install`）重新物化 ⇒ 新树里 `sharp.impl` 就是 `@ohos-ports/sharp@0.34.5-beta.12` 真件，`--check-sharp` 由红转绿；把真件落进**随包的那棵树**并 `--skip-install --place-in-app` 重打核心 zip（66.2 MB，解包逐字核对 `sharp.impl/package.json`）。**同时更正上一轮的一个错误判断**：当时说"手工替换不可行（`sharp.format()` 处就炸）"——那其实只是**开发机的平台名**是 `linux-arm64`，port 的解析落到 wasm32 回退；真机平台名是 `openharmony-arm64`，那条路本来是对的。**又一条实证**：本机**无法**端到端验证这条链——直接 require 那个 `.node` 得到 `/lib/aarch64-linux-gnu/libc.so: invalid ELF header`（它对着 **OHOS libc** 链接，glibc 上必然失败，补 `LD_LIBRARY_PATH`、建好 RPATH/soname 兼容软链都一样）⇒ 设备上能不能出图只能由 **D31** 判定。**还顺带修掉一个会误导的探针**：宿主 `runtimeFacts()` 原来**绕过调度器**直接 require 原生件，于是绕过了真件在 require 时建 soname/RPATH 兼容软链、设 `LD_LIBRARY_PATH` 的必要动作 ⇒ **设备上真件可用时它也会报失败**，而 D31 第 0 步正是看它。现在改成走调度器 + 三条同步判据（`hdshSharpLoadError` / 有没有 `versions` / require 时 `sharp.format()` 是否抛），本机读数因此从"原生绑定加载失败"变成诚实的 `Could not load the "sharp" module using the linux-arm64 runtime`。核心闭环 **21/21** 保持；10 道门禁全绿。
**"发一张图"撞出一个更重要的东西：随包的 sharp 是桩（P0-4 / E384）**。这一轮做的是输入区发图（官方 `serializeImages()` 的内联 `image` 片段）：系统图库选图（**不新增任何权限**）→ **内联**进消息（不走上传）→ 官方顺序（图片在前、正文在后）与官方四条类型白名单（png/jpeg/webp/gif）→ 图库 URI 不带扩展名时用**魔数**判定 → 附件条给**缩略图** → 离线时**明确拒绝**（图片没有可稍后补发的凭据）。代码写完、788 条 fixture 全绿，真 Host 却回了一句 `Unsupported or malformed image data.` —— 顺着这句查下去，发现比功能本身重要的事：**解包随应用分发的核心 zip，`node_modules/sharp.impl` 是 E79 留下的 602 字节桩**，而 Host 的图片接纳（`dsh-attachment-local`）正是用它 ⇒ **设备上一切图片处理必然失败**，还伪装成"你的图坏了"。它一路没被发现有三层原因：桩**import 时不抛**（于是打包日志写着"真件在 sharp.impl"、运行时事实也不报不可用）、真件**确实在包里**（所以"东西在不在"这类检查能过）、报错**指向用户**。**已知已做的三件事**：① 构建期闸门 `pack-core.mjs` 新增 `assertSharpImplIsReal()`（**幂等分支也要校验**——那正是漏掉的地方；判据是"真件该有的文件"，不按桩的报错文本判）＋只读 `node tools/pack-core.mjs --check-sharp`（对当前树**判红**，`--allow-sharp-stub` 才显式放行）；② 诊断报告新增「原生件」一行（`sharp` 的结论与原因——真机取证的唯一通道）；③ 核心闭环新增 M2f：走**应用自己的**入列与拼装通路把一张 1×1 真 PNG 打给真 Host，三种结局分开判（**接纳**=最强证据 / **解码器不可用**=SKIP 并写清原因 / 其余=缺陷）。**仍未修（已登记）**：核心需**重新物化**（`node tools/pack-core.mjs` 不带 `--skip-install`）才能把真件放到 `sharp.impl`；手工替换试过，本机在 `sharp.format()` 处就炸（会留下更难查的"半可用"树），故不做。fixture **755 → 788 条**；核心闭环 **21/21**（M2f 为 SKIP）；接线门禁 23 → **24 项**；真机判据新增 **D31**（第 0 步先看 Host 图片解码器）。
**文件变更流"自激"：一秒 367 次 RPC（E383，可用性与稳定性）**。这一轮本来是继续做功能，顺手读了一眼核心闭环的宿主日志，看到一个不该存在的模式：`files changes opened` / `POST /api/workspaceFiles/list` / `workspaceFiles/changes 结束` 三行在**同一秒内重复了三百多次**，而用户什么也没做。成因是一处闭环——变更帧的回调去重列，而重列又会**取消并重新订阅**变更流，于是"订阅 → Host 推一帧初次快照 → 重列并重订阅 → 又推一帧 → …"无限循环。它不报错、不崩、界面看着正常（只是"在转"），而且应用内 trace 有 300 行上限，**自激会把证据自己冲掉**，所以只有看**频率**而不是看单帧日志才发现得了。修法两层：① `ensureFilesStream(sessionId, force)` —— 订阅**只在作用域变化或用户/会话驱动时**建立，变更帧驱动的重列**不再重订阅**（哪怕流已正常结束）；② 变更帧按 300 ms **合并**再重列；③ 再加一道自激探测（一秒超 10 次即跳过并记账），让今后任何形态的自激都退化成"自动刷新停了（有日志）"，而不是又一次 RPC 风暴。`onEnd` 不重订阅、`onError` 才清作用域标记，这个区别是刻意的：否则一次网络抖动会让自动刷新**永久**停摆。**归真验证**：核心闭环新增第 20 步「workspaceFiles/list 调用次数有界」——`git stash` 掉修复回到修前版本 ⇒ 门禁报 **375 次（上限 8）❌**；还原 ⇒ **2 次 ✅**；闭环 **20/20**。顺带修掉上一轮引入的一句会误导人的文案（`session/attachment-invalid` 有**两种**用法：读历史图片、解析提示词里的文件回执，只写"图片附件"对文件那条路是错的）。真机判据新增 **D30**。
**消息图片：把正文里的字面 `[image]` 换成一张图（P0-3）**。会话事件里的图片块**只给一个不透明引用**（`attachment.attachmentId`）——既没有 URL 也没有字节，官方 web 同样要靠 `session/attachment`（`ISession.readAttachment`）把引用换成可显示的 URL。我们此前在投影层把它降级成正文里的字面 `[image]`，于是**真机上用户看到的就是这五个字符**（"有数据、没消费者"的又一例）。这一轮按官方 `dsh-client-ui-attachment` 的三个槽位补齐其中两个可做的：**消息内图片**与**轨迹图片**（两个视图共用同一个 `MessageRow`，因此是同一份呈现）。几何规则**逐条对齐官方**并搬进零依赖模型（`model/MessageImage.ets`）：一张图 → `singleFit` 大图（最大边 240、比例夹到 [0.25, 4]、**绝不放大小图**、超界比例保留"信息起点"那一侧），两张及以上 → **64×64 方图**、间距 10vp、按角色左右对齐，圆角 16。**门禁把方向错误钉死了**：第一版把 `scale` 写成"框 ÷ 图"（官方是"图 ÷ 框"），结果**大图变小图、小图变大图**、两个错互相掩护 —— 新增 fixture 里有两条正是为大图 240×240 与小图原样 100×50 准备的，当场红。读取路径只有三种状态且都由中枢给出（就绪 / 读取中 / **失败可点重试**），视图不持任何异步状态机；缓存按 `会话 id + 附件 id` 键（附件 id 内容寻址，但**授权是会话作用域**的），上限 24 张、断开连接即清空。**真 Host 取证**：`tools/check-core-loop.mjs` 新增一步，用一个不存在的附件 id 打真 Host ⇒ **`session/attachment-invalid`** ⇒ 端点**确实实现着**（"端点在兼容面上表里"终于不等于猜），这条 code 也据此写成了用户看得懂的一句话。**仍缺**：输入区**发送**图片（需要平台侧选图取字节）、官方点击开**灯箱**（我们是就地放大）、图片另存/分享（平台无保存能力）——三条都登记在 `docs/parity-matrix.md` 的 `attachment` 行。fixture **728 → 755 条**；核心闭环 18/18 → **19/19**；接线门禁 23 → **24 项**；真机判据新增 **D29**。
**应用内隐私与权限说明 + 上架合规对账门禁（P7-11）**。AppGallery 的材料分两半：**控制台里填的**与**应用里能看到的**。后者现在在应用里了 —— 设置 → 设备 → 「隐私与权限说明」（折叠块）：数据做法 6 条（不收集个人信息 / 数据只在本机沙箱 / 网络只连两处 / 不读设备标识 / 剪贴板只写不读 / 导出剔除敏感项，**每条都写能核实的做法**而不是口号）、申请的权限 2 项逐条给用途、以及版本与日期（AGC 那份文本以它为准）。更要紧的是**防漂移**：新增**第 10 道门禁** `tools/check-compliance.mjs` —— ① 权限清单**双向对账**（`module.json5` ↔ `PrivacyDisclosure`，多一项/少一项都红）；② **12 项刻意不申请的权限**（读剪贴板/位置/相机/麦克风/通讯录/媒体/Wi-Fi/跨设备…）一旦出现即红（要加就得先改那张表 = 一次有意识的产品决定）；③ 设置页必须真的渲染这两段（否则"应用里能看到"是空话）。**归真验证**：临时塞入 `READ_PASTEBOARD` ⇒ 当场两条红；还原 ⇒ 绿。fixture **719 → 728 条**；parity 新增端侧独有行 `hdsh-privacy-disclosure`（DONE）。
**计划待审面板（P7-10）—— 提问族的最后一块**。读源码后发现它不是另一个端点或命令，而是**同一个提问请求的另一种呈现**：官方 `planReviewOf` 在"整组只有一题 + `intent.kind=plan-review` + 带 `detail`（计划正文）+ 非多选 + 选项 ≤2 + `intent.approve` 指名的标签确实在选项里"时换成计划面板，六条少一条就**退回通用题组** —— 官方注释写明理由：「**意图只改变布局，绝不改变"可达的答案"**」（两颗按钮表达不了三个选项或多选，就不该抢这张卡）。三颗按钮的线上动作：**确认执行 / 拒绝** = 用对应选项的**标签原文**作答（走上一轮做的整组一次回）；**去聊天里说** = `pending.cancel()`，也就是上一轮刚取证的 `ASK_CANCELLED` 帧 —— **本轮没写一行新的线上协议**。**我们此前连 `intent` 都没投影**（中枢逐字段搬 `PendingQuestion` 时漏了它）⇒ 计划请求只能以通用题组出现。fixture **708 → 719 条**；接线门禁 22 → **23 项**。**提问族至此收口**，只剩卡片的收起/展开（纯观感，留真机一起看）。
**放弃整组提问：把最后一条"未取证"追到底（P7-9）**。上一轮记的「`nav.cancel` 线上语义未取证」，这轮把三层源码读齐：`questionError()` 造出 `name='UserQuestionError'` + `code='ASK_CANCELLED'` 的错误 → `pending.cancel()` 把它抛出 → 网关（`dsh-api-gateway/lib/client.js`）把「监听器抛错」编码成 `{kind:"rejected", error:{name,message,code}}`。我们照此发**同一帧**（`Wire.questionCancelledError` + `outcomeRejected`）—— **不是** `{kind:'next'}`：后者是"我不处理，交给下一个应答者"，Host 会继续问别人，与"用户明确取消这次提问"语义完全不同（那是我们 `declineToHandle` 的用途）。视图侧补上官方文案的「放弃整组问题」按钮，失败时**不移走卡片**（移走会让用户以为已经取消）。证据链写进了代码注释，下一个人不必再查一遍。**提问这条线至此没有"未取证"的缺口**，只剩「计划复核」与卡片的收起/展开（纯观感）。接线门禁 21 → **22 项**。
**出上架包变成一条命令（`tools/build-release.mjs`）**：release 构建此前只能手工敲 —— 要自己拼 `DEVECO_CLI_CLT_PATH` / `DEVECO_SDK_HOME` / `JAVA_HOME` 三个环境变量，跑完还得自己从 hvigor 的长输出里分辨"是编译失败还是签名失败"，于是它一直被当成"以后再说"的事 —— 而**上架要求的第一条就是"能重复地产出发布包"**。现在一条命令做三件事：① **先体检签名材料**（读 signingConfigs，逐个检查 .p12/.cer/.p7b 在不在本机；不在就**先**说清"会产出未签名包 + 还差什么"，而不是让人等两分钟才看到 `Invalid storeFile value`）；② 用正确的一套环境变量跑 release 打包；③ **报告产物**：签名状态、体积 Top 条目、**可疑内容**（sourcemap / 测试包 / 源码）。**本机实跑读数**：三个签名文件都不在本机 ⇒ 编译与打包全过、停在 `SignHap`，产出 **269.7 MB** 未签名 HAP；Top 是 `libnode.so.127` 109.4 MB + 两个内置核心各 66 MB；**可疑内容：无**（无 sourcemap、无测试包、无源码 —— 这一条以前没人查过）。⇒ 除了签名材料，发布包链路已经通了。
**提问的两条官方规则取证并落地（P7-7）**：上一轮把两件事记成"官方语义未取证"，这轮去把它们取回来 —— 结果是**一条能完整落地、另一条落地后发现我们原来是错的**。① **推荐标记不在字段里，在标签后缀里**：官方 `parseRecommendedLabel` 正则（半角/全角括号、大小写不敏感）⇒ 显示**剥掉后缀** + 加「推荐」徽标，而同一份源码的注释还写着关键的一半 —— **提交仍送原标签**（送剥过的版本 Host 就匹配不上）；我们此前连这个字段都没有，现在按后缀解析落地。② **答案编码我们原来是错的**：官方 `submitDrafts` 三条规则 （单选 + 自定义 ⇒ `selected: []` + `custom`；多选 ⇒ 并存；跳过 ⇒ 空选择不带 custom），而我们上一轮"一律都送" —— **单选里同时送选项与自定义文本，Host 会拿到用户从没表达过的组合**；现三条规则进纯函数 `encodeQuestionAnswers`。③ `nav.cancel` 的**取证结论**：官方是让这次提问以 `ASK_CANCELLED` **失败**收场（不是 waterfall 的 delegate），而我们要发哪种 `$events/result` 帧才能表达"用户取消"仍未取证 ⇒ **不做一个语义不明的按钮**（宁缺勿假）。**写法上的教训**：把"未取证"写成待办而不是结论 —— 去读源码、能落地就落地、落地不了就写清缺哪条证据。fixture **696 → 708 条**。
**权限预设（P7-6）：能切就切，不能切就说「不可用」（先探后做）**。`permission-presets` 行原记"只能显示不能切换"。先读官方 `dsh-client-ui-permission-presets`：切当前会话权限走的是**命令**（`live.command('/permission ' + option.id)`），"新会话默认"是**设置项**（schema 驱动），没能力时显示官方字典的 `unavailable`（「不可用」）—— 所以**不需要新端点**，复用既有命令通道即可。再给核心闭环自检加了两条真 Host 读数：权限投影 **`current=(空) options=0`**、命令表 5 条里**没有 `/permission`**、12 组设置里**没有**权限键 ⇒ **官方那两个入口在这台 Host 上本来就都不可用**，这把重点从"把切换做出来"改成"没能力时如实显示「不可用」而不是给死按钮"（正是官方行为）。实现：零依赖 `model/Permissions.ets`（能力判定 / 官方原词文案 / `/permission <id>` 形式 / 原因文案）+ `SessionHub.selectSessionPermission`（**没能力时直接发本地回执**，不让用户把宿主的 `unknown command` 误读成"我们发错了请求"）+ chip 两态（有能力可点 → 复用 `ChoiceSheet`，哨兵键名分流）。fixture **686 → 696 条**；核心闭环 **18/18**；真机判据新增 **D28**。
**提问整组（P7-5）—— 顺带修掉一个会卡死一轮对话的缺陷**：`user-questions` 那条差距原记的是"官方是输入区接管 + 计划复核"，读了源码才发现真问题不在排版：`SessionHub.addQuestionPending` 的注释写着"同一 waterfall 可能带多个问题"，而实现是 `const first = questions[0]` —— **后面的题根本不进界面**。上游 `AskUserQuestionRequest.questions` 是**整组**，Host 等的是**一个**答复值 `{answers:[{id,selected,custom?}…]}` ⇒ 用户只能答第一题，**整组答复永远凑不齐，那一轮就卡在那里**。现在：整组投影进 `PendingItem.questions[]`；应答改成**整组一次回**（`answerQuestionGroup` —— 原来每题各发一次，第一次就把事件结掉、后面的答案没处去）；新增 `view/QuestionGroupCard.ets` 持有逐题草稿，按官方交互实现**一个按钮前进**（`index === questions.length - 1 ? 提交 : 下一题`）+ `上一题`（到头停住不循环）+ `跳过本题`，提交前逐题校验并用**逐字取的官方文案**拦阻（`请先完成这道问题。` / `请选择一个选项或填写自定义答案。`），自定义答案占位用官方的「输入你的答案」。`PendingPane` 按 kind 分派（审批 → 原卡；提问 → 组卡），抽完门禁立刻抓出宿主 4 处搬迁残留并删净。**如实登记两处没做**：`option.recommended`（我们的选项投影没带这个字段 ⇒ 不画，也**不拿第一项冒充推荐**）、`nav.cancel`（放弃整组：官方这一动作的线上语义未取证 ⇒ 不做语义不明的按钮）。fixture **670 → 686 条**；接线门禁 20 → **21 项**；真机判据新增 **D27**。
**轨迹条目的事件详情（P7-4，inspector）**：`trajectory` 行"仍缺"的最后一条可做项 —— 点一条事件看它的详情。读官方 `dsh-client-ui-trajectory` 的字典：它点一条事件开出「事件详情」面板（`details.event`，成对字段：状态/用途/提供方/模型/工具调用/子工具调用/错误/结果/来源/层级/助手消息，可关闭、可拖动调宽）。新增零依赖 `model/TrajectoryDetail.ets`（**空值不产生行** ⇒ 有几行画几行；长文本复用工具卡同一套 `previewOutput` 截断阈值并写明总长；`internal` 条目在「来源」里如实标注「· 内部事件」，免得有人以为"界面上看不见就是没发生过"）+ `view/TrajectoryInspector.ets`，**会话头时间线下方**与**右栏「轨迹」面板下方**两处共用同一份（单栏手机上右栏是 Sheet ⇒ 三种形态都在场）。官方那些来自它自己事件模型的字段（purpose / provider / hierarchy / subtoolCalls）我们的投影没有 ⇒ **不画**，而不是画"未知"。fixture **654 → 670 条**；真机判据新增 **D26**（7 条）。
**后台任务改成官方的"触发器 + 展开清单"（P7-3）**：读 `dsh-client-ui-jobs` 源码 —— 官方在会话头只放**一个按钮**（`StateDot`（**仅 live 时**渲染）+ 「N 个后台任务运行中」/「N 个后台任务」+ 折叠指示，`aria-label: 后台任务`），点开才是清单（状态点 + 任务**类别** + 名称 + 状态/detail + 耗时）。我们此前是**常开**的换行任务条，任务一多就把会话头撑高，还带一句「展开收起全部任务在轨迹」的指引 —— 那是我们自己加的，官方没有，而且把用户从头部指去另一个页面看同一批任务（**顺带修掉**）。现在同结构、同文案（运行中/正在停止/已完成/已取消/已失败 + 已运行/耗时）。**登记一处刻意保留的差异**：轨迹里仍有 `JOB` 行 —— 官方轨迹**没有** job 这个 kind（实测其 bundle 里 `job` 出现 0 次），但去掉它要动轨迹的单元格索引映射（搜索命中与时间总览都按 `items` 下标走），无真机复核时不划算 ⇒ 保留为"何时起了哪个任务"的台账。折叠箭头用的 `chevron_up`/`chevron_down` **先在 CLT 的 `sysResource.js` 里查实存在**才写（本仓有过"符号名不存在不报错、只是画不出来"的教训）。接线门禁的"后台任务条"补上 `liveJobCount`；真机判据新增 **D25**。
**输入区接管（P7-2，对齐官方 approval / user-questions）**：`approval` 行的差距是"官方是输入区接管，我们是独立的「待决」页"。读官方源码后发现**差距不止位置**：`dsh-client-ui-approval` 往 `conversation.composer` 槽位注册的是 **priority 1、`select` 只选本会话当前那一条**的组件（卡片 = 圆点状态带「等待审批」+ `工具 {toolName} 请求越权执行` + 等宽原始请求 + 拒绝/允许一次），而我们此前把**中枢全量**待决铺在输入区上方 ⇒ **在会话 A 里点下去，放行的是会话 B 的审批**（误操作，不是排版问题）。现在：新增纯模型 `PendingFocus.ets`（只取本会话第一条，到达顺序；其它会话的条数用一句提示指向「待决」页），输入区上方按官方结构重画（状态带 / 标题 / 等宽原始请求只对审批给）；「待决」聚合页保留（跨会话总览，两者靠提示互相指路，不重复同一批卡）。fixture **640 → 654 条**；接线门禁 19 → **20 项**；真机判据新增 **D24**。**仍缺**（写进矩阵）：官方提问卡的整组能力（上一题/下一题/收起/放弃整组/推荐标记/跳过本题）与计划复核呈现 —— 我们的 `PendingItem` 是单条模型，要对齐得先让投影带上"问题组"。
**会话搜索（P7-1，官方 sidebar 的一等能力）**：`sidebar` 行的"仍缺"里挂着最像"缺功能"的一条 —— **无会话搜索**。这次不再凭印象对齐：`/opt/dsh/node_modules/@deepseek-ai/dsh-client-ui-*` 就是**官方客户端的已安装包**（39 个能力面一一对应），`dsh-client-ui-sidebar` 的包描述写着 `session multi-level tree, **search**, grouping, state dots`，而搜索的**形态**在 `dsh-client-ui-workspace` 里：**扁平结果行** = 标题 + 工作区上下文 +（可选）内容片段，注释还写明"本地命中与 Host 内容命中**合并**""标题为空的行不参与匹配"。载荷契约则早就在我们自己的 `docs/11` 里（`{request:{query}}` → `{items:[{sessionId,snippet}],hasMore}`，上限 20 / 片段 240 code points）。实现：输入关键词 ⇒ 会话区**换成扁平结果**（树用 `Visibility.None` 隐去，理由写在代码里），标题命中本地算、内容命中走 Host，两路合并去重；**降级不是"备而不用"** —— 本机真 Host 实测 `session/search` 回 `gateway/internal`（未挂 `dsh-session-query`），所以"按标题匹配 + 明确说明原因"就是当前真正在跑的那条路。纯模型 `SessionSearch.ets` + 中枢 `searchSessions` + 视图结果区；fixture **622 → 640 条**；接线门禁 18 → **19 项**；核心闭环 **16/16**；真机判据新增 **D23**。
**用户实测三报：设置页三处真缺陷（已修，E214）**。① **模型 → 提供方 →「配置」全部点不动**：候选提供方那一行点「配置」时把 `expandedProvider` 设成 `g.title`，而展开判定比的是**提供方 id**；更要紧的是**候选不在** `providerGroups()` 的循环里 ⇒ 就算键对了也**没有落点**，点了什么都不会发生。现在按 id 展开，且展开体与提供方卡片**共用同一个** `providerEditor`（设置字段 + 模型目录）。② **模型列表重复**：底部「各提供方的模型（点选设为新会话默认）」与提供方展开里的模型目录是**同一份** `g.models`、同样语义 ⇒ 删掉底部那份（E213「先搬后拆」的"拆"），"点选 = 设新会话默认 / 推理强度按模型选"的提示搬进展开体。③ **「插件」与「插件清单」功能重复**：官方能分成两个分区是因为它有**两个数据源**，而端侧只有**一份** `PluginItem[]` 投影 ⇒ 两个分区渲染同一批行（只差一个过滤框与一个徽标）。合并为一个「插件」分区（过滤框 + 可安装性徽标 + 两段说明），撤掉 `settings-plugin-inventory` 分区，矩阵该行改判 `PARTIAL` 并登记。另修一类真机"点不动"的**物理原因**：只挂 `.onClick` 的 `Text` 命中区就是那几行字 —— 新增 `actionLabel` 统一到 44vp（`Sz.TOUCH_MIN`），模型页三处行内动作都改用它。真机判据新增 **D22**（5 条）。
**上架合规自查：release 打包此前根本打不出来（本轮修通）+ 权限收紧到 2 项**。① **release 构建直接失败**：`platform` 与 `hostruntime` 两个模块的 `build-profile.json5` 声明了 `ruleOptions.files: ["./obfuscation-rules.txt"]`，而这两个模块**没有那个文件** —— debug 不读这一项，所以一直没人发现，**只有 release 会红**。补齐后 release 一路跑到 `SignHap`，产出 `entry-default-unsigned.hap`（270 MB / 74 文件）；顺带把六个模块的规则文件统一成"混淆保持关闭 + 开启前提"（原文件里写着 `-enable-property-obfuscation` 等指令，与 `enable: false` 自相矛盾 —— 一旦有人打开开关，协议层按字符串读字段会**静默失效**）。② **权限最小化**：删掉 `ohos.permission.GET_NETWORK_INFO` —— 它唯一的取值入口是 `@ohos.net.connection` 一族，而**全仓没有任何调用点**（应用自己的"离线"判据来自中枢状态），理由串一并删除。现存 2 项：`INTERNET`（连回环 Host / 用户自填远端）与 `KEEP_BACKGROUND_RUNNING`（长任务后台续跑，`KeepAlive.ets`）。③ 新增 **`docs/70-上架合规自查.md`**：包结构、权限逐项证据、数据与网络姿态（无遥测、只绑回环、不采设备标识、数据只落沙箱）、受限能力红线（不做动态下发代码、不申请 JIT/ACL、不滥用保活）、HAP 体积构成与"两个内置核心是刻意的（切回上一版必须本机就有）"、release 签名现状（仓库里是 DevEco **调试证书**且文件在开发机上 ⇒ 上架包需 AGC 发布证书）、AGC 侧待办与可复跑命令。**仍缺**：发布签名材料与真机验收（没有设备/hdc/签名文件）。
**核心使用闭环第一次在本机跑通（E371）**：此前的本地证据只有"Host 起得来"与"纯逻辑有 fixture"，**中间那半段**（应用自己的 `Connection` / `dshcompat` 端点表 / `projectSessionList` 投影）从来没在本机跑过 —— 它只在 D1 阶段真机上被走通过。现在 `tools/lib/kit-stubs/` 用 `node:http(s)` 与 Node 22 内建的全局 `WebSocket` 实现 `@kit.NetworkKit` 的三个能力（**应用代码一行不改**），`tools/check-core-loop.mjs` 把 `.ets` 摊成 `.ts` 编译后对着**真 dsh Host** 跑九步：就绪 → configure → authenticate（303 + cookie）→ start（事件流）→ session/list（0 条）→ session/create → **再 list，新会话在列表里** → session/prompt（**`{"accepted":true}`** + 3 帧事件）→ 事件流累计 7 帧。**9/9 通过**。**本轮把检查扩到应用真正的状态机**：`SessionHub`（模块级单例，窗口只是它的视图）也被搬进同一个垫片环境——它**一个 `@kit.*` 都不 import**（唯一平台符号是 `MAX_ATTACHMENT_BYTES` 与四个通知类型 ⇒ 一个 `platform-shim.ts` 就够），于是「配置 → 连接（`phase=live` + 事件流 + 控制流）→ 新建会话（进列表 + 自动选中）→ 发消息（已受理）→ 统计 → 事件类型全部认识」这六步在本机也能跑，整轮 **15/15 通过**（"轨迹 0→0 / turns=0"是因为本机没配模型，脚本会把这句话打印出来，不让人误读成坏了）。踩过的坑：垫片形状必须逐字段照抄（`NotifyRoute` 真身是接口，写成枚举编译就红）、**类字段名 ≠ 快照字段名**（`trajectoryList` vs `trajectory`，读错不报错 ⇒ 检查脚本一律只读 `snapshot()`）、地址必须把 token 拼回 URL（与应用同一条路）。早先踩的两个坑：ArkTS 的 kit 说明符是**点号**（`@kit.NetworkKit`，产出的 JS 就是 `require("@kit.NetworkKit")`，磁盘上要有同名目录），而 `tsconfig.paths` 只管**编译期**、运行时还得在构建目录补一层最小 `node_modules`；起 Host 必须 **Node 22**（`--no-experimental-fetch` 在 Node 23+ 是非法取反）。**它不替代真机验收**（端侧走 ArkTS 的 http/webSocket，自定义 header 与 ping/pong 有已知差异），故不进每轮门禁，按需跑：`/home/node/node22/bin/node tools/check-core-loop.mjs`。
**P5-7 已落地（剪贴板收口 + 窗口台账接上读数）**：登记册里 `hdsh-clipboard` 一行写着"**不允许挂着不动**"，这轮把"挂着"的东西逐个拍板。`readText` 挂着的理由是"读剪贴板要 `READ_PASTEBOARD`"（与设计原则 2「不申请特殊权限」冲突）；查下去发现 SDK 里**有**免权限的安全控件 `PasteButton`，但两处代价让它不值得：安全控件的**样式由系统校验**（改样式可能让授权失效）⇒ 在工具行里会是与相邻 chip **风格不一致**的胶囊按钮；官方文档还写明**被布局截断时点击不授权**，而工具行在 360vp 手机上已经很挤。**更要紧的是用户不需要它** —— 往输入框粘贴走的是**系统文本域自己的**粘贴菜单，应用不参与，按"不重复实现已有功能"的规矩这条路本就不该走。⇒ 删 `readText`；`clearClipboard` 的注释写着"含凭据的复制后应清理"，但复核三处 `copyText`（诊断报告**已剔除凭据** / 右栏行复制 / 消息复制）**没有任何复制凭据的入口** ⇒ 策略没有前提，一并删掉，"将来新增该入口需同时接清理"写进 parity 行。顺手查出另一个**只写不读**：`platform/RuntimeSingleton` 的窗口台账三个写点都在 `EntryAbility`，而读侧零消费点 ⇒ D1 §7.7.5b 要的"窗口数 >1 且只有一条连接"这条证据**在应用里取不出来**；现在 `runtimeFacts()` 接进诊断报告一行。死代码门禁规则⑤扫描面 **appstate → appstate + platform**（两层都是自研机制；`connection`/`dshcompat`/`Wire.ets` 是上游协议词汇表，不扫），判定面 582 → **635 个导出符号**；真机判据新增 **D21**（6 条）。
**P5-6 已落地（插件启停的文本层：搬出来，第一次有测试）**：上一轮把"零消费者导出"的量法扩到 `appstate` 之外，一眼看到 `hostruntime/core/PluginRows.ets` 里 `serializeUserRows` / `parseUserRows` / `USER_ROWS_FILENAME` 都"只在自己文件里被用一次"。查下去不是死代码，而是**没有测试**：端侧插件安装/卸载永远做不到（上游经 `pnpm` 创建进程），能做的只有"启停随包发版的行"，机制是写 `<profile>/.hdsh-plugin-rows.yml`、由入口脚本 `hostcore/app/main.js` **原样**拼进 `cordis.patch.yml` 的围栏块，下次启动再由本层读回来 —— **两侧任何一侧改格式，症状都是"静默丢启停"**（文件还在、行数变 0）。而既有的 `check-plugin-toggle.mjs` 是**自己手写**那段 YAML 的，证明不了我们的序列化器；测不了的原因是 `PluginRows.ets` 依赖三个 `@kit.*`（fixture 编译器加载不了）。⇒ 把文本层搬进**零依赖**的 `core/PluginRowsText.ets`，`PluginRows.ets` 只留文件 I/O 并原样再导出（对外面不变）。fixture **601 → 621 条**：输出形状（每条两行、不省略 `disabled`、结尾换行）/ **往返不变式**（`parse(serialize(rows))` 逐条相同且 `ignored === 0`）/ 容错计数（空 `- id:`、孤儿 `disabled:`、不认识的行都要数出来）/ `disabled` **fail-closed** 取值 / 文件名与入口脚本同名。顺手改掉 `hostruntime/Index.ets` 头部"核心切换/回滚尚未实现"的过期描述；另**登记未动**：`appstate` 之外的零消费者导出实测 **40 个**（多为协议词汇表，其中 `readText` 读剪贴板已登记在 `hdsh-clipboard`）。
**P5-5 已落地（零消费者导出：量出来、清掉、变成第 5 条规则）**：前几轮量的都是"字段有没有读者"，这轮换到**导出符号** —— 数**全仓出现次数**，`≤2` 就是"只有声明 + barrel 再导出"。一次清掉 **25 个**：`speakable`（`TurnView` 已有去标记版本，模型那份会把 `**` 念出来）、`sessionSubtitle`（副信息行早由 `WorkspaceBrowser` 内联 + `sessionContextLine` 承担）、`toolStateIsProblem`（与 `ToolPresentation` 同一判据）、`LARGE_OUTPUT_BYTES`（D3 §3.3 的 8 KB 从没被比较过）、`ConnectionBanner`（banner 的 UI 在 E345 就删了）、**6 个 `SETTINGS_*` 常量**（设置分区 id 的真值在 `PanelRegistry.settingsSections()` 的字符串字面量里，常量是第二份真相）、`emptyPanelList` / `PanelList` / `InAppNotice` / `modifierLabel` / `MODIFIER_LABEL` / `breakpointThresholds` / `shortcutBindingLabel` / `HarmonyMaterial` / `harmonyTokenFor` / `sessionListPayload` / `projectSettingsGroups`。三个**有意保留**写 `// dead-exempt: 理由`（帮助浮层未做的 `shortcutsForDesktop`、按键判定走 KeyCode 的 `keyEventSpecs`、文档化数据 `WEB_TOKEN_MAP`）。**量法的三个坑都实测过**：语料必须含 `tools/`（纯逻辑大量只被 fixture 读，不含就误报 19 处）、`model/Wire.ets` 整文件排除（上游协议词汇表，天然躺着 29 个暂时没人用的形状）、必须**剥注释**（几个符号的"引用"只在注释散文里）。死代码门禁 **4 → 5 条判定**，规则⑤对当前树归真命中 5 处后清零；新增审计 `tools/audit-zero-consumer-exports.mjs`；顺带删掉 `ToolCard.diffOf` 里被下一条完全包含、永远走不到的三行。
**P5-4 已落地（门面字段的"读点"变成第 4 条死代码规则）**：`export interface *Facade` 是本仓约定俗成的**写回通道**（子组件 → 宿主：值快照 + setter + 回调闭包），它的**声明与读者在子组件、实现在宿主** ⇒ 只数"本文件出现几次"的前三条死代码规则**既数不到读者、也数不到写者**。新规则改成**整仓数 `.字段`**：搜不到就是**没有任何调用点**。规则写完先在**还没修的当前工作树**上跑，**恰好命中 2 处**：`TabContentFacade.setConfirmingDeletePath` 与 `.setSelection` —— 声明在 `TabContentView`、实现在 `Index` 的 `buildTabFacade`、全仓零调用；两者的真值都另有写者（两步确认在宿主的 `toggleDeleteConfirm`、模型选择走 `SessionHub.selectSessionModel`）⇒ **残留的重复通道**（不是 E361 那种缺失的控制点），删掉。另配 4 条注入式自检（真死通道 / 读者在别的文件不误报 / 只写不读仍算死 / `dead-exempt:` 有意保留）。只盯 `*Facade` 不盯所有接口：数据型接口常被整体传参、逐字段判会变噪音。`Index.ets` 4059 → **4053 行**。
**P5-3 已落地（双栏的「展开侧栏」是个死按钮）**：上一轮把"呈现"与"几何"接上之后，这一轮去数"**呈现判定到底被几个调用点问了**"——答案是一半：`buildTriple` 问了，`buildDouble` 没问。`buildDouble` 调的是 `navRail()`，那份 surface 把呈现**写死**成 `TrackPresentation.RAIL`，于是双栏下点「展开侧栏」：偏好变了、纯函数判定也变了、轨道宽度也跟着变 —— **可唯一那个绘制侧栏的调用点根本没问判定**，rail 照画不误；D19 第 2 条在真机上必然失败。而 `navRail()` 与 `sidePanelSurface(...)` **逐字段相同、只差 `presentation` 与宽度来源**（它就是后者的手抄版，走样只是时间问题）⇒ 删掉 `navRail()`（−31 行），双栏改调 `navPanel()`。这类缺陷**正面计数拦不住**（该在的特征全都在，多的是一个不该有的常量），故 `check-feature-wiring` 新增**反面规则**：`AppShell.ets` 里不许出现 `TrackPresentation.RAIL`（它在本仓永远是判定的结果；`PANEL`/`OVERLAY` 是结构上固定的表面，写常量是对的），门禁先剥注释再匹配，并**对修前的 `HEAD` 归真命中 `AppShell.ets:228`**。`AppShell` 420 → **397 行**。
**P5-2 已落地（侧栏"收起"终于真的腾出宽度）**：上一轮把侧栏收起接通了，这一轮去查"收起之后到底发生了什么" —— **只有呈现变了、几何没变**：`AppShell.navPanel()` 传的是 `Sz.NAV_PANEL` 常量，而 `SidebarShell` 的 rail 宽度取的是**布局决策**里按形态算的 `navWidthVp` ⇒ 三栏收起侧栏后轨道照样占 240vp（"腾出宽度"一次都没发生），双栏收起后是 240vp 的框里放一条 56vp 的 rail、右边空出 184vp 底色。新增零依赖纯函数 `sidebarTrackWidthOf(mode, stored)`（panel 240 / rail 56 / 浮层 0）；`SidebarShell` 的 rail 宽度改用 `Sz.NAV_RAIL`，`navWidthVp` 这个 prop 与门面字段一起删掉（**组件自己的几何不该由外部按形态猜**）；`sidebarExpandedOf(stored)` 换成 **`sidebarExpandedForMode(mode, stored)`** —— "没存过"必须按形态给默认，否则双栏首启被读成"展开"，与 `shellTracksOf(DOUBLE).sidebar = RAIL` 和四形态 fixture 直接矛盾；偏好因此搬出 `NavigationState`（删 `sidebarExpanded` / `setSidebarExpanded`，真值只剩页面里那份原始 `boolean | undefined`，生效值每次渲染派生）；删 `sidebarOccupiesLayout`（与"宽度 > 0"同一个问题，且只有 fixture 在用）。fixture **595 → 601 条**；真机判据补进 D19 第 6 条。
**P5-1 已落地（核心页投影搬进 `appstate`）**：`Index.ets` 里 `pluginInventoryFact` 与 `corePluginRows` 是两个**纯投影**（宿主报告 → 核心页的事实与行），一行 UI 都不碰，却住在最大的那个页面文件里。搬到 `appstate/model/CoreProjection.ets` 时第一版编译就**红了** —— ArkTS **禁止结构化类型**（`arkts-no-structural-typing`）："字段一样"的接口**不能**互赋，只能 `extends`。出路两条：让 `appstate` 反向依赖 `hostruntime`（**方向是反的**，它连 `oh-package.json5` 的 `dependencies` 都是空的），或者让调用点把用到的字段**逐个取出来** —— 选了后者，签名改成 `pluginInventoryFact(note, version, totals, nativePackageCount)` / `pluginRowOf(...)` / `rankPluginRows(rows)`，接口降级为"参数分组"（避免 7 个位置参数写错顺序）。`rankPluginRows` 只排序不隐藏、且**返回新数组**（调用点那份仍保持清单原顺序）。fixture **+18 → 595 条**；`Index.ets` 4061 → **4031 行**；裸值随之下减少，令牌棘轮从 23 处 / 9 文件拧到 **21 处 / 8 文件**。**规律**：最值得继续搬的是"页面里长出来的纯投影"，判据是**它有没有 import ArkUI**，而不是它有多长。
**P2-17 已落地（侧栏收起状态落盘）**：照抄详情栏宽度记忆那一套（`LocalPrefs` + 启动读回 + 变更落盘），但多了一个**三态**问题 —— 侧栏默认是展开，而"偏好里没有记录"若直接读成 `false`，就会把"从没设置过"变成"收起"（用户第一次启动只看到一条 rail）。故 `KEY_SIDEBAR_EXPANDED` 存 `'true'`/`'false'` **字符串**、用 `has()` 判存在、缺失即 `undefined`；"没存过时用什么"这一步放零依赖纯函数 `sidebarExpandedOf`（fixture **+3 → 577 条**）。落盘失败**不弹提示** —— 与宽度记忆**有意不同**：它下次只是回到默认展开，没有信息损失。
**P2-16 已落地（新建会话入口补全）**：让侧栏能收起之后顺手查出**收起之后的直接后果** —— `＋ 新建会话` 这个一级入口**只画在 `panelBody`**（PANEL 呈现）里，于是：三栏收起侧栏（rail）时没有它，**单栏手机走底部标签栏时也没有它**，用户只能靠空态里那个按钮或 Ctrl+N（还要设备有键盘）。而官方侧栏**不论宽窄**都把 New Session 当一级入口 ⇒ 这是"信息架构在窄形态下缺项"。补法：rail 里排在「展开侧栏」下面（两者都是"轨道级"动作，读起来是一组），底部标签**排第一位**；`onNewSession()` 调用点 **1 → 3 处**（三种呈现各一），并修正组件头部那句"只在品牌行下方"的过期口径。
**P2-15 已落地（侧栏终于能收起）**：上一轮删 `activeOverlay` 时留下的同模式候选 `NavigationState.sidebarExpanded`，这一轮查清了性质 —— 它**不是冗余字段，而是一个缺失的功能**：侧栏呈现完全由形态决定（`shellTracksOf`：单栏浮层 / 双栏 rail / 三栏 panel）⇒ **官方 AppFrame 那个"收起侧栏腾出宽度"的动作在本仓做不到**。新增零依赖纯函数 `sidebarPresentationOf(mode, expanded)`（**单栏一律浮层**：那个档位没有"展开的侧栏"，按钮也不给；双栏默认 rail、可展开；三栏默认 panel、可收起），品牌行加「收起」、rail 顶部加「展开」—— **少了后者"收起"就是一道单向门**。fixture **+7 → 574 条**，并钉进功能接线门禁（第 18 项：纯函数判定 + 门面开关 + 视图控制点）。**规律**：见到"字段 + setter + 无人读"，先问"它描述的东西别处有没有真值" —— 有就删（`activeOverlay`），没有就是缺控制点（`sidebarExpanded`）。
**P2-14 已落地（删掉"只有 fixture 在用"的浮层状态机）**：从"导出了但 UI 从未引用"清单入手，查到 `NavigationState.activeOverlay` / `Overlay` / `openOverlay` / `closeOverlay` 在 `entry` 侧 **0 引用** —— 真实的浮层优先级由 `Index.overlayState()` 从六个布尔**派生**，于是这套字段**永远停在 `Overlay.NONE`**。它之所以"看起来还活着"，是因为 fixture 里有 3 条断言**只测它自己**（自证循环）。已删除，fixture **570 → 567**（**少的是自证断言，不是回归**）。**宁可少三条断言，也不要一套与真实界面平行的状态机**。同一份清单里 `sidebarExpanded` 是下一个同类候选（字段 + setter + 无人读）—— 它要"侧栏收成 rail"的产品语义，故登记待定，不在本轮顺手删。
**P2-13 已落地（单栏 Sheet 的右栏切换器）**：右栏的面板切换器此前只画在真右栏 / 侧边面板那一份里，而**单栏的详情 Sheet 没有它** ⇒ 手机用户打开详情后**根本切不到文件 / 预览 / 工具 / 子代理 / 交付物 / 轨迹**（P3 登记的第三个缺口，属"功能不可达"级别）。修法：切换器抽成共用的 `@Builder panelSwitcher()`，两处都调；顺手换掉 Sheet 里那句固定的「工具 / 子代理 / 交付物 / 目标 / 任务」提示 —— 它对文件 / 预览 / 详情三个面板是**错的措辞**。P3 另两个缺口（**滑入动画**与**拖拽调宽**）都属观感且**必须真机验收**，按本仓纪律继续留在登记里等设备通道。
**P2-12 第二步（门面接线完成）**：`RightbarShell` 的 **12 个内容 props 收成一个 `f: RightbarFacade`**（组件内 39 处用法改 `this.f.X`），`AppShellFacade` 里透传的 **11 个 `right*` 成员全部删除**；两处挂载点（三栏真右栏、详情浮层）现在都调同一个 `Index.buildRightbarFacade()` —— 浮层那一份此前是**内联重算**（`deliverablesOf` / `itemsOfKind` / `buildRightFilesFacade` 各写一遍），正是"新加一个面板很容易只给一处"的来源。顺便删掉浮层里重复的"`text.length > 0` 才复制"判断。**行数的诚实账**：`Index.ets` 4019 → **4026（+7）** —— 这一轮的收益是"两处只有一个真值"，不是变小；只看行数会误判它白做。
**P2-12 第一步（右侧内容门面定义）**：准备拆「详情浮层」时发现它只是一个 `RightbarShell({...})` —— 真问题不是那 36 行，而是 **`RightbarShell` 有两个挂载点、各自把 16 个 props 拼一遍**（真右栏经 `AppShellFacade` 的十来个 `right*` 成员；详情浮层在页面根**内联重算**）。只要有一处漏改，同一个面板在两种呈现下就会不一样。本轮先定义 `export interface RightbarFacade`（12 个两处共有的成员，并写明"每个挂载点只提供它自己那份"）；**接线留到下一轮**，那样改动面一眼可数。本轮**行数不变**（4019）—— 产出是契约，不是搬家。
**P2-11 已落地（`Index.ets` 第三、四刀）**：一次搬两个浮层 —— `view/CredentialSheet.ets`（127 行，保留三条真机实测语义：输入框**显式 44vp 高**（E95）、明文**只在这一个请求里存在**、**成功时才关面板**）与 `view/ChoiceSheet.ets`（99 行，单选即提交、**没有多余的"确定"按钮**，并保留"原生 Sheet 自己就是表面"这条修正）。抽完这两个，`sheetContent` 的六个分支现在**各是一句组件调用**——"谁在显示就渲染谁"只要看六行。`Index.ets` **4133 → 4019 行**（P2-9…P2-11 四刀合计 **4480 → 4019**）。
**P2-10 已落地（`Index.ets` 第二刀）**：两个设置编辑浮层各自成组件 —— `view/SettingTextSheet.ets`（131 行，文本/数字项）与 `view/SettingStructSheet.ets`（142 行，JSON 整值编辑，含"恢复为当前值"与"恢复默认"两个安全网）。它们的**输入提示**（类型 / 范围 / 步长 / 正则 / 必填 / 当前值占位）搬进零依赖的 `appstate/model/SettingEditors.ets` （**+12 条 fixture → 570 条**），并顺手消掉"当前：X / 当前未设置"两处各写一遍的隐患。两个组件接受**可空 item** 并早返回 —— 而不是让宿主造一个 **20 个字段**的占位设置项（那正是"形状靠猜"的坑）。`Index.ets` **4297 → 4133 行**（P2-9/P2-10 合计 4480 → 4133）。
**P2-9 已落地（`Index.ets` 第一刀）**：`Index.ets`（4480 行）是现在最大的单点，本轮拆出其中**最自足的一个浮层** —— `view/FolderPicker.ets`（297 行）带走沙箱目录选择器的**全部**（当前路径 / 子目录 / 提示 / 开合 + 读目录、进目录、上一级、新建、选定五个动作）。打开它的**两个**入口（设置里"选择文件夹"与系统选择器失败后的降级）用**控制器对象**（与 `TurnViewController` 同源）；控制器上必须有 `close()` —— **原生 Sheet 的关闭路径（下拉/遮罩/按钮）不经过组件**，少了它浮层会再也打不开（与 `bindContextMenu.onDisappear` 同一个坑）。沙箱根留在宿主（`getContext` 是平台能力），拿不到就不打开并说明原因。`Index.ets` **4480 → 4297 行**。
**P2-8 已落地（浮层结果出口按归属）**：本轮动手拆 `Index.ets` 的六个浮层（≈960 行）之前先读了一遍，结果查出更要紧的东西 —— **凭据 / 文本设置 / 结构设置三个浮层共用同一对字段**（`credentialNote` 与 `credentialBusy`）。两条实测后果：① **串浮层**——凭据写入失败 → 关掉 → 打开「编辑文本设置」，**那条凭据的失败文案会出现在文本编辑浮层里**；② **跨浮层置忙**——凭据在写时文本/结构浮层的按钮也会变灰。这与设置页那条"回执没有归属域"（E347）**是同一个缺陷类**。修法：回执带归属（`sheetNoteOwner`，打开时认领、关闭与返回键路径交还归属；判定在零依赖的 `appstate/model/Sheets.ets`）+ 每个浮层拿自己的 busy。fixture **+11 → 558 条**。**拆那 960 行的计划留到下一轮** —— 修完缺陷后它们是零风险搬家。
**P2-7 已落地（会话头上下文行）**：补官方 `conversation.header` 的 **Workspace context / Model / 最近活动** 三项 —— 此前用户得回工作区列表才知道这场会话在哪个目录里跑。规则做成零依赖纯函数 `appstate/model/SessionContext.ets`（工作区名取**末两段**：同名目录会撞；三段拼装**每段拿不到就不出现**、全空则整行不画），fixture **+14 → 547 条**。"现在"由调用点在渲染时给，**不引入第二个定时器**。`Agent preset` / `Schedule` / `Open in App` 三项**如实不做**（缺"当前会话的预设名"与协议面），留在缺口台账。
**P2-6 已落地（第二刀：一个回合的渲染整块搬出）**：`view/TurnView.ets`（492 行）带走回合骨架、过程分组、条目分派、思考/目标/错误三块、展开集合与消息动作与反馈辅助共 20 个成员。**展开集合留在子组件、按钮在父组件** ⇒引入**控制器对象**（父组件持空壳、子组件 `aboutToAppear` 注册实现；与 ArkUI `Scroller` 同源）。思考块抽成 `view/ReasoningRow.ets`（83 行）供**轨迹视图**与**过程分组**共用；轨迹视图另留条目级 `flatItem` 分派 —— **共享卡片，不共享分派**（两者上下文不同）。`ConversationPane` 1087 → **984 行**（P2-4…P2-6 合计 1414 → 984）。上一轮新增的死代码门禁当轮就抓出 2 处搬迁残留（`TurnView.reasoningItem` 已被取代；`hitIds`/`fbRating` 两个 prop 没有读者）。
**P2-6 已落地（第一刀：把「搬迁留下死代码」变成门禁）**：前两轮反复出现同一类无感缺陷 —— 编译通过、界面正常、八门禁全绿，而宿主体内躺着一批**零使用**的壳（E345 三个零调用 `@Builder`、E346 拆走两段后宿主那段唯一的读者还活着、E346b `settingsStates` 一条没人读的死链），三次都是我手工扫出来的。现固化成第 **9** 道门禁 `tools/check-dead-code.mjs`：零使用 **import / `@Builder` / 组件成员**三条判定，含 **9 条注入式自检**，并**对修前的 `SettingsPane` 归真命中 5 处**真实死代码。门禁在当轮就查出并删掉 3 处真死代码：`MessageFeedback.itemId`、`MessageRow.menuHint`、`SettingsPane.settingRow`（P4-3 的薄包装，P4-5 之后一个调用点都没有）——删 `menuHint` 的绑定还连带暴露 `ConversationPane.inputModality()` 成了死方法。
**P2-5 已落地（会话正文第二刀）**：把会话头那四块**不在列表里的** chrome 抽成
`view/ConversationHeader.ets`（284 行）—— 视图切换 + 轨迹工具栏（展开全部 / 收起全部 / 事件计数）、
后台任务条（官方 `conversation.header.jobs`，live 任务每秒走字）、时间总览、会话内搜索条。
**分工口径**：跨行状态（搜索的命中判定、任务条定时器）留在父组件，块内状态留在子组件；
`stats` 改成**必需 prop** —— 不造"全 0 的默认统计"，那会让"没接到数据"看起来像"这场会话什么也没花"。
`ConversationPane` 1234 → **1093 行**（P2-4/P2-5 两刀合计 1414 → 1093）。
**P2-4 已落地（会话正文第一刀）**：把"**一条消息**"整块抽成 `view/MessageRow.ets`（221 行）——
它带走了此前散在正文组件里的**五份行级状态**（悬停、上下文菜单开关与归属、反馈面板归属与回执）、
两个 `@Builder`（行内操作条、上下文菜单）与三条输入策略判定包装（悬停 / 右键 / 手势提示）。
**边界如实划定**：跨行的「展开全部」态、要读中枢反馈记录的动作清单、以及反馈的持久化，
都**留在父组件**（与 `ToolCard` 的 `expanded` 同一条规矩）。顺带删掉一处重复实现：
视图私有的 `clockOf` 与模型的 `formatClock` 逐字等价，保留带 fixture 的那个。
`ConversationPane` 1414 → **1234 行**。
**P4-6 已落地**：① 最后一段内联内容拆成 `view/SettingsCore.ets`（78 行，包住 `CorePane` + 两块提示；
它是 E118「`@BuilderParam` 注入在真机崩溃」的修复形态，不是多余转发层）。
② **修掉一个真缺陷（E347）**：设置写入回执是一个全局字符串、只有**一个**读取点（设置页顶部那条回显），
于是一方面切分区会把上一段的回执带过来（看起来像本页刚写出来的结果），另一方面——
更糟——**7 个工作区/会话函数、19 处回执写在设置通道里**，用户在会话里点「归档」等操作
**根本看不到任何回执**（"点了没反应"）。现在：设置回执带**归属域**（`settingsWriteDomain`，
只在"域 == 当前分区"时显示），工作区/会话回执改走会话输入区那条通道（`attachNotice`）。
域判定搬进**零依赖**的 `appstate/model/SettingsDomains.ets`（原文件再导出，所有导入点一字未改），
于是它能被 fixture 直接执行 —— **+19 条断言**（五类命名空间 + 三类"不猜"边界 + key→域三条边界）。
`SettingsPane` 497 → **500 行**（P4-1…P4-6 合计 **1890 → 500**），设置域九个组件：
`SettingRow` / `SettingsGeneral` / `SettingsModels` / `SettingsPlugins` / `SettingsInventory` /
`SettingsSkills` / `SettingsPresets` / `SettingsCore` / `SettingsDevice`。
**P4-5 已落地**：设置页最后两段大内容拆成域组件 —— `view/SettingsSkills.ets`（95 行：技能清单 + 读取结论，
只吃两个 prop、无写入动作）与 `view/SettingsPresets.ets`（271 行：官方这一页的两半——预设名单卡片
（复制 / 查看 / 两步确认删除）与 `agent-*` 分区编辑器，含三个组件内临时态与「查看」的中枢直读）。
**同时清掉 16 个零消费者成员**：搬走那段唯一的读者（6 个 prop/回调）、已住进域组件的三个临时态、
只服务于预设段的 `agentGroups()`，以及 `settingsStates` 这条**从头到尾没人读的死链**（中枢快照 →
`Index.@State` → 主区门面 → 假门面成员 → `SettingsPane.states`）与 `onPickEffort`。
`SettingsPane` 758 → **497 行**（P4-1…P4-5 合计 **1890 → 497**）。
设置域的八个组件：`SettingRow` / `SettingsGeneral` / `SettingsModels` / `SettingsPlugins` /
`SettingsInventory` / `SettingsSkills` / `SettingsPresets` / `SettingsDevice`。
**P4-4 已落地**：设置页又拆出两个域组件 —— `view/SettingsGeneral.ets`（通用段 + 只读权限事实 + 本地调试入口）
与 `view/SettingsDevice.ets`（已记住的 Host + 关于本机）。**设置页 1890 → 760 行**（P4-1…P4-4 五轮合计），
拆分出的域组件：`SettingRow` / `SettingsModels` / `SettingsPlugins` / `SettingsInventory` / `SettingsGeneral` / `SettingsDevice`。

**P4-3b 已落地**：设置页最大的一块——**模型域**（提供方卡片 + 凭据联接 + 新会话默认 + 全量模型目录，
约 550 行）搬成 `view/SettingsModels.ets`（645 行），行渲染复用 `SettingRow`。
`SettingsPane` **1890 → 932 行**（P4-1…P4-3b 四轮合计）。

**P4-3a 已落地**：设置页最忙的一块——**设置行**（开关/单选/文本/结构编辑/恢复默认 + 值来源提示）
连同它的三个取值助手与**四个模块级函数**（官方中文措辞表）搬成 `view/SettingRow.ets`（300 行）；
通用段、预设段、以及下一步要拆的模型域都用它。`SettingsPane` 1694 → **1458 行**。

**P4-2 已开工**：设置页按域拆组件 —— 拆出 `view/SettingsPlugins.ets`（插件配置域）与
`view/SettingsInventory.ets`（只读清单域），正好对应 P4-1 刚分开的两个分区；
顺带删掉 52 行**零调用**的 `credentialsTab`（凭据早已并入模型段）与一处**重复渲染的摘要行**。
`SettingsPane` 1890 → **1698 行**。下一步拆最大的一块：模型域（≈400 行）。

**P4（设置域）已开工**：设置分区进了注册表（P4-1）——新增 `PanelLocation.SETTINGS` +
`settingsSections()`（8 项：官方四段**通用 / 模型 / 插件 / 插件清单**在前，本仓特有的
核心 / 预设 / 技能 / 设备标 `owner: 'hdsh'` 在后），与侧栏、右栏**共用同一套**
「清单 + 排序 + 可用性 + 切换器」机制；视图里的 `@State tab` 删除，唯一真值回到
`NavigationState.settingsSection`。「插件清单」从插件段的子页签**升级为独立分区**（官方口径）。
下一步：设置页按域拆组件（`SettingsPane` 1878 行，仍是最大的视图文件）。

**P3 收口**：右栏「**轨迹**」面板落地（P3-6）—— 时间总览抽成 `view/TimelineOverview.ets`，
主区轨迹视图与右栏**共用同一份**；右栏**只放总览不放全量台账**（官方右栏的 trajectory 是"当前回合的过程"，
而本仓 `TrajectoryItem` 没有回合字段 ⇒ 宁可少放一份，也不照抄主区台账）。
**官方右栏六个候选至此全部接上**（文件 / 预览 / 交付物 / 子代理 / 工具 / 轨迹）+ 本仓特有的「详情」= 七个面板；
`ConversationPane` 1714 → **1414 行**；下一个阶段是 **P4「设置」域**。

**P3-5 已落地**：右栏「**工具**」「**子代理**」面板 —— 工具卡抽成 `view/ToolCard.ets`（163 行，
含改动对照的那一整套判定，宿主只给数据 + 展开态 + 回调）、子代理卡抽成 `view/SubagentCard.ets`（40 行），
两者都与会话过程流**共用同一份**卡；`ConversationPane` 1714 → **1534 行**。
右栏可用面板六个（详情 / 文件 / 工具 / 子代理 / 交付物 / 预览），只剩「轨迹」内容未做。

**P3-4 已落地**：右栏「**交付物**」面板 —— 交付物卡从 `ConversationPane` 抽成 `view/DeliverableCard.ets`，
右栏面板与会话过程流**共用同一份**卡；筛选是**纯模型**（`itemsOfKind` / `deliverablesOf`：保序 +
**同 id 只留最后一条**——同一条会被流式 merge 多次，"有几件事"不能等于"更新了几次"）。右栏可用面板：详情 / 文件 / 交付物 / 预览。

**P3-3 已落地**：右栏「**文件**」面板 —— 文件树从 `WorkspacePane` 抽成 `view/FileTreePane.ets`，
右栏与工作区页签**共用同一份**（展开/选中/交付物标记/分档空态）；`WorkspacePane` 464 → **274 行**
（预览与文件树两轮搬出后，它退化成"列表 + 两个挂载点"的装配层）。右栏可用面板：详情 / 文件 / 预览。

**P3-2 已落地**：右栏「**预览**」面板 —— 预览呈现从 `WorkspacePane` 抽成 `view/FilePreviewPane.ets`，
右栏与工作区页签**共用同一份**（含空态与两档"看不了"的说明）；注册表里 `right.preview` 从此可用。
可用面板 ≥2 ⇒ 右栏标题行出现**切换器**（只在一个可用面板时不画，避免噪声）。

**P3（右栏）已开工**：右栏**按面板 id 分派**（P3-1）——`RightbarShell` 新增 `panelId`/`panelLabel`，
`selectedRightPanel` 这个在模型里躺了几轮的字段**第一次有了消费者**（此前视图无条件渲染 `DetailPane`，
那条"切右栏面板"的 fixture 断言其实与界面无关）。同时如实登记了缺口的真实位置：
官方六个候选（文件/轨迹/工具/子代理/交付物/预览）**席位在、内容视图没做** ⇒ 一律不可用（E110 口径，
避免"点进去是空面板"）；唯一有内容的是**新增的**「详情」面板（对应官方 `conversation.detail` 那一类，
**不冒充"文件"**）。下一步（P3-2）：「文件」「预览」两个面板——它们的素材与渲染都已在仓内，属搬家 + 接线。

**P2-3 已落地**：消息反馈面板拆成独立组件 `view/MessageFeedback.ets` ——
表单态（类别/说明）归组件，宿主只留"哪条开着 + 回执 + 提交策略"；
原先它与消息列表共用一个组件，**每敲一个字都会重绘整个会话列表**。
下一步：`ConversationShell` 继续拆（Header / Content / ProcessGroup / Answer）+ 消息操作条与长按菜单 + Tool Card
（⚠️ 观感与交互须真机确认：侧栏/抽屉见 D11·D12，**正文渲染与链接见 D13**）。

理由：功能不少、页面还是不像官方，根因是**信息架构没落地**——框架错则间距、颜色、Markdown 全白做。
故 Markdown 与视觉精修**排在框架之后**，而不是先做。

## 设计原则

1. **不 fork、不魔改 dsh**：端侧差异只通过 dsh 自己的组合面（profile / `cordis.patch.yml` / bundle）表达。
2. **不申请特殊权限**：需要 JIT、ACL 之类前提的方案一律不进入选型，以保证可正常上架。
3. **界面不撒谎**：失败必须给出下一步；空态说明"可以做什么"；不可用的动作把原因写在旁边，而不是给一个点了没反应的入口。
4. **上游知识只出现在 `dshcompat`**：字段名、端点形状、事件类型集中一处，升级上游时改一个地方。
5. **产品语义跟 Web，视觉与交互用鸿蒙原生**：信息架构与行为对齐官方 Web（对等矩阵逐行登记），
   但视觉不用 Web CSS 的像素级翻译——用系统语义色、系统符号、原生控件（Sheet/菜单）、触控目标与多窗口语义表达。
   这样官方主题更新时不需要重做整套界面。

## 许可

见 [`LICENSE`](LICENSE)。
