/**
 * MobileTheme —— DSH Mobile 设计 token 移植层（v2 T001）。
 *
 * 【这个文件是什么】手机/折叠闭合形态的**唯一视觉 token 源**（v2 plan R&D-003）：
 * 从克隆源码 `.research/deepseek-harness-mobile/app/src/main/java/com/labteto/dshmobile/ui/theme/`
 * **逐值移植**（只读参照，禁止改动源码），供手机链组件「源码级对照」复刻使用。
 *
 * 【为什么不并进 HarmonyTheme】DSH Mobile 的 Material3 风格自有 token 与官方 web `--dsw-*`
 * 是两套设计语言；强行映射会让手机屏视觉被 web token 绑架，违背「逐屏对照一致」的验收口径
 * （plan.md Complexity Tracking 已终裁：独立 token 层）。
 *
 * 【对照源文件映射】（契约要求：头注释标注对照源码路径）
 *   · ① 原语色板        ← Color.kt `object Ds`
 *   · ② 语义色板（明/暗）← Color.kt `object DsLight` / `object DsDark` + Theme.kt `DsColors`/`DsThemeTokens`
 *   · ③ Material3 角色   ← Theme.kt `materialLightScheme()` / `materialDarkScheme()`
 *   · ④ 间距阶梯         ← Spacing.kt `object DsSpacing`
 *   · ⑤ 圆角阶梯         ← Shape.kt `object DsShapes` / `DsMaterialShapes`
 *   · ⑥ 字阶             ← Type.kt `object DsType` / `DsTypography`
 *   · ⑦ 动效             ← Animation.kt `object DsAnimations` / `Scale`
 *
 * 【移植约定】
 *   · 颜色一律 `number`（0xAARRGGBB）——与 Kotlin `Color(0x…)` 的 ARGB 布局**逐位相同**
 *     （ArkUI 数字色已核实支持 ARGB 格式，见 SDK `common.d.ts` scrollBarColor 文档）；
 *     含半透明 α 的值（如 borderL1 = rgba(0,0,0,.04) → 0x0A000000）原样保留。
 *   · 命名 ArkTS 化（UPPER_SNAKE），与源 token 的对应关系逐组标注；
 *   · 字重用数值（Normal=400 / Medium=500 / SemiBold=600 / Bold=700）——与 HarmonyTheme.TypeRole
 *     同一约定：纯数据、不依赖 ArkUI 枚举，HAR 保持可本机测试。
 */

// ───────────────────────── ① 原语色板（Color.kt `object Ds`，明暗共用） ─────────────────────────

/**
 * 原语色阶：静态基色，明暗两套语义色板都从这里取值。
 * 对照：Color.kt `object Ds`（"Primitive scales (identical in light & dark)"）。
 */
export class DsColor {
  // 中性偏蓝 UI 色阶（Color.kt `Ds.Bluish*`）
  static readonly BLUISH_00: number = 0xFFFFFFFF;
  static readonly BLUISH_50: number = 0xFFF9FAFB;
  static readonly BLUISH_60: number = 0xFFF5F6F7;
  static readonly BLUISH_75: number = 0xFFF1F3F5;
  static readonly BLUISH_100: number = 0xFFEBEEF2;
  static readonly BLUISH_150: number = 0xFFE9ECF2;
  static readonly BLUISH_200: number = 0xFFE1E5EE;
  static readonly BLUISH_300: number = 0xFFCFD3D6;
  static readonly BLUISH_400: number = 0xFFADB2B8;
  static readonly BLUISH_500: number = 0xFF979DA6;
  static readonly BLUISH_600: number = 0xFF81858C;
  static readonly BLUISH_700: number = 0xFF61666B;
  static readonly BLUISH_750: number = 0xFF43454A;
  static readonly BLUISH_800: number = 0xFF353638;
  static readonly BLUISH_850: number = 0xFF2C2C2E;
  static readonly BLUISH_875: number = 0xFF232324;
  static readonly BLUISH_900: number = 0xFF1B1B1C;
  static readonly BLUISH_950: number = 0xFF151517;
  static readonly BLUISH_1000: number = 0xFF0F1115;

  // DeepSeek 品牌蓝（Color.kt `Ds.Deepseek*`）
  static readonly DEEPSEEK_50: number = 0xFFEDF3FE;
  static readonly DEEPSEEK_100: number = 0xFFE4EDFD;
  static readonly DEEPSEEK_200: number = 0xFFD3E2FF;
  static readonly DEEPSEEK_300: number = 0xFFB7C8FE;
  static readonly DEEPSEEK_400: number = 0xFF679EFE;
  static readonly DEEPSEEK_450: number = 0xFF5686FE;
  static readonly DEEPSEEK_500: number = 0xFF4176E6;
  static readonly DEEPSEEK_600: number = 0xFF4868B2;
  static readonly DEEPSEEK_800: number = 0xFF34415B;
  static readonly DEEPSEEK_900: number = 0xFF283142;

  // 语义状态色（Color.kt `Ds.Green*` / `Ds.Red*` / `Ds.Amber*`）
  static readonly GREEN_100: number = 0xFFE6FAED;
  static readonly GREEN_400: number = 0xFF4ED17E;
  static readonly GREEN_500: number = 0xFF22C55E;
  static readonly GREEN_900: number = 0xFF233C2C;
  static readonly RED_50: number = 0xFFFEF2F2;
  static readonly RED_100: number = 0xFFFEE2E2;
  static readonly RED_400: number = 0xFFF25A5A;
  static readonly RED_500: number = 0xFFEF4444;
  static readonly RED_600: number = 0xFFEC1313;
  static readonly RED_900: number = 0xFF570C0C;
  static readonly AMBER_100: number = 0xFFFEF5E7;
  static readonly AMBER_400: number = 0xFFF7AD31;
  static readonly AMBER_500: number = 0xFFF59E0B;
  static readonly AMBER_600: number = 0xFFDD8629;
  static readonly AMBER_900: number = 0xFF27241F;

  // 代码高亮（Color.kt `Ds.Syntax*`，源注释：shiki.css light theme）
  static readonly SYNTAX_CONSTANT: number = 0xFF1C7ED6;
  static readonly SYNTAX_STRING: number = 0xFF2F9E44;
  static readonly SYNTAX_COMMENT: number = 0xFF868E96;
  static readonly SYNTAX_KEYWORD: number = 0xFFD6336C;
  static readonly SYNTAX_PARAMETER: number = 0xFFE8590C;
  static readonly SYNTAX_FUNCTION: number = 0xFF6741D9;
  static readonly SYNTAX_PUNCTUATION: number = 0xFF495057;
  static readonly SYNTAX_LINK: number = 0xFF1971C2;

  // 上下文计量条染色（Color.kt `Ds.Meter*`）
  static readonly METER_SYSTEM: number = 0xFFADB2B8;
  static readonly METER_TOOLS: number = 0xFFA78BFA;
  static readonly METER_MESSAGES: number = 0xFF4D93F8;
}

// ───────────────────────── ② 语义色板（Color.kt `DsLight`/`DsDark`，Theme.kt `DsColors`） ─────────────────────────

/**
 * 一套完整语义色板。
 * 对照：Theme.kt `data class DsColors`（54 个语义槽位），字段名与源码逐一同名（camelCase 保留）。
 */
export interface DsPalette {
  bgBase: number;
  bgLayer1: number;
  bgLayer2: number;
  bgLayer3: number;
  bgModulePlatform: number;
  borderL1: number;
  borderL2: number;
  borderL3: number;
  brandPrimary: number;
  onBrandPrimary: number;
  labelPrimary: number;
  labelSecondary: number;
  labelTertiary: number;
  labelCaption: number;
  labelDimmed: number;
  accent: number;
  onAccent: number;
  accentTertiary: number;
  accentHover: number;
  hover: number;
  hoverSolid: number;
  hoverAccent: number;
  active: number;
  dangerHover: number;
  buttonPrimaryHover: number;
  buttonPrimaryDimmed: number;
  buttonInfoFill: number;
  buttonInfoHover: number;
  error: number;
  errorSecondary: number;
  errorTertiary: number;
  success: number;
  successSecondary: number;
  successTertiary: number;
  warnLabel: number;
  warn: number;
  warnSecondary: number;
  warnTertiary: number;
  toastBg: number;
  tooltipBg: number;
  userBubble: number;
  userBubbleHighlight: number;
  composerCard: number;
  sidebar: number;
  sidebarNavActive: number;
  sidebarNavAccent: number;
  sidebarNavHover: number;
  tipSurface: number;
  codeBlockBg: number;
  codeBlockBanner: number;
  inlineCode: number;
  citation: number;
  markdownTag: number;
  overlayMask: number;
}

/**
 * 浅色语义色板。对照：Color.kt `object DsLight`（Theme.kt `DsThemeTokens.light` 同集）。
 * 引用原语的槽位直接引用 `DsColor.*`（保持源码的派生关系）；源码写死字面量的原样保留。
 */
export const DS_PALETTE_LIGHT: DsPalette = {
  bgBase: DsColor.BLUISH_00,
  bgLayer1: 0xFFFFFFFF,
  bgLayer2: 0xFFFFFFFF,
  bgLayer3: 0xFFFFFFFF,
  bgModulePlatform: DsColor.BLUISH_60,
  borderL1: 0x0A000000, // 源码注释 rgba(0,0,0,.04)
  borderL2: 0x1A000000, // rgba(0,0,0,.10)
  borderL3: 0x1F000000, // rgba(0,0,0,.12)
  brandPrimary: DsColor.BLUISH_1000, // 源码注释：ink button fill
  onBrandPrimary: 0xFFFFFFFF,
  labelPrimary: DsColor.BLUISH_1000,
  labelSecondary: DsColor.BLUISH_700,
  labelTertiary: DsColor.BLUISH_600,
  labelCaption: DsColor.BLUISH_400,
  labelDimmed: DsColor.BLUISH_200,
  accent: DsColor.DEEPSEEK_500,
  onAccent: 0xFFFFFFFF,
  accentTertiary: DsColor.DEEPSEEK_100,
  accentHover: DsColor.DEEPSEEK_400,
  hover: 0x0F263148, // rgba(38,49,72,.06)
  hoverSolid: DsColor.BLUISH_75,
  hoverAccent: 0x24263148, // rgba(38,49,72,.14)
  active: 0x1A263148, // rgba(38,49,72,.10)
  dangerHover: 0x0DEC1313, // rgba(236,19,19,.05)
  buttonPrimaryHover: DsColor.BLUISH_750,
  buttonPrimaryDimmed: DsColor.BLUISH_100,
  buttonInfoFill: DsColor.DEEPSEEK_500,
  buttonInfoHover: DsColor.DEEPSEEK_400,
  error: DsColor.RED_600,
  errorSecondary: DsColor.RED_400,
  errorTertiary: DsColor.RED_50,
  success: DsColor.GREEN_500,
  successSecondary: DsColor.GREEN_400,
  successTertiary: DsColor.GREEN_100,
  warnLabel: DsColor.AMBER_600,
  warn: DsColor.AMBER_500,
  warnSecondary: DsColor.AMBER_400,
  warnTertiary: DsColor.AMBER_100,
  toastBg: DsColor.BLUISH_800,
  tooltipBg: DsColor.BLUISH_850,
  // 源码注释（照录）：比 harness 自己的 `--dsw-specific-bubble`（Deepseek50）深一档，
  // 是全表**唯一一处有意偏离**——web 值对白底只有 1.06:1 对比度，在桌面宽栏里才读得出形状；
  // 手机尺寸与亮度下用户气泡与助手气泡分不开，比"填充色差一档"是更糟的失败。
  userBubble: DsColor.DEEPSEEK_100,
  userBubbleHighlight: DsColor.DEEPSEEK_200,
  composerCard: 0xFFFFFFFF,
  sidebar: DsColor.BLUISH_50,
  sidebarNavActive: DsColor.BLUISH_100,
  sidebarNavAccent: DsColor.DEEPSEEK_100,
  sidebarNavHover: DsColor.BLUISH_75,
  tipSurface: DsColor.BLUISH_60,
  codeBlockBg: DsColor.BLUISH_50,
  codeBlockBanner: DsColor.BLUISH_50,
  inlineCode: DsColor.BLUISH_100,
  citation: DsColor.BLUISH_100,
  markdownTag: DsColor.BLUISH_75,
  overlayMask: 0x3D000000 // rgba(0,0,0,.24)
};

/** 深色语义色板。对照：Color.kt `object DsDark`（Theme.kt `DsThemeTokens.dark` 同集）。 */
export const DS_PALETTE_DARK: DsPalette = {
  bgBase: DsColor.BLUISH_950,
  bgLayer1: DsColor.BLUISH_875,
  bgLayer2: DsColor.BLUISH_850,
  bgLayer3: DsColor.BLUISH_800,
  bgModulePlatform: DsColor.BLUISH_800,
  borderL1: 0x0FFFFFFF, // rgba(255,255,255,.06)
  borderL2: 0x1FFFFFFF, // rgba(255,255,255,.12)
  borderL3: 0x29FFFFFF, // rgba(255,255,255,.16)
  brandPrimary: DsColor.BLUISH_50, // 源码注释：inverted ink button fill
  onBrandPrimary: DsColor.BLUISH_1000,
  labelPrimary: DsColor.BLUISH_50,
  labelSecondary: DsColor.BLUISH_300,
  labelTertiary: DsColor.BLUISH_400,
  labelCaption: DsColor.BLUISH_600,
  labelDimmed: DsColor.BLUISH_750,
  accent: DsColor.DEEPSEEK_400,
  onAccent: 0xFFFFFFFF,
  accentTertiary: DsColor.DEEPSEEK_800,
  accentHover: DsColor.DEEPSEEK_500,
  hover: 0x14FFFFFF, // rgba(255,255,255,.08)
  hoverSolid: DsColor.BLUISH_850,
  hoverAccent: 0x3DFFFFFF, // rgba(255,255,255,.24)
  active: 0x24FFFFFF, // rgba(255,255,255,.14)
  dangerHover: 0x26F25A5A, // rgba(242,90,90,.15)
  buttonPrimaryHover: DsColor.BLUISH_100,
  buttonPrimaryDimmed: DsColor.BLUISH_750,
  buttonInfoFill: DsColor.DEEPSEEK_400,
  buttonInfoHover: DsColor.DEEPSEEK_500,
  error: DsColor.RED_400,
  errorSecondary: DsColor.RED_400,
  errorTertiary: DsColor.RED_900,
  success: DsColor.GREEN_500,
  successSecondary: DsColor.GREEN_400,
  successTertiary: DsColor.GREEN_900,
  warnLabel: DsColor.AMBER_600,
  warn: DsColor.AMBER_500,
  warnSecondary: DsColor.AMBER_400,
  warnTertiary: DsColor.AMBER_900,
  toastBg: DsColor.BLUISH_750,
  tooltipBg: DsColor.BLUISH_750,
  userBubble: DsColor.BLUISH_850,
  userBubbleHighlight: DsColor.BLUISH_750,
  composerCard: DsColor.BLUISH_850,
  sidebar: DsColor.BLUISH_900,
  sidebarNavActive: DsColor.BLUISH_750,
  sidebarNavAccent: DsColor.BLUISH_800,
  sidebarNavHover: DsColor.BLUISH_850,
  tipSurface: DsColor.BLUISH_800,
  codeBlockBg: DsColor.BLUISH_900,
  codeBlockBanner: DsColor.BLUISH_875,
  inlineCode: DsColor.BLUISH_850,
  citation: DsColor.BLUISH_800,
  markdownTag: DsColor.BLUISH_850,
  overlayMask: 0x80000000 // rgba(0,0,0,.5)
};

/**
 * 主题偏好。对照：Theme.kt `enum class ThemePreference { LIGHT, DARK, SYSTEM }`
 * （镜像 harness 的 Appearance 行）。
 */
export enum DsThemePreference {
  LIGHT = 'light',
  DARK = 'dark',
  SYSTEM = 'system'
}

/**
 * 按偏好取语义色板。对照：Theme.kt `DshTheme()` 里的 `when (preference)` 分支——
 * LIGHT→浅、DARK→深、SYSTEM→跟随系统（系统是否深色由调用方传入，本层不读系统状态）。
 */
export function dsPaletteOf(preference: DsThemePreference, systemDark: boolean): DsPalette {
  if (preference === DsThemePreference.LIGHT) {
    return DS_PALETTE_LIGHT;
  }
  if (preference === DsThemePreference.DARK) {
    return DS_PALETTE_DARK;
  }
  return systemDark ? DS_PALETTE_DARK : DS_PALETTE_LIGHT;
}

// ───────────────────────── ③ Material3 语义角色（Theme.kt `materialLightScheme`/`materialDarkScheme`） ─────────────────────────

/**
 * Material3 色彩角色（本工程实际消费的子集）。
 * 对照：Theme.kt `materialLightScheme()` / `materialDarkScheme()`——两个函数**函数体完全相同**
 * （仅 lightColorScheme/darkColorScheme 构造器不同），故这里收敛为一个纯函数 + 两个常量。
 */
export interface DsMaterialScheme {
  primary: number;
  onPrimary: number;
  secondary: number;
  onSecondary: number;
  tertiary: number;
  background: number;
  onBackground: number;
  surface: number;
  onSurface: number;
  surfaceVariant: number;
  onSurfaceVariant: number;
  outline: number;
  outlineVariant: number;
  error: number;
  onError: number;
}

/** 语义色板 → Material3 角色（逐行对照 Theme.kt `materialLightScheme` 的实参表）。 */
export function dsMaterialSchemeOf(c: DsPalette): DsMaterialScheme {
  return {
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.labelSecondary,
    onSecondary: c.bgBase,
    tertiary: c.warn,
    background: c.bgBase,
    onBackground: c.labelPrimary,
    surface: c.bgLayer1,
    onSurface: c.labelPrimary,
    surfaceVariant: c.bgModulePlatform,
    onSurfaceVariant: c.labelSecondary,
    outline: c.borderL2,
    outlineVariant: c.borderL1,
    error: c.error,
    onError: 0xFFFFFFFF // 源码：onError = Color.White
  };
}

/**
 * 浅色 Material3 角色（Theme.kt `materialLightScheme(DsThemeTokens.light)`）。
 *
 * 消费端目前只走 `dsMaterialSchemeOf(palette)` 这条函数，两个常量是"两套主题各自的
 * 角色表"这一移植事实本身。删掉它们会让移植层只剩函数、失去与源文件
 * `materialLightScheme`/`materialDarkScheme` 的一一对应（T001 的对照验收凭据）。
 */
// dead-exempt: T001 验收口径是"全量移植 ui/theme/*.kt"——这四组是移植件（详见各处说明）
export const DS_MATERIAL_LIGHT: DsMaterialScheme = dsMaterialSchemeOf(DS_PALETTE_LIGHT);

/** 深色 Material3 角色（Theme.kt `materialDarkScheme(DsThemeTokens.dark)`）。 */
// dead-exempt: 同 DS_MATERIAL_LIGHT——全量移植的两套角色表之一
export const DS_MATERIAL_DARK: DsMaterialScheme = dsMaterialSchemeOf(DS_PALETTE_DARK);

// ───────────────────────── ④ 间距阶梯（Spacing.kt `object DsSpacing`） ─────────────────────────

/**
 * 间距 token：全 App 布局节奏的唯一来源（源文件头注释："Use these tokens instead of
 * hardcoded dp values to maintain visual consistency"）。单位 vp（源 dp 1:1）。
 */
export class DsSpacing {
  /** 4vp —— 紧邻元素之间（图标与文字） */
  static readonly TINY: number = 4;
  /** 6vp —— 额外小间距 */
  static readonly XSMALL: number = 6;
  /** 8vp —— 组件内相关项的小间距 */
  static readonly SMALL: number = 8;
  /** 8vp —— 紧凑间距（small 的别名） */
  static readonly COMPACT: number = 8;
  /** 12vp —— 组件元素间的中档间距 */
  static readonly MEDIUM: number = 12;
  /** 12vp —— 标准间距（medium 的别名） */
  static readonly STANDARD: number = 12;
  /** 16vp —— 屏幕内距与区块内容的舒适间距 */
  static readonly COMFORTABLE: number = 16;
  /** 20vp —— 主要 UI 区块之间的大间距 */
  static readonly LARGE: number = 20;
  /** 24vp —— 独立内容块的特大间距 */
  static readonly XLARGE: number = 24;
  /** 32vp —— 主要分区（清晰视觉分隔） */
  static readonly XXLARGE: number = 32;
  /** 48vp —— Material 规范的最小触控目标 */
  static readonly TOUCH_TARGET: number = 48;
}

// ───────────────────────── ⑤ 圆角阶梯（Shape.kt `object DsShapes` / `DsMaterialShapes`） ─────────────────────────

/**
 * 圆角 token。对照 Shape.kt 头注释："capsules r18/r22/r24, cards r12, dialogs r24,
 * bubbles r22, code blocks r12, pills r12, tooltips r8, toasts r14, chips r6, tree rows r8"。
 * 单位 vp（源 dp 1:1）。
 */
export class DsShape {
  /** 按钮胶囊 r18 */
  static readonly BUTTON_CAPSULE: number = 18;
  /** 小按钮 r14 */
  static readonly BUTTON_SMALL: number = 14;
  /** 消息气泡 r22 */
  static readonly BUBBLE: number = 22;
  /** 输入区卡片 r22 */
  static readonly COMPOSER: number = 22;
  /** 审批卡 r20 */
  static readonly APPROVAL_CARD: number = 20;
  /** 对话框 r24 */
  static readonly DIALOG: number = 24;
  /** 菜单 r12 */
  static readonly MENU: number = 12;
  /** Toast r14 */
  static readonly TOAST: number = 14;
  /** Tooltip r8 */
  static readonly TOOLTIP: number = 8;
  /** 代码块/卡片 r12 */
  static readonly BLOCK: number = 12;
  /** Pill r12 */
  static readonly PILL: number = 12;
  /** 全圆 pill（源码 999dp 的胶囊哨兵值；消费端可映射为 ArkUI Capsule 形状） */
  static readonly PILL_FULL: number = 999;
  /** Chip r6 */
  static readonly CHIP: number = 6;
  /** 树/列表行 r8 */
  static readonly ROW: number = 8;
  /** 立方卡 r16 */
  static readonly CUBE: number = 16;
}

/**
 * Material3 形状角色。对照 Shape.kt `val DsMaterialShapes = Shapes(…)` 的五档映射。
 *
 * ArkUI 没有 `Shapes(…)` 这个对象，五档角色只能以常量表存在；本端手机链直接取具体档位
 * （`DsShape.BUBBLE` 等），因此这张**角色映射表**没有调用点——但它是"源文件的这五档
 * 确实被移植过"的唯一凭据。
 */
// dead-exempt: 全量移植件（见上）
export class DsMaterialShapes {
  static readonly EXTRA_SMALL: number = DsShape.CHIP;
  static readonly SMALL: number = DsShape.MENU;
  static readonly MEDIUM: number = DsShape.BLOCK;
  static readonly LARGE: number = DsShape.COMPOSER;
  static readonly EXTRA_LARGE: number = DsShape.DIALOG;
}

// ───────────────────────── ⑥ 字阶（Type.kt `object DsType` / `DsTypography`） ─────────────────────────

/**
 * 一档文字 = 字号 + 行高 + 字重 + 是否等宽（四者一起才构成"一种文字"，与
 * HarmonyTheme.TypeRole 同一纪律：不拆散、避免"标题字号配正文行高"的错位）。
 *
 * `mono` 对照 Type.kt 的 `FontFamily.Monospace`（codeFont）：true 时消费端应使用等宽字体栈。
 * 字重为数值：Normal=400 / Medium=500 / SemiBold=600 / Bold=700（对照 Compose FontWeight）。
 */
export interface DsTypeRole {
  size: number;
  lineHeight: number;
  weight: number;
  mono: boolean;
}

/** 字阶 token。对照 Type.kt `object DsType`（源注释：sizes 11..24, system UI stack + mono code stack）。 */
export class DsType {
  // Markdown 角色（Type.kt `// Markdown roles`）
  static readonly MD_H1: DsTypeRole = { size: 24, lineHeight: 34, weight: 700, mono: false };
  static readonly MD_H2: DsTypeRole = { size: 22, lineHeight: 32, weight: 700, mono: false };
  static readonly MD_H3: DsTypeRole = { size: 20, lineHeight: 30, weight: 700, mono: false };
  static readonly MD_H4: DsTypeRole = { size: 16, lineHeight: 28, weight: 600, mono: false };
  static readonly MD_BODY: DsTypeRole = { size: 16, lineHeight: 28, weight: 400, mono: false };
  static readonly MD_SMALL: DsTypeRole = { size: 14, lineHeight: 24, weight: 400, mono: false };
  static readonly MD_CODE: DsTypeRole = { size: 13, lineHeight: 22, weight: 400, mono: true };

  // UI 角色（Type.kt `// UI roles`）
  static readonly DISPLAY_24: DsTypeRole = { size: 24, lineHeight: 32, weight: 600, mono: false };
  static readonly HERO_26: DsTypeRole = { size: 26, lineHeight: 32, weight: 500, mono: false };
  static readonly LARGE_20: DsTypeRole = { size: 20, lineHeight: 28, weight: 500, mono: false };
  static readonly BASE_16: DsTypeRole = { size: 16, lineHeight: 24, weight: 400, mono: false };
  static readonly BASE_16_STRONG: DsTypeRole = { size: 16, lineHeight: 24, weight: 500, mono: false };
  static readonly STD_14: DsTypeRole = { size: 14, lineHeight: 22, weight: 400, mono: false };
  static readonly STD_14_STRONG: DsTypeRole = { size: 14, lineHeight: 22, weight: 500, mono: false };
  static readonly SMALL_13: DsTypeRole = { size: 13, lineHeight: 20, weight: 400, mono: false };
  static readonly SMALL_13_STRONG: DsTypeRole = { size: 13, lineHeight: 20, weight: 500, mono: false };
  static readonly XSMALL_12: DsTypeRole = { size: 12, lineHeight: 18, weight: 400, mono: false };
  static readonly CAPTION_11: DsTypeRole = { size: 11, lineHeight: 14, weight: 400, mono: false };
  static readonly CAPTION_11_STRONG: DsTypeRole = { size: 11, lineHeight: 14, weight: 500, mono: false };

  // 输入区 / 列表行 / 气泡（Type.kt `// Composer / rows / bubbles`）
  static readonly BUBBLE_TEXT: DsTypeRole = { size: 16, lineHeight: 24, weight: 400, mono: false };
  static readonly ROW_TEXT: DsTypeRole = { size: 14, lineHeight: 20, weight: 400, mono: false };
  static readonly TAB_TEXT: DsTypeRole = { size: 13, lineHeight: 16, weight: 500, mono: false };
  static readonly DOCK_TITLE: DsTypeRole = { size: 13, lineHeight: 24, weight: 500, mono: false };
  static readonly STATS_TEXT: DsTypeRole = { size: 12, lineHeight: 20, weight: 400, mono: false };
}

/**
 * Material3 排版角色。对照 Type.kt `val DsTypography = Typography(…)`（尺寸随 DsType，颜色来自 DsPalette）。
 *
 * 同 `DsMaterialShapes`——ArkUI 没有 `Typography(…)`，九档排版角色只能以常量表存在；
 * 手机链取具体字阶（`DsType.STD_14` 等）。
 */
// dead-exempt: 全量移植件（见上）
export class DsTypography {
  static readonly DISPLAY_LARGE: DsTypeRole = DsType.DISPLAY_24;
  static readonly HEADLINE_MEDIUM: DsTypeRole = DsType.LARGE_20;
  static readonly TITLE_MEDIUM: DsTypeRole = DsType.STD_14_STRONG;
  static readonly BODY_LARGE: DsTypeRole = DsType.BASE_16;
  static readonly BODY_MEDIUM: DsTypeRole = DsType.STD_14;
  static readonly BODY_SMALL: DsTypeRole = DsType.SMALL_13;
  static readonly LABEL_LARGE: DsTypeRole = DsType.STD_14_STRONG;
  static readonly LABEL_MEDIUM: DsTypeRole = DsType.SMALL_13_STRONG;
  static readonly LABEL_SMALL: DsTypeRole = DsType.CAPTION_11;
}

// ───────────────────────── ⑦ 动效（Animation.kt `object DsAnimations` / `Scale`） ─────────────────────────

/**
 * 弹簧动效参数。对照 Compose `spring(dampingRatio, stiffness)`：
 * 阻尼比 NoBouncy=1.0 / MediumBouncy=0.5；刚度 High=10000 / Medium=1500 / MediumLow=400。
 * 消费端映射到 ArkUI `curves.springMotion`/`animateTo` 时保留这两个参数的语义。
 */
export interface DsSpringSpec {
  dampingRatio: number;
  stiffness: number;
}

/**
 * 时长补间参数。源码全部 tween 使用 `FastOutSlowInEasing`——此处记为曲线名
 * `'FastOutSlowIn'`（与 ArkUI `Curve.FastOutSlowIn` 同名），消费端直接查表映射。
 */
export interface DsTweenSpec {
  durationMs: number;
  curve: string;
}

/** 源码唯二出现的曲线：FastOutSlowInEasing（所有 tween 共用）。 */
export const DS_EASING_FAST_OUT_SLOW_IN: string = 'FastOutSlowIn';

/**
 * 动效词汇表。对照 Animation.kt `object DsAnimations`（源文件头注释照录："motion
 * explains a change, it does not decorate one"——除加载骨架屏外无任何循环动效）。
 */
export class DsAnimation {
  /** 快而微弹——直接操纵类交互该有的"物理感"（spring<Float> MediumBouncy/High） */
  static readonly FAST_SPRING: DsSpringSpec = { dampingRatio: 0.5, stiffness: 10000 };
  /** 常规过渡默认值：无过冲地落位（spring NoBouncy/Medium） */
  static readonly NORMAL_SPRING: DsSpringSpec = { dampingRatio: 1.0, stiffness: 1500 };
  /** 按钮/pill/图标按钮的按压反馈（spring NoBouncy/High） */
  static readonly PRESS_SCALE: DsSpringSpec = { dampingRatio: 1.0, stiffness: 10000 };
  /** 披露行与 dock 展开：弹而不跳（内容向下生长出现过冲读作故障），线性 tween 又太机械（NoBouncy/MediumLow） */
  static readonly EXPAND: DsSpringSpec = { dampingRatio: 1.0, stiffness: 400 };
  /** 披露行的箭头旋转（tween 180ms FastOutSlowIn） */
  static readonly CHEVRON: DsTweenSpec = { durationMs: 180, curve: DS_EASING_FAST_OUT_SLOW_IN };
  /** 页签与内容切换——短，大列表上长切换等于一次完整重排（tween 150ms） */
  static readonly TAB_SWAP: DsTweenSpec = { durationMs: 150, curve: DS_EASING_FAST_OUT_SLOW_IN };
  /** 懒列表内条目插入/删除/重排的位移动画（spring NoBouncy/MediumLow） */
  static readonly LIST_ITEM: DsSpringSpec = { dampingRatio: 1.0, stiffness: 400 };
  /** 通用透明度变化（tween fadeDuration=150ms） */
  static readonly FADE: DsTweenSpec = { durationMs: 150, curve: DS_EASING_FAST_OUT_SLOW_IN };
  /** 面板滑入——比平台默认快，才跟得上拖拽（tween 220ms） */
  static readonly PANEL_SLIDE: DsTweenSpec = { durationMs: 220, curve: DS_EASING_FAST_OUT_SLOW_IN };

  /** 按压缩放动效时长（Animation.kt `scaleDuration`，ms） */
  static readonly SCALE_DURATION: number = 100;
  /** 透明度动效时长（Animation.kt `fadeDuration`，ms） */
  static readonly FADE_DURATION: number = 150;
  /** 布局变化的标准过渡时长（Animation.kt `transitionDuration`，ms） */
  static readonly TRANSITION_DURATION: number = 200;
}

/** 交互相缩放值。对照 Animation.kt `object Scale`。 */
export class DsScale {
  static readonly NORMAL: number = 1.0;
  static readonly PRESSED: number = 0.95;
}
