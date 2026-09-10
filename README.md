# DeepSeek Harness 鸿蒙客户端

面向 HarmonyOS（手机 / 折叠屏 / 平板 / 2in1 PC）的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）一等客户端，**ArkTS + ArkUI 原生实现**。

> **当前进度**：M1/M2 并行推进 —— 工程骨架、协议兼容层、**DSH 上游兼容面**、状态层骨架与产品 UI
> （三形态导航 + 待决 + 会话 + 轨迹）均已建成；主构建与 `entry@ohosTest` 测试目标编译通过；
> 已对**真实 dsh Host** 完成协议实测（只读端点 10/10 通过，认证与信任栅栏逐条命中）。
> **阻塞**：缺少可用设备（无真机连接；模拟器受宿主内存限制无法启动），
> 因此 POC-1 的设备侧步骤（mux / ready / 心跳 / cancel）尚未执行，详见
> [`docs/30-技术验证清单.md`](docs/30-技术验证清单.md) 的「POC-1 当前进展」。

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
├── entry/                    # HAP 入口：Ability、页面、视图、形态适配
│   └── src/
│       ├── main/ets/
│       │   ├── pages/Index.ets   # 产品首屏：三形态导航 + 让步链
│       │   ├── pages/Poc1.ets    # POC-1 协议往返验证页（验收工具）
│       │   └── view/             # 会话列表 / 会话轨迹 / 待决 / 占位面板
│       └── ohosTest/             # 单元测试（Hypium，约 60 条断言）
├── connection/               # HAR：协议**机制层**（零 UI 依赖，不含具体端点/字段名）
│   └── src/main/ets/protocol/
│       ├── Surface.ets       # 注入式「上游接口面」定义（路径等事实由 dshcompat 提供）
│       ├── RpcTypes.ets      # endpoint 校验、RemoteFailure、RpcResult
│       ├── Envelope.ets      # 一元信封构造/解析
│       ├── HostAddress.ets   # 地址规范化、authority、loopback 判定
│       ├── Cookies.ets       # Set-Cookie 多形态解析 + 按 authority 隔离的 CookieJar
│       ├── HttpClient.ets    # @ohos.net.http 载体
│       ├── AuthSession.ets   # token → 签名 cookie、401 重绑、403 信任栅栏诊断
│       ├── RemoteMux.ets     # 逻辑流复用 + 心跳
│       ├── EventStream.ets   # 事件流、ready 首项、generation 失效
│       ├── Backoff.ets       # 500ms→10s 退避 + 抖动
│       └── Connection.ets    # 门面 + 五项连接诊断
├── dshcompat/                # HAR：**DSH 上游兼容面（唯一的上游事实落点）**
│   └── src/main/ets/
│       ├── Endpoints.ets     # 端点上表（自动生成，74 条，含参数形态与流式标记）
│       ├── Surface.ets       # 载体路径 / 事件流端点 / 开流 payload
│       ├── Aliases.ets       # 字段别名表 + 常用 endpoint 常量
│       ├── CompatIndex.ets   # 能力映射 + 版本矩阵 + 参数构造 + 能力判定
│       └── CompatTypes.ets   # 兼容面类型
├── appstate/                 # HAR：状态层（投影 / 派生 / 呈现契约；零 UI 依赖）
│   ├── model/SessionList.ets # 会话列表投影（字段名走 dshcompat 别名表）
│   ├── model/Trajectory.ets  # 轨迹与待决的**呈现层契约**
│   ├── model/Present.ets     # 呈现层纯函数（相对时间 / 截断 / 排序 / 朗读文本）
│   ├── model/StubData.ets    # 桩数据源（设备到位前驱动 UI）
│   └── ui/                   # 断点与导航模型、设计令牌
├── tools/                    # 协议与兼容面工具（Node，独立于应用）
│   ├── protocol-enum.mjs        # 从已安装 dsh 包枚举 endpoint
│   ├── protocol-enum2.mjs       # 精确版：修正命名空间跨文件声明 / 属性名≠线上名
│   ├── protocol-contract.mjs    # 从生成描述符提取 74 个 endpoint 的权威调用契约
│   ├── gen-compat-endpoints.mjs # 由契约生成 dshcompat 端点上表
│   ├── compat-drift.mjs         # **上游漂移门禁**（CI 用，有漂移则非零退出）
│   └── protocol-probe.mjs       # 对真实 Host 做只读探测 → 可用性与错误码矩阵
└── docs/                     # 文档基线（D1~D5）
```

## 文档

入口：[`docs/README.md`](docs/README.md)

| 文档 | 作用 |
|---|---|
| [`docs/00-开发任务书.md`](docs/00-开发任务书.md) | **开发任务书 D1**：背景与对标、目标、架构（含安全分级 L0/L1/L2）、功能需求、POC 门、里程碑、验收体系、风险与待决事项 |
| [`docs/10-协议兼容事实基线.md`](docs/10-协议兼容事实基线.md) | 协议事实基线 D2：载体与端点、认证与信任、连接生命周期、**§8 实测矩阵与调用契约表** |
| [`docs/20-产品需求与体验规范.md`](docs/20-产品需求与体验规范.md) | 体验规范 D3：信息架构、三形态导航、界面规格、通知、无障碍、视觉 |
| [`docs/30-技术验证清单.md`](docs/30-技术验证清单.md) | 技术验证清单 D4：POC-1~11 的判定与止损 |
| [`docs/40-上游升级手册.md`](docs/40-上游升级手册.md) | **上游升级手册 D5**：分层前提与评审检查表、五步升级流程、漂移门禁、降级策略、版本矩阵 |

## 怎么应对 DSH 上游升级

核心约束：**上游接口细节只允许出现在 `dshcompat` 一处**。`connection` 只提供机制（载体/信封/cookie/退避），
`appstate` 与 UI 只认呈现层契约。上游改动全部落在 `dshcompat`，其余三层零改动。

```sh
# 1) 提取新上游的调用契约（每个 endpoint 的参数形态、流式标记、可否取消）
node tools/protocol-contract.mjs --json .research/protocol/contracts.json

# 2) 漂移门禁：与已提交基线逐条比对，有差异则非零退出并给出精确差异
node tools/compat-drift.mjs

# 3) 重新生成端点上表（必要时同步调整能力映射）
node tools/gen-compat-endpoints.mjs

# 4) 对真实 Host 复跑只读探测，确认端点可用性与错误码语义
node tools/protocol-probe.mjs --base http://127.0.0.1:3111 --token <token>
```

配套的**架构回归检查**（期望无输出）：

```sh
grep -rnE "session/|settings/|workspace/|pluginInventory/" connection/src appstate/src entry/src/main/ets/view
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
