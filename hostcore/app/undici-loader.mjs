/**
 * 模块解析钩子：把 `undici` 指到本仓的垫片。
 * 状态：**已实现、钩子行为已验证（`import("undici")` 会拿到本仓垫片），但尚未接线**。
 *
 * 【为什么用解析钩子而不是改代码】上游 `import("undici")` 是它自己的实现选择；
 * 端侧的差异应该由**运行期组合**表达（本项目的一贯边界：不改上游源码、不改核心树）。
 * Node 20.6+ 的 `module.register` 允许在进程内注册解析钩子，于是：
 *   `import("undici")` → `hostcore/app/undici-shim.js`
 * 只影响**这一次解析**，核心树文件一个字节都不动。
 *
 * 生效条件由入口脚本判断：只有在 `WebAssembly` 不可用（`--jitless`）时才注册——
 * 原生 undici 能用时不该被替换（它的连接池与协议实现比垫片完整得多）。
 */
const SHIM_URL = new URL('./undici-shim.js', import.meta.url).href;

export async function resolve(specifier, context, next) {
  if (specifier === 'undici') {
    return { url: SHIM_URL, shortCircuit: true, format: 'module' };
  }
  return next(specifier, context);
}
