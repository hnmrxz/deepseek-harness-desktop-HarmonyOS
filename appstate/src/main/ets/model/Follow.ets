/**
 * 贴底跟随模型（P1 §8：「sticky-follow 独立管理」）。
 *
 * ## 为什么需要它
 *
 * §8 明确要求 sticky-follow **独立管理**。此前它是散在视图里的三处判断：
 *   · `onVisibleRange` 用**几何比较**（可见区间末尾 vs 最后一行）直接赋 `stickToBottom`；
 *   · `onItemsChanged` 读它决定要不要跳到底；
 *   · 定时器读它决定要不要续跑。
 * 三处都合理，但**缺了两种"意图"信号**，于是有两个真实缺陷：
 *
 *   1. **切会话不重置跟随**：在会话 A 上翻过历史（跟随=false）之后切到会话 B，
 *      新会话打开时**不在底部**——用户看到的是 B 的中间某处。切换会话的意图显然是"看最新"。
 *   2. **发送消息不重新跟随**：用户上翻看历史后写一条消息发出去，跟随仍是 false ⇒
 *      回答可能在他看不到的地方出现。
 *
 * 这两个都不是几何问题，是**意图**问题。把它们显式建模成信号（而不是让几何判断顺带管意图），
 * 就是"独立管理"的实际含义。
 *
 * ## 为什么放在 appstate 且是纯函数
 *
 * 转移规则（什么信号把跟随打开、什么关掉）是**判断**，不是渲染。
 * 放这里之后 `tools/check-layout-fixtures.mjs` 能在本机直接执行它们（无需真机）。
 */

/** 影响"是否贴底跟随"的信号 */
export enum FollowSignal {
  /** 用户滚到 / 停在底部 */
  AT_BOTTOM = 'at-bottom',
  /** 用户上翻离开了底部 */
  SCROLLED_AWAY = 'scrolled-away',
  /** 切换会话：新会话应当从最新一条开始看 */
  SESSION_CHANGED = 'session-changed',
  /** 用户发了消息：他在等回答，自然要跟随 */
  USER_SENT = 'user-sent'
}

/**
 * 按信号推进跟随状态。
 *
 * 规则刻意简单到可以一眼看完——跟随状态只有"跟随/不跟随"两态，
 * 复杂化（比如"短暂暂停后恢复"）会让体感变得不可预测。
 */
export function nextFollowing(prev: boolean, signal: FollowSignal): boolean {
  if (signal === FollowSignal.SCROLLED_AWAY) {
    return false;
  }
  // 其余三种都是"想看到最新"的意图，一律打开
  return true;
}

/**
 * 贴底定时器是否该跑。
 *
 * 【为什么需要定时器】流式输出时**条目数不变而正文在长**，只靠"条目数变化"的事件会停在半截
 * （E113 的实测结论）。所以内容变化之外还需要一个周期性的贴底动作。
 * 只在"跟随中 且 会话在跑"时跑：用户上翻就立刻停，不然界面会跟他抢滚动条。
 */
export function followTimerShouldRun(following: boolean, running: boolean): boolean {
  return following && running;
}

/** 新条目到达时是否要跳到底（跟随中才跳；否则会把正在读历史的用户拽走） */
export function shouldJumpOnNewItems(following: boolean): boolean {
  return following;
}

/* ───────────────────────── 离开/回到同一个会话时的滚动位置（P9-6） ───────────────────────── */

/**
 * 上次离开某个会话时，列表顶部那一条的下标。
 *
 * 【为什么是"一个位置"而不是每个会话各记一份】"切到别的会话要不要回到它自己上次的位置"
 * 与本仓既有的明确决定冲突：会话切换的意图是**看最新**（P1 定的，见
 * `ConversationPane.onSessionChanged` 的注释）。所以这一层只服务一种情形——
 * **你离开了这个会话（去设置页、去看文件预览、去别处转一圈），又回到同一个会话**：
 * 那时把你放回原处，比把你甩到底部再让你重新翻一遍要合理得多。
 *
 * `top < 0` 表示"没有记录"（或记录无效），调用方据此走原来的"贴到底部"。
 */
export interface ScrollSpot {
  /** 会话 id（空串 = 没有记录） */
  sessionId: string;
  /** 列表顶部可见条目的下标（`-1` = 没有记录） */
  top: number;
}

/** 空记录 */
export function emptyScrollSpot(): ScrollSpot {
  return { sessionId: '', top: -1 };
}

/**
 * 记下离开时的位置。
 *
 * 【为什么"在底部"不记】贴底跟随是默认行为（新会话、发消息、切会话都回到底部）：
 * 把"我在底部"也记下来的话，回来时那次 restore 与随后的 follow 会互相打架
 * （先滚到底、又被新条目挤走），而"回到底部"本来就是默认动作，不需要记录。
 *
 * @param following 离开时是否处于贴底跟随（true ⇒ 记录被清空）
 */
export function rememberScrollSpot(sessionId: string, top: number, following: boolean): ScrollSpot {
  if (sessionId.length === 0 || top < 0 || following) {
    return emptyScrollSpot();
  }
  return { sessionId: sessionId, top: top };
}

/**
 * 进会话时要不要恢复上次的位置，以及恢复到哪一条。
 *
 * 四条判据缺一不可：
 *   ① 记录里就是这个会话（换了会话 ⇒ 走"看最新"，见上面的说明）；
 *   ② 记的下标还在列表范围内（会话里的条目会随投影变化，越界的下标 `scrollToIndex` 会抛）；
 *   ③ 用户还没有自己滚动过（他自己滚了，就别把他拽回去）；
 *   ④ 列表已经装下了那一条（`itemCount > top`；数据是异步到的，没到就先等）。
 *
 * @returns 要滚到的下标；`-1` = 不恢复（调用方按既有逻辑贴底）
 */
export function scrollRestoreTarget(spot: ScrollSpot, sessionId: string, itemCount: number,
  userScrolled: boolean): number {
  if (userScrolled || spot.top < 0 || spot.sessionId !== sessionId || sessionId.length === 0) {
    return -1;
  }
  if (itemCount <= spot.top) {
    return -1;
  }
  return spot.top;
}
