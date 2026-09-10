# DeepSeek Harness 鸿蒙客户端

面向 HarmonyOS（手机 / 折叠屏 / 平板 / 2in1 PC）的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）一等客户端，**ArkTS + ArkUI 原生实现**。

> **当前进度**：**全部界面开发完成**（M1/M2/M3 界面部分）+ **设备能力层** + **真实数据接线核心** + **上游基线已升级到 `0.1.5-rc.1`**。
>
> - **界面**：三形态导航与让步链、待决聚合、会话列表、会话轨迹与输入区、详情栏、
>   工作区与文件预览、设置五页签、连接诊断、添加 Host —— 共 9 个视图组件，全部建成。
> - **设备能力层**（`platform` HAR）：通知与三类渠道、长时任务保活、剪贴板、系统分享、
>   设备形态事实、窗口几何记忆、进程级运行时身份与窗口台账。
> - **真实数据接线**（`appstate/store/SessionHub.ets`）：全应用**单一** mux 连接 +
>   单一 `$events` + 单一 `session/control` + 单一 `session/follow`（D1 §7.7.5b），
>   含待发队列、离线降级、未识别上游事件的自证汇总。
> - **上游兼容面**：基线由 `0.1.2-rc.1`（74 端点）升级到 **`0.1.5-rc.1`（84 端点）**，
>   新增 `workspaceFiles/*`、`fileUploads/upload`、`goals/get`、`sessionFeedback/record` 四个能力域；
>   漂移门禁绿、负测试通过。
>
> **验证状态**：主构建与 `entry@ohosTest` 目标编译通过；三道门禁为绿
> （漂移门禁 + 架构回归门禁 + hostkit 的 295 项测试）；
> 已对**真实 `0.1.5-rc.1` Host** 完成两轮只读实测（含 mux 帧、`$events` ready、
> `session/control` baseline、`session/follow` snapshot、`session/page`、会话列表真实字段全集），
> 结论逐条落在 [`docs/10-协议兼容事实基线.md`](docs/10-协议兼容事实基线.md) §8.7。
>
> **设备侧**：API 26 手机模拟器上已完成构建 → 安装 → 启动 → 渲染与交互验收
> （单栏形态、会话列表状态徽标、待决聚合、**危险动作权重反转**逐条通过），
> 并已让应用在设备上真的连上宿主 Host：认证、mux、`$events`、控制流全部走通。
> **但 `session/list` 解析与 `$events` 长连接在经 `hdc rport` 时失败**——
> 有反证表明这是转发通道的问题而非协议栈（同样调用从宿主直连全部成功）。
> 详细结论与最小后续实验见
> [`docs/30-技术验证清单.md`](docs/30-技术验证清单.md) 的「设备 ↔ Host 端到端验证」。
>
> **仍待真机/设备的项**：轨迹内容事件（消息/思考/工具调用）的 `data` 内部字段名、
> `workspaceFileScopeId` 的来源、`agentId` 与会话 id 的关系、2in1 快捷键与多窗口的实机行为、
> 通知送达与点击直达。逐项列在
> [`docs/30-技术验证清单.md`](docs/30-技术验证清单.md) 的「界面完成度对照」与 POC 跟踪表。

## 核心主张

1. **原生而非套壳** —— ArkUI 原生渲染 + 原生协议客户端（`POST /api/<endpoint>` + `/api/remote.mux`），无浏览器内核、无端侧 Node 运行时。
2. **全形态而非只做 PC/平板** —— 手机竖屏单手可用、折叠屏展开秒变双栏、平板/2in1 多窗口 + 键鼠 + 拖拽。
3. **接入而不打洞** —— 不绑 `0.0.0.0`、不改写 `Host`/`Origin`、**0 个上游 patch**；跨设备访问走显式配对 + 加密隧道，隧道出口仍在 Host 的 loopback 上，因此上游安全围栏天然满足。
4. **升级友好** —— 上游接口细节只允许出现在 `dshcompat` 一处，配一个**会真的失败**的漂移门禁（详见下方）。

## 与参考项目的关系

| 项目 | 关系 |
|---|---|
| [`deepseek-ai/deepseek-harness/apps/desktop`](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/desktop/README.zh.md) | 官方 Electron 桌面壳。本项目借鉴其**架构决策与工程纪律**（发布身份、状态归属、激活事务、真机验收），不复制其形态与运行时 |
| [`fellow99/deepseek-harness-harmony`](https://github.com/fellow99/deepseek-harness-harmony) | 社区 Electron-on-鸿蒙移植（真机已跑通）。本项目以其为**反面对标**：换掉 172.7 MB 运行时与 143 MB 启动解压、去掉全部上游 patch、不再绑 `0.0.0.0`、补回终端/沙箱/图片管线能力、并把手机纳入一等目标 |

## 仓库结构

```
.
├── AppScope/                 # 应用级配置与资源（bundleName、图标、应用名）
├── entry/                    # HAP 入口：Ability、AbilityStage、页面、视图、形态适配
│   └── src/
│       ├── main/ets/
│       │   ├── abilitystage/     # specified 启动模式的实例 key（多窗口归属）
│       │   ├── entryability/     # UIAbility：窗口登记、几何记忆、启动参数下发
│       │   ├── pages/Index.ets   # 应用首屏：三形态导航 + 让步链 + 全部页面装配
│       │   ├── pages/Poc1.ets    # POC-1 协议往返验证页（验收工具）
│       │   └── view/             # 全部界面组件（9 个，见下）
│       └── ohosTest/             # 单元测试（Hypium，约 60 条断言）
├── platform/                 # HAR：**设备能力层**（机制，零 UI、零上游知识）
│   └── src/main/ets/
│       ├── notify/           # 通知发布/撤回/去重键 + 三类渠道 + 长时任务保活
│       ├── system/           # 剪贴板、系统分享、设备与形态事实
│       ├── window/           # 多窗口开启与路由参数、窗口几何/布局记忆
│       └── runtime/          # 进程级 runtimeId + 窗口台账（§7.7.5b 的可核查证据面）
├── connection/               # HAR：协议**机制层**（零 UI 依赖，不含具体端点/字段名）
│   └── src/main/ets/protocol/
│       ├── Surface.ets       # 注入式「上游接口面」定义（路径等事实由 dshcompat 提供）
│       ├── RpcTypes.ets      # endpoint 校验、RemoteFailure、RpcResult
│       ├── Envelope.ets      # 一元信封构造/解析
│       ├── HostAddress.ets   # 地址规范化、authority、loopback 判定
│       ├── Cookies.ets       # Set-Cookie 多形态解析 + 按 authority 隔离的 CookieJar
│       ├── HttpClient.ets    # @ohos.net.http 载体
│       ├── AuthSession.ets   # token → 签名 cookie、401 重绑、403 信任栅栏诊断
│       ├── RemoteMux.ets     # 逻辑流复用 + 心跳 + `item`/`error`/`end` 三态帧
│       ├── EventStream.ets   # 事件流、ready 首项、generation 失效
│       ├── Backoff.ets       # 500ms→10s 退避 + 抖动
│       └── Connection.ets    # 门面 + 五项连接诊断
├── dshcompat/                # HAR：**DSH 上游兼容面（唯一的上游事实落点）**
│   └── src/main/ets/
│       ├── Endpoints.ets     # 端点上表（自动生成，84 条，含参数形态与流式标记）
│       ├── Surface.ets       # 载体路径 / 事件流端点 / 开流 payload
│       ├── Aliases.ets       # 字段别名表 + endpoint 常量 + **参数改名别名（PARAM_ALIASES）**
│       ├── RemoteEvents.ets  # **转发事件白名单 + 审批/提问词汇 + 投影键**
│       ├── CompatIndex.ets   # 能力映射 + 版本矩阵 + 参数构造 + 能力判定
│       └── CompatTypes.ets   # 兼容面类型
├── appstate/                 # HAR：状态层（投影 / 派生 / 呈现契约；零 UI 依赖）
│   ├── store/SessionHub.ets  # **单一连接与会话状态中枢**（D1 §7.7.5b）
│   ├── model/SessionList.ets # 会话列表投影（标题走 `projections.values.title`）
│   ├── model/Trajectory.ets  # 轨迹与待决的**呈现层契约**
│   ├── model/Workspace.ets   # 工作区/文件树/预览的呈现契约（含预览类型推导）
│   ├── model/Settings.ets    # 设置/凭据/插件/Host/诊断/模型 的呈现契约
│   ├── model/Present.ets     # 呈现层纯函数（相对时间 / 截断 / 排序 / 朗读文本）
│   ├── model/Notify.ets      # 通知策略（D3 §6 六类 + 内容纪律 + 去重/撤回键）
│   ├── model/Wire.ets        # 请求构造器 + 回复投影（端点名一律取自 dshcompat）
│   ├── model/StubData*.ets   # 桩数据源（无 Host 时驱动界面）
│   └── ui/                   # 断点与导航模型、设计令牌、2in1 快捷键表
├── entry/src/main/ets/view/  # 全部界面组件（9 个）
│   ├── ConversationPane.ets  # 会话轨迹（7 类条目）+ 输入区
│   ├── Composer.ets          # 输入区：@引用 / 斜杠命令 / 附件 / 模型 chip / 离线排队
│   ├── DetailPane.ets        # 详情栏：工具 / 子代理 / 交付物 / 目标 / 任务
│   ├── SessionListPane.ets   # 会话列表（运行中/待审核/空闲/失败 状态徽标）
│   ├── PendingPane.ets       # 待决聚合（审批三选 / 提问单选与多选 / 自由文本）
│   ├── WorkspacePane.ets     # 工作区 → 文件树 → 文件预览（宽屏三列、窄屏栈式）
│   ├── SettingsPane.ets      # 设置五页签：通用 / 模型 / 凭据 / 插件 / 设备
│   ├── DiagnosticsPane.ets   # 连接诊断：五项判定 + 兼容面自检 + 旁路日志
│   └── ConnectPane.ets       # 添加 Host：URL / 手输 / 发现 / 授权 / 安全说明
├── hostkit/                  # PC 侧搭桥服务（Node，独立可发布，**可选组件**）
│   ├── src/core/             # 配对、设备白名单、E2E 加密帧、隧道、审计、Host 守护
│   ├── src/platform/         # 平台相关隔离（Windows / macOS / Linux）
│   └── test/                 # `node --test`，含隧道端到端测试
├── tools/                    # 协议与兼容面工具（Node，独立于应用）
│   ├── protocol-contract.mjs    # 从生成描述符提取调用契约（并写自描述元数据）
│   ├── gen-compat-endpoints.mjs # 由契约生成 dshcompat 端点上表（支持跨版本生成）
│   ├── compat-drift.mjs         # **上游漂移门禁**（支持版本间比对，有漂移则非零退出）
│   ├── arch-check.mjs           # **架构回归门禁**（注释感知 + 内置注入式自检）
│   ├── protocol-enum*.mjs       # endpoint 枚举（历史工具）
│   └── protocol-probe.mjs       # 对真实 Host 做只读探测 → 可用性与错误码矩阵
└── docs/                     # 文档基线（D1~D5）
```

## 文档

入口：[`docs/README.md`](docs/README.md)

| 文档 | 作用 |
|---|---|
| [`docs/00-开发任务书.md`](docs/00-开发任务书.md) | **开发任务书 D1**：背景与对标、目标、架构（含安全分级 L0/L1/L2）、功能需求、POC 门、里程碑、验收体系、风险与待决事项 |
| [`docs/10-协议兼容事实基线.md`](docs/10-协议兼容事实基线.md) | 协议事实基线 D2：载体与端点、认证与信任、连接生命周期、**§8 实测矩阵**（§8.7 = 0.1.5-rc.1 实测 + 本仓库缺陷修正 + 门禁升级） |
| [`docs/11-请求载荷契约.md`](docs/11-请求载荷契约.md) | **载荷契约 D2b**：84 个端点的请求内层字段与回复结构、6 条事件流的逐项结构、审批/提问应答编码、未确认清单（每行带上游源码出处） |
| [`docs/20-产品需求与体验规范.md`](docs/20-产品需求与体验规范.md) | 体验规范 D3：信息架构、三形态导航、界面规格、通知、无障碍、视觉 |
| [`docs/30-技术验证清单.md`](docs/30-技术验证清单.md) | 技术验证清单 D4：POC-1~11 的判定与止损 |
| [`docs/40-上游升级手册.md`](docs/40-上游升级手册.md) | **上游升级手册 D5**：分层前提与评审检查表、五步升级流程、漂移门禁、降级策略、版本矩阵 |

## 怎么应对 DSH 上游升级

核心约束：**上游接口细节只允许出现在 `dshcompat` 一处**。`connection` 只提供机制（载体/信封/cookie/退避），
`appstate` 与 UI 只认呈现层契约。上游改动全部落在 `dshcompat`，其余三层零改动。

```sh
# 1) 提取新上游的调用契约（每个 endpoint 的参数形态、流式标记、可否取消）
#    同时写出一份「自描述元数据」，下游工具据此报版本，不靠猜
node tools/protocol-contract.mjs --json .research/protocol/contracts.json

# 2) 漂移门禁：与已提交基线逐条比对，有差异则非零退出并给出精确差异
node tools/compat-drift.mjs

# 3) 重新生成端点上表（必要时同步调整能力映射）
node tools/gen-compat-endpoints.mjs

# 4) 对真实 Host 复跑只读探测，确认端点可用性与错误码语义
node tools/protocol-probe.mjs --base http://127.0.0.1:3111 --token <token>
```

**版本间比对**（升级评估时最常用，不需要改动机器上装的 dsh）：

```sh
# 把任意版本的契约装到隔离目录
npm install --prefix .research/upstream-0.1.5 "@deepseek-ai/dsh@0.1.5-rc.1"

# 用目标版本的契约重生成上表
DSH_NODE_MODULES=.research/upstream-0.1.5/node_modules \
  node tools/protocol-contract.mjs --json .research/protocol/contracts.json
node tools/gen-compat-endpoints.mjs

# 或者：只算「A 版本 → B 版本差了什么」，不动仓库文件
DSH_CONTRACTS=.research/protocol/contracts-0.1.2-rc.1.json node tools/compat-drift.mjs
```

配套的**架构回归检查**（期望无输出、exit 0）：

```sh
node tools/arch-check.mjs --self-test   # 先证明门禁有效（8 个正/负样例）
node tools/arch-check.mjs
```

配套的**门禁负测试**（期望非零退出——证明门禁真的会失败）：

```sh
DSH_CONTRACTS=.research/protocol/contracts-0.1.2-rc.1.json node tools/compat-drift.mjs; echo "exit=$?"
```

完整流程、降级策略、版本矩阵维护与「门禁必须经负测试验证」的纪律见
[`docs/40-上游升级手册.md`](docs/40-上游升级手册.md)。

## 开发

### 环境要求

| 项 | 版本 |
|---|---|
| DevEco Studio | DS-261.23567.138.36.2600821（或兼容版本） |
| HarmonyOS SDK | API 26（`platformVersion 26.0.0`） |
| Node.js | ≥ 22（仅 `tools/` 下的协议工具需要） |
| 命令行工具 | `devecocli`（DevEco CLI）、`ohpm`、`hdc` |

### 构建与运行

```sh
# 依赖安装（首次或模块增删后）
ohpm install --all

# 构建（产出未签名 HAP）
devecocli build

# 单元测试目标（仅编译；执行需设备）
devecocli build --modules entry@ohosTest

# 构建并部署到设备/模拟器
devecocli run

# 增量热重载（需先跑一次完整 run）
devecocli run --module entry --hotreload          # 后台常驻
devecocli run --module entry --hotreload-apply changes.txt
```

### 本地模拟器

```sh
devecocli emulator list                  # 查看实例（本仓库使用 DshApi26Phone）
devecocli emulator license accept        # 首次需接受协议（非交互式）
devecocli emulator start DshApi26Phone   # 启动 API 26 手机实例
devecocli device list                    # 确认已出现在 hdc targets

# 部署与查看日志
devecocli run --device DshApi26Phone
devecocli log --level E --from 5m --tail 200
devecocli ui screenshot --device DshApi26Phone --path ./screenshots/
devecocli ui layout --device DshApi26Phone --format json
```

> **宿主内存门槛**：模拟器的 `HostFreeMemMonitor` 要求**空闲内存 ≥ 3 GB**，不足会自行终止。
> 启动前请用 `Get-CimInstance Win32_OperatingSystem` 确认 `FreePhysicalMemory`。
> 另外：本仓库的开发代理运行在 DSH 自身进程内，**任何按进程名匹配的 kill 命令都被禁止**
> （`Get-Process node | ... | Stop-Process` 这类写法会杀掉代理自己）。
> 需要停止模拟器时用 `devecocli emulator stop <name>`，停止后台任务用任务 id。

### 应用内验证（POC-1）

产品首屏右上角的「POC」（或三栏模式左导航底部的「POC 协议验证」）进入 `pages/Poc1`：

1. 在 Host 上执行 `dsh web --no-open --port <port> --host 127.0.0.1`，记下打印的 URL；
2. 设备/模拟器上运行应用，填入 `host:port` 与 token（或整段启动 URL）；
3. 点「① 认证并跑通」依次执行：token 换 cookie → 一元只读调用 → 打开逻辑流复用端点 → 校验 `ready` 首项 → 心跳存活观察；
4. 点「诊断」查看五项判定（端点 / TLS / 认证 / 协议 / Host），点「复制报告」导出可归档的验证证据。

日志不打印 token 与 cookie 值（见 D1 §11.5 S4）。

## 关键待决（见 D1 §12.2）

- v1 是否必须同时覆盖手机形态？（建议：是）
- 跨设备加密隧道是否进 v1？（建议：进，否则手机场景不完整）
- 是否允许任何形式的上游 patch？（建议：v1 绝对禁止）
- 端侧 Host（Node 运行时进 HAP）是否值得评估？（建议：限时评估）

## 许可

[MIT](LICENSE)
