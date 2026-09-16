/**
 * **错误状态的生命周期**（P8-6c）：一条错误提示什么时候该消失。
 *
 * ## 为什么需要一条规则（真实缺陷）
 *
 * 中枢只有一个 `lastError` 槽位，而它被三十多处写：从"地址无法解析"到"这次提示词没被接受"。
 * 界面上那条状态条是**无条件渲染**的 ⇒ 一次"Host 拒绝了这次请求"之后，用户改一改再发、
 * 成功跑完一整轮，**那条红色提示还挂在那里**。用户的合理疑问正是本仓最怕的那种：
 * "我刚才那条到底发出去了没有？"
 *
 * `docs/09-安全与API错误呈现审计.md` §3.4 把这条写成硬要求：
 *   · 新一轮成功后清除旧的 transient error；
 *   · **持久**连接问题只有真正恢复连接后才清除。
 *
 * ## 两种作用域
 *
 * | 作用域 | 例子 | 什么时候消失 |
 * |---|---|---|
 * | `connection`（连接级） | 地址无法解析、令牌无效、事件流终止、连接未建立、当前离线 | **只有真正连上**（`connected`）才消失 |
 * | `action`（动作级） | 发送被拒、修改队列失败、创建会话失败、目录列举失败 | 同类动作**成功**后就该消失（发送被接受、轮次跑完） |
 *
 * 【为什么不能只按错误码判】同一句话可能两种来源都有（例如"未连接：无法…"既是动作的拒绝、
 * 也是连接事实）。所以作用域由**写那句话的地方**决定，而不是事后从文案里猜——
 * 猜文案是本仓反复禁止的做法。
 *
 * 【为什么"轮次跑完"也算一次成功】用户真正关心的是"我这次到底成没成"：
 * 一轮完整跑完（成功收场）比"发送被接受"更强地证明"没问题了"。
 * 但**失败收场不算**：那时错误应该留着（它解释了为什么这一轮失败）。
 */

/** 错误作用域：连接级（只有真正连上才清除） */
export const ERROR_SCOPE_CONNECTION: string = 'connection';
/** 错误作用域：动作级（同类动作成功即清除） */
export const ERROR_SCOPE_ACTION: string = 'action';

/** 触发清理的事件：连接建立 */
export const ERROR_TRIGGER_CONNECTED: string = 'connected';
/** 触发清理的事件：提示词被 Host 接受 */
export const ERROR_TRIGGER_PROMPT_ACCEPTED: string = 'prompt-accepted';
/** 触发清理的事件：一轮**成功**跑完（失败收场不触发，见文件头说明） */
export const ERROR_TRIGGER_TURN_ENDED_OK: string = 'turn-ended-ok';

/**
 * 这个触发事件该不该清掉这条错误。
 *
 * @param scope 错误的作用域（`ERROR_SCOPE_*`）
 * @param trigger 发生了什么（`ERROR_TRIGGER_*`）
 */
export function errorClearedBy(scope: string, trigger: string): boolean {
  if (scope !== ERROR_SCOPE_CONNECTION && scope !== ERROR_SCOPE_ACTION) {
    // 作用域缺失/未知：按**动作级**处理（宁可多清一次，也不要让一条早已过期的提示长期挂着
    // 让用户以为现在还是坏的）。这条默认值是有意的，写在注释里免得被"顺手改成 false"。
    return trigger !== '';
  }
  if (trigger === ERROR_TRIGGER_CONNECTED) {
    // 连上了：连接级与动作级的旧线索都过期了（连接级的那句"连接未建立"更是不再成立）
    return true;
  }
  if (trigger === ERROR_TRIGGER_PROMPT_ACCEPTED || trigger === ERROR_TRIGGER_TURN_ENDED_OK) {
    // 这两件事只证明"这个动作成了"，证明不了"连接问题解决了"
    return scope === ERROR_SCOPE_ACTION;
  }
  return false;
}

/** 这条错误是不是"只有真正连上才会消失"的那种（界面/诊断据此解释它为什么还在） */
export function errorIsConnectionLevel(scope: string): boolean {
  return scope === ERROR_SCOPE_CONNECTION;
}
