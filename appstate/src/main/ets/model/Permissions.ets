/**
 * 权限预设的**呈现与切换规则**（P7-6，对齐官方 `dsh-client-ui-permission-presets`）。
 *
 * ## 官方怎么做（读它的客户端源码）
 *
 *   1. **当前会话**：把 `/permission` 这条**命令**装饰成 `popupSelect`，选项来自会话的
 *      permissions 投影；选中后执行 **`/permission <presetId>`**（源码原文：
 *      `live.command('/permission ' + option.id)`）；
 *   2. **新会话默认**：`settings.general.item` 里 id=`permission` 的一行，由**设置 schema** 驱动；
 *   3. **没这个能力时**：`available: (session) => selectOf(...) !== void 0` ⇒ 不可用；
 *      设置行显示官方字典里的 `unavailable`（「不可用」）。
 *
 * ## 为什么这里只有"呈现规则"而没有请求构造
 *
 * 切换走的是**既有的命令通道**（`SessionHub.executeCommand`），不需要新端点
 * ⇒ 本文件只回答"界面上该显示什么、能不能点"，判定集中一处、可被 fixture 钉住。
 *
 * ## 实测事实（本机真 Host，见 `tools/check-core-loop.mjs` 的 M2 段）
 *
 * 0.1.5-rc.2 + ondevice profile 上：权限投影 `current=(空) options=0`、命令表 5 条里
 * **没有** `/permission`、12 组设置里**没有**权限相关键 ⇒ 官方那两个入口在这台 Host 上
 * 本来就都不可用。所以端侧**必须**显示「不可用」而不是给一个点了没反应的控件。
 */

/**
 * 单选列表的一项（与 `model/Settings` 的 `SettingChoice` **结构相同**）。
 *
 * 【为什么不 import 那个类型】`Settings.ets` 会把别的模型一起拉进 fixture 编译器，
 * 而这一层只想回答"显示什么、能不能点"。ArkTS 禁结构化类型 ⇒ 调用点构造的是**字面量**，
 * 本来就必须逐字段写出来，所以这边自带一份同样的形状是安全的
 * （字段若漂移，视图侧的 `ChoiceSheet` 会因类型不符当场编译失败）。
 */
export interface PermissionChoice {
  value: string;
  label: string;
}

/** 官方字典里"这台 Host 不支持"的那句话（`unavailable`） */
export const PERMISSION_UNAVAILABLE: string = '不可用';

/** 有投影值但没选：如实说"未设置"，不要拿第一个选项冒充当前值 */
export const PERMISSION_UNSET: string = '未设置';

/** 切换走的就是这条命令（官方原文形式：`/permission <presetId>`） */
export function permissionCommand(presetId: string): string {
  return `/permission ${presetId}`;
}

/** 这台 Host 到底有没有权限预设（官方 `available` 判据的同义物） */
export function permissionSwitchable(options: string[]): boolean {
  return options.length > 0;
}

/** 输入区那颗 chip 的文案：有值给值，没能力给官方那句「不可用」 */
export function permissionChipLabel(current: string, options: string[]): string {
  if (!permissionSwitchable(options)) {
    return PERMISSION_UNAVAILABLE;
  }
  return current.length > 0 ? current : PERMISSION_UNSET;
}

/** 不可用时的**原因**（写在无障碍文案里：不是"还没加载"，是"这台 Host 没有"） */
export function permissionUnavailableHint(): string {
  return '这台 Host 未提供权限预设（权限投影为空且命令表里没有 /permission），因此只能显示、无法切换';
}

/** 选项 → 单选列表（当前项标记由 `ChoiceSheet` 用 `current` 完成） */
export function permissionChoices(options: string[]): PermissionChoice[] {
  const out: PermissionChoice[] = [];
  for (let i = 0; i < options.length; i++) {
    out.push({ value: options[i], label: options[i] });
  }
  return out;
}
