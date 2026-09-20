/**
 * `@ohos.net.socket` 的 Node 垫片（W2，2026-09-20）。
 *
 * 配套 `ohosnetconnection.ts`：`LanDiscovery.ets` 的逐 IP TCP 探测需要
 * `socket.constructTCPSocketInstance()` 与 `TCPSocket.connect/close`。类型形状照抄
 * 使用面（`LanDiscovery.ets:187-206`），运行时 fail-loud —— 本机回路不测 LAN 发现。
 */
namespace socket {
  export interface NetAddress { address: string; port?: number; family?: number }
  export interface TCPConnectOptions { address: NetAddress; timeout?: number }
  export interface TCPSocket {
    connect(options: TCPConnectOptions, callback: (err: Error | undefined) => void): void;
    close(callback?: (err: Error | undefined) => void): void;
  }
  const STUB = 'LAN 发现垫片：@ohos.net.socket 在 Node 回路里不可用（需要真机 TCP 栈）';
  export function constructTCPSocketInstance(): TCPSocket {
    throw new Error(STUB);
  }
}
export default socket;
