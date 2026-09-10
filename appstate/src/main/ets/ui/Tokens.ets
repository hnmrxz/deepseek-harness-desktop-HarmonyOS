/**
 * 设计令牌（D3 §8）。
 *
 * 目的：把「尺寸 / 间距 / 圆角 / 动效 / 字号」集中成一处，避免各组件散落魔数。
 * 颜色走系统资源（深浅色自动适配），不在此硬编码色值。
 */

/** 间距（4 的倍数，D3 §8） */
export class Sp {
  static readonly XS: number = 4;
  static readonly S: number = 8;
  static readonly M: number = 12;
  static readonly L: number = 16;
  static readonly XL: number = 24;
}

/** 圆角 */
export class Radius {
  static readonly S: number = 8;
  static readonly M: number = 12;
  static readonly L: number = 16;
}

/** 字号（D3 §8 字号体系） */
export class Fs {
  static readonly TITLE_L: number = 20;
  static readonly TITLE_M: number = 18;
  static readonly TITLE_S: number = 16;
  static readonly BODY: number = 16;
  static readonly SECONDARY: number = 14;
  static readonly CAPTION: number = 12;
}

/** 行高倍数 */
export class Lh {
  static readonly BODY: number = 1.5;
  static readonly TIGHT: number = 1.3;
}

/** 动效时长（毫秒，D3 §8） */
export class Dur {
  static readonly FAST: number = 150;
  static readonly NORMAL: number = 200;
  static readonly PAGE: number = 250;
}

/** 布局尺寸 */
export class Sz {
  /** 导航栏收为图标条时的宽度（D3 §2.1） */
  static readonly NAV_RAIL: number = 56;
  /** 导航栏展开宽度 */
  static readonly NAV_PANEL: number = 240;
  /** 详情栏默认宽度 */
  static readonly DETAIL_PANEL: number = 320;
  /** 详情栏最小宽度 */
  static readonly DETAIL_MIN: number = 260;
  /** 触摸目标最小高度（无障碍） */
  static readonly TOUCH_MIN: number = 44;
}

/** 断点阈值（vp，D3 §2） */
export class Breakpoint {
  /** < 600：单栏（手机） */
  static readonly MD: number = 600;
  /** >= 840：三栏（平板横屏 / 2in1） */
  static readonly LG: number = 840;
}

/** 语义色（映射到系统资源，深浅色自动） */
export class SemanticColor {
  static readonly TEXT_PRIMARY: Resource = $r('sys.color.font_primary');
  static readonly TEXT_SECONDARY: Resource = $r('sys.color.font_secondary');
  static readonly TEXT_TERTIARY: Resource = $r('sys.color.font_tertiary');
  static readonly BG: Resource = $r('sys.color.background_primary');
  static readonly BG_SECONDARY: Resource = $r('sys.color.background_secondary');
  static readonly DIVIDER: Resource = $r('sys.color.comp_divider');
  static readonly BRAND: Resource = $r('sys.color.brand');
  static readonly WARNING: Resource = $r('sys.color.warning');
  static readonly ALERT: Resource = $r('sys.color.alert');
  static readonly CONFIRM: Resource = $r('sys.color.confirm');
}
