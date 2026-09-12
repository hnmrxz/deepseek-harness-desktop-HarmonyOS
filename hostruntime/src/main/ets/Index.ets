/**
 * 端侧核心运行层对外出口。
 *
 * 已实现（可单测的纯逻辑 + 文件系统实现 + 载体抽象）：
 *   - Types      ：核心仓库的状态与**激活/回滚/清理判据**（纯函数）
 *   - Naming     ：容器名与版本目录名的规则与安全校验（纯函数）
 *   - CoreStore  ：解包落位、状态读写、激活事务、回滚、清理
 *   - RuntimePort：运行时载体接口 + 「未接线」实现（如实报告未接线，不伪装）
 *   - DshHost    ：运行状态机（未接线/未安装/待启动/就绪/失败…），起停核心
 *
 * 尚未实现（下一步）：
 *   - 阶段一的 Electron-on-鸿蒙 载体实现（等华为侧产物）
 *   - 阶段二的 libnode.so 载体实现（等自建交叉编译产物，见 tools/node-runtime/）
 *   - Plugins    ：插件清单与纯 JS / 原生插件的分类与启停
 * 在实现前不导出，避免上层以为已经可用。
 */

export * from './core/Types';
export * from './core/Naming';
export * from './core/CoreStore';
export * from './runtime/RuntimePort';
export * from './runtime/DshHost';
