# HDSH

> HarmonyOS 原生 DeepSeek Harness 客户端：本地 Host + 原生 ArkUI Client，面向手机、折叠屏、平板与 2in1。

## 项目定位

HDSH 的产品边界是「端侧原生客户端 + 端侧核心运行能力」，不是 WebView 套壳，也不是 PC 远程控制器。应用内包含 Node 运行时与 DeepSeek Harness 核心，在应用沙箱内启动本地 Host；ArkUI 原生界面通过 HTTP/WS 与本地 Host 通信。

上游协议继续作为事实基线：HDSH 不 fork agent 业务逻辑，不自行发明会话状态协议；端侧负责连接、状态投影、交互与 HarmonyOS 适配。

## 当前状态（2026-09-16）

当前代码已进入 P7 功能收口阶段：目标栏、失败文案、模型重试、审批、队列竞态、发送恢复、`@`/`/` 输入触发、斜杠命令等均已有针对上游语义的实现，并保持纯模型/协议常量/视图分层。最近提交已连续通过仓库既有门禁；下一阶段重点不再是堆功能，而是多形态 UI 收口、真实设备矩阵、运行时稳定性与发布工程化。

## 核心能力

| 模块 | 用户能力 |
|---|---|
| 会话 | 会话列表、创建、切换、标题、消息、流式状态、错误恢复、待发队列 |
| Agent 轨迹 | 工具调用、命令、子代理、审批、重试、目标、任务、交付物、错误 |
| 工作区 | 目录选择、工作区与会话关联、文件浏览、附件与引用 |
| 模型 | Provider / baseURL / API Key / 模型发现 / 默认模型 / 推理强度 |
| 扩展 | 插件清单、启停与运行状态；核心版本安装、切换、回滚 |
| 多端 | 手机单栏、折叠/平板双栏、2in1 多窗/键鼠/拖拽/快捷键 |
| 系统集成 | 文件选择、剪贴板、通知、窗口记忆、主题、权限与备份 |

## UI 原则

- 保留 DeepSeek Harness 的产品语义，视觉与交互使用 HarmonyOS 原生表达。
- 统一令牌：`appstate/ui/Tokens.ets` → `appstate/ui/HarmonyTheme.ets` → `entry/.../view/NativePrimitives.ets`。
- 布局决策集中在 `Breakpoints.ets` / `LayoutController.ets` / `NavigationController.ets`，页面只消费决策。
- 浮层优先使用系统 `bindSheet`；图标使用系统符号；禁止重新引入 Web SVG/CSS 模拟层。
- 手机优先保证单手可用与审批效率；大屏优先利用空间，不简单拉伸手机布局。

## 技术基线

- ArkTS + ArkUI Stage 模型。
- SDK：`targetSdkVersion` / `compatibleSdkVersion` = `6.1.1(24)`。
- ABI：`arm64-v8a` + `x86_64`。
- Node Host 采用 `jitless` 运行；端侧通过原生 HTTP/HTTPS 垫片处理无 WASM 环境，并对 `undici` 名称解析做兼容。
- 应用目标设备：`phone` / `tablet` / `2in1`。

## 开发顺序

1. P8：真机/模拟器运行稳定性与 API 24 兼容性收口。
2. P9：手机、折叠屏、平板、2in1 的导航/布局/输入统一验收。
3. P10：核心版本与插件安装事务、备份/恢复、升级回滚。
4. P11：性能、功耗、内存、冷启动、长会话与异常恢复。
5. P12：签名、AGC 提审、升级路径与发布包验收。

## 文档入口

| 文档 | 用途 |
|---|---|
| [`docs/01-产品与功能说明.md`](docs/01-产品与功能说明.md) | 产品定位、用户任务、功能范围与非目标 |
| [`docs/02-开发计划.md`](docs/02-开发计划.md) | 阶段、任务、优先级、完成定义 |
| [`docs/03-技术架构与模块.md`](docs/03-技术架构与模块.md) | Host / Client / State / Platform 分层 |
| [`docs/04-HarmonyOS多端UI设计规范.md`](docs/04-HarmonyOS多端UI设计规范.md) | HarmonyOS 原生 UI 与多形态设计 |
| [`docs/05-验证与验收.md`](docs/05-验证与验收.md) | 本机、模拟器、真机、发布验收 |
| [`docs/06-开发与发布指南.md`](docs/06-开发与发布指南.md) | 构建、调试、提交、发布 |
| [`docs/07-当前状态与缺口.md`](docs/07-当前状态与缺口.md) | 已完成、风险、待办与决策记录 |
| [`docs/README.md`](docs/README.md) | 文档总索引与阅读顺序 |

## 构建

```bash
devecocli build
node tools/pack-core.mjs --skip-install --place-in-app
node tools/place-host-app.mjs
```

安装与签名材料不纳入仓库；完整流程见 `docs/06-开发与发布指南.md`。

## 远程开发约束

远程开发环境不要求模拟器或真机。所有纯逻辑模型、协议投影、布局决策、fixture 与门禁必须可在本机完成；UI/系统行为只进入“设备验证”队列，不阻塞协议与状态开发。

## License

Apache License 2.0，具体以仓库 `LICENSE` 为准。
