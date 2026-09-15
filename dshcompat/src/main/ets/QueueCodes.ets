/**
 * 排队项的两个**良性竞态**（P7-16，零依赖）。
 *
 * ## 为什么它住在 `dshcompat`
 *
 * 因为这两个字符串是**上游事实**（协议层错误码），而本仓有一条架构红线：
 * 上游字面量只允许出现在 `dshcompat`（`tools/arch-check.mjs` 强制）。
 * 我第一版把码写进了 `appstate/model/QueueRace.ets`，门禁当场判红——这是它该做的事。
 * 同时这个文件是**零依赖纯逻辑**，因此可以被 `tools/check-layout-fixtures.mjs` 直接钉住。
 *
 * ## 两个码与触发条件（`dsh-api-session-controller/lib/index.js`，逐字）
 *
 *   ① `session/queue-item-not-found` —— `"queued item is no longer pending"`
 *      （这一行已被 Agent 取走，或已被前一次操作删掉）
 *   ② `session/steer-unavailable` —— `"current turn no longer accepts steering"`，
 *      条件是 `action.kind === 'steer' && (target !== 'next-turn' || agent.status !== 'running')`
 *      ——也就是**轮次刚好结束**
 *
 * ## 官方为什么按"静默收敛"处理（`dsh-client-ui-conversation` 的 steer-all 注释）
 *
 *   > "A turn closing mid-way (`steer-unavailable`) or a row already claimed by the agent
 *   > (`queue-item-not-found`) **converges silently**, while a genuine failure surfaces as
 *   > one composer notice. Repeated triggers … rely on that `queue-item-not-found`
 *   > convergence: the snapshot may still list a row the host already steered, and the
 *   > duplicate strict steer is a silent no-op."
 *
 * 关键在最后一句：**重复触发本来就依赖这个收敛**。界面快照可能比 Host 慢一拍，
 * 把"这一行已经不在了"说成失败，只会让用户去重试、去怀疑网络。
 */

/** 排队项已被取走（不再是待发状态） */
export const QUEUE_ITEM_NOT_FOUND: string = 'session/queue-item-not-found';
/** 当前轮次已不接受插话（轮次刚好结束） */
export const STEER_UNAVAILABLE: string = 'session/steer-unavailable';

/** 竞态的种类（`''` = 不是竞态） */
export const QUEUE_RACE_NONE: string = '';
export const QUEUE_RACE_ITEM_GONE: string = 'item-gone';
export const QUEUE_RACE_STEER_CLOSED: string = 'steer-closed';

/**
 * 判定一个错误码属于哪种竞态（`''` = 不是竞态 ⇒ 调用方照常当失败处理）。
 *
 * 用"种类"而不是布尔：两种竞态对用户说的话不同（一个"已经被处理了"、
 * 一个"现在没有可插话的轮次，消息还在队列里"），调用方需要分得开。
 * 但**文案不在这里**——这一层只管协议事实，用户看的句子写在 `appstate`。
 */
export function queueRaceKind(code: string): string {
  if (code === QUEUE_ITEM_NOT_FOUND) {
    return QUEUE_RACE_ITEM_GONE;
  }
  if (code === STEER_UNAVAILABLE) {
    return QUEUE_RACE_STEER_CLOSED;
  }
  return QUEUE_RACE_NONE;
}

/** 是不是良性竞态（`queueRaceKind` 的布尔包装，供只关心"要不要报错"的调用点用） */
export function isBenignQueueRace(code: string): boolean {
  return queueRaceKind(code) !== QUEUE_RACE_NONE;
}
