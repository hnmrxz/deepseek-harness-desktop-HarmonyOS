# 功能对等矩阵（Parity Matrix）· P0

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

**是**：

- 官方 Web 能力面的**全量覆盖表**（行集 = 官方 `@deepseek-ai/dsh-client-ui-*` 的全部 38 个包 + `dsh-client-locale` + 端侧独有能力），每一行给出落地文件与四形态状态；
- 缺口登记处：**任何非 DONE 的行必须在 §6 登记**，含原因与下一步。门禁强制这条。

**不是**：

- 不是"最终验收通过"的声明。**本矩阵的 DONE 只表示"实现侧完成"**；真机验收是另一根轴（§1.3），今天整体是 `PENDING`；
- 不是设计文档。设计口径在 D3；协议事实在 D2/D2b；本文只登记**对等状态**。

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

> 第 7 项 `Validation` 在本环境的含义**限定为"可静态验证"**（门禁、门禁自检、单测、协议往返）——**不包括真机验收**。真机验收见 §1.3。

### 1.3 两根轴：实现侧 vs 设备验证

计划 §5（DONE 要八项齐备）与 §20（无真机时允许开发完成、不允许宣称设备验收完成）并不矛盾，前提是把它们**分成两根轴**：

| 轴 | 取值 | 今天的状态 |
|---|---|---|
| **实现侧** | 本矩阵的 `Status` / 四形态列 | 见 §5 统计 |
| **设备验证** | `PENDING` / `PASS` | **`PENDING`**（本环境无模拟器、无真机；**工具链已于 2026-09-14 就位**，HAR 模块可真编译，见 §3） |

**硬规则**：任何 `DONE` 行都不得被读作"已在设备上验收通过"；报告里必须同时给出设备验证轴的取值。

### 1.4 门禁强制的五条不变式

| # | 不变式 | 防止的注水 |
|---|---|---|
| A | 行集恰好覆盖官方能力面（38 个 `dsh-client-ui-*` + `client-locale` = 39 个 id 各一行），另有 `hdsh-` 前缀的端侧独有行 | 漏项、重复项、覆盖越界 |
| B | 状态 token 合法（只允许 §1.1 的四个）；**任一形态列不是 `DONE` 时，整体 `Status` 不得是 `DONE`** | 用整体 DONE 盖住某个形态的缺口 |
| C | 任何非 `DONE` 的行必须在 §6 缺口登记里有对应行；§6 也不得登记矩阵里不存在的 id | 悄悄降级、只留结论不留原因、幽灵登记 |
| D | §5 统计表必须与矩阵**实算**逐项相等（含合计） | 口径不明导致数字对不上（本项目真实发生过） |
| E | `DONE` 的行不得留在 §6 缺口登记里 | 陈旧登记：台账同时说"已完成"和"缺什么" |

> 五条都有**注入式负测试**（`--self-test` 的 12 个正/负样例）证明会真的失败。
> 另对**真实矩阵**做过一次端到端注入：把 `workflow-run` 从 `TODO` 谎报成 `DONE` 并顺手改对统计数字——
> 门禁仍以「陈旧登记」点名并退出 1（不变式 E 存在的理由：只靠 D 会被"顺手改统计"掩盖）。

---

## 2. 形态口径（四列的定义）

**这里对计划书的四形态做一处更正**，理由是 HarmonyOS 的实际事实：

> HarmonyOS 的 `deviceType` 只有 `phone` / `tablet` / `2in1`（另有 tv/wearable/car），**没有独立的 `PC`**。
> 计划书里的「PC」与「2-in-1」在系统看来是**同一个 `deviceType = 2in1`**，差别在**窗口模式与输入模态**。

因此四列的定义是「设备族 × 窗口/输入形态」，而不是四个设备类型：

| 列 | 判定 | 典型场景 |
|---|---|---|
| **Phone** | `deviceType=phone`，单栏 | 直板机；折叠屏折叠态 |
| **Tablet** | `deviceType=tablet` | 平板竖屏（双栏）/ 横屏（三栏） |
| **PC** | `deviceType=2in1` + 全屏/最大化窗口、键鼠为主 | 电脑模式、台式二合一接显示器 |
| **2-in-1** | `deviceType=2in1` + 自由窗口/悬停态、触摸为主 | 二合一笔记本、折叠屏悬停 |

**两条落地规则**（与 D3 §2.2 一致，本项目不做例外）：

1. **布局决策只看「窗口宽度 + 输入模态」**，不看 `deviceType`：`layoutModeOf(widthVp)` 是唯一入口。一个 2in1 被拖窄到 500vp，必须与手机同构（单栏）；这是"窗口变化时自动切换布局"的实现方式。
2. **`deviceType` 只用于门控系统能力**（系统文件夹选择器、快捷键提示、拖拽投喂等），且**只允许出现在 Layout/Platform 层**。

---

## 3. 本环境的验证手段口径（可做 / 不可做）

| 手段 | 本环境 | 说明 |
|---|---|---|
| Node 静态门禁（`tools/*.mjs`） | ✅ 可跑 | 已实测：架构门禁、接线回归、上架红线、对等门禁全绿；见 §3.1 |
| **ArkTS 编译（HAR 模块）** | ✅ 可跑 | `devecocli build --modules appstate connection dshcompat hostruntime platform` → **BUILD SUCCESSFUL**（apiVersion 26 SDK，145 任务）。这是**真编译器**，不是解析器 |
| **ArkTS 编译（entry 应用模块）** | ✅ **已可跑（2026-09-14 解锁）** | 两条路：① **只编 UI 层**（快，58s）：`<CLT>/tool/node/bin/node <CLT>/hvigor/bin/hvigorw.js default@CompileArkTS --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon`（需 `DEVECO_CLI_CLT_PATH` + `DEVECO_SDK_HOME=<CLT>/sdk` + `JAVA_HOME`）；② `devecocli build` 全量。**`Index.ets` 与全部 Pane 首次获得真编译验证**——P1~P3 改 UI 不再是盲改 |
| **完整打包（HAP）** | ✅ 可跑，**只差签名** | `devecocli build` → `CompileArkTS` ✅ `PackageHap` ✅ `PackingCheck` ✅，最后 `SignHap` 失败：`build-profile.json5` 的 `signingConfigs` 指向 Windows 路径（`C:\Users\hnzy1\.ohos\config\*.p12`）。产出 **`entry/build/default/outputs/default/entry-default-unsigned.hap`（138MB）**，内含 `libs/{arm64-v8a,x86_64}/libdshhost.so`（原生模块真的编出来了）+ 两个核心 zip + 入口脚本。⇒ **签名是纯环境问题**（需要那台机器的证书），与代码无关 |
| **ArkTS 语法错误的守护边界** | ⚠️ 只有真编译器能抓 | **实测**：codelinter **检不出语法错误**（往 `appstate` 注入 `return a +;` 后它一条都不报，而真编译器立刻 BUILD FAILED）⇒ 任何对 `.ets` 的改动都必须过 `default@CompileArkTS`/`devecocli build`，**不能用 lint 代替** |
| **设计令牌棘轮（`check-design-tokens.mjs`）** | ✅ 可跑且**失败已注入验证** | 计划 §6 点名禁止的裸 `fontSize`/`lineHeight`/`borderRadius`/`borderWidth`/颜色字面量：基线 58 处 / 11 文件，**只许变少**。为什么是棘轮而非一刀切：存量里**图标尺寸的收敛会改变视觉、必须真机验收**，一刀切会立刻几百处红——**永远红的门禁等于没有门禁**。豁免须写明理由（`// token-exempt: …`）；判定器自检 11 个样例 |
| **纯逻辑执行测试（layout fixtures）** | ✅ 可跑 | `tools/check-layout-fixtures.mjs`：把 `appstate/ui` 的三个**纯逻辑** `.ets` 按 `.ts` 编译后**在本机直接执行**（被测的是同一源文件，不是复制品），断言四形态 + 断点边界 + 让步链三分支，共 28 条 |
| **ArkTS 静态检查（codelinter）** | ✅ 可跑且**覆盖面已证明** | 直接调用 CLT 的 `codelinter/bin/codelinter -c code-linter.json5 <模块目录>`：**16 条 warning / 0 error**（7 个文件）。覆盖用**注入测试**证明：往一个「无问题」文件注入已知违规，能被检出（见 §3.2） |
| API 兼容扫描（`devecocli check compat`） | ❌ 平台不支持 | CLI 明文：`Unsupported platform: linux. compat only supports macOS and Windows.`——**与 CLT 是否安装无关**，Linux 上永远不可用 |
| 模型/协议往返（`check-model-roundtrip.mjs`） | ✅ **可跑且通过** | `--no-prompt --wait-ms 180000`（Node 22）：真起 Host → 铸 cookie → 读模型目录 → 建会话 → 开 mux → `session/page` → 收到 `follow` 的 snapshot 帧（含 projections） |
| 起真实 Host 的门禁（`check-origin-fence` / `check-plugin-toggle`） | ✅ **可跑且通过**（需 Node < 22，慢机器还要放宽就绪等待） | ① 这三个门禁用 `process.execPath` 起 Host 并传 `--no-experimental-fetch`，该 flag 在 **Node 22+ 已被移除**（fetch 转正）⇒ Node 24 下 Host 直接启动失败（`--no-experimental-fetch is an invalid negation`）。本机备了 **Node v22.23.2**（与端侧同版本）：`/home/node/node22/bin/node`。② **本机 Host 冷启动实测 62,951 ms**（`BOOT_60_HTTP_BIND …(+62951ms)`；Orange Pi 5B + 工作区在 NFS）⇒ `check-origin-fence` 原来的 60 秒就绪等待刚好不够（`check-plugin-toggle` 用 90 秒，所以它一直能过）。已把它改成可放宽（**默认值不变**）：`HDSH_CHECK_READY_MS=180000`。③ 结论：`check-origin-fence` **PASS**（clean/absent/duplicated → 101；foreign → 403；no-cookie → 401）；`check-plugin-toggle` **PASS**（155 条目 → 写用户行 → `ui-deliverables enabled=false`） |
| 在设备上真跑（装机） | ❌ 只差签名材料 | 运行期产物已齐（`entry/libs/arm64-v8a/` 含 `libnode.so.127`，见 §3.3）；`devecocli build` 打通 `CompileArkTS`→`PackageHap`，仅 `SignHap` 因 `build-profile.json5` 指向 Windows 证书路径而失败 |
| **完整 arm64 HAP（未签名）** | ✅ 已产出 | `entry/build/default/outputs/default/entry-default-unsigned.hap`（138 MB），内含 **`libnode.so.127`(114 MB) + `libkoffi.so`(1,600,496 B) + `libsystem.so`(10,496 B, flock) + `libdshhost.so` + 全套原生库**；三个原生附加件（koffi / flock / dshhost）都在这一台机器上**真的编出来了** |
| 布局/形态真机验收 | ❌ 不可跑 | 无模拟器、无真机 |
| 视觉像素、手势、键盘、触控笔、系统权限、文件选择器 | ❌ 不可跑 | 统一进 `docs/device-validation.md`（P4） |

### 3.1 已实测的基线（本轮）

```
node tools/arch-check.mjs            ✅ 无违规（上游字面量只在 dshcompat，扫描 63 文件）
node tools/check-feature-wiring.mjs  ✅ 15 个功能接线全在（扫描 65 文件）
node tools/check-store-readiness.mjs ✅ PASS
node tools/check-parity.mjs          ✅ 通过（本矩阵：覆盖 / token / 形态 / 登记 / 统计）
node tools/check-parity.mjs --self-test ✅ 12 个正负样例全符合预期（门禁自身可信）
node tools/check-dead-handlers.mjs   69 处（逐条判断用途，不追求归零）
node tools/check-native-closure.mjs  ⚠️ 跳过（无 entry/build 原生库目录）
node tools/check-origin-fence.mjs    ⚠️ 跑不了（缺 dist/core/ 核心树）
node tools/check-plugin-toggle.mjs   ⚠️ 跑不了（同上）
node tools/compat-drift.mjs          ⚠️ 跑不了（缺 .research/protocol/contracts.json）

devecocli build --modules appstate connection dshcompat hostruntime platform   ✅ BUILD SUCCESSFUL（52s）
codelinter -c code-linter.json5 <6 个模块目录>                                  ✅ 16 warn / 0 error
node tools/check-layout-fixtures.mjs                                            ✅ 28 条断言通过（四形态 + 边界 + 让步链）
node tools/check-layout-fixtures.mjs --self-test                                ✅ 注入的失败被如实报出

hvigorw default@CompileArkTS -p module=entry@default …                          ✅ BUILD SUCCESSFUL（0 error / 32 warn）
devecocli build（全量）                                                           ✅ CompileArkTS/PackageHap/PackingCheck 全过
                                                                                 ❌ SignHap（签名证书在 Windows 那台机器上）
                                                                                 ⇒ 产出 entry-default-unsigned.hap = 138 MB

# 三条"守护本身可信吗"的注入测试（门禁通过 ≠ 覆盖到了）
注入 `return a +;` 到 appstate → 真编译器 ✅ BUILD FAILED；codelinter ❌ 一条不报（故 codelinter 不能当解析守卫）
把 MAIN_MIN_VP 280→320 → check-layout-fixtures ✅ 立刻红（正好命中"840vp 详情栏被收窄"这条行为回归）
把 workflow-run 谎报成 DONE（并同步改统计）→ check-parity ✅ 以"陈旧登记"点名并退出 1
```

**门禁"通过"不等于"覆盖到了"**（docs/README 纪律 9）：上面 4 个跑不动的门禁，其覆盖面在本环境**是盲区**，不是通过。

### 3.3 不入库产物清单（新机器上要能编译/装机，需要哪些东西）

> **为什么单列这一节**：2026-09-14 在这儿栽过一次——`entry` 编不过，先被误判成"缺构建产物"，
> 真因却是**一个源码文件从未入库**（见 §3.2 的事故）。源码与产物必须分开讲，否则会朝错的方向找一天。

**① 源码（唯一权威副本在版本库；缺了就是仓库缺陷，不是环境问题）**

| 路径 | 状态 |
|---|---|
| `entry/src/main/ets/runtime/NodeRuntime.ets` | ✅ **已于 2026-09-14 补回版本库**（commit `b906e13`；此前被 `.gitignore` 的裸 `runtime/` 规则吞掉，见 §3.2） |

**② 不入库的产物（字节不进库、方法进库；都要能在本机生成，或从开发机拷贝）**

| 产物 | 路径 | 干什么用 | 产生方式 | 本机状态 |
|---|---|---|---|---|
| Node 头文件 | `entry/src/main/cpp/node-headers/` | CMake 编 `libdshhost`（**只需要它**） | `tools/node-runtime/sync-node-headers.sh`（从 Node v22.23.2 源码树取 `src/*.h` + `deps/v8/include` + `deps/uv/include`） | ✅ 已生成（3.8 MB） |
| koffi 源码 | `third_party/koffi/` | 编 `libkoffi.so`（`subprocess`/`sandbox` 两行插件依赖它） | `node tools/fetch-koffi.mjs` | ✅ 已就位（4.6 MB，随其余产物上传） |
| Host 入口脚本 | `entry/src/main/resources/resfile/resources/app/` | 装机后由原生层跑起 dsh | `node tools/place-host-app.mjs`（源 `hostcore/app/` **在库里**） | ✅ 已就位 |
| 核心包 | `entry/src/main/resources/resfile/*.zip` | 首启解包出端侧核心树 | `node tools/pack-core.mjs --skip-install --place-in-app` | ✅ 已就位（rc.2 / rc.3 各 69 MB） |
| **libnode** | `entry/libs/{arm64-v8a,x86_64}/libnode.so.127` | **运行期**：自建 Node（OHOS）载体；同时是"编不编 koffi"的门 | `tools/node-runtime/build-node-ohos.sh`（本机亦可：容器与真机同为 arm64） | ✅ `arm64-v8a` 已就位（169 MB 原生库组，随其余产物上传）⇒ **koffi 从此会被真正编进 HAP**；**不参与链接**（`CMakeLists.txt` 故意不写进 `DT_NEEDED`，见其注释） |
| 核心树 | `dist/core/work/dsh-core-*` | `pack-core` 的输入；`check-origin-fence` / `check-plugin-toggle` / `check-model-roundtrip` 门禁的前提 | **不需要上传**：`entry/src/main/resources/resfile/dsh-core-*.zip` 本身就是完整树（29006 个文件），`unzip` 到 `dist/core/work/` 即物化 |
| 协议契约 | `.research/protocol/contracts.json` | `compat-drift` 门禁的输入 | `node tools/protocol-contract.mjs` + 上游 checkout | ❌ 缺 ⇒ 漂移门禁仍是盲区（**唯一仍跑不动的门禁**） |
| 签名材料 | `.p12` / `.cer` / `.p7b` | `SignHap` 出可安装的 HAP | DevEco 自动签名（那个 Windows 机器上的 `C:\Users\hnzy1\.ohos\config\`） | ❌ 缺（路径写在 `build-profile.json5`，Linux 上无效） |

**工作区在 NFS 上——批量文件操作必须换到本地盘（本轮最大的效率教训）**

| 事实 | 读数 |
|---|---|
| 工作区文件系统 | **NFS**：宿主是 Orange Pi 5B，`/mnt/Develop` 来自 NAS `192.168.3.27:/volume1/Develop`；容器（内层 Docker）以 `/workspace` 挂载它 |
| 逐文件操作代价 | 把核心树（29k 个小文件）解到工作区：**跑了 25 分钟才 6.5k 个文件**（≈4 个/秒，照这速度要数小时） |
| 换到本地盘 | 容器本地 overlay（`/home/node`）实测 **2000 个小文件 0.12 秒**；同一份核心树解到 `/home/node/hdsh-cores/` 只用 **4 秒** |
| 做法 | 大批小文件的东西解到**容器本地**，再用软链挂进项目：`ln -sfn /home/node/hdsh-cores/dsh-core-0.1.5-rc.2 dist/core/work/dsh-core-0.1.5-rc.2`（`dist/` 已 gitignore，不污染仓库；`existsSync` 会跟随软链，门禁无需改动） |

**从别处拷贝产物时的两个实测坑（2026-09-14 各踩一次）**

| 坑 | 现象 | 核对办法 |
|---|---|---|
| **"上传了目录" ≠ "文件到了"** | `dist/core/work/dsh-core-*` 看起来存在，但 `find … -type f | wc -l` = **0**：只有目录骨架，没有文件 ⇒ Host 报 `找不到 profile-boot 入口（核心树可能不完整）` | 收到目录后用 **`find <dir> -type f | wc -l`** 核对文件数，不只看 `ls` |
| **文件带 +x 位** | 拷进来的 `.ets` / `.cpp` / `.d.ts` 变成 `100755`，与库里的 `100644` 产生**纯模式 diff**（内容逐字节相同） | `git diff --summary` 看 `mode change`；归一化用 `git update-index --chmod=-x <path>`（必要时重写文件以取得属主再 `chmod 644`） |

**结论**：**编译验证不需要任何外部产物**（HAR 模块 + entry 的 ArkTS + 原生 + 打包在这一台机器上全通）；
**装机运行**才需要 `libnode`（+ 签名）。这一点值得写下来，因为"编译过了"与"能装机"经常被混为一谈。

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

**一次被编译器揭穿的"仓库不完整"事故（2026-09-14，已修）**

| 环节 | 事实 |
|---|---|
| 症状 | 新克隆的仓库编不过 `entry`：`COMPILE RESULT:FAIL {ERROR:8 WARN:33}` |
| 误判风险 | 第一反应是"缺构建产物"（原生头文件/预编译库）——**方向错了**，会白找很久 |
| 真因 | `entry/src/main/ets/runtime/NodeRuntime.ets` **从未进过版本库**（`git log --diff-filter=A -- '*NodeRuntime*'` 为空），而 3 个已跟踪文件 import 它：`EntryAbility.ets:40`、`Index.ets:134`、`Poc1.ets:21` |
| 根因 | `.gitignore` 第 35 行是裸的 `runtime/`（本意是根目录 172 MB 的 Electron 载荷）。**gitignore 的裸目录名在任意层级都匹配** ⇒ 连 `entry/src/main/ets/runtime/`、`hostruntime/src/main/ets/runtime/` 这类**模块源码目录**也被忽略。文件在开发机上"看得见"，在任何新克隆里"不存在"，**且不报任何错** |
| 8 个错误的构成 | 3× `Cannot find module '../runtime/NodeRuntime'` + 1× Rollup `Could not resolve` + 4× `arkts-no-any-unknown`（无法解析导入后的连带）⇒ **全部可归因到这一个文件**，没有一个是真的代码缺陷 |
| 修法 | ① `.gitignore` 规则锚定为 `/runtime/`（commit `ff6cbc9`）；② 把源码补回版本库（commit `b906e13`）。修后 `default@CompileArkTS` → **BUILD SUCCESSFUL（0 error / 32 warn）** |
| 教训 | ① `.gitignore` 的目录规则要**锚定**，或在路径里带上足够的上层目录；② **"本地能跑" ≠ "仓库完整"**——被忽略的文件只会在别人机器上消失，本地永远无感；③ 遇到"新克隆编不过"时，先问"**源码**齐不齐"，再问"**产物**齐不齐" |

> **工具链的环境坑（实测，必须记住）**：在 Linux 上跑 `devecocli build` 会让 ohpm 重写 **5 个受版本控制的 `oh-package-lock.json5`**（191 行全变），
> 原因是构建机把行尾写成 LF 而仓库在 Windows（`core.autocrlf=true`）下是 CRLF——`git diff --ignore-cr-at-eol` 为空即可确认是纯行尾差异。
> **每次构建后必须 `git checkout --` 回退这些文件**，否则提交里会混进 191 行噪声（本项目对"噪声 diff"有明确纪律）。

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
| `message-feedback` 消息反馈 | 每消息反馈控件（**类别 → 可选备注 → 提交 → 存储态 → 撤回**） | `SessionHub.putFeedback`（含 `category`）/ `clearFeedback`（撤回，`ifVersion` 做 CAS）/ `refreshFeedback` / `feedbackOf`；类别取值域与请求类型**按上游源码核对**（`dsh-message-feedback/lib/types/types.d.ts`） | 消息操作条：复制 + 有帮助/没帮助 + **类别/备注面板 + 提交 + 撤回评价**（§10 的闭环） | `messageFeedback/put`（`ifVersion: string\|null`）、`messageFeedback/delete`（`ifVersion: string`，**幂等**） | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |

### 4.3 输入区与控制器

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `input-trigger` 输入触发管线 | `/` 与 `@` 检测、候选菜单、选路到已注册源 | `SessionHub.refreshCommands` / `refreshReferences` | `Composer` 的 `@`/`/` 弹层 | `commands/*`、`fileReferences/*` | DONE | DONE | DONE | DONE | DONE |
| `commands` 客户端命令面 | 全局目录缓存、`/` 源、**三种命令 UI 类型**、popupSelect 注册表 | `SessionHub.refreshCommands` / `executeCommand` | `Index.ets` 命令面板 | `commands/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `reference` 引用源 | 统一 Web `@file` 与 `@session` 引用源 | `SessionHub.refreshReferences` + `Wire.fileReferencesPayload` | `Composer` 引用弹层 | `fileReferences/list` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `attachment` 附件呈现 | 动态附件呈现：输入区、消息图、轨迹图三类槽位 | `SessionHub.attachLocalFile` / `attachWorkspaceFile` / `removeAttachment` / `clearAttachments` | `Composer` 附件条 | `fileUploads/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `model-selection` 模型选择 | 共享模型目录 + 会话投影 + `session.selectModel` | `SessionHub.selectSessionModel` / `setDefaultModel` / `refreshProviderCatalog` | `Composer` 模型与强度 chip + 设置页模型页 | `llm/*`、`settings/*` | DONE | DONE | DONE | DONE | DONE |
| `plan` 计划模式控件 | 输入区内的 plan 控件（`conversation.input.plan` 座位）+ `/plan` 通道 | `HubSnapshot.planActive` / `planPending`（判据按官方 chip 语义：`pending ? !active : active`） | `Index.ets` 面板内的计划开关（**不在 Composer 内**） | 计划投影 + 命令通道 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `permission-presets` 权限面 | General 里的新会话默认 + 会话内 `/permission` 弹层 | **只读**：`SessionHub.permissionsCurrent` / `permissionsOptions`（源码注明"切换需要 dsh-permission-presets"） | `Index.ets` 如实显示当前模式 | 读 `permissions` 投影；**无切换端点调用点** | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `approval` 审批 | 审批**接管输入区**，作用于有作用域的 Remote Event 瀑布流 | `SessionHub.handleWaterfall` → `PendingItem`、`Present.sortPending`（危险 > 审批 > 提问） | `view/PendingPane.ets` 审批卡（三选 / 危险动作权重反转 / 原始载荷可展开） | `approval/*`（到达与答复链路已实测） | DONE | DONE | DONE | DONE | PARTIAL |
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
| `settings-plugin-inventory` 插件清单页签 | 只读 Cordis Loader 清单页签 | `model/Core.ets`（`classifyPlugin`）+ `tools/scan-core-plugins.mjs` | `SettingsPane` 插件清单 | 核心树扫描 | DONE | DONE | DONE | DONE | DONE |

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
| `hdsh-clipboard` 剪贴板 | 无 | `platform/system/Clipboard.ets`：**写**（`copyText` / `clearClipboard`）已接；**读**（`readText`）已实现但**未接线**，且需 `ohos.permission.READ_PASTEBOARD`（未声明） | 消息复制（多处 `copyText`） | 无 | DONE | DONE | DONE | DONE | PARTIAL |
| `hdsh-window` 窗口记忆 | 无 | `platform/window/WindowMemory.ets` | 由 `EntryAbility` 驱动 | 无 | DONE | DONE | DONE | DONE | DONE |
| `hdsh-shortcuts` 快捷键 | 无（Web 用浏览器快捷键） | `ui/Shortcuts.ets`（13 个规格，含不可绑定项标记） | `view/ShortcutKeys.ets` + `Index` 分派 | 无 | BOUNDARY | DONE | DONE | DONE | PARTIAL |
| `hdsh-a11y` 无障碍 | 无（Web 走 ARIA） | `accessibilityText` + `Sz.TOUCH_MIN` | 各 Pane | 无 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |

---

## 5. 统计（本轮）

| 状态 | 行数 |
|---|---|
| `DONE` | 14 |
| `PARTIAL` | 31 |
| `BOUNDARY` | 3 |
| `TODO` | 2 |
| **合计** | **50** |

> 统计口径：**矩阵 §4 各行 `Status` 列的计数**（50 行 = 39 个官方能力面 id + 11 个 `hdsh-` 端侧独有行）。
> **纪律（docs/README 第 8 条）：统计前先定口径，并把口径写出来。** 本节数字由 `node tools/check-parity.mjs` 实算核对——
> 首版手写的统计（18/22/4/2）与实算不符，正是这条纪律要防的错误；门禁现在会直接报出差额。

---

## 6. 缺口登记（任何非 DONE 的行必须在此）

格式：`id` → 缺什么 → 下一步。门禁强制"矩阵里非 DONE 的 id 必须出现在本表"。

| id | 缺什么（对等差距） | 下一步（归属） |
|---|---|---|
| `layout` | ① 无拖拽调宽手柄（官方 AppFrame 有 drag handles）；`decideLayoutWithDetail` 已把"用户想要的宽度"这条路径做好并有 fixture，但**没有 UI 去产生这个宽度** ② 详情栏宽度记忆未落 ⑤ **平板（DOUBLE）目前与手机一样用半模态 Sheet**；计划 §12 说的"平板侧边浅层面板"尚未做（三栏已经是真右栏） ③ **待决（需真机）**：D3 §2 只按宽度判定 ⇒ **手机横屏（800vp 宽）会落成双栏**；要不要加高度/方向子句，看真机效果后定 ④ 输入模态仍未接入决策（传 `false` 并在源码里注明）：`pointerRich` 无消费点，P3 再统一 | P2：拖拽调宽 + 宽度记忆；P3：把 `readDeviceFacts().keyboardLikely` 接进 `LayoutInput` |
| `primitives` | ① 原语已落 `NativeChip` / `NativeSectionTitle` / `NativeCard` / `NativeButton` / `NativeActionBar`（+Sheet 参数助手）；**弹层/Dialog/导航**仍未原语化 ② **浮层改原生只做了 2/6**：详情、枚举选择已改 `bindSheet`；`folderSheet` / `credentialSheet` / `textSettingSheet` / `structSettingSheet` 四个仍是"整屏 Column + 自制遮罩"的老形态（遮罩已换成系统语义色 `HarmonyColor.MASK`，但原生拖拽关闭/键盘避让仍缺）③ `deliverableItem` 的保存/分享是**禁用+写明原因**（平台无文件保存能力） ② `WEB_TOKEN_MAP` 目前是**文档化数据 + fixture 可校验**，但还没有"视图必须经映射取色"的强制门禁（现有棘轮只管裸 fontSize/圆角/描边/颜色字面量） | P1.5 已做：HarmonyTheme 语义层 + 前两个原语 + 两处接入（消息操作条、Composer 工具行）。下一步按 P1.5 清单推进（Surface/Button/Card/Popup/Sheet/Dialog/ActionBar/Navigation），每个原语都**当时就接一个真实消费者**，不落没人用的空构件 |
| `slots` / `renderer` | 官方是 React + 槽位插件化渲染；ArkUI 无槽位系统，第三方不能贡献 UI | 架构边界：**不追平**，能力由"构建期装配 + 设置页开关"替代；本条登记以免被当作缺陷反复讨论 |
| `session` | 无"会话作用域槽位"；控制器能力（`SessionHub`）已具备 | 不追平（同上）；控制器本身已 DONE |
| `conversation` | ① 回合渲染已落地（对话视图按回合 + 过程分组折叠/展开），但**轨迹视图仍是条目级台账**——§8 的"统一模型"目前只在对话视图生效 ② PC/2-in-1 列随 `layout` 的缺口 | P1 已做：回合模型（15 条断言）+ 对话视图按回合渲染 + 行数单位收敛 + **sticky-follow 独立成模型**（`model/Follow`，9 条断言；顺带修掉两个真实缺陷——切会话与发消息都不恢复跟随）。下一步：轨迹视图也按回合组织（或明确"它就是全量台账"并在文档里定死）。**更正一条此前的错误判据**：上一轮把"回答本身可折叠"写成缺口是错的——官方折叠的是**过程**，回答是回合的目的、收起它会把这一轮的意义藏起来；故**不做**，此项从缺口移除 | | P1：Conversation 重构（先做模型，再改视图） |
| `trajectory` | 无交互式时间总览（timing overview）；无 inspector | P2：`TrajectoryPresenter` |
| `tool` | 无按工具细分的呈现（terminal / read / write / diff / search / web / image 的差异化卡片） | P2：`ToolPresenter` |
| `subagent` | 无续跑路由 UI；子代理不作为 `@` 引用源 | P2 |
| `deliverables` | 终答正文内的可点文件引用未接（只有独立交付物条目 + 工作区标记） | P2 |
| `jobs` | 官方在会话头有后台任务列表；HDSH 只在轨迹里显示 `JOB` 行，且不是 live 注册表视图 | P2 |
| `workflow-run` | 完全未实现；**协议侧也无 workflow 端点**（`dshcompat/Endpoints.ets` 内无匹配） | 先确认上游是否暴露 workflow 端点；无端点则本行长期 `TODO`（**不造无协议支持的假后端**） |
| `cordis` | 无 `cordis_define` 工具行与 run/stop 开关；端点已登记但无调用点 | P2/P3：需要 keyed tool row 能力（与 `tool` 同一批） |
| `skill` | 无对话内技能引用；无专用 skill 工具行 | P2 |
| `message-feedback` | ① **Retry / Edit / More 未接**（§10 列出的其余操作）：它们需要「重跑某一轮 / 改完再发」的协议面，本仓**没有对应端点** ⇒ 不放点了没反应的按钮（假入口），缺口显式留在这里 ② 面板与 chip 的**观感、触摸目标、四形态**均待真机验收 | P1 已做：类别（契约 7 个取值）→ 可选备注 → 提交 → 存储态回显 → **撤回**（`messageFeedback/delete` + CAS）；P2：Retry/Edit 需先确认协议面是否存在 |
| `commands` | 三种命令 UI 类型未细分；`popupSelect` 注册表语义未对齐 | P2 |
| `reference` | `@session` 引用源未确认（`@file` 已通） | P2：与子代理目录同一批 |
| `attachment` | 消息内图片、轨迹图片两类槽位未接（输入区附件已通） | P2 |
| `plan` | 控件不在 Composer 内（官方是 `conversation.input.plan` 座位）；`/plan` 命令通道未对齐 | P1：Composer 重组织（计划 §9） |
| `permission-presets` | **只能显示不能切换**；无 General 里的新会话默认项 | P1：需要 `dsh-permission-presets` 对应端点的调用点；先确认协议（D2b）再接线 |
| `approval` | 交互位置对等差距：官方是**输入区接管**（在对话上下文里答复），HDSH 是独立的「待决」聚合页；`Present.sortPending` 的排序已是官方语义 | P1：`PanelController` + Composer 接管式界面（与提问卡同一批） |
| `user-questions` | 同上：官方是 `ask_user_question` 的输入区接管 + 计划复核呈现，HDSH 落在待决页 | P1：同上（与 `approval` 同一批） |
| `agent-preset` | 缺**组合编辑器**（composition editor）与「后续会话默认」的显式面；复制/删除/查看已有 | P2 |
| `sidebar` | 无会话搜索；无"分组"显式交互（现为工作区为组） | P2 |
| `workspace` / `directory-picker-browse` | 真实文件树受 `workspaceFileScopeId` 阻塞（D4 已登记的未决来源） | 先确认该 id 的来源（协议事实）再接线 |
| `directory-picker-native` | 手机不支持系统文件夹选择器（`DocumentSelectMode` 仅 2in1） | 能力边界：手机走 `pickDocument` 回退路径；**不删功能、不假装可用** |
| `settings-general` | 版本化欢迎通知未确认 | P2 |
| `theme` | ⓪ **沉浸光感（API 26 空间化材质）暂不可用**：决策为 `targetSdkVersion` 保持 `6.1.1(24)`（2026-09-14），代价是材质只能用系统阴影表达；升级路径与「升级后只用在常驻外壳、不要全页滥用」的功耗提醒写在 `HarmonyMaterial` 注释里。① 无 `--dsw-*` 等价的**可声明令牌层**——现在是「token 常量 + 棘轮门禁」，不是可被主题切换的声明式变量；无 visual swatch ② **存量裸值 58 处**已被棘轮冻结，其中**图标字号 46 处**（12/14/16/18/20/22/28/32/36/40 共十档）、**圆角 5/9**、**颜色字面量 14 处**（`Color.Gray/Red/Green` 集中在 `Poc1.ets`，另有 `badge` 的 `Color.White`）需要一次设计收敛——**收敛会改变视觉，必须真机验收**，故不塞进机械替换 | P1 已做：token 补齐（`Border.HAIRLINE` / `Radius.XS` / `Fs.CAPTION_XS`）+ **机械替换 36 处**（数值不变 ⇒ 视觉无变化）+ 棘轮门禁。P2：图标档位与圆角的视觉收敛（真机）+ 声明式令牌层 |
| `client-locale` | 语言目录可扩展性未确认（官方支持扩展目录） | P2 |
| `hdsh-diag` | 诊断页 `home=` 仍显示桩值 `D:/work`（D4 待收口第 2 项） | 核实 `runDiagnostics()` 与 `getHostHome()` 空值路径 |
| `hdsh-notify` | 逐条通知的渠道路由被 SDK 标称枚举不一致阻塞（D4「仍待真机」第 5 项） | 真机阶段验证 |
| `hdsh-multiwindow` | "1 条 mux + 1 条 `$events`"的抓包核对待设备 | 真机阶段验证 |
| `hdsh-shortcuts` | 表与分类完成；**绑定与实机响应待验收**；Phone 不适用（无实体键盘） | 真机阶段验证 |
| `hdsh-a11y` | 朗读文本与触摸目标已实现，**待真机朗读验收** | 真机阶段验证 |
| `hdsh-clipboard` | **读**剪贴板不可用：`readText()` 需要 `ohos.permission.READ_PASTEBOARD`（API 12 起），应用未声明该权限；且 `readText` 全仓只有「定义 + 桶导出」2 处 ⇒ 按 E257 判据属**登记了没接**（粘贴入口本就没做）。写（复制）正常 | 决策点：① 若要支持「粘贴到输入区」，需评估声明 READ_PASTEBOARD 对上架/权限最小化策略的影响；② 若不支持，则把 `readText` 从桶导出里摘掉或明确标注为未接。**不允许挂着不动** |

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

| 事实 | 来源 | 版本 |
|---|---|---|
| 官方能力面清单与各包行为自述 | 本机安装的官方客户端包 `package.json`（`name` / `description` / `dsh.client`） | **0.1.2-alpha.1** |
| 各 `Web 行为` 列文案 | 由上述 `description` 意译（不新增未经查证的断言） | 同上 |
| Harmony 落点 | 本仓库源码（行级可核对，见各单元格文件路径） | HEAD `af00b0b` |

> ⚠️ **同一性提示**：本项目的协议基线是 **0.1.5-rc.1**（D2 §8.7），而本环境能拿到的官方客户端包是 **0.1.2-alpha.1**。
> 因此 §7.1 的能力面清单**需要用 0.1.5-rc.1 复核一遍**（可能新增/改名若干 `dsh-client-ui-*` 包）。
> 复核方法：在拿到 0.1.5-rc.1 的机器上跑 §7.1 的命令，与门禁内嵌清单比对——`node tools/check-parity.mjs` 会直接报出差集。

### 7.3 门禁

```bash
node tools/check-parity.mjs              # 校验本矩阵（覆盖 / token / 不变式 / 缺口登记）
node tools/check-parity.mjs --self-test  # 注入式自检：证明它会失败（未被负测试验证的门禁等于没有门禁）
node tools/check-parity.mjs --list       # 打印解析出的行与状态

node tools/check-layout-fixtures.mjs              # 四形态 + 断点边界 + 让步链（纯逻辑，无需设备）
node tools/check-layout-fixtures.mjs --self-test  # 证明断言器会失败
                                                  # 退出码 3 = 环境受阻（找不到 tsc），**不是通过**

node tools/check-arkts-entry.mjs              # 编 entry（UI 层）的 ArkTS：P1~P3 改 Index.ets/Pane 的守护
node tools/check-arkts-entry.mjs --clean      # 强制真正重新编译（增量时 CompileArkTS 会被 UP-TO-DATE 跳过）
node tools/check-arkts-entry.mjs --self-test  # 判定器自检（8 个样例，含"hvigor 失败却退出码 0"的真实形态）
```

---

## 附 A：`Index.ets` 依赖关系与拆分基线（P1 输入）

**现状**：`entry/src/main/ets/pages/Index.ets` = **4613 行**、**22 个 `@Builder`**、约 60 个方法，承担五类职责：

| 职责 | 现状落点（Index.ets 内） | 目标归属（计划 §3/§7） |
|---|---|---|
| 布局决策 | `applyWidth`、`layoutModeOf` 调用点、`Sz.NAV_RAIL` 判断 | `LayoutController` |
| 页面装配 | `mainContent`、`tabContent`、`buildSingle/Double/Triple` | `AppShell` + `MainContent` |
| 一级导航 | `bottomTabs`、`navRail`、`navPanel`、`navPanelAction` | `NavigationController` |
| 会话/输入区 | `header`、`hubBanner`、`workspaceHub`、`workspaceGroup`、`coreTabContent` | `Conversation/Composer/Workspace` 控制器 |
| 设置表单与审批 | `textSettingSheet`、`structSettingSheet`、`credentialSheet`、`folderSheet`、`choiceSheet` | `SettingsController` / `PanelController` |

**已经分出去的部分**（不用重做，避免重复实现已有功能）：

| 层 | 文件 | 被谁用 |
|---|---|---|
| 设计令牌 | `appstate/ui/Tokens.ets` | 各 Pane（`Sp`/`Radius`/`Fs`/`Sz`/`SemanticColor`） |
| 断点与档位 | `appstate/ui/Breakpoints.ets` | `Index`（3 个调用文件） |
| 快捷键表 | `appstate/ui/Shortcuts.ets` | `Index` + `view/ShortcutKeys.ets` |
| 设备事实 | `platform/system/DeviceFacts.ets` | 仅 `EntryAbility`（窗口账本）与 `RuntimeSingleton` |
| 系统能力 | `platform/system/*`（文件选择/剪贴板/通知/分享/窗口记忆） | 各 Pane 经 `platform` 桶导入 |

**本轮发现的三处硬事实**（可直接作为 P1 的起点）：

1. **`navPresentation` / `NavPresentation` 只有 2 处引用**：定义（`Breakpoints.ets`）+ 桶导出（`appstate/Index.ets`），**没有任何界面调用点**。
   按项目既定判据（E257：**1 处该删，2 处该登记**），它属于"登记了没接"：**导航呈现决策没有真的走布局层**，`Index.ets` 里自己按宽度与 `Sz.NAV_RAIL` 判。
   → P1 第一刀：让 `LayoutController` 消费 `navPresentation`，否则删掉这个会撒谎的 API（二选一，不允许挂着不动）。

2. **布局决策确实只由窗口宽度驱动**：全仓 `FormFactor` / `readDeviceFacts` 只出现在 `EntryAbility`（窗口账本登记）与 `RuntimeSingleton`，**没有任何 UI 用它做布局分支**。D3 §2.2 的硬规则在实现上是成立的（不需要先修）。

3. **系统能力调用直接落在 `Index.ets` 上**（P3 落点证据）：
   `Index.ets:839 applyThemeMode`、`:1211/:2818/:3094 copyText`、`:1390 pickDocument`、`:1794 pickFolder`。
   官方对等物是 `platform/*`，而计划 §15 要求"业务代码不得直接散落平台判断"。
   → P1 建 `PlatformAdapter` 边界时，先把这 6 个调用点收进适配层；**`deviceType` 判断本身目前没有散落**（这点是好消息）。

**拆分顺序（计划 §7，每次拆完保持门禁全绿）**：

```
1) layout decision    → LayoutController        ✅ 已做（Index 已消费，行为等价，commit fad954a）
2) navigation         → NavigationController    ✅ 已做：返回键 7 级优先级阶梯 + 页签归一化/清栈/静态事实重读
                                                  全部搬出，54 条 fixture 断言覆盖（含"浮层内部先后"）
3) detail/right panel → PanelController         待做
4) command palette    → PanelController         待做
5) composer           → ComposerController      待做
6) conversation       → ConversationController  待做
```

每一步的验收：`arch-check` / `check-feature-wiring` / `check-store-readiness` / `check-parity` /
`check-arkts-entry` / `check-layout-fixtures` / `check-design-tokens` 全绿 + 本矩阵对应行状态**只升不降**（门禁强制）。

> **第 2 步顺带发现的一个坑（值得记住）**：`NavTab.SESSIONS` 是 `'workspaces'` 的**别名**（E108 会话并入工作区），
> 所以"在会话页签"与"在工作区页签"是同一个状态、**不存在 `'sessions'` 这个取值**。
> fixture 第一版把它当独立值用，立刻红了两条——这正是把导航搬成纯函数想要的效果：
> 这类语义坑以前只存在于 `Index.ets` 的内联判断里，没人能单独测它。

---

## 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1.3 | 2026-09-14 | **`entry`（UI 层）获得真编译验证**：定位并修复「仓库缺一个从未入库的源码文件」事故（`.gitignore` 裸 `runtime/` 规则吞掉模块源码目录，commit `ff6cbc9` + `b906e13`）⇒ `default@CompileArkTS` BUILD SUCCESSFUL（0 error / 32 warn），全量 `devecocli build` 打通到 `PackageHap`（产出 138 MB unsigned HAP，含两 ABI 的 `libdshhost.so`），只剩签名（证书在 Windows 那台机器上）。新增 **§3.3 不入库产物清单**（源码 vs 产物分开讲，避免把"缺源码"误判成"缺产物"）；记录两处新能力：UI 层单模块快编命令、`PackageHap` 可跑 |
| v1.2 | 2026-09-14 | **P1 第一刀：`LayoutController` 落地**（`appstate/ui/LayoutController.ets`，形态/几何决策与让步链的唯一落点，被真编译器验证）+ **`tools/check-layout-fixtures.mjs`**（纯逻辑按 TS 编译后本机执行，四形态/边界/让步链 28 条断言，含自检与真实注入验证）。据此更新 `layout` 行与缺口；**新增硬事实**：`entry` 不只是没有编译器——**codelinter 检不出语法错误**（注入实测），故 `entry/src/main/ets/**` 目前**零自动验证**，已写进 §3 |
| v1.1 | 2026-09-14 | **工具链就位后校准 §3**：HAR 模块可真编译（BUILD SUCCESSFUL）、codelinter 全量可跑且**覆盖面经注入测试证明**、`check compat` 确认 Linux 永不支持、`entry` 因原生构建无编译验证。新增 §3.2 编译器首批发现——其中 `READ_PASTEBOARD` 缺失是**真实缺口**，据此把 `hdsh-clipboard` 由 `DONE` 降为 `PARTIAL`（编译器纠正了本矩阵）。补记 Linux 构建会重写 5 个 lock 文件行尾的环境坑 |
| v1.0 | 2026-09-14 | 首版：建立四形态口径（更正 PC 与 2-in-1 同为 `deviceType=2in1`）、状态口径与两轴规则、46 行对等矩阵、缺口登记、来源与版本标注、门禁 `check-parity.mjs`、附 A `Index.ets` 拆分基线 |
