/**
 * 端侧运行时宿主（RuntimeHost）—— 唯一负责"把 Node 起起来"的界面元素（D6 §4.1.2）。
 *
 * ────────────────────────────────────────────────────────────────────────
 * 为什么启动 Node 需要**一个界面元素**：
 *   华为 Electron-on-鸿蒙 运行时的启动入口是 native 侧的 `runBrowser(argv)`，
 *   而它在 ArkTS 侧**只能**从组件生命周期触达——
 *   `WebWindow` 内部的 `XComponent.onLoad` 回调里才调用它。
 *   也就是说：**没有 XComponent 表面，就没有 Node**。
 *   这不是我们的设计选择，是运行时的既有形状（源码精读结论，见 D6 §4.1.2）。
 *
 * 为什么是 1×1 且保持可渲染（而不是 0 尺寸 / Visibility.None）：
 *   `onLoad` 只有在表面**真正创建**之后才会触发。把尺寸设成 0 或把可见性设成
 *   None 都可能让系统跳过表面创建，症状是"页面正常、日志里什么都没有、Node 永远不启动"
 *   ——这类静默失败比崩溃难查得多。因此这里用一个极小的、仍然渲染的方块，
 *   并用 `hitTestBehavior(None)` 保证它不吃触摸事件。
 *
 * 为什么**绝不能**销毁它：
 *   表面一没，native 运行时随之结束。所以本组件必须常驻，
 *   页面切页签/重建时要保证它不被卸载（挂在根 Stack 上、不参与条件分支）。
 * ────────────────────────────────────────────────────────────────────────
 */

import { WebWindow } from 'web_engine';

@Component
export struct RuntimeHost {
  build() {
    Stack() {
      WebWindow()
    }
    .width(1)
    .height(1)
    .position({ x: 0, y: 0 })
    // 不吃触摸：它贴在左上角，必须让手势穿透到下面的真实 UI
    .hitTestBehavior(HitTestMode.None)
    // 保持"可渲染"：不要用 Visibility.None —— 见文件头说明
    .opacity(0.01)
  }
}
