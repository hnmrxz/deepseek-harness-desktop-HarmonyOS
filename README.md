# DeepSeek Harness 鸿蒙客户端

面向 HarmonyOS（手机 / 折叠屏 / 平板 / 2in1 PC）的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）一等客户端，**ArkTS + ArkUI 原生实现**。

> **当前进度**：M1 进行中 —— 工程骨架已建成，协议兼容层已实现并通过编译与静态检查；
> 已对**真实 dsh Host** 完成协议实测（只读端点 10/10 通过，认证与信任栅栏逐条命中）。
> 下一步：设备上跑通 POC-1（原生协议往返）。

## 核心主张

1. **原生而非套壳** —— ArkUI 原生渲染 + 原生协议客户端（`POST /api/<endpoint>` + `/api/remote.mux`），无浏览器内核、无端侧 Node 运行时。
2. **全形态而非只做 PC/平板** —— 手机竖屏单手可用、折叠屏展开秒变双栏、平板/2in1 多窗口 + 键鼠 + 拖拽。
3. **接入而不打洞** —— 不绑 `0.0.0.0`、不改写 `Host`/`Origin`、**0 个上游 patch**；跨设备访问走显式配对 + 加密隧道，隧道出口仍在 Host 的 loopback 上，因此上游安全围栏天然满足。

## 与参考项目的关系

| 项目 | 关系 |
|---|---|
| [`deepseek-ai/deepseek-harness/apps/desktop`](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/desktop/README.zh.md) | 官方 Electron 桌面壳。本项目借鉴其**架构决策与工程纪律**（发布身份、状态归属、激活事务、真机验收），不复制其形态与运行时 |
| [`fellow99/deepseek-harness-harmony`](https://github.com/fellow99/deepseek-harness-harmony) | 社区 Electron-on-鸿蒙移植（真机已跑通）。本项目以其为**反面对标**：换掉 172.7 MB 运行时与 143 MB 启动解压、去掉全部上游 patch、不再绑 `0.0.0.0`、补回终端/沙箱/图片管线能力、并把手机纳入一等目标 |

## 仓库结构

```
.
├── AppScope/                 # 应用级配置与资源（bundleName、图标、应用名）
├── entry/                    # HAP 入口模块：Ability、页面、形态适配
│   └── src/main/ets/
│       ├── entryability/     # EntryAbility
│       └── pages/Index.ets   # 当前为 POC-1 协议验证页（验证工具，非产品界面）
├── connection/               # HAR：dsh 协议兼容层（零 UI 依赖）
│   └── src/main/ets/protocol/
│       ├── RpcTypes.ets      # endpoint 校验、RemoteFailure、RpcResult
│       ├── Envelope.ets      # 一元信封构造/解析
│       ├── HostAddress.ets   # 地址规范化、authority、loopback 判定
│       ├── Cookies.ets       # Set-Cookie 多形态解析 + 按 authority 隔离的 CookieJar
│       ├── HttpClient.ets    # @ohos.net.http 载体
│       ├── AuthSession.ets   # token → 签名 cookie、401 重绑、403 信任栅栏诊断
│       ├── RemoteMux.ets     # /api/remote.mux 逻辑流复用 + 心跳
│       ├── EventStream.ets   # $events 事件流、ready 首项、generation 失效
│       ├── Backoff.ets       # 500ms→10s 退避 + 抖动
│       └── Connection.ets    # 门面 + 五项连接诊断
├── appstate/                 # HAR：状态层（连接持有、会话投影；零 UI 依赖）
├── tools/                    # 协议工具（Node，独立于应用）
│   ├── protocol-enum.mjs     # 从已安装 dsh 包枚举 endpoint
│   ├── protocol-enum2.mjs    # 精确版：修正命名空间跨文件声明 / 属性名≠线上名
│   ├── protocol-contract.mjs # 从生成描述符提取 74 个 endpoint 的权威调用契约
│   └── protocol-probe.mjs    # 对真实 Host 做只读探测 → 可用性与错误码矩阵
└── docs/                     # 文档基线（D1~D4）
```

## 文档

入口：[`docs/README.md`](docs/README.md)

| 文档 | 作用 |
|---|---|
| [`docs/00-开发任务书.md`](docs/00-开发任务书.md) | **开发任务书 D1**：背景与对标、目标、架构（含安全分级 L0/L1/L2）、功能需求、POC 门、里程碑、验收体系、风险与待决事项 |
| [`docs/10-协议兼容事实基线.md`](docs/10-协议兼容事实基线.md) | 协议事实基线 D2：载体与端点、认证与信任、连接生命周期、**§8 实测矩阵与调用契约表** |
| [`docs/20-产品需求与体验规范.md`](docs/20-产品需求与体验规范.md) | 体验规范 D3：信息架构、三形态导航、界面规格、通知、无障碍、视觉 |
| [`docs/30-技术验证清单.md`](docs/30-技术验证清单.md) | 技术验证清单 D4：POC-1~11 的判定与止损 |

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

# 构建并部署到设备/模拟器
devecocli run

# 增量热重载（需先跑一次完整 run）
devecocli run --module entry --hotreload          # 后台常驻
devecocli run --module entry --hotreload-apply changes.txt
```

### 协议工具用法

```sh
# 1) 枚举 endpoint（无需 Host）
node tools/protocol-enum2.mjs
node tools/protocol-contract.mjs --json .research/protocol/contracts.json

# 2) 启动一个隔离的 Host（不触碰既有会话）
DSH_HOME=$TEMP/dsh-poc-host dsh web --no-open --port 3111 --host 127.0.0.1
#    → 输出形如：dsh web: http://127.0.0.1:3111/?token=<token>

# 3) 对真实 Host 做只读探测，得到端点可用性与错误码矩阵
node tools/protocol-probe.mjs --base http://127.0.0.1:3111 --token <token>
```

工具只调用**只读**端点，不会创建或修改任何会话与配置。

### 应用内验证（POC-1）

当前 `entry` 的首屏是 **POC-1 协议验证页**（D4 的「生死门」）：

1. 在 Host 上执行 `dsh web --no-open --port <port> --host 127.0.0.1`，记下打印的 URL；
2. 设备/模拟器上运行应用，填入 `host:port` 与 token（或整段启动 URL）；
3. 点「① 认证并跑通」依次执行：token 换 cookie → 一元只读调用 → 打开 `/api/remote.mux` → 校验 `ready` 首项 → 心跳存活观察；
4. 点「诊断」查看五项判定（端点 / TLS / 认证 / 协议 / Host），点「复制报告」导出可归档的验证证据。

日志不打印 token 与 cookie 值（见 D1 §11.5 S4）。

## 关键待决（见 D1 §12.2）

- v1 是否必须同时覆盖手机形态？（建议：是）
- 跨设备加密隧道是否进 v1？（建议：进，否则手机场景不完整）
- 是否允许任何形式的上游 patch？（建议：v1 绝对禁止）
- 端侧 Host（Node 运行时进 HAP）是否值得评估？（建议：限时评估）

## 许可

[MIT](LICENSE)
