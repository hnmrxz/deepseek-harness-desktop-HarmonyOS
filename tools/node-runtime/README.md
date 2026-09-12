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

# 构建中断后原地续跑（会把真实退出码写进日志尾，便于判定成败）
bash tools/node-runtime/resume-make.sh
```

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

关于第二条的取舍（**写清楚，免得以后被当成"漏了一个优化"**）：
zlib 会退回可移植 C 的 CRC32。**正确性不变**，只影响 gzip CRC 吞吐；
在端侧推理/网络延迟占主导的场景里这不是关键路径，而换来的是不再依赖
一个 OHOS clang 尚未支持的函数级 target 属性、也不再需要 hwcap 探测。
要恢复它，得把该目标的 CPU 基线整体抬到 `armv8-a+crc+aes`，代价与收益不匹配。

> 注意：Node 生成的 `Makefile` **没有** `GYPFILES` 规则，所以**改 `.gyp` 不会自动重生成 makefile**。
> `fix-zlib-crc32.sh` 因此同时改 `out/**/*.target.mk` 并删掉旧对象——旧的 `zlib.o`
> 命令行里带 `-DCRC32_ARMV8_CRC32`，不删就会在链接期留下对 `armv8_crc32_little` 的引用。

## 已知风险（写在这里，避免"以为已经成功"）

1. **`--shared` 在 OpenHarmony 上是官方"未测试"路径**（Node 文档只保证 Linux/macOS/Windows/AIX）。
   `node.gyp` 里 ohos 的 shared 分支虽已接线，但没人验证过 —— 这次构建就是去证实或证伪它。
2. 交叉编译需要 `CC_host`/`CXX_host`（脚本用系统 gcc/g++），且 OHOS clang 要带 `-fno-emulated-tls`。
3. 构建本身只证明"能编译出产物"；**产物能否被 HAP 加载、能否起 Host，必须上设备才算数**。
4. 未签名或签名不匹配的 `.so` 在商用鸿蒙上会被拦（XPM），所以签名是**验收项**而不是收尾工作。
