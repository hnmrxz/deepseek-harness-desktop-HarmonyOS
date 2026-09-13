cmake_minimum_required(VERSION 3.5.0)
project(hdshprobe)

set(CMAKE_CXX_STANDARD 17)

# 最小探针模块：不依赖 Node 头文件、不链接 libnode。
#
# 【为什么先做这个小的】实测结论（D6 E25–E29）：我们手工把预编译的
# `libdshhost.so` 放进 `entry/libs/arm64-v8a/`，运行时**会 dlopen 它、构造器会执行**，
# 但 `napi_module_register` 注册的模块**从未被实例化**（`Init` 不被调用），
# ArkTS 侧拿到的是 ArkUI 的节点模块。名种名字口径、`nm_filename`、声明位置都已排除。
# 剩下最可疑的一环是：**这个项目的原生模块映射是不是只有走 CMake 由 hvigor 构建时才生成**。
# 用一个不依赖任何东西的最小模块来单独验证这一环，成本最低、结论最干净。
add_library(entryprobe SHARED probe.cpp)
target_link_libraries(entryprobe PUBLIC libace_napi.z.so)
