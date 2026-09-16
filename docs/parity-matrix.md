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
node tools/arch-check.mjs            ✅ 无违规（上游字面量只在 dshcompat，扫描 75 文件）
node tools/check-feature-wiring.mjs  ✅ 17 个功能接线全在（扫描 111 文件）
node tools/check-builder-recursion.mjs ✅ 99 个 @Builder 无自递归（E343）
node tools/check-dead-code.mjs        ✅ 81 文件 / 1855 处声明 / 0 死代码（E350）
node tools/check-store-readiness.mjs ✅ PASS
node tools/check-parity.mjs          ✅ 通过（本矩阵：覆盖 / token / 形态 / 登记 / 统计）
node tools/check-parity.mjs --self-test ✅ 12 个正负样例全符合预期（门禁自身可信）
node tools/check-dead-handlers.mjs   78 处（逐条判断用途，**不追求归零**；这 78 处绝大多数是 ArkTS 声明可空回调 prop 的惯用写法 `onX: (…) => void = () => {}`——结构体成员必须有初值，所以空默认值是**声明**，不是"死按钮"；真正要判断的是调用方有没有接线）
node tools/check-native-closure.mjs  ⚠️ 跳过（无 entry/build 原生库目录）
node tools/check-origin-fence.mjs    ⚠️ 跑不了（缺 dist/core/ 核心树）
node tools/check-plugin-toggle.mjs   ⚠️ 跑不了（同上）
node tools/compat-drift.mjs          ⚠️ 跑不了（缺 .research/protocol/contracts.json）

devecocli build --modules appstate connection dshcompat hostruntime platform   ✅ BUILD SUCCESSFUL（52s）
codelinter -c code-linter.json5 <6 个模块目录>                                  ✅ 16 warn / 0 error
node tools/check-layout-fixtures.mjs                                            ✅ 533 条断言通过（四形态 + 边界 + 让步链 + 模型/呈现/设置域）
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
| **真机待验收** | `register()` 的钩子跑在 Node 的**独立线程**里；端侧嵌入式运行时是否允许起线程，本环境无法证明。故 `installUndiciNameHook()` 失败时**只降级、不阻断启动** —— 正因如此**必须靠日志主动确认**，不能因为"Host 起来了"就以为生效了。真机两项已登记为 `docs/device-validation.md` 的 **D1（钩子在线程里能否注册）** 与 **D2（真机抓一次网页）** |

**一个把两次验证带偏的环境陷阱（记录下来，避免重犯）：ESM `import 'node:http'` 在 `--jitless` 下会炸**

排查期间我写的两个 harness 都在第一行 `import http from 'node:http'`，于是**测试自己**把进程搞崩，真正的结果被完全遮住，还一度让我得出错误结论。实测：

| 写法（均在 `--jitless --no-experimental-fetch` 下） | 结果 |
|---|---|
| `require('node:http')`（CJS） | ✅ 干净 |
| `import http from 'node:http'`（ESM，静态或动态） | 💥 进程在收尾时抛 internal undici 的 `WebAssembly is not defined`，**退出码 1** |
| `import('node:https')` / `import('node:net')` | ✅ 干净 |
| 同上但不带 `--jitless` | ✅ 干净 |

这是 Node 自身对 `node:http` 的 ESM facade 行为，与我们的代码无关；`dsh-host-webserver` 也是 `type: module` 且 `import { createServer } from "node:http"`，而 Host 是长活进程、被 kill 而非自然退出，故实践上不受影响。**对我们的要求很简单：端侧/jitless 相关的 harness 一律用 CJS `require` 取 `node:http`**（本仓 `main.js` 本来就是这样）。

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

项目所有者于 2026-09-14 重定义本阶段：**停止「缺一个功能 → 加一个组件」，改为先把页面框架搭正确。**
工作令与分步计划见 `docs/ia-parity-plan.md`（P0 AppFrame → P1 Sidebar → P2 Main → P3 Rightbar → P4 Settings 域 → P5 视觉精修）。

判断依据是「**功能不少、页面还是不像官方**」——根因是信息架构没落地，而不是缺按钮：

| 层级 | 现状 |
|---|---|
| Host / 协议 / 会话状态 / 多形态几何 / 输入模态事实 | 🟢 |
| Prompt 泄漏（P0-1） | 🟢 已关闭（结构字段 + 单一判据 + 搜索作用域，388 条 fixture 全过） |
| Conversation 数据模型（回合 / 跟随 / 可见性） | 🟢 |
| **AppFrame / Sidebar 信息架构 / PanelRegistry / Settings 域** | 🟡 **AppFrame 已完成**（`ShellTracks` + `AppShell` 三形态轨道 + `SidebarShell` / `MainHeaderShell` / `RightbarShell` / `TrackResizer` 各有其主 + 浮层门户提到页面根；`Index` 5040 → 4290 行）；🔴 **剩余**：Sidebar 重建（P1）、Conversation（P2）、Settings 域（P4） |
| Markdown | 🟢 **P2-1 已落地**：`appstate/model/Markdown`（纯模型，31 条断言）+ `entry/view/MarkdownRenderer.ets`（`Text > Span` 行内富文本）；正文/思考/过程三处已从 `Text(item.body)` **原文照显**换成渲染。**刻意不做**：HTML、表格、嵌套列表（前者是安全问题，后两者 ArkUI 的 `Text/Span` 表达不了）——缺的部分原文照显，不假装支持 |
| 视觉精修 | 🔴 排最后（框架错则间距 / 颜色 / 动效全白做） |

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
| `deliverables` | ① **右栏「交付物」面板已落地（P3-4）**：`DeliverableCard` 与过程流共用同一份卡；筛选是纯模型（`itemsOfKind` / `deliverablesOf`：保序 + 同 id 去重）；空态如实说明「本次会话还没有交付物」② 剩余：终答正文内的可点文件引用未接（只有独立交付物条目 + 工作区标记）；「保存 / 分享」因平台没有文件保存能力而**可见但禁用**（原因写在无障碍文案里）| P3-4 已做面板；正文内文件引用待 P2 收尾 |
| `jobs` | ① **会话头的后台任务条已落地（P2-2）**：模型 `appstate/model/Jobs`（40 条断言：live 判定 / 状态点语义 / 五种文案 / 时长三档与小时封顶 / 排序 / 计数 / 定时器按需）此前**一个视图消费者都没有**——中枢一直在维护 `jobs` 字段，界面只在轨迹里显示 `JOB` 行。现在：中枢投影 → `Index` → `MainShell` → 会话头上的任务条（有任务才出现；`Flex(wrap)` 任务块：状态点语义色 + 名称 + 状态文案 + 耗时，live 任务每秒走字，`jobTickerNeeded` 决定要不要开定时器；无障碍整段取自 `jobListA11y`）② 已用 `tools/check-feature-wiring.mjs` 把这条接线**钉成回归**（模型判定 + 中枢投影 + 会话头传参三段）③ **呈现已按官方改为"触发器 + 展开清单"（P7-3）**：读 `dsh-client-ui-jobs` 源码 —— 官方在会话头只放一个**按钮**（`StateDot`（**仅 live 时**）+ `{count} 个后台任务运行中`/`{count} 个后台任务` + 折叠指示，`aria-label: 后台任务`），点开才是清单（状态点 + `job.kind` + `job.label` + `job.detail ?? 状态文案` + 耗时）；我们此前是**常开**的换行任务条，还带一句"展开收起全部任务在轨迹"的指引（官方没有这个指引，且任务一多就把会话头撑高）。现在同结构、同文案。**登记一处刻意保留的差异**：轨迹视图里仍有 `JOB` 行（官方轨迹**没有** job 这个 kind —— 实测其 bundle 里 `job` 出现 0 次），那是我们的**台账**用法（何时起了哪个任务）；去掉它要动轨迹的单元格索引映射（搜索命中与时间总览都按 `items` 下标走），在没有真机复核的情况下不划算 ⇒ **保留并如实登记**。④ 任务详情（参数/输出）未接 | P2-2 已做：任务条。下一步：轨迹 `JOB` 行与任务条收敛为同一处语义；任务详情下钻 |
| `workflow-run` | 完全未实现；**协议侧也无 workflow 端点**（`dshcompat/Endpoints.ets` 内无匹配） | 先确认上游是否暴露 workflow 端点；无端点则本行长期 `TODO`（**不造无协议支持的假后端**） |
| `cordis` | 无 `cordis_define` 工具行与 run/stop 开关；端点已登记但无调用点 | P2/P3：需要 keyed tool row 能力（与 `tool` 同一批） |
| `skill` | 无对话内技能引用；无专用 skill 工具行 | P2 |
| `message-feedback` | ⓪ **面板已拆成独立组件（P2-3）**：`view/MessageFeedback.ets`（表单态归它，每敲一个字不再重绘整个会话列表）；宿主保留"哪条开着 + 回执 + 提交策略"。① **Edit / More 未接**（Retry 已接：用户消息的"重发"走 `session/prompt`，有真实协议面；助手消息的"重跑那一轮"无端点 ⇒ 不给）（§10 列出的其余操作）：它们需要「重跑某一轮 / 改完再发」的协议面，本仓**没有对应端点** ⇒ 不放点了没反应的按钮（假入口），缺口显式留在这里 ② 面板与 chip 的**观感、触摸目标、四形态**均待真机验收 | P1 已做：类别（契约 7 个取值）→ 可选备注 → 提交 → 存储态回显 → **撤回**（`messageFeedback/delete` + CAS）；P2：Retry/Edit 需先确认协议面是否存在 |
| `commands` | **回执与生命周期已对齐（P7-13）**：① 回执不再只看 `result.ok` —— 官方判定是「命令被宿主**受理**即成功」（生命周期已入日志、结局作为过程节点呈现），**只有** `result.kind === 'error'` 才把处理器给的 `text` 显示出来，`value === undefined`（没解析出来/名字不存在）按官方 `unknown or malformed command` 的语义提示并**保留输入**；② `command/run`（`{commandId,name,args?}`）与 `command/done`（`{commandId,kind,text?}`）按 `commandId` 落成**一条**命令条目（此前 `command/done` 因 `standalone:false` 被直接丢弃、`command/run` 被当内部事件隐掉 ⇒ 执行命令后界面上**什么也不会发生**），视图见 `CommandRow`。**真 Host 取证**：闭环 M2g 真跑一条只读命令（本机选到 `/feedback`）⇒ 回执 `command.rejected` + 宿主原文，轨迹出现 1 条已兑现命令条目（`kind=error`）。**仍缺**：① **三种命令 UI 类型未细分**，尤其 `popupSelect`（宿主让客户端弹「选项列表」再回选，`dsh-client-ui-commands` 有整套 `PopupSelectController`）—— 我们的命令面板只做「选中即执行」，遇到需要选项的命令只能靠用户手打参数；② 命令节点**位置精度**：官方是独立过程节点（在发生处），我们走回合的 NOTICE 槽位（同回合内排在回答之后，信息相同、位置粗一点）—— 留着真机看是否值得单开一槽 | P2：三种 UI 类型与 popupSelect |
| `reference` | **两个源都已接**：`@file`（`fileReferences/list`）与 `@session`（`session/referenceCandidates`）合并进同一个候选表；插入文本**一律取宿主给的 `mention`**（`Wire.projectSessionReferences` 的注释写明了为什么不能自拼 `@session:<id>`——mention 的语法由 Host 决定）。**P7-14 修掉一处插入缺陷**：此前是"往草稿末尾追加"，用户敲了 `@src/fo` 再点候选会得到 `@src/fo@src/foo.ts `（半截查询词留在正文里、且**长得像一条引用**会被 Host 当引用解析）；官方是**替换当前 token**，现在由 `model/InputTrigger.ets` 统一（含目录引用的未闭合引号 `@"dir/` **不补空格**，留给下一次补全继续钻）。**仍缺**：① 官方候选菜单有**分组与图标**（文件/会话分节、目录可"钻取"继续补全），我们是扁平列表 + `@kind` 文本标签；② `@session` 只在本机未配模型时无法端到端验证"插入后 Host 真的能解析出会话引用" | P2：候选菜单分组 / 钻取 |
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
| v1.62 | 2026-09-16 | **P9-2 图片点不开：单图压根点不动，多图只是“就地放大”**。官方 `ImageLightbox` 契约是“点缩略图打开**文档级**原图预览”（遮罩 + `contain` 原图 + 右上角关闭；Esc/点遮罩/关闭按钮都能关；关闭后焦点回缩略图），我们此前只有“就地放大到 240”且**单图没有 onClick**——手机上一张截图看不清。**上一轮把它记成“需要动宿主链”是错的**：ArkUI 的 `bindContentCover` 就是组件自己可挂的全屏模态（系统背景 + **系统返回键接管** + `onDisappear`），官方要 portal 只是因为祖先 transform 会困住 fixed 遮罩。现在：`MessageImage.lightboxFit()` 逐条实现官方三条 CSS（`contain` + `max-width:min(100%,1600px)` + `max-height:calc(100vh-80px)` ⇒ **只缩不放**）、三个无障碍文案逐字取官方中文字典（原图预览 / 关闭原图预览 / `{label}，点击查看原图`），`MessageImages` 给单图与方图**都**挂 `bindContentCover`。登记差异：官方预览原图 URL（我们只有一份字节）、官方半透明遮罩（我们用主题底色——`backgroundColor` 默认是白色，而手写 rgba 被 README 第 2 条禁止）、关闭按钮用本仓触控下限 44 而非官方 36。fixture 1015 → **1030 条**（归真：去掉“只缩不放” ⇒ 1 红）；设计令牌棘轮当场拦下新写的 36/18 ⇒ 换 token；接线门禁 36 → **37 项**；真机判据新增 **D49** |
| v1.61 | 2026-09-16 | **P8-6c 那条红色错误提示不会消失（用户只能问"我到底发出去没有"）**。中枢只有一个 `lastError` 槽位而状态条**无条件渲染** ⇒ 一次"发送被拒"之后成功跑完一整轮，红字还挂着——一条过期的错误让人怀疑已经成功的事。依据 `docs/09` §3.4：「新一轮成功后清除旧的 transient error」「持久连接问题只有真正恢复连接后才清除」。修法：零依赖 `model/ErrorLifecycle`（两种作用域由**写那句话的地方**决定，不从文案猜）：`connection` 只有连上才清、`action` 同类成功即清；中枢侧 `setConnectionError()` 成为连接层 5 处的唯一入口（文案与作用域一起写），连上时清理**放在开流之前**（否则开流失败会产生"写下又被清掉"的诡异读数），发送被接受与 `turn/end` 成功收场各清一次（**失败收场不清**——那条错误正好解释了为什么失败）。fixture 1005 → **1015 条**（归真：规则改成"不看作用域"⇒ 2 红）；接线门禁 35 → **36 项**；真机判据新增 **D48** |
| v1.60 | 2026-09-16 | **P8-7 守卫成了崩溃点：`accessSync` 会抛异常，而我们 24 处把它当"返回 false"**。SDK 声明 `accessSync` 抛 `BusinessError`（`13900018 Not a directory` / `13900012` / `13900005`…），而 `CoreStore.verifyStagedTree()` 的三个"关键件哨兵"**存在的意义就是"树不完整时给一句说得清的失败"**——真缺件时它抛，那句 `fail('解包结果缺少宿主包…')` 走不到，用户看到未处理异常（编译器早在 `CoreStore.ets:424/430/438` 报过 `Function may throw exceptions`）。现在统一走新增的 `hostruntime/core/FileProbe.fileExists()/dirExists()`（异常按"用不了"处理并留 `hilog.debug` code），24 处全换；顺带清三处 API 弃用（全局无参 `getContext()` ×2 —— 一处改成调用方传上下文、一处是零调用点的 `currentWindowId()` 直接删；`TextEncoder.encode()` → `encodeIntoUint8Array`）。**证据**：`devecocli build --modules hostruntime platform` 由 6 条告警变 **BUILD SUCCESSFUL 且这三类为 0**。**又一处门禁盲区**：死代码门禁的正则不认 `export async function` ⇒ 异步导出从未被扫过（补 `async`/`declare`/`abstract` 后 774 个符号/0 死代码）；接线门禁新增**仓库级反面规则**（`accessSync` 全域禁用，豁免 `FileProbe`；归真 ⇒ 红）。库模块权限告警定性为**良性**并写进 `docs/70`。真机判据新增 **D47** |
| v1.59 | 2026-09-16 | **P8-4b 手机上「模型」chip 被挤出屏幕（操作区静默消失）**。输入区工具行是"一行 `Row` + `Blank()`"装七件固定宽度控件，而 `Row` 里没有 `layoutWeight` 的子元素**不会缩**、超出即裁 ⇒ 360vp 手机上**最右边的「模型」chip 消失**（`docs/08` P0 §7 逐字点名了 Composer 工具栏与会话 Header）；同类还有会话头视图切换行（轨迹视图下右侧三个动作）与时间总览统计行（末尾统计项）。官方 Web 的输入区那一行正是 `flex-wrap: wrap; justify-content: space-between`（composer CSS `.W5Twba_row{…}` + `.trailing{margin-left:auto}`）⇒ 放得下靠右、放不下换行，不裁任何控件。现在三处改成可换行的 `Flex` + 两个组（间距改子元素 margin，照抄本仓 `NativeActionBar` 写法），并给消息元信息行的模型名加宽度上限+省略。**门禁新增第三种规则**「必含模式」（`REQUIRED_IN_FILE`）：布局性质是一个符号，全局计数说不出"哪个文件里的那一行"；归真：工具行改回 `Row` ⇒ 当场红在 `Composer.ets`。**如实说明**：布局行为要真机验收（换行观感、大字号行高、软键盘挤压顺序），本机只证明"仍可换行"+ 编译通过；真机判据新增 **D46** |
| v1.58 | 2026-09-16 | **P8-4 改了一半的设置被手一滑关掉，界面一句话都不说**。三个编辑浮层（凭据/文本设置/结构设置）都带拖拽条，误触极易；关闭时草稿被静默清掉 ⇒ 用户以为改动生效了（**假成功**），或回头发现没变却不知原因（依据：`docs/08` 的 Sheet 一节「关闭原因必须可区分」「编辑态关闭前要有明确的取消/保存策略」）。现在：零依赖 `Sheets.sheetDiscardNotice(kind,label,draft,seed)`（判据 = 草稿 ≠ 打开时的种子值；凭据只写不回显 ⇒ 非空即未保存；**枚举选择/目录选择/详情浮层一律空串**——每次都弹废话会让用户无视所有提示）；宿主唯一的主动关闭执行点 `dismissSheetByUser()` 接在 `shouldDismiss` 上（**程序化关闭不走它** ⇒ 不会"保存成功了还说已放弃"）；文案四要素（发生了什么 / 是哪一项 / 有没有写入 Host / 下一步），回执落到该项所在的设置域。fixture 993 → **1005 条**（归真：改回永远返回空串 ⇒ 6 红）；接线门禁 34 → **35 项**；真机判据新增 **D45**。**仍缺（已登记）**：系统级关闭无单独语义；不做"关闭前弹确认"（没有真机看不到确认框） |
| v1.57 | 2026-09-16 | **P8-3（后半）草稿跨重载：把矩阵里那条登记划掉**。官方契约两半，"survives session switches" 上一轮已兑现，"**and reloads**" 还欠着 ⇒ 应用一重启，没发出去的草稿全丢（登记在 `hdsh-composer-drafts`）。现在：① 纯模型 `ComposerDrafts` 增加 `serializeDrafts` / `parseDrafts`（平行数组原样序列化以保住"最近写过"的顺序；解析宽容——坏 JSON/形状不对/元素类型不对当空或丢该项，但**两数组长度不一致整个丢掉**，否则会把甲的草稿显示在乙的会话里）；② `platform/LocalPrefs` 只加一个**不透明字符串**键（形状由模型定，`platform` 不许依赖 `appstate`）；③ 宿主启动时读回**进袋子**（不填输入框：启动时还没有选中会话）且**只在内存袋子还空**时采用磁盘值（`prefs.attach` 异步，期间用户可能已敲字）；两个变更点（切会话 / 发送成功或被排队）各落一次盘，落盘失败给一次轻提示（草稿丢了要等下次启动才发现）。fixture 983 → **993 条**（归真：去掉长度一致性校验 ⇒ 1 红）；接线门禁「每会话草稿」扩到八段；矩阵该行 PARTIAL → **DONE**，§6 登记移除；真机判据新增 **D44** |
| v1.56 | 2026-09-16 | **P8-3 草稿跟着用户跑错了会话**。官方 `dsh-client-ui-conversation` 的视图契约逐字写着草稿是**会话视图状态的一部分**且要跨切换/重载存活（`contract/views.d.ts`："Composer draft (persisted; survives session switches and reloads)"），而我们是一份全局 `@State`：在会话 A 里写一半、切到 B、顺手发送 ⇒ **那段话发给了 B**（内容与收件人都错）。同一处的连带问题：附件本就是会话作用域（中枢切会话清空），草稿却不是 ⇒ 输入框里"文字属于上一个会话、附件属于这一个"。现在新增零依赖 `model/ComposerDrafts.ets`（按会话存文本草稿：平行数组、最近写过排最前、空文本删条目、上限 24）与宿主唯一的切换点 `switchDraftContext()`（`openSession` 与"离开会话页签"都经过它），发送成功或进待发队列后丢弃那一份（否则切回来会把已发出的原文又还给输入框）。fixture 967 → **983 条**（归真：`draftOf` 忽略会话 id ⇒ 3 红）；接线门禁 33 → **34 项**；真机判据新增 **D43**。**仍缺（已登记 §6）**：契约后半截 "…and reloads"——重启后草稿仍丢，需要落盘 + 启动时序 |
| v1.55 | 2026-09-16 | **P8-6 一次网络抖动画出「一墙红色错误卡」（重试链被当成 N 次独立失败）**。官方 `RetryId` 逐字是**链**身份（`dsh-llm-retry/lib/types/brand.d.ts`："Stable identity shared by every attempt in one request-step retry chain."），生产者 `recover()` 按 turn/step/provider/policyKey 复用上一条的 `retryId`；官方界面据此把整条链渲染成**一个** `model-retry` 节点（`RetryState{turn, step, attempts[]}`）。我们 P7-18 把它读成"每次重试唯一"⇒ 同一次故障的 5 次重试成了 5 条默认展开的红色错误卡：用户看不出这是同一个请求在自动重试。现在：`RETRY_ID` 槽位进 `dshcompat`、条目 id 由纯函数 `retryItemId(attempt, chainId)` 算（同链一行；老 Host 无 id 时退回每次一行）、`retryStarted: boolean` → `retryState`（scheduled/started/**cancelled**）、合并规则「序号更高就听新的 + started 单向 + cancelled 最强势」、`cancelTurn()` 把还在等待的标成已取消（否则那一行永远写着"等待重试… 7s"——不会发生的承诺）、文案换成官方一行模板 `{label}（{n}/{max}） · {s}s` 与官方四段标签（含"模型请求重试已取消"）及官方秒数规则（`max(1, ceil(ms/1000))`）、视图补官方 `重试延迟：`/`失败原因：` 两行、删掉只有写点的 `retryMode` 字段。fixture 947 → **967 条**（归真：id 规则改回按次数 ⇒ 2 红；状态合并改回"或" ⇒ 1 红）；接线门禁「重试行」项同步更名；真机判据新增 **D42**。**登记差异**：官方节点保留整条 `attempts[]` 历史且渲染成可展开 `<details>`，我们只留最新一次的序号与原因、恒展开（D3 §4 要求失败可见） |
| v1.54 | 2026-09-16 | **P8-5 敏感内容隔离：点一下时间线格子就能读到完整的系统提示词**。事实源是本仓审计 `docs/09` §2.2/§4（官方 Web 没有"系统提示词该不该给用户看"这条契约，但它给的 `system/message` 类型与我们的 `internal` 标记是同一件事 ⇒ 这一轮同样不假装对齐上游）。**修掉的真实泄露**：时间线是可点的，而内部事件也产生格子（`system/message` 是 kind=MESSAGE）⇒ 点开「事件详情」本可读到整段系统提示词（未识别事件则是整段原始载荷）。现在 `TrajectoryDetail` 对内部条目**一律不画正文类字段**（正文/思考/工具参数/工具结果/错误原文），只留结构化事实（类别/状态/工具名/模型/字符数/耗时）+ 一行写清"为什么看不见"的说明；判据 `Turns.mayExposeBodyToUser()`（与对话可见性同源的 `internal` 事实）、取值 `Turns.userFacingBodyOf()`（复制两处 + 引用一处都改从它取）、脱敏 `Redact.scrubCredentials()`（从 `Notify` 搬进**零依赖**新模型 `model/Redact.ets`，理由：规则留在通知里等于"只有通知这条出口脱敏"；搬出来后 fixture 能直接执行它）。**Host 原文统一脱敏**：`FailureText.hostDetail()` 一处收口（错误行/诊断报告/剪贴板三个出口共用），5 种凭据形状被 fixture 钉住。**顺带核实并如实记录（不是缺陷）**：通知早有 `assertNoSensitiveContent` + `sanitizeDetail` 两道闸；旁路日志只有 id 前缀/条数/错误码，无正文。**本轮还修好门禁自己**：`check-dead-code` 剥块注释不保留换行 ⇒ 行号错位 ⇒ "零使用 import"**长期假阴性**；对齐后 **44 个真死 import** 现形并删净，计数口径改为"剥注释、保留字符串"（模板串用法才算使用）。fixture 922 → **947 条**（归真：改回旧行为 ⇒ 9 条红）；接线门禁 32 → **33 项**（「内部内容隔离」）；真机判据新增 **D41** |
| v1.53 | 2026-09-16 | **P8-1 返回键层级：第一次白按、第二次退出应用（并按 `docs/08` 的 P0 §1/§2 收口）**。事实源是本仓审计 `docs/08-UI与返回交互审计.md`（P0 §1 组合态漏洞、§2 归一化）+ 一条布局事实（`WorkspacePane.buildStacked`：0=工作区列表、1=文件树、**≥2=预览**）——**不是**官方 Web（Web 没有物理返回键，这条无法从上游取证，故不假装对齐上游）。三个缺陷：① `decideBack()` 把"工作区下钻"排在"关预览"之前，而单栏下预览**就是第 2 层** ⇒ 按返回只减层数、`previewOpen` 留着，之后**白按一次**；现在 `previewIsLayer()` 判定"预览是不是盖在页面上的整页层"（多栏并排栏不算层）⇒ 整页层排在下钻之前、并排栏仍排在页面层级之后（同一事实、同一判定），`drillAfterPreviewClosed()` 保证关预览同时退回文件树。② 关预览是**假关闭**：视图写 `this.preview = undefined`，而真值在中枢 `SessionHub.filePreview`（视图只是镜像，每次广播覆盖回来）⇒ 下一次中枢广播把预览装回来；中枢 `closeFilePreview()` 此前**零调用点**，现由接线门禁第 32 项钉住。③ 手机会话页：`openSession` 在单栏下既切主区面板又设 `stackPage=CONVERSATION`，而 `STACK_TO_MAIN` **只改 `stackPage`** ⇒ 按返回屏幕无变化、再按一次到根层**直接退出应用**；新增 `BackAction.BACK_TO_LIST`（回列表 + **保留会话**），排在二级页之前。④ 归一化收口：四个"退回一层"入口共用 `Index.consumeBack()`；浮层复位只剩 `closeSheet()`（三个 `closeXSheet()` 变一行委托；顺带修掉结构浮层关闭清错忙标志的错位——如实说明它未变成已复现缺陷）。fixture 908 → **922 条**，含新增 **2304 种组合态矩阵**（阶梯写成数据表 + 独立实现对账）；接线门禁 31 → **32 项**（并且**修掉它自己的一处瞎**：计数不剥注释 ⇒ 注释里写出符号名就能把“调用点被删”判绿，现改为只看代码，同一归真因此立刻红）；**归真验证两处**：只回退次序与会话整页分支 ⇒ 矩阵红 **74/2304**，还原即绿；真机判据新增 **D40**；`docs/07` 的 P0 段据此重写（剩余：Sheet 关闭原因回传、多栏预览面板是否吃返回键） |
| v1.52 | 2026-09-15 | **P7-21 回合产出文件行（官方 `ui-deliverables` 的 turn-tail 槽位）**。官方规则：来源是**成功的写类工具调用**（`write`/`edit`/可变 `str_replace_editor`）的参数，**不是**回答正文——"a produced file must be listed whether or not the model remembered to name it"；读/未知工具/畸形参数/失败结果都不算；路径首次出现顺序 + 去重。我们此前只有 `deliverables/presented` 事件（取决于模型是否上报）⇒ agent 改了文件但没上报时用户看不到产出。现在：零依赖 `model/ProducedFiles.ets` 按同一规则推导（**复用** `ToolDiff.intendedDiffOf()` 的收窄判据，不重写解析），`view/ProducedFilesRow.ets` 在回合尾部渲染 chip（0 个不渲染），点 chip **读内容 + 切到工作区页**（只读不切在手机上是"点了没反应"）。差异登记：官方的 `fitProducedFiles()` 按宽度测量，我们横滑 + 上限 6 + 文案交代总数。fixture 896 → **908 条**；接线门禁 30 → **31 项**；真机判据新增 **D39** |
| v1.51 | 2026-09-15 | **P7-20 目标栏从"只读"变成可操作（并对齐官方的渲染规则）**。官方 `dsh-client-ui-goal` 的契约：`phase` 决定动词（`active`→暂停、`paused`→继续）+ 编辑（同一行内联表单）+ 清除，**创建走 `/goal` 命令不在栏里**；且 `loading/no goal/complete` **整条不渲染**。我们此前：① 只有 `refreshGoal`（读），四个动词一个都没有；② 解析只取正文（候选键名去猜）⇒ 没有相位，显示不出"已暂停/受阻"，也无法决定给哪个动词；③ 空态白占一行。现在按 `dsh-goal` 的权威类型逐字投影（`GoalRef{id,revision}` / `GoalSnapshot{objective, phase, blockedReason?, maxGoalRounds}`），写动词用生成表的参数名且 `ref` 必带 `revision`；并补上**实时性**——官方读的是宿主算好的 `goal` 投影，我们既读投影也吃 `goal/change` 事件（非 clear 带整份快照；clear 清空），两条来源共用 `applyGoalView`；写动词**不做乐观改**（等事件/回复快照落地）。判定全在零依赖 `model/GoalBar.ets`（fixture 22 条），**唯一保留的空态是"读不到"**。fixture 874 → **896 条**；真机判据新增 **D38** |
| v1.50 | 2026-09-15 | **P7-19 失败文案：上游 46 个错误码，我们只写了 13 句**。上游 `dsh-api-session-controller` 的 `RemoteErrorDetailsMap` 是**权威错误码表**（46 个码，各带 details 形状），而本仓此前只有 `friendlyFailure()` 的 8 个特例 + `friendlyWorkspaceFailure()` 的 5 个，**其余一律兜底 `${code} ${message}`** ⇒ 真机上出现「session/conflict session "xxx" already has cwd "/path"」这种只有开发者读得懂的句子。现在：新增零依赖 `appstate/model/FailureText.ets`（40 条专门文案 + 客户端自己的码 + **`REACHABLE_FAILURE_CODES` 可达集合**），中枢两个函数瘦成一行委托。两条纪律被 fixture 钉住：**兜底必须带上原始码并说清"还没有专门文案"**（上游多新码时界面看得见）、**专门文案不许以 code 开头**。两个码特意"看原文分流"：`session/attachment-invalid`（文件回执 vs 图片，两种成因处置不同）与 `carrier/*`（必须带底层 reason）。**门禁当场抓到一次搬家丢逻辑**：改委托时我把这两处的特例丢了，对账断言立刻红——这正是"搬进纯模型 + 对账"的价值。fixture 850 → **874 条**；接线门禁 29 → **30 项** |
| v1.49 | 2026-09-15 | **P7-18 模型重试：从"出错了 + 一片空白"到带倒计时的重试行**。上游 `llm/retry` 是 `{mode:'normal', retry, maxRetries, delayMs, failure:{code,message}}` 或 `{mode:'always', retry, delayMs, failure}`（`dsh-llm-retry` 类型逐字，`invariant` 保证 failure 两字段非空），`llm/retry-started` 在等待结束、请求发出前写入；官方 `ModelRetryItem` 据此显示「第几次/上限 + 倒计时 + 原因」。我们此前只绑 `retry` 一个槽位（注释写着 failure 形状"未实测"）、拼成 `title = "重试 2"`、正文为空，而 `llm/retry-started` 是 `standalone:false` ⇒ **被投影直接丢弃**（界面永远停在倒计时）。于是设备网络最差时用户看到一条"出错了"加空白：不知道在重试、第几次、还要多久。现在：五个槽位逐字绑定、`retry-started` 成真条目、`TrajectoryItem` 加五个重试字段（`retryMax = -1` 表示无上限，不用 0 以免读成"上限 0 次"）、两段文案进纯模型 `Present.retryCountLine/retryWaitLine`（fixture 10 条）、新组件 `view/RetryRow.ets` 给每秒自减的倒计时（只在未开始时开定时器；起点用**事件时间** `item.at`，否则迟到的事件会让倒计时偏大）。顺带删掉错误行里那个**没有 onClick** 的假「重试」标签。fixture 840 → **850 条**；接线门禁 28 → **29 项**；真机判据新增 **D37** |
| v1.48 | 2026-09-15 | **P7-17 审批卡回到「两选」（删掉假入口）+ 清理没有调用点的产品层词汇**。官方 `dsh-client-ui-approval` 的审批卡只有两颗按钮（源码：`answer("rejected")` 与 `answer("allowed-once")`），因为上游 `ApprovalOutcome` 是闭集且**没有持久授权**。我们此前多一颗「本次会话内均允许」，文案写着「仅在本客户端生效」，而实现里 `always` **只写一行旁路日志**——也就是说：它连「本客户端」都没生效。按本仓「不放点了没反应的假入口」的规矩直接删掉，回到官方两选。同轮把 `Wire` 里那套**零调用点**的产品层词汇也删了（`ApprovalDecision{ALLOW_ONCE,DENY,ALWAYS}` / `approvalOutcomeFor` / `decisionIsClientSideOnly` / `approvalAnswer` / `ApprovalAnswerValue`，全靠 barrel 再导出撑着——零消费者门禁按既有边界**不扫 `Wire.ets`**，所以它们一直没被发现）；`ALWAYS` 正是那颗假按钮的余毒。顺带：审批请求改用既有的 `Wire.projectApprovalRequest()` 读（此前中枢就地 `getString` 是第二份实现），并且**缺 `toolName` 时交还链条**——不再摆一张「未知操作 + 允许一次」的卡（审批一律 fail-closed）。真机判据新增 **D36** |
| v1.47 | 2026-09-15 | **P7-16 排队项的两个良性竞态被当成"失败"**。上游 `session/queue-item-not-found`（"queued item is no longer pending"）与 `session/steer-unavailable`（"current turn no longer accepts steering"，条件 `action.kind === 'steer' && (target !== 'next-turn' \|\| agent.status !== 'running')`）都不是失败，而是"你慢了一拍"；官方客户端明确要求**静默收敛**（`dsh-client-ui-conversation`：`"…converges silently, while a genuine failure surfaces as one composer notice"`），并且**依赖**这种收敛来处理重复触发（快照比 Host 慢一拍时重复插话应是无操作）。我们把任何失败都写成红色横幅 ⇒ 连点两下「插话」、或轮次刚结束时点「插话」都会显示「修改待发队列失败」（假失败，用户会去重试/怀疑网络）。现在两个码成为 `dshcompat` 具名常量，判定与文案在零依赖 `model/QueueRace.ets`，中枢命中即记账 + 视为收敛 + 不设错误横幅；其余码照旧报错。fixture 828 → **840 条**；接线门禁 27 → **28 项**；真机判据新增 **D35**。（弯路记一笔：两个码第一版被我写进 appstate，`arch-check` 判红——上游字面量只许住 `dshcompat`；现在码与判定在 `dshcompat/QueueCodes.ets`，用户可见文案留在 appstate。）|
| v1.46 | 2026-09-15 | **P7-15 发送失败后草稿凭空消失**。官方 `dsh-client-ui-conversation` 的 `sink()` 注释写明了提交语义：`"Default sink: optimistic clear + prompt. … a failed first prompt is an ordinary prompt failure (banner via promptError, **draft restored only while untouched**)."` —— 先乐观清空、失败走错误横幅、**只在用户没动过输入框时**把原文还回去。我们此前是"清了就不管"（`Index.sendDraft()` 第一件事 `this.draft = ''`，之后不看结果）⇒ 宿主拒绝/参数不符/连接刚断时用户的长消息**凭空消失**，只能重敲。现在：零依赖纯模型 `model/ComposerSend.ets` 的 `shouldRestoreDraft(sendOk, queued, currentDraft, submitted)`（成功不还 / **已排队不还** / 输入框非空不还 / 原文为空不还），中枢新增 `HubSnapshot.lastSendQueued` 明确告知"这次失败是不是已经排队了"（离线排队时还回去会造成**同一条消息发两遍**；让视图解析 `lastError` 文案去猜是脆弱的）。连带修正：未配置 Host 时不再"清空后什么都不做"。fixture 822 → **828 条**；接线门禁 26 → **27 项**；真机判据新增 **D34** |
| v1.45 | 2026-09-15 | **P7-14 `@`/`/` 输入触发：修掉"追加而非替换"**。官方的 `dsh-client-ui-input-trigger` 是"检出 `@`/`/` → 候选菜单 → 把选中项**替换当前 token**"（`slash/input-consume-token` 带 `{kind:'span', span}`），而我们两处 click 处理都是 `draft + insert + ' '`：用户敲 `@src/fo` 再点候选，输入框里得到 **`@src/fo@src/foo.ts `** —— 半截查询词留在正文里，而且它**长得像一条引用**，Host 会去解析一个不存在的 `@src/fo`。现在把词法搬进零依赖纯模型 `model/InputTrigger.ets`：`detectTrigger`（命令：行首 `/` 且尚无空白；引用：行内最后一个 `@` 且其后无空白；转义 `\@` 不算）、`applyPick`（**替换** token 区间，保留前后正文）、`needsTrailingSpace`（对齐官方 `formatFileMention`：目录引用的未闭合引号 `@"dir/` **不补空格**，否则下一次补全接不上）、`appendPick`（先点按钮再选候选的兜底）。18 条 fixture 钉住（含"替换后不再残留半截查询词"这条正是本次修的东西）。fixture 799 → **822 条**；接线门禁 25 → **26 项**；真机判据新增 **D33**。**同时更正一行状态注水**：本行此前标 DONE，但"选中即替换"这件事一直没做对——状态行不变（功能现在确实做完），缺陷记在变更记录里 |
| v1.44 | 2026-09-15 | **P7-13 斜杠命令：修掉「界面无反应」与「假成功」**。上游 `dsh-commands` 的 `execute()` 有两件事我们此前都没做对：① 命令的生命周期（`command/run{commandId,name,args?}` → `command/done{commandId,kind,text?}`，**靠 `commandId` 配对**）在官方是**对话里的持久过程节点**，而我们把它标成 `standalone:false`（`done` 帧被直接丢弃）+ 列进「内部事件」（`run` 帧不显示）⇒ 用户执行命令后**界面上什么也不会发生**；② 回执只看 `result.ok` ⇒ 「命令没解析出来 / 处理器报错」**全部显示「已执行」**（假成功）。现在：命令有自己的族（`EventFamily.COMMAND`）与条目类型（`TrajectoryKind.COMMAND`），两帧按 `commandId` 落成一条并给出 **进行中/已完成/失败** 三态（`view/CommandRow.ets`，失败时把 `text` 直接显示）；`executeCommand` 读回执的 `result.kind`：受理=成功、`error`=「命令被拒绝：…」、`value===undefined`=「宿主不认识这条命令」。**真 Host 取证**：闭环新增 M2g 真跑一条只读命令（白名单外则 SKIP，不拿会话冒险），本机 `/feedback`（缺参数）⇒ `command.rejected` + 宿主原文，轨迹里 1 条已兑现命令条目（`kind=error`）。**门禁抓到一个坑**：两帧可能乱序，`'running'` 不能覆盖已兑现的结局（fixture 当场红）。fixture 788 → **799 条**；闭环 21/21 → **22/22**；接线门禁 24 → **25 项**；真机判据新增 **D32** |
| v1.43 | 2026-09-15 | **AGC 提审预检并入第 10 道门禁 + 提交步骤写成可照抄的清单（P7-12）**：`docs/70` 此前已有权限对账与 release 打包，但"提审要看的字段与资源"只在文档里用散文描述，而这些字段**错了不会构建失败**：`deviceTypes` 少写一个 ⇒ 那种设备**装不上**（上架后才发现，看起来像"不兼容"）；`abilities[].skills` 少了桌面入口 ⇒ 装上了但**桌面没有图标**；`$string:app_name` 指向空串 ⇒ 应用名是空白；图标引用指向**存在却非法**的文件同样不会报错。现在 `tools/check-compliance.mjs` 增加一段"包元数据与资源预检"（同一道门禁，避免"少跑一个门禁等于它不存在"）：bundleName 反向域名 / vendor 非空 / versionCode 正整数 / versionName x.y.z / `runtimeOS=HarmonyOS` / target 与 compatible SDK 都在 / buildModeSet 含 release / `type=entry` / **deviceTypes 含 phone·tablet·2in1** / deliveryWithInstall / 桌面入口 `entity.system.home` + `ohos.want.action.home` / ability 四个资源字段都是资源引用 / **每个资源引用都能解析**（AppScope 与 entry 两处）/ 应用名与 ability 名**非空** / 三个图标是**合法 PNG**（并打印尺寸：1024×1024、1024×1024、144×144）。**归真验证三处**：去掉 `tablet` ⇒ 红；`foreground.png` 换成文本 ⇒ 红；`app_name` 置空串 ⇒ 红；全部还原 ⇒ 绿。`docs/70` 同步新增 **§6.4 提交步骤（照抄即可）**（AGC 各字段填什么 / 签名材料怎么来 / 出包怎么确认"已签名 + 可疑内容无" / 商店材料谁提供）与 §0 摘要、§8、§9 的更新 |
| v1.42 | 2026-09-15 | **E384 修复：把随包的 sharp 桩换成真件（图片能力的前置）**。上一轮查出"随应用分发的核心 zip 里 `sharp.impl` 是 E79 留下的 602 字节桩"（⇒ 设备上一切图片处理必然失败，还被包装成"图片数据损坏"）。本轮把修法走完：① `node tools/pack-core.mjs`（**不带** `--skip-install`）重新物化 ⇒ 新树里 `sharp.impl` 就是 `@ohos-ports/sharp@0.34.5-beta.12` 真件，`--check-sharp` 由红转绿；② 把真件落进**随包的那棵树**并 `--skip-install --place-in-app` 重打核心 zip（66.2 MB，解包逐字核对 `sharp.impl/package.json`）；③ **修正上一轮的一个错误判断**——当时"手工替换不可行"的结论来自开发机平台名 `linux-arm64` 让 port 的解析落到 wasm32 回退，真机平台名是 `openharmony-arm64`，那条路本来是对的；④ **实证本地无法端到端验证**：直接 require 那个 `.node` 得到 `/lib/aarch64-linux-gnu/libc.so: invalid ELF header`（它对着 OHOS libc 链接，glibc 上必然失败）⇒ 设备上图片能否出图只能由 **D31** 判定；⑤ **修掉一个会误导的探针**：宿主 `runtimeFacts()` 原来**绕过调度器**直接 require 原生件，绕过了真件在 require 时建 soname/RPATH 兼容软链与 `LD_LIBRARY_PATH` 的必要动作 ⇒ 设备上真件可用时它也会报失败，而 D31 第 0 步正是看它；现在走调度器 + 三条同步判据，本机读数变成诚实的 `Could not load the "sharp" module using the linux-arm64 runtime`；⑥ `check-core-loop.mjs` 支持 `HDSH_LOOP_CORE` 指向另一棵核心树（对照实验用，避免为本地方便污染随包那棵树）。核心闭环 **21/21** 保持；10 道门禁全绿 |
| v1.41 | 2026-09-15 | **P0-4 输入区发图 + E384「随包的 sharp 是桩」**：本轮做"手机发一张图"（官方 `serializeImages()` 的内联 `image` 片段）：`platform.pickImage()`（系统图库，**不新增任何权限**）+ `SessionHub.attachLocalImage()`（**内联，不走上传**）+ 纯模型 `model/InputAttachment.ets`（官方顺序"图片在前、正文在后"；官方四条类型白名单；魔数嗅探救回没有扩展名的图库 URI；12 MiB 内联上限）+ 附件条缩略图 + 离线时**明确拒绝**（图片没有可稍后补发的凭据）。**代码做完、fixture 788 条全绿，真 Host 却回 `Unsupported or malformed image data.`** —— 顺着查下去发现比功能本身重要的事：解包随应用分发的核心 zip 逐字核对，`node_modules/sharp.impl` 是 **E79 留下的 602 字节桩**，而 `dsh-attachment-local` 正是用它做图片接纳 ⇒ **设备上一切图片处理必然失败**，且失败被包装成"图片数据损坏"。它一路没被发现，是因为桩**import 时不抛**（所以打包日志写着"真件在 sharp.impl"、运行时事实也不报不可用）、真件确实在包里、而报错又指向用户。**已做**：① 构建期闸门 `assertSharpImplIsReal()`（在**幂等分支**也校验——那正是漏掉的地方；判据用"真件该有的文件"而不是桩的文本）+ 只读 `--check-sharp`（对当前树**判红**，`--allow-sharp-stub` 才放行并警告）；② 诊断报告新增「原生件」一行（`sharp` 的结论与原因，真机取证的唯一通道）；③ `friendlyFailure` 对这一 code 按 `message` 分支并明说"或图像解码器不可用"；④ 核心闭环新增 **M2f**：走应用自己的入列+发送通路把一张 1×1 真 PNG 打给真 Host，三种结局分开判（接纳=最强证据 / 解码器不可用=**SKIP 并写清原因** / 其余=缺陷）。**未修（已登记）**：核心需重新物化（`pack-core` 不带 `--skip-install`）才能把真件放到 `sharp.impl`；手工替换试过，本机在 `sharp.format()` 处就炸（会留下更难查的"半可用"树），故不做。fixture 755 → **788 条**；核心闭环 20/20 → **21/21**（M2f 为 SKIP）；接线门禁 23 → **24 项**；真机判据新增 **D31** |
| v1.40 | 2026-09-15 | **E383 文件变更流的自激（可用与稳定）**：顺手读核心闭环宿主日志时发现 `files changes opened` / `POST /api/workspaceFiles/list` / `workspaceFiles/changes 结束` 三行在**同一秒重复 367 次**（而用户什么也没做）。成因是闭环：变更帧回调 → 重列 → **重订阅** → Host 又推一帧"初次快照" → …。修法：`ensureFilesStream(sessionId, force)` —— 订阅**只在作用域变化/用户驱动时**建立；变更帧按 300 ms 合并再重列；一秒内超过 10 次即判自激、跳过并记账（今后任何形态的自激都退化成"自动刷新停了（日志可查）"，而不是 RPC 风暴）。`onEnd` 不重订阅、`onError` 清作用域标记这一区别是刻意的（否则一次网络抖动会让自动刷新永久停摆）。**顺带修文案**：`session/attachment-invalid` 有**两种**用法（读历史图片 / 解析提示词里的文件回执），上一轮只写"图片附件"对文件那条路是错的。**归真验证**：核心闭环新增第 20 步「workspaceFiles/list 调用次数有界」——`git stash` 掉修复回到修前版本 ⇒ 门禁报 **375 次（上限 8）❌**；还原 ⇒ **2 次 ✅**；闭环 19/19 → **20/20**。真机判据新增 **D30** |
| v1.39 | 2026-09-15 | **P0-3 消息图片（官方 `ui-attachment` 的消息图 / 轨迹图两个槽位）**：图片块此前在投影层被降级成正文里的字面 `[image]` ⇒ 真机上用户看到的是那五个字符。现在整条链补齐：投影（`projectImageBlock`）→ 中枢读字节与缓存（`imageUrlOf`/`imageErrorOf`/`retryImage`，键含会话 id）→ 呈现（`view/MessageImages.ets`，几何真值在零依赖 `model/MessageImage.ets`）。几何逐条对齐官方 `singleFit` 与 CSS（240 / [0.25,4] / 不放大小图 / 64px 方图 / gap 10 / 圆角 16 / 按角色对齐）。**门禁抓到一次方向错误**：`scale` 写成"框 ÷ 图"（官方为"图 ÷ 框"）⇒ 大图缩小、小图放大，两条 fixture（1000×1000 ⇒ 240×240、100×50 ⇒ 原样）当场红。**真 Host 取证**：核心闭环新增 M2e 步，假附件 id ⇒ `session/attachment-invalid` ⇒ 端点已实现（据此写 `friendlyFailure` 文案）。fixture 728 → **755 条**；核心闭环 18/18 → **19/19**；接线门禁 23 → **24 项**；真机判据新增 **D29**。仍缺：输入区发送图片、官方灯箱、图片另存/分享 |
| v1.38 | 2026-09-15 | **P7-11 应用内隐私与权限说明 + 上架合规对账门禁**：AppGallery 材料分两半（控制台里填的 / 应用里能看到的），而两半之间最容易出的问题是**漂移**（文档说两项权限，包里悄悄多一项）。新增 `model/PrivacyDisclosure.ets`（数据做法 6 条 + 权限 2 项 + 版本日期，**单一真值**）+ 设置→设备里的折叠块（与 `module.json5` 逐项对账）+ **第 10 道门禁** `tools/check-compliance.mjs`：① 权限清单双向对账（多一项/少一项都红）② 12 项**刻意不申请**的权限一旦出现即红（读剪贴板/位置/相机/麦克风/通讯录/媒体/Wi-Fi/跨设备…）③ 设置页必须真的渲染这两段（否则"应用里能看到"是空话）。门禁**注入式归真验证**：临时塞入 `READ_PASTEBOARD` ⇒ 红；还原 ⇒ 绿 |
| v1.37 | 2026-09-15 | **P7-10 计划待审面板**：官方 `dsh-client-ui-user-questions` 的 `planReviewOf` 把带 `intent.kind=plan-review` 的**单题**请求换成计划面板（`计划待审` + 正文 + `确认执行`/`拒绝`/`去聊天里说`），**六条收窄规则**（单题 / 有 detail / 非多选 / 选项 ≤2 / approve 标签必须存在 / 其余至多一项当拒绝）—— 官方理由："意图只改变布局，绝不改变可达的答案"。**我们此前连 `intent` 都没投影** ⇒ 计划请求只能以通用题组出现。现在：投影 `intentKind`/`intentApprove` + 纯函数 `planReviewOf` + 面板（确认执行/拒绝=按**标签原文**作答；去聊天里说=上一轮的 `ASK_CANCELLED` 帧）。fixture 708 → **719 条**；接线门禁 22 → **23 项** |
| v1.36 | 2026-09-15 | **P7-9 放弃整组提问（取证到位后落地）**：上一轮记的"`nav.cancel` 线上语义未取证"，这轮把三层证据读齐 —— `questionError()` 造 `UserQuestionError`/`ASK_CANCELLED` → `pending.cancel()` 抛出 → 网关把"监听器抛错"编码成 `{kind:"rejected", error:{name,message,code}}`。我们发**同一帧**（`Wire.questionCancelledError`），并补上官方文案的「放弃整组问题」按钮；失败时**不移走卡片**（移走会让用户以为已取消）。接线门禁 21 → **22 项**。**提问这条线至此没有"未取证"的缺口**（只剩计划复核与卡片的收起/展开） |
| v1.35 | 2026-09-15 | **P7-7 提问的两条官方规则取证并落地**：① **推荐标记编码在标签后缀里**（官方 `parseRecommendedLabel` 正则，半角/全角括号、大小写不敏感）：显示剥掉后缀 + 「推荐」徽标，**提交仍送原标签**；② **答案编码三条规则**（官方 `submitDrafts`）：单选 + 自定义 ⇒ `selected: []` + `custom`，多选 ⇒ 并存，跳过 ⇒ 空选择不带 custom —— 我们此前"一律都送"是错的。两条都进纯模型（`parseOptionLabel` / `encodeQuestionAnswers`）+ fixture；`nav.cancel` 的**取证结论**（官方让提问以 `ASK_CANCELLED` 失败，不是 delegate）已写进矩阵，但**不实现**（发哪种 `$events/result` 帧未取证）。fixture 696 → **708 条** |
| v1.34 | 2026-09-15 | **P7-6 权限预设：能切就切，不能切就说"不可用"（先探后做）**。先扩 `tools/check-core-loop.mjs` 探真 Host：`current=(空) options=0`、命令表 5 条里**没有** `/permission`、12 组设置里没有权限键 ⇒ 官方那两个入口在这台 Host 上本来就都不可用。实现：新增零依赖 `model/Permissions.ets`（能力判定 / chip 文案（官方 `unavailable` 原文「不可用」）/ `/permission <id>` 命令形式 / 原因文案）；`SessionHub.selectSessionPermission` 复用命令通道，**没能力时直接发本地回执**（不让用户把宿主那句 unknown command 误读成"我们发错了请求"）；权限 chip 分两态：有能力可点（复用 `ChoiceSheet`，哨兵键名分流）→ `/permission <id>`，没能力显示「不可用」+ 原因。fixture 686 → **696 条**；真机判据新增 D28 |
| v1.33 | 2026-09-15 | **P7-5 提问整组（修一个会卡死对话的缺陷）**：官方 `dsh-client-ui-user-questions` 是整组卡（一个按钮前进、最后一题变「提交」、`nav.prev`、`action.skip`、提交前用 `error.incomplete`/`error.unanswered` 拦阻）；**我们此前只投影 `questions[0]`** ⇒ 后几道题用户答不了，而 Host 要等整组答案才继续 —— **一轮对话卡死**。现在整组进 `PendingItem.questions[]`、应答改**整组一次回**（`answerQuestionGroup`：Host 等的是一个答复值 `{answers:[…]}`，逐题各发一次会让"第一次就结掉、后面的没处去"）、新增 `QuestionGroupCard`（逐题草稿 + 上一题/跳过本题/提交；单题不显示"第 1/1 题"这种噪音）。**如实登记两处没做**：`option.recommended`（我们的选项投影没带这个字段 ⇒ 不画，也不拿第一项冒充推荐）、`nav.cancel`（放弃整组 —— 官方这一动作的线上语义未取证 ⇒ 不做语义不明的按钮）。fixture 670 → **686 条**；真机判据新增 D27 |
| v1.32 | 2026-09-15 | **P7-4 轨迹条目的事件详情（inspector）**：官方轨迹点一条事件会开出「事件详情」面板（`details.event`：状态/用途/提供方/模型/工具调用/子工具调用/错误/结果/来源/层级/助手消息）。新增零依赖 `model/TrajectoryDetail.ets`（`trajectoryDetailRows`：**空值不产生行**，长文本复用工具卡同一套截断阈值；内部事件在「来源」里如实标注「· 内部事件」）+ `view/TrajectoryInspector.ets`，**会话头时间线下方**与**右栏「轨迹」面板下方**两处共用同一份。官方那些来自它自己事件模型的字段我们没有 ⇒ 不画。fixture 654 → **670 条**；真机判据新增 D26 |
| v1.31 | 2026-09-15 | **P7-1 会话搜索（官方 sidebar 的一等能力）**：官方 `dsh-client-ui-sidebar` 的包描述就是"session multi-level tree, **search**, grouping, state dots"，而我们此前**一个入口都没有**。按官方 `dsh-client-ui-workspace` 的形态实现：输入关键词 ⇒ 会话区**换成扁平结果列表**（标题 + 工作区上下文 + 内容片段），标题命中本地算、内容命中走 Host 的 `session/search`（`docs/11` 已有载荷契约：`{request:{query}}` → `{items:[{sessionId,snippet}],hasMore}`，上限 20 / 片段 240 code points），两路**合并去重**（官方语义）。**真机之外的实测发现**：本机真 Host **未挂** `@deepseek-ai/dsh-session-query` ⇒ `session/search` 回 `gateway/internal`，因此"降级为标题匹配 + 明确说明原因"是**当前真正在跑的那条路**（不是备而不用）。新增纯模型 `model/SessionSearch.ets`（18 条断言）+ 中枢 `searchSessions` + 视图扁平结果区；功能接线门禁新增第 19 项；真机判据新增 D23 |
| v1.30 | 2026-09-15 | **E214 用户实测三报：设置页三处真缺陷**。① **「配置」全部点不动**：`SettingsModels` 的候选提供方那一行点「配置」把 `expandedProvider` 设成 `g.title`，而展开判定比的是**提供方 id**，且候选**不在** `providerGroups()` 循环里 ⇒ 点了什么都不会发生；改为按 id 展开，展开体与提供方卡片**共用同一个** `providerEditor`。② **模型列表重复**：底部「各提供方的模型（点选设为新会话默认）」与提供方展开里的模型目录是同一份 `g.models`、同样语义 ⇒ 删掉底部那份（E213「先搬后拆」的"拆"），语义提示搬进 `providerEditor`。③ **「插件」与「插件清单」功能重复**：端侧只有一份投影 ⇒ 合并为一个「插件」分区（过滤框 + 可安装性徽标 + 两段说明），撤掉 `settings.plugin-inventory`（矩阵该行改判 PARTIAL 并登记）。另修一类**真机"点不动"的物理原因**：只挂 `.onClick` 的 `Text` 命中区只有那几行字，新增 `actionLabel` 统一 44vp（`Sz.TOUCH_MIN`）｜
| v1.29 | 2026-09-15 | **P5-7 剪贴板与平台层的零消费者收口（E370）**：`hdsh-clipboard` 登记册上写着"**不允许挂着不动**"，本轮逐个拍板 —— 删掉 `readText`（应用没有主动读剪贴板的需求：用户粘贴走**系统文本域自己的**菜单；程序化读要么声明 `READ_PASTEBOARD` 与"不申请特殊权限"冲突，要么用安全控件 `PasteButton` —— 它不能自由改样式、被截断就不授权，工具行在 360vp 手机上已经很挤）与 `clearClipboard`（注释写着"含凭据的复制后清理"，但全仓没有复制凭据的入口，复核三处 `copyText` 均不含凭据）。同时把**只写不读**的窗口台账接上：`runtimeFacts()` 接进诊断报告（窗口数 / 标签 / 运行时长 / runtimeId）—— D1 §7.7.5b 要的"窗口数 >1 且只有一条连接"这条证据此前在应用里取不出来。死代码门禁规则⑤扫描面 **appstate → appstate + platform**（两层都是自研机制；`connection`/`dshcompat`/`Wire.ets` 是上游协议词汇表，不扫）| 
| v1.28 | 2026-09-15 | **P5-6 插件启停的文本层搬出来并补上测试（E369）**：`serializeUserRows` / `parseUserRows` 是「启停能不能活过重启」的唯一契约（入口脚本把该文件**原样**拼进 `cordis.patch.yml`），却**一行测试都没有** —— `check-plugin-toggle.mjs` 自己手写那段 YAML，走的是入口脚本那一侧。测不了的原因是 `PluginRows.ets` 依赖三个 `@kit.*`。⇒ 文本层搬进**零依赖**的 `core/PluginRowsText.ets`，`PluginRows.ets` 只留文件 I/O 并原样再导出（对外面不变）。fixture **601 → 621 条**：输出形状 / **往返不变式**（`parse(serialize(rows))` 逐条相同且 `ignored === 0`）/ 容错计数 / `disabled` fail-closed 取值 / 文件名与入口脚本一致。顺手改掉 `hostruntime/Index.ets` 头部"核心切换/回滚尚未实现"的过期描述。另**登记未动**：`appstate` 之外的零消费者导出实测 **40 个** |
| v1.27 | 2026-09-15 | **P5-5 零消费者导出清理（E368）**：把"有没有消费者"的量法换到**导出符号**上（全仓出现 ≤2 次 = 只有声明 + barrel）。一次清掉 **25 个**：`speakable` / `sessionSubtitle` / `toolStateIsProblem` / `LARGE_OUTPUT_BYTES` / `ConnectionBanner` / 6 个 `SETTINGS_*` 常量（设置分区 id 的真值在 `PanelRegistry` 的字面量里）/ `emptyPanelList` / `PanelList` / `InAppNotice` / `modifierLabel` / `MODIFIER_LABEL` / `breakpointThresholds` / `shortcutBindingLabel` / `HarmonyMaterial` / `harmonyTokenFor` / `sessionListPayload` / `projectSettingsGroups`。三个"有意保留"写 `dead-exempt:`：`shortcutsForDesktop`（帮助浮层未做）/ `keyEventSpecs`（按键判定走 KeyCode）/ `WEB_TOKEN_MAP`（文档化数据）。**量法的三个坑**（都实测过）：语料必须含 `tools/`（否则误报 19 处）、`model/Wire.ets` 整文件排除（协议词汇表）、必须剥注释（几个符号的"引用"只在注释散文里）。死代码门禁 4 → **5 条判定**，规则⑤对当前树归真命中 5 处后清零；新增审计 `tools/audit-zero-consumer-exports.mjs`；顺带删掉 `ToolCard.diffOf` 里永远走不到的那三行 |
| v1.26 | 2026-09-15 | **P5-4 门面字段"读点"成为第 4 条死代码规则（E367）**：`export interface *Facade` 的声明与读者在子组件、实现在宿主 ⇒ 只数"本文件出现几次"的前三条规则**看不见它**。新规则整仓数 `.字段`，搜不到即"通道有、没消费者"。当场命中 2 条真死通道：`TabContentFacade.setConfirmingDeletePath` / `.setSelection`（真值另有写者：两步确认在宿主、模型选择走 `SessionHub.selectSessionModel`）⇒ 残留的重复通道，已删。规则先对**修前的工作树**归真命中 2 处，另配 4 条注入式自检。`Index.ets` 4059 → **4053 行** |
| v1.25 | 2026-09-15 | **P5-3 双栏的「展开侧栏」是死按钮（E366）**：`buildDouble` 调的是 `navRail()`，那份 surface 把侧栏呈现**硬编码**成 `TrackPresentation.RAIL` ⇒ 双栏下点「展开侧栏」什么都不发生（偏好变了、纯函数判定也变了，只有那个绘制侧栏的调用点没问判定），D19 第 2 条在真机上必然失败。删掉 `navRail()`（与 `sidePanelSurface` 逐字段相同、只差呈现的手抄版），双栏改调 `navPanel()`。`check-feature-wiring` 新增**反面规则**（`AppShell.ets` 不许出现 `TrackPresentation.RAIL`，先剥注释再匹配），并**对修前的 `HEAD` 版本归真命中 `AppShell.ets:228`** —— 正面计数拦不住"多了一个不该有的东西"。`AppShell` 420 → **397 行** |
| v1.24 | 2026-09-15 | **P5-2 侧栏轨道的几何跟随实际呈现（E365）**：P2-15 让侧栏能收起，但只改了*呈现* ——轨道宽度仍按**形态默认**算 ⇒ 三栏收起后照样占 240vp（"腾出宽度"没发生）、双栏收起后是 240vp 轨道里放 56vp rail。新增纯函数 `sidebarTrackWidthOf(mode, stored)`（panel 240 / rail 56 / 浮层 0），`SidebarShell` 的 rail 宽度改用 `Sz.NAV_RAIL`并删掉 `navWidthVp` prop 与门面字段；`sidebarExpandedOf(stored)` → **`sidebarExpandedForMode(mode, stored)`**（"没存过"必须按形态给默认，否则双栏首启被读成展开、与 `shellTracksOf(DOUBLE).sidebar = RAIL` 矛盾）；偏好搬出 `NavigationState`（删 `sidebarExpanded` / `setSidebarExpanded`，真值只剩页面里那份原始 `boolean \| undefined`）；删 `sidebarOccupiesLayout`（与"宽度 > 0"同一个问题、且只有 fixture 在用）。fixture 595 → **601**；真机判据补进 D19 |
| v1.23 | 2026-09-15 | **P5-1 核心页投影搬进 appstate（E364）**：`pluginInventoryFact` / `corePluginRows` 是**纯投影**（宿主报告 → 事实与行），却住在 `Index.ets` 里。搬迁时撞上 ArkTS **禁止结构化类型**（`HostPluginReport` 与同形状接口不可互赋，两处调用点报红）⇒ 接口降级为"参数分组"、调用点逐字段取值（`appstate` 不反向依赖 `hostruntime`）。新增 `CoreProjection.ets`（0 UI 依赖）：`pluginInventoryFact` / `pluginRowOf` / `rankPluginRows`（只排序不隐藏，且返回新数组）。fixture 577 → **595**；设计令牌棘轮 23/9 → **21/8**；`Index.ets` 4061 → **4027 行** |
| v1.22 | 2026-09-15 | **P2-17 侧栏收起状态落盘（E363）**：照抄详情栏宽度记忆那一套（`LocalPrefs` + 启动读回 + 变更落盘），并处理三态 —— `KEY_SIDEBAR_EXPANDED` 存 `'true'`/`'false'` 字符串、缺失即 `undefined`（否则"从没设置过"会被读成"收起"，用户第一次启动只看到一条 rail）；默认值放纯模型 `sidebarExpandedOf`（fixture +3 → **577**）。落盘失败**不弹提示**（与宽度记忆**有意不同**：没有信息损失）|
| v1.21 | 2026-09-15 | **P2-16 「新建会话」补到 rail 与底部标签（E362）**：该一级入口此前只在 `panelBody`（PANEL 呈现）里⇒ 三栏收起侧栏、或单栏走底部标签时**都开不了新会话**（只能靠空态按钮或 Ctrl+N）。rail 里排在「展开侧栏」下面、底部标签排第一位（都用本仓已在用的 `plus_circle`）；`onNewSession()` 调用点 1 → **3 处**，并修正组件头部那句"只在品牌行下方"的口径 |
| v1.20 | 2026-09-15 | **P2-15 侧栏可收起（E361）**：`NavigationState.sidebarExpanded` 长期无控制点 ⇒ 官方「收起侧栏腾出宽度」在本仓**做不到**（功能缺口，非字段冗余）；新增纯函数 `sidebarPresentationOf(mode, expanded)`（单栏一律浮层；双栏默认 rail、可展开；三栏默认 panel、可收起），品牌行加「收起」、rail 顶部加「展开」（**双向门**）。fixture 567 → **574**；功能接线门禁 17 → **18** |
| v1.19 | 2026-09-15 | **P2-14 删掉"只有 fixture 在用"的浮层状态机（E360）**：`NavigationState.activeOverlay` / `Overlay` / `openOverlay` / `closeOverlay` 在 `entry` 侧 **0 引用**（真实浮层优先级由 `Index.overlayState()` 从六个布尔派生），而 fixture 里有 3 条断言**只测它自己**（自证循环）。已删除；fixture 570 → **567**（少的是自证断言，不是回归）。同清单里 `sidebarExpanded` 是下一个同类候选（**需先定产品语义**，登记未动）|
| v1.18 | 2026-09-15 | **P2-13 单栏 Sheet 的右栏切换器（E359）**：切换器此前只画在 `framedBody`，单栏详情 Sheet（`sheetBody`）没有它 ⇒ **手机用户根本切不到别的右栏面板**（功能不可达级别）。抽成共用 `@Builder panelSwitcher()` 两处都调；顺手换掉那句对文件/预览/详情**措辞是错的**固定提示。P3 的另两个缺口（滑入动画 / 拖拽调宽）仍留待真机。`RightbarShell` 444 → 461 行 |
| v1.17 | 2026-09-15 | **P2-12 第二步：门面接线（E358）**：`RightbarShell` 的 12 个内容 props 收成 `f: RightbarFacade`（组件内 39 处用法改 `this.f.X`）；`AppShellFacade` 的 11 个 `right*` 成员全删；两处挂载点都调`Index.buildRightbarFacade()`（浮层此前是内联重算）。`Index.ets` 4019 → 4026（**+7，收益在"只有一个真值"而不在行数**） |
| v1.16 | 2026-09-15 | **P2-12 第一步：右侧内容门面定义（E357）** —— 拆 `detailSheet` 时发现真问题不是那 36 行，而是 `RightbarShell` 的**两个挂载点各自拼 16 个 props**（真右栏经 `AppShellFacade`、详情浮层在页面根内联重算）⇒ 迟早不同步。本轮只做 `export interface RightbarFacade`（12 个共有成员），**接线留到下一轮**。行数不变（4019）；记录 ArkTS `arkts-no-misplaced-imports` 与类型重复导入两个坑 |
| v1.15 | 2026-09-15 | **P2-11 凭据浮层 + 选项浮层（E356）**：`CredentialSheet`（127 行）/ `ChoiceSheet`（99 行）成组件；`sheetContent` 的六个分支现在各是一句组件调用。`Index.ets` **4133 → 4019 行**（P2-9…P2-11 四刀合计 4480 → 4019）。死代码门禁连续抓出搬迁残留的四批导入 |
| v1.14 | 2026-09-15 | **P2-10 两个设置编辑浮层（E355）**：`SettingTextSheet`（131 行）/ `SettingStructSheet`（142 行）成组件，输入提示进零依赖的 `model/SettingEditors.ets`（fixture +12 → **570 条**）；两处重复的"当前值占位"合并为 `placeholderOf`。`Index.ets` **4297 → 4133 行**（P2-9/P2-10 合计 4480 → 4133） |
| v1.13 | 2026-09-15 | **P2-9 `Index.ets` 第一刀（E354）**：沙箱文件夹选择器拆成 `view/FolderPicker.ets`（297 行，4 状态 + 6 方法 + 1 段 UI），`Index.ets` **4480 → 4297 行**；打开它的两个入口用**控制器对象**（与 `TurnViewController` 同源），且控制器上必须有 `close()` —— 原生 Sheet 关闭路径不经过组件 |
| v1.12 | 2026-09-15 | **P2-8 三个浮层共用结果出口（E353）**：凭据 / 文本设置 / 结构设置三个浮层共用 `credentialNote` 与 `credentialBusy` ⇒ **串浮层**（凭据的失败文案出现在文本编辑浮层里）与**跨浮层置忙**。修法：回执带归属（`sheetNoteOwner`，判定在零依赖的 `model/Sheets.ets`）+ 每个浮层自己的 busy；fixture 547 → **558 条**。原计划的"拆 960 行浮层"留到下一轮（修完缺陷后是零风险搬家） |
| v1.11 | 2026-09-15 | **P2-7 会话头上下文行（E352）**：补官方 `conversation.header` 的 **Workspace context / Model / 最近活动** 三项（规则在零依赖的 `model/SessionContext.ets`，fixture +14 → **547 条**）；Agent preset / Schedule / Open in App 三项**如实不做**（缺"当前会话的预设名"与协议面），留在 §6 缺口台账 |
| v1.10 | 2026-09-15 | **P2-6 第二刀：`TurnView`（E351）** —— "一个回合怎么画"整块搬出（492 行），展开集合留在子组件而按钮在父组件 ⇒ 引入**控制器对象**（与 ArkUI `Scroller` 同源）；思考块抽 `ReasoningRow` 供轨迹视图与过程分组**共用**；轨迹视图另留条目级 `flatItem` 分派（**共享卡片、不共享分派**）。`ConversationPane` 1087 → **984 行**（P2-4…P2-6 合计 1414 → 984）。死代码门禁当轮抓出 2 处搬迁残留 |
| v1.9 | 2026-09-15 | **死代码门禁 `check-dead-code.mjs`（E350）**：把"搬迁留下的壳"（零使用 import / `@Builder` / 组件成员）变成第 9 道门禁——前两轮三次手工扫出的同类缺陷（E345/E346/E346b）从此自动拦。门禁本身立刻查出 3 处真死代码（`MessageFeedback.itemId` / `MessageRow.menuHint` / `SettingsPane.settingRow`）并连带清掉级联死代码；含 9 条注入式自检 + 对修前 `SettingsPane` 归真命中 5 处 |
| v1.8 | 2026-09-15 | **P2-5 会话头抽成 `ConversationHeader`（E349）**：视图切换 / 轨迹工具栏 / 后台任务条 / 时间总览 / 会话内搜索条四块 chrome 整块搬出（284 行），`ConversationPane` 1234 → **1093 行**；`stats` 改为必需 prop（不造"全 0 默认统计"）。记录该类脚本化编辑的**第五次事故与三条硬规则**（不混用整块替换与局部再改 / 编辑后先 grep 锚点 / 报错里出现自己的占位符先怀疑文件被改坏） |
| v1.7 | 2026-09-15 | **P2-4 消息行抽成 `MessageRow`（E348）**：会话正文组件里"一行的事"（悬停 / 长按与右键同一个菜单 / 行内动作条 / 反馈表单 / 输入策略三判定）整块搬出（221 行），`ConversationPane` 1414 → **1234 行**；顺带删掉视图层与模型 `formatClock` 重复的 `clockOf`。记录该类脚本化搬迁的**第四次事故与处置**（结束锚用了块内也出现的字符串 ⇒ 多删 4 个成员，按花括号配平从备份取回） |
| v1.6 | 2026-09-15 | **P4-6 设置域收口 + 回执按域归属（E347）**：核心段拆成 `SettingsCore`（78 行）；写入回执带归属域（`settingsWriteDomain`），并修掉「7 个工作区/会话函数把回执写进设置通道 ⇒ 用户看不到」这个真缺陷；域判定搬进零依赖的 `model/SettingsDomains.ets` ⇒ fixture 514 → **533 条**。`SettingsPane` **500 行**（1890 → 500） |
| v1.5 | 2026-09-15 | **P4-5 设置域收口**：技能段 / 预设段拆成 `SettingsSkills`（95 行）/ `SettingsPresets`（271 行），`SettingsPane` 758 → **497 行**（P4-1…P4-5 合计 1890 → 497）；同时清掉 **16 个零消费者成员**（搬迁后宿主那段唯一的读者、已住进域组件的临时态、以及 `settingsStates` 这条从 `HubSnapshot` 到 `SettingsPane.states` 的**死链**）。据此校准 §3.1 基线（feature-wiring 111 文件） |
| v1.4 | 2026-09-15 | **真机崩溃修复（E343）**：Mate 70 Pro+ 冷启后点一下界面即 `RangeError: Stack overflow!` 被杀进程——根因是 `MainShell.mainContent` 的兜底分支 `else { this.mainContent(this.compact) }`（自递归）。修复=兜底改为渲染 `TabContentView({ f: this.f.tabFacade })`（主区剩下的工作区/核心/设置三类面板本来归它）；新增门禁 `tools/check-builder-recursion.mjs`（剥注释扫 `this.<自己>(`，5 条注入式自检 + **对修前提交归真命中**）；`check-feature-wiring` 16 → **17 个功能**（新增「主区兜底」）。据此校准 §3.1 基线（arch-check 75 文件 / feature-wiring 109 文件 & 17 功能） |
| v1.3 | 2026-09-14 | **`entry`（UI 层）获得真编译验证**：定位并修复「仓库缺一个从未入库的源码文件」事故（`.gitignore` 裸 `runtime/` 规则吞掉模块源码目录，commit `ff6cbc9` + `b906e13`）⇒ `default@CompileArkTS` BUILD SUCCESSFUL（0 error / 32 warn），全量 `devecocli build` 打通到 `PackageHap`（产出 138 MB unsigned HAP，含两 ABI 的 `libdshhost.so`），只剩签名（证书在 Windows 那台机器上）。新增 **§3.3 不入库产物清单**（源码 vs 产物分开讲，避免把"缺源码"误判成"缺产物"）；记录两处新能力：UI 层单模块快编命令、`PackageHap` 可跑 |
| v1.2 | 2026-09-14 | **P1 第一刀：`LayoutController` 落地**（`appstate/ui/LayoutController.ets`，形态/几何决策与让步链的唯一落点，被真编译器验证）+ **`tools/check-layout-fixtures.mjs`**（纯逻辑按 TS 编译后本机执行，四形态/边界/让步链 28 条断言，含自检与真实注入验证）。据此更新 `layout` 行与缺口；**新增硬事实**：`entry` 不只是没有编译器——**codelinter 检不出语法错误**（注入实测），故 `entry/src/main/ets/**` 目前**零自动验证**，已写进 §3 |
| v1.1 | 2026-09-14 | **工具链就位后校准 §3**：HAR 模块可真编译（BUILD SUCCESSFUL）、codelinter 全量可跑且**覆盖面经注入测试证明**、`check compat` 确认 Linux 永不支持、`entry` 因原生构建无编译验证。新增 §3.2 编译器首批发现——其中 `READ_PASTEBOARD` 缺失是**真实缺口**，据此把 `hdsh-clipboard` 由 `DONE` 降为 `PARTIAL`（编译器纠正了本矩阵）。补记 Linux 构建会重写 5 个 lock 文件行尾的环境坑 |
| v1.0 | 2026-09-14 | 首版：建立四形态口径（更正 PC 与 2-in-1 同为 `deviceType=2in1`）、状态口径与两轴规则、46 行对等矩阵、缺口登记、来源与版本标注、门禁 `check-parity.mjs`、附 A `Index.ets` 拆分基线 |
