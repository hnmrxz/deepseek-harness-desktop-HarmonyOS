# DeepSeek Harness 鸿蒙客户端

面向 HarmonyOS（手机 / 折叠屏 / 平板 / 2in1 PC）的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）一等客户端，**ArkTS + ArkUI 原生实现**。

> 当前阶段：**开发任务书已完成，待评审**。评审通过后进入 M1（协议层打通）。

## 与参考项目的关系

| 项目 | 关系 |
|---|---|
| [`deepseek-ai/deepseek-harness/apps/desktop`](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/desktop/README.zh.md) | 官方 Electron 桌面壳。本项目借鉴其**架构决策与工程纪律**（发布身份、状态归属、激活事务、真机验收），不复制其形态与运行时 |
| [`fellow99/deepseek-harness-harmony`](https://github.com/fellow99/deepseek-harness-harmony) | 社区 Electron-on-鸿蒙移植（真机已跑通）。本项目以其为**反面对标**：换掉 172.7 MB 运行时与 143 MB 启动解压、去掉全部上游 patch、不再绑 `0.0.0.0`、补回终端/沙箱/图片管线能力、并把手机纳入一等目标 |

## 核心主张

1. **原生而非套壳** —— ArkUI 原生渲染 + 原生协议客户端（`POST /api` + `/api/remote.mux`），无浏览器内核、无端侧 Node 运行时。
2. **全形态而非只做 PC/平板** —— 手机竖屏单手可用、折叠屏展开秒变双栏、平板/2in1 多窗口 + 键鼠 + 拖拽。
3. **接入而不打洞** —— 不绑 `0.0.0.0`、不改写 `Host`/`Origin`、**0 个上游 patch**；跨设备访问走显式配对 + 加密隧道，隧道出口仍在 Host 的 loopback 上，因此上游安全围栏天然满足。

## 文档

入口：[`docs/README.md`](docs/README.md)

| 文档 | 作用 |
|---|---|
| [`docs/00-开发任务书.md`](docs/00-开发任务书.md) | **开发任务书 D1**：背景与对标、目标、架构（含安全分级）、功能需求、POC 门、里程碑、验收体系、风险与待决事项 |
| [`docs/10-协议兼容事实基线.md`](docs/10-协议兼容事实基线.md) | 协议事实基线 D2：载体与端点、认证与信任栅栏、连接生命周期、未决问题 |
| [`docs/20-产品需求与体验规范.md`](docs/20-产品需求与体验规范.md) | 体验规范 D3：信息架构、三形态导航、界面规格、通知、无障碍、视觉 |
| [`docs/30-技术验证清单.md`](docs/30-技术验证清单.md) | 技术验证清单 D4：POC-1~11 的判定与止损 |

## 关键待决（见 D1 §12.2）

- v1 是否必须同时覆盖手机形态？（建议：是）
- 跨设备加密隧道是否进 v1？（建议：进，否则手机场景不完整）
- 是否允许任何形式的上游 patch？（建议：v1 绝对禁止）
- 端侧 Host（Node 运行时进 HAP）是否投入评估？（建议：限时评估）

## 许可

[MIT](LICENSE)
