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
**页面选择已收成唯一真值**（`NavigationState.selectedMainPanel`，`NavTab` 退化为迁移期别名），
"此刻显示哪个面板"的组合逻辑也已收进纯模型（`activeMainPanelOf`）；
`AppShell` / `MainShell` 与"`Index` 不再负责页面级 Pane 选择"仍待完成
（机制已验 ⇒ 这一步现在可负担；⚠️ 运行时行为须真机确认，见 `docs/device-validation.md` D9）。

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
