/**
 * LAN 发现协议层（DSH Full Parity §FR-034）。
 *
 * ## 职责
 *
 * 在 Wi-Fi 子网内自动发现运行 DSH Host 的设备：
 *   1. 获取本机 Wi-Fi IP 地址
 *   2. 扫描同子网的 DSH 端口（默认 3080）
 *   3. 对每个响应主机执行 readiness 探测（TCP 连接测试）
 *
 * ## 降级策略
 *
 * - 无 Wi-Fi / 无法获取 IP → 返回空列表，界面提示"请确认 Wi-Fi 已连接"
 * - 扫描超时 → 返回已发现的部分结果
 * - 单个主机探测失败 → 跳过，不阻塞其他主机的发现
 *
 * ## 分层说明
 *
 * 本模块位于 connection 层，不依赖 appstate 层。
 * 返回的是轻量的 LanHostRecord（只有 address + readyState），
 * 上层（SessionHub）负责将 LanHostRecord 转换为 RemoteHost 模型。
 */

import connection from '@ohos.net.connection';
import socket from '@ohos.net.socket';
import { Connection } from './Connection';
import { FALLBACK_SURFACE } from './Surface';

/** DSH 默认端口 */
const DSH_DEFAULT_PORT: number = 3080;

/** TCP 连接测试超时（毫秒） */
const TCP_TIMEOUT_MS: number = 2000;

/** 单个子网扫描并发上限（避免瞬间打满文件描述符） */
const SCAN_CONCURRENCY: number = 20;

/** readiness 探测的 HTTP 超时（毫秒） */
const READINESS_TIMEOUT_MS: number = 3000;

/** LAN 发现的主机记录（轻量，不含 appstate 依赖） */
export interface LanHostRecord {
  /** 主机地址（格式 `ip:port` 或 `http://ip:port`） */
  address: string;
  /** 就绪状态：`'ready'` / `'not-ready'` / `'unknown'` */
  readyState: string;
}

/**
 * 扫描 LAN 发现远程主机——入口函数（供 SessionHub.scanLan() 调用）。
 *
 * 流程：获取本机 IP → 推算子网范围 → 逐 IP 扫描端口 → 对可达主机做 readiness 探测。
 * 失败不抛错：返回部分或空列表。
 */
export async function scanLanHosts(): Promise<LanHostRecord[]> {
  const ip: string = await getLocalIp();
  if (ip.length === 0) {
    return [];
  }
  const subnet: string = subnetOf(ip);
  if (subnet.length === 0) {
    return [];
  }
  const reachable: string[] = await scanSubnet(subnet, DSH_DEFAULT_PORT, TCP_TIMEOUT_MS);
  if (reachable.length === 0) {
    return [];
  }
  const hosts: LanHostRecord[] = [];
  for (let i = 0; i < reachable.length; i++) {
    const address: string = reachable[i];
    const readyState: string = await probeReadiness(address);
    const host: LanHostRecord = { address: address, readyState: readyState };
    hosts.push(host);
  }
  return hosts;
}

/**
 * 扫描子网指定端口——返回可达地址列表（格式 `ip:port`）。
 */
export async function scanSubnet(subnet: string, port: number, timeout: number): Promise<string[]> {
  const reachable: string[] = [];
  const total: number = 254;
  let batch: number = 0;
  const batchSize: number = SCAN_CONCURRENCY;

  while (batch * batchSize < total) {
    const start: number = batch * batchSize + 1;
    const end: number = Math.min((batch + 1) * batchSize, total);
    const tasks: Promise<string | null>[] = [];

    for (let i: number = start; i <= end; i++) {
      const ip: string = `${subnet}.${i}`;
      tasks.push(probeTcp(ip, port, timeout));
    }

    const results: (string | null)[] = await PromiseAllSafe(tasks);
    for (let i: number = 0; i < results.length; i++) {
      if (results[i] !== null) {
        reachable.push(results[i] as string);
      }
    }
    batch++;
  }
  return reachable;
}

/**
 * 探测主机就绪状态——TCP 连接测试。
 *
 * 返回 `'ready'` = 端口可达，`'not-ready'` = 端口不可达，`'unknown'` = 探测失败。
 */
export async function probeReadiness(hostAddress: string): Promise<string> {
  try {
    const port: number = extractPort(hostAddress);
    const ip: string = extractIp(hostAddress);
    const canConnect: boolean = await tcpConnectTest(ip, port, READINESS_TIMEOUT_MS);
    return canConnect ? 'ready' : 'not-ready';
  } catch (e) {
    return 'unknown';
  }
}

/**
 * 认证并建立连接——返回已认证的 Connection 实例。
 */
export async function authenticate(hostAddress: string, port: number): Promise<Connection | null> {
  const address: string = hostAddress.indexOf('http') === 0 ? hostAddress : `http://${hostAddress}`;
  const conn: Connection = new Connection({ surface: FALLBACK_SURFACE });
  const configured: Object | undefined = conn.configure(address);
  if (configured === undefined) {
    return null;
  }
  const auth = await conn.authenticate();
  if (!auth.ok) {
    return null;
  }
  return conn;
}

// ───────────────────────── 内部工具函数 ─────────────────────────

/** 获取本机 Wi-Fi IP 地址 */
async function getLocalIp(): Promise<string> {
  try {
    const netHandle: connection.NetHandle = await connection.getDefaultNet();
    const props: connection.ConnectionProperties = await connection.getConnectionProperties(netHandle);
    const linkAddresses: connection.LinkAddress[] = props.linkAddresses;
    if (linkAddresses === undefined || !Array.isArray(linkAddresses)) {
      return '';
    }
    for (let i = 0; i < linkAddresses.length; i++) {
      const addr: connection.LinkAddress = linkAddresses[i];
      const ip: string = addr.address.address;
      if (ip.indexOf('.') >= 0 && ip !== '0.0.0.0' && ip.indexOf('127.') !== 0) {
        return ip;
      }
    }
    return '';
  } catch (e) {
    return '';
  }
}

/** 从 IP 地址推算子网前缀（"192.168.1.42" → "192.168.1"） */
function subnetOf(ip: string): string {
  const parts: string[] = ip.split('.');
  if (parts.length !== 4) {
    return '';
  }
  return `${parts[0]}.${parts[1]}.${parts[2]}`;
}

/** TCP 连接测试——返回 `ip:port` 或 null */
async function probeTcp(ip: string, port: number, timeout: number): Promise<string | null> {
  try {
    const canConnect: boolean = await tcpConnectTest(ip, port, timeout);
    return canConnect ? `${ip}:${port}` : null;
  } catch (e) {
    return null;
  }
}

/** TCP 连接测试——尝试连接指定 IP:Port */
async function tcpConnectTest(ip: string, port: number, timeout: number): Promise<boolean> {
  try {
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    return await new Promise<boolean>((resolve: (value: boolean) => void) => {
      const timer: number = setTimeout(() => {
        try {
          tcp.close();
        } catch (_) {
          // 关闭失败不影响结果
        }
        resolve(false);
      }, timeout);

      try {
        const netAddr: connection.NetAddress = { address: ip, port: port, family: 1 };
        const connectOpts: socket.TCPConnectOptions = {
          address: netAddr
        };
        tcp.connect(connectOpts, () => {
          clearTimeout(timer);
          try {
            tcp.close();
          } catch (_) {
            // 关闭失败不影响结果
          }
          resolve(true);
        });
      } catch (e) {
        clearTimeout(timer);
        resolve(false);
      }
    });
  } catch (e) {
    return false;
  }
}

/** 安全的 Promise.all——单个失败不阻塞 */
async function PromiseAllSafe<T>(tasks: Promise<T>[]): Promise<(T | null)[]> {
  const results: (T | null)[] = [];
  for (let i = 0; i < tasks.length; i++) {
    try {
      results.push(await tasks[i]);
    } catch (e) {
      results.push(null);
    }
  }
  return results;
}

/** 从地址中提取端口号 */
function extractPort(address: string): number {
  const colon: number = address.lastIndexOf(':');
  if (colon < 0) {
    return DSH_DEFAULT_PORT;
  }
  const portStr: string = address.substring(colon + 1);
  const slash: number = portStr.indexOf('/');
  const clean: string = slash >= 0 ? portStr.substring(0, slash) : portStr;
  const port: number = parseInt(clean, 10);
  return isNaN(port) ? DSH_DEFAULT_PORT : port;
}

/** 从地址中提取 IP 地址 */
function extractIp(address: string): string {
  let clean: string = address;
  if (clean.indexOf('http://') === 0) {
    clean = clean.substring(7);
  } else if (clean.indexOf('https://') === 0) {
    clean = clean.substring(8);
  }
  const colon: number = clean.indexOf(':');
  if (colon >= 0) {
    clean = clean.substring(0, colon);
  }
  return clean;
}
