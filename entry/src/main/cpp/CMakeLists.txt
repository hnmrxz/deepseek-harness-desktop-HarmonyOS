cmake_minimum_required(VERSION 3.5.0)
project(hdshnative)

set(CMAKE_CXX_STANDARD 17)

# ── 为什么这里有 CMake（D6 E30 的结论）────────────────────────────────────────
#
# 实测（同进程、相隔几毫秒的并列对照）：
#   HDSH-PROBE  cmake 构建的原生模块可绑定，返回值=hdsh-probe-ok   ← 走 hvigor 的 CMake 路径
#   HDSH-RUNTIME runtimeVersion is undefined                       ← 手工拷进 entry/libs/
# ⇒ **本项目里"手工放预编译 .so"不会生成 ArkTS↔原生模块的映射**：运行时会 dlopen 它、
#   构造器会执行，但 `napi_module_register` 注册的模块**永远不会被实例化**（`Init` 不被调用）。
#   所以 `libdshhost.so` 必须由 hvigor 自己编译链接，而不是我们编好再拷进去。
#
# 代价：CMake 需要 Node 的头文件，由 `tools/node-runtime/sync-node-headers.sh` 同步到
# `node-headers/`（**已 gitignore**：几十 MB 的三方头文件，字节不进库、方法进库）。

set(NATIVE_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
# cpp → main → src → entry → 仓库根；`entry/libs` 是上溯三级
set(REPO_ROOT ${NATIVE_ROOT}/../../../..)
set(ENTRY_LIBS ${NATIVE_ROOT}/../../../libs)

# 1) 最小探针模块：回答"CMake 路径能否绑定"（见 probe.cpp 与 E30），保留它作为回归证据。
add_library(entryprobe SHARED probe.cpp)
target_link_libraries(entryprobe PUBLIC libace_napi.z.so)

# 2) 真正的引导模块：dshhost（源码在 hostruntime 里，那一层才是它的归属）。
add_library(dshhost SHARED
    ${NATIVE_ROOT}/../../../../hostruntime/src/main/cpp/dshhost.cc)

target_include_directories(dshhost PRIVATE
    ${NATIVE_ROOT}/node-headers/src
    ${NATIVE_ROOT}/node-headers/v8include
    ${NATIVE_ROOT}/node-headers/uvinclude)

# -fno-emulated-tls / -D__MUSL__：与交叉编译 libnode.so.127 时用的口径保持一致。
# TLS 模型不一致时，与 libnode 的交互会出现难以定位的问题，所以两端必须同口径。
target_compile_options(dshhost PRIVATE -fno-emulated-tls -D__MUSL__)
set_target_properties(dshhost PROPERTIES LINK_FLAGS "-fno-emulated-tls")

target_link_libraries(dshhost PUBLIC libace_napi.z.so)

# 诊断日志用 OH_LOG_Print（应用进程的 stdout 在设备上看不见，见 D6 E23）。
# 独立编译时用 -lhilog_ndk.z，CMake 里要显式列出来，否则 --no-undefined 会直接报 undefined symbol。
target_link_libraries(dshhost PUBLIC hilog_ndk.z)

# libnode.so.127 是**预编译**产物（自建 Node，见 tools/node-runtime/）。
#
# 【为什么**不**链接它，而是运行期 dlopen】见 dshhost.cc 构造函数里的说明：
# 若写进 DT_NEEDED，动态加载器会先以**局部作用域**把它载入，之后原生模块（koffi/node-pty/sharp）
# 就解析不到 `napi_*` 符号——musl 不支持事后把已载入的库提升为全局（实测：dlopen 带 RTLD_GLOBAL
# 返回 ok，符号依然 not found）。所以改为在构造函数里**首次** dlopen 并带 RTLD_GLOBAL，
# 并用 dlsym 取 `node::Start`（mangled 名 `_ZN4node5StartEiPPc`）。
# 代价：链接期不再校验 libnode —— 这是**有意的**取舍，换来 `.node` 能加载。

# ── koffi 3.x（自建；见 D6 E47 / E50）────────────────────────────────────────
#
# 【为什么自建】dsh 全线声明 `koffi ^3.1.0`，而鸿蒙侧只有 `@ohos-ports/koffi@2.16.2-beta.0`：
# 2.x 的 `koffi.struct(...).size` 是 undefined ⇒ `dsh-win32-process` 的**模块顶层**断言抛错
# ⇒ `subprocess-local` / `sandbox-local` 加载失败（整棵树 fail-loud）。上游 3.x 的分平台包
# 没有 openharmony 变体，其 musl 预编译的 DT_NEEDED 是 libstdc++.so.6 / libc.musl-aarch64.so.1
# ——鸿蒙都不提供。所以只能自己编。
#
# 【为什么编在这里】hvigor 已经有可用的 OHOS CMake/ninja 工具链，并且天然按 ABI（arm64-v8a /
# x86_64）各编一份、按 `lib<target>.so` 打进 HAP 的 `libs/`。目标名取 `koffi` ⇒ 产出
# `libs/<abi>/libkoffi.so`，正好命中入口脚本的原生库重定向约定（`lib<stem>.so`，D6 E40）。
#
# 源码由 `node tools/fetch-koffi.mjs` 取到 `third_party/koffi/`（**已 gitignore**）。
# 取不到就只 warn 不失败：缺 koffi 只影响 subprocess/sandbox 两行，不该让整个 HAP 编不出来。
enable_language(ASM)

set(KOFFI_DIR ${REPO_ROOT}/third_party/koffi)
if(EXISTS ${KOFFI_DIR}/package/src/koffi/CMakeLists.txt)
  set(KOFFI_SRC ${KOFFI_DIR}/package/src/koffi)
  set(KOFFI_CXX
      ${KOFFI_SRC}/src/ffi.cc
      ${KOFFI_SRC}/src/call.cc
      ${KOFFI_SRC}/src/interp.cc
      ${KOFFI_SRC}/src/parser.cc
      ${KOFFI_SRC}/src/type.cc
      ${KOFFI_SRC}/src/util.cc
      ${KOFFI_SRC}/src/uv.cc
      ${KOFFI_SRC}/src/win32.cc
      ${KOFFI_DIR}/package/lib/native/base/base.cc)

  # 默认当 arm64（出货目标）；只有明确是 x86 才走 x64sysv，避免 CMAKE_SYSTEM_PROCESSOR
  # 在 OHOS 工具链里为空时**静默编错架构**（这种错误要到运行时才暴露）
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64|X86_64" OR OHOS_ARCH MATCHES "x86")
    set(KOFFI_TARGET x86_64)
    list(APPEND KOFFI_CXX ${KOFFI_SRC}/src/abi/x64sysv.cc)
    set(KOFFI_ASM ${KOFFI_SRC}/src/abi/x64sysv_asm.S)
    set(HDSH_LIBNODE ${ENTRY_LIBS}/x86_64/libnode.so.127)
  else()
    set(KOFFI_TARGET arm64)
    list(APPEND KOFFI_CXX ${KOFFI_SRC}/src/abi/arm64.cc)
    set(KOFFI_ASM ${KOFFI_SRC}/src/abi/arm64_asm.S)
    set(HDSH_LIBNODE ${ENTRY_LIBS}/arm64-v8a/libnode.so.127)
  endif()

  # 【为什么"没有 libnode 就不编 koffi"】koffi 的 napi_*/uv_* 必须靠 DT_NEEDED 放进
  # 它自己的依赖闭包（E43：libnode 即便 RTLD_GLOBAL 首载也不进它的可见集）。
  # 而 OHOS 工具链默认带 `-Wl,--no-undefined` ⇒ 拿不到 libnode 时链接必然失败。
  # 与其放宽成"允许未定义符号"（那会产出运行时必崩的 .node），不如**这个 ABI 先不产**：
  # x86_64 的 libnode 一进 entry/libs/x86_64/，这里就会自动开始编。
  if(NOT EXISTS ${HDSH_LIBNODE})
    message(WARNING "koffi(${KOFFI_TARGET}) 跳过：缺 ${HDSH_LIBNODE}（DT_NEEDED 必须有它）。"
                    "先出该架构的 libnode.so.127，或到模拟器上临时禁用 subprocess/sandbox 两行")
  else()
    add_library(koffi MODULE ${KOFFI_CXX} ${KOFFI_ASM})
    set_target_properties(koffi PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)
    target_include_directories(koffi PRIVATE
        ${KOFFI_SRC}
        ${KOFFI_DIR}/package
        ${KOFFI_DIR}/package/vendor/node-addon-api
        ${KOFFI_DIR}/package/vendor/node-api-headers/include
        ${KOFFI_DIR}/trampolines
        ${NATIVE_ROOT}/node-headers/src)
    # 宏与选项逐条照抄上游 src/koffi/CMakeLists.txt（NAPI 实验版是 koffi 的硬要求）
    target_compile_definitions(koffi PRIVATE
        FELIX_TARGET=koffi
        NAPI_VERSION=NAPI_VERSION_EXPERIMENTAL
        NODE_ADDON_API_DISABLE_CPP_EXCEPTIONS
        NODE_ADDON_API_REQUIRE_BASIC_FINALIZERS)
    set_source_files_properties(${KOFFI_SRC}/src/ffi.cc PROPERTIES COMPILE_DEFINITIONS VERSION=3.2.1)
    target_compile_options(koffi PRIVATE
        -fno-exceptions -fno-rtti -fwrapv
        -fno-semantic-interposition -fvisibility=hidden -fdata-sections -ffunction-sections)
    target_link_options(koffi PRIVATE -Wl,--gc-sections)
    target_link_libraries(koffi PRIVATE ${HDSH_LIBNODE})
    message(STATUS "koffi 3.2.1 编入 HAP：target=${KOFFI_TARGET} libnode=${HDSH_LIBNODE}")
  endif()
else()
  message(WARNING "未找到 koffi 源码（${KOFFI_DIR}）⇒ 本架构不带 libkoffi.so；"
                  "先跑 `node tools/fetch-koffi.mjs`")
endif()
