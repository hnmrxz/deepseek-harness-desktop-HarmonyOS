/**
 * `@kit.NetworkKit` 的 **Node 垫片**（只为 `tools/check-core-loop.mjs` 用）。
 *
 * ## 它为什么存在
 *
 * 客户端的协议层（`connection/protocol`）只用到这个 kit 的两样东西：
 * `http.createHttp()` 与 `webSocket.createWebSocket()`。把它们在 Node 上实现一遍，
 * 就能让**应用自己的代码**（不是重写一遍的探针）在本机对着**真 dsh Host** 跑完整闭环 ——
 * 这是没有设备时唯一能证明"连得上、建得了会话、收得到事件"的办法。
 *
 * ## 形状为什么是 namespace
 *
 * SDK 里它们是**全局命名空间**，应用代码既当值用（`http.createHttp()`）、也当类型用
 * （`const r: http.HttpRequest`）。垫片导出同名命名空间即可同时满足两者。
 *
 * ## 纪律
 *
 * 垫片只补"平台能力"，**不改变语义**：请求头、cookie、方法、超时原样透传；
 * WS 只做"能发能收能关"。任何为了"让检查过"而对协议动手脚的做法都不允许——
 * 那样测的就不是应用代码了。
 */

declare const require: (id: string) => any;
declare const Buffer: any;
declare const globalThis: any;

export namespace http {
  export enum RequestMethod {
    OPTIONS = 'OPTIONS',
    GET = 'GET',
    HEAD = 'HEAD',
    POST = 'POST',
    PUT = 'PUT',
    DELETE = 'DELETE',
    TRACE = 'TRACE',
    CONNECT = 'CONNECT',
  }

  export enum HttpDataType {
    STRING = 0,
    OBJECT = 1,
    ARRAY_BUFFER = 2,
  }

  export interface HttpRequestOptions {
    method?: RequestMethod | string;
    header?: Record<string, string>;
    readTimeout?: number;
    connectTimeout?: number;
    expectDataType?: HttpDataType;
    usingCache?: boolean;
    extraData?: string | Object;
  }

  export interface HttpResponse {
    responseCode: number;
    result: string;
    cookies: string;
    header: Record<string, string>;
  }

  export interface HttpRequest {
    request(url: string, options?: HttpRequestOptions): Promise<HttpResponse>;
    destroy(): void;
  }

  /** 与 ArkTS 同名同形：一次请求一个对象，用完即弃 */
  export function createHttp(): HttpRequest {
    const nodeHttp = require('node:http');
    const nodeHttps = require('node:https');
    let destroyed = false;
    return {
      destroy(): void {
        destroyed = true;
      },
      request(url: string, options?: HttpRequestOptions): Promise<HttpResponse> {
        return new Promise<HttpResponse>((resolve, reject) => {
          if (destroyed) {
            reject(new Error('http request destroyed'));
            return;
          }
          const target = new URL(url);
          const mod = target.protocol === 'https:' ? nodeHttps : nodeHttp;
          const header: Record<string, string> = options?.header ?? {};
          const method: string = String(options?.method ?? RequestMethod.GET);
          const req = mod.request({
            protocol: target.protocol,
            hostname: target.hostname,
            port: target.port,
            path: `${target.pathname}${target.search}`,
            method: method,
            headers: header,
          }, (res: any) => {
            const chunks: any[] = [];
            res.on('data', (c: any) => chunks.push(c));
            res.on('end', () => {
              const raw: string = Buffer.concat(chunks).toString('utf8');
              const outHeader: Record<string, string> = {};
              for (const key of Object.keys(res.headers)) {
                const value = res.headers[key];
                outHeader[key] = Array.isArray(value) ? value.join(', ') : String(value);
              }
              const setCookie = res.headers['set-cookie'];
              resolve({
                responseCode: res.statusCode ?? 0,
                result: raw,
                cookies: Array.isArray(setCookie) ? setCookie.join('; ') : String(setCookie ?? ''),
                header: outHeader,
              });
            });
          });
          req.on('error', (error: any) => reject(error));
          if (options?.connectTimeout !== undefined && options.connectTimeout > 0) {
            req.setTimeout(options.connectTimeout, () => {
              req.destroy(new Error(`connect timeout after ${options.connectTimeout}ms`));
            });
          }
          if (options?.extraData !== undefined) {
            req.write(String(options.extraData));
          }
          req.end();
        });
      },
    };
  }
}

export namespace webSocket {
  export interface WebSocketRequestOptions {
    header?: Record<string, string>;
  }

  export interface CloseResult {
    code: number;
    reason: string;
  }

  export interface WebSocket {
    on(event: string, callback: (...args: any[]) => void): void;
    off(event: string, callback?: (...args: any[]) => void): void;
    connect(url: string, options?: WebSocketRequestOptions): Promise<boolean>;
    send(data: string): Promise<boolean>;
    close(options?: Object): Promise<boolean>;
  }

  /**
   * 用 Node 22 内建的全局 `WebSocket`（undici）实现 ArkTS 的 `webSocket` 形状。
   *
   * **只用于本机对真 Host 的验证**：端侧走 ArkTS 的 webSocket（libwebsockets），
   * 两者在"自定义 header 是否转发""ping/pong 处理"上有已知差异（见 `RemoteMux` 注释），
   * 所以本垫片跑通**不能**替代真机验收。
   */
  export function createWebSocket(): WebSocket {
    let socket: any = undefined;
    const handlers: Record<string, ((...args: any[]) => void)[]> = {};
    const emit = (event: string, ...args: any[]): void => {
      for (const cb of handlers[event] ?? []) {
        cb(undefined, ...args);
      }
    };
    return {
      on(event: string, callback: (...args: any[]) => void): void {
        if (handlers[event] === undefined) handlers[event] = [];
        handlers[event].push(callback);
      },
      off(event: string, callback?: (...args: any[]) => void): void {
        if (callback === undefined) {
          handlers[event] = [];
          return;
        }
        handlers[event] = (handlers[event] ?? []).filter((c) => c !== callback);
      },
      connect(url: string, options?: WebSocketRequestOptions): Promise<boolean> {
        return new Promise<boolean>((resolve) => {
          try {
            const WS = globalThis.WebSocket;
            socket = options?.header === undefined ? new WS(url) : new WS(url, { headers: options.header });
          } catch (error) {
            resolve(false);
            return;
          }
          socket.addEventListener('open', () => {
            emit('open');
            resolve(true);
          });
          socket.addEventListener('message', (event: any) => {
            emit('message', typeof event.data === 'string' ? event.data : String(event.data));
          });
          socket.addEventListener('close', (event: any) => {
            emit('close', { code: event.code ?? 0, reason: event.reason ?? '' });
          });
          socket.addEventListener('error', () => {
            emit('error');
            resolve(false);
          });
        });
      },
      send(data: string): Promise<boolean> {
        return new Promise<boolean>((resolve, reject) => {
          try {
            socket.send(data);
            resolve(true);
          } catch (error) {
            reject(error);
          }
        });
      },
      close(): Promise<boolean> {
        return new Promise<boolean>((resolve) => {
          try {
            socket.close();
          } catch (error) {
            // 已经关了：视作成功（与 ArkTS 行为一致）
          }
          resolve(true);
        });
      },
    };
  }
}
