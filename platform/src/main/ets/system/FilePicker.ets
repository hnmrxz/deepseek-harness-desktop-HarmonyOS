/**
 * 本机文件选择与读取（附件「投喂」的端侧那一半）。
 *
 * ───────────────────────── 这一层为什么必须存在 ─────────────────────────
 * 上游的附件链路是两段：
 *   1. `fileUploads/upload`（我们发 base64）→ 得到**不透明回执** `receiptId`；
 *   2. 把回执照放进 `session/prompt.request.content[].type='file'`。
 * 第 2 段在 `appstate/model/Wire.ets` 里早就写好了（`filePart()` / `projectFileUpload()`），
 * 缺的一直是第 1 段的**输入**：把用户选中的本机文件变成 base64。
 * 没有这一层时，界面上的「附件」按钮只能塞一个编造的文件名（历史上就是这么做的），
 * 或者静默无反应——两者都在骗人。
 *
 * ───────────────────────── 为什么在这里做而不是在 UI 里 ─────────────────────────
 * 选择器、文件 IO、base64 都是**设备能力**，不是产品策略；UI 只应决定
 * 「什么时候问用户要文件」，不应知道 `picker`/`fileIo` 的用法。
 * 与 `Clipboard` / `SecretStore` 同一立场。
 *
 * ───────────────────────── 一条纪律：绝不静默失败 ─────────────────────────
 * `PickOutcome` 把「用户取消」「文件过大」「读取失败」分成三种**明确结果**。
 * 合并成 `undefined` 会让 UI 无法区分「用户按了取消」与「读取真的失败了」——
 * 前者不该提示任何错误，后者必须提示，否则用户会以为文件已经带上了。
 */

import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD5A1;
const TAG: string = 'platform/filepicker';

/**
 * 类型嗅探要看的头字节数（12）：PNG(8) / JPEG(3) / GIF(4) / WEBP 的 `RIFF….WEBP`(12)。
 * 取最大值并写成常量，避免各处再出现 `12` 这种裸魔数。
 */
const HEAD_BYTES: number = 12;

/**
 * 端侧单文件上限（字节）。
 *
 * 【这是**我们**的护栏，不是上游的限制】上游只对**图片**给了
 * `imageLimits.maxImageBytes = 20971520`（20 MiB，实测自 `session/list` 的投影），
 * 通用文件的限制没有公开。取 16 MiB 的理由是 base64 会膨胀约 33%：
 * 16 MiB 的文件会变成约 21 MB 的 JSON，一条 RPC 里塞这么大已经足够冒险。
 * 因此这里**主动拒绝并说明**，而不是让它在 RPC 层以超时/截断的形式失败——
 * 后者在用户看来只是「发送卡住了」。
 */
export const MAX_ATTACHMENT_BYTES: number = 16 * 1024 * 1024;

/**
 * 图片**降尺度**的目标长边（像素，T028）。
 *
 * 【为什么要降】内联图片走 `appstate/model/InputAttachment` 的 12 MiB 上限（塞进一条
 * JSON RPC），而手机主摄直出普遍 4000–8000px / 3–15 MiB。没有这一步时，用户发一张
 * 大照片得到的是"请先压缩再发送"——把压缩这个动作推给用户，等于这条功能没做完。
 *
 * 【为什么是 2048】聊天场景里 2048px 长边在手机屏上已无可见差异，而 JPEG 重编码后
 * 通常落在几百 KiB——一次把"超大被拒"与"发送超时"两类失败都消掉。
 */
const IMAGE_DOWNSCALE_MAX_EDGE: number = 2048;

/**
 * 触发**重编码**的体积门槛（字节，T028）。
 *
 * 低于这个体积的图片原样通过：重编码是有损操作，对几百 KiB 的图做 JPEG 化
 * 省不了多少体积，却白白损失一次画质。只对"大到值得"的图动手。
 */
const IMAGE_REENCODE_TRIGGER_BYTES: number = 1024 * 1024;

/** 重编码的 JPEG 质量（0–100）。85 是"肉眼无感、体积显著下降"的常用平衡点。 */
const IMAGE_REENCODE_QUALITY: number = 85;

/** 选择的三种明确结果 + 一个「用户取消」 */
export enum PickOutcome {
  /** 选到了并已读成 base64 */
  PICKED = 'picked',
  /** 用户主动取消（**不是错误**，UI 不该报错） */
  CANCELLED = 'cancelled',
  /** 选到了但超过端侧上限（UI 要说明原因与大小） */
  TOO_LARGE = 'too_large',
  /** 选择器或读取失败（UI 要给出可执行建议） */
  FAILED = 'failed'
}

/** 选择结果 */
export interface PickedFile {
  outcome: PickOutcome;
  /** 原始 URI（诊断与去重可用；**不要**展示给用户，它很长且含编码） */
  uri: string;
  /** 展示名（URI 末段，已解码） */
  name: string;
  /** 推断出的 MIME 类型（仅用于展示与图片内联判断） */
  mediaType: string;
  /** 精确字节数 */
  bytes: number;
  /** 规范 base64（仅 `PICKED` 时有值） */
  base64: string;
  /**
   * 文件**开头**的若干字节（最多 12 个；读不到则为空数组）。
   *
   * 【为什么要带这一点点字节】判定"这是不是一张能内联的图片"必须看**内容**：
   * 图库返回的媒体 URI 不一定带扩展名（见 `appstate/model/InputAttachment` 的
   * `sniffImageMediaType`）。只带 12 个字节是因为四个图片容器的签名都在前 12 字节内——
   * 为了认类型把整张图（可达数 MB）再复制一份上去是不划算的。
   */
  head: number[];
  /** 可直接展示给用户的原因（`CANCELLED` 时为空串） */
  reason: string;
}

/** 造一个只有结果与原因的结果对象（避免各处重复写字面量）。 */
function outcomeOf(outcome: PickOutcome, uri: string, reason: string): PickedFile {
  return {
    outcome: outcome, uri: uri, name: '', mediaType: '', bytes: 0, base64: '', head: [], reason: reason
  };
}

/** 选中的**文件夹**（E102）：URI 与**真实路径**都带回来（Host 侧用路径）。 */
export interface PickedFolder {
  outcome: PickOutcome;
  /** 原始 URI（file://docs/...） */
  uri: string;
  /** 供 Host（Node）使用的真实路径；取不到时为空串（那时**不猜**，按失败处理） */
  path: string;
  name: string;
  reason: string;
}

/**
 * 拉起系统**文件夹**选择器，用于把设备上的真实项目目录选作工作区。
 *
 * 【平台边界（SDK 原文）】`DocumentSelectMode` 的注释明确写着
 * "Only 2-in-1 devices are supported" ⇒ **手机/平板拿不到文件夹选择**。
 * 所以调用方必须准备好回退路径（我们的做法：回退到"浏览沙箱目录"，
 * 并把原因说清楚），而不是让按钮点了没反应。
 *
 * 【路径怎么来】选择器给的是 `file://docs/...` URI，而 Host 是 Node、按**路径**干活，
 * 因此用 `fileUri.FileUri(uri).path` 换成真实路径。转换失败就返回空路径，
 * 由调用方按"不可用"处理（不拿 URI 冒充路径）。
 */
export async function pickFolder(context: common.Context): Promise<PickedFolder> {
  let uris: string[] = [];
  try {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    const view: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    uris = await view.select(options);
  } catch (err) {
    const e = err as BusinessError;
    const cancelled: boolean = isCancelCode(e.code);
    hilog.info(DOMAIN, TAG, 'pickFolder rejected: code=%{public}d', e.code);
    return {
      outcome: cancelled ? PickOutcome.CANCELLED : PickOutcome.FAILED,
      uri: '', path: '', name: '',
      reason: cancelled ? '' : `文件夹选择器不可用（该能力仅 2in1 支持）：${e.message}（code=${e.code}）`
    };
  }
  if (uris.length === 0) {
    return { outcome: PickOutcome.CANCELLED, uri: '', path: '', name: '', reason: '' };
  }
  const uri: string = uris[0];
  let realPath: string = '';
  try {
    realPath = new fileUri.FileUri(uri).path;
  } catch (e) {
    const e2 = e as BusinessError;
    hilog.warn(DOMAIN, TAG, 'URI → 路径失败：%{public}s', e2.message);
  }
  if (realPath.length === 0) {
    return {
      outcome: PickOutcome.FAILED, uri: uri, path: '', name: nameOfUri(uri),
      reason: '已选中文件夹，但拿不到它的真实路径（Host 需要路径而不是 URI），因此无法作为工作区。'
    };
  }
  return { outcome: PickOutcome.PICKED, uri: uri, path: realPath, name: nameOfUri(uri), reason: '' };
}

/**
 * 拉起系统文件选择器并读取选中的文件。
 *
 * `context` 必须由调用方（UI 层）传入：本模块没有 UI，`getContext()` 在这里
 * 拿不到窗口上下文。传进来比在这里猜要诚实。
 *
 * 只允许单选。理由：多选会让「哪几个上传成功了」变成一个需要逐个报错的状态机，
 * 而当前的 UI 只有一个附件列表；在能逐条显示失败原因之前，多选只会制造歧义。
 */
export async function pickDocument(context: common.Context): Promise<PickedFile> {
  let uris: string[] = [];
  try {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    const view: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    uris = await view.select(options);
  } catch (err) {
    const e = err as BusinessError;
    // 用户取消在多数系统上表现为一次 reject（错误码 13900020 / 或 message 含 cancel）。
    // 取消不提示错误，因此必须与真正的失败分开：
    hilog.info(DOMAIN, TAG, 'select rejected: code=%{public}d', e.code);
    const cancelled: boolean = isCancelCode(e.code);
    return outcomeOf(cancelled ? PickOutcome.CANCELLED : PickOutcome.FAILED, '',
      cancelled ? '' : `无法拉起文件选择器：${e.message}（code=${e.code}）`);
  }
  if (uris.length === 0) {
    return outcomeOf(PickOutcome.CANCELLED, '', '');
  }
  return await readPickedFile(uris[0]);
}

/** 判断一个错误码是否表示「用户取消」。 */
function isCancelCode(code: number): boolean {
  // 13900020 = 参数错误（部分系统用它表示用户取消）；其他实现直接给 0/undefined。
  return code === 13900020 || code === 0;
}

/** 取开头若干字节（最多 `HEAD_BYTES`）用于类型嗅探；不足则给多少算多少 */
function headBytesOf(bytes: Uint8Array): number[] {
  const limit: number = bytes.length < HEAD_BYTES ? bytes.length : HEAD_BYTES;
  const out: number[] = [];
  for (let i = 0; i < limit; i++) {
    out.push(bytes[i]);
  }
  return out;
}

/**
 * 拉起**系统图库**选择器，选一张图片并读成 base64（P0-4：输入区内联发送图片）。
 *
 * ───────── 为什么用图库而不是文件选择器 ─────────
 * 手机上"发一张照片/截图"是最高频的输入之一，而图库选择器给的是**缩略图界面**，
 * 比在文件树里翻 `Pictures/` 快得多。两者都是系统选择器，**都不需要任何权限**
 * （用户选中的那一刻即授权），所以这一步没有新增申请项（上架合规不变）。
 *
 * ───────── 与 `pickDocument` 的差别 ─────────
 * · 只列图片（`PhotoViewMIMETypes.IMAGE_TYPE`）；
 * · 返回的是**媒体 URI**（`file://media/…`），展示名不一定带扩展名 ⇒ 靠
 *   `head`（魔数）兜底判断类型，见 `PickedFile.head` 的说明；
 * · 仍然单选：与 `pickDocument` 同一理由（多选会让"哪几张成功"变成状态机，
 *   而当前的附件条只能逐条报错）。
 *
 * ⚠️ **未真机验收**：媒体 URI 与文档 URI 都由 `fileIo` 支持，但**授权方式不同**，
 * 这一步在真机上的成败记在 `docs/device-validation.md` 的 D31；在那之前不得宣称可用。
 *
 * ───────── 降尺度（T028） ─────────
 * 图库是**相机直出图**的主要来源，也是最容易撞上内联 12 MiB 上限的地方，因此这里
 * 打开降尺度：超过 1 MiB 的 PNG/JPEG/WEBP 会被缩到长边 ≤2048 并重编码为 JPEG
 * （产物更小才采纳，失败原样放行，GIF 不动）。`pickDocument` 不开：从文件管理器
 * 选的图片里可能有用户明确要保持原样的素材，降尺度只服务"拍照/截图发出去"这一条链。
 */
export async function pickImage(context: common.Context): Promise<PickedFile> {
  let uris: string[] = [];
  try {
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const view: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const result: photoAccessHelper.PhotoSelectResult = await view.select(options);
    uris = result.photoUris;
  } catch (err) {
    const e = err as BusinessError;
    hilog.info(DOMAIN, TAG, 'photo select rejected: code=%{public}d', e.code);
    const cancelled: boolean = isCancelCode(e.code);
    return outcomeOf(cancelled ? PickOutcome.CANCELLED : PickOutcome.FAILED, '',
      cancelled ? '' : `无法拉起图库：${e.message}（code=${e.code}）`);
  }
  if (uris.length === 0) {
    return outcomeOf(PickOutcome.CANCELLED, '', '');
  }
  return await readPickedFile(uris[0], true);
}

/** 读取一个已选中的 URI 并把内容编码成 base64。 */
async function readPickedFile(uri: string, downscale: boolean = false): Promise<PickedFile> {
  const name: string = nameOfUri(uri);
  let file: fs.File | undefined = undefined;
  try {
    file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const size: number = fs.statSync(file.fd).size;
    if (size > MAX_ATTACHMENT_BYTES) {
      return {
        outcome: PickOutcome.TOO_LARGE, uri: uri, name: name,
        mediaType: mediaTypeOf(name), bytes: size, base64: '', head: [],
        reason: `文件 ${formatBytes(size)} 超过端侧附件上限 ${formatBytes(MAX_ATTACHMENT_BYTES)}`
      };
    }
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    const read: number = fs.readSync(file.fd, buffer);
    // 只编码**实际读到**的字节：`stat` 与 `read` 之间文件可能被改动，
    // 按 size 编码会在尾部带上未写入的 0，产生一个「能上传但内容坏了」的附件。
    const bytes: Uint8Array = new Uint8Array(buffer, 0, read);
    let payload: Uint8Array = bytes;
    let mediaType: string = mediaTypeOf(name);
    let head: number[] = headBytesOf(bytes);
    if (downscale) {
      const shrunk: Uint8Array | undefined = await tryDownscaleImage(bytes);
      if (shrunk !== undefined) {
        payload = shrunk;
        // 重编码后字节就是 JPEG：mediaType 与 head 必须跟着改。
        // 【为什么不能留给上层推断】`resolveImageMediaType` 是**名字优先**的，
        // 一个叫 photo.png 的文件重编码后若仍声明 image/png，会形成
        // "声明与字节不符"的附件——上游按声明解码就是坏图。
        mediaType = 'image/jpeg';
        head = headBytesOf(shrunk);
      }
    }
    const helper: util.Base64Helper = new util.Base64Helper();
    const base64: string = helper.encodeToStringSync(payload);
    return {
      outcome: PickOutcome.PICKED, uri: uri, name: name, mediaType: mediaType,
      bytes: payload.length, base64: base64, head: head, reason: ''
    };
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'read failed: %{public}s', e.message);
    return outcomeOf(PickOutcome.FAILED, uri, `读取文件失败：${e.message}（code=${e.code}）`);
  } finally {
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (closeErr) {
        // 关闭失败不影响已读到的数据，仅记录
        hilog.warn(DOMAIN, TAG, 'close failed');
      }
    }
  }
}

/**
 * 从头部字节认出**可降尺度**的图片类型（`''` = 不适合降尺度）。
 *
 * 只认 PNG / JPEG / WEBP 三种静态容器。**GIF 是刻意排除的**：它的动画由多帧组成，
 * `createPixelMap` 只取首页、JPEG 重编码丢掉全部动画——"把动图变成静图"不是降尺度，
 * 是毁数据，宁可让它原样走（大 GIF 会被体积上限如实拒绝并说明）。
 *
 * 【为什么在这里再写一份魔数判定】`appstate/model/InputAttachment.sniffImageMediaType`
 * 是同一套判定，但依赖方向是 appstate → platform，这里反向 import 会把分层倒过来。
 * 魔数是公开且稳定的容器签名，镜像一份比反向依赖干净。
 */
function sniffDownscalableType(head: number[]): string {
  if (head.length >= 8 && head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4E && head[3] === 0x47
    && head[4] === 0x0D && head[5] === 0x0A && head[6] === 0x1A && head[7] === 0x0A) {
    return 'image/png';
  }
  if (head.length >= 3 && head[0] === 0xFF && head[1] === 0xD8 && head[2] === 0xFF) {
    return 'image/jpeg';
  }
  if (head.length >= 12 && head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46
    && head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50) {
    return 'image/webp';
  }
  return '';
}

/**
 * 尝试把一张**过大的静态图**降尺度/重编码成更小的 JPEG（T028）。
 *
 * 触发条件（两条都满足才动手）：
 *   · 类型是 PNG / JPEG / WEBP（GIF 见 `sniffDownscalableType` 的说明）；
 *   · 体积超过 `IMAGE_REENCODE_TRIGGER_BYTES`（小图不值得有损重编码）。
 *
 * 长边超过 `IMAGE_DOWNSCALE_MAX_EDGE` 时按比例缩到 2048；否则只做 JPEG 重编码
 * （一张 8 MiB 的全尺寸 PNG 重编码后往往只剩几百 KiB，同样受益）。
 *
 * 【采纳判据】产物**必须比原文件小**才返回；否则返回 `undefined`（原样用原文件）。
 * 任何一步失败同样返回 `undefined`——降尺度是**优化**，不允许把"优化失败"变成"发送失败"。
 */
async function tryDownscaleImage(bytes: Uint8Array): Promise<Uint8Array | undefined> {
  const sniffed: string = sniffDownscalableType(headBytesOf(bytes));
  if (sniffed.length === 0) {
    return undefined;
  }
  if (bytes.length <= IMAGE_REENCODE_TRIGGER_BYTES) {
    return undefined;
  }
  let source: image.ImageSource | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  let pixelMap: image.PixelMap | undefined = undefined;
  try {
    // `bytes` 可能是某个更大 ArrayBuffer 的前缀视图（`stat` 与 `read` 之间文件可能变小），
    // 解码器要的是**恰好这么多字节**的缓冲，切片拷贝一次，不带尾部脏数据。
    const exact: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length);
    source = image.createImageSource(exact);
    const info: image.ImageInfo = await source.getImageInfo();
    const width: number = info.size.width;
    const height: number = info.size.height;
    if (width <= 0 || height <= 0) {
      return undefined;
    }
    const longEdge: number = width > height ? width : height;
    let options: image.DecodingOptions | undefined = undefined;
    if (longEdge > IMAGE_DOWNSCALE_MAX_EDGE) {
      const scale: number = IMAGE_DOWNSCALE_MAX_EDGE / longEdge;
      const targetWidth: number = Math.max(1, Math.round(width * scale));
      const targetHeight: number = Math.max(1, Math.round(height * scale));
      const target: image.Size = { width: targetWidth, height: targetHeight };
      const decoding: image.DecodingOptions = { desiredSize: target };
      options = decoding;
    }
    pixelMap = await source.createPixelMap(options);
    packer = image.createImagePacker();
    const packOptions: image.PackingOption = {
      format: 'image/jpeg',
      quality: IMAGE_REENCODE_QUALITY
    };
    const packed: ArrayBuffer = await packer.packing(pixelMap, packOptions);
    if (packed.byteLength >= bytes.length) {
      // 重编码反而更大（典型于本来就已高度压缩的小分辨率 JPEG）：保留原文件
      return undefined;
    }
    hilog.info(DOMAIN, TAG,
      'downscale: %{public}d -> %{public}d bytes, edge %{public}d -> %{public}d (jpeg q%{public}d)',
      bytes.length, packed.byteLength, longEdge,
      longEdge > IMAGE_DOWNSCALE_MAX_EDGE ? IMAGE_DOWNSCALE_MAX_EDGE : longEdge, IMAGE_REENCODE_QUALITY);
    return new Uint8Array(packed);
  } catch (err) {
    const e = err as BusinessError;
    // 解码/编码失败一律按"跳过降尺度"处理：原图仍然完整可用
    hilog.info(DOMAIN, TAG, 'downscale skipped: code=%{public}d %{public}s', e.code, e.message);
    return undefined;
  } finally {
    if (pixelMap !== undefined) {
      try {
        await pixelMap.release();
      } catch (releaseErr) {
        hilog.warn(DOMAIN, TAG, 'pixelMap release failed');
      }
    }
    if (packer !== undefined) {
      try {
        await packer.release();
      } catch (releaseErr) {
        hilog.warn(DOMAIN, TAG, 'packer release failed');
      }
    }
    if (source !== undefined) {
      try {
        await source.release();
      } catch (releaseErr) {
        hilog.warn(DOMAIN, TAG, 'source release failed');
      }
    }
  }
}

/** 从 URI 末段取展示名并解码百分号转义。 */
function nameOfUri(uri: string): string {
  let end: number = uri.length;
  const query: number = uri.indexOf('?');
  if (query >= 0) {
    end = query;
  }
  const slash: number = uri.lastIndexOf('/', end - 1);
  const raw: string = uri.substring(slash + 1, end);
  try {
    return decodeURIComponent(raw);
  } catch (err) {
    // 非法转义序列（少见）：原样使用比抛错好，名字只是展示
    return raw;
  }
}

/** 常见扩展名 → MIME。未知一律 `application/octet-stream`（不猜成 text/plain）。 */
function mediaTypeOf(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0) {
    return 'application/octet-stream';
  }
  const ext: string = name.substring(dot + 1).toLowerCase();
  if (ext === 'png') {
    return 'image/png';
  }
  if (ext === 'jpg' || ext === 'jpeg') {
    return 'image/jpeg';
  }
  if (ext === 'webp') {
    return 'image/webp';
  }
  if (ext === 'gif') {
    return 'image/gif';
  }
  if (ext === 'txt' || ext === 'log' || ext === 'md') {
    return 'text/plain';
  }
  if (ext === 'json' || ext === 'json5') {
    return 'application/json';
  }
  if (ext === 'pdf') {
    return 'application/pdf';
  }
  return 'application/octet-stream';
}

/** 字节数的可读形式（本模块自用，避免为一个格式化函数反向依赖 appstate）。 */
function formatBytes(n: number): string {
  if (n < 1024) {
    return `${n} B`;
  }
  if (n < 1024 * 1024) {
    return `${Math.round(n / 1024)} KB`;
  }
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}
