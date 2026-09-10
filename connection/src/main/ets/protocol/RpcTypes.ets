/**
 * RPC 目标校验与信封类型定义。
 *
 * 事实基线（D2 §1.1）：
 *   - endpoint 段字符集 `^[A-Za-z0-9_$.-]+$`，以 `/` 连接，禁止空段与 `.` / `..`
 *   - channel 必须匹配 `^/[A-Za-z0-9._~-]+$`，且 `/api` 由 Gateway 认领
 *   - 一元请求体：{ type:"client-request", rpcId, method, payload }
 *   - 一元响应体：{ type:"server-response", rpcId, result }
 *   - result.ok=true  → { ok:true, value }
 *   - result.ok=false → { ok:false, error:{ code, message, details } }
 */

/** 一元 RPC 的 channel（Gateway 认领的唯一 channel） */
export const API_CHANNEL: string = '/api';

/** 事件流逻辑端点（D2 §1.3） */
export const EVENTS_ENDPOINT: string = '$events';

/** 事件 waterfall 结果回送端点（D2 §1.3） */
export const EVENTS_RESULT_ENDPOINT: string = '$events/result';

/** 逻辑流复用 WebSocket 路径（D2 §1.2） */
export const REMOTE_MUX_PATH: string = '/api/remote.mux';

/** 逻辑流开流 payload（D2 §1.3：{ args: {} }） */
export const EMPTY_ARGS_PAYLOAD: string = '{"args":{}}';

const CHANNEL_PATTERN: RegExp = /^\/[A-Za-z0-9._~-]+$/;
const ENDPOINT_SEGMENT_PATTERN: RegExp = /^[A-Za-z0-9_$.-]+$/;

/** 校验结果 */
export interface TargetCheck {
  ok: boolean;
  reason?: string;
}

/**
 * 校验 channel + endpoint 组合是否合法。
 * 与上游 `assertTarget` 语义一致：任一不合法即视为调用方错误（装配错误，非业务错误）。
 */
export function checkTarget(channel: string, endpoint: string): TargetCheck {
  if (!CHANNEL_PATTERN.test(channel)) {
    return { ok: false, reason: `invalid channel ${JSON.stringify(channel)}` };
  }
  if (channel === API_CHANNEL) {
    return { ok: false, reason: `channel ${API_CHANNEL} is reserved for the Gateway` };
  }
  if (endpoint.length === 0) {
    return { ok: false, reason: 'empty endpoint' };
  }
  const segments: string[] = endpoint.split('/');
  for (let i = 0; i < segments.length; i++) {
    const segment: string = segments[i];
    if (segment === '' || segment === '.' || segment === '..') {
      return { ok: false, reason: `invalid endpoint segment in ${JSON.stringify(endpoint)}` };
    }
    if (!ENDPOINT_SEGMENT_PATTERN.test(segment)) {
      return { ok: false, reason: `invalid endpoint segment ${JSON.stringify(segment)}` };
    }
  }
  return { ok: true };
}

/** 把 namespace + method 拼成 endpoint */
export function endpointOf(namespace: string, method: string): string {
  return `${namespace}/${method}`;
}

/** 业务/传输失败（与上游 RemoteError 对齐：code + message + details） */
export class RemoteFailure {
  code: string;
  message: string;
  details: string;
  /** 触发该失败的 HTTP 状态码（0 表示载体未获得响应）；用于区分 401/403 语义 */
  httpStatus: number = 0;

  constructor(code: string, message: string, details: string, httpStatus: number = 0) {
    this.code = code;
    this.message = message;
    this.details = details;
    this.httpStatus = httpStatus;
  }

  /** 是否由载体（非业务）引起 */
  isCarrierFailure(): boolean {
    return this.code === 'carrier/closed' || this.code === 'carrier/transport'
      || this.code === 'carrier/parse' || this.code === 'carrier/timeout';
  }

  static carrier(message: string, details: string = ''): RemoteFailure {
    return new RemoteFailure('carrier/transport', message, details);
  }

  static closed(message: string): RemoteFailure {
    return new RemoteFailure('carrier/closed', message, '');
  }

  static parse(message: string, details: string = ''): RemoteFailure {
    return new RemoteFailure('carrier/parse', message, details);
  }

  static timeout(message: string): RemoteFailure {
    return new RemoteFailure('carrier/timeout', message, '');
  }

  toString(): string {
    return `${this.code}: ${this.message}`;
  }
}

/** 一元调用结果：ok=true 携带 value，ok=false 携带 error。绝不为载体问题 reject。 */
export interface RpcResult {
  ok: boolean;
  value?: Object;
  error?: RemoteFailure;
}

export function rpcOk(value: Object): RpcResult {
  return { ok: true, value: value };
}

export function rpcFail(error: RemoteFailure): RpcResult {
  return { ok: false, error: error };
}
