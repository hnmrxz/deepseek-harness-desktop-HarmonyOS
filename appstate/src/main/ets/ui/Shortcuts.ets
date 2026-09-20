/**
 * 2in1 / 平板（外接键盘）快捷键表（D3 §5.1）。
 *
 * 本文件是规范的**代码形态**：11 行逐行对应，键位组合与行为描述都照抄规范，不做「优化」。
 * 它是纯数据 + 纯函数，不含任何 ArkUI 依赖——
 * 这样同一张表既能驱动绑定，也能驱动设置页的「快捷键」列表与帮助浮层。
 *
 * 为什么按键平台事实要写进数据（而不是在绑定处静默丢弃）：
 *   ArkUI 的 `keyboardShortcut(value, keys, action)` 有三个硬约束：
 *     1. 修饰键只有 `Ctrl` / `Shift` / `Alt` 三个，**没有** Cmd/Meta；
 *        因此规范里的 `Ctrl/Cmd` 在鸿蒙上只能落成 `Ctrl`（Mac 风格⌘在本平台不存在）。
 *     2. 键必须是**恰好一个**可打印字符，或者一个 `FunctionKey`，可再叠加修饰键。
 *     3. 因此 `Esc`（非 `FunctionKey` 的功能键）与 `Alt + ↑/↓`（方向键不是可打印字符）
 *        **无法**表达成 `keyboardShortcut`，只能走 `onKeyEvent` 自己判键。
 *   如果把这些行悄悄从表里删掉，UI 层就再也看不见它们了；
 *   正确做法是留在表里并打上 `requiresKeyEvent` 标记，让 UI 知道「这行得换条路实现」。
 */

/**
 * 修饰键。
 *
 * 刻意**不复用** ArkUI 的全局 `ModifierKey` 枚举：
 * `appstate` 要能脱离 UI 框架编译与单测，一旦引用 UI 全局枚举，
 * 本文件就只能在 ArkUI 运行时里求值了。由 `entry` 层负责做一次枚举映射。
 */
export enum ShortcutModifier {
  CTRL = 'ctrl',
  SHIFT = 'shift',
  ALT = 'alt'
}

/**
 * 一个快捷键规格（D3 §5.1 的一行）。
 *
 * 字段之间的约束（由 `SHORTCUTS` 的构造纪律保证，见各条注释）：
 *   - `requiresKeyEvent = true` ⇒ 本行无法用 `keyboardShortcut` 绑定；
 *   - `functionKey = true` ⇒ `key` 是功能键名（如 F5），`modifiers` 一般为空；
 *   - `key` 是**恰好一个字符**（可打印字符行）或功能键名（`functionKey` 行）。
 */
export interface ShortcutSpec {
  /** 稳定 id（供设置页、命令面板与测试按 id 查找；不含空格与符号） */
  id: string;
  /** 用户可见的键位标签（规范表格「快捷键」列原样，含 `Ctrl/Cmd` 的历史写法） */
  label: string;
  /**
   * 键。
   * 普通行 = 恰好一个可打印字符（`n` / `,` / `+` / `Enter` 这类具名回车单独见下）；
   * 功能键行 = 功能键名（`F5`）。
   */
  key: string;
  /** 修饰键（顺序即展示顺序）；无修饰键时为空数组，**不要**写 undefined */
  modifiers: ShortcutModifier[];
  /** 是否为 ArkUI `FunctionKey` 成员（`F5` 等）；只有这类行允许配合空修饰键绑定 */
  functionKey: boolean;
  /** 是否需要由 `onKeyEvent` 自行判定（`keyboardShortcut` 表达不了本行） */
  requiresKeyEvent: boolean;
  /** 是否仅 2in1 / 平板（外接键盘）可用（D3 §5.1 整节的范围） */
  desktopOnly: boolean;
  /** 行为描述（规范表格「行为」列原样） */
  description: string;
}


/**
 * D3 §5.1 快捷键表。
 *
 * 规模说明（**此处曾写错，数字以实测为准，并已由单测钉住**）：
 *   - 规范 §5.1 的表体是 **12 行**（不是 11 行——旧注释少算了一行）；
 *   - 本数组是 **12 个规格，与规范逐行一一对应**：`Enter` / `Shift+Enter` 是规范里的
 *     **同一行**，本表**不为它单列一行**，而是在键位判定里用方向字段区分
 *     （见 `entry/view/ShortcutKeys.ts` 的 `ShortcutHit.delta`）。
 *     旧注释声称"拆成两个规格、共 13 个"，与数组实际内容不符。
 *
 * 取值说明（逐行核对用）：
 *   - **8 行**可走 `keyboardShortcut`：N / K / F / B / J / `Ctrl+Shift+P` /
 *     `Ctrl+Shift+C` / `Ctrl+,`；
 *   - **3 行**必须 `onKeyEvent`（`keyboardShortcut` 表达不了非可打印键）：
 *     `Enter`（含 `Shift+Enter`）、`Esc`、`Alt+↑/↓`；
 *   - **1 行**是功能键：`F5`（属于 `keyboardShortcut` 可绑定的那一类）。
 *   8 + 3 + 1 = 12，与数组元素数一致，也与规范行数一致。
 *
 * > 这条说明本身是**可验证的**：`LiveWire.test.ets` 断言了 12 = 8 + 3 + 1 的构成。
 * > 写下来是因为"表里到底几行"曾经被注释说错——而它是"规范到底覆盖了多少"的唯一凭据。
 */
export const SHORTCUTS: ShortcutSpec[] = [
  {
    id: 'new-session',
    label: 'Ctrl/Cmd + N',
    key: 'n',
    modifiers: [ShortcutModifier.CTRL],
    functionKey: false,
    requiresKeyEvent: false,
    desktopOnly: true,
    description: '新建会话'
  },
  {
    id: 'command-palette',
    label: 'Ctrl/Cmd + K',
    key: 'k',
    modifiers: [ShortcutModifier.CTRL],
    functionKey: false,
    requiresKeyEvent: false,
    desktopOnly: true,
    description: '全局搜索 / 命令面板'
  },
  {
    id: 'search-in-session',
    label: 'Ctrl/Cmd + F',
    key: 'f',
    modifiers: [ShortcutModifier.CTRL],
    functionKey: false,
    requiresKeyEvent: false,
    desktopOnly: true,
    description: '会话内搜索'
  },
  {
    id: 'toggle-nav',
    label: 'Ctrl/Cmd + B',
    key: 'b',
    modifiers: [ShortcutModifier.CTRL],
    functionKey: false,
    requiresKeyEvent: false,
    desktopOnly: true,
    description: '切换左导航栏'
  },
  {
    id: 'toggle-detail',
    label: 'Ctrl/Cmd + J',
    key: 'j',
    modifiers: [ShortcutModifier.CTRL],
    functionKey: false,
    requiresKeyEvent: false,
    desktopOnly: true,
    description: '切换详情栏'
  },
  {
    id: 'pending-inbox',
    label: 'Ctrl/Cmd + Shift + P',
    key: 'p',
    modifiers: [ShortcutModifier.CTRL, ShortcutModifier.SHIFT],
    functionKey: false,
    requiresKeyEvent: false,
    desktopOnly: true,
    description: '待决聚合'
  },
  {
    id: 'send-message',
    label: 'Enter / Shift+Enter',
    // 键位字段取无修饰的那一个（Enter）；带 Shift 的变体是同一行内的「可反转」行为，
    // 由 entry 层在 onKeyEvent 里按 shift 状态分流，故本表不为它单列一行。
    key: 'Enter',
    modifiers: [],
    functionKey: false,
    requiresKeyEvent: true,
    desktopOnly: true,
    description: '发送 / 换行（可反转）'
  },
  {
    id: 'stop-turn',
    label: 'Esc',
    key: 'Esc',
    modifiers: [],
    functionKey: false,
    requiresKeyEvent: true,
    desktopOnly: true,
    description: '停止当前轮次（弹二次确认）/ 关闭弹层'
  },
  {
    id: 'prev-next-message',
    label: 'Alt + ↑/↓',
    // 一行两个方向：规范把它们放在同一行、同一行为描述里，故本表也保持一行。
    // 方向键不是可打印字符，keyboardShortcut 表达不了，只能 onKeyEvent。
    key: 'ArrowUp/ArrowDown',
    modifiers: [ShortcutModifier.ALT],
    functionKey: false,
    requiresKeyEvent: true,
    desktopOnly: true,
    description: '上一条 / 下一条消息'
  },
  {
    id: 'copy-code-block',
    label: 'Ctrl/Cmd + Shift + C',
    key: 'c',
    modifiers: [ShortcutModifier.CTRL, ShortcutModifier.SHIFT],
    functionKey: false,
    requiresKeyEvent: false,
    desktopOnly: true,
    description: '复制选中代码块（带语言标记）'
  },
  {
    id: 'open-settings',
    label: 'Ctrl/Cmd + ,',
    // 逗号是**可打印字符**，因此这行能正常绑定；
    // 它与「key 必须是单字符」的约束相容，不需要特殊处理。
    key: ',',
    modifiers: [ShortcutModifier.CTRL],
    functionKey: false,
    requiresKeyEvent: false,
    desktopOnly: true,
    description: '打开设置'
  },
  {
    id: 'reconnect',
    label: 'F5',
    key: 'F5',
    // 功能键可以不带修饰键：ArkUI 允许 (FunctionKey.F5, [])，
    // 这正是 F5 与 Esc/方向键的关键差别（后两者不是 FunctionKey 成员）。
    modifiers: [],
    functionKey: true,
    requiresKeyEvent: false,
    desktopOnly: true,
    description: '手动重连'
  }
];

/**
 * 仅 2in1 / 平板（外接键盘）可用的快捷键。
 *
 * 存在理由（D3 §5.1 的节标题就是「2in1 / 平板（外接键盘）」）：
 * 手机上没有物理键盘，这些绑定不应出现在手机的设置页与帮助里。
 * 函数形式（而不是常量过滤结果）是为了让 UI 每次按当前形态取值，
 * 避免模块加载时就把形态固化下来。
 */
// dead-exempt: 帮助浮层（按形态展示快捷键）尚未做；Index.ets 的快捷键绑定处已写明"不在此假装"
export function shortcutsForDesktop(): ShortcutSpec[] {
  const out: ShortcutSpec[] = [];
  for (let i = 0; i < SHORTCUTS.length; i++) {
    if (SHORTCUTS[i].desktopOnly) {
      out.push(SHORTCUTS[i]);
    }
  }
  return out;
}

/**
 * 可以用 ArkUI `keyboardShortcut` 绑定的规格。
 *
 * 过滤条件就是平台的硬约束本身：既不是功能键、也不需要 onKeyEvent，
 * 且键恰好是单字符。留下这个「单字符」判定（而不是只信标记位）是为了让
 * 将来有人往表里加了不符合约束的键时，它会**自动掉出**绑定集合而不是绑定失败。
 *
 * 在 `entry/src/main` 内已无调用点（`DESKTOP_LIKE` 走官方 Web UI，它自带全套快捷键；
 * `PHONE` 无外接键盘范式），保留它的两个理由见下面那行豁免说明。
 */
// dead-exempt: ① 它是**规范表的可验证投影**——`entry/src/ohosTest/ets/test/LiveWire.test.ets` 用它钉住"9 条声明式 + 3 条 onKeyEvent = 12 行"（本门禁语料不含 ohosTest，看不见这个读者）；② 上架期恢复外接键盘支持时，接线位置就是它（`SHORTCUTS` 是真值）
export function keyboardShortcutSpecs(): ShortcutSpec[] {
  const out: ShortcutSpec[] = [];
  for (let i = 0; i < SHORTCUTS.length; i++) {
    const s: ShortcutSpec = SHORTCUTS[i];
    if (s.requiresKeyEvent) {
      continue;
    }
    if (!s.functionKey && s.key.length !== 1) {
      continue;
    }
    out.push(s);
  }
  return out;
}

/**
 * 必须由 `onKeyEvent` 自行判定的规格。
 *
 * `entry` 层拿到这批规格后，只需按 `key` 建一个小映射表，在 `onKeyEvent` 里查表分发；
 * 键位字符串（`Esc` / `ArrowUp` / `Enter`）到 ArkUI `KeyCode` 的翻译刻意留在 UI 层，
 * 使本文件不含任何 UI 框架符号。
 */
// dead-exempt: 按键判定走 KeyCode（ShortcutKeys.ets 说明了为什么表里的按键串表达不了），故这份"需要 onKeyEvent 的规格"没有代码读者
export function keyEventSpecs(): ShortcutSpec[] {
  const out: ShortcutSpec[] = [];
  for (let i = 0; i < SHORTCUTS.length; i++) {
    if (SHORTCUTS[i].requiresKeyEvent) {
      out.push(SHORTCUTS[i]);
    }
  }
  return out;
}

/*
 * 【本轮删除：`findShortcut(id)`（按 id 查规格）】
 *
 * 它是给"按 id 执行某个快捷键"那条原生链路用的（v1 的 `ShortcutKeys.ets` 按 id 分发），
 * 那条链路随 PC 原生链删除（T026）：`DESKTOP_LIKE` 的快捷键由官方 Web UI 自己处理，
 * `PHONE` 没有快捷键范式。删除前实测：整仓（含 `entry/src/ohosTest` 与 `tools/`）
 * 零调用点——它是"已删组件的连带残留"，不是"留着将来用"的词汇表
 * （需要按 id 查的时候，`SHORTCUTS` 与 `keyboardShortcutSpecs` 都还在，一行 filter 就是它）。
 */
