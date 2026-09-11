/**
 * 逻辑流复用载体（`/api/remote.mux`，D2 §1.2）。
 *
 * 帧事实（服务端 → 客户端，共三类，见上游 `dsh-api-gateway/lib/types/stream-protocol.d.ts`
 * 的 `RemoteStreamServerMessage`）：
 *   1. `{ type:"item", streamId, value? }` —— 逐项推送业务值；
 *   2. `{ type:"error", streamId, error:{code,message,details} }` —— 终止并报错；
 *   3. `{ type:"end", streamId }` —— **正常终止**。
 *
 * 【事实修正】D2 §8.3 原先记录「正常结束即流结束（无终止帧）」，该记录**已被上游类型声明推翻**：
 *   `end` 帧确实存在。漏处理它不会立刻出错（因为上游随后也会关闭逻辑流），
 *   但会让上层无法区分「Host 主动正常结束」与「连接意外断开」——
 *   前者不该触发重连，后者必须触发。因此这里必须显式处理。
 *
 * 客户端 → `{ type:"open", streamId, endpoint, payload }` / `{ type:"cancel", streamId }`
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

/**
 * `error` 事件之后的**活性宽限期**（毫秒）。
 *
 * 依据：服务端每 2 s 发一次 Ping（文件头的「心跳事实」），所以 6 s 内至少应有一个
 * 周期到达。取 6 s 是在「真断了要尽快恢复」与「不要被一个含义含糊的事件误判」
 * 之间折中——实测这个误判会让全部逻辑流被杀掉（见 `socket.on('error')` 的说明）。
 */
const LIVENESS_GRACE_MS: number = 6000;

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
  /** 活性宽限期计时器（-1 = 未在宽限期内），见 `startLivenessGrace` */
  private livenessTimer: number = -1;

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
      // 收到帧 = 链路活着的**证据**：撤销 error 引入的宽限期
      this.clearLivenessGrace();
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
      // 【不要把 error 事件当成连接已死】实测（`entry/src/ohosTest/.../MuxProbe.test.ets`，
      // 在设备内部连同一个 mux 地址）：ArkTS 会在**连接仍然健康**时抛出
      // `code=200 message=undefined` 的 error 事件——实测该事件在 73–198 ms 到达，
      // 而**没有任何 close 事件**，连接随后稳定存活整个 8 s 观察窗口
      // （无心跳与带心跳两种配置都一样）。
      //
      // 旧实现一见 error 就 `onSocketClosed()`，于是：
      //   - 全部逻辑流被以 `carrier/closed` 终止（症状就是「open 后 ~27 ms 就 closed」）；
      //   - 上层看到「连接失效」，而物理链路其实是好的。
      // 表现为审批/提问推送、通知、设置页外部改动刷新全部失效，且错误文案指向
      // 「载体断了」这个**错误的方向**。
      //
      // 改为：记下错误并给一段**宽限期**，让后续到达的帧来证明链路仍然活着；
      // 只有宽限期内**一个帧都没来**，才判定为真的断开。
      // 「谁说了算」这样才落在证据（收到帧）上，而不是落在一个含义含糊的事件上。
      this.startLivenessGrace();
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

  /**
   * 收到 `error` 后给链路的**宽限期**（毫秒）。
   *
   * 取值依据：服务端每 2 s 发一次 Ping（见文件头心跳事实），
   * 因此 6 s 内至少应有一个周期到达。取 6 s 是为了在
   * 「真断了要尽快恢复」与「不要被一个含糊事件误判」之间折中。
   */
  // 常量在文件末尾声明（ArkTS 要求先声明后用，这里用类静态字段规避顺序问题）

  /**
   * 进入活性宽限期：等一个**真实的帧**来证明链路还活着。
   *
   * 为什么不是直接判死：实测 `error` 事件会在链路健康时到来（见 `socket.on('error')`
   * 的说明）。只有「宽限期内一个帧都没收到」才是可靠证据。
   */
  private startLivenessGrace(): void {
    if (this.livenessTimer !== -1) {
      // 已在宽限期内：重复的 error 不重置计时（否则持续的错误会让宽限期永不结束）
      return;
    }
    this.livenessTimer = setTimeout(() => {
      this.livenessTimer = -1;
      // 宽限期内没有任何帧到达 → 这次是真的断了
      this.onSocketClosed(this.lastError ?? 'wss 活性宽限期超时（未收到任何帧）');
    }, LIVENESS_GRACE_MS);
  }

  /** 收到任何服务端帧：链路被证明是活的，撤销宽限期并清掉错误 */
  private clearLivenessGrace(): void {
    if (this.livenessTimer !== -1) {
      clearTimeout(this.livenessTimer);
      this.livenessTimer = -1;
    }
    if (this.lastError !== undefined) {
      this.lastError = undefined;
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
      // 【命名修正】原先这里用 `gateway/internal` 作兜底码——那是**我们自造的**，
      // 不是上游的码（上游的 `gateway/*` 是一组明确的边界错误，见 D2）。
      // 用自己的码冒充上游命名空间会带来两个问题：一是架构门禁无法区分
      // 「上游事实」与「我们的兜底」（正是它把此处报成违规的原因），
      // 二是排查时会把「我们的解析兜底」误读成「Host 报了一个网关错误」。
      // 语义上这确实是**信封解析**问题（错误对象读不出 code），故归入 carrier/parse。
      const code: string = error === undefined ? 'carrier/parse' : (getString(error, 'code') ?? 'carrier/parse');
      const message: string = error === undefined ? 'stream error' : (getString(error, 'message') ?? 'stream error');
      stream.sink.onError(code, message);
      return;
    }
    if (type === 'end') {
      // 正常终止：与 error 区分开，上层据此**不**触发重连（见文件头「事实修正」）
      this.streams.delete(streamId);
      stream.settled = true;
      stream.sink.onEnd();
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
