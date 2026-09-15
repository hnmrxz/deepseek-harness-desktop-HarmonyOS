/**
 * 输入区附件的**判定与拼装**（零依赖纯逻辑，P0-4）。
 *
 * ## 它解决的两件事
 *
 * 1. **图片可以内联**：上游提示词的内容片段是 `text | image | file` 三选一
 *    （`Wire.PromptContentPart`）。文件走"先上传拿回执、再随消息发 `file` 片段"，
 *    而**图片可以直接内联 base64**（官方 `dsh-client-ui-conversation` 的
 *    `serializeImages()` 就是这条）。此前我们只会走文件那条路，所以`imagePart()`
 *    一直是个没有消费者的导出。
 * 2. **顺序与白名单有官方依据**，不该在 UI 或中枢里各写一遍：
 *    · 官方 `sendSession()`：`content = [...图片片段, ...(text === '' ? [] : [{type:'text', text}])]`
 *      ⇒ **图片在前、正文在后**（同一段源码里两处都是这个顺序）；
 *    · 官方 `imageMediaType(value)`：只接受 `image/png` / `image/jpeg` / `image/webp` /
 *      `image/gif`，其余**抛错**（`UnsupportedImageMediaTypeError`）。
 *      在端侧提前拦下，用户得到的是一句"这张图不支持"，而不是一条 `arguments-invalid`。
 *
 * ## 为什么这些常量不放在 `platform`
 *
 * "多大算太大""哪些类型收"是**产品策略**，不是设备能力——放平台层会让
 * `tools/check-core-loop.mjs` 的垫片跟着长（垫片只该替设备能力），也会让它们无法被 fixture 钉住。
 */

/** 附件种类：文件（先上传拿回执） / 图片（内联 base64） */
export enum AttachmentKind {
  FILE = 'file',
  IMAGE = 'image'
}

/**
 * 上游接受的图片类型（官方 `imageMediaType()` 的四条 case，逐字）。
 * 其余类型上游会**抛错**，所以这里提前拒绝并给出可读原因。
 */
export const SUPPORTED_IMAGE_TYPES: string[] = ['image/png', 'image/jpeg', 'image/webp', 'image/gif'];

/**
 * 我们的**内联图片**上限（字节）。
 *
 * 【为什么比上游的 20 MiB 小】上游的 `imageLimits.maxImageBytes = 20971520` 是
 * **Host 侧**的门槛；而内联图片是**塞进一条 JSON RPC** 发的：base64 膨胀约 33%，
 * 12 MiB 的照片会让请求体涨到约 16 MB，发送耗时与失败后的重试代价都由端侧承担。
 * 手机照片（含 48MP 直出）大多在 3–8 MiB，12 MiB 覆盖得住；再大就让用户先压缩——
 * 这比"发出去卡住十分钟然后超时"诚实得多。
 */
export const MAX_INLINE_IMAGE_BYTES: number = 12 * 1024 * 1024;

/**
 * 从**头部字节**认出图片类型（`''` = 认不出）。
 *
 * 【为什么需要它】系统图库返回的是一个媒体 URI，展示名**不一定**带扩展名
 * （`file://media/Photo/12/IMG_a/IMG_b` 这种形状是存在的）。只按扩展名判断，
 * 一批本来合法的照片会被我们自己的白名单挡回去，而用户看到的是"格式未知"——
 * 这是"用猜的方式做判定"的典型恶果。
 *
 * 【为什么是字节而不是猜】上游自己的注释就是这条纪律：`ImageAttachmentRef.mediaType`
 * 是"**由存储字节验证过的**媒体类型"。这里的四条魔数（PNG/JPEG/GIF/WEBP）都是
 * 公开且稳定的容器签名，认得出就认，认不出就**如实返回空串**（由调用方拒绝并说明）。
 *
 * @param head 文件**开头**若干字节（12 个就够；不足则认不出）
 */
export function sniffImageMediaType(head: number[]): string {
  if (head.length >= 8 && head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4E && head[3] === 0x47
    && head[4] === 0x0D && head[5] === 0x0A && head[6] === 0x1A && head[7] === 0x0A) {
    return 'image/png';
  }
  if (head.length >= 3 && head[0] === 0xFF && head[1] === 0xD8 && head[2] === 0xFF) {
    return 'image/jpeg';
  }
  if (head.length >= 4 && head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x38) {
    return 'image/gif';
  }
  // WEBP 是 RIFF 容器：`RIFF` **** `WEBP`
  if (head.length >= 12 && head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46
    && head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50) {
    return 'image/webp';
  }
  return '';
}

/**
 * 决定一张待内联图片的**最终类型**：名字推断优先，名字不可信时用魔数。
 *
 * 顺序是刻意的：扩展名已经命中白名单就直接用（不读字节、零开销）；
 * 命中不了再看魔数（救回"没有扩展名/扩展名错"的真实照片）。
 */
export function resolveImageMediaType(byName: string, head: number[]): string {
  if (SUPPORTED_IMAGE_TYPES.indexOf(byName) >= 0) {
    return byName;
  }
  return sniffImageMediaType(head);
}

/** 拼装提示词用的**附件草稿**（视图/中枢各自的类型在这里汇合，避免跨层结构类型） */
export interface AttachmentDraftInput {
  /** 行身份：文件是回执 id，图片是客户端生成的草稿 id */
  key: string;
  /** 种类（`AttachmentKind` 的字符串值） */
  kind: string;
  /** 展示名（可空） */
  name: string;
  /** MIME（图片必须命中白名单） */
  mediaType: string;
  /** 精确字节数 */
  bytes: number;
  /** 仅图片：规范 base64（不含 `data:` 前缀） */
  data: string;
  /** 仅文件：上传回执 id */
  receiptId: string;
}

/** 提示词片段的**计划**（与 `Wire.PromptContentPart` 字段同名，但是本层的本地类型） */
export interface AttachmentPartPlan {
  /** `'text'` / `'image'` / `'file'` */
  type: string;
  /** 正文（仅 `text`） */
  text: string;
  /** 图片 MIME（仅 `image`） */
  mediaType: string;
  /** 图片 base64（仅 `image`） */
  data: string;
  /** 展示名（仅 `image`，空 = 不带） */
  name: string;
  /** 回执 id（仅 `file`） */
  receiptId: string;
}

/**
 * 这张图能不能内联（`''` = 可以，否则是给用户看的原因）。
 *
 * 三条判定按"用户最容易理解"的顺序排：类型 → 大小 → 空数据。
 */
export function imageDraftRejection(mediaType: string, bytes: number, base64Length: number): string {
  if (mediaType.length === 0 || SUPPORTED_IMAGE_TYPES.indexOf(mediaType) < 0) {
    return `这张图的格式（${mediaType.length > 0 ? mediaType : '未知'}）不能内联发送——`
      + `只支持 ${SUPPORTED_IMAGE_TYPES.join(' / ')}。`;
  }
  if (bytes > MAX_INLINE_IMAGE_BYTES) {
    return `图片 ${formatBytesOf(bytes)} 超过内联上限 ${formatBytesOf(MAX_INLINE_IMAGE_BYTES)}——`
      + '请先压缩或裁剪后再发送（内联图片会整段随消息走网络，太大必然发送失败）。';
  }
  if (base64Length === 0) {
    return '图片内容为空（读取失败或文件被移动），请重新选择。';
  }
  return '';
}

/** 字节数的可读形式（`MiB`/`KiB`；本层不 import 任何工具模块，自己算） */
export function formatBytesOf(bytes: number): string {
  if (bytes >= 1024 * 1024) {
    return `${Math.round(bytes / (1024 * 1024) * 10) / 10} MiB`;
  }
  if (bytes >= 1024) {
    return `${Math.round(bytes / 1024)} KiB`;
  }
  return `${bytes} B`;
}

/**
 * 附件 + 正文 → 提示词片段计划（**顺序与官方一致**）。
 *
 * 顺序（官方 `sendSession()` 的展开式）：
 *   1. **全部图片**，按用户在附件条里的先后；
 *   2. **正文**（空串则整段不带——官方 `text === '' ? [] : [{type:'text', text}]`）；
 *   3. **文件回执**（按先后）。
 *
 * 【第 3 段的位置为什么保持不变】官方图片那条路已取证"图片在前"；文件回执走的是
 * 另一条链路（`fileUploads/upload` + `file` 片段），其顺序**没有**官方依据可抄，
 * 而本仓既有行为就是"正文之后"。**没有证据就不改**——改了只是换一种猜测。
 *
 * 纯函数：不做 IO、不看全局、不抛错（坏输入只是被跳过并如实体现在结果长度上）。
 */
export function attachmentPlanFor(drafts: AttachmentDraftInput[], text: string): AttachmentPartPlan[] {
  const out: AttachmentPartPlan[] = [];
  for (let i = 0; i < drafts.length; i++) {
    const draft: AttachmentDraftInput = drafts[i];
    if (draft.kind === AttachmentKind.IMAGE && draft.data.length > 0) {
      out.push({
        type: 'image', text: '', mediaType: draft.mediaType, data: draft.data,
        name: draft.name, receiptId: ''
      });
    }
  }
  if (text.length > 0) {
    out.push({ type: 'text', text: text, mediaType: '', data: '', name: '', receiptId: '' });
  }
  for (let i = 0; i < drafts.length; i++) {
    const draft: AttachmentDraftInput = drafts[i];
    if (draft.kind === AttachmentKind.FILE && draft.receiptId.length > 0) {
      out.push({
        type: 'file', text: '', mediaType: '', data: '', name: draft.name,
        receiptId: draft.receiptId
      });
    }
  }
  return out;
}

/**
 * 待发附件里是否有**图片**。
 *
 * 【为什么要单独问这一句】图片内联在消息里 ⇒ **离线时发不出去也存不下**
 * （没有可稍后补发的回执）。中枢据此在离线时明确拒绝，而不是把图片静默丢掉后
 * 只发正文——后者用户会以为图发出去了。
 */
export function hasInlineImage(drafts: AttachmentDraftInput[]): boolean {
  for (let i = 0; i < drafts.length; i++) {
    if (drafts[i].kind === AttachmentKind.IMAGE) {
      return true;
    }
  }
  return false;
}
