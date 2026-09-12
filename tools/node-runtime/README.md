# node-runtime —— 自建端侧 Node 运行时（阶段二的关键路径）

> 目的：产出**能被 HAP 加载的 Node 运行时**（`libnode.so`），它就是 D6 §4.2 说的"阶段二目标形态"。
> 之所以要自己做：华为侧 Electron-on-鸿蒙 的产物在 DevCloud CodeHub、需账号登录、无公开 URL；
> 而 Node 官方已支持 OpenHarmony，源在自己手里最可靠，**并且是唯一能天然满足"不申请 JIT 特殊权限"的形态**
> （自建时可用 jitless 构建；Electron 运行时的 V8 带 JIT，且其子进程方案依赖 JIT）。

## 已核实的前提（不要凭记忆改）

| 事实 | 依据 |
|---|---|
| Node 官方支持 OpenHarmony/arm64（Experimental） | Node `BUILDING.md` 平台表 |
| OHOS 支持落在 v22.17.0 / v24.4.0 / v25+ / v26+ | `common.gypi` 在 **v22.23.2 这个 tag 上**确有 `OS=="openharmony"` 分支 |
| `--dest-os` 的合法取值是 `openharmony`（**不是** `ohos`） | `configure.py` 的 `valid_os` 枚举 |
| 版本下限 = **v22.17.0** | OHOS 支持（≥22.17.0）与 `node:zlib` zstd（≥22.15）两条约束的交集；本目录默认 `v22.23.2` |
| OpenHarmony 公开 SDK（含 Linux NDK）可匿名下载 | `https://repo.huaweicloud.com/openharmony/os/6.1-Release/ohos-sdk-windows_linux-public.tar.gz`（2.33 GB） |
| 商用鸿蒙会拦未签名 ELF，且**只有 `.note.ohos.ident` 不算已签名** | 见 D6 §4.2 R4 的实测对照 |

## 用法（在 WSL2 里跑；宿主是 Windows 时 Node 的构建脚本需要 POSIX + make）

```bash
# 1) 取 SDK（约 2.3 GB，解出 native/llvm 与 native/sysroot）
bash tools/node-runtime/fetch-ohos-sdk.sh
#    可用环境变量换版本：OHOS_SDK_VER=6.0.0.2-Release bash ...

# 2) 交叉编译 Node（会等 SDK 就绪；V8 很重，预计 30~90 分钟）
bash tools/node-runtime/build-node-ohos.sh
#    换版本：NODE_VER=v24.21.0 bash ...

# 3) 看进展
bash tools/node-runtime/status.sh
#    只想看三行结论（是否在跑 / 产物有没有出现 / 日志尾）：
bash tools/node-runtime/status-brief.sh

# 构建中断后原地续跑（会清掉误用宿主编译器编出的目标对象，并把真实退出码写进日志尾）
bash tools/node-runtime/resume-make.sh

# 失败时看原因（尾部若干行 + 错误标记，逐行截断，不会刷屏）
bash tools/node-runtime/show-build-failure.sh 40 190
# 校验"目标对象是不是真的都是 AArch64"（这个数必须是 other=0）
bash tools/node-runtime/diagnose-toolchain.sh

# 查 HAP 里的原生 .so 有没有签名段、以及打包有没有改动它们
bash tools/node-runtime/check-hap-native-signing.sh
```

**已实测的结论（E18）**：构建出的 HAP 里全部 4 个 `libs/arm64-v8a/*.so`
（`libelectron` / `libadapter` / `libffmpeg` / `libc++_shared`）都**只有 `.note.ohos.ident`、
没有 `.codesign`**，且与 `entry/libs/arm64-v8a/` 下的源文件**逐字节相同**——
**我们的打包流程从不给 `.so` 签名**。HAP 自身的签名是包级的，不会回溯给内嵌 `.so`。

这直接关系到阶段二能否上架：`libnode.so` / `libdshhost.so` 也是内嵌 `.so`，
它们会不会被系统校验拒掉，**必须上设备用 `dlopen` 的错误码回答**（两种互斥解释见 D6 §4.1.9）。
若确实需要签名，那一步必须放在 **HAP 组装之前**（组装后再改包内字节会破坏 HAP 签名）。

产物在 `~/ohos/node-<ver>/out/Release/`：`libnode.so.<n>` 与 `node`。
脚本最后会对两者做 ELF 检查（Class/Machine/Type）并**打印签名段**：
- 有 `.codesign` → 可以直接进 HAP
- 只有 `.note.ohos.ident` → **还不算已签名**，需要用 `binary-sign-tool` 或
  `ohos-bst-light` 的 `self-sign.py` 补签（参见 D6 §4.2 R4）

## 必须的源码修补（已接线进 build-node-ohos.sh，在 configure 之前跑）

这两条修的是**我们自己编译 Node 时的构建配置**，与"对 dsh 上游零 patch"的纪律无关——
dsh 那边仍然一个字节都没改。

| 脚本 | 修什么 | 证据 |
|---|---|---|
| `fix-cxx-std.sh` | `common.gypi` 里 linux/openharmony 分支的 `-std=gnu++17` → `gnu++20` | `deps/ncrypto/ncrypto.cc` 用了 C++20 三路比较，报 `'operator<=' cannot be the name of a variable or data member` |
| `fix-zlib-crc32.sh` | 把 `CRC32_ARMV8_CRC32` 这个宏名整体改名，使 zlib 的 ARMv8 CRC32 SIMD 路径不参与编译 | OHOS clang 15 报 `fatal error: error in backend: Cannot select: intrinsic %llvm.aarch64.crc32b`；实测补 `-march=armv8-a+crc` 只能消掉 `crc32b`，同一函数里的内联 `pmull` 仍报 `instruction requires: aes`，因为 `+aes` 只存在于被 OHOS clang 忽略的函数级 target 属性里。详见脚本头部注释 |
| `fix-latomic.sh` | 从**目标**链接行去掉 `-latomic`（保留宿主工具的） | `node.gyp:507` 的 `['OS=="linux" and clang==1', {'libraries': ['-latomic']}]` 把 OHOS 当成了 linux，而 **OHOS SDK 没有 libatomic**（`find $SDK/native/sysroot -name '*atomic*'` 只有头文件），链接报 `ld.lld: error: unable to find library -latomic`。aarch64 的 1/2/4/8 字节原子操作由 clang 内联下发，`libatomic` 只在 16 字节原子时才需要——真需要的话链接会**响亮地**报未定义 `__atomic_*_16`，不会静默产出坏库 |

关于第二条的取舍（**写清楚，免得以后被当成"漏了一个优化"**）：
zlib 会退回可移植 C 的 CRC32。**正确性不变**，只影响 gzip CRC 吞吐；
在端侧推理/网络延迟占主导的场景里这不是关键路径，而换来的是不再依赖
一个 OHOS clang 尚未支持的函数级 target 属性、也不再需要 hwcap 探测。
要恢复它，得把该目标的 CPU 基线整体抬到 `armv8-a+crc+aes`，代价与收益不匹配。

> 注意：Node 生成的 `Makefile` **没有** `GYPFILES` 规则，所以**改 `.gyp` 不会自动重生成 makefile**。
> `fix-zlib-crc32.sh` 因此同时改 `out/**/*.target.mk` 并删掉旧对象——旧的 `zlib.o`
> 命令行里带 `-DCRC32_ARMV8_CRC32`，不删就会在链接期留下对 `armv8_crc32_little` 的引用。

## 构建期纪律：工具链环境只有一个来源（`toolchain-env.sh`）

`out/Makefile` 第 43 行是 **`CC.target ?= $(CC)`**——gyp 生成的 makefile **从环境变量取目标编译器**。
因此任何一次不带 `CC`/`CXX` 导出的 `make`，都会静默改用宿主 `cc`/`g++` 去编译 `obj.target/` 下的
**目标**对象。**编译期不报任何错**，几千个对象之后才以宿主 gcc 撞上 OHOS 专属头文件
（`asm/hwcap.h: No such file or directory`、`arm_neon.h: No such file or directory`）的形式暴露，
而那个错误看起来和"编译器选错了"毫无关系。

实测代价：一次漏导出的续跑把 **2410 个目标对象里的 1112 个**编成了 x86-64。

规矩：
- 交叉工具链的所有 export **只写在 `toolchain-env.sh`**，`build-node-ohos.sh` 与
  `resume-make.sh` 都 `source` 它。不要再在任何地方另写一份。
- 怀疑被污染就跑 `diagnose-toolchain.sh`：`other` **必须是 0**。
- `resume-make.sh` 默认（`PURGE_FOREIGN=1`）在续跑前自动删掉所有非 AArch64 的目标对象。

## NAPI 引导模块 `libdshhost.so`（阶段二：把 Node 在同进程内起起来）

源码：`hostruntime/src/main/cpp/dshhost.cc`（**它只做引导**，不做协议、不碰 dsh：
dsh 的 Host 由 Node 侧脚本在 loopback 上起，ArkTS 仍按既有 HTTP/WS 协议说话——
这样换了运行时载体，上面的客户端一行都不用改）。

```bash
# 只编译（不需要 libnode.so，可以立刻验证 C++ 对不对）
bash tools/node-runtime/build-dshhost.sh --compile-only

# 编译 + 链接（需要 out/Release/libnode.so 已经产出）
bash tools/node-runtime/build-dshhost.sh
#   产物：entry/libs/arm64-v8a/libdshhost.so（该目录已 gitignore，字节不进库、方法进库）
```

**为什么同进程而不是 fork/exec**：鸿蒙手机**禁止三方应用 fork/创建进程**
（D6 E15，`childProcessManager` 仅平板/PC-2in1）。同进程加载 `libnode.so` 是
手机 / 折叠屏 / 平板 / 2in1 四条形态唯一共同可行的路径。

**导出的接口**（ArkTS 侧 `import dshhost from 'libdshhost.so'`）：

| 成员 | 语义 |
|---|---|
| `runtimeVersion(): string` | 编译进 libnode.so 的 Node 版本。**只要它返回非空就证明"模块加载成功且与 libnode 链接在一起了"**——这是"运行时可用"的第一条可观测证据 |
| `startHost(argv: string[], envPairs: string[]): {started, note, envApplied}` | 在独立线程里跑 `node::Start`（阻塞）。**同进程只允许起一次**：第二次返回 `started=false` 并说明原因，而不是偷偷再起一个（两个 Host 会抢同一个端口） |
| `isHostRunning(): boolean` | Node 线程是否还活着 |
| `stopHost(): {ok, note}` | **如实返回做不到**，理由见下 |

**为什么 `startHost` 需要 `envPairs`（这是读入口脚本才发现的）**：端侧 Host 的配置通道
**是环境变量，不是 argv**——`hostcore/app/main.js` 读 `HDSH_CORE_DIR` / `HDSH_HOME` /
`HDSH_SANDBOX_HOME` / `HDSH_PORT` / `HDSH_PROFILE`，而 ArkTS 侧**没有任何办法设置原生进程的
环境变量**。所以必须由引导层在 `node::Start` 之前 `setenv()`。

于是"该传哪些键、argv 该带什么"成了两端之间最容易写错、且**写错了不会报错**的接口：
键名拼错 → Host 用上默认目录，表面上起来了、实际指向了错的 `$DSH_HOME`。因此这两条契约在
ArkTS 侧是**可单测的纯函数**（`hostruntime/.../RuntimePort.ets` 的 `buildHostArgv()` /
`buildHostEnv()` / `isWellFormedEnvPair()`），而不是散在实现里的字符串拼接；
`envPairs` 用 `KEY=VALUE` 字符串而非两个平行数组，少一类"键值错位"的错法。

`HDSH_*` 的取值由 `buildHostEnv()` 给出；`--jitless` 由 `buildHostArgv()` 给出且必须排在
脚本路径**之前**（Node 把第一个非选项参数当脚本，顺序反了就会去执行一个叫 `--jitless` 的东西）。

**已知边界（写清，别当成已解决）**：

1. **进程内 Node 无法从外部线程安全停止**。`node::Start` 阻塞，唯一正路是在 Node 线程
   内部持一个 `uv_async` 句柄并调用 `node::Stop(env)`；那需要先拿到 env，属于下一步。
   现在 `stopHost()` 返回 `ok:false` 而不是假装成功——假装成功会让上层以为核心停了，
   而它还在监听回环端口，那比报错更糟。
2. `node::Start` 会走 `uv_setup_args` 并尝试确定 `process.execPath`；鸿蒙沙箱下
   `/proc/self/exe` 未必可用，`process.execPath` 可能为空。**必须上设备验证**。
3. 本项目统一 jitless，因此 `argv` 里必须带 `--jitless`；否则 V8 初始化时会申请
   可写可执行内存而被系统拦（这也是不申请 `ALLOW_WRITABLE_CODE_MEMORY` 的前提）。
4. `libnode.so` 与 `libdshhost.so` 都必须随 HAP 打包且已签名（D6 E14），
   热更新的 `.so` 会被系统拦截。

**接线顺序（有依赖，不要提前做）**：`entry/oh-package.json5` 里声明 `${napi_name}.so`
依赖 + `entry/src/main/cpp/types/` 下放 `.d.ts`，这两步**必须等 `libdshhost.so` 真的链接出来之后**
再做——在此之前声明一个不存在的原生库，会让 ArkTS 侧引用到一个加载不起来的模块，
把当前可用的构建与页面一起弄坏。

## 已知风险（写在这里，避免"以为已经成功"）

1. **`--shared` 在 OpenHarmony 上是官方"未测试"路径**（Node 文档只保证 Linux/macOS/Windows/AIX）。
   `node.gyp` 里 ohos 的 shared 分支虽已接线，但没人验证过 —— 这次构建就是去证实或证伪它。
2. 交叉编译需要 `CC_host`/`CXX_host`（脚本用系统 gcc/g++），且 OHOS clang 要带 `-fno-emulated-tls`。
3. 构建本身只证明"能编译出产物"；**产物能否被 HAP 加载、能否起 Host，必须上设备才算数**。
4. 未签名或签名不匹配的 `.so` 在商用鸿蒙上会被拦（XPM），所以签名是**验收项**而不是收尾工作。
