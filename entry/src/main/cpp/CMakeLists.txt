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

# libnode.so.127 是**预编译**产物（自建 Node，见 tools/node-runtime/），这里只链接不重编。
# 用绝对路径链接：链接器会按它的 SONAME 记 NEEDED，所以 HAP 里必须同时带上这个文件。
# 文件名不能改：`libdshhost.so` 的 NEEDED 就是 `libnode.so.127`。
target_link_libraries(dshhost PUBLIC
    ${NATIVE_ROOT}/../../../libs/arm64-v8a/libnode.so.127)
