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
 * ## 点击缩略图 → 原图预览（灯箱，P9-2）
 *
 * 官方 `ImageLightbox`（`dsh-client-ui-attachment`）的契约逐字：**点缩略图打开"原图预览"**，
 * 它是一个**文档级**（portal）全屏对话框 —— 背景遮罩 + `object-fit: contain` 的原图 +
 * 右上角关闭按钮；**Esc / 点遮罩 / 关闭按钮**都能关；关闭后焦点回到打开它的那个元素；
 * 无障碍名分别是 `image.preview`（对话框）与 `image.closePreview`（关闭按钮）。
 *
 * 【为什么现在才做】上一轮把它记成"需要页面级遮罩 + 返回键接管，而页面根只有一个 sheet 宿主"
 * ——那个判断**错了**：ArkUI 的 `bindContentCover` 就是**本组件自己**能挂的全屏模态
 * （系统提供遮罩、系统返回键接管、`onDisappear` 回调），根本不需要动宿主链。
 * 官方之所以要 portal，是因为它的祖先节点带了 transform/filter 会把固定定位的遮罩困住；
 * 在 ArkUI 里 `bindContentCover` 承担了同一件事。**判断错了就改**——这就是"就地放大"被替换的原因。
 *
 * 一处如实说明：官方灯箱取的是**原图** URL（缩略图可能是另一张更小的图），而我们手上只有
 * Host 给的那一份字节 ⇒ 灯箱与缩略图**同一 URL**，差别只有显示尺寸。
 *
 * ## 读取状态只有三种，且都由中枢给出
 *
 * 视图**不持有**任何异步状态机：`imageUrlOf()` 返回可显示 URL（顺带发起一次读取），
 * `imageErrorOf()` 给出失败原因。读完中枢 `notify()`，父组件重画，这里自然拿到 URL。
 * 这样"一张图被读了两次"或"失败后永远转圈"都不可能发生。
 */

import {
  Border, Fs, galleryVariantOf, HarmonyColor, hiddenImageCount, IMAGE_CLOSE_PREVIEW, IMAGE_GALLERY_GAP,
  IMAGE_MIN_HIT, IMAGE_PREVIEW_DIALOG, imageOpenOriginalLabel, lightboxFit, LIGHTBOX_PADDING,
  HarmonyIconSize, Radius, SessionHub, singleImageFit, Sp, Sz, TILE_IMAGE_SIDE, visibleImageCount
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
  /** 正在灯箱里看的那一张（-1 = 没有）：点了缩略图就开，关了回 -1 */
  @State viewerIndex: number = -1;
  /** 灯箱内容区的实测尺寸（vp）：`lightboxFit` 要用它算"装得进且不放大"的尺寸 */
  @State viewportW: number = 0;
  @State viewportH: number = 0;

  /** 一张图的显示规格（官方 `variant === 'single'` 时按 `singleFit`，否则 64×64 方图） */
  private boxOf(image: ImageAttachmentRefValue, index: number): ImageBox {
    if (galleryVariantOf(this.images.length) === 'single') {
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

  /**
   * 原图预览的内容（官方 `ImageLightbox` 的结构：全屏 + 居中大图 + 右上角关闭）。
   *
   * 【背景用系统语义色，不手写遮罩】`bindContentCover` 是全屏模态，但它自己的
   * `backgroundColor` **默认是白色**（SDK 文档 `BindOptions.backgroundColor`：
   * "Default value: Color.White"）。官方灯箱用的是半透明遮罩 + 模糊，
   * 而本仓 README 第 2 条明令**不许手写 `rgba(...)` 遮罩**（深色主题下观感必然不对）。
   * 折中是：背景取**应用自己的页面底色**（`sys.color.background_primary`，深浅色自动）——
   * 深色主题下与官方观感一致，浅色主题下就是一页干净的图片查看页。差异已登记在矩阵。
   *
   * 【点哪里都能关】官方 "closes on … backdrop press"：整块内容区挂 `onClick` 关闭，
   * 关闭按钮另外给一个显式的（尺寸取本仓的触控下限 `Sz.TOUCH_MIN`，见下面的说明）。
   * 系统返回键由 `bindContentCover` 自己接管（`onDisappear` 里复位状态）。
   */
  @Builder
  lightbox(image: ImageAttachmentRefValue, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        if (this.urlOf(image).length > 0) {
          Image(this.urlOf(image))
            .width(lightboxFit(this.viewportW, this.viewportH, image.width, image.height).width)
            .height(lightboxFit(this.viewportW, this.viewportH, image.width, image.height).height)
            .objectFit(ImageFit.Contain)
            .borderRadius(Radius.L)
            .accessibilityText(imageOpenOriginalLabel(this.a11yOf(image, index)))
        } else {
          Text('图片还没读到：请稍后重试')
            .fontSize(Fs.SECONDARY)
            .fontColor(HarmonyColor.TEXT_TERTIARY)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding(LIGHTBOX_PADDING)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        // 实测可用空间：`lightboxFit` 据此算"装得进且不放大"的尺寸
        this.viewportW = newArea.width as number;
        this.viewportH = newArea.height as number;
      })
      .onClick(() => {
        // 点遮罩关闭（官方行为）
        this.viewerIndex = -1;
      })

      Button() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(HarmonyIconSize.NAV)
      }
      /*
       * 【为什么是 44 而不是官方的 36】官方 CSS 是 36×36，但那是**网页鼠标**的尺寸；
       * 本仓的无障碍下限是 `Sz.TOUCH_MIN = 44`（手指点得中），且这一条比"逐字对齐 CSS"
       * 更重要——关闭按钮点不中会让用户困在灯箱里。差异登记在矩阵的 `attachment` 行。
       */
      .width(Sz.TOUCH_MIN)
      .height(Sz.TOUCH_MIN)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .margin({ top: Sp.M, right: Sp.M })
      .accessibilityText(IMAGE_CLOSE_PREVIEW)
      .onClick(() => {
        this.viewerIndex = -1;
      })
    }
    .width('100%')
    .height('100%')
    .accessibilityText(IMAGE_PREVIEW_DIALOG)
  }

  /** 画廊里的一格 */
  @Builder
  imageFrame(image: ImageAttachmentRefValue, index: number) {
    this.plainFrame(image, index)
  }

  /**
   * 一格图片的三种状态（已就绪 / 读取中 / 失败可重试）。
   *
   * 三种状态**几何一致**（同一尺寸的框），因此"图从加载中变成就绪"不会让整条消息跳动。
   */
  @Builder
  plainFrame(image: ImageAttachmentRefValue, index: number) {
    if (this.urlOf(image).length > 0) {
      Image(this.urlOf(image))
        .width(this.boxOf(image, index).width)
        .height(this.boxOf(image, index).height)
        .objectFit(this.fitOf(this.boxOf(image, index).anchor))
        .borderRadius(Radius.L)
        .borderWidth(Border.HAIRLINE)
        .borderColor(HarmonyColor.DIVIDER)
        .margin({ right: IMAGE_GALLERY_GAP, bottom: IMAGE_GALLERY_GAP })
        .accessibilityText(`${imageOpenOriginalLabel(this.a11yOf(image, index))}`)
        // 单图与方图**都**能点开灯箱（官方：点缩略图打开原图预览）
        .onClick(() => {
          this.viewerIndex = index;
        })
        /*
         * 原图预览挂在**缩略图这个节点**上（ArkUI 允许在任意节点上绑模态）。
         * 【为什么用 bindContentCover 而不是自己写遮罩】它是本组件自己能挂的全屏模态：
         * 系统提供遮罩、**系统返回键自动接管**、`onDisappear` 回调复位状态 ⇒
         * 不必动页面根那个"只有一个 sheet 宿主"的约束（上一轮正是因为误判这一点才没做）。
         */
        .bindContentCover(this.viewerIndex === index, this.lightbox(image, index), {
          modalTransition: ModalTransition.DEFAULT,
          backgroundColor: HarmonyColor.SURFACE,
          onDisappear: () => {
            this.viewerIndex = -1;
          }
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
