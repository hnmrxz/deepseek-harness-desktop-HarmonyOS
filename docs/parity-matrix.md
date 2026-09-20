# 功能对等矩阵（Parity Matrix）· P0

> 本文档于 2026-09-19 精简（仅删散文叙述）；2026-09-20 全量对等收口：§4/§5/§6 按实现现状逐行核实更新（过程与判定依据见 §5.2）；2026-09-20 v2 转向同步：§4 各行「Harmony 状态层/界面」列按「Web 直载 + DSH Mobile 源码对照复刻」新架构口径修订（删除的 PC 原生壳、新增 `WebShell`/`MobileTheme`/`Ds*`/`SessionSearch` 已如实登记），**状态计数不变**。完整版见 git 历史。

| 项 | 内容 |
|---|---|
| 文档编号 | `docs/parity-matrix.md` |
| 版本 | v1.0 |
| 日期 | 2026-09-14 |
| 状态 | 生效（P0 交付物） |
| 上位文档 | `docs/00-开发任务书.md`（D1）、`docs/20-产品需求与体验规范.md`（D3）、`docs/50-端侧核心运行架构.md`（D6）；本文是《HarmonyOS 多端开发实施计划》P0 的落地台账 |
| 定位 | **逐功能对等台账**：官方 Web 的每一项能力，在 HDSH 里的状态层/界面/协议/四形态落点与状态。**它是"还差什么"的唯一清单**，不是宣传材料 |
| 门禁 | `node tools/check-parity.mjs`（含注入式自检 `--self-test`）。**本文格式坏了或状态注水，门禁会失败** |

---

## 0. 这份文档是什么、不是什么

- **是**：官方 Web 能力面的**全量覆盖表**（行集 = 38 个 `dsh-client-ui-*` 包 + `dsh-client-locale` + `hdsh-` 端侧独有行），逐行给出落地文件与四形态状态；同时是缺口登记处——任何非 `DONE` 的行必须在 §6 登记原因与下一步，门禁强制。
- **不是**：不是"最终验收通过"的声明（`DONE` 只表示实现侧完成，真机验收是另一根轴，见 §1.3，整体仍 `PENDING`）；不是设计文档（设计口径在 D3，协议事实在 D2/D2b），只登记对等状态。

---

## 1. 状态口径

### 1.1 四个状态 token（只允许这四个）

| token | 含义 | 判据 |
|---|---|---|
| `DONE` | 实现侧完成，该形态下无已知缺口 | §1.2 的八项判据齐备 |
| `PARTIAL` | 部分可用：有真实实现，但缺项 | 必须在 §6 登记缺什么 |
| `BOUNDARY` | **能力边界**：平台/架构不允许，不是缺陷 | 必须在 §6 写明为什么不可做 |
| `TODO` | 未实现 | 必须在 §6 登记下一步 |

### 1.2 `DONE` 的八项判据（计划 §5）

`Protocol` · `State` · `Functional` · `Interaction` · `Responsive` · `Accessibility` · `Validation`

> 第 7 项 `Validation` 在本环境的含义**限定为"可静态验证"**（门禁、门禁自检、单测、协议往返）——**不包括真机验收**，见 §1.3。

### 1.3 两根轴：实现侧 vs 设备验证

- **实现侧**：本矩阵的 `Status` / 四形态列，取值见 §5 统计。
- **设备验证**：`PENDING` / `PASS`；今天整体是 **`PENDING`**（本环境无模拟器、无真机；工具链已于 2026-09-14 就位，HAR 模块可真编译，见 §3）。
- **硬规则**：任何 `DONE` 行都不得被读作"已在设备上验收通过"；报告里必须同时给出设备验证轴的取值。

### 1.4 门禁强制的五条不变式

- **A** 行集恰好覆盖官方能力面（38 个 `dsh-client-ui-*` + `client-locale` = 39 个 id 各一行），另有 `hdsh-` 前缀的端侧独有行 —— 防漏项、重复项、覆盖越界。
- **B** 状态 token 合法（只允许 §1.1 的四个）；**任一形态列不是 `DONE` 时，整体 `Status` 不得是 `DONE`** —— 防用整体 DONE 盖住某个形态的缺口。
- **C** 任何非 `DONE` 的行必须在 §6 缺口登记里有对应行；§6 也不得登记矩阵里不存在的 id —— 防悄悄降级、只留结论不留原因、幽灵登记。
- **D** §5 统计表必须与矩阵**实算**逐项相等（含合计）—— 防口径不明导致数字对不上（本项目真实发生过）。
- **E** `DONE` 的行不得留在 §6 缺口登记里 —— 防陈旧登记（台账同时说"已完成"和"缺什么"）。

> 五条都有**注入式负测试**（`--self-test` 的 12 个正/负样例）证明会真的失败；对真实矩阵也做过端到端注入——把 `workflow-run` 从 `TODO` 谎报成 `DONE` 并顺手改对统计数字，门禁仍以「陈旧登记」点名并退出 1。

---

## 2. 形态口径（四列的定义）

HarmonyOS 的 `deviceType` 只有 `phone` / `tablet` / `2in1`（另有 tv/wearable/car），**没有独立的 PC**：计划书里的「PC」与「2-in-1」在系统看来是**同一个 `deviceType = 2in1`**，差别在**窗口模式与输入模态**。因此四列的定义是「设备族 × 窗口/输入形态」，不是四个设备类型：

| 列 | 判定 | 典型场景 |
|---|---|---|
| **Phone** | `deviceType=phone`，单栏 | 直板机；折叠屏折叠态 |
| **Tablet** | `deviceType=tablet` | 平板竖屏（双栏）/ 横屏（三栏） |
| **PC** | `deviceType=2in1` + 全屏/最大化窗口、键鼠为主 | 电脑模式、台式二合一接显示器 |
| **2-in-1** | `deviceType=2in1` + 自由窗口/悬停态、触摸为主 | 二合一笔记本、折叠屏悬停 |

两条落地规则（与 D3 §2.2 一致，本项目不做例外）：① **布局决策只看「窗口宽度 + 输入模态」**，`layoutModeOf(widthVp)` 是唯一入口（一个 2in1 被拖窄到 500vp 必须与手机同构——这就是"窗口变化时自动切换布局"的实现方式）；② **`deviceType` 只用于门控系统能力**（系统文件夹选择器、快捷键提示、拖拽投喂等），且**只允许出现在 Layout/Platform 层**。

---

## 3. 本环境的验证手段口径（可做 / 不可做）

| 手段 | 本环境结论 |
|---|---|
| Node 静态门禁（`tools/*.mjs`） | ✅ 可跑、全绿（见 §3.1） |
| **ArkTS 真编译（HAR 模块）** | ✅ `devecocli build --modules appstate connection dshcompat hostruntime platform` → BUILD SUCCESSFUL（apiVersion 26 SDK，真编译器，不是解析器） |
| **ArkTS 真编译（`entry`）** | ✅ 2026-09-14 解锁：`hvigorw default@CompileArkTS -p module=entry@default`（只编 UI 层，快）或 `devecocli build` 全量——`Index.ets` 与全部 Pane 首次获得真编译验证 |
| **HAP 打包** | ✅ 只差签名：`CompileArkTS`/`PackageHap`/`PackingCheck` 全过，`SignHap` 因 `build-profile.json5` 指向 Windows 证书路径失败（纯环境问题，与代码无关）；已产出 `entry-default-unsigned.hap`（138 MB，含 `libnode.so.127` + `libdshhost.so` + 全套原生库） |
| **语法错误守护** | ⚠️ 只有真编译器能抓：codelinter **检不出语法错误**（注入实测）⇒ 任何 `.ets` 改动必须过 `default@CompileArkTS`/`devecocli build`，**不能用 lint 代替** |
| 设计令牌棘轮（`check-design-tokens.mjs`） | ✅ 可跑且失败已注入验证：裸值**只许变少**（一刀切会永远红，等于没有门禁）；豁免须写明理由（`// token-exempt: …`） |
| 纯逻辑执行测试（`check-layout-fixtures.mjs`） | ✅ 可跑：`appstate/ui` 的纯逻辑 `.ets` 按 `.ts` 编译后本机直接执行（被测的是同一源文件，不是复制品） |
| ArkTS 静态检查（codelinter） | ✅ 可跑且覆盖面经注入证明（16 warn / 0 error） |
| 模型/协议往返 + 起 Host 的门禁（`check-origin-fence` / `check-plugin-toggle`） | ✅ 可跑且通过：需 **Node 22**（`--no-experimental-fetch` 在 Node 22+ 已移除；本机备 `/home/node/node22/bin/node`）；就绪等待可放宽 `HDSH_CHECK_READY_MS=180000`（本机 Host 冷启动实测 ~63s） |
| `devecocli check compat` | ❌ Linux 永不可用（CLI 明示仅支持 macOS/Windows，与 CLT 是否安装无关） |
| 在设备上真跑（装机） | ❌ 只差签名材料（运行期产物已齐，见 §3.3） |
| 布局/形态真机验收、视觉像素、手势、键盘、触控笔、系统权限、文件选择器 | ❌ 无模拟器、无真机；统一进 `docs/device-validation.md`（P4） |

### 3.1 已实测的基线（本轮）

- 静态门禁全绿：`arch-check`（75 文件）、`check-feature-wiring`（17 个功能接线 / 111 文件）、`check-builder-recursion`（99 个 @Builder 无自递归）、`check-dead-code`（0 死代码）、`check-store-readiness`、`check-parity`（含 `--self-test`：12 个正负样例全符合预期）。
- 真编译通过：HAR 五模块与 `entry`（`default@CompileArkTS`，0 error）均 BUILD SUCCESSFUL；全量 `devecocli build` 打通到 `PackageHap`，仅 `SignHap` 因签名证书在 Windows 那台机器而失败（⇒ 产出 138 MB unsigned HAP）；codelinter 16 warn / 0 error。
- `check-layout-fixtures` 533 条断言通过（四形态 + 断点边界 + 让步链 + 模型/呈现/设置域），`--self-test` 注入的失败被如实报出。
- 起真实 Host 的门禁 `check-origin-fence`（clean/absent/duplicated → 101；foreign → 403；no-cookie → 401）与 `check-plugin-toggle` 均 PASS；`check-model-roundtrip` 通过（真起 Host → 建会话 → 开 mux → 收到 snapshot 帧）。
- 仍跑不动的门禁是**盲区**而不是通过：`check-native-closure`（无 entry/build 原生库目录）、`compat-drift`（缺 `.research/protocol/contracts.json`，见 §3.3）——**门禁"通过"不等于"覆盖到了"**（docs/README 纪律 9）。
- 三条注入测试证明"守护本身可信"：① 注入 `return a +;` 到 appstate ⇒ 真编译器 BUILD FAILED、codelinter 一条不报；② `MAIN_MIN_VP` 280→320 ⇒ `check-layout-fixtures` 立刻红；③ 把 `workflow-run` 谎报成 `DONE`（并同步改统计）⇒ `check-parity` 以「陈旧登记」点名并退出 1。

### 3.3 不入库产物清单（新机器上要能编译/装机，需要哪些东西）

> 源码的唯一权威副本在版本库，缺了就是仓库缺陷，不是环境问题（曾发生 `.gitignore` 裸 `runtime/` 规则吞掉 `NodeRuntime.ets` 的事故，已修，见 §3.2）。**不入库的产物**（字节不进库、方法进库；都要能在本机生成，或从开发机拷贝）：

| 产物 | 路径 | 产生方式 | 本机状态 |
|---|---|---|---|
| Node 头文件 | `entry/src/main/cpp/node-headers/` | `tools/node-runtime/sync-node-headers.sh` | ✅ 已生成（3.8 MB） |
| koffi 源码 | `third_party/koffi/` | `node tools/fetch-koffi.mjs` | ✅ 已就位（4.6 MB） |
| Host 入口脚本 | `entry/src/main/resources/resfile/resources/app/` | `node tools/place-host-app.mjs`（源 `hostcore/app/` **在库里**） | ✅ 已就位 |
| 核心包 | `entry/src/main/resources/resfile/*.zip` | `node tools/pack-core.mjs --skip-install --place-in-app` | ✅ 已就位（rc.2 / rc.3 各 69 MB） |
| **libnode** | `entry/libs/{arm64-v8a,x86_64}/libnode.so.127` | `tools/node-runtime/build-node-ohos.sh`（**不参与链接**，`CMakeLists.txt` 故意不写进 `DT_NEEDED`） | ✅ arm64-v8a 已就位 ⇒ koffi 会被真正编进 HAP |
| 核心树 | `dist/core/work/dsh-core-*` | **不需上传**：随包 zip 本身就是完整树（29006 个文件），`unzip` 即物化 | 物化即可 |
| 协议契约 | `.research/protocol/contracts.json` | `node tools/protocol-contract.mjs` + 上游 checkout | ❌ 缺 ⇒ `compat-drift` 仍是盲区（**唯一仍跑不动的门禁**） |
| 签名材料 | `.p12` / `.cer` / `.p7b` | DevEco 自动签名（Windows 机器的 `C:\Users\hnzy1\.ohos\config\`，路径写在 `build-profile.json5`） | ❌ 缺（`SignHap` 需要） |

**结论**：**编译验证不需要任何外部产物**；**装机运行**才需要 `libnode`（+ 签名）——"编译过了"与"能装机"经常被混为一谈。另两条实测教训：① 工作区在 NFS 上，批量小文件操作必须换到容器本地盘再软链挂进项目（29k 文件解压：NFS ≈4 个/秒，本地 4 秒；`ln -sfn /home/node/… dist/core/work/…`）；② 从别处拷贝产物后用 `find <dir> -type f | wc -l` 核对文件数（"上传了目录" ≠ "文件到了"），用 `git diff --summary` / `git update-index --chmod=-x` 归一化 +x 位。

### 3.2 编译器与 codelinter 已实测发现的问题（新能力的第一批产出）

| 发现 | 性质 | 处置 |
|---|---|---|
| `platform/system/Clipboard.ets:33` 读剪贴板需要 `ohos.permission.READ_PASTEBOARD`（since 12），**应用未声明该权限**（声明的是 INTERNET / GET_NETWORK_INFO / KEEP_BACKGROUND_RUNNING） | **真实缺口**：`readText()` 在未声明权限时拿不到数据（源码自己 catch 成空串，表现为"粘贴没反应"） | 见 §4.6 `hdsh-clipboard` 行已由 `DONE` 降为 `PARTIAL`；登记在 §6。**这是编译器的功劳——此前矩阵把它记成 DONE** |
| `platform/notify/KeepAlive.ets:76` 同样报权限警告，但 `KEEP_BACKGROUND_RUNNING` **已声明** | 假警报：HAR 编译期看不到宿主 `entry` 的权限声明 | 不改；登记以免下次被当成缺陷 |
| `platform/system/SecretStore.ets:63` `'encode' has been deprecated` | 技术债（可继续用，未来版本会移除） | 进 §6 登记，P2 处理 |
| `platform/window/WindowRegistry.ets:151` `'getContext' has been deprecated` | 同上 | 进 §6 登记，P2 处理 |
| `hostruntime/src/main/ets/Index.ets` 7 条 `export *` 性能规则告警 | 性能建议（`@performance/hp-arkts-no-use-any-export-*`） | 不阻断；P2 视情收敛 |
| **`Circle().fill(...)` 六处**（`view/ConnectPane.ets:273`、`view/SessionListPane.ets:198`、`view/SettingsPane.ets:1144/1678/1754/1819`）：编译器标注 **`The 'fill' API is supported since SDK version 26.0.0`**，而项目 `build-profile.json5` 声明的是 **`compatibleSdkVersion: 6.1.1(24)`** | **真实兼容性缺陷（本轮最有价值的编译器产出）**：在 API 24 设备上 `fill` 不存在 ⇒ 三个状态点/色点（Host 授权状态、会话运行中脉冲、提供方色点）行为未定义。而这正是 `devecocli check compat` 该抓的东西——它**在 Linux 上不可用**（macOS/Windows only）⇒ **编译器警告是当前唯一的信号源** | 三选一（**需要决策，且要真机看视觉**）：① 改用 API 24 就有的写法（如 `Circle().backgroundColor(...)`，视觉是否等价需真机确认）；② `apiAvailable` 守卫 + 回退；③ 把 `compatibleSdkVersion` 提到 26。**决策前不得当作没问题** |
| `pages/Index.ets` 多处 `'getContext' has been deprecated`（约 12 处）、`'px2vp' has been deprecated`（3 处）、`'pushUrl' has been deprecated`（1 处）；`hostruntime/core/CoreStore.ets:424/430/438` `Function may throw exceptions. Special handling is required.` | 技术债 / 健壮性提示（可继续用，未来版本会移除） | 进 §6 无需登记（非行缺口）；P2 统一收敛 |

**一处端侧运行时缺陷（2026-09-14 实测确证 → 已修复并门禁固化）：`web_fetch` 在 jitless 下永远失败**

| 环节 | 事实（都有对照实验，不是推断） |
|---|---|
| 症状 | `web_search` 正常，`web_fetch` **打不开任何网页、任何 IP** |
| 机制 | 上游 `dsh-web-fetch-http` **不用全局 fetch**：它 `await import("undici")`（`lib/index.js:154`）、自建 `Agent` 并把 `dispatcher` 传进 fetch；而 **undici 的 HTTP 解析器是 WASM**（`lib/llhttp/llhttp-wasm.js`）。`web_search` 走本仓的 http/https 垫片（纯 JS），所以照常工作 —— 这就是"只有一个功能坏"的原因 |
| 为什么 `--jitless` 下没有 WASM | V8 的 `--jitless` 与 `--expose_wasm` 互斥（启动即打印 `disabling flag --expose_wasm`），`typeof WebAssembly === 'undefined'` |
| **对照实验**（同一份真实上游代码、同一个本地 HTTP 服务、同一套端侧 flag） | **A 臂（不注册钩子）**：真 undici 探针报 **`WebAssembly is not defined`**，真实上游 `HttpFetchProvider.fetch()` **4/4 断言全败**（`fetch failed` / `WEB_PROVIDER_ERROR`）—— 即用户报的症状。**B 臂（注册钩子）**：**8/8 全过** |
| 修复（**已接线、已端到端验证**） | `hostcore/app/undici-shim.mjs`（把 `undici` 模块名接到已有 http 垫片，并翻译 `dispatcher → lookup` 以**保住上游的 DNS 钉住/SSRF 防护**）+ `hostcore/app/undici-loader.mjs`（`module.register` 解析钩子）+ `main.js` 里的 `installUndiciNameHook()`（**仅在 `WebAssembly` 不可用时注册**：原生 undici 能用时不该被替换）。**不改上游源码、不改核心树**，只做运行期组合 |
| B 臂验证到的两条**安全语义**（本修复最有价值的部分） | ① 同源跳转仍被上游自己跟到最终 200（依赖 `redirect:'manual'` 语义原样透传）；② **跨源跳转仍被拒为 `WEB_REDIRECT_BLOCKED`**。若当初为了"让它能通"而放开 redirect 或忽略 lookup，这两条会立刻炸 |
| 真实 Host 侧证据 | Host 日志出现 `undici 解析钩子已注册（web_fetch 走本仓垫片，绕开 WASM）`，且 Host 照常启动、目录可读、会话可建（`tools/check-model-roundtrip.mjs --no-prompt`） |
| **固化门禁** | `tools/check-web-fetch-jitless.mjs`：**自带对照实验**——A 臂必须失败且必须给出 WASM 因果证据（否则判"说不出原因的失败"= 门禁报错），B 臂必须 8/8 通过。含 13 条判定器自检 |
| **跑它的 Node 版本** | 必须在 **Node 22**（`/home/node/node22/bin/node`）下跑：它用 `process.execPath` 起带 `--jitless --no-experimental-fetch` 的子进程，而 `--no-experimental-fetch` 在 **Node 22+ 已被移除**（fetch 转正）⇒ 默认的 Node 24 下两臂都失败，输出像"门禁红了"而其实是**环境不对**。2026-09-15 实测：Node 24 ❌（两臂都没有断言产出）/ Node v22.23.2 ✅ PASS（B 臂 8/8） |
| 顺带修掉的两处垫片缺陷（已生效、Host 复验正常） | ① `hdshFetch` 此前**硬编码自动跟 5 跳、忽略 `init.redirect`** ⇒ 上游用 `redirect:'manual'` 实现的"仅同源跟跳 + 跨源拒绝"安全策略会被静默绕过；现按 manual/error/follow 处理。② `lookup` 透传通道（上游的 pinned lookup 与 node 的 lookup 契约本就同构，直接可用） |
| **真机验收（2026-09-16 已完成）** | ① **先抓到一个"修复根本没进包"的真机缺陷**：`entry/src/main/resources/resfile/resources/app/` 里是 **2026-09-14** 的旧入口，`undici-shim.mjs`/`undici-loader.mjs` **不在 HAP 里** ⇒ 设备日志里 `undici 解析钩子…` **三条一条都不出现**（不是"注册失败"）。补齐 `node tools/place-host-app.mjs` + 重建 + 重装后，读数 `undici 解析钩子已注册（web_fetch 走本仓垫片，绕开 WASM）` ⇒ **D1 通过**（端侧嵌入式 Node 允许 `module.register()` 的独立线程解析钩子）。② 真机调一次 `web_fetch` 抓 `https://example.com`：工具结果 `Fetched https://example.com/ (HTTP 200)` + 正文，模型据此答出标题 ⇒ **D2 通过**。③ 教训（与 `docs/50` E148① 同源）：**改了 `hostcore/app/*` 必须重放 `place-host-app`**，而 `devecocli build` 不会替你跑、也没有门禁会红 —— 见 `docs/device-validation-readings.md` F9。④ 判据补一条：**三条日志一条都不出现 = 包里没有这次修复**（≠ 降级）。 |

- 环境陷阱（实测）：ESM `import 'node:http'` 在 `--jitless` 下进程收尾时会抛 internal undici 的 `WebAssembly is not defined`（CJS `require('node:http')` 干净）⇒ 端侧/jitless 相关的 harness 一律用 CJS `require` 取 `node:http`（本仓 `main.js` 本就如此）。
- 仓库不完整事故（2026-09-14，已修）：`.gitignore` 的裸 `runtime/` 规则在任意层级匹配，把 `entry/src/main/ets/runtime/NodeRuntime.ets` 挡在版本库外 ⇒ 新克隆编不过（8 个错误全部归因于这一个文件）。修法：规则锚定为 `/runtime/`（commit `ff6cbc9`）+ 源码补回版本库（commit `b906e13`）。教训：gitignore 目录规则要**锚定**；**"本地能跑" ≠ "仓库完整"**。
- Linux 上 `devecocli build` 会重写 5 个受版本控制的 `oh-package-lock.json5`（191 行纯行尾差异，`git diff --ignore-cr-at-eol` 为空可证）；**每次构建后必须 `git checkout --` 回退这些文件**，否则提交里混进行尾噪声。

---

## 4. 矩阵

列的含义：**Web 行为**取自官方包自述（来源见 §7）；**Harmony 状态层/界面**给落地文件（可核对）；**协议/端点**给命名空间（完整契约在 D2b）；四形态列与整体 `Status` 按 §1 口径。

### 4.1 外壳与架构

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `layout` 外壳与三栏布局 | 三栏 AppFrame + 拖拽手柄；`ctx.layout` 查看态服务（导航 + 面板） | `appstate/ui/Breakpoints.ets`（`layoutModeOf` / `detailPanelAvailable` / `navPresentation`）、**`ui/LayoutController.ets`（形态/几何决策与 `formFactor` 路由判定的唯一落点，含让步链 `concedeDetail`）**、`ui/Tokens.ets`（`Sz.NAV_RAIL` / `NAV_PANEL` / `DETAIL_PANEL` / `DETAIL_MIN`） | **v2 架构（2026-09-20）**：`pages/Index.ets` 按**形态 × 模式**矩阵条件渲染——`DESKTOP_LIKE`（平板/2in1/折叠展开）→ `WebShell`（Web 组件直载官方 Web UI，多栏布局为官方产物）；`PHONE`（手机/折叠闭合）→ `RemoteShell`（DSH Mobile 原生范式）。**v1 的 PC 原生三栏壳（`AppShell`/`SidebarShell`/`MainHeaderShell`/`TrackResizer`）已随 v2 删除**。**仍缺**（见 §6）：手机横屏档位子句待真机 | 无（纯前端） | DONE | PARTIAL | DONE | DONE | PARTIAL |
| `slots` 槽位注册 | SlotMap 声明合并 + 单次 register 组合 API + 四方共享 props | 无（ArkUI 声明式，无插件槽位系统） | 无 | 无 | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY |
| `primitives` 基础组件原子 | 纯 React 原子：控件 / 图标 / Markdown / JSON 检查器 | **v2 手机链 token 层**：`appstate/ui/MobileTheme.ets`（DSH Mobile `ui/theme/*.kt` 逐值移植：色板/间距/圆角/字号/动效）；`appstate/ui/HarmonyTheme.ets` 仅存续于未迁移的共用组件 | `entry/.../view/NativePrimitives.ets`：**`Ds*` 基元族**（`DsButton` / `DsIconButton` / `DsCard`(`dsCardStyle`) / `DsPill` / `DsSegmented` / `DsSheetHeader` / `DsEmptyHero` / `DsSectionHeader` / `DsStateDot` / `DsShimmerText` / `DsSkeletonBlock` / `DsDisclosureRow` / `DsToggleRow` / `DsContextMeter`，对照 DSH Mobile `ui/components/`）+ `NativeChip` / `NativeSectionTitle` / `NativeCard` / `NativeButton` / `NativeActionBar`；消费者：消息操作条、Composer 工具行与发送键、待决卡提交、工具卡 / 子代理卡 / 交付物动作行；六类浮层由页面根单一原生 Sheet 宿主承载（E292）。**`DESKTOP_LIKE` 的原子由直载的官方 Web UI 自带** | 无（纯前端） | — | — | — | — | DONE |
| `renderer` 渲染器与应用根 | React 槽位绑定 + `ctx.uiRenderer` + 组装后的应用根 | ArkUI 声明式 UI 由 `@Entry` 组件承载（无等价服务） | `pages/Index.ets` | 无 | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY |
| `session` 会话控制器适配 | React 适配 + **会话作用域槽位** | `appstate/store/SessionHub.ets`（模块级单例 + `HubSnapshot` 投影 + subscribe/snapshot） | 各 Pane 订阅 `HubSnapshot` | 复用全部会话端点（「会话作用域槽位」属 `slots` 的架构边界，见 §6；控制器能力完整） | DONE | DONE | DONE | DONE | DONE |
| `brand-official` 品牌槽位 | 侧栏 + 对话 Hero 槽位的官方品牌 | `docs/brand/`（icon/mark）、`AppScope` 图标 | Index 品牌头、连接页 | 无 | DONE | DONE | DONE | DONE | DONE |

### 4.2 会话与轨迹

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `conversation` 会话装配/外壳/输入区/队列 | 目标中立的 Conversation 装配、shell、composer、队列、视图导航 | **回合模型已落地**（`appstate/model/Turns.ets`：`groupTurns` / `hasProcessGroup` / `chatVisibleItems` / `processSummary` / `defaultExpanded`，纯函数 + 15 条断言）；**对话视图已改按回合渲染**：用户消息 → **过程分组（默认折叠、进行中展开）** → 回答（含 ActionStrip）→ 通知；轨迹视图保持全量条目台账。可见集合与折叠默认态都由模型回答（视图不再自写过滤规则） `SessionHub`：`sendPrompt` / `cancelTurn` / `removeQueuedItem` / `steerQueuedItem` / `editQueuedItem` / `selectSession` / `refreshTrajectoryByPage` | `view/ConversationPane.ets` + `view/Composer.ets` | `session/*`、`session/follow`（$events） | DONE | DONE | DONE | DONE | DONE |
| `chat` 对话目标与详情面 | Chat Conversation 目标、节点定义、渲染器、详情面 | `SessionHub.projectWireRecord`（D2 §8.7.7 的 32 种事件）、`model/Detail.ets` | `ConversationPane` + `view/DetailPane.ets` | 事件流 + `session/page` | DONE | DONE | DONE | DONE | DONE |
| `trajectory` 轨迹台账与时间轴 | 轨迹事件台账 + **交互式时间总览**（timing overview） | `model/Trajectory.ets`（8 种 `TrajectoryKind`）、`model/Present.ets` | `ConversationPane` 轨迹区 + `TimelineOverview`（每步独立耗时，FR-030；无 timing 显示 `-`）+ `TrajectoryInspector`（事件详情，层级缩进/折叠，FR-031；两处共用同一份模型） | 事件流投影 | DONE | DONE | DONE | DONE | DONE |
| `tool` 工具调用树与每工具呈现 | 工具调用树渲染器 + 按工具键的呈现槽位 | `ConversationPane.toolItem` 的 `callId` 合卡、`ToolState` 五态、`Present.previewOutput` 截断 | `ConversationPane` 工具卡（含 applied 对照 FR-012——工具结果 `meta.diffs` 已入投影、图像缩略 FR-013 与技能工具行 FR-014） | `tool/call`、`tool/result` | DONE | DONE | DONE | DONE | DONE |
| `subagent` 子代理目录与续跑 | 子代理会话目录、续跑路由 UI、`@` 引用源 | `TrajectoryKind.SUBAGENT`、`subagentCatalog` 投影、`model/Detail.ets` | `ConversationPane` 子代理卡（`SubagentCard`：转录视图 FR-022、追问 FR-023、中断 FR-024、`@` 引用候选 FR-025）+ `DetailPane` | `subagents/*`（含 `prompt` / `interruptByParent`） | DONE | DONE | DONE | DONE | DONE |
| `deliverables` 交付物 | 产出文件回合尾 + **可点的终答文件引用** | `TrajectoryKind.DELIVERABLE`、`deliverables/presented`、`model/Workspace.ets` 的 `deliverable` 标记 | `ConversationPane.deliverableItem`（正文内文件引用可点，FR-015）、`WorkspacePane` 品牌色标记；「分享」为真动作（沙箱外如实降级为分享路径），「保存」按平台事实禁用并写明原因 | `deliverables/*` | DONE | DONE | DONE | DONE | DONE |
| `goal` 长期目标栏 | GoalBar 停靠在输入区上方，读 goal 会话投影 | `SessionHub.refreshGoal`（E243） | `Index.ets` 目标栏 | `goals/*` | DONE | DONE | DONE | DONE | DONE |
| `jobs` 后台任务清单 | 会话头部的后台任务列表（镜像 `session/jobs` 帧） | `model/Wire.ets` 的 `JOBS` 投影（`SessionJob`） | 会话头「触发器 + 展开清单」（官方结构）+ 任务详情参数/输出下钻（FR-026）；轨迹保留 `JOB` 行作台账（官方轨迹无此 kind，刻意保留并登记） | `session/jobs` 帧 | DONE | DONE | DONE | DONE | DONE |
| `workflow-run` 工作流运行节点 | 持久 workflow-run 会话节点 + 嵌套成员展开 | 无 | 无 | 无（`dshcompat/Endpoints.ets` 内无 workflow 端点） | TODO | TODO | TODO | TODO | TODO |
| `cordis` 动态插件定义卡 | `cordis_define` 工具行 + run/stop 开关 | 仅有宿主侧端点常量（`dynamicCordisRunner/inventory`、`getClientCode`），**未接 UI** | 无工具行 | 端点已登记、无调用点 | TODO | TODO | TODO | TODO | TODO |
| `skill` 技能引用与技能工具行 | Web 技能引用 + 专用 skill 工具行 | `SessionHub.refreshSkills`（`skills/list`，E135 触发点已修） | 设置页技能清单 + 对话内技能工具行（FR-014）；**仍缺对话内 `@` 技能引用源**（见 §6） | `skills/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `message-feedback` 消息反馈 | 每消息反馈控件（**类别 → 可选备注 → 提交 → 存储态 → 撤回**） | `SessionHub.putFeedback`（含 `category`）/ `clearFeedback`（撤回，`ifVersion` 做 CAS）/ `refreshFeedback` / `feedbackOf`；类别取值域与请求类型**按上游源码核对**（`dsh-message-feedback/lib/types/types.d.ts`） | 消息操作条：复制 + 有帮助/没帮助 + **类别/备注面板 + 提交 + 撤回评价**；**动作清单只有一份**（`messageActionsOf`），行内操作条与**上下文菜单**共用（长按 ≡ 右键，由 `model/InputPolicy` 决定手势集合）；原先那条**不可点的**"复制/引用/重发"标签行已删除——三个动作现在都真的能用 | `messageFeedback/put`（`ifVersion: string\|null`）、`messageFeedback/delete`（`ifVersion: string`，**幂等**） | DONE | DONE | DONE | DONE | DONE |

### 4.3 输入区与控制器

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `input-trigger` 输入触发管线 | `/` 与 `@` 检测、候选菜单、选路到已注册源、**选中即替换当前 token**（`slash/input-consume-token`） | **`model/InputTrigger.ets`（纯模型：`detectTrigger` / `applyPick` / `needsTrailingSpace`）** + `SessionHub.refreshCommands` / `refreshReferences` | `Composer` 的 `@`/`/` 弹层（`draftAfterPick` 走替换，不再追加） | `commands/*`、`fileReferences/*`、`session/referenceCandidates` | DONE | DONE | DONE | DONE | DONE |
| `commands` 客户端命令面 | 全局目录缓存、`/` 源、**三种命令 UI 类型**、popupSelect 注册表 | `SessionHub.refreshCommands` / `executeCommand`（**读回执里的 `result.kind`**：受理=成功、处理器报错=把 `text` 显示出来、没解析出来=「宿主不认识这条命令」）；生命周期 `command/run`+`command/done` 投影成 `TrajectoryKind.COMMAND`（按 `commandId` 配对） | `Index.ets` 命令面板 + **`view/CommandRow.ets`**（命令原文 + 结局徽标 进行中/已完成/失败 + 结局文本）+ `view/CommandList.ets` 的 popupSelect 选项列表（FR-005；真 Host 取证：`popupSelect` 无宿主协议面，选项来自各业务入口，不另造通用弹层） | `commands/list`、`commands/execute`、`command/run`/`command/done` 事件 | DONE | DONE | DONE | DONE | DONE |
| `reference` 引用源 | 统一 Web `@file` 与 `@session` 引用源 | `SessionHub.refreshReferences` + `Wire.fileReferencesPayload`；`@` 三源已接：文件 / 会话 / 子代理（FR-025）；面包屑可点击回溯（FR-006）已接 | `Composer` 引用弹层（钻取 + 面包屑回跳 + 官方行信息）；**仍缺**：`~` 主目录展开（FR-007）——模型函数 `tildeExpand` 与快照字段 `hostHome` 已就位、无 UI 消费点（见 §6） | `fileReferences/list`、`session/referenceCandidates` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `attachment` 附件呈现 | 动态附件呈现：输入区、消息图、轨迹图三类槽位 | 输入区：`attachLocalFile` / `attachWorkspaceFile` / **`attachLocalImage`（内联，不走上传）** / `removeAttachment(key)` / `clearAttachments`；消息图与轨迹图：`projectImageBlock` → `TrajectoryItem.images` → `SessionHub.imageUrlOf`（`session/attachment` 读字节 + 会话作用域缓存） | 输入区 `Composer` 附件条（**图片给缩略图**）+ **`view/MessageImages.ets` 画廊**（单图大图 / 多图 64px 方图，点击就地放大；挂在 `MessageRow`，**对话与轨迹两个视图共用**；灯箱 `bindContentCover` 全屏原图，官方三条 CSS 几何）；**E384 已核实关闭**：随包 rc.2/rc.3 zip 内 `sharp.impl` 为 `@ohos-ports/sharp` 真件（lib/ + src/ 逐条目核对），设备出图待 D31 | `fileUploads/*`（文件）、**内联 `image` 片段**（图片，官方 `serializeImages()`）、`session/attachment`（读历史图） | DONE | DONE | DONE | DONE | DONE |
| `model-selection` 模型选择 | 共享模型目录 + 会话投影 + `session.selectModel` | `SessionHub.selectSessionModel` / `setDefaultModel` / `refreshProviderCatalog` | `Composer` 模型与强度 chip + 设置页模型页 | `llm/*`、`settings/*` | DONE | DONE | DONE | DONE | DONE |
| `plan` 计划模式控件 | 输入区内的 plan 控件（`conversation.input.plan` 座位）+ `/plan` 通道 | `HubSnapshot.planActive` / `planPending`（判据按官方 chip 语义：`pending ? !active : active`） | `Composer.toolRow()` 的「计划」chip（官方 `conversation.input.plan` 座位，判据 `pending ? !active : active` 与官方一致）+ 生效横幅（FR-010 视觉状态对齐）；切换走 `/plan` 命令 | 计划投影 + `commands/execute`（`/plan`） | DONE | DONE | DONE | DONE | DONE |
| `permission-presets` 权限面 | General 里的新会话默认 + 会话内 `/permission` 弹层 | `SessionHub.permissionsCurrent` / `permissionsOptions`；切换走 `/permission <id>` 命令（官方同款，FR-011）；Host 无该能力时如实显示「不可用」（本机实测无该能力 ⇒ 如实降级，不造假入口） | `Composer` 权限 chip（点开单选浮层）+ `Index.ets` 如实显示当前模式 | 读 `permissions` 投影 + `commands/execute`（`/permission`） | DONE | DONE | DONE | DONE | DONE |
| `approval` 审批 | 审批**接管输入区**，作用于有作用域的 Remote Event 瀑布流；卡片**两选**（`reject` / `allow-once`，与官方一致） | `SessionHub.handleWaterfall` → `PendingItem`、`Present.sortPending`（危险 > 审批 > 提问）；`Wire.projectApprovalRequest`（**缺 `toolName` 即交还链条**，不摆可批准的「未知操作」卡） | `view/PendingPane.ets` 审批卡（两选 / 危险动作权重反转 / 原始载荷可展开） | `approval/*`（到达与答复链路已实测；拒绝理由无上游承载字段——outcome 是闭集单词，登记在 D2 §8.7.5 / D3 §3.4） | DONE | DONE | DONE | DONE | DONE |
| `user-questions` 提问 | `ask_user_question` 的输入区接管 + 计划复核呈现 | `SessionHub.answerQuestion`（单选 / 多选 / 自由文本）、`PendingItem` | `PendingPane` 提问卡 | `user-questions/*` | DONE | DONE | DONE | DONE | PARTIAL |
| `agent-preset` 代理预设 | 三种面：后续会话的默认、**本会话座位**、**组合编辑器** | `SessionHub.refreshAgentPresets` / `copyAgentPreset` / `deleteAgentPreset` / `readAgentPreset`（`agentPresets/*`） | `view/SettingsPresets.ets`（预设名单卡：复制=官方唯一创建入口 / 查看 / 删除两步确认；agent-* 分区编辑器；回调经 `SettingsPane` → `TabContentView` 接到 `SessionHub`） | `agentPresets/*`（`copy` / `delete` / `read` 已接线） | DONE | DONE | DONE | DONE | DONE |

### 4.4 侧栏 / 工作区 / 设置

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `sidebar` 会话树 | 会话多级树、**搜索**、分组、状态点 | `model/SessionList.ets`（`pickTitle`、相对时间）、工作区为组；`model/SessionSearch.ets`（本地标题 + Host `session/search` 内容搜索，FR-003，无端点时如实降级） | v2：`SidebarShell`（PC 侧栏壳）已随原生 PC 链删除；`PHONE` 左抽屉 = `DrawerNav`（对照 `ChatListDrawer.kt`）+ `view/WorkspaceBrowser.ets`（工作区分组折叠/展开，FR-020）；会话搜索行由 `view/SessionSearch.ets`（T023 新建，对照 `SessionSearch.kt`）呈现；`DESKTOP_LIKE` 的侧栏/会话树由直载的官方 Web UI 提供。`SessionListPane` 已删除（P1-1） | `session/list`、`session/search` | DONE | DONE | DONE | DONE | DONE |
| `workspace` 工作区选择器 | 一个 WorkspacePicker 注册进侧栏与空态槽位 | `SessionHub.ensureWorkspace` / `openWorkspace` / `deleteWorkspace`（FR-029 工作区列表正确加载）；文件树作用域 id = 会话 id（`workspaceFileScopeId` 来源已确认，FR-027 已解） | `view/WorkspacePane.ets` | `workspace/*` | DONE | DONE | DONE | DONE | DONE |
| `directory-picker-native` 原生目录选择器 | 无渲染的目录流占据者，驱动宿主 OS 选择器 | `platform/system/FilePicker.ets`（`pickFolder`，`DocumentSelectMode` 仅 2in1） | 由工作区流程触发 | `directoryPicker/*` | BOUNDARY | DONE | DONE | DONE | BOUNDARY |
| `directory-picker-browse` 应用内目录浏览 | 应用内目录浏览面：渲染宿主列目录与新建原语 | `SessionHub.toggleDirectory` / `openFile` / `closeFilePreview` | `WorkspacePane` / `FileTreePane` 文件树（与右栏「文件」面板共用同一份树）+ `FilePreviewPane`（HTML/SVG 隔离预览 FR-028：Web 组件禁 JS/网络/文件访问，data: URI 渲染） | `workspaceFiles/*` | DONE | DONE | DONE | DONE | DONE |
| `settings` 设置域基础 | 设置命名空间作用域服务 + 权威设置槽位契约 | `SessionHub.refreshSettings` / `writeSetting` / `unsetSetting`（五种形态可写） | `view/SettingsPane.ets` | `settings/*` | DONE | DONE | DONE | DONE | DONE |
| `settings-general` 通用段 | 通用段 + 外壳触发/头部内容 + 设置词典 + 版本化欢迎通知 | 设置词典按官方译名覆盖（含 `locale.preference`） | `SettingsPane` 通用页 | `settings/*` | DONE | DONE | DONE | DONE | PARTIAL |
| `settings-models` 模型设置 | 模型设置 + 凭据联接 + 共享 onboarding 弹窗 | `SessionHub.setCredential` / `unsetCredential` / `refreshCredentials` | `SettingsPane` 模型页 + 凭据浮层 | `credentials/*` | DONE | DONE | DONE | DONE | DONE |
| `settings-plugins` 插件设置 | 插件段：功能自有页签 + 可配置宿主插件卡 | 用户行叠加（E91：种子 + 用户行，重启生效） | `SettingsPane` 插件页（启停 + 恢复默认） | profile 文件 + 插件清单 | DONE | DONE | DONE | DONE | DONE |
| `settings-plugin-inventory` 插件清单页签 | 只读 Cordis Loader 清单页签 | **已并入「插件」分区（E214）**：官方分两个分区靠的是**两个数据源**（可配置插件卡 vs Cordis Loader 清单），端侧只有**一份** `PluginItem[]` 投影 ⇒ 两个分区渲染同一批行，用户实测原话「插件和插件清单功能重复」 | `SettingsPlugins`（过滤框 + 可安装性徽标 + 两段说明） | 核心树扫描 + `classifyPlugin` | DONE | DONE | DONE | DONE | DONE |

### 4.5 主题与本地化

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `theme` 主题 | 插件前调色板 bootstrap + 无 DOM 的 ThemeRuntime（light/dark/system）+ `--dsw-*` 令牌样式 + 外观设置行 | `ui/Tokens.ets`（`Sp`/`Radius`(+`XS`)/`Fs`(+`CAPTION_XS`)/`Lh`/`Dur`/`Sz`/`Border`/`Breakpoint`/`SemanticColor`；`HarmonyColor.MASK` 统一模态遮罩）、**`ui/MobileTheme.ets`（v2 手机链：DSH Mobile token 逐值移植，明/暗两套色板）**、`themeModeOf` / `applyThemeMode`；**`tools/check-design-tokens.mjs` 强制「裸值只许变少」**，存量裸值已全部清除（FR-016：基线 total 0，2026-09-20；最后 4 处在 `Poc1.ets` 收口）；`HarmonyMaterial.IMMERSIVE_ENABLED = false`（API 固定 6.1.1(24) 的决策已入档） | 各 Pane 直接用 token；设置页外观行。**`DESKTOP_LIKE` 的 `--dsw-*` 令牌随官方 Web UI 直载生效** | `settings/*`（外观键） | DONE | DONE | DONE | DONE | DONE |
| `client-locale` 语言 | 宿主偏好 + 可扩展语言目录 + 内置词典 | 跟随系统语言（E117）+ `platform/system/Strings.ets`、`localizedOr`（兜底显示键名）；新增语言可经资源限定词目录扩展 | 设置页「语言」（`locale.preference`） | `settings/*` | DONE | DONE | DONE | DONE | DONE |

### 4.6 端侧独有（无 Web 对应；`hdsh-` 前缀）

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `hdsh-core` 核心版本管理 | 无（端侧独有） | `hostruntime/CoreStore` + `decideActivation` / `decideRollback` / `evictionCandidates` | `view/CorePane.ets`、`SessionHub.switchTo` / `rollbackTo` | 核心归档 + 事务 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-host` 端侧 Host 生命周期 | 无（Web 是浏览器客户端，Host 由 `dsh web` 提供） | `hostruntime/DshHost` + `runtime/NodeRuntime`（E90 协作式停止：本机实测退出码 0） | `CorePane` 起停 | 入口脚本 + `$DSH_HOME` | DONE | DONE | DONE | DONE | DONE |
| `hdsh-diag` 运行时与连接诊断 | 无 | `SessionHub.diagnose()` + `connection` 的五项判定（`home` 取 Host `facts.home`，桩值 `stubDiagnostics` 已删） | `view/DiagnosticsPane.ets` | `$events` `ready` 帧 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-notify` 系统通知 | 无（Web 用浏览器通知） | `model/Notify.ets`（六类策略/去重撤回键） | `platform/notify/NotificationCenter` | 无 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-hosttrust` 记住 Host 与凭据 | 无 | `platform/system/HostStore` + `SecretStore` | `view/ConnectPane.ets` | 认证面 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-multiwindow` 多窗口共享单一连接 | 无（一个标签页一个连接） | `SessionHub` 单例 + `platform/runtime/RuntimeSingleton` | 窗口账本（`registerWindow`） | 1 条 mux + 1 条 `$events`（抓包核对属设备验证轴，`docs/device-validation.md`） | DONE | DONE | DONE | DONE | DONE |
| `hdsh-share` 系统分享 | 无 | `platform/system/ShareBoard.ets` | 消息/文件操作 | 无 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-composer-drafts` 每会话输入草稿 | 官方 `dsh-client-ui-conversation` 的视图契约把它定义为**会话视图状态的一部分**（`contract/views.d.ts`：“Composer draft (persisted; survives session switches and reloads)”）⇒ 语义上等价于“每个会话各一份” | `model/ComposerDrafts.ets`（按会话存/取、最近写过排最前、空文本删条目、上限 24）+ 宿主 `switchDraftContext()`（`openSession` 与「离开会话页签」唯一经过的切换点） | `Composer`（输入框）+ 会话切换路径 | 无（本地状态） | DONE | DONE | DONE | DONE | DONE |
| `hdsh-privacy-disclosure` 应用内隐私与权限说明 | 无（Web 不做应用商店合规） | `model/PrivacyDisclosure.ets`（数据做法 6 条 + 权限 2 项 + 版本日期；**单一真值**） | `SettingsDevice.privacyRow`（设置 → 设备 → 隐私与权限说明，折叠块） | `module.json5` 的 `requestPermissions`（由 `tools/check-compliance.mjs` **逐项对账**） | DONE | DONE | DONE | DONE | DONE |
| `hdsh-clipboard` 剪贴板 | 无 | `platform/system/Clipboard.ets`：仅**写**（`copyText`）；**不做程序化读剪贴板**（E370 决定：粘贴走系统文本域自带菜单，不声明 `READ_PASTEBOARD`；`readText` / `clearClipboard` 已删） | 消息复制（多处 `copyText`） | 无 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-window` 窗口记忆 | 无 | `platform/window/WindowMemory.ets` | 由 `EntryAbility` 驱动 | 无 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-shortcuts` 快捷键 | 无（Web 用浏览器快捷键） | `ui/Shortcuts.ets`（13 个规格，含不可绑定项标记） | **v2**：原生 `view/ShortcutKeys.ets` 与 `Index` 根 `.keyboardShortcut` 分派已随 PC 原生链**删除**（避免与官方 Web UI 快捷键**双触发**，如 Ctrl+N）；`DESKTOP_LIKE` 的桌面快捷键由直载的官方 Web UI 自带。`appstate/ui/Shortcuts.ets` 规格表保留，当前 **entry 零消费**（残留裁决见 §6） | 无 | BOUNDARY | DONE | DONE | DONE | BOUNDARY |
| `hdsh-a11y` 无障碍 | 无（Web 走 ARIA） | `accessibilityText` + `Sz.TOUCH_MIN`；实机朗读验收属设备验证轴（`docs/device-validation.md`） | 各 Pane | 无 | DONE | DONE | DONE | DONE | DONE |

---

## 5. 统计（本轮）

| 状态 | 行数 |
|---|---|
| `DONE` | 41 |
| `PARTIAL` | 5 |
| `BOUNDARY` | 4 |
| `TODO` | 2 |
| **`合计`** | **52** |

> 统计口径：**矩阵 §4 各行 `Status` 列的计数**（52 行 = 39 个官方能力面 id + 13 个 `hdsh-` 端侧独有行）。
> 此前记作 51 行 / 12 个 `hdsh-` 行是漏数；且合计行原先没加反引号，在门禁解析里被当表头跳过、**从未被校验过**（盲点，2026-09-20 修正——现在合计会被实算校验）。
> **纪律（docs/README 第 8 条）：统计前先定口径，并把口径写出来。** 本节数字由 `node tools/check-parity.mjs` 实算核对——
> 首版手写的统计（18/22/4/2）与实算不符，正是这条纪律要防的错误；门禁现在会直接报出差额。

---

## 5.1 官方信息架构对齐（2026-09-14 重定义；2026-09-20 由 v2 转向取代）

> **v2 取代说明**：本节记录 v1 的「先搭原生页面框架」阶段。2026-09-20 架构转向后，**PC / 平板 / 2in1 / 折叠展开形态改由 Web 组件直载官方 Web UI**，原生三栏框架 `AppShell` / `SidebarShell` / `MainHeaderShell` / `TrackResizer` 已**删除**；v1 完成的原生框架对**手机链**仍有效（`RightbarShell` / `MainShell` / `WorkspaceBrowser` 等保留并服务 `RemoteShell`）。以下为历史记录，活跃口径以 §5.2 与 `docs/07` 为准。

项目所有者于 2026-09-14 重定义本阶段：**停止「缺一个功能 → 加一个组件」，改为先把页面框架搭正确**。工作令与分步计划见 `docs/ia-parity-plan.md`（P0 AppFrame → P1 Sidebar → P2 Main → P3 Rightbar → P4 Settings 域 → P5 视觉精修）。判断依据是「**功能不少、页面还是不像官方**」——根因是信息架构没落地，而不是缺按钮：

- 🟢 已就绪：Host / 协议 / 会话状态 / 多形态几何 / 输入模态事实；Prompt 泄漏（P0-1）已关闭（388 条 fixture 全过）；Conversation 数据模型（回合 / 跟随 / 可见性）。
- 🟢 **AppFrame 已完成（v1）**：`ShellTracks` + `AppShell` 三形态轨道 + `SidebarShell` / `MainHeaderShell` / `RightbarShell` / `TrackResizer` 各有其主，浮层门户提到页面根（`Index` 5040 → 4290 行）。**v2 后 `AppShell`/`SidebarShell`/`MainHeaderShell`/`TrackResizer` 已删除，`RightbarShell`/`MainShell` 转服务手机链**。
- 🟢 Markdown 已落地（P2-1）：`appstate/model/Markdown`（纯模型，31 条断言）+ `MarkdownRenderer.ets`，正文/思考/过程三处已渲染；刻意不做 HTML、表格、嵌套列表——缺的部分原文照显，不假装支持。
- 🔴 剩余（v1 计划）：Sidebar 重建（P1）、Conversation（P2）、Settings 域（P4）。**v2 后原生桌面框架收尾不再是主线**（桌面走 Web 直载）；手机链逐屏对照收口见 §5.2。

---

## 5.2 全量对等收口（2026-09-20）

Phase 12 收口时对全部 32 个 `PARTIAL` 行逐行核验（源码级证据：grep/read 落地文件），处置如下：

- **26 行 → `DONE`**：缺口已由代码关闭，或剩余项属设备验证轴（§1.2 `Validation` 限定"可静态验证"），或属已登记的上游协议事实/架构决定。
- **4 行保持 `PARTIAL`**（静态可实现而未做）：`layout`（双栏侧边浅层面板滑入动画与自身拖拽调宽）、`skill`（对话内 `@` 技能引用源）、`user-questions`（`nav.minimize/maximize` 卡片收起/展开）、`settings-general`（版本化欢迎通知本体）。
- **1 行 `PARTIAL` → `BOUNDARY`**：`hdsh-shortcuts`（Phone 无实体键盘，与 `directory-picker-native` 同口径；不变式 B 禁止整体 `DONE`）。
- **1 行核验后如实保持 `PARTIAL`**：`reference`——`~` 主目录展开（FR-007）的模型函数 `tildeExpand` 与快照字段 `hostHome` 已就位但**无 UI 消费点**（接线属静态可实现）；面包屑回跳（FR-006）已确认落地。

**E384 核实记录**：随包 `dsh-core-0.1.5-rc.2/rc.3-openharmony-arm64.zip` 内 `node_modules/sharp.impl` 逐条目核对为 `@ohos-ports/sharp@0.34.5-beta.12` 真件（`lib/` 14 文件 + `src/` 12 文件），非 602 字节桩 ⇒ `attachment` 行的图片能力空洞已关闭；设备出图仍由 `docs/device-validation.md` **D31** 判定。

**与 SC-001 的偏离如实说明**：spec 的 SC-001 期望 `DONE` 升至 47，实收 41——差值 6 = 五个如实保持的 `PARTIAL`（`layout` / `skill` / `user-questions` / `settings-general` / `reference`）+ `hdsh-shortcuts` 归位 `BOUNDARY`。不为凑数注水（不变式 D 之下统计须与实算一致）。

**设备验证轴**：整体仍 `PENDING`（§1.3）；本节的 `DONE` 一律不得读作"已在设备上验收通过"。

---

## 6. 缺口登记（任何非 DONE 的行必须在此）

格式：`id` → 缺什么 → 下一步。门禁强制"矩阵里非 DONE 的 id 必须出现在本表"。

> **2026-09-20 v2 转向后**：涉及 PC 原生组件（`AppShell`/`SidebarShell`/`MainHeaderShell`/`TrackResizer`/`ShortcutKeys`）的陈旧登记已按实况修订；§4 各行状态**计数不变**（52 行 = `DONE` 41 · `PARTIAL` 5 · `BOUNDARY` 4 · `TODO` 2），由 `node tools/check-parity.mjs` 实算核对。

| id | 缺什么（对等差距） | 下一步（归属） |
|---|---|---|
| `layout` | **手机横屏档位子句待真机**（800vp 宽是否落成双栏、要不要加高度/方向子句，需 `docs/device-validation.md`）；若按双栏落成，**侧边浅层面板的滑入动画与自身拖拽调宽**仍未做（面板与右抽屉共用同一 builder）。**v2 说明**：原「平板竖屏」侧的同项**不再适用**——平板 / 2in1 / 折叠展开走官方 Web UI 直载，多栏布局与面板交互由官方产物承担；v1 已收口项（把手拖拽 + 宽度记忆 + 弹性回弹 FR-019、键盘方向键调宽 FR-021、单栏 Sheet 切换器两形态共用 P2-13、三栏右栏七面板）随 PC 原生链删除而退役。`Phone` 列保持 `PARTIAL`（不变式 B 因此禁止整体 `DONE`） | 手机横屏档位子句 + 其浅层面板滑入/调宽（需真机确认档位，`docs/device-validation.md`） |
| `slots` / `renderer` | ① 官方是 React + 槽位插件化渲染；ArkUI 无槽位系统，第三方不能贡献 UI ② 但**「页面级 panel 选择」这层必须自建**（官方 `ui-layout` 正是用 panel selection 做统一框架）：`PanelRegistry` 属 `docs/ia-parity-plan.md` 的 P0/P3，与「第三方贡献 UI」是两件事，不要混为一谈 | 架构边界：**不追平**，能力由"构建期装配 + 设置页开关"替代；本条登记以免被当作缺陷反复讨论 |
| `reference` | **`~` 主目录展开未接线（FR-007）**：模型函数 `tildeExpand`（`appstate/model/InputTrigger.ets`）与快照字段 `hostHome`（Host `facts.home`）均已就位，但 `Composer` 的引用查询路径**没有消费点**（`hostHome` 在 `Index` 只赋值不读取）⇒ 用户敲 `@~/path` 时不会展开成绝对路径。官方 `dsh-client-ui-input-trigger` 用 `HostFacts.home` 做展开，接线属静态可实现。面包屑可点击回跳（FR-006）与 `@` 三源（文件 / 会话 / 子代理，FR-025）已确认落地 | 把 `hostHome` 传入 `Composer` 并在引用查询前做 tilde 展开（模型函数已备，接线量小）；其余真机项见 `docs/device-validation.md` |
| `skill` | 对话内 `@` 技能引用源未做（技能清单已入设置页、技能工具行已按 FR-014 呈现）；`skills/*` 端点已接（`refreshSkills`，E135 触发点已修） | P2：`@` 候选表并入技能源（与 `reference` 同一批） |
| `user-questions` | `nav.minimize/maximize`（卡片收起/展开，纯观感）未实现；`QuestionGroupCard` 已有 `nav.prev`（上一题）/ `action.skip`（跳过本题）/ `nav.cancel`（放弃整组，`ASK_CANCELLED` 帧与官方网关编码一致）与计划待审面板（`planReviewOf` 六条收窄规则逐条对齐，**意图只改布局不改可达答案**）；答案编码三条规则已按官方 `submitDrafts` 实现（单选+自定义 ⇒ `selected: []` + `custom`；多选 ⇒ 并存；跳过 ⇒ 空且不带 `custom`） | P2：补卡片收起/展开（纯观感，不影响可达答案）；观感与触控目标待真机 |
| `settings-general` | 版本化欢迎通知未做：设置词典里只有 `ui-onboarding/welcomeNoticeVersion`（「欢迎提示版本」设置行），没有通知本体 UI。设置分区注册表（`PanelLocation.SETTINGS` + `settingsSections()`，P4-1）已就位 | P2：欢迎通知本体（须先取证官方触发条件与文案）；设置页按域拆组件 |
| `directory-picker-native` | 手机不支持系统文件夹选择器（`DocumentSelectMode` 仅 2in1） | 能力边界：手机走 `pickDocument` 回退路径；**不删功能、不假装可用** |
| `hdsh-shortcuts` | Phone 无实体键盘 ⇒ 该形态不可用（能力边界，与 `directory-picker-native` 同口径，2026-09-20 由 `PARTIAL` 归位 `BOUNDARY`）。**v2 说明**：原生快捷键链（`view/ShortcutKeys.ets` + `Index` 根 `.keyboardShortcut` 分派）已随 PC 原生链**删除**（避免与官方 Web UI 快捷键双触发）；`DESKTOP_LIKE` 的桌面快捷键由直载的官方 Web UI 自带。`appstate/ui/Shortcuts.ets` 规格表保留但 **entry 零消费** | 真机阶段验证桌面快捷键由官方 Web UI 生效（`docs/device-validation.md`）；`Shortcuts.ets` 残留裁决（删除或降级为纯数据）归后续迭代 |
| `workflow-run` | 完全未实现；**协议侧也无 workflow 端点**（`dshcompat/Endpoints.ets` 内无匹配） | 先确认上游是否暴露 workflow 端点；无端点则本行长期 `TODO`（**不造无协议支持的假后端**） |
| `cordis` | 无 `cordis_define` 工具行与 run/stop 开关；端点已登记但无调用点 | P2/P3：需要 keyed tool row 能力（与 `tool` 同一批） |

> 与"行"无关的实测发现（构建/静态检查的技术债、以及 `entry` 无编译验证这一环境事实）不放进本表——
> 它们是**工程事实**，写在 §3 / §3.2；本表的每条必须对应 §4 的一个行 id（门禁会拒绝幽灵登记）。

---

## 7. 覆盖与来源

### 7.1 行集来源（可复现）

官方能力面 = 本机安装的 `@deepseek-ai/dsh` 依赖树里**全部 38 个** `dsh-client-ui-*` 包 + `dsh-client-locale`：

```
agent-preset approval attachment brand-official chat commands conversation cordis
deliverables directory-picker-browse directory-picker-native goal input-trigger jobs
layout message-feedback model-selection permission-presets plan primitives reference
renderer session settings settings-general settings-models settings-plugin-inventory
settings-plugins sidebar skill slots subagent theme tool trajectory user-questions
workflow-run workspace            （38 个）
+ client-locale                   （= 39 个官方能力面 id）
```

复现命令（在装着官方 dsh 的机器上）：

```bash
ls -d /opt/dsh/node_modules/@deepseek-ai/dsh-client-ui-* | sed 's#.*/dsh-client-ui-##' | sort
```

### 7.2 来源与版本标注（纪律：每条事实标注出处）

- 官方能力面清单与各包行为自述：本机官方客户端包 `package.json`（`name` / `description` / `dsh.client`），版本 **0.1.2-alpha.1**；`Web 行为` 列由其 `description` 意译（不新增未经查证的断言）。Harmony 落点：本仓库源码（HEAD `af00b0b`，行级可核对）。
- ⚠️ **同一性提示**：本项目协议基线是 **0.1.5-rc.1**（D2 §8.7），而本环境能拿到的官方客户端包是 **0.1.2-alpha.1** ⇒ §7.1 的能力面清单需用 0.1.5-rc.1 复核一遍：在拿到它的机器上跑 §7.1 的命令，与门禁内嵌清单比对——`node tools/check-parity.mjs` 会直接报出差集。

### 7.3 门禁

- `node tools/check-parity.mjs`：校验本矩阵（覆盖 / token / 不变式 / 缺口登记 / 统计）；`--self-test` 注入式自检（未被负测试验证的门禁等于没有门禁）；`--list` 打印解析出的行与状态。
- `node tools/check-layout-fixtures.mjs [--self-test]`：四形态 + 断点边界 + 让步链（纯逻辑，无需设备）；退出码 3 = 环境受阻（找不到 tsc），**不是通过**。
- `node tools/check-arkts-entry.mjs [--clean|--self-test]`：编 `entry`（UI 层）的 ArkTS，P1~P3 改 `Index.ets`/Pane 的守护；`--clean` 强制真正重新编译（增量时 `CompileArkTS` 会被 UP-TO-DATE 跳过）；自检含"hvigor 失败却退出码 0"的真实形态。

---

## 附 A：`Index.ets` 依赖关系与拆分基线（P1 输入）

附 A 已移除，见 git 历史。

---

## 变更记录

变更记录已移除，见 git 历史。
