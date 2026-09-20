/**
 * ArkUI 全局（`Resource` 类型与 `$r()` 函数）的最小垫片（W2，2026-09-20）。
 *
 * 【为什么需要】0.1.6 升级轮里 `SessionHub.ets` 新增 `import { RunMode } from
 * '../ui/Breakpoints'`（运行模式 LOCAL/REMOTE 的枚举），而 `Breakpoints.ets` 又拉进
 * `Tokens.ets` —— 后者的 `SemanticColor` 在**类字段初始化**时就会调
 * `$r('sys.color.…')`，前者 `settingsSectionLabelRes` 的返回类型是 `Resource`。
 * 端侧这两个全局由 ArkUI 编译器注入；本机回路（tsc 把 .ets 当 .ts 编）两者都没有。
 *
 * 【口径】类型给最小形状；`$r` 运行时返回**惰性标记对象**（不参与任何断言，
 * 只是让被拉进来的模块能完成求值）——回路的断言从不看资源解析结果，
 * 真机上的资源解析由 ArkUI 自己负责。
 */
declare global {
  type Resource = { readonly hdshResourcePath: string };
  function $r(path: string): Resource;
}

const g = globalThis as unknown as Record<string, unknown>;
if (g.$r === undefined) {
  g.$r = (path: string): Resource => ({ hdshResourcePath: path });
}
export {};
