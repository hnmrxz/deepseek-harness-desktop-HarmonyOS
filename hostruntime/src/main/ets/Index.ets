/**
 * 端侧核心运行层对外出口。
 *
 * 已实现（可单测的纯逻辑 + 文件系统实现 + 载体抽象）：
 *   - Types      ：核心仓库的状态与**激活/回滚/清理判据**（纯函数）
 *   - Naming     ：容器名与版本目录名的规则与安全校验（纯函数）
 *   - CoreStore  ：解包落位、状态读写、激活事务、回滚、清理
 *   - BundledCore：把 resfile 里内置的核心容器落地（首启安装；幂等）
 *   - RuntimePort：运行时载体接口 + 「未接线」实现（如实报告未接线，不伪装）
 *   - DshHost    ：运行状态机（未接线/未安装/待启动/就绪/失败…），起停核心
 *   - Plugins    ：插件清单与「纯 JS / 依赖原生」分类——**清单来自树内元数据**
 *                  （打包器写入，端侧只读一个小 JSON，不遍历 27000 余文件）。
 *                  已能如实回答"这一版装了什么、哪些装不了"；
 *                  **启停/安装插件尚未实现**（需要 Host 起得来才能改 profile 生效）。
 *
 * 尚未实现（下一步）：
 *   - 阶段一的 Electron-on-鸿蒙 载体实现（等华为侧产物）
 *   - 阶段二的 libnode.so 载体实现（等自建交叉编译产物，见 tools/node-runtime/）
 *   - 插件的启用/停用/安装动作（只读清单已经真实，动作没有假入口）
 * 在实现前不导出，避免上层以为已经可用。
 */

export * from './core/Types';
export * from './core/Naming';
export * from './core/CoreStore';
export * from './core/BundledCore';
export * from './runtime/RuntimePort';
export * from './runtime/DshHost';
