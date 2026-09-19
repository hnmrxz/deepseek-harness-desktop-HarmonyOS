<div align="center">

<img src="docs/brand/hdsh-icon.png" alt="HDSH" width="112" />

# HDSH

**在 HarmonyOS 上自足运行 DeepSeek Harness 的应用**

</div>

HDSH 把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）的**运行本体**装进一个鸿蒙应用：HAP 内自带 Node 运行时与 dsh 核心树，核心在本机 `127.0.0.1` 上起 Host，应用内的原生 ArkUI 页面就是这个本地 Host 的客户端。

**它不是 PC 上 dsh 的遥控器**，也不需要在电脑上常驻任何服务：装上即用，数据只在本机应用沙箱内。支持 HarmonyOS 手机 / 折叠屏 / 平板 / 2in1。

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

不申请 JIT 权限意味着 Host 全程以 `--jitless` 运行，而 V8 的 `--jitless` 与 `--expose_wasm` **互斥** ⇒ 端侧 `typeof WebAssembly === 'undefined'`（恒定，不是配置问题）。由此推出一条对上游代码的判据：

> **凡是上游直接 `import('undici')` 的功能，在端侧都会失败**（undici 的 HTTP 解析器是 WASM）。

实测过的一个实例：`dsh-web-fetch-http` 不用全局 `fetch` 而自建 `Agent`，于是 `web_fetch` 打不开任何网页，而走纯 JS `node:http` 垫片的 `web_search` 照常工作 ⇒ 对付它需要**两层**，缺一层就会出现"Host 起来了、模型也能回话，但某个工具静默坏掉"：

| 层 | 做什么 | 不做的后果 |
|---|---|---|
| 全局 fetch 垫片（`fetch-shim.js`） | 用 `node:http/https` 重写 `fetch/Request/Response/Headers/FormData` | 调模型就走不通 |
| `undici` **模块名**解析钩子（`main.js` 的 `installUndiciNameHook()`） | 让上游的 `await import("undici")` 拿到同一个垫片 | **`web_fetch` 打不开任何网页** |

不改上游源码、不改核心树；由 `tools/check-web-fetch-jitless.mjs` 守着（自带对照实验：不注册钩子必须失败、注册后必须全过，且跨源跳转仍须被拒）。细节见 `docs/parity-matrix.md` §3.2。

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

构建、检查、发布与上架的完整口径见 [`docs/06-开发与发布指南.md`](docs/06-开发与发布指南.md) 与 [`docs/70-上架合规自查.md`](docs/70-上架合规自查.md)。

## 设计体系（P1.5：Web 语义 + HarmonyOS 原生表达）

**对标口径**：手机端对标 [DSH Mobile](https://github.com/sorsama/deepseek-harness-mobile) 的移动交互范式；PC/平板复刻对标 **dsh 官方最新原版**（官方 Web/Desktop，当前参考 `v37.2.3-20260825.1`）——信息架构与行为逐行对照（矩阵登记），**视觉与交互用 HarmonyOS 原生表达**，不是把 Web 的 CSS 机械翻译成 ArkUI（口径见 [`docs/01-产品与功能说明.md`](docs/01-产品与功能说明.md) §1.1）：

| 层 | 落点 | 作用 |
|---|---|---|
| 尺度原语 | `appstate/ui/Tokens.ets` | `Sp` / `Radius` / `Border` / `Fs` / `Sz` / `Dur`（"有哪些档位"） |
| 语义令牌 | `appstate/ui/HarmonyTheme.ets` | 角色 → 系统语义资源（`sys.color.*`）+ 排版成套角色 + 层级/动效/触控；**`WEB_TOKEN_MAP`** 逐条映射官方 `--dsw-*` |
| 原生原语 | `entry/src/main/ets/view/NativePrimitives.ets` | `NativeChip` / `NativeCard` / `NativeButton` / `NativeActionBar` / `NativeSectionTitle` + Sheet 参数助手 |

四条已经定下来的规则（都是踩过或查证后写的，不是偏好）：

1. **浮层用系统形态**：半模态一律 `bindSheet`（`harmonySheetOptions()` 统一参数），全应用只在**页面根**挂一次（`bindSheet` 是组件属性，同一节点只能绑一个）：`sheetKind()` 从既有状态派生显示哪个、`closeSheet()` 一处复位 ⇒ 结构上不可能同时开出两个浮层，复位也只写一次。
2. **遮罩交给系统**：不手写 `rgba(...)` 遮罩（35% 黑在深色主题下观感就是错的）。
3. **图标用系统符号**：`SymbolGlyph` 只支持系统预置资源，**不引入 Web SVG**（API 约束）。
4. **裸值只许变少**：`tools/check-design-tokens.mjs` 是棘轮门禁，管字号/圆角/描边/颜色字面量（含 `rgb()/rgba()/hsl()`——首版漏检过，已补）。

## 仓库结构

| 目录 | 作用 |
|---|---|
| `entry/` | 鸿蒙应用入口：ArkUI 页面与视图（含**原生原语** `view/NativePrimitives.ets`）、原生桥（`libdshhost`）、随包资源（核心包与原生库） |
| `hostcore/` | 端侧 Host 的入口脚本与 profile（`cordis.patch.yml`）、`fetch` 垫片、`undici` 模块名解析钩子（见上文 jitless 一节） |
| `hostruntime/` | 核心版本仓库、激活事务、运行时载体（`RuntimePort` → `NodeRuntime`） |
| `appstate/` | 客户端状态中枢（`store/SessionHub`）与**纯逻辑**：导航/布局/断点决策、回合与轨迹模型、工具呈现、失败文案、脱敏、目标、产出文件等——零依赖，可在本机直接测（断言见 `docs/05`） |
| `platform/` | 系统能力封装（文件选择、剪贴板、通知、窗口记忆等） |
| `dshcompat/` | 与上游协议有关的**全部**事实：端点、参数形状、事件类型与投影键 |
| `tools/` | 构建与检查脚本（核心打包、依赖闭包、上架红线、协议往返、死代码与接线门禁等） |
| `docs/` | 文档基线，索引见 [`docs/README.md`](docs/README.md) |

## 当前状态

**阶段**：P8/P9 收口后进入设备复验。信息架构骨架（`AppFrame → Sidebar → Main → Rightbar → Settings 域`）与四形态轨道已落地；近十四轮成果（返回层级、分享、滚动位置、`@` 引用钻取、命令分流、灯箱、错误生命周期、每会话草稿、重试链、敏感内容隔离等）逐轮索引见 [`docs/13-缺陷编年.md`](docs/13-缺陷编年.md)。

- **能力对等唯一清单**：[`docs/parity-matrix.md`](docs/parity-matrix.md)（由 `tools/check-parity.mjs` 强制）；**权威状态结论**：[`docs/07-当前状态与缺口.md`](docs/07-当前状态与缺口.md)。
- **设备验收**：2026-09-16/17 在 HUAWEI Mate 70 Pro+ 跑过一轮，抓出 32 条缺陷；当前 **已修已验 6 / 已修待验 16 / 部分已修 2 / 待定位 1 / 待修 1 / 核心版本不具备 4**（定时任务、取消归档、撤销、待决跨重启——已核实无端点，**不造假入口**）。修法见 [`docs/80-修复与优化方案.md`](docs/80-修复与优化方案.md)，复验清单见 [`docs/81-待真机复验清单.md`](docs/81-待真机复验清单.md)。
- **本仓库不宣称"已通过设备验收"**：上面 16 条"已修待验"还没在设备上复核。

## 文档

从 [`docs/README.md`](docs/README.md)（总索引与阅读顺序）进入。最常用的四份：

1. [`docs/01-产品与功能说明.md`](docs/01-产品与功能说明.md) —— 产品是什么、做什么、不做什么。
2. [`docs/02-开发计划.md`](docs/02-开发计划.md) —— 当前阶段与实施顺序（开发代理的执行入口）。
3. [`docs/03-技术架构与模块.md`](docs/03-技术架构与模块.md) + [`docs/04-HarmonyOS多端UI设计规范.md`](docs/04-HarmonyOS多端UI设计规范.md) —— 代码放哪里、UI 怎么做。
4. [`docs/05-验证与验收.md`](docs/05-验证与验收.md) —— 无设备时做到哪一层、什么时候必须上设备。

## 设计原则

1. **不 fork、不魔改 dsh**：端侧差异只通过 dsh 自己的组合面（profile / `cordis.patch.yml` / bundle）表达。
2. **不申请特殊权限**：需要 JIT、ACL 之类前提的方案一律不进入选型，以保证可正常上架。
3. **界面不撒谎**：失败必须给出下一步；空态说明"可以做什么"；不可用的动作把原因写在旁边，而不是给一个点了没反应的入口。
4. **上游知识只出现在 `dshcompat`**：字段名、端点形状、事件类型集中一处，升级上游时改一个地方。
5. **产品语义按形态对标**：手机对标 DSH Mobile 的移动交互范式，PC/平板复刻官方 Web 的信息架构与行为（矩阵登记）；视觉不用 CSS 的像素级翻译——用系统语义色、系统符号、原生控件与多窗口语义表达，官方主题更新时无需重做界面。

## 许可

见 [`LICENSE`](LICENSE)。
