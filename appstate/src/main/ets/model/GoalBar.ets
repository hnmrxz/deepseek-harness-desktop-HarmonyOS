/**
 * 长期目标栏的**可判定状态**（P7-20，对齐官方 `dsh-client-ui-goal` 的 `GoalBar`）。
 *
 * ## 官方的规则（`lib/types/client/GoalBar.d.ts` 的文档注释，逐字）
 *
 *   > "A present goal shows a goal glyph, a phase label, the truncated objective, and icon
 *   > actions — **resume when paused, edit** (inline form in the same strip), and **clear**.
 *   > Goal creation lives on the `/goal` command, not here: **loading (undefined), no goal
 *   > (null), and complete goals render nothing**."
 *
 * 三件事因此是**规则**、不是观感取舍：
 *   ① **没有目标 / 加载中 / 已完成 ⇒ 整条栏不渲染**（我们此前无论有没有目标都画一行，
 *      空态时写着"该会话当前没有长期目标"——在手机上那就是白占一行）；
 *   ② **phase 决定给哪个动词**：`active` 给「暂停」、`paused` 给「继续」、`blocked` 给原因 +
 *      编辑/清除（受阻不是用户暂停的，给"继续"会误导：它得先解决受阻原因）；
 *   ③ **创建不在这条栏里**（走 `/goal` 命令），所以这里永远不出现"新建目标"。
 *
 * ## 我们仍然保留的一处诚实
 *
 * "读不到"（投影没到 / 形状认不出 / 读失败）与"确实没有目标"是**两件事**：
 * 前者会让用户以为目标丢了。所以状态里带 `note`：只有"读不到"才给一句说明，
 * "确实没有"就**什么都不显示**（与官方一致）。
 *
 * 纯逻辑：不 import 任何 kit，可被 `tools/check-layout-fixtures.mjs` 钉住。
 */

/** 目标相位（上游 `GoalPhase`；'' = Host 没给） */
export const GOAL_PHASE_ACTIVE: string = 'active';
export const GOAL_PHASE_PAUSED: string = 'paused';
export const GOAL_PHASE_BLOCKED: string = 'blocked';
export const GOAL_PHASE_COMPLETE: string = 'complete';

/** 目标栏的状态（视图只读它，不再自己判） */
export interface GoalBarState {
  /** 是否渲染这条栏 */
  visible: boolean;
  /** 相位文案（'' = 不显示标签） */
  phaseLabel: string;
  /** 目标正文（可见时非空） */
  objective: string;
  /** 是否给「暂停」（`active` 时） */
  canPause: boolean;
  /** 是否给「继续」（`paused` 时） */
  canResume: boolean;
  /** 是否给「编辑」（可见时都给：暂停/受阻都能改正文） */
  canEdit: boolean;
  /** 是否给「清除」（可见时都给） */
  canClear: boolean;
  /** 读不到时的说明（'' = 不需要说明） */
  note: string;
}

/** 相位 → 文案（官方 `PHASE_LABELS`：active/paused/blocked 三个键） */
export function goalPhaseLabel(phase: string): string {
  if (phase === GOAL_PHASE_ACTIVE) {
    return '进行中';
  }
  if (phase === GOAL_PHASE_PAUSED) {
    return '已暂停';
  }
  if (phase === GOAL_PHASE_BLOCKED) {
    return '受阻';
  }
  if (phase === GOAL_PHASE_COMPLETE) {
    return '已完成';
  }
  return '';
}

/**
 * 算出目标栏该长什么样。
 *
 * @param present Host 说"有目标"（`projectGoalView().present`）
 * @param objective 目标正文
 * @param phase 相位
 * @param blockedMessage 受阻说明（仅受阻时非空）
 * @param unreadReason **读不到**的原因（'' = 读到了）
 */
export function goalBarStateOf(present: boolean, objective: string, phase: string,
  blockedMessage: string, unreadReason: string): GoalBarState {
  if (unreadReason.length > 0) {
    /*
     * 读不到：**显示一行说明**（这是唯一保留的"空态"渲染）。
     * 理由：把"读不到"说成"没有目标"会让用户以为目标丢了（本仓早先就踩过这条）。
     * 这一行同时也是一句可行动的提示（去诊断页看旁路日志）。
     */
    return {
      visible: true, phaseLabel: '', objective: unreadReason,
      canPause: false, canResume: false, canEdit: false, canClear: false, note: unreadReason
    };
  }
  if (!present || objective.length === 0) {
    // 确实没有目标（或正文是空的）⇒ **整条不渲染**（官方："no goal (null) … render nothing"）
    return {
      visible: false, phaseLabel: '', objective: '',
      canPause: false, canResume: false, canEdit: false, canClear: false, note: ''
    };
  }
  if (phase === GOAL_PHASE_COMPLETE) {
    // 已完成 ⇒ 整条不渲染（官方同上；目标是"做完了"的状态，不需要常驻占位）
    return {
      visible: false, phaseLabel: goalPhaseLabel(phase), objective: objective,
      canPause: false, canResume: false, canEdit: false, canClear: false, note: ''
    };
  }
  /*
   * 可见态。相位未知（Host 没给）时：给「编辑 / 清除」但不给暂停/继续 ——
   * 不知道该给哪个动词时**不给**，而不是猜一个（猜错就是一次误导性的操作）。
   */
  const body: string = blockedMessage.length > 0 ? `${objective}（受阻：${blockedMessage}）` : objective;
  return {
    visible: true,
    phaseLabel: goalPhaseLabel(phase),
    objective: body,
    canPause: phase === GOAL_PHASE_ACTIVE,
    canResume: phase === GOAL_PHASE_PAUSED,
    canEdit: true,
    canClear: true,
    note: ''
  };
}
