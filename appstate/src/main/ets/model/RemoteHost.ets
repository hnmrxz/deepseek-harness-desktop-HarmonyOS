/**
 * 远程主机实体（DSH Full Parity §FR-032–037）。
 *
 * ## 存在理由
 *
 * 手机端「连接远程」模式需要发现、认证、维护与远程 DSH Host 的连接。
 * 与本机 Host 不同，远程 Host 的生命周期由网络与对端共同决定：
 *   - 发现来源（LAN 扫描 / 手动输入 / 历史记录）
 *   - 认证状态（未认证 → 认证中 → 已认证 / 失败）
 *   - 就绪状态（未知 → 探测中 → 就绪 / 未就绪）
 *   - 最后发现时间（用于排序与"离线多久"提示）
 *
 * ## 为什么是值类型
 *
 * 本模型只做「事实记录」，不含行为；行为在 SessionHub（连接管理）
 * 与 LanDiscovery（扫描/探测/认证）里。纯数据便于快照化与 Facade 模式传递。
 */

/** 主机发现来源 */
export enum HostSource {
  /** LAN 子网扫描自动发现 */
  LAN_SCAN = 'lan-scan',
  /** 用户手动输入 IP:Port */
  MANUAL = 'manual',
  /** 历史连接记录（本地持久化后恢复） */
  HISTORY = 'history'
}

/** 认证状态 */
export enum HostAuthState {
  /** 尚未认证 */
  UNAUTHENTICATED = 'unauthenticated',
  /** 正在认证中 */
  AUTHENTICATING = 'authenticating',
  /** 已认证通过 */
  AUTHENTICATED = 'authenticated',
  /** 认证失败 */
  FAILED = 'failed'
}

/** 就绪状态（readiness 握手结果） */
export enum HostReadyState {
  /** 未知（尚未探测） */
  UNKNOWN = 'unknown',
  /** 正在探测中 */
  PROBING = 'probing',
  /** 已就绪（mux open + $events ready） */
  READY = 'ready',
  /** 未就绪（端口可达但 mux 未开 / $events 未 ready） */
  NOT_READY = 'not-ready'
}

/** 远程主机实体——值类型，不含行为 */
export interface RemoteHost {
  /** 主机地址（IP:Port 或完整 URL） */
  hostAddress: string;
  /** 显示名称（用户可编辑；默认取地址） */
  label: string;
  /** 发现来源 */
  source: HostSource;
  /** 认证状态 */
  authState: HostAuthState;
  /** 就绪状态 */
  readyState: HostReadyState;
  /** 最后发现时间（毫秒时间戳；0 = 尚未发现） */
  lastSeen: number;
}

/** 创建一个默认的远程主机实体（所有字段取零值/初始态） */
export function createRemoteHost(address: string, source: HostSource, label?: string): RemoteHost {
  return {
    hostAddress: address,
    label: label !== undefined && label.length > 0 ? label : address,
    source: source,
    authState: HostAuthState.UNAUTHENTICATED,
    readyState: HostReadyState.UNKNOWN,
    lastSeen: Date.now()
  };
}

/*
 * 【本轮删除：`hostAuthStateLabel`（认证状态的中文名）】
 *
 * 删除依据（不是"没人用"这么弱）：**参照源码里就没有这个界面元素**。
 * `.research/.../ui/screens/connect/ConnectScreen.kt` 的发现卡/历史卡只表达
 * "能不能连"（`ConnectFailure` 十种失败 + 探活结果），认证走的是**一次性 token 对话框**
 * （同一文件 `LaunchTokenDialog`），没有"未认证/认证中/已认证"这类持久状态位。
 * 因此本端把它画出来只会是**凭空多出的一个状态**（而且它与真实的失败态是两套词）。
 * `HostAuthState` 字段与枚举**保留**：它是 `RemoteHost` 实体形状的一部分（协议/快照用）。
 *
 * 就绪状态不同：源码卡上明确有探活结论，`hostReadyStateLabel` 被 `ConnectPane` 消费。
 */

/** 就绪状态的中文名（界面显示） */
export function hostReadyStateLabel(state: HostReadyState): string {
  if (state === HostReadyState.UNKNOWN) {
    return '未知';
  }
  if (state === HostReadyState.PROBING) {
    return '探测中';
  }
  if (state === HostReadyState.READY) {
    return '就绪';
  }
  return '未就绪';
}
