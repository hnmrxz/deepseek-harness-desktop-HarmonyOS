/**
 * 图片附件的**协议形状**（零依赖）。
 *
 * 出处：上游 `@deepseek-ai/dsh-attachment/lib/types/types.d.ts` 的 `ImageAttachmentRef`。
 *
 * 【为什么单独一个文件，而不是放在 `Wire.ets` 里】
 *   `Wire.ets` 是"线上载荷的读法"，它 import 不了任何东西就要保持可测；而**轨迹条目**
 *   （`Trajectory.ets`）也要携带这个类型（`TrajectoryItem.images`）。
 *   早先把接口放在 `Wire.ets` 里，于是 `Trajectory.ets` → `Wire.ets` 的依赖把轨迹模型
 *   拖进了"必须连协议层一起编译"的处境——`tools/check-layout-fixtures.mjs` 只编译纯逻辑文件，
 *   实测直接崩在 `Cannot find module './Wire'`。
 *   把它抽成零依赖文件后，协议层与呈现层各自引用同一份**字面形状**，谁都不用依赖谁。
 *
 * 【它与 `FileAttachmentRefValue` 是两个接口，不能合并】图片比文件多三件事：
 * `mediaType`（渲染 `data:` URL 必需）、`width`/`height`（官方按它们算缩略尺寸）。
 * 合并成一个"什么都有"的接口会让"这到底是不是图片"变成运行期猜测。
 */

/** 图片附件引用（内容寻址；**不是**路径、也不是带授权的 URL） */
export interface ImageAttachmentRefValue {
  /** 内容寻址 id：**就是这些字节的 sha256** */
  attachmentId: string;
  /** 由**存储字节**验证过的媒体类型（`image/png` 等；'' = 没拿到） */
  mediaType: string;
  /** 精确字节数（0 = 未知） */
  bytes: number;
  /** 编码后的固有宽度（像素；0 = 未知） */
  width: number;
  /** 编码后的固有高度（像素；0 = 未知） */
  height: number;
  /** 可选展示名（已剥离本地路径；'' = 没有） */
  name: string;
}
