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
  upstreamIdentity,
  VersionVerdict
} from './CompatIndex';
export type { TableStats, VersionCheck } from './CompatIndex';

// 上游接口面（注入给 connection）
export { SURFACE } from './Surface';

// 字段别名表与常用 endpoint（投影层不再硬编码字段名与端点字面量）
export {
  argsFor,
  CREDENTIALS_DESCRIBE_ENDPOINT,
  FIELD_ALIASES,
  MODEL_CATALOG_ENDPOINT,
  PLUGIN_INVENTORY_ENDPOINT,
  READONLY_PROBE_ENDPOINTS,
  SESSION_CONTROL_ENDPOINT,
  SESSION_CREATE_ENDPOINT,
  SESSION_FOLLOW_ENDPOINT,
  SESSION_LIST_ENDPOINT,
  SESSION_PROMPT_ENDPOINT,
  sessionListArgs,
  SETTINGS_DESCRIBE_ENDPOINT
} from './Aliases';
