# HDSH —— 应用本体自足运行 DeepSeek Harness 的鸿蒙端

<img src="docs/brand/hdsh-icon.png" alt="HDSH 应用图标" width="112" align="right" />

面向 HarmonyOS（手机 / 折叠屏 / 平板 / 2in1）的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）端，**ArkTS + ArkUI 原生实现**。

> **它不是"PC 上 dsh 的遥控器"。** 应用**本体就是 DSH 的运行载体**：HAP 内自带 Node 运行时与 dsh 核心树，
> Host 起在本端 `127.0.0.1`，ArkUI 原生页面就是这个**本地** Host 的客户端页面；
> 并支持插件的增删启停与核心版本的安装 / 切换 / 回滚。
> 「连接远程 Host」保留为**可选能力**，不再是目标与验收口径。
>
> 目标与架构的权威说明见 **[`docs/50-端侧核心运行架构.md`](docs/50-端侧核心运行架构.md)（D6）**；
> 界面规范见 **[`docs/60-界面重塑-端侧核心.md`](docs/60-界面重塑-端侧核心.md)（D7）**。
> 与 D1（开发任务书）冲突处，以 D6/D7 为准——D1 的部分结论（把端侧 Host 列为非目标）已经过期。

## 为什么是端侧自足（三条事实变了）

| # | 事实 | 后果 |
|---|---|---|
| 1 | **Node.js 官方已支持 OpenHarmony**（`BUILDING.md` 平台表列 `OpenHarmony / arm64 / >= 5.0`；支持 PR [#58350](https://github.com/nodejs/node/pull/58350) 已合入 `main`） | "端侧没有 Node 运行时"这个前提不成立 |
| 2 | **dsh 的原生依赖已有鸿蒙移植**：`@ohos-ports/{koffi,node-pty,sharp}`、`@ohos-npm-ports/*`，甚至已有 `@ohos-ports/deepseek-ai-dsh` | "原生模块无 aarch64 产物 → 能力全缺失"这条反面对标的理由过期 |
| 3 | 端侧自足后**不存在跨设备传输层**：Host 与页面同进程走回环 | 旧方案最痛的"长连接周期性断开 / 转发不可靠 / 需要隧道"从关键路径消失 |

## 架构

```
┌─ HDSH（HAP）────────────────────────────────────────────────────────┐
│  页面层   ArkUI 原生：待决 / 会话 / 工作区 /【核心】/ 设置            │
│  状态层   appstate：单一连接与会话状态中枢（SessionHub）             │
│  协议层   connection + dshcompat：84 端点 / 4 流，漂移门禁保护        │
│  核心层   hostruntime：版本仓库 + 激活事务 + 运行时载体抽象 + 状态机   │
│  设备层   platform：通知 / 长时任务 / 剪贴板 / 分享 / 窗口 / 密钥存储  │
└────────────────────────────────────────────────────────────────────┘
        │ 进程内回环：POST /api/<endpoint> + WS /api/remote.mux
        ▼
   端侧 dsh Host（Node 运行时跑在本应用进程内）
     webserver(127.0.0.1) ├ /api ├ /api/remote.mux ├ $events
     DSH_HOME = <应用沙箱>/dsh/home（跨核心版本共享的唯一一份用户数据）
```

**同进程的好处不是"省事"，而是安全语义不用绕**：社区方案必须绑 `0.0.0.0` + 改写 `Host` 头才能穿过
鸿蒙的进程间 loopback 隔离；同进程不跨该边界，因此**不绑全网卡、不改信任头、不需要隧道**。

## 当前状态（据实，2026-09-12）

| 项 | 状态 |
|---|---|
| 目标与架构 | ✅ 已更正为端侧自足（D6），四项决策落定 |
| 界面 | ✅ 新增「核心」一级页面（阶段/运行时事实/版本/插件四分区）；会话空态按核心阶段分档 |
| 端侧核心树 | ✅ `tools/pack-core.mjs` 可产出鸿蒙形态核心包（zip 63.2 MB / 解包 207 MB；48 个原生 ELF 全部带 `.codesign`） |
| 核心版本管理 | ✅ `hostruntime` 的版本仓库与激活事务（stage→verify→health→activate→rollback）可编译 |
| **运行时载体** | ⏳ **未接线**——这是当前关键路径。阶段一（Electron-on-鸿蒙）缺华为侧产物；阶段二（自建 `libnode.so`）交叉编译已启动，见 `tools/node-runtime/` |
| 设备验收 | ⏳ 无活动设备；所有"真机可用"的结论都还没产生 |

> 界面上不写桩数据：运行时没接上就显示「未接线」，未探测的事实写「未探测 + 探测条件」，
> 不可用的动作把原因写在按钮下方。**"看起来正常"比"报错"更危险**，这一条在本项目已有过教训。

## 不变式（改代码前先看这四条）

1. **零上游 patch**：不 fork、不魔改 dsh；端侧差异只走它自己的组合面（profile / `cordis.patch.yml` / bundle）。
2. **不打洞**：默认只监听 `127.0.0.1`；不绑 `0.0.0.0`、不伪造 `Host`/`Origin`。
3. **不申请特殊权限**：各端一律按 **jitless** 运行，权限面只保留普通权限（网络 = `ohos.permission.INTERNET`），
   以确保顺利上架。任何"靠申请 JIT 类 ACL 权限才能成立"的方案都不进选型（D6 §4.4）。
4. **界面不说谎**：失败必须给出下一步；空态要说明"可以做什么"；未探测 ≠ 未知。

## 仓库结构

```
AppScope/        应用级配置（bundleName: com.hnmrxz.hdsh、图标、应用名）
entry/           HAP 入口：Ability、页面、10 个视图组件、形态适配
appstate/        状态与呈现契约：SessionHub（单一状态中枢）、Core（核心页契约，纯函数）、
                 ui/（断点导航、设计令牌、快捷键）
connection/      协议机制层：信封 / cookie / RemoteMux / EventStream / 退避（零 UI 依赖）
dshcompat/       **唯一的上游事实落点**：端点表、事件白名单、能力映射、版本矩阵
platform/        设备能力层：通知、长时任务、剪贴板、分享、文件选择、窗口与形态、密钥存储
hostruntime/ ★   端侧核心运行层：CoreStore（版本仓库 + 激活事务）、RuntimePort（载体抽象）、DshHost（状态机）
hostcore/        打包期配方与端侧 profile（core-recipe.json、profile/ondevice/）
tools/           协议与打包工具：pack-core.mjs（核心包）、node-runtime/（自建 Node 运行时）、
                 compat-drift.mjs（漂移门禁）、arch-check.mjs（架构回归门禁）、dev-host.mjs（远程 Host 调试）
hostkit/         可选的 PC 侧搭桥服务（仅在"连接远程 Host"这一可选路径下才需要）
docs/            文档基线（见下）
```

## 文档

| # | 文档 | 作用 |
|---|---|---|
| **D6** | [`50-端侧核心运行架构.md`](docs/50-端侧核心运行架构.md) | **先读这篇**：目标更正、目标架构、可行性证据、运行时路线与 JIT 决策、核心版本激活事务、指标与里程碑 |
| **D7** | [`60-界面重塑-端侧核心.md`](docs/60-界面重塑-端侧核心.md) | 界面重塑规范：新一级导航、核心页规格、"去掉无用功能"清单与去向 |
| D1 | [`00-开发任务书.md`](docs/00-开发任务书.md) | 开发任务书（**其"远程客户端"定位已被 D6 更正**） |
| D2 / D2b | [`10-协议兼容事实基线.md`](docs/10-协议兼容事实基线.md)、[`11-请求载荷契约.md`](docs/11-请求载荷契约.md) | 协议事实与载荷契约（含实测矩阵） |
| D3 / D3b | [`20-产品需求与体验规范.md`](docs/20-产品需求与体验规范.md)、[`12-设置页契约.md`](docs/12-设置页契约.md) | 体验规范与设置页契约 |
| D4 | [`30-技术验证清单.md`](docs/30-技术验证清单.md) | POC 清单（POC-11/12/13 是端侧运行时与 JIT 的门） |
| D5 | [`40-上游升级手册.md`](docs/40-上游升级手册.md) | 上游升级流程、漂移门禁、版本矩阵 |

## 构建与运行

| 项 | 值 |
|---|---|
| HarmonyOS SDK | **API 24（platformVersion 6.1.1）** —— 本机 DevEco 为 DS-243.24978.46.36.611300，其 hvigor 上限为 `modelVersion 6.1.1`；原声明的 API 26 在本机无法构建，已按此下调 |
| 包名 | `com.hnmrxz.hdsh` |
| 命令行工具 | `devecocli`、`ohpm`、`hdc` |

```sh
ohpm install --all                     # 依赖安装（首次或模块增删后）
devecocli build                        # 构建（产出未签名 HAP）
devecocli build --modules entry@ohosTest   # 单测目标（仅编译；执行需设备）
devecocli run                          # 构建 + 安装 + 启动（需设备）
```

**签名**：本仓库**不提交** `build-profile.json5` 的 `signingConfigs`。
DevEco 自动签名写进去的是机器绑定的绝对路径与加密口令，且它引用的
`.p12` / `.cer` / `.p7b` 在 `~/.ohos/config/` 下、**不在库内**——提交它既帮不了别人，
也会让 `build-profile.json5` 每次都被改脏。要装到真机时，用 DevEco 打开工程走一次
**自动签名**（File → Project Structure → Signing Configs → Automatically generate signature），
它会就地写回该文件；这一步是每台机器各自做一次的事。

**产出端侧核心包**（随应用分发的 dsh 核心树）：

```sh
node tools/pack-core.mjs               # 物化 → 裁剪 → 校验签名 → 打包（首次约 5 分钟）
node tools/pack-core.mjs --skip-install        # 复用已有 node_modules，秒级重打包
node tools/pack-core.mjs --place-in-app        # 额外把核心 zip 放进 entry 的 resfile（随 HAP 分发）
# 产物：dist/core/dsh-core-<ver>-openharmony-arm64.zip + .manifest.json
# （放 dist/ 而不是 build/：根 build/ 属于 HarmonyOS 构建，devecocli build 会清掉它）
```

**扫描端侧核心的插件与原生模块**（回答"哪些插件能运行时安装、发版风险面有多大"）：

```sh
node tools/scan-core-plugins.mjs       # 读真实核心树，不改任何东西
# 产物：dist/core/plugin-scan.json + plugin-scan.md（不进版本库，方法进库）
# 实测结论与两条方法纠正见 docs/50-端侧核心运行架构.md §6.2.1
```

**自建 Node 运行时**（阶段二关键路径，在 WSL2/Linux 里跑）：

```sh
bash tools/node-runtime/fetch-ohos-sdk.sh    # 匿名下载 OpenHarmony 公开 SDK（含 Linux NDK）
bash tools/node-runtime/build-node-ohos.sh   # 交叉编译 libnode.so + node（V8 很重）
bash tools/node-runtime/status.sh            # 看进展
```

## 可选：连接远程 Host

端侧自足之外仍保留这条路（例如手机连开发机上的 Host）：`node tools/dev-host.mjs` 会自己拉起一个
dsh 核心、建反连，并把地址与令牌经启动参数带进应用；跨设备可用 `hostkit/` 的加密隧道。
**注意**：这条路径不是目标，其"必须在另一台机器上跑 dsh"的前提也不再是验收口径。

## 在本仓库里做脚本化改动的两条硬约束

1. **不要用 `Get-Content -Raw` + `Set-Content` 往返改写源文件**：Windows PowerShell 5.1 默认按 ANSI/GBK
   读取、按 UTF-8 写回，会把中文注释全变成乱码。要改就用字面量替换的工具，或显式 `-Encoding UTF8`
   读 + `[System.IO.File]::WriteAllText` 以无 BOM UTF-8 写回。
2. **不要按进程名 kill**。本仓库的开发代理运行在 DSH 自身进程内，`Get-Process node | ... | Stop-Process`
   这类写法会杀掉代理自己。停后台任务用任务 id，停模拟器用 `devecocli emulator stop <name>`。

## 许可

[MIT](LICENSE)
