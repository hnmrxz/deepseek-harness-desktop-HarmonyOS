<div align="center">

<img src="docs/brand/hdsh-icon.png" alt="HDSH" width="112" />

# HDSH

**在 HarmonyOS 上自足运行 DeepSeek Harness 的应用**

</div>

HDSH 把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）的**运行本体**装进一个鸿蒙应用：HAP 内自带 Node 运行时与 dsh 核心树（当前 **0.1.6-alpha.2**），核心在本机 `127.0.0.1` 上起 Host，应用内的页面就是这个本地 Host 的客户端。

**它不是 PC 上 dsh 的遥控器**，也不需要在电脑上常驻任何服务：装上即用，数据只在本机应用沙箱内。支持 HarmonyOS 手机 / 折叠屏 / 平板 / 2in1。

---

## 能力

| 领域 | 说明 |
|---|---|
| **本地核心** | 内置 Node 运行时（自建、`jitless`）与 dsh 核心树 0.1.6-alpha.2（随包 zip 约 68.8 MB，resfile 仅此一个）；Host 仅监听 `127.0.0.1`，随应用生命周期起停 |
| **双形态界面** | 按窗口宽度路由（`600vp` 分界）：**桌面态**（平板 / 2in1 / 折叠展开）用 `WebShell` **直载官方 Web UI**——与官方同一前端产物，全部官方界面能力开箱即得；**手机态**（手机 / 折叠闭合）用 `RemoteShell` 以 DSH Mobile 的移动范式**原生复刻**（ArkTS + `MobileTheme` 令牌 + `Ds*` 基元） |
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
│  客户端页面（pages/Index.ets 按形态 × 模式矩阵路由）              │
│    · DESKTOP_LIKE（≥600vp）→ WebShell：直载官方 Web UI          │
│    · PHONE（<600vp）       → RemoteShell：原生复刻 DSH Mobile   │
│        │  HTTP /api/*        WebSocket /api/remote.mux          │
│        ▼                                                        │
│  端侧 dsh Host（Node 运行时运行在**本应用进程内**，               │
│                以 --jitless --expose-internals 启动）            │
│        │  DSH_HOME = <应用沙箱>/dsh/home（跨版本共享的唯一数据）  │
│        ▼                                                        │
│  核心版本仓库（多个版本可并存，切换 = 停旧 + 起新 + 校验）        │
└─────────────────────────────────────────────────────────────────┘
```

同进程带来的是**安全语义的简化**：客户端与 Host 走回环，不需要把服务暴露到局域网，也不需要跨设备转发。

### 0.1.6-alpha.2 的端侧适配要点（v3 升级，2026-09-20/21）

| 事项 | 事实 |
|---|---|
| 新硬原生依赖 | 0.1.6 新增 `node-addon-require-builtin`（dsh-app-boot 的 profile resolution 必经路径）。打包期垫片把它替换为 `createRequire` 直通；**宿主 argv 必带 `--expose-internals`**（由 `RuntimePort.buildHostArgv` 加入），缺它 Host 起不来（fail-loud） |
| 端侧 preset | 0.1.6 的 standard preset 新增 PTC 工作流链（端侧必挂），`ondevice` preset 现禁用**五行**：`tool-bash` / `tool-pwsh` / `tool-fs-search` / `workflow-ptc` / `tool-workflow`（preset mount 仍是全有或全无） |
| boot 语义 | host 侧 boot 对 pending 行从 fail-loud 改为**警告不失败**。端侧实测 pending 四条：`ptc-runtime` / `terminal-controller` / `ui-deliverables` / `workspace-changes`，根都在 `subprocess`/`sandbox` 被禁（手机无进程创建能力，上游硬约束） |
| 协议面 | 端点 84 → **109**（+25 全为增量：`agentTeams`×3 / `officeToPdf`×2 / `permissionPresets`×1 / `pluginManager`×8 / `terminal`×10 / `workspace unarchiveSession`×1），既有端点 wire 参数零漂移；转发事件白名单 19 → **23**（新增 4 条仅登记不投影） |
| 工作区写入 | 0.1.6 的 `dsh-fs-local` `writeFileAtomic` 形态未变——本仓 `link()` 被沙箱拒后的降级垫片（`installLinkFallback`）继续覆盖"新建 = `COPYFILE_EXCL`、覆盖 = `rename`"两语义；工作区链路逐段核对零漂移 |

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
（仅用于仓库内的构建与检查脚本；**门禁/工具链指定 `D:\nodejs\node.exe`（v24）**——系统默认的旧版 Node 跑不动相关脚本）。

> **SDK 版本口径**：`compatibleSdkVersion` / `targetSdkVersion` 固定为 **`6.1.1(24)`**（决策，2026-09-14）。
> 代价是**不能用 API 26 的「沉浸光感」材质**（官方要求 `targetAPIVersion ≥ 26`）——
> 界面层次当前由系统阴影表达；升级路径与要改的几处列在 `appstate/ui/HarmonyTheme.ets` 的 `HarmonyMaterial`。

**不入库的产物（新克隆必须先备齐，否则编不过）**：

| 产物 | 路径 | 说明 |
|---|---|---|
| Node 头文件 | `entry/src/main/cpp/node-headers/` | 编 `libdshhost` 只需要它（`libnode` **不参与链接**） |
| 原生库 | `entry/libs/<abi>/` | 运行期需要（含 `libnode.so.127`）；也是"编不编 koffi/flock"的门 |
| 核心包 | `entry/src/main/resources/resfile/dsh-core-0.1.6-alpha.2-openharmony-arm64.zip` | 首启解包出端侧核心树；**resfile 仅此一个 zip**（约 68.8 MB，rc.2/rc.3 旧包已移除） |
| 入口脚本 | `entry/src/main/resources/resfile/resources/app/` | 由 `node tools/place-host-app.mjs` 从 `hostcore/app/` 生成 |

```bash
# 1) 打完整体（HAP + 原生库 + 内置核心资源）
devecocli build

# 2) 需要重新打包核心树时（素材来自 dist/core/，产物落到应用资源目录）
node tools/pack-core.mjs --skip-install --place-in-app
node tools/place-host-app.mjs        # 改过 hostcore/app/* 后必须重放（check-host-app-fresh 守着）

# 3) 安装到已连接设备（注意：产物是 **unsigned**；签名材料不在库内）
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

构建、检查、发布与上架的完整口径见 [`docs/06-开发与发布指南.md`](docs/06-开发与发布指南.md) 与 [`docs/70-上架合规自查.md`](docs/70-上架合规自查.md)。

## 设计体系（v2：桌面直载官方 Web · 手机原生对照复刻）

**对标口径**：按形态分流，不做同一种界面的两份实现——

- **桌面态（`DESKTOP_LIKE`，≥600vp：平板 / 2in1 / 折叠展开）**：`WebShell` 用 ArkWeb `Web` 组件**直载官方 Web UI**（本机 `http://127.0.0.1:<port>`；远程模式加载远程主机地址）。与官方**同一前端产物**，信息架构、多栏布局、快捷键全部由官方自带，不存在"复刻漂移"。
- **手机态（`PHONE`，<600vp：手机 / 折叠闭合）**：以 DSH Mobile（Kotlin + Compose）源码为**唯一参照逐屏原生复刻**。设计链三层：

| 层 | 落点 | 作用 |
|---|---|---|
| 移动令牌 | `appstate/ui/MobileTheme.ets` | DSH Mobile `ui/theme/*.kt` **逐值移植**（色板/间距/圆角/字号/动效，明暗两套）；手机链唯一 token 源 |
| 原生原语 | `entry/src/main/ets/view/NativePrimitives.ets` | **`Ds*` 基元族**（`DsButton` / `DsCard` / `DsPill` / `DsSegmented` / `DsSheetHeader` / `DsEmptyHero` / `DsDisclosureRow` / `DsToggleRow` 等，对照 DSH Mobile `ui/components/`） |
| 共用令牌 | `appstate/ui/HarmonyTheme.ets` + `Tokens.ets` | 未迁移的共用组件继续消费（含排版角色、层级、触控目标） |

四条已经定下来的规则（都是踩过或查证后写的，不是偏好；**七项门禁棘轮**负责让它们不回退）：

1. **浮层用系统形态**：半模态一律 `bindSheet`（`harmonySheetOptions()` 统一参数），全应用只在**页面根**挂一次（`bindSheet` 是组件属性，同一节点只能绑一个）：`sheetKind()` 从既有状态派生显示哪个、`closeSheet()` 一处复位 ⇒ 结构上不可能同时开出两个浮层，复位也只写一次。
2. **遮罩交给系统**：不手写 `rgba(...)` 遮罩（35% 黑在深色主题下观感就是错的）。
3. **图标用系统符号**：`SymbolGlyph` 只支持系统预置资源，**不引入 Web SVG**（API 约束）。
4. **裸值只许变少**：`tools/check-design-tokens.mjs` 是棘轮门禁，管字号/圆角/描边/颜色字面量（含 `rgb()/rgba()/hsl()`——首版漏检过，已补）；基线只降不升，豁免须写明理由（`// token-exempt: …`）。

## 仓库结构

| 目录 | 作用 |
|---|---|
| `entry/` | 鸿蒙应用入口：形态路由（`pages/Index.ets`）、`WebShell` / `RemoteShell` 与全部视图（含 `Ds*` 原生原语）、原生桥（`libdshhost`）、随包资源（核心包与原生库） |
| `hostcore/` | 端侧 Host 的入口脚本与 ondevice profile（`cordis.patch.yml`）、`fetch` 垫片、`undici` 模块名解析钩子、`link()` 降级与 0.1.6 的 `--expose-internals` 前置检查（见上文两节） |
| `hostruntime/` | 核心版本仓库、激活事务、运行时载体（`RuntimePort` → `NodeRuntime`，argv 含 `--jitless --expose-internals`） |
| `appstate/` | 客户端状态中枢（`store/SessionHub`）与**纯逻辑**：导航/布局/断点决策、回合与轨迹模型、工具呈现、失败文案、脱敏、目标、产出文件等——零依赖，可在本机直接测（断言见 `docs/05`） |
| `platform/` | 系统能力封装（文件选择、剪贴板、通知、窗口记忆等） |
| `dshcompat/` | 与上游协议有关的**全部**事实：端点表（109 端点，自动生成）、参数形状、转发事件白名单（23 条）与投影键 |
| `tools/` | 构建与检查脚本（核心打包、依赖闭包、协议探测与漂移门禁、七项质量门禁、死代码与接线检查等） |
| `docs/` | 文档基线，索引见 [`docs/README.md`](docs/README.md) |

## 当前状态

**阶段**：v3 周期（核心升级 0.1.6-alpha.2）实现侧收口完成（2026-09-21，T001-T018），待 Phase 9 端侧验证。

- **v3 已完成（代码层 + 本机可验层）**：核心物化/打包全绿（补丁逐锚点适配，无静默跳过）；本机核心回路 22/22（boot 序列、会话闭环、文件变更流）；协议探测 18 项全预期形态、契约基线 109 端点零漂移；设置存储逐包对比零不兼容（新增 `dshCachePath` 为纯增量）；Web UI 设置项核查清单就绪（[`docs/14-设置项核查清单.md`](docs/14-设置项核查清单.md)，31 项待走查）。
- **待端侧验证（Phase 9，如实列出）**：模型回合流式增量、图片内联显示、preset 在实际会话中的工具面、真机四步文件链（新建→读取→覆盖→列目录）、设置项逐项"改→存→重启→读回"、手机链一轮会话回归；v2 遗留验收一并回归：形态路由矩阵（PHONE/DESKTOP_LIKE × 本机/远程/诊断）、删除收敛后页面无死链、WebShell 直载官方 UI。
- **已登记的 v3 缺口**（详见 [`docs/07-当前状态与缺口.md`](docs/07-当前状态与缺口.md)）：`permissionPresets/catalog` 在 ondevice profile 下 404；Web UI 的交付物/变更面板（`ui-deliverables`）端侧从未激活（pending，桌面特性）；4 条新增转发事件仅登记不投影；PTC 工作流（`workflow-ptc`/`tool-workflow`）端侧禁用。
- **能力对等唯一清单**：[`docs/parity-matrix.md`](docs/parity-matrix.md)（52 行 = DONE 41 · PARTIAL 5 · BOUNDARY 4 · TODO 2，由 `tools/check-parity.mjs` 强制）；**权威状态结论**：[`docs/07-当前状态与缺口.md`](docs/07-当前状态与缺口.md)。
- **本仓库不宣称"已通过设备验收"**：设备验证轴整体 `PENDING`，v2 遗留的"已修待验"条目与 v3 新增项统一归 Phase 9。

## 文档

从 [`docs/README.md`](docs/README.md)（总索引与阅读顺序）进入。最常用的四份：

1. [`docs/01-产品与功能说明.md`](docs/01-产品与功能说明.md) —— 产品是什么、做什么、不做什么（§1.1 双形态对标基线）。
2. [`docs/02-开发计划.md`](docs/02-开发计划.md) —— 当前阶段与实施顺序（开发代理的执行入口）。
3. [`docs/03-技术架构与模块.md`](docs/03-技术架构与模块.md) + [`docs/04-HarmonyOS多端UI设计规范.md`](docs/04-HarmonyOS多端UI设计规范.md) —— 代码放哪里、手机原生链的 UI 怎么做。
4. [`docs/05-验证与验收.md`](docs/05-验证与验收.md) —— 无设备时做到哪一层、什么时候必须上设备。

## 设计原则

1. **不 fork、不魔改 dsh**：端侧差异只通过 dsh 自己的组合面（profile / `cordis.patch.yml` / bundle）与运行期垫片（入口脚本）+ 打包期补丁层表达；上游源码零改动。
2. **不申请特殊权限**：需要 JIT、ACL 之类前提的方案一律不进入选型，以保证可正常上架。
3. **界面不撒谎**：失败必须给出下一步；空态说明"可以做什么"；不可用的动作把原因写在旁边，而不是给一个点了没反应的入口；能力边界（如端侧 pending 的行）如实呈现。
4. **上游知识只出现在 `dshcompat`**：字段名、端点形状、事件类型集中一处，升级上游时改一个地方。
5. **产品语义按形态对标**：手机态对照 DSH Mobile 的移动交互范式逐屏复刻，桌面态直接加载官方 Web 产物（不维护第二份桌面界面）；信息架构与行为的对等以 `parity-matrix.md` 逐行登记，视觉用系统语义色、系统符号与原生控件表达。

## 许可

见 [`LICENSE`](LICENSE)。
