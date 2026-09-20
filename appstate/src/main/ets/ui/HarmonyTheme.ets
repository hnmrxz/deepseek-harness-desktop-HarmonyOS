/**
 * HarmonyTheme —— **Web 语义 → HarmonyOS 视觉**的映射层（P1.5）。
 *
 * ## 为什么要有这一层（而不是继续加 Parity* 令牌）
 *
 * 本项目的对等原则是「**功能与交互语义对齐官方 Web；布局、输入与系统能力按设备适配**」。
 * 落到视觉上有两种做法：
 *   A. 把 Web 的 CSS 像素级翻译成 ArkUI —— 追不上（官方主题一改就重做），且丢掉鸿蒙的原生质感；
 *   B. **产品语义保持 Web，视觉/交互用 HarmonyOS 原生表达** —— 本层就是 B 的落点。
 *
 * 因此这里分成两半：
 *   · **上半：Harmony* 视觉令牌**（Color/Typography/Spacing/Radius/Border/Elevation/Motion/Touch）——
 *     尽量指向**系统语义资源**（`sys.color.*`），于是深浅色、品牌色、无障碍对比由系统保证；
 *   · **下半：`WEB_TOKEN_MAP`** —— 把官方 Web 的语义 token 名映射到上面的视觉令牌，
 *     **一一写在数据里**。官方 Web 更新时，先改这张表，而不是满仓找 `fontSize`。
 *
 * ## 与既有 Tokens.ets 的关系（不重复实现）
 *
 * `Tokens.ets` 是**尺度原语**（Sp/Radius/Border/Fs/Sz/Dur——"有哪些档位"）；
 * 本文件是**语义角色**（"这个位置该用哪一档"）。角色的值**引用原语**，不另立数字。
 *
 * ## 一条硬约束（实测，决定了 Material 层的写法）
 *
 * `$r('sys.color.*')` 的名字**由编译器校验**（注入假名字会 `Unknown resource name` 并 BUILD FAILED）⇒
 * 本文件里出现的每个系统资源名都是**编译期验证过存在**的，不是"看起来像"。
 */

import { Border, Dur, Fs, Lh, Radius, Sp, Sz } from './Tokens';

// ───────────────────────── ① 语义颜色 ─────────────────────────

/**
 * 语义颜色：**角色 → 系统资源**。
 *
 * 只增角色，不增色值。凡是系统已有的语义（正文字阶、表面、描边、状态色、品牌色之上的一层）
 * 一律用 `sys.color.*`，让深浅色/品牌色/对比度**由系统保证**——
 * 手工色值在深色模式下必然有一处看不清，而那是真机上才发现的缺陷。
 */
export class HarmonyColor {
  // 文字阶（三级，够用且不过度分档）
  static readonly TEXT_PRIMARY: Resource = $r('sys.color.font_primary');
  static readonly TEXT_SECONDARY: Resource = $r('sys.color.font_secondary');
  static readonly TEXT_TERTIARY: Resource = $r('sys.color.font_tertiary');
  /** 需要跳出来的文字（标题/强调数字）；比 PRIMARY 更强 */
  static readonly TEXT_EMPHASIZE: Resource = $r('sys.color.font_emphasize');

  // 表面阶（页面底 / 卡片与栏底 / 更高一层）
  static readonly SURFACE: Resource = $r('sys.color.background_primary');
  static readonly SURFACE_RAISED: Resource = $r('sys.color.background_secondary');
  static readonly SURFACE_TERTIARY: Resource = $r('sys.color.comp_background_tertiary');

  // 描边 / 分隔
  static readonly DIVIDER: Resource = $r('sys.color.comp_divider');


  // 状态色（语义，不写死红绿）
  static readonly BRAND: Resource = $r('sys.color.brand');
  static readonly WARNING: Resource = $r('sys.color.warning');
  static readonly ALERT: Resource = $r('sys.color.alert');
  static readonly CONFIRM: Resource = $r('sys.color.confirm');

  /**
   * 「品牌/状态色**之上**」的前景（文字与图标）。
   *
   * 【为什么单独列出来】此前 badge 里直接写 `Color.White`——那在浅色品牌底上或许对，
   * 但换成系统品牌色、深色模式或高对比模式就不一定。系统提供了对应的**前景色**语义，
   * 交给它比手工挑白色更稳（且编译器已校验这两个名字存在）。
   */
  static readonly ON_BRAND_TEXT: Resource = $r('sys.color.font_on_primary');
  static readonly ON_BRAND_ICON: Resource = $r('sys.color.icon_on_primary');
}

// ───────────────────────── ② 排版角色 ─────────────────────────

/**
 * 排版角色（一组"字号 + 行高 + 字重"）。
 *
 * 【为什么不是三个独立令牌】三者一起才构成"一种文字"。分开写必然出现
 * "标题的字号配了正文的行高"这类只在真机上才看得出的错位。
 *
 * `weight` 用**数值**（400/500/600）而不是 `FontWeight` 枚举：数值是 ArkUI 的合法入参，
 * 也让本文件保持**不依赖 ArkUI 枚举**（HAR 里的纯数据更可测）。
 */
export interface TypeRole {
  size: number;
  lineHeight: number;
  weight: number;
}

export class HarmonyType {
  /** 展示级标题（页面大标题；对齐 --dsw-font-display） */
  static readonly DISPLAY: TypeRole = { size: Fs.DISPLAY, lineHeight: Fs.DISPLAY * Lh.TIGHT, weight: 600 };
  /** 页面级标题 */
  static readonly TITLE: TypeRole = { size: Fs.TITLE_L, lineHeight: Fs.TITLE_L * Lh.TIGHT, weight: 600 };
  /** 区块标题 */
  static readonly SUBTITLE: TypeRole = { size: Fs.TITLE_M, lineHeight: Fs.TITLE_M * Lh.TIGHT, weight: 500 };
  /** 正文（会话内容的主字号） */
  static readonly BODY: TypeRole = { size: Fs.BODY, lineHeight: Fs.BODY * Lh.BODY, weight: 400 };
  /** 次要信息（时间、模型名、路径） */
  static readonly CAPTION: TypeRole = { size: Fs.SECONDARY, lineHeight: Fs.SECONDARY * Lh.BODY, weight: 400 };
  /** 标签/徽标文字 */
  static readonly LABEL: TypeRole = { size: Fs.CAPTION, lineHeight: Fs.CAPTION * Lh.TIGHT, weight: 500 };
  /** 最小可读档（徽标计数、等宽日志行） */
  static readonly OVERLINE: TypeRole = { size: Fs.CAPTION_XS, lineHeight: Fs.CAPTION_XS * Lh.TIGHT, weight: 400 };
  /** 等宽代码行（对齐 --dsw-font-code；区别于 OVERLINE 在于字号更大且用于代码块） */
  static readonly CODE: TypeRole = { size: Fs.CODE, lineHeight: Fs.CODE * Lh.BODY, weight: 400 };
}

// ───────────────────────── ③ 空间 / 圆角 / 描边 ─────────────────────────

/**
 * 空间角色：把 `Sp` 的档位**按用途**命名。
 *
 * 【为什么要再包一层】`Sp.M` 只说明"12"，不说明"哪儿该用 12"。工具栏内距、卡片内距、
 * 区块间距是三种不同的用途，混用会让界面节奏散掉；命名后 review 时能一眼看出用错。
 */
export class HarmonySpacing {
  /** 紧邻元素之间（图标与文字） */
  static readonly INLINE: number = Sp.XS;
  /** 控件内距（chip/按钮） */
  static readonly CONTROL_INNER: number = Sp.S;
  /** 容器内距（卡片/面板） */
  static readonly CONTAINER: number = Sp.M;
  /** 区块之间 */
  static readonly SECTION: number = Sp.L;
  /** 页面级留白 */
  static readonly PAGE: number = Sp.XL;
}

/**
 * 图标档位（**只给原语需要的角色**命名）。
 *
 * 【为什么只给一个】现网图标尺寸有 **10 档**裸值（12/14/16/18/20/22/28/32/36/40），
 * 它们的收敛**会改变视觉、需要真机验收**，属待决策项（见矩阵缺口登记）。
 * 若现在就把这 10 档照抄成"令牌"，只是给魔数换个名字，反而把问题藏起来。
 * 因此这里只命名**新原语真正需要的角色**（行内图标），并且取值与现网一致（14 ⇒ 视觉不变）；
 * 其余档位继续留在棘轮基线里，等设计收敛时一次处理。
 */
export class HarmonyIconSize {
  /** 卡片/列表行内的图标（与现网工具卡的 14 一致） */
  static readonly INLINE: number = 14;
  /**
   * 导航面板里的图标（侧栏完整面板）。
   *
   * 【为什么要单列】导航图标比行内图标大一号才站得住（原实现写死 20），
   * 而"写死 20"正是设计令牌棘轮要挡的裸值——搬到 shell 后不再有祖父条款，
   * 故在这里给它一个名字。
   */
  static readonly NAV: number = 20;
  /** 导航 rail / 底部标签栏里的图标（比面板里再大一号：没有文字陪伴，图标要更醒目） */
  static readonly NAV_RAIL: number = 22;
  /** 状态提示图标（横幅里的警示符号等；原实现写死 16） */
  static readonly STATUS: number = 16;
}

/** 圆角角色（值引用原语，不另立数字） */
export class HarmonyRadius {
  /** 药丸/小徽标 */
  static readonly CHIP: number = Radius.XS;
  /** 控件（输入框、按钮） */
  static readonly CONTROL: number = Radius.S;
  /** 卡片 / 浮层 */
  static readonly SURFACE: number = Radius.M;
  /** 大面板 / Sheet */
  static readonly PANEL: number = Radius.L;
}

/** 描边角色 */
export class HarmonyBorder {
  /** 分隔线 / 常规描边 */
  static readonly HAIRLINE: number = Border.HAIRLINE;
}

/**
 * 阴影层级。
 *
 * 【为什么用数据而不是直接 `.shadow(…)`】层级是**设计决定**（哪一层更"高"），
 * 具体阴影参数是实现细节。集中成数据后，改成系统材质或统一调参只动一处。
 */
export interface ShadowLevel {
  radius: number;
  offsetY: number;
  /** 透明度（0–1）；越高的层级越明显 */
  alpha: number;
}

export class HarmonyElevation {
  /** 贴地（列表项、内联卡片）：几乎只有一层分隔感 */
  static readonly FLAT: ShadowLevel = { radius: 4, offsetY: 1, alpha: 0.04 };
  /** 抬起（Composer、浮动操作区） */
  static readonly RAISED: ShadowLevel = { radius: 12, offsetY: 4, alpha: 0.10 };
  /** 悬浮（Popup / 菜单 / Sheet） */
  static readonly OVERLAY: ShadowLevel = { radius: 24, offsetY: 8, alpha: 0.16 };
  /** 高悬浮（模态对话框 / 全屏 Sheet；对齐 DSH --dsw-shadow-3） */
  static readonly MODAL: ShadowLevel = { radius: 32, offsetY: 12, alpha: 0.22 };
}

// ───────────────────────── ③b 材质（Material） ─────────────────────────

// ───────────────────────── ④ 动效 ─────────────────────────

/**
 * 动效时长角色（毫秒）与**意图**。
 *
 * 曲线不在这里定：`Curve` 是 ArkUI 的枚举，放在视图层选择（保持本文件不依赖 ArkUI 枚举）。
 * 这里只固定"多快"——时长不统一时，界面会显得同一个动作时快时慢。
 */
export class HarmonyMotion {
  /** 状态切换（按压、选中）：要"立刻" */
  static readonly STATE: number = Dur.FAST;
  /** 常规过渡（展开/折叠、淡入淡出） */
  static readonly TRANSITION: number = Dur.NORMAL;
  /** 层级切换（页面/面板进出） */
  static readonly ENTER: number = Dur.PAGE;
}

// ───────────────────────── ⑤ 触控 ─────────────────────────

/**
 * 触控目标与指针目标的尺寸角色（计划 §7 无障碍 + P3 输入模态）。
 *
 * 【为什么要区分】**手指与鼠标不是一回事**：手指需要 ≥44vp（`Sz.TOUCH_MIN`，系统无障碍底线），
 * 而鼠标指针可以接受更小的目标。把两者写成两个名字，P3 接输入模态时才有地方可改，
 * 而不是到处找魔数。
 */
export class HarmonyTouch {
  /** 手指可及的最小目标（无障碍底线） */
  static readonly MIN_TARGET: number = Sz.TOUCH_MIN;
  /** 图标按钮的目标尺寸（比图标本身大一圈，保证可点） */
  static readonly ICON_TARGET: number = Sz.TOUCH_MIN;
  /** 指针（鼠标/触控笔）可接受的最小目标 */
  static readonly MIN_TARGET_POINTER: number = Sz.POINTER_MIN;
}

// ───────────────────────── ⑥ Web 语义 → Harmony 视觉（映射表） ─────────────────────────

/**
 * 一行映射：官方 Web 的语义 token → 本层的视觉令牌。
 *
 * 【为什么做成数据而不是注释】官方 Web 的主题**会变**。把映射写成可枚举的数据，
 * 升级时"改了哪几处"是可核对、可测试的（fixture 会检查每条映射都填齐）；
 * 写在注释里则一定会随代码漂移。
 *
 * `web` 用官方 `--dsw-*` 的语义名（`ui-theme` 包的令牌族），`harmony` 写本文件的令牌路径。
 */
export interface WebTokenMapping {
  /** 官方 Web 语义 token（`--dsw-*` 族） */
  web: string;
  /** 本层对应的 HarmonyOS 视觉令牌（写成路径便于核对） */
  harmony: string;
  /** 一句话说明"为什么这样对应"（尤其是不 1:1 的地方） */
  note: string;
}

// dead-exempt: 文档化数据（官方 --dsw-* → 本仓令牌的逐条对照）；parity-matrix 已登记"还没有强制门禁"，给它与人与文档核对用
export const WEB_TOKEN_MAP: WebTokenMapping[] = [
  // ── 色板 ──
  { web: '--dsw-color-bg', harmony: 'HarmonyColor.SURFACE', note: '页面底色 → 系统 background_primary（深浅色自动）' },
  { web: '--dsw-color-bg-elevated', harmony: 'HarmonyColor.SURFACE_RAISED', note: '抬起的栏/卡片 → background_secondary' },
  { web: '--dsw-color-bg-secondary', harmony: 'HarmonyColor.SURFACE_TERTIARY', note: '次级背景 → comp_background_tertiary' },
  { web: '--dsw-color-bg-inverse', harmony: 'HarmonyColor.BRAND', note: '反色背景（Toast/高亮条）→ 品牌色' },
  { web: '--dsw-color-text', harmony: 'HarmonyColor.TEXT_PRIMARY', note: '正文主色 → font_primary' },
  { web: '--dsw-color-text-weak', harmony: 'HarmonyColor.TEXT_SECONDARY', note: '次要信息 → font_secondary' },
  { web: '--dsw-color-text-faint', harmony: 'HarmonyColor.TEXT_TERTIARY', note: '最弱信息（提示/占位）→ font_tertiary' },
  { web: '--dsw-color-text-inverse', harmony: 'HarmonyColor.ON_BRAND_TEXT', note: '反色背景上的文字 → font_on_primary' },
  { web: '--dsw-color-text-on-brand', harmony: 'HarmonyColor.ON_BRAND_TEXT', note: '品牌色上的文字 → font_on_primary' },
  { web: '--dsw-color-icon-on-brand', harmony: 'HarmonyColor.ON_BRAND_ICON', note: '品牌色上的图标 → icon_on_primary' },
  { web: '--dsw-color-border', harmony: 'HarmonyColor.DIVIDER', note: '分隔线 → comp_divider（鸿蒙的分隔语义只有一档）' },
  { web: '--dsw-color-border-weak', harmony: 'HarmonyColor.DIVIDER', note: '弱分隔线 → comp_divider（鸿蒙不分强弱分隔）' },
  { web: '--dsw-color-brand', harmony: 'HarmonyColor.BRAND', note: '品牌色 → sys.color.brand（跟随系统主题）' },
  { web: '--dsw-color-danger', harmony: 'HarmonyColor.ALERT', note: '危险 → alert' },
  { web: '--dsw-color-warning', harmony: 'HarmonyColor.WARNING', note: '警告 → warning' },
  { web: '--dsw-color-success', harmony: 'HarmonyColor.CONFIRM', note: '成功 → confirm' },
  { web: '--dsw-color-info', harmony: 'HarmonyColor.BRAND', note: '信息 → brand（鸿蒙无独立 info 色）' },
  { web: '--dsw-color-surface-dim', harmony: 'HarmonyColor.SURFACE', note: '低亮度表面 → background_primary' },
  { web: '--dsw-color-surface-bright', harmony: 'HarmonyColor.SURFACE_RAISED', note: '高亮度表面 → background_secondary' },
  { web: '--dsw-color-surface-container', harmony: 'HarmonyColor.SURFACE_TERTIARY', note: '容器表面 → comp_background_tertiary' },
  { web: '--dsw-color-surface-container-low', harmony: 'HarmonyColor.SURFACE', note: '低层级容器 → background_primary' },
  { web: '--dsw-color-surface-container-high', harmony: 'HarmonyColor.SURFACE_RAISED', note: '高层级容器 → background_secondary' },
  { web: '--dsw-color-on-surface', harmony: 'HarmonyColor.TEXT_PRIMARY', note: '表面上文字 → font_primary' },
  { web: '--dsw-color-on-surface-variant', harmony: 'HarmonyColor.TEXT_SECONDARY', note: '表面上次要文字 → font_secondary' },
  { web: '--dsw-color-outline', harmony: 'HarmonyColor.DIVIDER', note: '描边/轮廓 → comp_divider' },
  { web: '--dsw-color-outline-variant', harmony: 'HarmonyColor.DIVIDER', note: '弱描边 → comp_divider' },
  { web: '--dsw-color-error', harmony: 'HarmonyColor.ALERT', note: '错误 → alert' },
  { web: '--dsw-color-on-error', harmony: 'HarmonyColor.ON_BRAND_TEXT', note: '错误上的文字 → font_on_primary' },
  { web: '--dsw-color-chip-bg', harmony: 'HarmonyColor.SURFACE_TERTIARY', note: 'Chip 背景 → comp_background_tertiary' },
  { web: '--dsw-color-chip-border', harmony: 'HarmonyColor.DIVIDER', note: 'Chip 描边 → comp_divider' },
  { web: '--dsw-color-chip-text', harmony: 'HarmonyColor.TEXT_PRIMARY', note: 'Chip 文字 → font_primary' },
  { web: '--dsw-color-badge-bg', harmony: 'HarmonyColor.BRAND', note: '徽标背景 → brand' },
  { web: '--dsw-color-badge-text', harmony: 'HarmonyColor.ON_BRAND_TEXT', note: '徽标文字 → font_on_primary' },
  { web: '--dsw-color-toolbar-bg', harmony: 'HarmonyColor.SURFACE', note: '工具栏背景 → background_primary' },
  { web: '--dsw-color-input-bg', harmony: 'HarmonyColor.SURFACE_RAISED', note: '输入框背景 → background_secondary' },
  { web: '--dsw-color-input-border', harmony: 'HarmonyColor.DIVIDER', note: '输入框描边 → comp_divider' },
  { web: '--dsw-color-code-bg', harmony: 'HarmonyColor.SURFACE_TERTIARY', note: '代码块背景 → comp_background_tertiary' },
  { web: '--dsw-color-scrollbar', harmony: 'HarmonyColor.TEXT_TERTIARY', note: '滚动条 → font_tertiary（低对比度）' },
  { web: '--dsw-color-selection', harmony: 'HarmonyColor.BRAND', note: '选区 → brand' },
  { web: '--dsw-color-hover', harmony: 'HarmonyColor.SURFACE_TERTIARY', note: '悬浮态 → comp_background_tertiary' },
  { web: '--dsw-color-active', harmony: 'HarmonyColor.SURFACE_RAISED', note: '激活态 → background_secondary' },
  { web: '--dsw-color-focus-ring', harmony: 'HarmonyColor.BRAND', note: '焦点环 → brand' },

  // ── 排版 ──
  { web: '--dsw-font-display', harmony: 'HarmonyType.DISPLAY', note: '展示级标题（新增 DISPLAY 角色覆盖 --dsw-font-display）' },
  { web: '--dsw-font-title', harmony: 'HarmonyType.TITLE', note: '标题' },
  { web: '--dsw-font-subtitle', harmony: 'HarmonyType.SUBTITLE', note: '区块标题 → SUBTITLE' },
  { web: '--dsw-font-body', harmony: 'HarmonyType.BODY', note: '正文字号+行高+字重**成套**映射（Web 是三属性，鸿蒙这里是一个角色）' },
  { web: '--dsw-font-body-small', harmony: 'HarmonyType.CAPTION', note: '小号正文 → CAPTION' },
  { web: '--dsw-font-label', harmony: 'HarmonyType.LABEL', note: '标签/徽标；鸿蒙侧字重更高（小字号下更清晰）' },
  { web: '--dsw-font-overline', harmony: 'HarmonyType.OVERLINE', note: '标注/overline → OVERLINE' },
  { web: '--dsw-font-caption', harmony: 'HarmonyType.OVERLINE', note: '辅助说明 → OVERLINE（同 overline 档位）' },
  { web: '--dsw-font-code', harmony: 'HarmonyType.CODE', note: '等宽代码 → CODE（新增 CODE 角色，字号 Fs.CODE）' },
  { web: '--dsw-font-size-display', harmony: 'Fs.DISPLAY', note: '展示字号原语 → 24' },
  { web: '--dsw-font-size-title', harmony: 'Fs.TITLE_L', note: '标题字号原语 → 20' },
  { web: '--dsw-font-size-body', harmony: 'Fs.BODY', note: '正文字号原语 → 16' },
  { web: '--dsw-font-size-small', harmony: 'Fs.SECONDARY', note: '小字号原语 → 14' },
  { web: '--dsw-font-size-caption', harmony: 'Fs.CAPTION', note: '说明字号原语 → 12' },
  { web: '--dsw-font-size-overline', harmony: 'Fs.CAPTION_XS', note: '最小字号原语 → 10' },
  { web: '--dsw-font-size-code', harmony: 'Fs.CODE', note: '代码字号原语 → 13' },
  { web: '--dsw-line-height-tight', harmony: 'Lh.TIGHT', note: '紧凑行高 → 1.3' },
  { web: '--dsw-line-height-normal', harmony: 'Lh.BODY', note: '常规行高 → 1.5' },

  // ── 间距 ──
  { web: '--dsw-space-0', harmony: 'Sp.XXS', note: '0/1px 极小间距 → 1' },
  { web: '--dsw-space-1', harmony: 'Sp.XXS', note: '1/4 基础间距 → 4' },
  { web: '--dsw-space-2', harmony: 'HarmonySpacing.INLINE', note: '行内间隙 → 4（Sp.XS）' },
  { web: '--dsw-space-3', harmony: 'HarmonySpacing.CONTROL_INNER', note: '控件内距 → 8（Sp.S）' },
  { web: '--dsw-space-4', harmony: 'HarmonySpacing.CONTAINER', note: '容器内距 → 12（Sp.M）' },
  { web: '--dsw-space-5', harmony: 'Sp.L', note: '中等间距 → 16' },
  { web: '--dsw-space-6', harmony: 'Sp.XL', note: '较大间距 → 24' },
  { web: '--dsw-space-8', harmony: 'Sp.XXL', note: '大间距 → 32' },
  { web: '--dsw-space-10', harmony: 'Sp.XXXL', note: '超大间距 → 48' },

  // ── 圆角 ──
  { web: '--dsw-radius-none', harmony: 'Radius.NONE', note: '无圆角 → 0' },
  { web: '--dsw-radius-xs', harmony: 'Radius.XS', note: '极小圆角 → 6' },
  { web: '--dsw-radius-sm', harmony: 'HarmonyRadius.CHIP', note: '小圆角/药丸 → 6（Radius.XS）' },
  { web: '--dsw-radius-md', harmony: 'HarmonyRadius.SURFACE', note: 'Web 的中圆角 → 鸿蒙卡片圆角' },
  { web: '--dsw-radius-lg', harmony: 'HarmonyRadius.PANEL', note: '大圆角 → 面板圆角' },
  { web: '--dsw-radius-pill', harmony: 'HarmonyRadius.CHIP', note: '药丸 → chip 圆角' },
  { web: '--dsw-radius-full', harmony: 'Radius.XXL', note: '全圆角 → 24' },

  // ── 阴影 ──
  { web: '--dsw-shadow-0', harmony: 'HarmonyElevation.FLAT', note: '无阴影 → 贴地' },
  { web: '--dsw-shadow-1', harmony: 'HarmonyElevation.RAISED', note: 'Web 的 box-shadow 层级 → 鸿蒙阴影层级（更克制）' },
  { web: '--dsw-shadow-2', harmony: 'HarmonyElevation.RAISED', note: 'Web 二级阴影 → 鸿蒙 RAISED（比 Web 更克制）' },
  { web: '--dsw-shadow-3', harmony: 'HarmonyElevation.OVERLAY', note: 'Web 三级阴影 → 鸿蒙 OVERLAY' },

  // ── 动效 ──
  { web: '--dsw-duration-instant', harmony: 'Dur.INSTANT', note: '瞬时 → 50ms' },
  { web: '--dsw-duration-fast', harmony: 'HarmonyMotion.STATE', note: '状态切换时长 → 150ms' },
  { web: '--dsw-duration-normal', harmony: 'HarmonyMotion.TRANSITION', note: '常规过渡时长 → 200ms' },
  { web: '--dsw-duration-slow', harmony: 'Dur.SLOW', note: '慢速过渡 → 350ms' },

  // ── 描边 ──
  { web: '--dsw-border-width', harmony: 'HarmonyBorder.HAIRLINE', note: '常规描边宽度 → 1' },

  // ── 尺寸 ──
  { web: '--dsw-icon-inline', harmony: 'HarmonyIconSize.INLINE', note: '行内图标 → 14' },
  { web: '--dsw-icon-nav', harmony: 'HarmonyIconSize.NAV', note: '导航图标 → 20' },
  { web: '--dsw-touch-min', harmony: 'Sz.TOUCH_MIN', note: '最小触控目标 → 44' },
  { web: '--dsw-pointer-min', harmony: 'Sz.POINTER_MIN', note: '最小指针目标 → 24' },
  { web: '--dsw-nav-rail-width', harmony: 'Sz.NAV_RAIL', note: '导航栏收为图标条时的宽度 → 56' },
  { web: '--dsw-nav-panel-width', harmony: 'Sz.NAV_PANEL', note: '导航栏展开宽度 → 240' },
  { web: '--dsw-detail-panel-width', harmony: 'Sz.DETAIL_PANEL', note: '详情栏默认宽度 → 320' }
];
