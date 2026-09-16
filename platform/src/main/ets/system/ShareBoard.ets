/**
 * 系统分享面板机制封装（Share Kit）。
 *
 * 用途（D3 §5.2 长按消息 → 分享）：把会话内容或交付物交给系统分享面板，
 * 由用户选择目标应用。不自己造分享 UI——系统面板在手机/折叠/2in1 上有各自
 * 正确的形态（模态 / 对话框 / 悬浮窗锚点），自造会做不对。
 *
 * 内容纪律（D3 §6 同源）：分享内容由调用方决定；本文件不读取、不拼装会话内容。
 */

import { systemShare } from '@kit.ShareKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD5A1;
const TAG: string = 'platform/share';

/**
 * 把**沙箱内的绝对路径**分享成"文件本体"（P9-7）。
 *
 * 【为什么必须转 URI】系统分享面板的 `SharedRecord` 要么给 `content`（文本）、要么给 `uri`；
 * SDK 文档逐字："method to obtain the file URI from the sandbox path. Either **content** or
 * **uri** must be set." ⇒ 文件只能经 `fileUri.getUriFromPath()` 换成一个系统可授权的 URI，
 * 接收方才能打开它（直接给沙箱路径字符串对方读不到）。
 *
 * 【沙箱外的路径会失败】`getUriFromPath` 只认应用沙箱内的路径；工作区若是用户经系统选择器
 * 挑的沙箱外目录，调用会抛 —— 调用方据此**降级为分享路径文本**（判定在
 * `appstate/model/ProducedFiles.deliverableShareTarget`，不是在这里猜）。
 *
 * @returns 面板是否成功拉起（失败时调用方要给一句可读的回执）
 */
export async function shareFile(context: common.UIAbilityContext, absPath: string,
  title?: string, anchorId?: string): Promise<boolean> {
  try {
    const uri: string = fileUri.getUriFromPath(absPath);
    const record: systemShare.SharedRecord = {
      // `general.file`：SDK 的 `UniformDataType.FILE`（没有 GENERAL_FILE 这个名字）
      utd: utd.UniformDataType.FILE,
      uri: uri
    };
    if (title !== undefined && title.length > 0) {
      record.title = title;
    }
    const data: systemShare.SharedData = new systemShare.SharedData(record);
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    const options: systemShare.ShareControllerOptions = {};
    if (anchorId !== undefined && anchorId.length > 0) {
      options.anchor = anchorId;
    }
    await controller.show(context, options);
    return true;
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'shareFile failed: %{public}s', e.message);
    return false;
  }
}

/** 一次分享请求的文本内容 */
export interface ShareText {
  content: string;
  title?: string;
  description?: string;
  /** 是否按超链接类型分享（内容为 URL 时设 true，系统会匹配浏览器等目标） */
  asLink?: boolean;
}

/**
 * 弹出系统分享面板分享文本。
 *
 * @param context UIAbility 上下文（2in1/平板下系统需要它决定面板以悬浮窗还是模态展示）
 * @param text 分享内容
 * @param anchorId 可选：面板锚点组件的 id（2in1 上让面板贴着触发它的按钮弹出）
 * @returns 面板是否成功拉起
 */
export async function shareText(context: common.UIAbilityContext, text: ShareText,
  anchorId?: string): Promise<boolean> {
  try {
    const record: systemShare.SharedRecord = {
      utd: text.asLink === true ? utd.UniformDataType.HYPERLINK : utd.UniformDataType.PLAIN_TEXT,
      content: text.content
    };
    if (text.title !== undefined) {
      record.title = text.title;
    }
    if (text.description !== undefined) {
      record.description = text.description;
    }
    const data: systemShare.SharedData = new systemShare.SharedData(record);
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    const options: systemShare.ShareControllerOptions = {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    };
    if (anchorId !== undefined && anchorId.length > 0) {
      options.anchor = anchorId;
    }
    await controller.show(context, options);
    return true;
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'share panel failed: %{public}s', e.message);
    return false;
  }
}
