/**
 * 连接门面（Connection）：把协议兼容层组装成一个可被 UI/状态层直接使用的对象。
 *
 * 职责边界：
 *   - 拥有 cookie jar、认证会话、HTTP 载体、mux、事件流、重连调度；
 *   - 对外只暴露：configure / authenticate / start / stop / reconnect / call / openStream / 诊断；
 *   - **不**做业务投影（会话状态由上层投影），**不**持有 UI 引用（D1 §6.3 分层铁律）。
 */

import {
  HostAddress,
  ParsedTarget,
  parseTarget
} from './HostAddress';
import { CookieJar } from './Cookies';
import { HttpClient, HttpOutcome } from './HttpClient';
import { AuthOutcome, AuthSession, isAuthFailureStatus } from './AuthSession';
import { RemoteMux } from './RemoteMux';
import { EventStream, EventStreamPhase } from './EventStream';
import { ReconnectController } from './Backoff';
import { stringifyJson } from './JsonValue';
import {
  API_CHANNEL,
  checkTarget,
  RemoteFailure,
  rpcFail,
  RpcResult
} from './RpcTypes';
import { parseConnectionResponse } from './Envelope';
import {
  CallOptions,
  ConnectionState,
  CookieRecord,
  DiagnosticItem,
  DiagnosticReport,
  EventSink,
  HostConfig,
  StreamSink
} from './Types';

/** 连接参数 */
export interface ConnectionOptions {
  /** 一元调用默认超时（毫秒） */
  defaultTimeoutMs?: number;
  /** mux 单次连接尝试超时（毫秒） */
  muxConnectTimeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS: number = 30000;
const DEFAULT_MUX_TIMEOUT_MS: number = 10000;

/** cookie 持久化钩子（实现方负责加密存储，D1 §11.5 S3） */
export interface CookiePersistence {
  load(): string | undefined;
  save(serialized: string): void;
  clear(): void;
}

/** 随机 UUID（RFC 4122 v4，避免额外依赖） */
export function randomUuid(): string {
  const hex: string = '0123456789abcdef';
  let out: string = '';
  for (let i = 0; i < 32; i++) {
    out += hex.charAt(Math.floor(Math.random() * 16));
  }
  return `${out.substring(0, 8)}-${out.substring(8, 12)}-4${out.substring(13, 16)}`
    + `-a${out.substring(17, 20)}-${out.substring(20)}`;
}

export class Connection {
  private options: Required<ConnectionOptions>;
  private jar: CookieJar = new CookieJar();
  private http: HttpClient;
  private mux?: RemoteMux;
  private eventStream?: EventStream;
  private auth?: AuthSession;
  private address?: HostAddress;
  private config?: HostConfig;
  private reconnector: ReconnectController = new ReconnectController();
  private state: ConnectionState = ConnectionState.IDLE;
  private lastError?: string;
  private persistence?: CookiePersistence;
  private stateListeners: Array<(state: ConnectionState, detail: string) => void> = [];

  constructor(options?: ConnectionOptions) {
    const merged: Required<ConnectionOptions> = {
      defaultTimeoutMs: options?.defaultTimeoutMs ?? DEFAULT_TIMEOUT_MS,
      muxConnectTimeoutMs: options?.muxConnectTimeoutMs ?? DEFAULT_MUX_TIMEOUT_MS
    };
    this.options = merged;
    this.http = new HttpClient(this.jar);
  }

  // ─────────────────────────── 配置与状态 ───────────────────────────

  getState(): ConnectionState {
    return this.state;
  }

  getLastError(): string | undefined {
    return this.lastError;
  }

  getConfig(): HostConfig | undefined {
    return this.config;
  }

  /** 事件流阶段（诊断与 UI 展示） */
  getEventPhase(): EventStreamPhase {
    return this.eventStream?.getPhase() ?? EventStreamPhase.IDLE;
  }

  /** Host 事实（ready 首项之后可用） */
  getHostFactsClientId(): string | undefined {
    return this.eventStream?.getFacts()?.clientId;
  }

  getHostHome(): string | undefined {
    return this.eventStream?.getFacts()?.home;
  }

  onStateChange(listener: (state: ConnectionState, detail: string) => void): void {
    this.stateListeners.push(listener);
  }

  private setState(state: ConnectionState, detail: string): void {
    this.state = state;
    if (state === ConnectionState.DISCONNECTED) {
      this.lastError = detail;
    }
    for (let i = 0; i < this.stateListeners.length; i++) {
      this.stateListeners[i](state, detail);
    }
  }

  /** 注入 cookie 持久化实现并立即恢复已保存的 cookie */
  attachPersistence(persistence: CookiePersistence): void {
    this.persistence = persistence;
    const serialized: string | undefined = persistence.load();
    if (serialized !== undefined && serialized.length > 0) {
      this.jar.replaceAll(deserializeCookies(serialized));
    }
  }

  /**
   * 解析并设置目标地址（不发起网络请求）。
   * 接受 `host:port` / `http://host:port` / 带 `?token=` 的启动 URL。
   */
  configure(input: string, name?: string): HostConfig | undefined {
    const target: ParsedTarget | undefined = parseTarget(input);
    if (target === undefined) {
      this.lastError = `无法解析地址：${input}`;
      return undefined;
    }
    const address: HostAddress = target.address;
    this.address = address;
    this.pendingToken = target.token;
    this.auth = new AuthSession(this.jar, this.http, address);
    this.auth.setToken(target.token);
    const config: HostConfig = {
      name: name ?? address.authority,
      authority: address.authority,
      hostname: address.hostname,
      port: address.port,
      scheme: address.scheme,
      baseUrl: address.baseUrl,
      wsBaseUrl: address.wsBaseUrl,
      isLoopback: address.isLoopback
    };
    this.config = config;
    return config;
  }

  /** 当前是否已配置 */
  isConfigured(): boolean {
    return this.address !== undefined;
  }

  // ─────────────────────────── 认证 ───────────────────────────

  /** 是否已持有可用 cookie */
  hasSession(): boolean {
    return this.auth?.hasCookie() ?? false;
  }

  /** 用 token 交换签名 cookie（配置必须已完成） */
  async authenticate(token?: string): Promise<AuthOutcome> {
    const session: AuthSession | undefined = this.auth;
    if (session === undefined) {
      return { ok: false, status: 0, reason: '未配置 Host 地址' };
    }
    const effective: string = token ?? this.pendingToken ?? '';
    if (effective.length === 0) {
      return {
        ok: false,
        status: 0,
        reason: '未提供 token',
        advice: '粘贴 Host 的启动 URL（形如 http://127.0.0.1:3000/?token=xxxx），或单独填写 token。'
      };
    }
    const outcome: AuthOutcome = await session.exchange(effective);
    if (outcome.ok) {
      this.persistCookies();
    }
    return outcome;
  }

  /** 重新绑定认证（cookie 失效时） */
  async rebind(): Promise<AuthOutcome> {
    const session: AuthSession | undefined = this.auth;
    if (session === undefined) {
      return { ok: false, status: 0, reason: '未配置 Host 地址' };
    }
    const outcome: AuthOutcome = await session.rebind();
    if (outcome.ok) {
      this.persistCookies();
    }
    return outcome;
  }

  /** 最近一次 configure 中解析出的 token（用于自动重绑） */
  private pendingToken?: string;

  // ─────────────────────────── 生命周期 ───────────────────────────

  /**
   * 建立连接：一次 mux 物理连接尝试 + 打开事件流。
   * 首次握手由调用方在 authenticate() 之后调用。失败时不自动重试（由 start 负责调度）。
   */
  async connectOnce(): Promise<boolean> {
    const address: HostAddress | undefined = this.address;
    if (address === undefined) {
      this.lastError = '未配置 Host 地址';
      return false;
    }
    if (this.mux === undefined) {
      this.mux = new RemoteMux(address.wsBaseUrl, () => this.jar.headerFor(address.authority));
    }
    this.setState(ConnectionState.CONNECTING, '正在连接…');
    const opened: boolean = await this.mux.connectOnce(this.options.muxConnectTimeoutMs);
    if (!opened) {
      this.lastError = this.mux.getLastError() ?? 'WebSocket 连接失败';
      return false;
    }
    return true;
  }

  /**
   * 启动连接循环：建立连接 + 打开事件流，失败按 D2 §3 退避重试。
   * @param sink 事件流回调
   */
  async start(sink: EventSink): Promise<boolean> {
    this.reconnector.reset();
    this.eventStream = new EventStream(this.getMux(), {
      onReady: (facts) => {
        this.setState(ConnectionState.CONNECTED, `已连接（clientId=${facts.clientId}）`);
        const readySink = sink.onReady;
        if (readySink !== undefined) {
          readySink(facts);
        }
      },
      onEvent: (event: Object) => {
        sink.onEvent(event);
      },
      onEnd: (error?: string) => {
        this.lastError = error ?? '事件流结束';
        this.scheduleReconnect(sink);
      }
    });
    const ok: boolean = await this.connectOnce();
    if (!ok) {
      this.scheduleReconnect(sink);
      return false;
    }
    const streamOk: boolean = this.eventStream.open();
    if (!streamOk) {
      this.scheduleReconnect(sink);
      return false;
    }
    return true;
  }

  private getMux(): RemoteMux {
    const address: HostAddress | undefined = this.address;
    if (this.mux === undefined) {
      const base: string = address === undefined ? '' : address.wsBaseUrl;
      const authority: string = address === undefined ? '' : address.authority;
      this.mux = new RemoteMux(base, () => this.jar.headerFor(authority));
    }
    return this.mux;
  }

  private scheduleReconnect(sink: EventSink): void {
    this.reconnector.schedule(async (): Promise<boolean> => {
      const mux: RemoteMux | undefined = this.mux;
      if (mux !== undefined) {
        await mux.close();
      }
      this.mux = undefined;
      const ok: boolean = await this.connectOnce();
      if (!ok) {
        return false;
      }
      // cookie 可能在断连期间失效：401 由 call 处理，这里只重建事件流 generation
      const stream: EventStream | undefined = this.eventStream;
      if (stream !== undefined) {
        return stream.open();
      }
      return true;
    }, (progress) => {
      this.setState(ConnectionState.CONNECTING,
        `第 ${progress.attempt} 次重试将在 ${progress.waitMs}ms 后进行（档位 ${progress.delayMs}ms）`);
    }, () => {
      this.setState(ConnectionState.DISCONNECTED, `重试已耗尽：${this.lastError ?? '未知原因'}`);
      sink.onEnd(this.lastError);
    });
  }

  /** 立即手动重连（对应上游 connection.reconnect()） */
  async reconnect(sink: EventSink): Promise<boolean> {
    const mux: RemoteMux | undefined = this.mux;
    if (mux !== undefined) {
      await mux.close();
    }
    this.mux = undefined;
    this.reconnector.reset();
    return await this.start(sink);
  }

  /** 停止并释放（幂等） */
  async stop(): Promise<void> {
    this.reconnector.stop();
    this.eventStream?.close();
    this.eventStream = undefined;
    const mux: RemoteMux | undefined = this.mux;
    if (mux !== undefined) {
      await mux.close();
    }
    this.mux = undefined;
    this.setState(ConnectionState.IDLE, '已停止');
  }

  // ─────────────────────────── 一元调用 ───────────────────────────

  /**
   * 发起一元 Remote 调用。
   *
   * 纪律：**绝不为载体问题 reject**；调用方只需判 `result.ok`。
   * 401 时（且 allowAuthRetry !== false）自动重绑一次并重放原请求。
   */
  async call(endpoint: string, args: Object, options?: CallOptions): Promise<RpcResult> {
    const address: HostAddress | undefined = this.address;
    if (address === undefined) {
      return rpcFail(RemoteFailure.carrier('未配置 Host 地址'));
    }
    const target = checkTarget(API_CHANNEL, endpoint);
    if (!target.ok) {
      return rpcFail(RemoteFailure.parse(`非法 endpoint：${target.reason ?? endpoint}`));
    }

    const timeoutMs: number = options?.timeoutMs ?? this.options.defaultTimeoutMs;
    const first: RpcResult = await this.callOnce(address, endpoint, args, timeoutMs);
    if (first.ok) {
      return first;
    }
    const failure: RemoteFailure | undefined = first.error;
    const shouldRetryAuth: boolean = options?.allowAuthRetry !== false;
    if (shouldRetryAuth && failure !== undefined && isAuthFailureStatus(failure.httpStatus ?? 0)) {
      const rebind: AuthOutcome = await this.rebind();
      if (rebind.ok) {
        return await this.callOnce(address, endpoint, args, timeoutMs);
      }
      return rpcFail(new RemoteFailure('auth/rebind-failed',
        rebind.reason ?? '重新授权失败', rebind.advice ?? ''));
    }
    return first;
  }

  private async callOnce(address: HostAddress, endpoint: string, args: Object,
    timeoutMs: number): Promise<RpcResult> {
    const rpcId: string = randomUuid();
    const body: string | undefined = buildBody(rpcId, endpoint, args);
    if (body === undefined) {
      return rpcFail(RemoteFailure.parse(`无法序列化请求体：${endpoint}`));
    }
    const outcome: HttpOutcome = await this.http.send(
      `${address.baseUrl}${API_CHANNEL}/${endpoint}`,
      address.authority, true, body, timeoutMs, true);

    if (!outcome.responded) {
      return rpcFail(RemoteFailure.carrier(
        `请求失败：${outcome.transportError ?? '未知网络错误'}`));
    }
    if (outcome.status !== 200) {
      if (isAuthFailureStatus(outcome.status)) {
        const failure: RemoteFailure = new RemoteFailure('auth/unauthorized',
          '会话未认证或已过期（HTTP 401）', '需要重新授权');
        failure.httpStatus = outcome.status;
        return rpcFail(failure);
      }
      return rpcFail(new RemoteFailure('carrier/transport',
        `传输失败：HTTP ${outcome.status}（${endpoint}）`, outcome.body.substring(0, 200)));
    }
    if (outcome.body.length === 0) {
      return rpcFail(RemoteFailure.parse(`空响应体（${endpoint}）`));
    }
    return parseConnectionResponse(outcome.body, rpcId, endpoint);
  }

  // ─────────────────────────── 逻辑流 ───────────────────────────

  /**
   * 打开一条业务逻辑流（如 `session/follow`）。
   * @returns 取消函数；未连接时返回 undefined
   */
  openStream(endpoint: string, args: Object, sink: StreamSink): (() => void) | undefined {
    const mux: RemoteMux | undefined = this.mux;
    if (mux === undefined || !mux.isOpen()) {
      return undefined;
    }
    const payload: Record<string, Object> = { 'args': args };
    const payloadJson: string | undefined = stringifyJson(payload as Object);
    if (payloadJson === undefined) {
      return undefined;
    }
    const streamId: string | undefined = mux.open(endpoint, payloadJson, sink);
    if (streamId === undefined) {
      return undefined;
    }
    return () => {
      mux.cancel(streamId);
    };
  }

  // ─────────────────────────── 诊断 ───────────────────────────

  /** 生成五项连接诊断（D1 G7） */
  async diagnose(): Promise<DiagnosticReport> {
    const items: DiagnosticItem[] = [];
    const address: HostAddress | undefined = this.address;

    // ① 端点
    if (address === undefined) {
      items.push({
        name: '端点', passed: false, detail: '未配置 Host 地址',
        advice: '填写 Host 地址（如 127.0.0.1:3000）或粘贴启动 URL。'
      });
      return { items: items, healthy: false, generatedAt: Date.now() };
    }
    const isUp: boolean = await this.probeReachable(address);
    items.push({
      name: '端点', passed: isUp,
      detail: isUp ? `${address.authority} 可达` : `${address.authority} 不可达`,
      advice: isUp ? undefined : '确认 Host 正在运行、端口正确，且设备与 Host 网络互通。'
    });

    // ② TLS
    const tlsOk: boolean = address.scheme === 'http' ? true : isUp;
    items.push({
      name: 'TLS', passed: tlsOk,
      detail: address.scheme === 'https'
        ? (isUp ? 'HTTPS 握手成功' : 'HTTPS 握手失败')
        : 'HTTP（dsh 默认 loopback 姿态，不设 Secure cookie）',
      advice: address.scheme === 'https' && !isUp
        ? '自签证书需在设备上受信任；建议优先使用隧道方案而非直接暴露 Host。'
        : undefined
    });

    // ③ 认证
    const cookieNames: string[] = this.auth?.cookieNames() ?? [];
    const authOk: boolean = cookieNames.length > 0;
    items.push({
      name: '认证', passed: authOk,
      detail: authOk ? `已持有会话 cookie（${cookieNames.join(', ')}）` : '未持有会话 cookie',
      advice: authOk ? undefined : '重新粘贴 Host 启动 URL（含 ?token=）完成授权。'
    });

    // ④ 协议（mux 是否就绪 + 事件流阶段）
    const muxReady: boolean = this.mux?.isOpen() ?? false;
    const phase: EventStreamPhase = this.getEventPhase();
    const protocolOk: boolean = muxReady && phase === EventStreamPhase.LIVE;
    items.push({
      name: '协议', passed: protocolOk,
      detail: `WebSocket ${muxReady ? '已建立' : '未建立'}；事件流 ${phase}`,
      advice: protocolOk ? undefined
        : (muxReady ? '事件流未就绪：查看诊断日志中的帧序列，确认 /api/remote.mux 与 $events 行为。'
          : 'WebSocket 未建立：可能是 Host 未启用 webserver，或中间网络阻断 upgrade。')
    });

    // ⑤ Host 版本/事实
    const clientId: string | undefined = this.getHostFactsClientId();
    items.push({
      name: 'Host', passed: phase === EventStreamPhase.LIVE,
      detail: phase === EventStreamPhase.LIVE
        ? `clientId=${clientId ?? '(空)'} home=${this.getHostHome() ?? '(空)'}`
        : '尚未收到 ready 首项，无法读取 Host 事实',
      advice: phase === EventStreamPhase.LIVE ? undefined : '等待 ready 首项；若长期不到达，检查事件流端点可用性。'
    });

    let healthy: boolean = true;
    for (let i = 0; i < items.length; i++) {
      if (!items[i].passed) {
        healthy = false;
      }
    }
    return { items: items, healthy: healthy, generatedAt: Date.now() };
  }

  /** 探测端点可达性（用根路径 HEAD 语义的 GET，不消耗业务端点） */
  private async probeReachable(address: HostAddress): Promise<boolean> {
    const outcome: HttpOutcome =
      await this.http.send(`${address.baseUrl}/`, address.authority, false, undefined, 8000, false);
    return outcome.responded;
  }

  // ─────────────────────────── cookie 持久化 ───────────────────────────

  private persistCookies(): void {
    const persistence: CookiePersistence | undefined = this.persistence;
    if (persistence === undefined) {
      return;
    }
    persistence.save(serializeCookies(this.jar.snapshot()));
  }

  /** 清空认证与持久化 cookie */
  clearSession(): void {
    this.auth?.clear();
    this.persistence?.clear();
  }
}

/** 构造一元请求体 */
function buildBody(rpcId: string, endpoint: string, args: Object): string | undefined {
  const payload: Record<string, Object> = { 'args': args };
  const message: Record<string, Object> = {
    'type': 'client-request',
    'rpcId': rpcId,
    'method': endpoint,
    'payload': payload as Object
  };
  return stringifyJson(message as Object);
}

/** cookie 序列化（仅内存/持久化用；实现方须加密存储） */
export function serializeCookies(records: CookieRecord[]): string {
  const parts: string[] = [];
  for (let i = 0; i < records.length; i++) {
    const r: CookieRecord = records[i];
    parts.push(`${r.authority}|${r.name}|${r.value}`);
  }
  return parts.join('\n');
}

/** cookie 反序列化 */
export function deserializeCookies(text: string): CookieRecord[] {
  const out: CookieRecord[] = [];
  const lines: string[] = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i];
    if (line.length === 0) {
      continue;
    }
    const first: number = line.indexOf('|');
    const second: number = line.indexOf('|', first + 1);
    if (first <= 0 || second <= first) {
      continue;
    }
    out.push({
      authority: line.substring(0, first),
      name: line.substring(first + 1, second),
      value: line.substring(second + 1)
    });
  }
  return out;
}
