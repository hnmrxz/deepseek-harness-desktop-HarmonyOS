/**
 * 消息图片的**几何判定**（零依赖：不 import 任何 kit，视图只读结论）。
 *
 * 出处：官方 `@deepseek-ai/dsh-client-ui-attachment` 的 `ImageGallery` / `MessageImage` /
 * `singleFit`（`lib/client.js`）与同文件的 CSS 模块：
 *   · 一条消息里**只有一张**图 → `variant = 'single'`，按 `singleFit` 的尺寸大图显示；
 *   · **两张及以上** → `variant = 'tile'`，每张固定 **64×64** 方图（DeepSeek Chat 规则）；
 *   · 画廊是 `flex-wrap` + `gap: 10px`，靠左对齐（用户消息靠右，`data-align=end`）；
 *   · 单图框圆角 16px、最小 44×44（命中区下限），`object-fit: cover` 裁切。
 *
 * 【为什么把数字搬到这里，而不是写在视图里】
 *   `singleFit` 是一段**有边界条件**的纯函数（比例夹到 [0.25, 4]、**绝不放大小图**、
 *   裁切锚点按"很高的图看顶部、很宽的图看左边"）。写在 `@Builder` 里就只能靠肉眼验证；
 *   写成纯函数才能被 `check-layout-fixtures` 用官方同一组输入钉住。
 */

/** 单图尺寸与裁切锚点（锚点是与平台无关的词汇，视图再映射到 ArkUI 的 `ImageFit`） */
export interface SingleImageFit {
  /** 显示宽度（vp） */
  width: number;
  /** 显示高度（vp） */
  height: number;
  /**
   * 裁切锚点（`cover` 时保留哪一侧）：
   * `'top'`（很高的图） / `'start'`（很宽的图） / `'center'`（比例正常）。
   */
  anchor: string;
}

/** 单图外框的最大边长（官方 `singleFit` 的 `240`） */
export const SINGLE_IMAGE_BOX: number = 240;
/** 多图时每张方图的边长（官方 CSS `width:64px;height:64px`） */
export const TILE_IMAGE_SIDE: number = 64;
/** 画廊间距（官方 CSS `gap:10px`） */
export const IMAGE_GALLERY_GAP: number = 10;
/** 命中区下限（官方 CSS `min-width:44px;min-height:44px`） */
export const IMAGE_MIN_HIT: number = 44;
/** 比例夹取区间（官方 `Math.min(4, Math.max(.25, natural))`） */
export const IMAGE_RATIO_MIN: number = 0.25;
export const IMAGE_RATIO_MAX: number = 4;

/**
 * 一张图还是一组图（官方：`images.length === 1 ? 'single' : 'tile'`）。
 *
 * 空组返回 `'tile'`——调用方本就不该渲染空画廊，返回 `'single'` 会让
 * "没有图"和"只有一张图"在判定上撞车。
 */
export function galleryVariantOf(count: number): string {
  return count === 1 ? 'single' : 'tile';
}

/**
 * 单图显示尺寸（官方 `singleFit` 的逐行等价实现）。
 *
 * 尺寸未知（宽或高 ≤ 0）时给 240×240 的方框并居中——**这是官方的兜底分支**
 * （`variant === 'single'` 且 `dimensions === undefined`），不是我们编的。
 */
export function singleImageFit(width: number, height: number): SingleImageFit {
  if (width <= 0 || height <= 0) {
    return { width: SINGLE_IMAGE_BOX, height: SINGLE_IMAGE_BOX, anchor: 'center' };
  }
  const natural: number = width / height;
  let ratio: number = natural;
  if (ratio < IMAGE_RATIO_MIN) {
    ratio = IMAGE_RATIO_MIN;
  }
  if (ratio > IMAGE_RATIO_MAX) {
    ratio = IMAGE_RATIO_MAX;
  }
  let boxWidth: number = SINGLE_IMAGE_BOX;
  let boxHeight: number = SINGLE_IMAGE_BOX;
  if (ratio >= 1) {
    boxHeight = SINGLE_IMAGE_BOX / ratio;
  } else {
    boxWidth = SINGLE_IMAGE_BOX * ratio;
  }
  /*
   * 「绝不放大小图」：scale 封顶 1，且取 `图/框` 两个方向里更小的那个
   * （官方 `Math.min(1, dimensions.width / box.width, dimensions.height / box.height)`）。
   *
   * 【这里曾经写反过】把 `box / width` 当 scale，于是 1000×1000 的大图被算成 58×58
   * （框被"缩"到比自然尺寸小 17 倍），而 100×50 的小图反而被放大到 240×120。
   * 方向一颠倒，**大图变小图、小图变大图**，两个错互相掩护——门禁里那两条断言
   * （大图 240×240、小图原样）就是为这个方向错误准备的。
   */
  let scale: number = 1;
  const byWidth: number = width / boxWidth;
  if (byWidth < scale) {
    scale = byWidth;
  }
  const byHeight: number = height / boxHeight;
  if (byHeight < scale) {
    scale = byHeight;
  }
  let anchor: string = 'center';
  if (natural < IMAGE_RATIO_MIN) {
    anchor = 'top';
  } else if (natural > IMAGE_RATIO_MAX) {
    anchor = 'start';
  }
  return {
    width: Math.max(1, Math.round(boxWidth * scale)),
    height: Math.max(1, Math.round(boxHeight * scale)),
    anchor: anchor
  };
}

/**
 * 一个消息里最多同时展示几张图。
 *
 * 官方**没有**上限（`images.map`）。我们设一个：真机上一次渲染几十张 base64 图会把
 * 内存和首帧都拖垮，而多出来的图对"看懂这条消息"没有增量信息。
 * 超出的部分由视图用一行「还有 N 张」交代——**如实告知，不静默丢弃**。
 */
export const IMAGE_GALLERY_MAX: number = 12;

/** 需要展示的图片张数（≤ 上限） */
export function visibleImageCount(total: number): number {
  return total > IMAGE_GALLERY_MAX ? IMAGE_GALLERY_MAX : total;
}

/** 被折叠掉的图片张数（0 = 没有折叠） */
export function hiddenImageCount(total: number): number {
  return total > IMAGE_GALLERY_MAX ? total - IMAGE_GALLERY_MAX : 0;
}

/* ───────────────────────── 原图预览（灯箱，P9-2） ───────────────────────── */

/**
 * 灯箱内距（官方 CSS `.backdrop{padding:40px}`，四边各 40）。
 *
 * 它与下一行的上限一起构成官方那句 `max-height: calc(100vh - 80px)`（上下各 40）。
 */
export const LIGHTBOX_PADDING: number = 40;
/** 灯箱里图片的最大宽度（官方 CSS `max-width:min(100%,1600px)`） */
export const LIGHTBOX_MAX_WIDTH: number = 1600;

/**
 * 灯箱的三个无障碍文案（**逐字取官方** `dsh-client-ui-conversation` 的中文字典）。
 *
 * 出处（同一段字典）：
 *   `image.preview` = 原图预览        `image.closePreview` = 关闭原图预览
 *   `image.openOriginal` = 查看原图   `image.openOriginalLabel` = `{label}，点击查看原图`
 */
export const IMAGE_PREVIEW_DIALOG: string = '原图预览';
export const IMAGE_CLOSE_PREVIEW: string = '关闭原图预览';
export const IMAGE_OPEN_ORIGINAL: string = '查看原图';

/** 缩略图的无障碍文案（官方 `image.openOriginalLabel` 的模板：`{label}，点击查看原图`） */
export function imageOpenOriginalLabel(label: string): string {
  return label.length > 0 ? `${label}，点击查看原图` : IMAGE_OPEN_ORIGINAL;
}

/**
 * 灯箱里这张图该画多大（官方 CSS 的等价实现）。
 *
 * 官方的规则是三条 CSS 叠出来的：
 *   · `object-fit: contain` —— 等比缩放装进框内；
 *   · `max-width: min(100%, 1600px)` 与 `max-height: calc(100vh - 80px)` —— **只封顶、不放大**：
 *     小图按**原始尺寸**显示（例如 100×50 的图标不会被拉成满屏）；
 *   · 内距 40 —— 上下左右各留 40，所以可用空间是视口减 80。
 *
 * 尺寸未知（宽或高 ≤ 0）时**填满可用空间**：CSS 会等图片加载出自然尺寸再算，
 * 而 ArkUI 这边拿不到"加载完成后的自然尺寸"回调，填满可用空间正好等价于 `contain` 的表现。
 *
 * @param viewportW / viewportH 灯箱可用视口（vp，已减安全区由系统负责）
 * @param imageW / imageH 原图尺寸（像素；未知传 0）
 */
export function lightboxFit(viewportW: number, viewportH: number,
  imageW: number, imageH: number): SingleImageFit {
  const boxWidth: number = Math.max(1, Math.min(viewportW - LIGHTBOX_PADDING * 2, LIGHTBOX_MAX_WIDTH));
  const boxHeight: number = Math.max(1, viewportH - LIGHTBOX_PADDING * 2);
  if (imageW <= 0 || imageH <= 0) {
    // 未知尺寸：填满可用空间（见上面的说明）
    return { width: Math.round(boxWidth), height: Math.round(boxHeight), anchor: 'center' };
  }
  // 只缩不放（`scale` 上限为 1），与官方的 max-width/max-height 语义一致
  const scale: number = Math.min(1, boxWidth / imageW, boxHeight / imageH);
  return {
    width: Math.max(1, Math.round(imageW * scale)),
    height: Math.max(1, Math.round(imageH * scale)),
    anchor: 'center'
  };
}
