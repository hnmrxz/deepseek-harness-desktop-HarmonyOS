/**
 * HAR 模块：DSH 上游兼容面（dshcompat）。
 *
 * **这是整个工程里唯一允许出现 DSH 上游接口细节的地方。**
 *
 * 分层：
 *   connection（机制）  ← 注入 ProtocolSurface ←  dshcompat（上游事实）  →  appstate / UI
 *
 * 上游升级流程（三条命令 + 一次判定）：
 *   1. node tools/protocol-contract.mjs --json .research/protocol/contracts.json
 *   2. node tools/gen-compat-endpoints.mjs          # 重新生成端点上表
 *   3. node tools/compat-drift.mjs                  # 门禁：有漂移则非零退出并给出精确差异
 *   4. 按漂移报告的处置步骤更新能力映射与受支持版本矩阵，并回写 D2 §8 附录
 *
 * 因此上游变更**只改动本模块**（生成物 + 能力映射 + 版本矩阵），
 * connection / appstate / UI 均无需改动。
 */

// 端点上表与能力表（自动生成）
export { DSH_CAPABILITIES, DSH_ENDPOINTS, UPSTREAM_IDENTITY } from './Endpoints';

// 兼容面类型
export { ArgsShape, EndpointProbe } from './CompatTypes';
export type {
  CapabilityState,
  DshCapability,
  DshEndpoint,
  FieldAliases,
  ProbeTable,
  UpstreamIdentity
} from './CompatTypes';

// 解析逻辑
export {
  allCapabilityIds,
  buildArgs,
  capabilityOf,
  checkVersion,
  emptyProbeTable,
  endpointOf,
  evaluateCapability,
  probeArgs,
  tableStats,
  supportedVersionsText,
  upstreamCapturedAt,
  upstreamIdentity,
  VersionVerdict
} from './CompatIndex';
export type { TableStats, VersionCheck } from './CompatIndex';

// 上游接口面（注入给 connection）
export { SURFACE } from './Surface';

// 字段别名表与常用 endpoint（投影层不再硬编码字段名与端点字面量）
export {
  argsFor,
  COMMANDS_EXECUTE_ENDPOINT,
  COMMANDS_LIST_ENDPOINT,
  FILE_REFERENCES_LIST_ENDPOINT,
  SESSION_REFERENCE_CANDIDATES_ENDPOINT,
  CREDENTIALS_DESCRIBE_ENDPOINT,
  CREDENTIALS_SET_ENDPOINT,
  CREDENTIALS_UNSET_ENDPOINT,
  demoTraceLines,
  FIELD_ALIASES,
  FILE_UPLOAD_ENDPOINT,
  GATEWAY_ARGUMENTS_INVALID,
  GATEWAY_INPUT_INVALID,
  GATEWAY_SIGNATURE_INVALID,
  GOALS_GET_ENDPOINT,
  hasParamAliases,
  MODEL_CATALOG_ENDPOINT,
  PARAM_ALIASES,
  PLUGIN_INVENTORY_ENDPOINT,
  READONLY_PROBE_ENDPOINTS,
  rebuildWithLegacyNames,
  SESSION_CANCEL_ENDPOINT,
  SESSION_CONTROL_ENDPOINT,
  SESSION_CREATE_ENDPOINT,
  SESSION_FEEDBACK_RECORD_ENDPOINT,
  SESSION_FOLLOW_ENDPOINT,
  SESSION_FORK_ENDPOINT,
  SESSION_LIST_ENDPOINT,
  SESSION_PROMPT_ENDPOINT,
  SESSION_RENAME_ENDPOINT,
  SESSION_UPDATE_QUEUE_ENDPOINT,
  sessionListArgs,
  SETTINGS_CONFLICT,
  SETTINGS_DESCRIBE_ENDPOINT,
  SETTINGS_MUTATE_ENDPOINT,
  SETTINGS_REJECTED,
  CREDENTIAL_REJECTED,
  WORKSPACE_FILES_CHANGES_ENDPOINT,
  WORKSPACE_FILES_LIST_ENDPOINT,
  WORKSPACE_FILES_READ_ALL_ENDPOINT,
  WORKSPACE_FILES_READ_ENDPOINT,
  WORKSPACE_FILES_STAT_ENDPOINT
} from './Aliases';
export type { ParamAlias } from './Aliases';

// 转发事件白名单、瀑布调用词汇、投影键（审批/提问这条核心链路的全部上游事实）
export {
  APPROVAL_ALLOWED_ONCE,
  APPROVAL_CANCELLED,
  APPROVAL_OUTCOMES,
  APPROVAL_REJECTED,
  APPROVAL_UNAVAILABLE,
  EVENT_COMMANDS_CHANGE,
  EVENT_CREDENTIALS_REFERENCE_UPDATED,
  EVENT_GOAL_ACTIVATION_CHANGED,
  EVENT_LLM_ADAPTERS_UPDATED,
  EVENT_PREFIX_SESSION_TITLE,
  EVENT_PREFIX_TURN,
  EVENT_SESSION_ACTIVITY,
  EVENT_SESSION_ADDED,
  EVENT_SESSION_ERROR,
  EVENT_SESSION_REMOVED,
  EVENT_SESSION_STATUS,
  EVENT_SETTINGS_DOCUMENT_UPDATED,
  EVENT_TURN_END,
  AUDIT_EVENT_TYPES,
  classifyEventType,
  EventFamily,
  isAuditEventType,
  isKnownEventType,
  KNOWN_EVENT_TYPE_COUNT,
  isUserAuthoredEvent,
  FORWARDED_EVENTS,
  ForwardedEventMode,
  forwardedModeOf,
  isForwardedEvent,
  isSessionListEvent,
  isWaterfallEvent,
  mayChangeSessionTitle,
  mayChangeTurnState,
  PROJECTION_AGENT_PRESET,
  PROJECTION_INBOX,
  PROJECTION_TITLE,
  RemoteEventFrameType,
  titleFromProjections,
  WATERFALL_APPROVAL,
  WATERFALL_QUESTION
} from './RemoteEvents';
export type { ForwardedEvent } from './RemoteEvents';

// 会话事件的**形状表**（字段取值路径 + 内容槽位；实测事实的唯一来源）
export {
  ContentSlot,
  eventShapeOf,
  familyIsStandalone,
  isMeasuredEventType,
  MEASURED_EVENT_TYPE_COUNT,
  SESSION_EVENT_SHAPES,
  slotBinding
} from './EventShape';export type { SessionEventShape, SlotBinding } from './EventShape';
