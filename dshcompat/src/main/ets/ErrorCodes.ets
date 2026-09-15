/**
 * 上游**错误码**的具名常量（P7-19，零依赖）。
 *
 * ## 为什么它必须住在这里
 *
 * 上游有一张权威表：`dsh-api-session-controller/lib/typert.host.js` 的 `RemoteErrorDetailsMap`
 * （**46 个码**，每个码还带自己的 details 形状）。而本仓的架构红线是"**上游字面量只允许出现在
 * `dshcompat`**"（`tools/arch-check.mjs` 强制）——我第一版把码直接写进了
 * `appstate/model/FailureText.ets` 的文案表里，门禁当场判红（40 处）。这是它该做的事：
 * 码是上游事实，文案才是我们的产品选择，两者分住两层。
 *
 * ## 为什么只列 39 个（不是 46）
 *
 * 这 39 个是**本仓界面真会撞上**的（逐个对照我们的调用点：会话 / 网关 / 设置 / 凭据 /
 * 模型目录 / 工作区 / 工作区文件 / 目录选择器 / 代理预设）。剩下 8 个是 `subagent/*`
 * （`not-found` / `not-resumable` / `unauthorized` / `catalog-diagnostic` / `delivery-unavailable` /
 * `parent-unavailable` / `projections-unavailable` / `invalid-time-zone` 族）——
 * 本仓没有子代理续跑与授权界面，写八句用不上的文案是自欺。**将来接子代理时再加**，
 * 加的地方就是这里。
 */
/** `session/not-found` */
export const ERR_SESSION_NOT_FOUND: string = 'session/not-found';
/** `session/conflict` */
export const ERR_SESSION_CONFLICT: string = 'session/conflict';
/** `session/agent-busy` */
export const ERR_SESSION_AGENT_BUSY: string = 'session/agent-busy';
/** `session/model-unavailable` */
export const ERR_SESSION_MODEL_UNAVAILABLE: string = 'session/model-unavailable';
/** `session/workspace-attach-failed` */
export const ERR_SESSION_WORKSPACE_ATTACH_FAILED: string = 'session/workspace-attach-failed';
/** `session/invalid-time-zone` */
export const ERR_SESSION_INVALID_TIME_ZONE: string = 'session/invalid-time-zone';
/** `session/title-invalid` */
export const ERR_SESSION_TITLE_INVALID: string = 'session/title-invalid';
/** `session/fork-unavailable` */
export const ERR_SESSION_FORK_UNAVAILABLE: string = 'session/fork-unavailable';
/** `session/attachment-invalid` */
export const ERR_SESSION_ATTACHMENT_INVALID: string = 'session/attachment-invalid';
/** `session/queue-item-not-found` */
export const ERR_SESSION_QUEUE_ITEM_NOT_FOUND: string = 'session/queue-item-not-found';
/** `session/steer-unavailable` */
export const ERR_SESSION_STEER_UNAVAILABLE: string = 'session/steer-unavailable';
/** `gateway/bad-request` */
export const ERR_GATEWAY_BAD_REQUEST: string = 'gateway/bad-request';
/** `gateway/arguments-invalid` */
export const ERR_GATEWAY_ARGUMENTS_INVALID: string = 'gateway/arguments-invalid';
/** `gateway/input-invalid` */
export const ERR_GATEWAY_INPUT_INVALID: string = 'gateway/input-invalid';
/** `gateway/cancelled` */
export const ERR_GATEWAY_CANCELLED: string = 'gateway/cancelled';
/** `gateway/internal` */
export const ERR_GATEWAY_INTERNAL: string = 'gateway/internal';
/** `settings/rejected` */
export const ERR_SETTINGS_REJECTED: string = 'settings/rejected';
/** `settings/conflict` */
export const ERR_SETTINGS_CONFLICT: string = 'settings/conflict';
/** `credential/rejected` */
export const ERR_CREDENTIAL_REJECTED: string = 'credential/rejected';
/** `llm/model-discovery-rejected` */
export const ERR_LLM_MODEL_DISCOVERY_REJECTED: string = 'llm/model-discovery-rejected';
/** `workspace/not-found` */
export const ERR_WORKSPACE_NOT_FOUND: string = 'workspace/not-found';
/** `workspace/invalid-path` */
export const ERR_WORKSPACE_INVALID_PATH: string = 'workspace/invalid-path';
/** `workspace/name-conflict` */
export const ERR_WORKSPACE_NAME_CONFLICT: string = 'workspace/name-conflict';
/** `workspace/move-invalid` */
export const ERR_WORKSPACE_MOVE_INVALID: string = 'workspace/move-invalid';
/** `workspace-file/not-found` */
export const ERR_WORKSPACE_FILE_NOT_FOUND: string = 'workspace-file/not-found';
/** `workspace-file/outside-workspace` */
export const ERR_WORKSPACE_FILE_OUTSIDE_WORKSPACE: string = 'workspace-file/outside-workspace';
/** `workspace-file/too-large` */
export const ERR_WORKSPACE_FILE_TOO_LARGE: string = 'workspace-file/too-large';
/** `workspace-file/not-text` */
export const ERR_WORKSPACE_FILE_NOT_TEXT: string = 'workspace-file/not-text';
/** `workspace-file/not-regular-file` */
export const ERR_WORKSPACE_FILE_NOT_REGULAR_FILE: string = 'workspace-file/not-regular-file';
/** `workspace-file/not-directory` */
export const ERR_WORKSPACE_FILE_NOT_DIRECTORY: string = 'workspace-file/not-directory';
/** `directory-picker/unavailable` */
export const ERR_DIRECTORY_PICKER_UNAVAILABLE: string = 'directory-picker/unavailable';
/** `directory-picker/unreadable` */
export const ERR_DIRECTORY_PICKER_UNREADABLE: string = 'directory-picker/unreadable';
/** `directory-picker/exists` */
export const ERR_DIRECTORY_PICKER_EXISTS: string = 'directory-picker/exists';
/** `directory-picker/create-failed` */
export const ERR_DIRECTORY_PICKER_CREATE_FAILED: string = 'directory-picker/create-failed';
/** `agent-preset/not-found` */
export const ERR_AGENT_PRESET_NOT_FOUND: string = 'agent-preset/not-found';
/** `agent-preset/invalid` */
export const ERR_AGENT_PRESET_INVALID: string = 'agent-preset/invalid';
/** `agent-preset/read-only` */
export const ERR_AGENT_PRESET_READ_ONLY: string = 'agent-preset/read-only';
/** `agent-preset/locked` */
export const ERR_AGENT_PRESET_LOCKED: string = 'agent-preset/locked';
/** `agent-preset/conflict` */
export const ERR_AGENT_PRESET_CONFLICT: string = 'agent-preset/conflict';

/**
 * 上表全部码的清单（供"可达集合"对账用；顺序与声明顺序一致）。
 *
 * 【为什么要一个数组】文案表那边需要遍历它做对账（"可达集合里每个码都得有专门文案"），
 * 而 ArkTS 禁止在运行时枚举对象键（`Object.keys` 等被 `arkts-no-func-apply-call` 一系规则挡住）
 * ⇒ 键集必须在**声明处**物化成数组（与 `RemoteEvents.KNOWN_EVENT_TYPES` 同一手法）。
 */
export const REACHABLE_ERROR_CODES: string[] = [
  ERR_SESSION_NOT_FOUND,
  ERR_SESSION_CONFLICT,
  ERR_SESSION_AGENT_BUSY,
  ERR_SESSION_MODEL_UNAVAILABLE,
  ERR_SESSION_WORKSPACE_ATTACH_FAILED,
  ERR_SESSION_INVALID_TIME_ZONE,
  ERR_SESSION_TITLE_INVALID,
  ERR_SESSION_FORK_UNAVAILABLE,
  ERR_SESSION_ATTACHMENT_INVALID,
  ERR_SESSION_QUEUE_ITEM_NOT_FOUND,
  ERR_SESSION_STEER_UNAVAILABLE,
  ERR_GATEWAY_BAD_REQUEST,
  ERR_GATEWAY_ARGUMENTS_INVALID,
  ERR_GATEWAY_INPUT_INVALID,
  ERR_GATEWAY_CANCELLED,
  ERR_GATEWAY_INTERNAL,
  ERR_SETTINGS_REJECTED,
  ERR_SETTINGS_CONFLICT,
  ERR_CREDENTIAL_REJECTED,
  ERR_LLM_MODEL_DISCOVERY_REJECTED,
  ERR_WORKSPACE_NOT_FOUND,
  ERR_WORKSPACE_INVALID_PATH,
  ERR_WORKSPACE_NAME_CONFLICT,
  ERR_WORKSPACE_MOVE_INVALID,
  ERR_WORKSPACE_FILE_NOT_FOUND,
  ERR_WORKSPACE_FILE_OUTSIDE_WORKSPACE,
  ERR_WORKSPACE_FILE_TOO_LARGE,
  ERR_WORKSPACE_FILE_NOT_TEXT,
  ERR_WORKSPACE_FILE_NOT_REGULAR_FILE,
  ERR_WORKSPACE_FILE_NOT_DIRECTORY,
  ERR_DIRECTORY_PICKER_UNAVAILABLE,
  ERR_DIRECTORY_PICKER_UNREADABLE,
  ERR_DIRECTORY_PICKER_EXISTS,
  ERR_DIRECTORY_PICKER_CREATE_FAILED,
  ERR_AGENT_PRESET_NOT_FOUND,
  ERR_AGENT_PRESET_INVALID,
  ERR_AGENT_PRESET_READ_ONLY,
  ERR_AGENT_PRESET_LOCKED,
  ERR_AGENT_PRESET_CONFLICT
];
