# 功能对等矩阵（Parity Matrix）· P0

> 本文档于 2026-09-19 精简（仅删散文叙述；§4/§5/§6 全部表格逐字未动）；完整版见 git 历史。

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
| `layout` 外壳与三栏布局 | 三栏 AppFrame + 拖拽手柄；`ctx.layout` 查看态服务（导航 + 面板） | `appstate/ui/Breakpoints.ets`（`layoutModeOf` / `detailPanelAvailable` / `navPresentation`）、**`ui/LayoutController.ets`（P1：形态/几何决策的唯一落点，含让步链 `concedeDetail`）**、`ui/Tokens.ets`（`Sz.NAV_RAIL` / `NAV_PANEL` / `DETAIL_PANEL` / `DETAIL_MIN`） | **`pages/Index.ets` 已改为消费决策**：`applySize` 取 `decideLayout()`，navRail/detailColumn 的宽度取 `navWidthVp()`/`detailWidthVp()`（commit `fad954a`）——本文件不再有第二份断点/几何实现 | 无（纯前端） | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `slots` 槽位注册 | SlotMap 声明合并 + 单次 register 组合 API + 四方共享 props | 无（ArkUI 声明式，无插件槽位系统） | 无 | 无 | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY |
| `primitives` 基础组件原子 | 纯 React 原子：控件 / 图标 / Markdown / JSON 检查器 | **P1.5 已建层**：`appstate/ui/HarmonyTheme.ets`（Web 语义 → HarmonyOS 视觉的映射：HarmonyColor/Type/Spacing/Radius/Border/Elevation/Motion/Touch + `WEB_TOKEN_MAP`） | `entry/.../view/NativePrimitives.ets`：`NativeChip` / `NativeSectionTitle` / **`NativeCard`** / **`NativeButton`** / **`NativeActionBar`**（+ `harmonySheetOptions` 参数助手）；真实消费者：**消息操作条、Composer 工具行与发送键、待决卡提交、工具卡 / 子代理卡 / 目标任务卡 / 交付物动作行** | 无（纯前端） | — | — | — | — | PARTIAL |
| `renderer` 渲染器与应用根 | React 槽位绑定 + `ctx.uiRenderer` + 组装后的应用根 | ArkUI 声明式 UI 由 `@Entry` 组件承载（无等价服务） | `pages/Index.ets` | 无 | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY |
| `session` 会话控制器适配 | React 适配 + **会话作用域槽位** | `appstate/store/SessionHub.ets`（模块级单例 + `HubSnapshot` 投影 + subscribe/snapshot） | 各 Pane 订阅 `HubSnapshot` | 复用全部会话端点 | DONE | DONE | DONE | DONE | PARTIAL |
| `brand-official` 品牌槽位 | 侧栏 + 对话 Hero 槽位的官方品牌 | `docs/brand/`（icon/mark）、`AppScope` 图标 | Index 品牌头、连接页 | 无 | DONE | DONE | DONE | DONE | DONE |

### 4.2 会话与轨迹

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `conversation` 会话装配/外壳/输入区/队列 | 目标中立的 Conversation 装配、shell、composer、队列、视图导航 | **回合模型已落地**（`appstate/model/Turns.ets`：`groupTurns` / `hasProcessGroup` / `chatVisibleItems` / `processSummary` / `defaultExpanded`，纯函数 + 15 条断言）；**对话视图已改按回合渲染**：用户消息 → **过程分组（默认折叠、进行中展开）** → 回答（含 ActionStrip）→ 通知；轨迹视图保持全量条目台账。可见集合与折叠默认态都由模型回答（视图不再自写过滤规则） `SessionHub`：`sendPrompt` / `cancelTurn` / `removeQueuedItem` / `steerQueuedItem` / `editQueuedItem` / `selectSession` / `refreshTrajectoryByPage` | `view/ConversationPane.ets` + `view/Composer.ets` | `session/*`、`session/follow`（$events） | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `chat` 对话目标与详情面 | Chat Conversation 目标、节点定义、渲染器、详情面 | `SessionHub.projectWireRecord`（D2 §8.7.7 的 32 种事件）、`model/Detail.ets` | `ConversationPane` + `view/DetailPane.ets` | 事件流 + `session/page` | DONE | DONE | DONE | DONE | DONE |
| `trajectory` 轨迹台账与时间轴 | 轨迹事件台账 + **交互式时间总览**（timing overview） | `model/Trajectory.ets`（8 种 `TrajectoryKind`）、`model/Present.ets` | `ConversationPane` 轨迹区 | 事件流投影 | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `tool` 工具调用树与每工具呈现 | 工具调用树渲染器 + 按工具键的呈现槽位 | `ConversationPane.toolItem` 的 `callId` 合卡、`ToolState` 五态、`Present.previewOutput` 截断 | `ConversationPane` 工具卡 | `tool/call`、`tool/result` | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `subagent` 子代理目录与续跑 | 子代理会话目录、续跑路由 UI、`@` 引用源 | `TrajectoryKind.SUBAGENT`、`subagentCatalog` 投影、`model/Detail.ets` | `ConversationPane` 子代理卡 + `DetailPane` | `subagents/*` | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `deliverables` 交付物 | 产出文件回合尾 + **可点的终答文件引用** | `TrajectoryKind.DELIVERABLE`、`deliverables/presented`、`model/Workspace.ets` 的 `deliverable` 标记 | `ConversationPane.deliverableItem`、`WorkspacePane` 品牌色标记 | `deliverables/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `goal` 长期目标栏 | GoalBar 停靠在输入区上方，读 goal 会话投影 | `SessionHub.refreshGoal`（E243） | `Index.ets` 目标栏 | `goals/*` | DONE | DONE | DONE | DONE | DONE |
| `jobs` 后台任务清单 | 会话头部的后台任务列表（镜像 `session/jobs` 帧） | `model/Wire.ets` 的 `JOBS` 投影（`SessionJob`） | `ConversationPane` 的 `GOAL`/`JOB` 折叠块 | `session/jobs` 帧 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `workflow-run` 工作流运行节点 | 持久 workflow-run 会话节点 + 嵌套成员展开 | 无 | 无 | 无（`dshcompat/Endpoints.ets` 内无 workflow 端点） | TODO | TODO | TODO | TODO | TODO |
| `cordis` 动态插件定义卡 | `cordis_define` 工具行 + run/stop 开关 | 仅有宿主侧端点常量（`dynamicCordisRunner/inventory`、`getClientCode`），**未接 UI** | 无工具行 | 端点已登记、无调用点 | TODO | TODO | TODO | TODO | TODO |
| `skill` 技能引用与技能工具行 | Web 技能引用 + 专用 skill 工具行 | `SessionHub.refreshSkills`（`skills/list`，E135 触发点已修） | 设置页技能清单 | `skills/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `message-feedback` 消息反馈 | 每消息反馈控件（**类别 → 可选备注 → 提交 → 存储态 → 撤回**） | `SessionHub.putFeedback`（含 `category`）/ `clearFeedback`（撤回，`ifVersion` 做 CAS）/ `refreshFeedback` / `feedbackOf`；类别取值域与请求类型**按上游源码核对**（`dsh-message-feedback/lib/types/types.d.ts`） | 消息操作条：复制 + 有帮助/没帮助 + **类别/备注面板 + 提交 + 撤回评价**；**动作清单只有一份**（`messageActionsOf`），行内操作条与**上下文菜单**共用（长按 ≡ 右键，由 `model/InputPolicy` 决定手势集合）；原先那条**不可点的**"复制/引用/重发"标签行已删除——三个动作现在都真的能用 | `messageFeedback/put`（`ifVersion: string\|null`）、`messageFeedback/delete`（`ifVersion: string`，**幂等**） | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |

### 4.3 输入区与控制器

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `input-trigger` 输入触发管线 | `/` 与 `@` 检测、候选菜单、选路到已注册源、**选中即替换当前 token**（`slash/input-consume-token`） | **`model/InputTrigger.ets`（纯模型：`detectTrigger` / `applyPick` / `needsTrailingSpace`）** + `SessionHub.refreshCommands` / `refreshReferences` | `Composer` 的 `@`/`/` 弹层（`draftAfterPick` 走替换，不再追加） | `commands/*`、`fileReferences/*`、`session/referenceCandidates` | DONE | DONE | DONE | DONE | DONE |
| `commands` 客户端命令面 | 全局目录缓存、`/` 源、**三种命令 UI 类型**、popupSelect 注册表 | `SessionHub.refreshCommands` / `executeCommand`（**读回执里的 `result.kind`**：受理=成功、处理器报错=把 `text` 显示出来、没解析出来=「宿主不认识这条命令」）；生命周期 `command/run`+`command/done` 投影成 `TrajectoryKind.COMMAND`（按 `commandId` 配对） | `Index.ets` 命令面板 + **`view/CommandRow.ets`**（命令原文 + 结局徽标 进行中/已完成/失败 + 结局文本） | `commands/list`、`commands/execute`、`command/run`/`command/done` 事件 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `reference` 引用源 | 统一 Web `@file` 与 `@session` 引用源 | `SessionHub.refreshReferences` + `Wire.fileReferencesPayload` | `Composer` 引用弹层 | `fileReferences/list` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `attachment` 附件呈现 | 动态附件呈现：输入区、消息图、轨迹图三类槽位 | 输入区：`attachLocalFile` / `attachWorkspaceFile` / **`attachLocalImage`（内联，不走上传）** / `removeAttachment(key)` / `clearAttachments`；消息图与轨迹图：`projectImageBlock` → `TrajectoryItem.images` → `SessionHub.imageUrlOf`（`session/attachment` 读字节 + 会话作用域缓存） | 输入区 `Composer` 附件条（**图片给缩略图**）+ **`view/MessageImages.ets` 画廊**（单图大图 / 多图 64px 方图，点击就地放大；挂在 `MessageRow`，**对话与轨迹两个视图共用**） | `fileUploads/*`（文件）、**内联 `image` 片段**（图片，官方 `serializeImages()`）、`session/attachment`（读历史图） | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `model-selection` 模型选择 | 共享模型目录 + 会话投影 + `session.selectModel` | `SessionHub.selectSessionModel` / `setDefaultModel` / `refreshProviderCatalog` | `Composer` 模型与强度 chip + 设置页模型页 | `llm/*`、`settings/*` | DONE | DONE | DONE | DONE | DONE |
| `plan` 计划模式控件 | 输入区内的 plan 控件（`conversation.input.plan` 座位）+ `/plan` 通道 | `HubSnapshot.planActive` / `planPending`（判据按官方 chip 语义：`pending ? !active : active`） | `Index.ets` 面板内的计划开关（**不在 Composer 内**） | 计划投影 + 命令通道 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `permission-presets` 权限面 | General 里的新会话默认 + 会话内 `/permission` 弹层 | **只读**：`SessionHub.permissionsCurrent` / `permissionsOptions`（源码注明"切换需要 dsh-permission-presets"） | `Index.ets` 如实显示当前模式 | 读 `permissions` 投影；**无切换端点调用点** | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `approval` 审批 | 审批**接管输入区**，作用于有作用域的 Remote Event 瀑布流；卡片**两选**（`reject` / `allow-once`，与官方一致） | `SessionHub.handleWaterfall` → `PendingItem`、`Present.sortPending`（危险 > 审批 > 提问）；`Wire.projectApprovalRequest`（**缺 `toolName` 即交还链条**，不摆可批准的「未知操作」卡） | `view/PendingPane.ets` 审批卡（两选 / 危险动作权重反转 / 原始载荷可展开） | `approval/*`（到达与答复链路已实测） | DONE | DONE | DONE | DONE | PARTIAL |
| `user-questions` 提问 | `ask_user_question` 的输入区接管 + 计划复核呈现 | `SessionHub.answerQuestion`（单选 / 多选 / 自由文本）、`PendingItem` | `PendingPane` 提问卡 | `user-questions/*` | DONE | DONE | DONE | DONE | PARTIAL |
| `agent-preset` 代理预设 | 三种面：后续会话的默认、**本会话座位**、**组合编辑器** | `SessionHub.refreshAgentPresets` / `copyAgentPreset` / `deleteAgentPreset` / `readAgentPreset`（`agentPresets/*`） | `SettingsPane` 预设区 | `agentPresets/*` | DONE | DONE | DONE | DONE | PARTIAL |

### 4.4 侧栏 / 工作区 / 设置

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `sidebar` 会话树 | 会话多级树、**搜索**、分组、状态点 | `model/SessionList.ets`（`pickTitle`、相对时间）、工作区为组 | `view/SessionListPane.ets`（标题/副信息/状态徽标/未读点/选中态） | `session/list` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `workspace` 工作区选择器 | 一个 WorkspacePicker 注册进侧栏与空态槽位 | `SessionHub.ensureWorkspace` / `openWorkspace` / `deleteWorkspace` | `view/WorkspacePane.ets` | `workspace/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `directory-picker-native` 原生目录选择器 | 无渲染的目录流占据者，驱动宿主 OS 选择器 | `platform/system/FilePicker.ets`（`pickFolder`，`DocumentSelectMode` 仅 2in1） | 由工作区流程触发 | `directoryPicker/*` | BOUNDARY | DONE | DONE | DONE | BOUNDARY |
| `directory-picker-browse` 应用内目录浏览 | 应用内目录浏览面：渲染宿主列目录与新建原语 | `SessionHub.toggleDirectory` / `openFile` / `closeFilePreview` | `WorkspacePane` 文件树 + 预览 | `workspaceFiles/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `settings` 设置域基础 | 设置命名空间作用域服务 + 权威设置槽位契约 | `SessionHub.refreshSettings` / `writeSetting` / `unsetSetting`（五种形态可写） | `view/SettingsPane.ets` | `settings/*` | DONE | DONE | DONE | DONE | DONE |
| `settings-general` 通用段 | 通用段 + 外壳触发/头部内容 + 设置词典 + 版本化欢迎通知 | 设置词典按官方译名覆盖（含 `locale.preference`） | `SettingsPane` 通用页 | `settings/*` | DONE | DONE | DONE | DONE | PARTIAL |
| `settings-models` 模型设置 | 模型设置 + 凭据联接 + 共享 onboarding 弹窗 | `SessionHub.setCredential` / `unsetCredential` / `refreshCredentials` | `SettingsPane` 模型页 + 凭据浮层 | `credentials/*` | DONE | DONE | DONE | DONE | DONE |
| `settings-plugins` 插件设置 | 插件段：功能自有页签 + 可配置宿主插件卡 | 用户行叠加（E91：种子 + 用户行，重启生效） | `SettingsPane` 插件页（启停 + 恢复默认） | profile 文件 + 插件清单 | DONE | DONE | DONE | DONE | DONE |
| `settings-plugin-inventory` 插件清单页签 | 只读 Cordis Loader 清单页签 | **已并入「插件」分区（E214）**：官方分两个分区靠的是**两个数据源**（可配置插件卡 vs Cordis Loader 清单），端侧只有**一份** `PluginItem[]` 投影 ⇒ 两个分区渲染同一批行，用户实测原话「插件和插件清单功能重复」 | `SettingsPlugins`（过滤框 + 可安装性徽标 + 两段说明） | 核心树扫描 + `classifyPlugin` | DONE | DONE | DONE | DONE | PARTIAL |

### 4.5 主题与本地化

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `theme` 主题 | 插件前调色板 bootstrap + 无 DOM 的 ThemeRuntime（light/dark/system）+ `--dsw-*` 令牌样式 + 外观设置行 | `ui/Tokens.ets`（`Sp`/`Radius`(+`XS`)/`Fs`(+`CAPTION_XS`)/`Lh`/`Dur`/`Sz`/`Border`/`Breakpoint`/`SemanticColor`；`HarmonyColor.MASK` 统一模态遮罩）、`themeModeOf` / `applyThemeMode`；**`tools/check-design-tokens.mjs` 强制「裸值只许变少」**；`HarmonyMaterial.IMMERSIVE_ENABLED = false`（API 固定 6.1.1(24) 的决策已入档） | 各 Pane 直接用 token；设置页外观行 | `settings/*`（外观键） | DONE | DONE | DONE | DONE | PARTIAL |
| `client-locale` 语言 | 宿主偏好 + 可扩展语言目录 + 内置词典 | 跟随系统语言（E117）+ `platform/system/Strings.ets`、`localizedOr` | 设置页「语言」（`locale.preference`） | `settings/*` | DONE | DONE | DONE | DONE | PARTIAL |

### 4.6 端侧独有（无 Web 对应；`hdsh-` 前缀）

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `hdsh-core` 核心版本管理 | 无（端侧独有） | `hostruntime/CoreStore` + `decideActivation` / `decideRollback` / `evictionCandidates` | `view/CorePane.ets`、`SessionHub.switchTo` / `rollbackTo` | 核心归档 + 事务 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-host` 端侧 Host 生命周期 | 无（Web 是浏览器客户端，Host 由 `dsh web` 提供） | `hostruntime/DshHost` + `runtime/NodeRuntime`（E90 协作式停止：本机实测退出码 0） | `CorePane` 起停 | 入口脚本 + `$DSH_HOME` | DONE | DONE | DONE | DONE | DONE |
| `hdsh-diag` 运行时与连接诊断 | 无 | `SessionHub.diagnose()` + `connection` 的五项判定 | `view/DiagnosticsPane.ets` | `$events` `ready` 帧 | DONE | DONE | DONE | DONE | PARTIAL |
| `hdsh-notify` 系统通知 | 无（Web 用浏览器通知） | `model/Notify.ets`（六类策略/去重撤回键） | `platform/notify/NotificationCenter` | 无 | DONE | DONE | DONE | DONE | PARTIAL |
| `hdsh-hosttrust` 记住 Host 与凭据 | 无 | `platform/system/HostStore` + `SecretStore` | `view/ConnectPane.ets` | 认证面 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-multiwindow` 多窗口共享单一连接 | 无（一个标签页一个连接） | `SessionHub` 单例 + `platform/runtime/RuntimeSingleton` | 窗口账本（`registerWindow`） | 1 条 mux + 1 条 `$events` | DONE | DONE | DONE | DONE | PARTIAL |
| `hdsh-share` 系统分享 | 无 | `platform/system/ShareBoard.ets` | 消息/文件操作 | 无 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-composer-drafts` 每会话输入草稿 | 官方 `dsh-client-ui-conversation` 的视图契约把它定义为**会话视图状态的一部分**（`contract/views.d.ts`：“Composer draft (persisted; survives session switches and reloads)”）⇒ 语义上等价于“每个会话各一份” | `model/ComposerDrafts.ets`（按会话存/取、最近写过排最前、空文本删条目、上限 24）+ 宿主 `switchDraftContext()`（`openSession` 与「离开会话页签」唯一经过的切换点） | `Composer`（输入框）+ 会话切换路径 | 无（本地状态） | DONE | DONE | DONE | DONE | DONE |
| `hdsh-privacy-disclosure` 应用内隐私与权限说明 | 无（Web 不做应用商店合规） | `model/PrivacyDisclosure.ets`（数据做法 6 条 + 权限 2 项 + 版本日期；**单一真值**） | `SettingsDevice.privacyRow`（设置 → 设备 → 隐私与权限说明，折叠块） | `module.json5` 的 `requestPermissions`（由 `tools/check-compliance.mjs` **逐项对账**） | DONE | DONE | DONE | DONE | DONE |
| `hdsh-clipboard` 剪贴板 | 无 | `platform/system/Clipboard.ets`：**写**（`copyText` / `clearClipboard`）已接；**读**（`readText`）已实现但**未接线**，且需 `ohos.permission.READ_PASTEBOARD`（未声明） | 消息复制（多处 `copyText`） | 无 | DONE | DONE | DONE | DONE | PARTIAL |
| `hdsh-window` 窗口记忆 | 无 | `platform/window/WindowMemory.ets` | 由 `EntryAbility` 驱动 | 无 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-shortcuts` 快捷键 | 无（Web 用浏览器快捷键） | `ui/Shortcuts.ets`（13 个规格，含不可绑定项标记） | `view/ShortcutKeys.ets` + `Index` 分派 | 无 | BOUNDARY | DONE | DONE | DONE | PARTIAL |
| `hdsh-a11y` 无障碍 | 无（Web 走 ARIA） | `accessibilityText` + `Sz.TOUCH_MIN` | 各 Pane | 无 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |

---

## 5. 统计（本轮）

| 状态 | 行数 |
|---|---|
| `DONE` | 15 |
| `PARTIAL` | 32 |
| `BOUNDARY` | 3 |
| `TODO` | 2 |
| **合计** | **51** |

> 统计口径：**矩阵 §4 各行 `Status` 列的计数**（51 行 = 39 个官方能力面 id + 12 个 `hdsh-` 端侧独有行）。
> **纪律（docs/README 第 8 条）：统计前先定口径，并把口径写出来。** 本节数字由 `node tools/check-parity.mjs` 实算核对——
> 首版手写的统计（18/22/4/2）与实算不符，正是这条纪律要防的错误；门禁现在会直接报出差额。

---

## 5.1 当前阶段：官方信息架构对齐（2026-09-14 重定义）

项目所有者于 2026-09-14 重定义本阶段：**停止「缺一个功能 → 加一个组件」，改为先把页面框架搭正确**。工作令与分步计划见 `docs/ia-parity-plan.md`（P0 AppFrame → P1 Sidebar → P2 Main → P3 Rightbar → P4 Settings 域 → P5 视觉精修）。判断依据是「**功能不少、页面还是不像官方**」——根因是信息架构没落地，而不是缺按钮：

- 🟢 已就绪：Host / 协议 / 会话状态 / 多形态几何 / 输入模态事实；Prompt 泄漏（P0-1）已关闭（388 条 fixture 全过）；Conversation 数据模型（回合 / 跟随 / 可见性）。
- 🟢 **AppFrame 已完成**：`ShellTracks` + `AppShell` 三形态轨道 + `SidebarShell` / `MainHeaderShell` / `RightbarShell` / `TrackResizer` 各有其主，浮层门户提到页面根（`Index` 5040 → 4290 行）。
- 🟢 Markdown 已落地（P2-1）：`appstate/model/Markdown`（纯模型，31 条断言）+ `MarkdownRenderer.ets`，正文/思考/过程三处已渲染；刻意不做 HTML、表格、嵌套列表——缺的部分原文照显，不假装支持。
- 🔴 剩余：Sidebar 重建（P1）、Conversation（P2）、Settings 域（P4）；视觉精修排最后（框架错则间距 / 颜色 / 动效全白做）。

---

## 6. 缺口登记（任何非 DONE 的行必须在此）

格式：`id` → 缺什么 → 下一步。门禁强制"矩阵里非 DONE 的 id 必须出现在本表"。

| id | 缺什么（对等差距） | 下一步（归属） |
|---|---|---|
| `layout` | ⓪ **右栏面板体系已落地（P3-1）**：`selectedRightPanel` 此前在模型里躺了好几轮没有消费者（右栏无条件渲染 `DetailPane`）——现在 `RightbarShell` 按**面板 id** 分派、标题取 descriptor 的 `label`，选择经注册表校验。**同时如实登记了缺口的真实位置**：官方那六个候选（文件/轨迹/工具/子代理/交付物/预览）**席位在、内容视图没做**，按 E110 的口径一律 `available: () => false`（不能填的入口不进选择集，避免"点进去是空面板"）；**右栏面板体系已收口（P3-2…P3-6）**：官方六个候选**全部接上**——**「文件」**（`FileTreePane`，与工作区页签共用）、**「轨迹」（P3-6）**（`TimelineOverview`，与主区轨迹视图共用；右栏只放总览，见模型注释）、**「工具」**（`ToolCard`，与过程流共用）、**「子代理」**（`SubagentCard`）、**「交付物」**（`DeliverableCard`）与 **「预览」**（`FilePreviewPane`）；另有本仓特有的 **「详情」**（`right.detail` = 已投影的 sections 清单，属官方 `conversation.detail` 那一类，**不冒充**「文件」）⇒ 共七个可用面板。可用面板 ≥2 ⇒ 标题行出现**切换器**（只有一个可用面板时不画）。**仍缺**：侧边面板滑入动画、面板自身拖拽调宽、单栏 Sheet 里的切换器。⇒ 后续把某个候选的内容视图做出来，只需把它的 `available` 改成 true，面板体系不用动① **拖拽调宽手柄已落地**（P3）：此前 `decideLayoutWithDetail` 那条"用户想要的宽度"路径在模型里做好、也有 fixture，**却没有 UI 去产生这个宽度**（`decideLayout()` 直接用常量）。现在三栏下栏间把手可拖，宽度存进 `detailWidthDesired`；拖拽策略（可用空间 `detailRoomOf`、夹取不跳变、**左拖变宽**的方向规则、记忆值收窄）全在纯模型里，25 条断言覆盖 ② **宽度记忆已落地**：`platform/LocalPrefs` 只存/取一个数字（平台层**不许**依赖 appstate，判定规则留在模型 `detailWidthOf`），启动读回、拖拽结束落盘；落盘失败给一句轻提示而不是静默失效 ③ **平板侧边浅层面板已落地**（P3 §12）：此前双栏与手机一样弹半模态 Sheet，把列表整个盖住，"边看列表边看详情"这件事就没了。现在详情呈现由模型的三值枚举决定并**真的被视图消费**——`DetailPresentation`：三栏=真右栏 / 双栏=侧边浅层面板 / 单栏=整页（顺带**删掉了此前那个`detailOverlay: boolean`：它算了却没有任何消费点，视图用自己的 `sheetKind()` 判断）。**仍缺**：侧边面板的**滑入动画**（transition 必须挂在面板自身的根上，而它与三栏右栏共用同一个builder，值得专门做而不是顺手加）、侧边面板**自身的拖拽调宽**（目前只沿用记住的宽度）、把手的**键盘调整**（聚焦后用方向键） ④ **待决（需真机）**：D3 §2 只按宽度判定 ⇒ **手机横屏（800vp 宽）会落成双栏**；要不要加高度/方向子句，看真机效果后定。另有一条**已实测的边界事实**：详情栏只在 TRIPLE（≥840vp）并排，而该档可用空间最小 320vp > `DETAIL_MIN`(260vp) ⇒ 让步链的 `DETAIL_CLOSED` 分支**当前不可达**（防御性保留，已钉成断言，将来调阈值时会**有意识地**让这条分支复活） | P3 已做：输入模态真实接入 + 拖拽把手 + 宽度记忆。下一步：平板侧边浅层面板；把手键盘调整；手机横屏档位子句（需真机） |
| `primitives` | ① 原语已落 `NativeChip` / `NativeSectionTitle` / `NativeCard` / `NativeButton` / `NativeActionBar`（+Sheet 参数助手）；**弹层/Dialog/导航**仍未原语化 ② **浮层已全部改原生、且宿主已提到页面根**：六类浮层（详情 / 枚举选择 / 目录 / 凭据 / 文本设置 / 整值设置）统一由**单一浮层宿主**承载——全应用只在**页面根**挂一次 `bindSheet`，`sheetKind()` 从既有状态**派生**当前该显示哪个（不另立字段，避免两个真值来源），`closeSheet()` 一处复位；手写遮罩与"整屏居中卡片"全部删除（遮罩由原生 Sheet 提供）。**修法说明（P0 收尾时发现）**：门户原先挂在**单栏布局的根节点**上，而四类浮层的触发点都在主区内容里（主区三形态都可见）⇒ **双栏/三栏下这些浮层根本打不开**（"不是没做，是够不着"）。提到页面根后与形态无关——这正是官方 Web「portal 挂在 `App` 根、不属于任何 pane」的语义（E292）③ `deliverableItem` 的保存/分享是**禁用+写明原因**（平台无文件保存能力） ④ `WEB_TOKEN_MAP` 目前是**文档化数据 + fixture 可校验**，但还没有"视图必须经映射取色"的强制门禁（现有棘轮只管裸 fontSize/圆角/描边/颜色字面量） | P1.5 已做：HarmonyTheme 语义层 + 前两个原语 + 两处接入（消息操作条、Composer 工具行）。下一步按 P1.5 清单推进（Surface/Button/Card/Popup/Sheet/Dialog/ActionBar/Navigation），每个原语都**当时就接一个真实消费者**，不落没人用的空构件 |
| `slots` / `renderer` | ① 官方是 React + 槽位插件化渲染；ArkUI 无槽位系统，第三方不能贡献 UI ② 但**「页面级 panel 选择」这层必须自建**（官方 `ui-layout` 正是用 panel selection 做统一框架）：`PanelRegistry` 属 `docs/ia-parity-plan.md` 的 P0/P3，与「第三方贡献 UI」是两件事，不要混为一谈 | 架构边界：**不追平**，能力由"构建期装配 + 设置页开关"替代；本条登记以免被当作缺陷反复讨论 |
| `session` | 无"会话作用域槽位"；控制器能力（`SessionHub`）已具备 | 不追平（同上）；控制器本身已 DONE |
| `conversation` | ① 回合渲染已落地（对话视图按回合 + 过程分组折叠/展开），但**轨迹视图仍是条目级台账**——§8 的"统一模型"目前只在对话视图生效 ② PC/2-in-1 列随 `layout` 的缺口 | P1 已做：回合模型（15 条断言）+ 对话视图按回合渲染 + 行数单位收敛 + **sticky-follow 独立成模型**（`model/Follow`，9 条断言；顺带修掉两个真实缺陷——切会话与发消息都不恢复跟随）。下一步：轨迹视图也按回合组织（或明确"它就是全量台账"并在文档里定死）。**更正一条此前的错误判据**：上一轮把"回答本身可折叠"写成缺口是错的——官方折叠的是**过程**，回答是回合的目的、收起它会把这一轮的意义藏起来；故**不做**，此项从缺口移除 | | P1：Conversation 重构（先做模型，再改视图） |
| `trajectory` | ① **交互式时间总览已落地**（`model/Timeline`，47 条断言）：轨迹视图上方给「总计 + 每格比例条 + **水平拖动可聚焦事件**」（官方 `timeline.overviewAria` 原文语义）+ 聚焦格详情（种类 / 第 n 格 / 开始于 / 耗时）。种类与文案**逐字取官方** `dsh-client-ui-trajectory`（`system/user/context/compacted/message/tool/subtool` 七个中文标签、`timeline.total/started/noTimingData` 文案）；比例用**累计起点**摆放（不是浮动相加，避免四舍五入出缝隙），拖动越界夹到首尾。顺带把**投影出来却一直没人显示**的 `sessionStats` 时间四项接上界面（模型用时 / 工具调用用时 / TTFT / TPS）；轮次与步数**不在这里重复**（会话头部那行已有，E125/E129） ② 我方条目→格子的映射有**四类刻意不产生格子**（交付物 / 目标 / 任务 / 错误；官方把错误记在格子上的 `isError`，不是一种 kind），且 `SUBAGENT` 一律算 `TOOL`（官方的 `tool`/`subtool` 之分需要父子调用关系，我方 `TrajectoryItem` 没有该字段） ③ **仍缺**：**逐步计时**（官方的「首 token / 解码」来自官方客户端自己的 metrics，`timingRecorded` 只存在于其 bundle 内，我方投影没有 ⇒ 没有消费者的函数不留，故本模型不提供；要按步显示得先让投影带上这些字段）；**双向联动已做**：条 → 列表（拖动松手/点选后滚到那一格对应的条目，用 `ScrollAlign.START` 对齐，这样"列表首行"与"聚焦格"一致、不会自己抖自己）+ 列表 → 条（滚动时首行对应的格子自动聚焦，拖动条期间关掉这一路以免互相覆盖）；聚焦条目在列表里用**左侧色条**标出（与搜索命中的 brand 色区分，用 `font_emphasize`）。**事件详情已做（P7-4）**：读官方 `dsh-client-ui-trajectory` 的字典 —— 它点一条事件开出「事件详情」面板（`details.event`，成对字段：状态/用途/提供方/模型/工具调用/子工具调用/错误/结果/来源/层级/助手消息，可关闭、可拖动调宽）。我们做**同一件事的等价物**：新建 `model/TrajectoryDetail.ets`（空值不产生行 ⇒ 有几行画几行）+ `view/TrajectoryInspector.ets`，**两处共用同一份**（会话头时间线下方、右栏「轨迹」面板下方）；官方那些来自它自己事件模型的字段（purpose / provider / hierarchy / subtoolCalls）我们的投影**没有** ⇒ 不画，而不是画"未知"。**仍缺**：官方详情面板的**拖动调宽**与**层级/子工具调用**两类字段（要投影先带上父子调用关系）；`SYSTEM`/`CONTEXT`/`COMPACTED`/`SUBTOOL` 四种种类**保留但暂不可达**（我方投影没有对应事件类型，保留是为了标签表与官方一致） | P2 已做：映射规则 + 比例条 + 拖动聚焦 + 统计四项。下一步：投影接逐步 metrics；点格子打开该条详情（真正意义的 inspector） |
| `tool` | ⓪ **`web_fetch` 在端侧 jitless 下曾完全不可用**（根因、修复与对照实验见 §3.2；已由 `tools/check-web-fetch-jitless.mjs` 固化；真机起线程一项仍待验收）① **`ToolPresenter` 已落地**（`model/ToolPresentation`：终端/读取/写入/编辑/搜索/网络/图像/提问 + 通用，17 条断言；图标、语气、展开默认态、无障碍文案都由模型判定，视图只映射）② **路径摘要已落地**（`toolSummaryOf`，12 条断言：终端的命令 / 读取的路径 / 搜索的"模式 · 范围" / 网络的 url；提炼不到才退回清理后的原文——此前这里写着"直接显示参数原文"，是过期描述，已更正）③ **改动对照已落地**（`model/ToolDiff`，45 条断言）：`write`/`edit`/`str_replace_editor` 出加/减行对照并逐行着色，规则逐条对齐官方 `intendedDiff`/`validEscalationFields`（含提权闸门、空 `old_string` 归一成 null、`replace_all` 类型校验、路径 trim 判空），失败/被拒**不出**对照卡（对齐官方 `isError → null`）④ 仍缺：**applied 对照**（官方结束后优先用工具结果 `meta.diffs` 显示"实际落盘"的改动；本仓投影只解析 `TOOL_NAME`/`TOOL_ARGS`/`TOOL_OUTPUT`/`CALL_ID` 四个槽位、**未携带 `meta`** ⇒ 只能显示"意图"）；**嵌套调用不区分**（官方对 `parentCallId !== undefined` 不出对照卡，而 `TrajectoryItem` 无父子关系字段）；结果预览的类别化（图像类应出缩略而非等宽文本）；对照的逐行着色**折叠阈值**是呈现层取舍（官方阈值无证据，未假装对齐） | P2 已做：类别判定 + 每类一个系统符号 + 失败默认展开 + 按类别提炼摘要 + 改动对照卡。下一步：确认事件里 `meta` 的槽位名并接进投影（applied 对照）；图像类结果缩略 |
| `subagent` | 无续跑路由 UI；子代理不作为 `@` 引用源 | P2 |
| `deliverables` | ① **右栏「交付物」面板已落地（P3-4）**：`DeliverableCard` 与过程流共用同一份卡；筛选是纯模型（`itemsOfKind` / `deliverablesOf`：保序 + 同 id 去重）；空态如实说明「本次会话还没有交付物」② **正文内的可点文件引用已接（P9-3）**：行内代码里的路径若命中**本回合产出的文件**就变可点，点击复用 P7-21 那条链路（读内容 + 切到工作区页）；认不出来/歧义的保持普通代码（官方 "never guesses"）；**「分享」已做成真动作（P9-7）**：沙箱内的交付物**分享文件本体**（平台 `fileUri` → 系统分享面板）、沙箱外**如实降级**为分享**路径**（按钮文案变「分享路径」）、定位不到则禁用并写明原因；**「保存」仍禁用**（平台确实没有“另存为”——这条理由是真的）| P3-4 已做面板；正文内文件引用待 P2 收尾 |
| `jobs` | ① **会话头的后台任务条已落地（P2-2）**：模型 `appstate/model/Jobs`（40 条断言：live 判定 / 状态点语义 / 五种文案 / 时长三档与小时封顶 / 排序 / 计数 / 定时器按需）此前**一个视图消费者都没有**——中枢一直在维护 `jobs` 字段，界面只在轨迹里显示 `JOB` 行。现在：中枢投影 → `Index` → `MainShell` → 会话头上的任务条（有任务才出现；`Flex(wrap)` 任务块：状态点语义色 + 名称 + 状态文案 + 耗时，live 任务每秒走字，`jobTickerNeeded` 决定要不要开定时器；无障碍整段取自 `jobListA11y`）② 已用 `tools/check-feature-wiring.mjs` 把这条接线**钉成回归**（模型判定 + 中枢投影 + 会话头传参三段）③ **呈现已按官方改为"触发器 + 展开清单"（P7-3）**：读 `dsh-client-ui-jobs` 源码 —— 官方在会话头只放一个**按钮**（`StateDot`（**仅 live 时**）+ `{count} 个后台任务运行中`/`{count} 个后台任务` + 折叠指示，`aria-label: 后台任务`），点开才是清单（状态点 + `job.kind` + `job.label` + `job.detail ?? 状态文案` + 耗时）；我们此前是**常开**的换行任务条，还带一句"展开收起全部任务在轨迹"的指引（官方没有这个指引，且任务一多就把会话头撑高）。现在同结构、同文案。**登记一处刻意保留的差异**：轨迹视图里仍有 `JOB` 行（官方轨迹**没有** job 这个 kind —— 实测其 bundle 里 `job` 出现 0 次），那是我们的**台账**用法（何时起了哪个任务）；去掉它要动轨迹的单元格索引映射（搜索命中与时间总览都按 `items` 下标走），在没有真机复核的情况下不划算 ⇒ **保留并如实登记**。④ 任务详情（参数/输出）未接 | P2-2 已做：任务条。下一步：轨迹 `JOB` 行与任务条收敛为同一处语义；任务详情下钻 |
| `workflow-run` | 完全未实现；**协议侧也无 workflow 端点**（`dshcompat/Endpoints.ets` 内无匹配） | 先确认上游是否暴露 workflow 端点；无端点则本行长期 `TODO`（**不造无协议支持的假后端**） |
| `cordis` | 无 `cordis_define` 工具行与 run/stop 开关；端点已登记但无调用点 | P2/P3：需要 keyed tool row 能力（与 `tool` 同一批） |
| `skill` | 无对话内技能引用；无专用 skill 工具行 | P2 |
| `message-feedback` | ⓪ **面板已拆成独立组件（P2-3）**：`view/MessageFeedback.ets`（表单态归它，每敲一个字不再重绘整个会话列表）；宿主保留"哪条开着 + 回执 + 提交策略"。① **Edit / More 未接**（Retry 已接：用户消息的"重发"走 `session/prompt`，有真实协议面；助手消息的"重跑那一轮"无端点 ⇒ 不给）（§10 列出的其余操作）：它们需要「重跑某一轮 / 改完再发」的协议面，本仓**没有对应端点** ⇒ 不放点了没反应的按钮（假入口），缺口显式留在这里 ② 面板与 chip 的**观感、触摸目标、四形态**均待真机验收 | P1 已做：类别（契约 7 个取值）→ 可选备注 → 提交 → 存储态回显 → **撤回**（`messageFeedback/delete` + CAS）；P2：Retry/Edit 需先确认协议面是否存在 |
| `commands` | **回执与生命周期已对齐（P7-13）**：① 回执不再只看 `result.ok` —— 官方判定是「命令被宿主**受理**即成功」（生命周期已入日志、结局作为过程节点呈现），**只有** `result.kind === 'error'` 才把处理器给的 `text` 显示出来，`value === undefined`（没解析出来/名字不存在）按官方 `unknown or malformed command` 的语义提示并**保留输入**；② `command/run`（`{commandId,name,args?}`）与 `command/done`（`{commandId,kind,text?}`）按 `commandId` 落成**一条**命令条目（此前 `command/done` 因 `standalone:false` 被直接丢弃、`command/run` 被当内部事件隐掉 ⇒ 执行命令后界面上**什么也不会发生**），视图见 `CommandRow`。**真 Host 取证**：闭环 M2g 真跑一条只读命令（本机选到 `/feedback`）⇒ 回执 `command.rejected` + 宿主原文，轨迹出现 1 条已兑现命令条目（`kind=error`）。**参数分流已做（P9-4）**：Host 的 `input.hint` 是权威信号 ⇒ 要参数的命令不再“选中即执行”（此前必然被 Host 拒绝并弹英文 usage），而是把 `命令 + 空格` 填进输入框并说明；命令行把参数提示与说明各占一行。**边界（已核实并登记）**：`popupSelect` 机制本身**没有协议面**——Host 的 `CommandDescriptor` 只有 `{name, description, input?}`，官方注释也写着贡献 “lives entirely on the client (no host descriptor)”，选项来自各业务包自己的协议 ⇒ 我们的等价物是按命令各自的具体入口（输入区权限 chip / 模型选择 / 目录选择），**不另造一套通用弹层**；**仍缺**：② 命令节点**位置精度**：官方是独立过程节点（在发生处），我们走回合的 NOTICE 槽位（同回合内排在回答之后，信息相同、位置粗一点）—— 留着真机看是否值得单开一槽 | P2：三种 UI 类型与 popupSelect |
| `reference` | **两个源都已接**：`@file`（`fileReferences/list`）与 `@session`（`session/referenceCandidates`）合并进同一个候选表；插入文本**一律取宿主给的 `mention`**（`Wire.projectSessionReferences` 的注释写明了为什么不能自拼 `@session:<id>`——mention 的语法由 Host 决定）。**P7-14 修掉一处插入缺陷**：此前是"往草稿末尾追加"，用户敲了 `@src/fo` 再点候选会得到 `@src/fo@src/foo.ts `（半截查询词留在正文里、且**长得像一条引用**会被 Host 当引用解析）；官方是**替换当前 token**，现在由 `model/InputTrigger.ets` 统一（含目录引用的未闭合引号 `@"dir/` **不补空格**，留给下一次补全继续钻）。**菜单形态与钻取已对齐（P9-5）**：官方该源的 `showGroupTitle: false`（**不画分节标题**，靠行的外观区分），但**顺序是文件在前、会话在后**（我们同）；行信息按官方 `fileCandidate`/`sessionCandidate` 逐条实现（目录名带尾斜杠、父目录**仅未钻孔时**显示、会话行「位置 · 时间」且同工作区不写位置、无 cwd 写「（无工作目录）」）；**选中目录继续钻**（菜单不关 = 官方 `{text, continue: true}`）；**钻取列表给面包屑**（`crumb.root`=工作区，官方注释：钻孔“欠用户一条回得去的路”）；顺带修好**引号形态**（`@"含空格的路径"` 此前查询词带着引号 ⇒ 匹配不上）。**仍缺**：① 面包屑不可点（官方按段可回跳）；② `cwd` 未做 `~` 缩写（官方 `abbreviateHomePath` 需要 Host 的 `home`）；③ `@session` 的"插入后 Host 真能解析"仍需真机端到端验
| `attachment` | **三个槽位都有了代码（P0-3 看图 + P0-4 发图）**，但**设备上能不能真的出图，取决于一个本轮才查清的 Host 事实（E384：随包的 `sharp` 是桩）**。① 看图（P0-3）：官方 `dsh-client-ui-attachment` 三个槽位的数据形状已从源码读齐：图片块是 `{type:'image', attachment:{attachmentId, mediaType, bytes, width, height, name}}` —— **只有不透明引用**，字节必须另走 `session/attachment`（官方 `ISession.readAttachment`）。我们此前把它降级成正文里的字面 `[image]`；现在投影收集引用（`projectImageBlock`）+ 中枢读字节缓存（`imageUrlOf`/`imageErrorOf`/`retryImage`，键 = `会话 id:附件 id`，上限 24 张，断开即清空）+ `view/MessageImages.ets` 按官方几何呈现（`singleFit` 240/[0.25,4]/不放大小图；多图 64×64、gap 10、圆角 16；按角色对齐），几何真值在零依赖 `model/MessageImage.ets`。② 发图（P0-4）：`pickImage()`（**系统图库**，无需权限）+ `attachLocalImage()`（**内联**，不走上传）+ 官方顺序拼装（`attachmentPlanFor`：图片在前、正文在后；文件回执仍在正文之后——那段没有官方依据，故不改）+ 官方四条类型白名单（`image/png|jpeg|webp|gif`，其余上游会抛错）+ **魔数嗅探**（图库 URI 可能不带扩展名）+ 12 MiB 内联上限 + 附件条缩略图。③ **E384 的能力空洞（上一轮发现，本轮已修）**：随包核心 zip 里 `node_modules/sharp.impl` 曾是 **E79 留下的 602 字节桩**，而 `dsh-attachment-local` 正是用它做图片接纳 ⇒ **设备上一切图片处理必然失败**，且 Host 会把它说成 `Unsupported or malformed image data.`（看起来像用户的图坏了）。构建期闸门（`assertSharpImplIsReal()` + 只读 `--check-sharp`）与取证通道（诊断报告「原生件」一行）上一轮已加；本轮完成**修复**：重新物化 ⇒ `sharp.impl` = `@ohos-ports/sharp@0.34.5-beta.12` 真件、随包 zip 重打并逐字核对，宿主探针改为**走调度器**（原先绕过它，会在设备上误报不可用）。**本地只能证明到"真件在位 + 观测通道诚实"**：该 `.node` 对着 OHOS libc 链接，glibc 开发机上必然 `invalid ELF header` ⇒ **设备上能否出图由 D31 判定**。**灯箱已做（P9-2）**：点缩略图（单图与方图都行）打开**全屏原图预览**，几何按官方三条 CSS（`contain` + 1600 上限 + 视口减 80，**只缩不放**）、无障碍文案逐字取官方中文字典、`bindContentCover` 承担“文档级模态 + 系统返回键接管”（即官方的 portal 语义）。登记三处差异：预览的是同一份字节（官方是原图 URL）、背景用主题底色（官方半透明遮罩；`backgroundColor` 默认白色，手写 rgba 被禁）、关闭按钮 44（本仓触控下限）而非官方 36。**仍缺**：图片**另存/分享**（平台无保存能力，与 `deliverables` 同批）。**真机验收**：`docs/device-validation.md` **D31**（第 0 步先看 Host 图片解码器）与 D29 | P0-3/P0-4 代码就位 + 核心真件已就位；**设备能力待 D31 验收** |
| `plan` | **更正一条过期描述**：本行原先写「控件不在 Composer 内／`/plan` 通道未对齐」——实际两件都已就位：`Composer.toolRow()` 里有「计划」chip（官方 `conversation.input.plan` 座位，判据 `pending ? !active : active` 与官方一致），宿主 `togglePlan()` 走的就是 `/plan` 命令（`executeCommand`）。剩余：chip 的观感与触控目标待真机验收 | 已就位（真机验收见 `docs/device-validation.md`） |
| `permission-presets` | **已接线（P7-6）**：读官方 `dsh-client-ui-permission-presets` —— 切当前会话权限走的是**命令**（`live.command('/permission ' + option.id)`），新会话默认是**设置项**（`settings.general.item` id=permission，schema 驱动），没这个能力时显示官方字典的 `unavailable`（「不可用」）。我们照此：能力判定用权限投影（`permissionsOptions`），有能力则权限 chip 可点 → 复用既有 `ChoiceSheet` → 选中走 `/permission <id>`；没能力则显示「不可用」并把原因写进无障碍文案。**真机实测（`tools/check-core-loop.mjs` M2 段）**：本机 Host `current=(空) options=0`、命令表 5 条里没有 `/permission`、12 组设置里没有权限键 ⇒ 官方那两个入口在这台 Host 上本来就都不可用，故**如实显示「不可用」而不是给死按钮**。**仍缺**：新会话默认项由 Host 的 schema 声明，端侧不造假入口（本机 Host 未声明） |
| `approval` | **输入区接管已做（P7-2）**：读官方 `dsh-client-ui-approval` 源码 —— 它往 `conversation.composer` 槽位注册**优先级 1、只选"本会话当前那一条"**的组件（composer takeover），卡片结构是 `strip`（圆点 + `waiting: 等待审批`）+ `headline`（`escalation: 工具 {toolName} 请求越权执行`）+ `command`（等宽原始请求）+ 动作行。我们照此实现：**状态带 + 标题 + 等宽原始请求 + 单条交互卡**，且**只处理本会话**的待决（此前把中枢全量铺在输入区上方 ⇒ 在会话 A 里能替会话 B 放行，属误操作）；其它会话还有多少条用一句提示指向「待决」页。`Present.sortPending` 的排序仍是官方语义 | P1：`PanelController` + Composer 接管式界面（与提问卡同一批） | **词汇与卡片对齐官方（P7-17）**：官方 `dsh-client-ui-approval` 的卡片只有两颗按钮（源码里就是 `answer("rejected")` 与 `answer("allowed-once")` 两处），因为上游 `ApprovalOutcome` 是**闭集**（`allowed-once | rejected | cancelled | unavailable`，`dshcompat.APPROVAL_OUTCOMES` 是活常量）——**没有任何持久授权**。我们此前多一颗「本次会话内均允许」，而它在本端**什么都没记住**（`always` 标记只写进旁路日志）⇒ 用户以为「以后别问了」，实际下次照样问：那是「点了没反应」的假入口，已删。同轮还删掉了 `Wire` 里那套**没有任何调用点**的产品层词汇（`ApprovalDecision{ALLOW_ONCE,DENY,ALWAYS}` / `approvalOutcomeFor` / `decisionIsClientSideOnly` / `approvalAnswer`，只靠 barrel 再导出撑着）——`ALWAYS` 正是那颗假按钮的余毒。另：审批请求改用 `projectApprovalRequest` 读，**缺 `toolName` 时交还链条**（不做「未知操作 + 允许一次」的卡片：那等于让用户批准一个自己看不见的操作）。**仍缺**：拒绝理由无法随应答上传（上游 outcome 只是一个词，没有承载理由的字段；登记在 D2 §8.7.5 / D3 §3.4）
| `user-questions` | **输入区接管已做（P7-2）**（与 `approval` 同一批：官方 `dsh-client-ui-user-questions` 也 inject `conversation.composer`），单条提问同样只在本会话输入区出现。**整组已做（P7-5）**：官方提问是一张**整组**卡（一个按钮前进、最后一题变「提交」、`nav.prev` 回看、`action.skip` 跳过、提交前逐题校验并用 `error.incomplete` / `error.unanswered` 拦阻）。**我们此前只投影 `questions[0]`** —— 后几道题界面上不存在、用户答不了，而 Host 要等**整组**答案才继续 ⇒ **会把一轮对话卡死**（不是排版差距）。现在：整组投影进 `PendingItem.questions[]`、应答改成**整组一次回**（`answerQuestionGroup`）、新增 `QuestionGroupCard` 逐题导航与草稿。**两类细节已取证并按官方实现（P7-7）**：① **推荐标记不是字段，是标签后缀** —— 官方 `parseRecommendedLabel` 用正则 `/\s*(?:\((?:recommended|推荐)\)|（(?:recommended|推荐)）)\s*$/i` 解析，显示剥掉后缀并加「推荐」，**提交仍送原标签**（送剥过的版本 Host 匹配不上）；② **答案编码三条规则**（官方 `submitDrafts`）：单选 + 自定义 ⇒ `selected: []` + `custom`；多选 ⇒ 两者并存；跳过 ⇒ 空选择且不带 `custom`。我们此前"一律都送"是**错的**（单选里同时送选项与自定义文本，Host 会拿到用户没表达过的组合）。**`nav.cancel` 已按取证实现（P7-9）**：取证链三层 —— 官方 `questionError()` 造出 `name='UserQuestionError'` + `code='ASK_CANCELLED'` 的错误，`pending.cancel()` 把它抛出，网关（`dsh-api-gateway/lib/client.js`）再把"监听器抛错"编码成 `{kind:"rejected", error:{name,message,code}}`。我们照此发**同一帧**（`Wire.questionCancelledError` + `outcomeRejected`）—— **不是** `{kind:'next'}`：后者是"我不处理，交给下一个应答者"，Host 会继续问别人，与"用户明确取消这次提问"语义不同。视图侧补上官方文案的「放弃整组问题」按钮（失败时**不移走卡片**，否则用户以为已经取消）。**计划待审面板已做（P7-10）**：官方 `planReviewOf` 把"带 `intent.kind='plan-review'` 的**单题**请求"换成计划面板 （`计划待审` + 计划正文 + `确认执行` / `拒绝` / `去聊天里说`），**六条收窄规则**（单题 / 有 detail / 非多选 / 选项 ≤2 / `intent.approve` 指名的标签必须在选项里 / 其余至多一项当拒绝）少一条就退回通用题组 —— 官方注释写明理由：**意图只改变布局，绝不改变"可达的答案"**。三颗按钮的线上动作：确认执行与拒绝=用对应**标签原文**作答；去聊天里说=`pending.cancel()`（就是我们上一轮实现的 `ASK_CANCELLED` 帧）。**我们此前连 `intent` 都没投影** ⇒ 计划请求只能以通用题组的样子出现。**仍缺**：`nav.minimize/maximize`（卡片收起/展开，纯观感）（`plan.header: 计划待审` / `plan.approve: 确认执行` / `plan.decline: 拒绝` / `plan.discuss: 去聊天里说`）；我们的 `PendingItem` 是**单条**模型，没有"整组"这个概念 ⇒ 要对齐得先让投影带上问题组 | P1：同上（与 `approval` 同一批） |
| `agent-preset` | 缺**组合编辑器**（composition editor）与「后续会话默认」的显式面；复制/删除/查看已有 | P2 |
| `sidebar` | ① **官方 Sidebar 不是「页签栏」**：它承担 Brand / New Session / **Workspace→Session 树** / Panel 列表 / Settings（固定底部）/ 折叠 rail。我方当前页签只有 工作区 / 核心 / 设置（`SESSIONS` 是 `WORKSPACES` 别名、`PENDING` 不占页签），本质仍是**传统 Tab 架构** ② **更正一条过期描述**：本行原先写"我方是 `WorkspacePane` + `SessionListPane` 两个并列 Pane"——`SessionListPane`（221 行）**早就没有任何渲染点**（E108 把「会话」页签并进工作区视图之后，会话列表改由 `workspaceGroup` 渲染；它只剩 Index 里的一条死导入）。P1-1 已**删除该死文件**，并把主区里那棵真实的树（`workspaceHub` + `workspaceGroup`，285 行）抽成 `view/WorkspaceBrowser.ets`（30 门面成员，**一行都不用改名**——它本来就只经显式门面访问宿主）③ **树已挂进侧栏**（P1-3）：`SidebarShell` 的 PANEL 呈现里，树在品牌行与面板入口之间（官方顺序）；窄版行（P1-2）为 240vp 宽改行不改树。三栏下主区的「工作区」页签**不再重复一份**，只说明"列表在左侧"（判据取自 `ShellTracks`，与 AppShell 选轨道同源）。单栏 / 双栏仍由主区承载（底部标签栏 / 图标条放不下树）④ **一级导航已改由注册表驱动**（P1-4）：入口的存在/顺序归 `sidebarEntries` / `sidebarPinnedEntries`（沉底是清单属性 `SIDEBAR_PINNED_ORDER`）、图标与文案归按面板 id 的编译期映射、高亮归宿主；`SidebarShell` 里再无 `NavTab`。`NewSession` 已成为品牌行下方的一级入口；Settings 沉底；核心席位按 E110 标记为不可用（语义写进模型，不再靠视图"恰好没遍历它"）⑤ **单栏已是抽屉**（P1-5）：手机侧栏按官方语义"盖在页面上"（页头根页有导航入口、点外部收起、返回键第一优先级收抽屉、选入口/会话自动收起）；底部标签栏**暂时保留**（过渡，见 `docs/50` E306）。剩余：无「分组」显式交互（现为工作区为组）；RAIL 上无 NewSession；**会话搜索已做（P7-1）**：输入即切成**扁平结果列表**（标题 + 工作区 + 内容片段），标题命中本地算、内容命中走 Host 的 `session/search`（真 Host 若未挂该端点 ⇒ **如实降级为标题匹配并说明**，见 `docs/50` §15.4ax） | P1-1…P1-5 已做（树抽出 → 窄版行 → 挂进侧栏 + 主区去重 → 注册表驱动入口 + NewSession + Settings 沉底 → 单栏抽屉）。**下一步（P1-6）**：会话搜索、"分组"、RAIL 上的 NewSession；真机确认后决定手机是否撤掉底部标签栏。真机项见 `docs/device-validation.md` **D11/D12** |
| `workspace` / `directory-picker-browse` | 真实文件树受 `workspaceFileScopeId` 阻塞（D4 已登记的未决来源） | 先确认该 id 的来源（协议事实）再接线 |
| `directory-picker-native` | 手机不支持系统文件夹选择器（`DocumentSelectMode` 仅 2in1） | 能力边界：手机走 `pickDocument` 回退路径；**不删功能、不假装可用** |
| `settings-general` | ① **P4-1：设置分区已进注册表**（`PanelLocation.SETTINGS` + `settingsSections()`；官方四段在前、本仓特有四项标 `owner: 'hdsh'` 在后）；分区状态回归 `NavigationState.settingsSection`（视图里的 `@State tab` 已删除）② 版本化欢迎通知未确认 | P2 剩余：欢迎通知；P4-2：设置页按域拆组件 |
| `settings-plugin-inventory` | **分区已并入「插件」（E214，按用户实测）**：官方两个分区靠两个数据源，端侧只有一份 `PluginItem[]` ⇒ 同一批行印两遍。合并后这一能力面在**我们的**形态里由「插件」一页承担（过滤 + 可安装性徽标 + 只读说明）；若将来端侧能拿到 Cordis Loader 的独立清单（与可配置插件卡不同源），再把分区拆回去。**下一步**：真机复核 D22 第 4/5 条（只有一个插件分区、过滤实时生效） |
| `theme` | ⓪ **沉浸光感（API 26 空间化材质）暂不可用**：决策为 `targetSdkVersion` 保持 `6.1.1(24)`（2026-09-14），代价是材质只能用系统阴影表达；升级路径与「升级后只用在常驻外壳、不要全页滥用」的功耗提醒写在 `HarmonyMaterial` 注释里。① 无 `--dsw-*` 等价的**可声明令牌层**——现在是「token 常量 + 棘轮门禁」，不是可被主题切换的声明式变量；无 visual swatch ② **存量裸值 58 处**已被棘轮冻结，其中**图标字号 46 处**（12/14/16/18/20/22/28/32/36/40 共十档）、**圆角 5/9**、**颜色字面量 14 处**（`Color.Gray/Red/Green` 集中在 `Poc1.ets`，另有 `badge` 的 `Color.White`）需要一次设计收敛——**收敛会改变视觉，必须真机验收**，故不塞进机械替换 | P1 已做：token 补齐（`Border.HAIRLINE` / `Radius.XS` / `Fs.CAPTION_XS`）+ **机械替换 36 处**（数值不变 ⇒ 视觉无变化）+ 棘轮门禁。P2：图标档位与圆角的视觉收敛（真机）+ 声明式令牌层 |
| `client-locale` | 语言目录可扩展性未确认（官方支持扩展目录） | P2 |
| `hdsh-diag` | 诊断页 `home=` 仍显示桩值 `D:/work`（D4 待收口第 2 项） | 核实 `runDiagnostics()` 与 `getHostHome()` 空值路径 |
| `hdsh-notify` | 逐条通知的渠道路由被 SDK 标称枚举不一致阻塞（D4「仍待真机」第 5 项） | 真机阶段验证 |
| `hdsh-multiwindow` | "1 条 mux + 1 条 `$events`"的抓包核对待设备 | 真机阶段验证 |
| `hdsh-shortcuts` | 表与分类完成；**绑定与实机响应待验收**；Phone 不适用（无实体键盘） | 真机阶段验证 |
| `hdsh-a11y` | 朗读文本与触摸目标已实现，**待真机朗读验收** | 真机阶段验证 |
| `hdsh-clipboard` | **已收口（P5-7 / E370）——「不做程序化读剪贴板」是决定，不是缺口**。原先登记的是"`readText` 只有定义 + 桶导出 ⇒ 登记了没接"，本轮逐个拍板后**删掉 `readText` / `clearClipboard`**：① 应用**没有**主动读剪贴板的需求 —— 用户往输入框粘贴走的是**系统文本域自己的**粘贴菜单（应用不参与）；② 程序化读要么声明 `ohos.permission.READ_PASTEBOARD`（与 README 设计原则 2「不申请特殊权限」冲突），要么用系统安全控件 `PasteButton`（SDK 里确实有，API 10 起）—— 但它**不能自由改样式**（安全控件样式由系统校验，改了可能不授权）且**被布局截断就不授权**，而工具行在 360vp 手机上已经很挤；为一件系统已提供的事付这两样代价不划算；③ `clearClipboard` 的注释写着"含凭据的复制之后应主动清理"，但**全仓没有复制凭据的入口**（复核三处 `copyText`：诊断报告〔已显式剔除凭据〕/ 右栏行复制 / 消息复制）⇒ 策略没有前提。**将来若新增"复制凭据"入口，需同时接清理**（本行据此重开）。复核过的复制路径：`copyText` 三处，均正常 | 已收口（真机只验"系统粘贴菜单可用 + 应用未声明 READ_PASTEBOARD"，见 `docs/device-validation.md` D21） |

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
