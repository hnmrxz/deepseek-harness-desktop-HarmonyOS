/**
 * 载体「接口面」：由兼容面（dshcompat）注入的上游事实。
 *
 * 为什么这样切（回答「方便适配上游升级」）：
 *   `connection` 只提供**机制**——HTTP/WS 载体、信封编解码、cookie、退避、诊断。
 *   它**不含**任何具体端点或路径知识：路径、事件流端点、随机 id 长度等
 *   全部由本接口注入。上游改路径/改端点时，改动落在 dshcompat 一处，
 *   connection 与 UI/状态层零改动。
 */

/** 兼容面必须提供的最小事实集 */
export interface ProtocolSurface {
  /** 一元 RPC channel（如 `/api`） */
  apiChannel: string;
  /** 逻辑流复用 WebSocket 路径（如 `/api/remote.mux`） */
  muxPath: string;
  /** 事件流逻辑端点（如 `$events`） */
  eventsEndpoint: string;
  /** 事件流开流 payload 文本（如 `{"args":{}}`） */
  eventsPayloadJson: string;
  /** 事件 waterfall 结果回送端点（如 `$events/result`） */
  eventsResultEndpoint: string;
  /**
   * **连接级探活**用的逻辑端点。
   *
   * 要求：无副作用、必然应答、参数可重复。由兼容面注入而不是在 connection 里写死——
   * 它是**上游端点名**，属于 `dshcompat` 的事实；connection 只管
   * 「怎么发一帧并等回帧」这个机制（D5 §1 分层纪律）。
   */
  probeEndpoint: string;
  /** 生成 rpcId / streamId 用的随机串长度 */
  idLength: number;
}

/**
 * 兜底默认值（仅用于测试与「未注入」时的安全退化）。
 *
 * 生产路径**必须**显式注入 dshcompat 提供的 surface；
 * 若某次运行真的走到这里，说明装配漏了一处，诊断页会显示出来。
 */
export const FALLBACK_SURFACE: ProtocolSurface = {
  apiChannel: '/api',
  muxPath: '/api/remote.mux',
  eventsEndpoint: '$events',
  eventsPayloadJson: '{"args":{}}',
  eventsResultEndpoint: '$events/result',
  // 与 dshcompat 的 `SETTINGS_DESCRIBE_ENDPOINT` 一致；这里只是兜底值
  probeEndpoint: 'settings/describe',
  idLength: 32
};
