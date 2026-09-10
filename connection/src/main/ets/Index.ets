/**
 * HAR 模块：dsh 协议兼容层。
 *
 * 这是 D1 §6.1 中「协议兼容层」的唯一对外入口。上层（状态层 / UI / 设备接入层）
 * 只应通过本文件导入，不得深层导入 src/main/ets/protocol/*。
 */

export { Connection, randomUuid, serializeCookies, deserializeCookies } from './protocol/Connection';
export type { ConnectionOptions, CookiePersistence } from './protocol/Connection';

export {
  API_CHANNEL,
  EVENTS_ENDPOINT,
  EVENTS_RESULT_ENDPOINT,
  REMOTE_MUX_PATH,
  EMPTY_ARGS_PAYLOAD,
  RemoteFailure,
  rpcFail,
  rpcOk,
  checkTarget,
  endpointOf
} from './protocol/RpcTypes';
export type { RpcResult } from './protocol/RpcTypes';

export { parseHostAddress, parseTarget, extractStartupUrl, extractToken } from './protocol/HostAddress';
export type { HostAddress, ParsedTarget } from './protocol/HostAddress';

export {
  CookieJar,
  parseCookieString,
  parseSetCookieHeader
} from './protocol/Cookies';

export { buildClientRequest, parseConnectionResponse, peekResponseOk } from './protocol/Envelope';

export { HttpClient } from './protocol/HttpClient';
export type { HttpOutcome } from './protocol/HttpClient';

export { AuthSession, isAuthFailureStatus, isTrustFailureStatus } from './protocol/AuthSession';
export type { AuthOutcome } from './protocol/AuthSession';

export { RemoteMux, MuxState } from './protocol/RemoteMux';

export { EventStream, EventStreamPhase } from './protocol/EventStream';

export { BACKOFF_STEPS_MS, backoffDelayMs, isRetryable, ReconnectController } from './protocol/Backoff';

export {
  getArray,
  getBoolean,
  getField,
  getNumber,
  getRecord,
  getString,
  isRecord,
  isStringArray,
  parseJson,
  stringifyJson,
  toStringArray
} from './protocol/JsonValue';

export { ConnectionState } from './protocol/Types';
export type {
  CallOptions,
  CookieRecord,
  DiagnosticItem,
  DiagnosticReport,
  EventSink,
  HostConfig,
  HostFacts,
  RetryProgress,
  StreamSink
} from './protocol/Types';
