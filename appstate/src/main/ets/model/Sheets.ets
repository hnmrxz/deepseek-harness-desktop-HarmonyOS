/**
 * 浮层的**结果出口归属**（P2-8，E353）：哪条回执属于哪个浮层。
 *
 * ## 为什么需要一条规则（一个真实的缺陷）
 *
 * 三个浮层（凭据 / 文本设置 / 结构设置）原先**共用**一个 `credentialNote` 与一个
 * `credentialBusy`。两条实测后果：
 *   1. **串浮层**：在凭据浮层里写入失败 → 关掉 → 打开「编辑文本设置」，
 *      那条**凭据的失败文案会出现在文本编辑浮层里**（用户会以为是文本设置写坏了）；
 *   2. **跨浮层置忙**：文本/结构浮层的按钮读的是凭据浮层的忙标志 ⇒ 凭据正在写时，
 *      另一边的按钮也会变灰。
 *
 * 这与设置页那条"回执没有归属域"（E347）**是同一个缺陷类**：一个全局字符串被多个域写、
 * 被多个界面读。修法也一样：**记下归属，只让主人显示它**。
 *
 * ## 判定放纯模型的理由
 *
 * 与 `SettingsDomains` / `SessionContext` 相同：规则要能被 fixture 直接执行。
 * 本文件零依赖。
 */

/** 浮层的三种"有结果出口"的种类（与本仓 `sheetKind()` 的取值同形） */
export const SHEET_NOTE_NONE: string = '';
export const SHEET_NOTE_CREDENTIAL: string = 'credential';
export const SHEET_NOTE_TEXT: string = 'text';
export const SHEET_NOTE_STRUCT: string = 'struct';

/**
 * 这条回执该不该在这个浮层里显示。
 *
 * 【判据只有一条】回执的**归属**必须等于当前浮层的种类。
 * 归属为空串（没人认领：刚关掉某个浮层、或还没写过）⇒ **一律不显示**——
 * 显示一条"不知道谁写的"错误比不显示更糟：用户会照着它去改一个无关的输入。
 *
 * 【为什么不做"谁先谁后"的时间比较】加时间戳只会引入第二个真值（时钟），
 * 而归属本身就是充分条件：写回执的地方一定知道自己是谁。
 */
export function sheetNoteVisible(owner: string, sheetKind: string): boolean {
  return owner.length > 0 && owner === sheetKind;
}

/**
 * 这条回执的文案该不该显示（归属对 + 文案非空）。
 *
 * 【为什么把"非空"也放进模型】界面上是同一处判断（`if (显示) { Text(note) }`）：
 * 把它留成两个条件会让调用点出现"两层 if"，而两处调用点各写一遍就会漂移。
 */
export function sheetNoteText(owner: string, sheetKind: string, note: string): string {
  return sheetNoteVisible(owner, sheetKind) ? note : '';
}

/* ───────────────────────── 关闭语义：未保存的修改不能说没就没（P8-4） ───────────────────────── */

/**
 * 用户**主动**关掉一个可编辑浮层（拖拽下拉 / 点遮罩 / 关闭按钮 / 系统返回）时，
 * 那里面还没提交的内容该怎么办 —— 以及要不要说一句。
 *
 * ## 为什么这是一条规则，而不是"顺手清掉"
 *
 * 三个浮层都是"改一改就写进 Host"的编辑态，而**拖拽关闭极其容易误触**（`dragBar: true`）。
 * 此前用户改完一个数字或一段 JSON、手一滑把浮层拖没了，界面**一句话都不说**：
 *   · 他会以为改动生效了（**假成功**，而真相是根本没写）；
 *   · 或者过一会儿发现值没变，再回来重改一遍（而原因无从得知）。
 * 本仓的纪律是"界面不撒谎"：**放弃了什么，就要说出来**。
 *
 * ## 判据：草稿与"打开时的值"不一致
 *
 * 每个可编辑浮层在打开时都有一个**种子值**（文本/数字设置 = 当前值；结构设置 = 当前 JSON 的
 * 美化形式；凭据 = 空，因为它是只写不回的）。用户改过 ⇒ 草稿 ≠ 种子 ⇒ 关掉就是放弃。
 *
 * 【为什么凭据只看"非空"】密钥是写进去就看不见的（只写不回显），种子恒为空串，
 * 于是"非空即未保存"天然成立，不需要另存一个种子。
 *
 * @param kind 浮层种类（`SHEET_NOTE_CREDENTIAL` / `_TEXT` / `_STRUCT`）
 * @param label 这一项的标题（写进文案，用户才知道放弃的是哪一项）
 * @param draft 当前草稿
 * @param seed 打开时的种子值（凭据固定给空串）
 * @returns 要说的一句话；**没有未保存修改时给空串**（不能每次都弹一句废话）
 */
export function sheetDiscardNotice(kind: string, label: string, draft: string, seed: string): string {
  if (kind === SHEET_NOTE_CREDENTIAL) {
    return draft.length > 0
      ? '已放弃未保存的密钥输入：它没有写入 Host，也没有留在本机。'
      : '';
  }
  if (kind !== SHEET_NOTE_TEXT && kind !== SHEET_NOTE_STRUCT) {
    // 枚举选择 / 目录选择这类浮层没有"未保存内容"可言：选就是选，关就是关
    return '';
  }
  if (draft === seed) {
    return '';
  }
  const what: string = label.length > 0 ? `「${label}」` : '这一项';
  return `已放弃未保存的修改：${what}没有写入 Host（若要保存，请重新打开并提交）。`;
}
