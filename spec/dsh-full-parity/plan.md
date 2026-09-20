# Implementation Plan: dsh 核心升级 0.1.6-alpha.2 —— 设置项核查与工作区工具能力修复（v3）

**Input**: Feature specification from `spec/dsh-full-parity/spec.md`（v3 周期）

## Summary

把端侧捆绑的 dsh 核心从 0.1.5-rc.2/rc.3 升级到 0.1.6-alpha.2：更新打包配方并重跑 pack-core 全流程，把六个沙箱补丁逐个适配到新源树（fail-loud，漂移即更新锚点）；resfile 只保留 alpha.2 一个核心包。在新核心之上：端到端诊断并修复 agent 工作区文件读写能力（link 降级/默认工作区两条历史修复取真机证据）；逐项核查 Web UI 与原生两侧设置项；对 0.1.6-alpha.2 跑协议探测回归。v2 的 UI 复刻成果为基线不动；v2 遗留验证并入本周期 build+ui 验证。

## Technical Context

**Language/Version**: ArkTS（API 26 级工程，State Management V1 既有）+ Node.js 22/24（hostcore 运行期脚本，入口跑在端侧 libnode）+ npm 打包链
**Primary Dependencies**: @deepseek-ai/dsh 全家（0.1.6-alpha.2，npm alpha tag）、@ohos-ports/node-pty、koffi 3.x 自建（fetch-koffi 路线）、sharp/libvips（collect-libvips 路线）、hvigor 构建
**State Management**: 沿用既有（V1 @State/AppStorage；本周期基本不新增 UI 状态）
**Storage**: 沙箱 filesDir（cores/<version>/ 树、core-state.json、host-ready.json、$DSH_HOME 用户数据跨版本共享）；resfile 大资源
**Testing**: hostratest 既有单测 + ohosTest 源集 + tools/ 七项门禁脚本 + protocol-probe 端点探测 + 真机/模拟器手动走查（build+ui 验证）
**Target Platform**: HarmonyOS（openharmony/arm64），设备或模拟器以当时可用为准
**Project Type**: 既有 HarmonyOS 应用（含端侧 Node 宿主）的增量升级周期
**Performance Goals**: 核心包体积不显著超 rc.3（裁剪后同量级，约 66-70MB zip）；首启解包时长同量级
**Constraints**: 不改上游源码（端侧差异只走运行期组合 + 打包补丁层）；补丁形状断言 fail-loud；resfile 仅一个核心 zip；门禁全绿为硬门槛
**Scale/Scope**: 1 个核心版本升级 + 2 类能力核查修复；预计触达 tools/pack-core.mjs、hostcore/app/main.js、配方文件、（如漂移）dshcompat/appstate 协议层、文档口径

## Project Structure

### Documentation (this feature)

```text
spec/dsh-full-parity/
├── spec.md              # v3 需求（本周期）
├── plan.md              # 本文件
├── tasks.md             # Phase 3 生成
└── deletion-manifest.md # v2 历史产物（保留，不再更新）
```

### Source Code (repository root)

```text
hostcore/
├── core-recipe.json        # 唯一配方：coreVersion → 0.1.6-alpha.2（本次升级入口）
├── core-recipe-rc3.json    # 变体配方：删除（避免双真值源；历史在 git）
├── profile/ondevice/       # 端侧 profile（bundle 顺序 + patchReload）
└── app/main.js             # 入口脚本：启动参数表按新 startup.js 复核；工作区/工具垫片如需增强
tools/
├── pack-core.mjs           # 打包全流程：六补丁锚点适配到 0.1.6-alpha.2 源树
├── fetch-koffi.mjs         # koffi 3.x 自建供给（新核心版本要求若变则适配）
├── collect-libvips.mjs     # sharp/libvips 供给
├── place-host-app.mjs      # 入口脚本重放（改 main.js 必须重跑）
├── protocol-probe.mjs / gen-compat-endpoints.mjs / protocol-contract.mjs  # 协议探测与端点表再生成
└── check-*.mjs / arch-check.mjs  # 七门禁（升级后全绿）
entry/src/main/resources/resfile/
├── dsh-core-0.1.6-alpha.2-openharmony-arm64.zip  # 新核心包（产物）
└── （rc.2/rc.3 zip 移除）
hostruntime/src/main/ets/
├── core/{CoreStore,CoreDecision 依赖的 Types,Naming,BundledCore}.ets  # 版本字符集/激活/回滚（预计无需改，验证 0.1.6-alpha.2 过 isSafeVersion）
└── runtime/{DshHost,RuntimePort}.ets  # HDSH_CORE_DIR 指向新版本树
appstate/src/main/ets/
├── store/SessionHub.ets    # session/create 的 workspaceId/cwd 回退（E98 链路）
└── model/Wire.ets          # 协议载荷（漂移适配点）
dshcompat/src/main/ets/     # 协议别名层（漂移适配点）
entry/src/main/ets/         # 原生设置界面（SettingsPane 等，预计不动，仅回归）
docs/                       # 口径同步：parity-matrix / 07-当前状态与缺口 / 50-端侧核心运行架构 / 10-协议兼容事实基线
```

**Structure Decision**: 沿用既有项目架构（hostcore 打包层 + hostruntime 宿主层 + appstate/dshcompat 协议层 + entry UI 层），不引入 MVVM 迁移、不新增目录层级。本周期改动集中在打包配方与工具链、入口脚本、（如漂移）协议层，UI 层仅回归不重构。

## Complexity Tracking

> 无 Constitution 违例需豁免。

## Research & Decisions

### R&D-001 版本固定与配方收敛

- **Decision**: `hostcore/core-recipe.json` 的 `coreVersion` 更新为 `0.1.6-alpha.2`；删除 `core-recipe-rc3.json` 变体（rc.2/rc.3 的 zip 从 resfile 移除，仅保留 alpha.2 产物）。npm 安装显式钉 `@deepseek-ai/*@0.1.6-alpha.2`（alpha dist-tag 已确认存在）。
- **Rationale**: 配方是唯一事实来源（其头注释明示）；双配方并存会造成"哪份是真"的漂移。resfile 多一个 zip 即 HAP +69MB 且首启解包翻倍，用户已裁决仅保留 alpha.2。已安装旧核心树的设备不受影响（cores/<version>/ 目录与 CoreState 回滚语义仍在）。
- **Alternatives considered**: alpha.2 + rc.3 双保留（用户已否决，体积代价）；新建 spec 目录（用户已裁决沿用 dsh-full-parity 覆盖）。

### R&D-002 补丁适配策略（fail-loud 逐锚点）

- **Decision**: pack-core 的六类补丁（Origin 栅栏列表、link 沙箱降级、凭据属主豁免、sharp 调度器 wrapSharp、node-addon-system 平台包、linux_arm64 平台别名）+ ondevice preset 生成 + 树内清单契约，全部以 0.1.6-alpha.2 源码为准**逐个重新核锚**：上游形状未变则补丁原样生效；漂移则更新锚点与断言，绝不放宽为"找不到就跳过"。main.js 的启动参数表（--port/--host/--no-open/--trusted-host）按新 dsh-web-app startup.js 重新核对，增删选项以新版为准。
- **Rationale**: 这些断言存在的意义就是"上游一变就叫"；升级周期的正确姿势是让它们响、然后显式适配。历史先例：--skip-auth 是臆造参数导致 rc=1（D6 E33），参数表必须实证。
- **Alternatives considered**: 关闭断言硬闯（违背 fail-loud 不变式，埋"看似绿实际没用"的雷）。

### R&D-003 工作区工具能力诊断与修复路径

- **Decision**: 分三层诊断：①agent 工具层——会话内执行"新建→读取→覆盖→列目录"四步链，观察 dsh-fs-local 的 writeFileAtomic 走 link/copyFile/rename 哪条路径，main.js 的 link 降级垫片是否命中并如实打日志；②会话默认工作区——host-ready.json 的 workspace 字段（可写目录而非 `/`）被 SessionHub 建会话时以 workspaceId/cwd 回退送出（互斥，二者不混送），workspaceFiles 面板列出真实文件；③工具集配置——ondevice preset 按新核心的 preset 机制重生成，禁用项（tool-bash/tool-pwsh/tool-fs-search 默认维持禁用）不出现在会话、启用项可用。修复优先级：运行期垫片（main.js）> 打包期补丁；不改上游。
- **Rationale**: 已知两处历史修复（F1 link 降级、E98 默认工作区）从未做过端到端验证；用户报告的"工具能力问题"最可能藏在这条链路的未验证段。互斥回退是上游硬约束（`gateway/bad-request session.create accepts workspaceId or cwd, not both`）。
- **Alternatives considered**: 直接改上游 dsh-fs-local（违背不变式）；跳过端到端只做静态核查（无法暴露沙箱策略问题）。

### R&D-004 设置项核查方法

- **Decision**: 升级后先**生成清单**再走查：Web UI 侧以新版设置页实际渲染项为准枚举（模型/供应商与密钥、工具开关、插件管理、外观等），原生侧枚举 SettingsPane/主题/核心管理既有项；每项走"打开→修改→保存→重启→读回"五步，结果落成核查清单文档（含每项结论与修复状态）。设置存储位于 $DSH_HOME（跨版本共享），旧配置在新核心下的兼容性属核查范围（升级不丢用户设置）。发现的故障按"宿主可修（main.js/垫片/补丁）→ 修复；上游限制 → 如实登记"。
- **Rationale**: "各设置项是否正常"必须清单化才可验收；$DSH_HOME 跨版本共享意味着升级是设置兼容性的真实考验。
- **Alternatives considered**: 抽查几个关键项（不满足"逐项"验收）。

### R&D-005 协议兼容回归

- **Decision**: 0.1.6-alpha.2 host 就绪后运行 tools/protocol-probe.mjs 与 gen-compat-endpoints.mjs：既有契约端点（会话创建/列表/跟随、轨迹流、审批、提问、workspaceFiles 等）逐一探测核对，漂移则适配 dshcompat/appstate 协议层并复测；端点表由契约生成（手写必然漂移——既有工具的立场均如此）。适配范围以"既有功能不回归"为界，不做超前适配。
- **Rationale**: 协议漂移是版本升级的隐性断点，且 v2 手机链（RemoteShell 全功能）的存续完全系于协议兼容。
- **Alternatives considered**: 只跑 UI 冒烟不探协议（漂移会被"某个面板空白"式的随机症状掩盖）。

### R&D-006 验证环境与 v2 遗留验证合并

- **Decision**: Phase 5 验证范围 build+ui，以当时可用设备为准（真机优先——link/symlink 类沙箱策略只有真机能定论；模拟器验证项在报告中如实标注覆盖差异）。v2 未竟验证（形态路由矩阵、删除收敛回归、手机链对照）作为回归清单并入本轮 UI 验证，不单独开周期。
- **Rationale**: 用户裁决"都可以，以当时可用设备为准"；v2 的验收口径已在 v2 spec 定稿，本周期只需按其执行。
- **Alternatives considered**: 先对 rc.3 跑一轮 v2 验证再升级（对将被替换的版本做一次性验证，浪费）。

## Data Model

- **核心配方（core-recipe.json）**: `coreVersion`（"0.1.6-alpha.2"）、`platform{os,cpu}`、`overrides`（node-pty/koffi/sharp → ohos 供给别名）、`prune[]`（裁剪规则，按新树核对 keepOnlyDirs 是否仍成立）、`requiredNative[]`（koffi.node/pty.node/spawn-helper 必在）、`optionalNativeGlobs`。约束：pack-core 读写它做物化/裁剪/校验；字段缺失即失败。
- **核心包**: zip 容器（命名 `dsh-core-<version>-openharmony-arm64.zip`）+ 树内元数据 `hdsh-core.json`（coreVersion/profile/插件清单，pack 写完读回逐字段核对）。
- **CoreState**: `current/previous/history[]`（激活与回滚决策的持久状态；版本号需过 `isSafeVersion` 字符集校验——"0.1.6-alpha.2" 含点与连字符，实现时验证通过即可，预计无需改 Naming）。
- **host-ready.json**: `url/baseUrl/token/port/profile/workspace/runtime{nodeVersion,platform,jitless,zstd,listenAddress,natives[]}`。`workspace` 字段是 E98 链路的核心（客户端建会话取它）；`runtime` 段喂核心页"运行时事实"。升级后 schema 若被 host 侧扩充，读取侧按"可能缺失"既有口径兼容。
- **session/create 载荷**: `workspaceId` 或 `cwd`（互斥，都无则交回 Host 默认行为）+ `prompt` 等；上游 bad-request 是硬约束。
- **设置项核查清单**: 项名、所属侧（Web UI/原生）、五步走查结果、故障描述、修复状态（已修/上游限制登记）。作为文档工件落 docs。
- **协议契约端点表**: 由探测工具对 host 实测生成；客户端协议层以此为对照基准。

## Contracts & Interfaces

- **pack-core CLI 契约**: 旗标不变（全流程 / --skip-install / --place-in-app / --recipe / --allow-sharp-stub）；任何补丁锚点失配必须非零退出并指明失配补丁，不允许降级为告警。
- **resfile 契约**: `BundledCore.installAll` 扫描 `dsh-core-*-openharmony-arm64.zip`，`parseArchiveName` 解出版本并过 `isSafeVersion`；仅 alpha.2 一个 zip 在场。
- **RuntimePort 环境契约**: `HDSH_CORE_DIR/HDSH_HOME/HDSH_SANDBOX_HOME/HDSH_PORT(/trusted-host 走 ctx.cmdlineArgs)`——升级不改契约本身，只改 CORE_DIR 指向的树版本。
- **dsh-web-app CLI 参数契约**: 以 0.1.6-alpha.2 的 startup.js 实测为准（当前认知：--host/--no-open/--port/--trusted-host 四项合法）；增删选项须在 main.js 同步并留注释证据。
- **host 就绪信号契约**: stdout `HDSH_READY {...}` + host-ready.json 落盘；ArkTS 侧等端口可连后才采信。
- **停止通道契约**: `<HOME_DIR>/host-stop-request` 文件轮询（升级后核对 dsh shutdown 语义未变）。
- **session/create 契约**: workspaceId 与 cwd 互斥（上游 bad-request）；默认工作区来自 host-ready.json 的 workspace 字段。
- **门禁契约**: check-parity / check-design-tokens / check-feature-wiring / check-layout-fixtures / check-compliance / check-dead-code / arch-check 全部 EXIT 0；design-token 基线棘轮只降不升；入口脚本若改动必须重放 place-host-app。
- **验证范围标记**: tasks.md 验证段使用 `<!-- verification_scope: build+ui -->`。

## Changelog

- 2026-09-20（v3 覆盖重写）: 本 plan 替换 v2 版本。修改动因：用户提出新需求（升级 0.1.6-alpha.2、设置项核查、工作区工具能力修复），按 SDD 回溯规则从 Phase 1 重执行。v2 的 UI 复刻设计与决策保留于 git 历史；v2 已交付实现作为本周期基线不重做，其未竟验证并入本周期验证段（R&D-006）。
