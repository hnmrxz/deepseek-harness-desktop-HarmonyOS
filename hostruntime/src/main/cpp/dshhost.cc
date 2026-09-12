// dshhost —— 端侧 Node 运行时的 NAPI 引导模块（阶段二）
//
// 角色：把 libnode.so 里的 Node 在同一进程内起起来，供 ArkTS 侧调用。
// 它**只做引导**，不做协议、不碰 dsh：dsh 的 Host 由 Node 侧脚本
// （hostcore/app/main.js）在 loopback 上起，ArkTS 仍按既有 HTTP/WS 协议说话。
// 这样"运行时载体"换了，上面的客户端一行都不用改。
//
// 为什么同进程而不是 fork/exec：
//   鸿蒙手机**禁止三方应用 fork/创建进程**（D6 E15，childProcessManager 仅平板/PC-2in1）。
//   同进程加载 libnode.so 是四条形态唯一共同可行的路径。
//
// 已知边界（不要以为已经解决）：
//   1. **无法从外部线程安全停止进程内 Node**。node::Start 是阻塞的，唯一的正路是在
//      Node 线程内部持一个 uv_async 句柄并调用 node::Stop(env)。那需要先拿到 env，
//      属于下一步；现在 stopHost() 如实返回"做不到"，不假装成功。
//   2. node::Start 会走 uv_setup_args 并尝试确定 process.execPath。鸿蒙沙箱下
//      /proc/self/exe 未必可用，process.execPath 可能为空——**必须上设备验证**。
//   3. libnode.so 必须随 HAP 打包且已签名（D6 E14），热更新的 .so 会被系统拦截。
//   4. 本项目统一 jitless（不申请 ALLOW_WRITABLE_CODE_MEMORY），因此 argv 里必须带
//      --jitless；否则 V8 会在初始化时申请可写可执行内存而被拦。
//
// 编译验证：`bash tools/node-runtime/build-dshhost.sh --compile-only`
//   （只编译不链接，因此不需要 libnode.so 存在）

#include <node_api.h>
#include <node.h>
#include <node_version.h>

#include <atomic>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

namespace {

// Node 线程与它的 argv。argv 必须活到线程结束，所以放静态存储。
std::thread g_nodeThread;
std::atomic<bool> g_running{false};
std::atomic<bool> g_started{false};
std::vector<std::string> g_argStore;
std::vector<char*> g_argv;

void SetString(napi_env env, napi_value obj, const char* key, const std::string& value) {
  napi_value v = nullptr;
  napi_create_string_utf8(env, value.c_str(), value.length(), &v);
  napi_set_named_property(env, obj, key, v);
}

void SetBool(napi_env env, napi_value obj, const char* key, bool value) {
  napi_value v = nullptr;
  napi_get_boolean(env, value, &v);
  napi_set_named_property(env, obj, key, v);
}

/**
 * runtimeVersion(): 返回编译进 libnode.so 的 Node 版本。
 * 只要这个函数返回了非空字符串，就证明"模块加载成功且与 libnode 链接在一起了"——
 * 这是端侧"运行时是否真的可用"的第一条可观测证据（第二条是 Host 真的起来）。
 */
napi_value RuntimeVersion(napi_env env, napi_callback_info info) {
  napi_value out = nullptr;
  napi_create_string_utf8(env, NODE_VERSION_STRING, NAPI_AUTO_LENGTH, &out);
  return out;
}

/**
 * startHost(argv: string[], envPairs: string[]): { started: boolean, note: string }
 *
 * 在独立线程里跑 node::Start（阻塞）。**同一个进程只能起一次**：第二次调用返回
 * started=false 并说明原因，而不是偷偷再起一个（那样会有两个 Host 抢同一个端口）。
 *
 * 【为什么需要 envPairs】端侧 Host 的配置通道**是环境变量，不是 argv**：
 * hostcore/app/main.js 读的是 HDSH_CORE_DIR / HDSH_HOME / HDSH_SANDBOX_HOME /
 * HDSH_PORT / HDSH_PROFILE，而 ArkTS 侧**没有任何办法设置原生进程的环境变量**。
 * 所以必须由这里在 node::Start 之前 setenv()。
 * 取"KEY=VALUE"字符串数组而不是两个平行数组：无需在两端各自维护下标对应关系，
 * 少一类"键值错位"的错法（键值错位会静默把 Host 指向错误的目录）。
 */
napi_value StartHost(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  napi_value out = nullptr;
  napi_create_object(env, &out);

  if (g_started.load()) {
    SetBool(env, out, "started", false);
    SetString(env, out, "note", "运行时已经启动过；同一进程只允许一个 Node 实例");
    return out;
  }

  // argv：第 0 位是程序名（node::Start 要求），其余由 ArkTS 侧给出。
  g_argStore.clear();
  g_argStore.emplace_back("node");
  uint32_t len = 0;
  if (argc >= 1 && napi_get_array_length(env, args[0], &len) == napi_ok) {
    for (uint32_t i = 0; i < len; i++) {
      napi_value el = nullptr;
      if (napi_get_element(env, args[0], i, &el) != napi_ok) {
        continue;
      }
      size_t n = 0;
      if (napi_get_value_string_utf8(env, el, nullptr, 0, &n) != napi_ok) {
        continue;  // 非字符串项直接跳过，不猜
      }
      std::string s(n, '\0');
      napi_get_value_string_utf8(env, el, &s[0], n + 1, &n);
      g_argStore.push_back(s);
    }
  }

  // 环境变量：必须在 node::Start 之前生效——Node 启动时就会读 process.env 初始化，
  // 之后再 setenv 对已启动的 Host 没有任何作用。
  uint32_t envCount = 0;
  int envBad = 0;
  if (argc >= 2 && napi_get_array_length(env, args[1], &envCount) == napi_ok) {
    for (uint32_t i = 0; i < envCount; i++) {
      napi_value el = nullptr;
      if (napi_get_element(env, args[1], i, &el) != napi_ok) {
        continue;
      }
      size_t n = 0;
      if (napi_get_value_string_utf8(env, el, nullptr, 0, &n) != napi_ok) {
        continue;
      }
      std::string pair(n, '\0');
      napi_get_value_string_utf8(env, el, &pair[0], n + 1, &n);
      const size_t eq = pair.find('=');
      if (eq == std::string::npos || eq == 0) {
        envBad++;  // 没有 "=" 或键为空：不猜，计数后如实报告
        continue;
      }
      setenv(pair.substr(0, eq).c_str(), pair.substr(eq + 1).c_str(), 1);
    }
  }

  g_argv.clear();
  for (std::string& s : g_argStore) {
    g_argv.push_back(&s[0]);
  }

  g_started.store(true);
  g_running.store(true);
  g_nodeThread = std::thread([]() {
    int rc = node::Start(static_cast<int>(g_argv.size()), g_argv.data());
    g_running.store(false);
    // 只记录退出码；调用方通过 isHostRunning() 观察到"不跑了"。
    // 不在这里做任何恢复动作：静默重启会把"Host 崩了"伪装成"还好好的"。
    (void)rc;
  });

  SetBool(env, out, "started", true);
  napi_value applied = nullptr;
  napi_create_uint32(env, envCount - static_cast<uint32_t>(envBad), &applied);
  napi_set_named_property(env, out, "envApplied", applied);
  // 环境变量格式不对必须说出来：静默忽略会让 Host 用上默认目录，
  // 表面上"起来了"，实际指向了错的 $DSH_HOME。
  SetString(env, out, "note",
            envBad > 0
                ? ("Node 线程已启动，但有 " + std::to_string(envBad) +
                   " 条环境变量格式不合法（缺少 KEY=）已被忽略")
                : "Node 线程已启动（node::Start 阻塞运行）");
  return out;
}

napi_value IsHostRunning(napi_env env, napi_callback_info info) {
  napi_value out = nullptr;
  napi_get_boolean(env, g_running.load(), &out);
  return out;
}

/**
 * stopHost(): { ok: boolean, note: string }
 *
 * **如实返回做不到**。进程内 Node 无法从外部线程安全停止：node::Start 阻塞，
 * 唯一正路是在 Node 线程内持 uv_async 并调用 node::Stop(env)。在拿到 env 之前，
 * 假装停成功会让上层以为核心已经停了（而它还在监听回环端口）——那比报错更糟。
 */
napi_value StopHost(napi_env env, napi_callback_info info) {
  napi_value out = nullptr;
  napi_create_object(env, &out);
  SetBool(env, out, "ok", false);
  SetString(env, out, "note",
            "进程内 Node 暂不支持从外部线程停止（需在 Node 线程内用 uv_async + node::Stop）。"
            "当前只能随应用退出而结束。");
  return out;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"runtimeVersion", nullptr, RuntimeVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"startHost", nullptr, StartHost, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"isHostRunning", nullptr, IsHostRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stopHost", nullptr, StopHost, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}

napi_module g_dshHostModule = {
    1,          // nm_version
    0,          // nm_flags
    nullptr,    // nm_filename
    Init,       // nm_register_func
    "dshhost",  // nm_modname：ArkTS 侧 `import dshhost from 'libdshhost.so'`
    nullptr,    // nm_priv
    {nullptr},  // reserved
};

}  // namespace

// 模块注册：OHOS 的 NAPI 也是靠 constructor 把模块挂上去的（与 Node 原生模块一致）。
extern "C" __attribute__((constructor)) void RegisterDshHostModule() {
  napi_module_register(&g_dshHostModule);
}
