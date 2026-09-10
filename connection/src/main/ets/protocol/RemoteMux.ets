/**
 * 逻辑流复用载体（`/api/remote.mux`，D2 §1.2）。
 *
 * 帧事实：
 *   客户端 → `{ type:"open", streamId, endpoint, payload }` / `{ type:"cancel", streamId }`
 *   服务端 → `item`（逐项）/ `error`（终止并报错）；正常终止即流结束（无终止帧）
 *
 * 心跳事实：Host 每 2 s 发 Ping 控制帧，若在下一周期前未收到 Pong 会**主动断开**。
 * ArkTS 侧对策（本项目决策，写入 D2）：显式开启客户端心跳
 *   `pingInterval=5000ms, pongTimeout=4000ms`
 * 使链路上持续存在**双向**流量，避免中间设备与对端把连接判为静默。
 *
 * 连接纪律：物理连接**空闲也保持**；重连调度由 ReconnectController 拥有，
 * 本类只做「一次物理连接尝试」，不做自主重试（与上游语义一致）。
 */

import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { getString, getRecord, parseJson, stringifyJson } from './JsonValue';
import { ProtocolSurface, FALLBACK_SURFACE } from './Surface';
import { StreamSink } from './Types';

/** 一条逻辑流的本地记账 */
interface LogicalStream {
  streamId: string;
  sink: StreamSink;
  /** 流是否已进入终态（避免重复回调） */
  settled: boolean;
}

/** 物理连接状态 */
export enum MuxState {
  CLOSED = 'closed',
  CONNECTING = 'connecting',
  OPEN = 'open'
}

export class RemoteMux {
  private baseUrl: string;
  private cookieProvider: () => string | undefined;
  /** 上游接口面（路径等事实由兼容面注入，不在本类硬编码） */
  private surface: ProtocolSurface;
  private socket?: webSocket.WebSocket;
  private state: MuxState = MuxState.CLOSED;
  private streams: Map<string, LogicalStream> = new Map<string, LogicalStream>();
  private disposed: boolean = false;
  private openWaiters: Array<(ok: boolean, reason?: string) => void> = [];
  private lastError?: string;

  constructor(baseUrl: string, cookieProvider: () => string | undefined,
    surface: ProtocolSurface = FALLBACK_SURFACE) {
    this.baseUrl = baseUrl;
    this.cookieProvider = cookieProvider;
    this.surface = surface;
  }

  getState(): MuxState {
    return this.state;
  }

  getLastError(): string | undefined {
    return this.lastError;
  }

  /** 当前活动逻辑流数（诊断用） */
  activeStreamCount(): number {
    return this.streams.size;
  }

  /** 是否已就绪（可开流） */
  isOpen(): boolean {
    return this.state === MuxState.OPEN && !this.disposed;
  }

  /**
   * 执行一次物理连接尝试。成功返回 true。
   * 若已有开启的连接，直接返回 true（幂等）。
   */
  async connectOnce(timeoutMs: number): Promise<boolean> {
    if (this.disposed) {
      return false;
    }
    if (this.state === MuxState.OPEN) {
      return true;
    }
    if (this.state === MuxState.CONNECTING) {
      return await this.waitForOpen(timeoutMs);
    }

    const socket: webSocket.WebSocket = webSocket.createWebSocket();
    this.socket = socket;
    this.state = MuxState.CONNECTING;
    this.lastError = undefined;

    socket.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
      if (err !== undefined && err !== null && err.code !== 0) {
        return;
      }
      if (typeof data === 'string') {
        this.handleFrame(data as string);
      }
    });
    socket.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      const code: number = value === undefined || value === null ? 0 : value.code;
      const reason: string = value === undefined || value === null ? '' : (value.reason ?? '');
      this.onSocketClosed(`close code=${code}${reason.length > 0 ? ` reason=${reason}` : ''}${err !== undefined && err !== null && err.code !== 0 ? ` err=${err.code}` : ''}`);
    });
    socket.on('error', (err: BusinessError) => {
      this.lastError = `ws error code=${err.code} message=${err.message}`;
      this.onSocketClosed(this.lastError);
    });

    const header: Record<string, string> = {};
    const cookie: string | undefined = this.cookieProvider();
    if (cookie !== undefined) {
      header['cookie'] = cookie;
    }
    const options: webSocket.WebSocketRequestOptions = {
      header: header,
      // 见文件头「心跳事实」：显式开启双向心跳，避免 2 s Ping 语义下被判静默
      pingInterval: 5000,
      pongTimeout: 4000
    };

    try {
      const opened: boolean = await socket.connect(`${this.baseUrl}${this.surface.muxPath}`, options);
      if (!opened) {
        this.lastError = 'ws connect 返回 false';
        this.state = MuxState.CLOSED;
        this.resolveOpenWaiters(false, this.lastError);
        return false;
      }
      this.state = MuxState.OPEN;
      this.resolveOpenWaiters(true);
      return true;
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      this.lastError = `ws connect 失败 code=${businessError.code} message=${businessError.message}`;
      this.state = MuxState.CLOSED;
      this.resolveOpenWaiters(false, this.lastError);
      return false;
    }
  }

  private waitForOpen(timeoutMs: number): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      const timer: number = setTimeout(() => {
        resolve(false);
      }, timeoutMs);
      this.openWaiters.push((ok: boolean, reason?: string) => {
        clearTimeout(timer);
        resolve(ok);
      });
    });
  }

  private resolveOpenWaiters(ok: boolean, reason?: string): void {
    const waiters = this.openWaiters;
    this.openWaiters = [];
    for (let i = 0; i < waiters.length; i++) {
      waiters[i](ok, reason);
    }
  }

  /** 物理连接关闭：终止全部逻辑流并让上层（ReconnectController）看到失效 */
  private onSocketClosed(reason: string): void {
    if (this.state === MuxState.CLOSED) {
      return;
    }
    this.state = MuxState.CLOSED;
    this.resolveOpenWaiters(false, reason);
    const ids: string[] = [];
    this.streams.forEach((_value: LogicalStream, key: string) => {
      ids.push(key);
    });
    for (let i = 0; i < ids.length; i++) {
      const stream: LogicalStream | undefined = this.streams.get(ids[i]);
      if (stream !== undefined) {
        this.streams.delete(ids[i]);
        if (!stream.settled) {
          stream.settled = true;
          stream.sink.onError('carrier/closed', reason);
        }
      }
    }
  }

  /** 处理一条服务端帧 */
  private handleFrame(text: string): void {
    const frame: Object | undefined = parseJson(text);
    if (frame === undefined) {
      return;
    }
    const streamId: string | undefined = getString(frame, 'streamId');
    if (streamId === undefined) {
      return;
    }
    const stream: LogicalStream | undefined = this.streams.get(streamId);
    if (stream === undefined) {
      return;
    }
    const type: string | undefined = getString(frame, 'type');
    if (type === 'item') {
      const value: Object | undefined = getRecord(frame, 'value');
      if (value !== undefined) {
        stream.sink.onItem(value);
      }
      return;
    }
    if (type === 'error') {
      this.streams.delete(streamId);
      stream.settled = true;
      const error: Object | undefined = getRecord(frame, 'error');
      const code: string = error === undefined ? 'gateway/internal' : (getString(error, 'code') ?? 'gateway/internal');
      const message: string = error === undefined ? 'stream error' : (getString(error, 'message') ?? 'stream error');
      stream.sink.onError(code, message);
      return;
    }
    // 未知帧类型：忽略（前向兼容）
  }

  /**
   * 打开一条逻辑流。
   * @returns streamId；未连接时返回 undefined（调用方应先 await connectOnce）
   */
  open(endpoint: string, payloadJson: string, sink: StreamSink): string | undefined {
    if (!this.isOpen()) {
      return undefined;
    }
    const socket: webSocket.WebSocket | undefined = this.socket;
    if (socket === undefined) {
      return undefined;
    }
    const streamId: string = randomId();
    this.streams.set(streamId, { streamId: streamId, sink: sink, settled: false });
    const payload: Object | undefined = parseJson(payloadJson);
    const frame: Record<string, Object> = {
      'type': 'open',
      'streamId': streamId,
      'endpoint': endpoint,
      'payload': payload ?? (parseJson(this.surface.eventsPayloadJson) as Object)
    };
    const text: string | undefined = stringifyJson(frame as Object);
    if (text === undefined) {
      this.streams.delete(streamId);
      return undefined;
    }
    socket.send(text).catch((error: BusinessError) => {
      const stream: LogicalStream | undefined = this.streams.get(streamId);
      this.streams.delete(streamId);
      if (stream !== undefined && !stream.settled) {
        stream.settled = true;
        stream.sink.onError('carrier/transport', `send 失败 code=${error.code}`);
      }
    });
    return streamId;
  }

  /** 主动取消一条逻辑流（对应上游 finally 里的 cancel 帧） */
  cancel(streamId: string): void {
    const stream: LogicalStream | undefined = this.streams.get(streamId);
    if (stream === undefined) {
      return;
    }
    this.streams.delete(streamId);
    stream.settled = true;
    const socket: webSocket.WebSocket | undefined = this.socket;
    if (socket !== undefined && this.state === MuxState.OPEN) {
      const frame: Record<string, Object> = { 'type': 'cancel', 'streamId': streamId };
      const text: string | undefined = stringifyJson(frame as Object);
      if (text !== undefined) {
        socket.send(text).catch((_error: BusinessError) => {
          // 取消失败无副作用：连接已被上层视为失效
        });
      }
    }
    stream.sink.onEnd();
  }

  /** 关闭物理连接（永久） */
  async close(): Promise<void> {
    this.disposed = true;
    const socket: webSocket.WebSocket | undefined = this.socket;
    this.socket = undefined;
    this.onSocketClosed('client closed');
    if (socket !== undefined) {
      try {
        await socket.close();
      } catch (error) {
        // 忽略关闭异常
      }
    }
  }
}

/** 生成 streamId（无外部依赖的随机标识） */
function randomId(): string {
  const hex: string = '0123456789abcdef';
  let out: string = '';
  for (let i = 0; i < 32; i++) {
    out += hex.charAt(Math.floor(Math.random() * 16));
  }
  return `${out.substring(0, 8)}-${out.substring(8, 12)}-${out.substring(12, 16)}-${out.substring(16, 20)}-${out.substring(20)}`;
}
