/**
 * HAR 模块对外入口：设备能力层。
 *
 * 分层纪律（与 `connection` / `dshcompat` / `appstate` 同一套）：
 *   本模块只提供**机制**——把 HarmonyOS 的系统能力（通知、长时任务、剪贴板、分享、
 *   窗口与形态、运行时身份）包装成中性、可注入、可降级的接口。
 *   它**不认识** DSH 上游（无端点、无事件名），也**不含产品策略**（不知道什么该通知）。
 *   策略在 `appstate`，装配在 `entry`。
 *
 * 这样分层的收益：
 *   上游升级时不碰本模块；换平台（如未来做其他 OS）时只换本模块；
 *   单元测试可在无设备环境下覆盖策略，而不必 mock 系统 API。
 */

// ── 通知 ──
export { NotificationCenter, priorityAllowsBypassDnd, stableId } from './notify/NotificationCenter';
export { NotifyPriority, NotifySlot } from './notify/NotifyTypes';
export type { NotificationDraft, NotifyFacts, NotifyRoute } from './notify/NotifyTypes';

// ── 后台保活 ──
export { KeepAlive } from './notify/KeepAlive';
export type { KeepAliveFacts } from './notify/KeepAlive';

// ── 系统能力 ──
export { clearClipboard, copyText, readText } from './system/Clipboard';
export { shareText } from './system/ShareBoard';
export type { ShareText } from './system/ShareBoard';
export { SecretLoadState, SecretStore } from './system/SecretStore';
export type { SecretLoadResult } from './system/SecretStore';
export { HostStore } from './system/HostStore';
export type { RememberedHost, RememberedToken } from './system/HostStore';
export {
  EVENT_HOST_CONNECTED,
  EVENT_KEY_HOST_TOKEN,
  EVENT_KEY_HOST_URL
} from './system/HostEvents';
export { FormFactor, readDeviceFacts } from './system/DeviceFacts';
export type { DeviceFacts } from './system/DeviceFacts';
export { MAX_ATTACHMENT_BYTES, PickOutcome, pickDocument } from './system/FilePicker';
export type { PickedFile } from './system/FilePicker';

// ── 窗口与形态 ──
export {
  currentWindowId,
  focusMainWindow,
  openRoutedWindow,
  openSessionWindow,
  parseWindowParams,
  PARAM_ROUTE,
  PARAM_SESSION_ID,
  PARAM_TITLE,
  PARAM_WINDOW_KIND,
  WindowKind
} from './window/WindowRegistry';
export type { WindowParams } from './window/WindowRegistry';
export { defaultLayoutState, WindowMemory } from './window/WindowMemory';
export type { WindowLayoutState, WindowRect } from './window/WindowMemory';

// ── 运行时身份与窗口台账（D1 §7.7.5b 的可观测证据面） ──
export { registerWindow, relabelWindow, runtimeFacts, runtimeId, unregisterWindow, windowCount } from './runtime/RuntimeSingleton';
export type { RuntimeFacts, WindowLedgerEntry } from './runtime/RuntimeSingleton';
