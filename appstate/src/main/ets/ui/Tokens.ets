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
  /** 小徽标 / 药丸（P1 补：原先散落着 5/6/9 三种魔数，取出现最多的 6） */
  static readonly XS: number = 6;
  static readonly S: number = 8;
  static readonly M: number = 12;
  static readonly L: number = 16;
}

/**
 * 边框宽度。
 *
 * P1 补：此前代码里散落 7 处 `.borderWidth(1)`。这不是"设计选择"，而是**忘了给它起名**——
 * 一位像素的描边在深浅色下都要清晰，值本身不该由各处自己决定。
 */
export class Border {
  /** 常规分隔线 / 描边（1px）。`MEDIUM` 等更粗的档位**等真有使用者再加**，不预置空 API。 */
  static readonly HAIRLINE: number = 1;
}

/** 字号（D3 §8 字号体系） */
export class Fs {
  static readonly TITLE_L: number = 20;
  static readonly TITLE_M: number = 18;
  static readonly TITLE_S: number = 16;
  static readonly BODY: number = 16;
  static readonly SECONDARY: number = 14;
  static readonly CAPTION: number = 12;
  /**
   * 徽标文字 / 等宽日志行（P1 补）。
   *
   * 【为什么单独一个名字】原先散落 3 处 `.fontSize(10)`（徽标计数、旁路日志的等宽行、
   * "由 Host 维护"脚注）。它比 `CAPTION` 还小一档，是有意的**最小可读档**——
   * 各处自己写 10 会让"到底还有没有更小的档"永远说不清。
   */
  static readonly CAPTION_XS: number = 10;
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
  /** 触摸目标最小高度（无障碍，D3 §7） */
  static readonly TOUCH_MIN: number = 44;
  /**
   * **指针**（鼠标/触控笔）可接受的最小目标（P1.5）。
   *
   * 【为什么要和 TOUCH_MIN 分开】手指与鼠标不是一回事：手指要 44vp 才点得准，
   * 鼠标 24vp 就足够。合成一个数必然二选一——要么桌面端目标过大显得笨重，
   * 要么手机端点不中。P3 接输入模态时按设备取（`HarmonyTouch` 已经分好两个名字）。
   */
  static readonly POINTER_MIN: number = 24;
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
