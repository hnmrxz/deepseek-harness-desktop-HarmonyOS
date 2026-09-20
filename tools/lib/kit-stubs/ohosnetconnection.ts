/**
 * `@ohos.net.connection` 的 Node 垫片（W2，2026-09-20）。
 *
 * 【为什么现在才需要】0.1.6 升级轮里 `connection` 模块新增了 `protocol/LanDiscovery.ets`
 * （LAN 发现：枚举本机网段 → 逐 IP 探 3520 端口找同伴 Host），它 import 了
 * `@ohos.net.connection` / `@ohos.net.socket` 两个鸿蒙系统模块。`check-core-loop` 会把
 * `connection/src/main/ets` **全量**编译（Index.ets 以 `export type { … } from
 * './protocol/LanDiscovery'` 重导出它的类型，排除文件会断重导出），于是这两个模块
 * 必须有可编译的形状。
 *
 * 【垫片口径】只给**类型形状**；运行时函数一律 fail-loud 抛错——本机回路不测 LAN 发现
 * （它需要真机的默认网络与 TCP 栈），真被调到就说明回路走到了不该走的分支，要的是
 * 一句明确的话而不是静默的空结果。与 `@kit.*` 垫片同一纪律（见 networkkit.ts）。
 */
namespace connection {
  export interface NetHandle { netId: number }
  export interface NetAddress { address: string; port?: number; family?: number }
  export interface LinkAddress { address?: NetAddress; prefixLength?: number }
  export interface ConnectionProperties { ifName: string; linkAddresses: LinkAddress[]; mtu: number }
  const STUB = 'LAN 发现垫片：@ohos.net.connection 在 Node 回路里不可用（需要真机网络栈）';
  export function getDefaultNet(): Promise<NetHandle> {
    throw new Error(STUB);
  }
  export function getConnectionProperties(_netHandle: NetHandle): Promise<ConnectionProperties> {
    throw new Error(STUB);
  }
}
export default connection;
