/**
 * 端侧核心运行层对外出口。
 *
 * 当前已实现（可单测的纯逻辑 + 文件系统实现）：
 *   - Types      ：核心仓库的状态与**激活/回滚/清理判据**（纯函数）
 *   - Naming     ：容器名与版本目录名的规则与安全校验（纯函数）
 *   - CoreStore  ：解包落位、状态读写、激活事务、回滚、清理
 *
 * 尚未实现（下一步，见 docs/50-端侧核心运行架构.md §2/§6.2）：
 *   - DshHost    ：核心生命周期（准备 → 起 → 健康检查 → ready → 停/重启）
 *   - RuntimePort：运行时载体（阶段一 Electron-on-鸿蒙 / 阶段二 libnode.so）
 *   - Plugins    ：插件清单与纯 JS / 原生插件的分类与启停
 * 这些在实现前不导出，避免上层以为已经可用。
 */

export * from './core/Types';
export * from './core/Naming';
export * from './core/CoreStore';
