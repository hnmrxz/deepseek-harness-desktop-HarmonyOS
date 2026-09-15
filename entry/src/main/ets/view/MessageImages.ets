/**
 * 消息里的**图片画廊**（P0-3，对齐官方 `conversation.message.images` 槽位）。
 *
 * ## 为什么会有这个组件
 *
 * 会话事件里的图片块只带一个**不透明引用**（`attachment.attachmentId`），字节要另走
 * `session/attachment` 才拿得到。在此之前，投影层把图片块降级成正文里的字面 `[image]`——
 * 真机上用户看到的就是这五个字符，而不是一张图（本仓"有数据、没消费者"的又一例）。
 *
 * ## 呈现规则全部来自官方（`@deepseek-ai/dsh-client-ui-attachment`）
 *
 * 1. **一张图 → 大图**（`singleFit`：最大边 240，比例夹到 [0.25, 4]，**绝不放大小图**）；
 * 2. **两张及以上 → 64×64 方图**（DeepSeek Chat 规则），`flex-wrap` 排列、间距 10vp；
 * 3. 用户消息靠右（官方 `data-align=end`），助手消息靠左；
 * 4. 圆角 16、`object-fit: cover`；比例超界的图保留"信息起点"那一侧
 *    （很高的图看顶部、很宽的图看左边）——ArkUI 没有 `object-position`，
 *    用 `ImageFit` 的对齐变体（`TOP` / `START` / `CENTER`）表达同一件事。
 *
 * 几何判定**不在本文件**：全部由 `appstate` 的 `MessageImage.ets` 给出，
 * 因此可以被 `tools/check-layout-fixtures.mjs` 用官方同一组输入钉住。
 *
 * ## 与官方的一处已知差异（已登记）
 *
 * 官方点击缩略图打开**灯箱**（全屏遮罩 + 原图）。我们改成"就地放大到单图尺寸"：
 * 灯箱需要页面级遮罩与返回键接管，而页面根节点只有**一个** sheet 宿主
 * （见 `Index.ets` 的 `sheetKind()`），把它接进来要动整条宿主链。
 * 就地放大拿到的是同一个结果（看清原图），因此本轮先要这个；
 * 差异记在 `docs/parity-matrix.md` 的 `attachment` 行，与 `deliverables` 的另存/分享同批处理。
 *
 * ## 读取状态只有三种，且都由中枢给出
 *
 * 视图**不持有**任何异步状态机：`imageUrlOf()` 返回可显示 URL（顺带发起一次读取），
 * `imageErrorOf()` 给出失败原因。读完中枢 `notify()`，父组件重画，这里自然拿到 URL。
 * 这样"一张图被读了两次"或"失败后永远转圈"都不可能发生。
 */

import {
  Border, Fs, galleryVariantOf, HarmonyColor, hiddenImageCount, IMAGE_GALLERY_GAP, IMAGE_MIN_HIT,
  Radius, SessionHub, singleImageFit, Sp, TILE_IMAGE_SIDE, visibleImageCount
} from 'appstate';
import type { ImageAttachmentRefValue, SingleImageFit } from 'appstate';

/** 一张缩略图/大图的显示规格（把"几何判定"收成视图只认的一个形状） */
interface ImageBox {
  /** 显示宽度（vp） */
  width: number;
  /** 显示高度（vp） */
  height: number;
  /** 裁切锚点：`'top'` / `'start'` / `'center'` */
  anchor: string;
}

/** 消息里的图片画廊（单图大图 / 多图方图；点击就地放大） */
@Component
export struct MessageImages {
  /** 会话 id：图片读取是**会话作用域授权**的，没有它就取不到字节 */
  @Prop sessionId: string = '';
  /** 本条消息携带的图片（顺序即内容顺序） */
  @Prop images: ImageAttachmentRefValue[] = [];
  /** 是否靠右对齐（用户消息为 true） */
  @Prop alignEnd: boolean = false;
  /** 当前被就地放大的那张（-1 = 没有） */
  @State zoomIndex: number = -1;

  /** 一张图的显示规格（官方 `variant === 'single'` 时按 `singleFit`，否则 64×64 方图） */
  private boxOf(image: ImageAttachmentRefValue, index: number): ImageBox {
    if (galleryVariantOf(this.images.length) === 'single' || index === this.zoomIndex) {
      const fit: SingleImageFit = singleImageFit(image.width, image.height);
      return { width: fit.width, height: fit.height, anchor: fit.anchor };
    }
    return { width: TILE_IMAGE_SIDE, height: TILE_IMAGE_SIDE, anchor: 'center' };
  }

  /** 裁切锚点 → ArkUI 的 `ImageFit`（官方用 CSS `object-position`，这里用对齐变体） */
  private fitOf(anchor: string): ImageFit {
    if (anchor === 'top') {
      return ImageFit.TOP;
    }
    if (anchor === 'start') {
      return ImageFit.START;
    }
    return ImageFit.CENTER;
  }

  /** 可显示 URL（空 = 还在读或读失败）；这一调用**同时发起**读取 */
  private urlOf(image: ImageAttachmentRefValue): string {
    return SessionHub.shared().imageUrlOf(this.sessionId, image.attachmentId);
  }

  /** 读取失败的原因（空 = 没失败） */
  private errorOf(image: ImageAttachmentRefValue): string {
    return SessionHub.shared().imageErrorOf(this.sessionId, image.attachmentId);
  }

  /** 要画出来的那几张（超出上限的部分用一行说明交代，不静默丢弃） */
  private shown(): ImageAttachmentRefValue[] {
    return this.images.slice(0, visibleImageCount(this.images.length));
  }

  /** 一张图的无障碍文案（说不出内容就说它是第几张、多大） */
  private a11yOf(image: ImageAttachmentRefValue, index: number): string {
    const size: string = image.width > 0 && image.height > 0 ? `${image.width}×${image.height}` : '尺寸未知';
    return `第 ${index + 1} 张图片，${size}${image.name.length > 0 ? '，' + image.name : ''}`;
  }

  build() {
    Column({ space: Sp.XS }) {
      // ── 就地放大的那一张（官方是灯箱；差异已登记）──
      if (this.zoomIndex >= 0 && this.zoomIndex < this.images.length) {
        this.zoomPreview(this.images[this.zoomIndex], this.zoomIndex)
      }
      // ── 画廊：官方 `flex-wrap` + `gap:10px`，按角色对齐 ──
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: this.alignEnd ? FlexAlign.End : FlexAlign.Start
      }) {
        ForEach(this.shown(), (image: ImageAttachmentRefValue, index: number) => {
          this.imageFrame(image, index)
        }, (image: ImageAttachmentRefValue, index: number) => `img-${image.attachmentId}-${index}`)
      }
      .width('100%')

      if (hiddenImageCount(this.images.length) > 0) {
        Text(`本条还有 ${hiddenImageCount(this.images.length)} 张图未显示`)
          .fontSize(Fs.CAPTION_XS)
          .fontColor(HarmonyColor.TEXT_TERTIARY)
      }
    }
    .width('100%')
    .alignItems(this.alignEnd ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  /** 就地放大的预览（点击收起） */
  @Builder
  zoomPreview(image: ImageAttachmentRefValue, index: number) {
    this.plainFrame(image, index, true)
  }

  /** 画廊里的一格 */
  @Builder
  imageFrame(image: ImageAttachmentRefValue, index: number) {
    this.plainFrame(image, index, false)
  }

  /**
   * 一格图片的三种状态（已就绪 / 读取中 / 失败可重试）。
   *
   * 三种状态**几何一致**（同一尺寸的框），因此"图从加载中变成就绪"不会让整条消息跳动。
   */
  @Builder
  plainFrame(image: ImageAttachmentRefValue, index: number, zoomed: boolean) {
    if (this.urlOf(image).length > 0) {
      Image(this.urlOf(image))
        .width(this.boxOf(image, index).width)
        .height(this.boxOf(image, index).height)
        .objectFit(this.fitOf(this.boxOf(image, index).anchor))
        .borderRadius(Radius.L)
        .borderWidth(Border.HAIRLINE)
        .borderColor(HarmonyColor.DIVIDER)
        .margin({ right: IMAGE_GALLERY_GAP, bottom: IMAGE_GALLERY_GAP })
        .accessibilityText(this.a11yOf(image, index))
        .onClick(() => {
          // 单图本来就是大图 ⇒ 点击无事可做（避免"点了没反应"的错觉：官方此时开灯箱）
          if (galleryVariantOf(this.images.length) === 'single') {
            return;
          }
          this.zoomIndex = zoomed ? -1 : index;
        })
    } else if (this.errorOf(image).length > 0) {
      Column({ space: Sp.XS }) {
        Text('图片加载失败')
          .fontSize(Fs.CAPTION)
          .fontColor(HarmonyColor.TEXT_TERTIARY)
        Text('点此重试')
          .fontSize(Fs.CAPTION_XS)
          .fontColor(HarmonyColor.TEXT_EMPHASIZE)
      }
      .constraintSize({ minWidth: IMAGE_MIN_HIT, minHeight: IMAGE_MIN_HIT })
      .padding(Sp.XS)
      .borderRadius(Radius.M)
      .borderWidth(Border.HAIRLINE)
      .borderColor(HarmonyColor.DIVIDER)
      .margin({ right: IMAGE_GALLERY_GAP, bottom: IMAGE_GALLERY_GAP })
      .accessibilityText(`图片加载失败：${this.errorOf(image)}，点按重试`)
      .onClick(() => {
        SessionHub.shared().retryImage(this.sessionId, image.attachmentId);
      })
    } else {
      // 读取中：与就绪态同一个框，只是里面写着状态（避免"先小后大"的跳动）
      Stack() {
        Text('加载中…')
          .fontSize(Fs.CAPTION_XS)
          .fontColor(HarmonyColor.TEXT_TERTIARY)
      }
      .width(this.boxOf(image, index).width)
      .height(this.boxOf(image, index).height)
      .borderRadius(Radius.L)
      .backgroundColor(HarmonyColor.SURFACE_TERTIARY)
      .margin({ right: IMAGE_GALLERY_GAP, bottom: IMAGE_GALLERY_GAP })
      .accessibilityText(`图片读取中：${this.a11yOf(image, index)}`)
    }
  }
}
