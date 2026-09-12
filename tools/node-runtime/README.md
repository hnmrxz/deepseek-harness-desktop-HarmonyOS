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
```

产物在 `~/node-<ver>/out/Release/`：`libnode.so.<n>` 与 `node`。
脚本最后会对两者做 ELF 检查（Class/Machine/Type）并**打印签名段**：
- 有 `.codesign` → 可以直接进 HAP
- 只有 `.note.ohos.ident` → **还不算已签名**，需要用 `binary-sign-tool` 或
  `ohos-bst-light` 的 `self-sign.py` 补签（参见 D6 §4.2 R4）

## 已知风险（写在这里，避免"以为已经成功"）

1. **`--shared` 在 OpenHarmony 上是官方"未测试"路径**（Node 文档只保证 Linux/macOS/Windows/AIX）。
   `node.gyp` 里 ohos 的 shared 分支虽已接线，但没人验证过 —— 这次构建就是去证实或证伪它。
2. 交叉编译需要 `CC_host`/`CXX_host`（脚本用系统 gcc/g++），且 OHOS clang 要带 `-fno-emulated-tls`。
3. 构建本身只证明"能编译出产物"；**产物能否被 HAP 加载、能否起 Host，必须上设备才算数**。
4. 未签名或签名不匹配的 `.so` 在商用鸿蒙上会被拦（XPM），所以签名是**验收项**而不是收尾工作。
