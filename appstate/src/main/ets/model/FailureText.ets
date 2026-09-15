/**
 * **失败文案的唯一真值**（P7-19，从 `SessionHub` 里搬出来的纯逻辑）。
 *
 * ## 为什么要有这一层
 *
 * 上游有一张**权威的错误码表**（`dsh-api-session-controller/lib/typert.host.js` 的
 * `RemoteErrorDetailsMap`，46 个码，每个码还带自己的 details 形状）。而本仓此前只有
 * `friendlyFailure()` 里的 8 个特例 + 一个 `friendlyWorkspaceFailure()` 里的 5 个，
 * 其余一律落到兜底 `${code} ${message}` —— 真机上用户看到的是
 * 「session/conflict session "xxx" already has cwd …」这种**只有开发者读得懂**的句子。
 *
 * 搬进纯模型有三个好处：① 文案能被 fixture 钉住（尤其"兜底不许把 code 吞掉"这条）；
 * ② 中枢那个函数瘦成一行委托；③ "这台 Host 可能回哪些码"与"我们给了哪些话"可以**对账**。
 *
 * ## 两条纪律
 *
 * 1. **绝不吞掉 code**：兜底文案必须**带上原始码**。它是发现"上游多了新码"的唯一线索
 *    （与 `noteUnknown` 同一条思路：不认识就说出来，而不是含糊过去）。
 * 2. **兜底必须看起来像兜底**：不许编一句"操作失败，请重试"来冒充专门文案——
 *    那会让"我们还没为这个码写话"这件事实消失。
 *
 * ## 可达集合（`REACHABLE_FAILURE_CODES`）是怎么定的
 *
 * 逐个对照本仓**真实调用点**的端点：只有那张表里**我们的界面真会撞上**的码才进这个集合
 * （`subagent/*` 八个码我们没有对应的界面入口，就不进——写八句用不上的话是自欺）。
 * fixture 用它做**对账**：集合里每一个码都必须在文案表里，且文案不得以原始码开头。
 */

import {
  ERR_SESSION_NOT_FOUND,
  ERR_SESSION_CONFLICT,
  ERR_SESSION_AGENT_BUSY,
  ERR_SESSION_MODEL_UNAVAILABLE,
  ERR_SESSION_WORKSPACE_ATTACH_FAILED,
  ERR_SESSION_INVALID_TIME_ZONE,
  ERR_SESSION_TITLE_INVALID,
  ERR_SESSION_FORK_UNAVAILABLE,
  ERR_SESSION_ATTACHMENT_INVALID,
  ERR_SESSION_QUEUE_ITEM_NOT_FOUND,
  ERR_SESSION_STEER_UNAVAILABLE,
  ERR_GATEWAY_BAD_REQUEST,
  ERR_GATEWAY_ARGUMENTS_INVALID,
  ERR_GATEWAY_INPUT_INVALID,
  ERR_GATEWAY_CANCELLED,
  ERR_GATEWAY_INTERNAL,
  ERR_SETTINGS_REJECTED,
  ERR_SETTINGS_CONFLICT,
  ERR_CREDENTIAL_REJECTED,
  ERR_LLM_MODEL_DISCOVERY_REJECTED,
  ERR_WORKSPACE_NOT_FOUND,
  ERR_WORKSPACE_INVALID_PATH,
  ERR_WORKSPACE_NAME_CONFLICT,
  ERR_WORKSPACE_MOVE_INVALID,
  ERR_WORKSPACE_FILE_NOT_FOUND,
  ERR_WORKSPACE_FILE_OUTSIDE_WORKSPACE,
  ERR_WORKSPACE_FILE_TOO_LARGE,
  ERR_WORKSPACE_FILE_NOT_TEXT,
  ERR_WORKSPACE_FILE_NOT_REGULAR_FILE,
  ERR_WORKSPACE_FILE_NOT_DIRECTORY,
  ERR_DIRECTORY_PICKER_UNAVAILABLE,
  ERR_DIRECTORY_PICKER_UNREADABLE,
  ERR_DIRECTORY_PICKER_EXISTS,
  ERR_DIRECTORY_PICKER_CREATE_FAILED,
  ERR_AGENT_PRESET_NOT_FOUND,
  ERR_AGENT_PRESET_INVALID,
  ERR_AGENT_PRESET_READ_ONLY,
  ERR_AGENT_PRESET_LOCKED,
  ERR_AGENT_PRESET_CONFLICT
} from 'dshcompat';

/** 一个错误码的文案（表项） */
export interface FailureTextEntry {
  /** 上游错误码 */
  code: string;
  /** 给用户看的一句话（可行动，不甩术语） */
  text: string;
}

/**
 * 可达错误码集合：**从 `dshcompat` 转出**（码是上游事实，只许住那一层）。
 *
 * 清单本身与出处写在 `dshcompat/ErrorCodes.ets`：那是 `RemoteErrorDetailsMap`（46 个码）
 * 里本仓界面真会撞上的 39 个；`subagent/*` 八个没有界面入口，故不列。
 * 这里转出是为了让文案表的**消费者**（视图、fixture）只依赖 appstate 一层。
 */
export { REACHABLE_ERROR_CODES as REACHABLE_FAILURE_CODES } from 'dshcompat';

/**
 * 文案表。
 *
 * 【写法约定】① 先说"发生了什么"，再说"你能做什么"；② Host 的原文由调用方附加，
 * 这里不重复；③ 只有一句能行动的话，不写"请联系管理员"这类空话。
 */
export const FAILURE_TEXT_TABLE: FailureTextEntry[] = [
  // ── 会话 ──
  { code: ERR_SESSION_NOT_FOUND, text: '这条会话在 Host 侧已经不存在了（未挂载或已被删除）。回到会话列表刷新一下再看。' },
  { code: ERR_SESSION_CONFLICT, text: '这个目录已经有一个会话了——Host 不允许两个会话共用同一个工作目录。请换一个目录，或直接打开那个已有会话。' },
  { code: ERR_SESSION_AGENT_BUSY, text: '这个会话正忙（上一次请求还在处理）。等它结束，或先按「停止」。' },
  { code: ERR_SESSION_MODEL_UNAVAILABLE, text: '这个模型在 Host 侧不可用（凭据缺失或提供方没配好）。到「设置 → 模型」里换一个，或先配好该提供方的凭据。' },
  { code: ERR_SESSION_WORKSPACE_ATTACH_FAILED, text: '把这个工作区挂到会话上失败了（目录可能已被移动或没有权限）。确认目录还在，再试一次。' },
  { code: ERR_SESSION_INVALID_TIME_ZONE, text: '客户端报的时区 Host 不认。这通常是本客户端的缺陷，请把诊断报告发出来。' },
  { code: ERR_SESSION_TITLE_INVALID, text: '这个标题 Host 不接受（可能为空或过长）。换一个短一点的标题。' },
  { code: ERR_SESSION_FORK_UNAVAILABLE, text: '这个会话当前不能分叉（Host 只允许从有内容的轮次分叉）。' },
  { code: ERR_SESSION_QUEUE_ITEM_NOT_FOUND, text: '这一行已经不在待发队列里了（Host 已取走或已被删掉）——按无事发生处理即可。' },
  { code: ERR_SESSION_STEER_UNAVAILABLE, text: '当前轮次已经结束，没法再插话——这条消息仍留在队列里，下一轮会正常发出。' },
  // ── 网关 ──
  { code: ERR_GATEWAY_BAD_REQUEST, text: 'Host 认为这次请求不合法。若是首次出现，请把诊断报告发出来（码与原文都在里面）。' },
  { code: ERR_GATEWAY_ARGUMENTS_INVALID, text: '调用参数与 Host 的契约不符。这是本客户端的兼容面缺陷，请提交诊断报告以便修正上表——重试与换网络都不会有用。' },
  { code: ERR_GATEWAY_INPUT_INVALID, text: '调用参数与 Host 的契约不符。这是本客户端的兼容面缺陷，请提交诊断报告以便修正上表。' },
  { code: ERR_GATEWAY_CANCELLED, text: '这次请求被取消了（可能是超时或你按了停止）。' },
  { code: ERR_GATEWAY_INTERNAL, text: 'Host 内部出错。可以先重试一次；若反复出现，请带上诊断报告——它需要 Host 侧的日志才能定位。' },
  // ── 设置与凭据 ──
  { code: ERR_SETTINGS_REJECTED, text: 'Host 拒绝了这次设置写入（命名空间未注册、只读，或没通过 schema 校验）。确认这一项在设置里是「可写」的再改。' },
  { code: ERR_SETTINGS_CONFLICT, text: '设置在你编辑期间被别处改了（版本冲突）。重新读取当前值后再改一次——直接重试会一直失败。' },
  { code: ERR_CREDENTIAL_REJECTED, text: 'Host 拒绝了这次凭据写入。检查这项凭据的引用名是否正确，以及它是否被声明为可写。' },
  // ── 模型目录 ──
  { code: ERR_LLM_MODEL_DISCOVERY_REJECTED, text: '这个提供方拒绝了模型目录查询（多半是 base URL 或密钥不对）。到「设置 → 模型」检查该提供方的配置。' },
  // ── 工作区 ──
  { code: ERR_WORKSPACE_NOT_FOUND, text: '这个工作区在 Host 侧已经不存在了。刷新工作区列表后重试。' },
  { code: ERR_WORKSPACE_INVALID_PATH, text: '这个路径 Host 不接受（可能是相对路径或含非法字符）。用一个绝对路径。' },
  { code: ERR_WORKSPACE_NAME_CONFLICT, text: '已经有一个同名工作区了。换一个名字。' },
  { code: ERR_WORKSPACE_MOVE_INVALID, text: '这次移动不合法（目标位置在自身之下，或顺序参数不对）。换一个目标位置。' },
  // ── 工作区文件 ──
  { code: ERR_WORKSPACE_FILE_NOT_FOUND, text: '文件不存在或已被移动。' },
  { code: ERR_WORKSPACE_FILE_OUTSIDE_WORKSPACE, text: '该路径在会话工作区之外，Host 拒绝访问。' },
  { code: ERR_WORKSPACE_FILE_TOO_LARGE, text: '文件超过 Host 的单页上限，端侧不预览。可在 Host 侧用工具分段读取。' },
  { code: ERR_WORKSPACE_FILE_NOT_TEXT, text: '二进制文件（非 UTF-8 文本），端侧不预览。可在 Host 侧用工具读取。' },
  { code: ERR_WORKSPACE_FILE_NOT_REGULAR_FILE, text: '不是一个普通文件（可能是目录或符号链接），无法预览。' },
  { code: ERR_WORKSPACE_FILE_NOT_DIRECTORY, text: '这不是一个目录（可能是文件或符号链接），无法列出内容。' },
  // ── 目录选择器 ──
  { code: ERR_DIRECTORY_PICKER_UNAVAILABLE, text: 'Host 侧没有可用的目录选择器（那是桌面端的能力）。请手填路径，或用工作区页面挑一个已有工作区。' },
  { code: ERR_DIRECTORY_PICKER_UNREADABLE, text: '这个目录 Host 读不了（权限或不存在）。换一个目录。' },
  { code: ERR_DIRECTORY_PICKER_EXISTS, text: '同名目录已经存在。换一个名字，或直接打开它。' },
  { code: ERR_DIRECTORY_PICKER_CREATE_FAILED, text: '创建目录失败（权限或磁盘）。换一个位置再试。' },
  // ── 代理预设 ──
  { code: ERR_AGENT_PRESET_NOT_FOUND, text: '这个预设已经不存在了。刷新预设列表后重试。' },
  { code: ERR_AGENT_PRESET_INVALID, text: '这个预设的内容不合法（Host 给了具体原因）。按原文改一改，或换一个预设。' },
  { code: ERR_AGENT_PRESET_READ_ONLY, text: '这是内置预设，不能改。想改就先「复制」一份再改。' },
  { code: ERR_AGENT_PRESET_LOCKED, text: '这个会话的预设被锁住了（会话已开始运行）。' },
  { code: ERR_AGENT_PRESET_CONFLICT, text: '这个会话已经绑定了别的预设，Host 不让换。' }
];

/**
 * 客户端**自己**的失败码（不是上游的，但同样需要一句人话）。
 *
 * `carrier/*` 是连接层给出的传输失败（`RemoteMux` / `HttpClient` 上报），
 * 它们**不是** Host 的业务错误，所以不在那张上游表里——但用户撞上的概率最高（设备上网络最不稳）。
 */
export const CLIENT_FAILURE_TEXT_TABLE: FailureTextEntry[] = [
  { code: 'client/endpoint-invalid', text: '客户端拼装了一个 Host 不认识的 endpoint。这是本客户端的兼容面缺陷，请提交诊断报告以便修正上表——重试与换网络都不会有用。' },
  { code: 'carrier/parse', text: '响应无法解析——通常是中间转发通道截断了连接（开发期的端口转发常见）。请改用直连本机回环，或使用 hostkit 的加密隧道。' },
  { code: 'carrier/closed', text: '连接在传输中断开——中间转发通道不稳定，或 Host 已停止。请检查 Host 是否仍在运行；若经端口转发访问，请改用 hostkit 隧道。' },
  { code: 'carrier/transport', text: '连接在传输中断开——中间转发通道不稳定，或 Host 已停止。请检查 Host 是否仍在运行；若经端口转发访问，请改用 hostkit 隧道。' },
  { code: 'carrier/timeout', text: '请求超时。请检查网络连通性；若 Host 负载很高可稍后重试。' }
];

/**
 * 附件被拒的文案（**要按 Host 原文分两种成因**，见 `failureText` 的调用处）。
 *
 * `session/attachment-invalid` 这个码同时覆盖三件事（P7-18/E384 的取证）：
 *   ① 提示词里的**文件回执**不属于这条会话（上游原文 `"File was not uploaded for this session."`）；
 *   ② 读历史图片字节时引用不属于这条会话；
 *   ③ **图片数据本身**不被接纳（上游原文 `"Unsupported or malformed image data."`）。
 * 只写"图片附件"对文件那条路是错的；只写"不属于这条会话"对图片那条路也是错的。
 * 这里按 `message` 里有没有 `image` 分流——这是线上唯一能区分两者的线索。
 */
function attachmentInvalidText(message: string): string {
  if (message.indexOf('image') >= 0) {
    return 'Host 说这张图无法接纳（格式不支持、数据损坏，**或 Host 侧的图像解码器不可用**）。'
      + '诊断报告里的「运行时事实」会给出 Host 原生件的真实探测结论，先看那一条再决定是换图还是报缺陷。'
      + (message.length > 0 ? `（Host 原文：${message}）` : '');
  }
  return 'Host 拒绝了这个附件：它不属于这条会话（附件回执与图片引用都是**会话作用域**的）。'
    + '常见原因：附件是在另一个会话里选的，或会话切走后又把旧附件发了出去。'
    + '重新选择文件后再发即可。' + (message.length > 0 ? `（Host 原文：${message}）` : '');
}

/**
 * 兜底文案（**必须带上原始码**）。
 *
 * 这条兜底本身就是一条纪律：它明确说"这个码还没有专门文案"，
 * 于是"上游多了新码"这件事**在界面上就看得见**，而不是被一句含糊的"操作失败"盖住。
 */
export function untranslatedFailure(code: string, message: string): string {
  const detail: string = message.length > 0 ? `（Host 原文：${message}）` : '';
  return `Host 报了一个本客户端还没有专门文案的错误：${code}。`
    + `请把这一行连同诊断报告一起提交，我们会补上它的说明${detail}`;
}

/**
 * 这个码有没有**专门**文案（`untranslatedFailure` 的反面）。
 *
 * 【为什么不能只看表】`session/attachment-invalid` 的文案要按 Host 原文分流，
 * 所以它**不在表里**、走 `attachmentInvalidText()`。这里把它一并算作"有"，
 * 否则对账断言会要求把它塞进表里，从而把"分流"这件事逼回成一个含糊的句子。
 */
export function hasFailureText(code: string): boolean {
  return code === ERR_SESSION_ATTACHMENT_INVALID || findFailureText(code) !== undefined;
}

/** 查表（找到第一个匹配） */
function findFailureText(code: string): FailureTextEntry | undefined {
  for (let i = 0; i < FAILURE_TEXT_TABLE.length; i++) {
    if (FAILURE_TEXT_TABLE[i].code === code) {
      return FAILURE_TEXT_TABLE[i];
    }
  }
  for (let j = 0; j < CLIENT_FAILURE_TEXT_TABLE.length; j++) {
    if (CLIENT_FAILURE_TEXT_TABLE[j].code === code) {
      return CLIENT_FAILURE_TEXT_TABLE[j];
    }
  }
  return undefined;
}

/**
 * 一个错误码 + Host 原文 → 给用户看的一句话。
 *
 * @param code 上游（或本客户端）的错误码
 * @param message Host 给的原文（可空；**非空时会附在文案后面**——原文是唯一的第一手证据）
 */
export function failureText(code: string, message: string): string {
  /*
   * `session/attachment-invalid` 要**按原文分流**（同一个码覆盖文件回执与图片两条路，
   * 处置完全不同）⇒ 它不进表，走专门的函数。这也解释了为什么表里的每条文案都必须是
   * "与 message 无关"的那种：需要看原文的码不该被塞进表里假装一句话能说清。
   */
  if (code === ERR_SESSION_ATTACHMENT_INVALID) {
    return attachmentInvalidText(message);
  }
  const entry: FailureTextEntry | undefined = findFailureText(code);
  if (entry === undefined) {
    return untranslatedFailure(code, message);
  }
  /*
   * `carrier/*` 必须把底层 `reason` 一起带出来（E71 的教训）：连接层的 reason 通常是
   * 明确的（"探活超时（连接级）" / "send 失败 code=-1"），而固定文案会把它盖掉，
   * 于是排查只能从零猜。其余码的原文同样附上——原文是第一手证据。
   */
  return entry.text + (message.length > 0 ? `（Host 原文：${message}）` : '');
}
