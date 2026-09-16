/**
 * 功能接线回归门禁（E258）。
 *
 * 【为什么需要它】构建能查出语法与类型错误，**查不出"调用点被删"**：
 * 一个功能的实现留在中枢、界面上的入口被某次重构顺手删掉，编译依然通过，
 * 只有跑一遍界面才会发现（本项目 E135 就出过：技能的数据层与界面都在，**触发点没了**，页面永远显示"未读"）。
 *
 * 【它做什么】对一组**已实现/已真机验证**的功能，检查"必须存在的接线特征"是否还在：
 *   · 中枢侧：方法/端点调用存在；
 *   · 界面侧：调用点存在（这是最容易悄悄消失的一环）。
 * 缺任何一项就退出码 1 并列出缺哪一项——**宁可吵，也不要静默**。
 *
 * 【它不做什么】不做语义判断（不保证逻辑正确），也不替代真机验收；它是"接线还在不在"的粗筛。
 *
 * 用法：node tools/check-feature-wiring.mjs
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.cwd();
const SCAN_DIRS = [
  'appstate/src/main/ets',
  'entry/src/main/ets',
  'hostruntime/src/main/ets',
  'dshcompat/src/main/ets',
  'platform/src/main/ets'
];

/** 递归收集 .ets 文件 */
function collect(dir) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      out.push(...collect(p));
    } else if (e.name.endsWith('.ets')) {
      out.push(p);
    }
  }
  return out;
}

const files = SCAN_DIRS.flatMap((d) => collect(join(ROOT, d)));
const sources = files.map((f) => ({ path: relative(ROOT, f).replace(/\\/g, '/'), text: readFileSync(f, 'utf8') }));

function count(pattern) {
  const re = new RegExp(pattern);
  let n = 0;
  const where = [];
  for (const s of sources) {
    /*
     * 【为什么计数前要剥注释】本门禁判的是"调用点在不在"，而注释里写出同一个符号名
     * （"中枢本来就有 `closeFilePreview()`，但没人调用"）会让计数**假装**还有调用点。
     * P8-1 归真验证时当场撞上：把真正的调用换回旧写法（只清本地镜像），本门禁照样打印"全在"。
     * 于是计数与反面规则口径统一：都只看代码。
     */
    const lines = stripComments(s.text).split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (re.test(lines[i])) {
        n++;
        if (where.length < 3) where.push(`${s.path}:${i + 1}`);
      }
    }
  }
  return { n, where };
}

/**
 * 每个功能列出"必须存在的接线"。
 * `min` 是期望的最少出现次数：**1 处往往意味着只剩定义（没有调用）**，所以要 >1。
 */
const FEATURES = [
  { name: '工作区删除', patterns: [['deleteWorkspaceByPath', 2]] },
  { name: '会话归档', patterns: [['archiveSession', 2]] },
  { name: '预设复制', patterns: [['copyAgentPreset', 2]] },
  { name: '预设删除', patterns: [['deleteAgentPreset', 2]] },
  { name: '预设查看', patterns: [['readAgentPreset', 2]] },
  { name: '技能清单', patterns: [['refreshSkills', 2], ['skills/list', 1]] },
  { name: '提供方目录', patterns: [['refreshProviderCatalog', 2]] },
  { name: '命令面板', patterns: [['refreshCommands', 2], ['executeCommand', 2]] },
  /*
   * 长期目标（P7-20 起**可操作**）。官方 `dsh-client-ui-goal` 的目标栏给"暂停/继续/编辑/清除"
   * （相位决定给哪个），创建走 `/goal` 命令；没有目标/加载中/已完成时整条不渲染。
   * 我们此前只有 `refreshGoal`（读），四个动词一个都没有。
   */
  { name: '长期目标', patterns: [['refreshGoal', 2], ['goalBarStateOf', 2], ['pauseGoal', 2], ['goal/change', 1]] },
  { name: '消息反馈', patterns: [['putFeedback', 2], ['refreshFeedback', 2]] },
  /*
   * 返回层级收口（P8-1）。这一条钉的正是"**能力存在、调用点没有**"的缺陷：
   *   · `SessionHub.closeFilePreview()` 早就写好了，但**一个调用点都没有**；视图里关预览写的是
   *     `this.preview = undefined`（只清本地镜像）⇒ 下一次中枢广播就把预览装回来 = "关不掉"。
   *   · 返回箭头原先各自写一行（`wsDrill-1` / `setStackPage(MAIN)`）⇒ 与返回键两套实现。
   * 现在要求：关预览走中枢、下钻归一化走纯函数、所有"退回一层"的入口都经过 `consumeBack`。
   */
  { name: '返回层级收口', patterns: [['closeFilePreview', 2], ['drillAfterPreviewClosed', 2], ['consumeBack', 2], ['backOneLayer', 2], ['BACK_TO_LIST', 2]] },
  /*
   * 内部内容隔离（P8-5）。钉的是"出口自带判据"这条纪律：内部事件（系统提示词、未识别事件载荷）
   * 不得进入五个用户可达出口——对话 / 复制 / 引用 / 通知 / 导出。
   * 判据只有一处（`Turns.mayExposeBodyToUser`，来源事实是 `internal`），
   * 取值只有一处（`userFacingBodyOf`），脱敏只有一处（`Redact.scrubCredentials`）。
   * 三个都要"有调用点"：只留定义就等于又回到"通道有、没接"。
   */
  /*
   * 每会话草稿（P8-3）。官方 `views.d.ts` 逐字："Composer draft (persisted; survives session
   * switches and reloads)" —— 草稿是**会话视图状态的一部分**，而我们此前是全应用一份：
   * 在会话 A 里写一半、切到 B、顺手发送 ⇒ **那段话发给了 B**。
   * 钉三段接线：纯模型的"取回"与"存回"都要有调用点，宿主里那个切换点必须在。
   */
  { name: '每会话草稿', patterns: [['switchDraftContext', 2], ['draftOf', 2], ['putDraft', 2], ['dropDraft', 2],
    // 落盘那一半：编解码（模型）+ 读写键（平台）+ 宿主两处调用点（读回/保存）
    ['serializeDrafts', 2], ['parseDrafts', 2], ['saveComposerDrafts', 2], ['loadComposerDrafts', 2]] },
  /*
   * 关闭语义（P8-4）。官方审计（`docs/08` 的 Sheet 一节）要求"关闭原因必须可区分"
   * 与"编辑态关闭前要有明确的取消/保存策略"。我们的修法是**说出来**：
   * 用户主动关掉一个改过但没提交的浮层时，明确告诉他"已放弃、没有写入 Host"。
   * 钉三段：判定（纯模型）+ 唯一执行点（`dismissSheetByUser`）+ 拖拽关闭那条路必须真的接上。
   */
  /*
   * 错误生命周期（P8-6c）。`docs/09` §3.4 的硬要求：**新一轮成功后清除旧的 transient error**、
   * 持久连接问题只有真正恢复连接后才清除。此前只有一个 `lastError` 槽位而界面无条件渲染它
   * ⇒ 一次"发送被拒"之后成功跑完一整轮，那条红字还挂着，用户会问"我到底发出去没有"。
   * 钉三段：纯模型判定 + 连接级写入口 + 清理调用点（连上 / 发送成功 / 一轮成功跑完）。
   */
  /*
   * 原图预览（灯箱，P9-2）。官方 `ImageLightbox` 的契约：点缩略图打开**文档级**全屏预览
   * （遮罩 + contain 原图 + 右上角关闭），Esc/点遮罩/关闭按钮都能关，关闭后焦点回到缩略图。
   * 我们此前是"点一下就地放大"，且**单图压根点不动**（官方此时开灯箱）。
   * 钉三段：几何判定（纯模型）+ 文案（官方中文字典逐字）+ 模态挂载点。
   */
  { name: '原图预览（灯箱）', patterns: [['lightboxFit', 2], ['bindContentCover', 1], ['IMAGE_PREVIEW_DIALOG', 2]] },
  { name: '错误生命周期', patterns: [['errorClearedBy', 2], ['clearErrorOn', 2], ['setConnectionError', 2]] },
  { name: '浮层关闭语义', patterns: [['sheetDiscardNotice', 2], ['dismissSheetByUser', 2], ['textSettingSeed', 2]] },
  { name: '内部内容隔离', patterns: [['mayExposeBodyToUser', 2], ['userFacingBodyOf', 2], ['scrubCredentials', 2], ['INTERNAL_BODY_HIDDEN', 1]] },
  /*
   * 文件变更流（E226）。E383 修自激时把 `openFilesStream` 改名为 `ensureFilesStream`
   * （语义也变了：**只在作用域变化/用户驱动时**才订阅），本门禁当场红了 —— 这正是它该做的事：
   * 符号没了就是"接线可能被剪断"，改名必须显式改这里，而不是让调用点悄悄消失。
   * 现在钉两端：「确保订阅」与「关掉订阅」（改名后仍要求 ≥2 处：定义 + 调用）。
   */
  { name: '文件变更流', patterns: [['ensureFilesStream', 2], ['closeFilesStream', 2]] },
  { name: '计划模式', patterns: [['planActive|planPending', 2]] },
  { name: '核心版本切换', patterns: [['switchTo', 2], ['rollbackTo', 2]] },
  { name: '插件启停', patterns: [['plugin', 4]] },
  { name: '凭据写入', patterns: [['openCredentialSheet', 2]] },
  /*
   * 后台任务条（P2-2）。这一条正是**本门禁该拦下的那类缺口**：`Jobs` 模型 40 条断言、
   * 中枢一直在维护 `jobs` 字段，而视图里一个消费者都没有（"通道有、没接"）——
   * 编译不报、界面不报，只有肉眼看才发现的缺口。故把它钉成三段接线：
   * 模型判定（orderedJobs/jobListVisible）+ 中枢投影 + 会话头的传参。
   */
  { name: '后台任务条', patterns: [['orderedJobs', 2], ['jobListVisible', 2], ['jobs: this.f.jobs', 1], ['liveJobCount', 2]] },
  /*
   * 主区兜底（E343）。它同样是"接线断了不会有任何症状"的那一类，**后果更重**：
   * `MainShell` 只分派诊断/连接/会话三块，剩下的工作区/设置/核心由 `TabContentView` 渲染。
   * 这条接线曾断过——兜底写成 `this.mainContent(...)`（真机栈溢出杀进程，见 E343）。
   * 故钉住"视图里真的绑定了 tabFacade"（它是"剩下的面板归谁渲染"的唯一凭据）。
   */
  { name: '主区兜底', patterns: [['TabContentView\\(\\{ f: this\\.f\\.tabFacade', 1], ['tabFacade', 2]] },
  /*
   * 侧栏可收起（P2-15）。这一条是**功能缺口**而不是"接线断了"：`NavigationState.sidebarExpanded`
   * 长期没有任何控制点（侧栏呈现完全由形态决定），于是官方 AppFrame 那个"收起侧栏腾出宽度"
   * 的动作在本仓做不到。现在钉住三段接线：纯函数判定 + 门面开关 + 视图里的控制点。
   */
  /*
   * 会话搜索（P7-1）。官方 sidebar 的一等能力（`dsh-client-ui-sidebar` 的包描述就是
   * "session multi-level tree, search, grouping, state dots"），我们此前**一个入口都没有**。
   * 钉三段接线：模型合并规则（Host 内容命中 + 本地标题命中）、中枢方法、视图传参。
   * 注意**降级路径也是这条接线的一部分**：真 Host 未挂 `session/search` 时按标题匹配，
   * 本机闭环实测走的就是这条（见 tools/check-core-loop.mjs 的 M2 段）。
   */
  { name: '会话搜索', patterns: [['mergeSessionSearch', 2], ['searchSessions', 2], ['sessionSearchRows', 2]] },
  /*
   * 输入区接管（P7-2）。官方 `dsh-client-ui-approval` / `-user-questions` 都是往
   * `conversation.composer` 槽位注册"只选本会话当前那一条"的组件（composer takeover）。
   * 我们此前把**中枢全量**待决都铺在输入区上方 ⇒ 在会话 A 里能替会话 B 放行（误操作）。
   * 钉三段：焦点规则 + 文案规则 + 视图里的判定方法。
   */
  { name: '输入区接管', patterns: [['pendingForSession', 2], ['takeoverHeadline', 2], ['focusPending', 2]] },
  /*
   * 放弃整组提问（P7-9）。线上帧已取证：官方 `nav.cancel` 让监听器抛
   * `UserQuestionError` / `ASK_CANCELLED`，网关编码成 `{kind:'rejected', error}` ——
   * **不是** `{kind:'next'}`（那是"交给下一个应答者"）。钉三段：
   * 错误对象构造 + 中枢方法 + 视图按钮。
   */
  { name: '放弃整组提问', patterns: [['questionCancelledError', 2], ['cancelQuestionGroup', 2], ['放弃整组问题', 1]] },
  /*
   * 计划待审（P7-10）。官方 `dsh-client-ui-user-questions` 的 `planReviewOf` 把
   * "带 plan-review 意图的单题请求"换成计划面板（计划待审 / 确认执行 / 拒绝 / 去聊天里说）。
   * 钉三段：意图投影 + 收窄判定 + 视图面板。
   */
  { name: '计划待审', patterns: [['intentKind', 2], ['planReviewOf', 2], ['计划待审', 1]] },
  { name: '侧栏收起', patterns: [['sidebarPresentationOf', 2], ['onToggleSidebarExpanded', 2], ['showExpandToggle', 2]] },
  /*
   * 消息图片（P0-3）。官方 `dsh-client-ui-attachment` 往三个槽位注册呈现
   * （`conversation.input.attachments` / `conversation.message.images` / `conversation.trajectory.images`），
   * 后两个槽位的数据是**会话事件里的图片块**——只给不透明引用（`attachment.attachmentId`），
   * 字节另走 `session/attachment`（官方 `ISession.readAttachment` 同一条路）。
   * 我们此前把图片块降级成正文里的字面 `[image]`（真机上用户看到的就是这五个字符）。
   * 钉三段接线：块→引用（投影）+ 引用→URL（中枢读字节并缓存）+ URL→画面（视图）。
   */
  { name: '消息图片', patterns: [['projectImageBlock', 2], ['imageUrlOf', 2], ['MessageImages', 2]] },
  /*
   * 输入区发送图片（P0-4）。官方 `conversation.input.attachments` 槽位的图片走**内联**：
   * `serializeImages()` 直接把 base64 塞进提示词的 `image` 片段（不经过 `fileUploads/upload`），
   * 内容顺序是"图片在前、正文在后"。钉三段接线：图库选择（platform）+ 入列判定（中枢）
   * + 输入区入口（视图按钮与宿主回调）。
   */
  { name: '输入区图片', patterns: [['pickImage', 2], ['attachLocalImage', 2], ['onAddImage', 2]] },
  /*
   * 斜杠命令（P7-13）。官方让命令的生命周期在对话里渲染成一个持久过程节点
   * （`dsh-client-ui-commands`：`command/run`/`command/done`），并且**命令受理即成功**、
   * 处理器报错才保留输入。我们此前两处都不对：命令帧被当内部事件隐掉（执行后界面无反应）、
   * 回执只看 `result.ok`（"没解析出来/处理器报错"也显示「已执行」= 假成功）。
   * 钉三段：回执投影（Wire）+ 执行处读结局（中枢）+ 命令卡（视图）。
   */
  { name: '斜杠命令', patterns: [['projectCommandOutcome', 2], ['commandKind', 3], ['CommandRow', 2]] },
  /*
   * 输入触发管线（P7-14）。官方的 `dsh-client-ui-input-trigger` 是"检出 `@`/`/` → 候选菜单 →
   * 把选中项**替换当前 token**"（`slash/input-consume-token` 带 `{kind:'span', span}`）；
   * 我们此前是"往草稿末尾追加" ⇒ 半截查询词留在正文里（`@src/fo@src/foo.ts`），
   * 而它长得像一条引用、会被 Host 当引用去解析。钉两端：纯模型（识别 + 替换）与视图调用点。
   */
  { name: '输入触发', patterns: [['detectTrigger', 2], ['applyPick', 2], ['draftAfterPick', 2]] },
  /*
   * 提交失败后的草稿恢复（P7-15）。官方的 composer sink 是"乐观清空 + 失败后**只在
   * 用户没动过输入框时**还回去"（`dsh-client-ui-conversation` 的 sink 注释）。我们此前
   * 只管清空：发送失败时用户的长消息凭空消失，只能重敲。钉三段：纯规则 + 中枢的
   * "这次是否已排队"标记 + 视图的恢复调用点。
   */
  { name: '失败恢复草稿', patterns: [['shouldRestoreDraft', 2], ['lastSendQueued', 3], ['draft = submitted', 1]] },
  /*
   * 排队项的两个良性竞态（P7-16）。官方 `dsh-client-ui-conversation` 的注释写明：
   * "A turn closing mid-way (`steer-unavailable`) or a row already claimed by the agent
   * (`queue-item-not-found`) **converges silently**, while a genuine failure surfaces as one
   * composer notice." 我们此前把任何失败都写成红色横幅 ⇒ 连点两下「插话」/轮次刚结束去插话
   * 都会显示"修改待发队列失败"（假失败）。钉两端：纯判定 + 中枢里的分支。
   */
  { name: '队列竞态', patterns: [['isBenignQueueRace', 2], ['QUEUE_ITEM_NOT_FOUND', 2], ['STEER_UNAVAILABLE', 2]] },
  /*
   * 回合产出的文件（P7-21）。官方 `dsh-client-ui-deliverables` 把"本回合写了哪些文件"
   * 作为回合尾部一行可点条目渲染，来源是**成功的写类工具调用**（"whether or not the model
   * remembered to name it"），不读回答正文；只算成功、首次出现顺序 + 去重。
   * 我们此前只有 `deliverables/presented` 事件（取决于模型是否上报）。
   * 钉三段：纯推导 + 行组件 + 宿主打开回调（读内容 **并** 切到能看见预览的页面）。
   */
  { name: '产出文件', patterns: [['producedFilesOf', 2], ['ProducedFilesRow', 2], ['openProducedFile', 2]] },
  /*
   * 模型请求的重试行（P7-18）。上游 `llm/retry` 携带 `{retry, maxRetries, delayMs, mode, failure}`
   * （`dsh-llm-retry` 的类型逐字），官方据此渲染一个**带倒计时**的节点；我们此前只读 `retry`
   * 拼个 title、正文空白 ⇒ 设备网络最差时用户看到"出错了 + 一片空白"。钉三段：投影（中枢读五个槽位）
   * + 两段文案（纯模型）+ 行组件（含每秒倒计时）。
   */
  /*
   * 重试行（P7-18，P8-6 改为"整条链一行"）。P8-6 把文案换成官方 `message.retry.status` 一行模板、
   * 把 id 规则抽成纯函数（同链一条）⇒ 本门禁必须跟着改：**改名/改结构时它必须显式改这里**，
   * 而不是让调用点悄悄消失（这正是它的用途）。
   */
  { name: '重试行', patterns: [['retryStatusLine', 2], ['retryItemId', 2], ['RetryRow', 2]] },
  /*
   * 失败文案表（P7-19）。上游有一张权威错误码表（46 个码），而本仓此前只有 8+5 个特例，
   * 其余落到兜底 `${code} ${message}` ⇒ 真机上出现「session/conflict session "x" already has cwd …」
   * 这种只有开发者读得懂的句子。现在文案表在纯模型里、可达集合可对账，中枢只委托。
   */
  { name: '失败文案', patterns: [['failureText', 2], ['REACHABLE_FAILURE_CODES', 2], ['FAILURE_TEXT_TABLE', 2]] }
];

/**
 * 「不许出现」的接线（E366）。
 *
 * 【为什么要反面规则】`FEATURES` 只能表达"某特征至少出现 N 次"，而这一轮查出的缺陷恰恰是
 * **多了一个不该有的东西**：`AppShell.buildDouble` 自己画了一份 rail surface，把侧栏呈现
 * **硬编码**成 `TrackPresentation.RAIL`，于是双栏下「展开侧栏」是个死按钮（偏好变了、纯函数
 * 判定也变了，只有这一个调用点没问判定）。这类缺陷正面计数拦不住 —— 该在的特征（`sidebarPresentationOf`
 * 的定义与调用）全都在。
 *
 * 【为什么只拦 RAIL，不拦 PANEL / OVERLAY】`RAIL` 在本仓**永远是判定的结果**（形态默认或用户
 * 收起），任何地方把它写成常量就等于绕过了判定；而 `PANEL`（手机抽屉）与 `OVERLAY`（底部标签）
 * 在 `AppShell` 里是**结构上固定**的表面，写常量是对的。
 *
 * 【注释先剥掉】规则命中的是代码；本轮修复留下的那段注释里就写着那个常量名，
 * 不剥注释的话门禁会拦下自己的说明文字。
 */
const FORBIDDEN = [
  {
    /*
     * `accessSync` 会抛异常（`@ohos.file.fs` 的 `13900018 Not a directory` 等），
     * 而本仓近二十处把它当纯布尔谓词用过 —— 其中 `CoreStore.verifyStagedTree()` 的三个
     * "关键件哨兵"正是**靠它来决定要不要给一句说得清的失败**：文件真缺时它抛异常，
     * 那句 `fail('解包结果缺少宿主包…')` 根本走不到（守卫成了崩溃点，E402）。
     * 现在统一走 `hostruntime/core/FileProbe.fileExists()` / `dirExists()`。
     */
    name: '`fs.accessSync` 不得直接使用（它会抛，不是返回 false）',
    dirs: ['hostruntime/src', 'entry/src', 'appstate/src', 'platform/src', 'connection/src'],
    patterns: ['accessSync'],
    allowFiles: ['hostruntime/src/main/ets/core/FileProbe.ets'],
    why: '改用 FileProbe 的 fileExists()/dirExists()：accessSync 在"不是目录/权限不足"时抛异常，'
      + '会让守卫把失败原因换成一个未处理异常'
  },
  {
    name: '侧栏呈现判定不得被硬编码',
    files: ['entry/src/main/ets/view/shell/AppShell.ets'],
    patterns: ['TrackPresentation\\.RAIL']
  }
];

/**
 * 「某文件里**必须**出现某模式」的规则（P8-4b）。
 *
 * 【为什么需要第三种规则】FEATURES 是**全局计数**（符号有没有被调用），FORBIDDEN 是
 * "某文件里**不许**出现某模式"。而这一轮修的是"**某一行必须可换行**"这类**布局性质**：
 * 它在代码里就是一个 `FlexWrap.Wrap`，全局计数说不出"是**哪个**文件里的那一行"。
 * 布局行为本身要真机验收（见 `docs/device-validation.md` D46），但"这行还是不是可换行的"
 * 这件事可以被静态钉住 —— 否则下一次有人为了"少一层 Flex"把它改回 `Row`，谁都不会发现。
 *
 * 【规则怎么定的】每条都对应 `docs/08` P0 §7 点名的一行（操作区被挤压时不得静默消失），
 * 失败信息里写清"这一行为什么必须能换行"，免得下一个人以为是风格要求。
 */
const REQUIRED_IN_FILE = [
  {
    file: 'entry/src/main/ets/view/Composer.ets',
    pattern: 'FlexWrap\\.Wrap',
    why: '输入区工具行必须可换行：手机宽度下固定控件的总宽已超屏宽，'
      + '尾部的「模型」chip 会被挤出屏幕（docs/08 P0 §7）'
  },
  {
    file: 'entry/src/main/ets/view/ConversationHeader.ets',
    pattern: 'FlexWrap\\.Wrap',
    why: '会话头视图切换行必须可换行：轨迹视图下右侧三个动作 + 左侧两个 chip 在手机上超宽，'
      + '会被直接裁掉'
  },
  {
    file: 'entry/src/main/ets/view/TimelineOverview.ets',
    pattern: 'FlexWrap\\.Wrap',
    why: '时间总览统计行必须可换行：末尾的统计项在手机上会被裁掉，而用户不会知道少了东西'
  }
];

/** 剥掉块注释与行注释（只做这一步：规则关心的常量名不会出现在字符串字面量里） */
function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

const problems = [];
for (const rule of REQUIRED_IN_FILE) {
  const src = sources.find((x) => x.path === rule.file);
  if (src === undefined) {
    problems.push(`  ✗ 必含模式规则：受检文件不存在 ${rule.file}`);
    continue;
  }
  if (!new RegExp(rule.pattern).test(stripComments(src.text))) {
    problems.push(`  ✗ ${rule.file} 里找不到 "${rule.pattern.replace(/\\/g, '')}"：${rule.why}`);
  }
}

for (const f of FEATURES) {
  for (const [pattern, min] of f.patterns) {
    const { n, where } = count(pattern);
    if (n < min) {
      problems.push(`  ✗ ${f.name}：接线 "${pattern}" 只找到 ${n} 处（期望 ≥${min}）`);
    }
  }
}

for (const rule of FORBIDDEN) {
  /*
   * 反面规则支持两种范围：`files`（点名若干文件）与 `dirs`（某个目录下**所有**文件）。
   * 后者是这一轮加的：`accessSync` 这种"哪里都不许出现"的模式，一个一个文件列名字
   * 只会在新增文件时漏掉——而漏掉的门禁等于没有。
   */
  const targets = rule.dirs === undefined
    ? rule.files.map((rel) => ({ path: rel, text: (sources.find((x) => x.path === rel) || { text: undefined }).text }))
    : sources.filter((x) => rule.dirs.some((d) => x.path.startsWith(d)));
  for (const t of targets) {
    if (t.text === undefined) {
      problems.push(`  ✗ ${rule.name}：受检文件不存在 ${t.path}`);
      continue;
    }
    if (rule.allowFiles !== undefined && rule.allowFiles.includes(t.path)) {
      continue;
    }
    const body = stripComments(t.text);
    const lines = body.split('\n');
    for (let i = 0; i < lines.length; i++) {
      for (const pattern of rule.patterns) {
        if (new RegExp(pattern).test(lines[i])) {
          problems.push(`  ✗ ${rule.name}：${t.path}:${i + 1} 出现了 "${pattern.replace(/\\/g, '')}"`
            + `（${rule.why === undefined ? '该模式在本仓被禁用' : rule.why}）`);
        }
      }
    }
  }
}

console.log(`# 功能接线回归（扫描 ${files.length} 个文件，${FEATURES.length} 个功能，`
  + `${REQUIRED_IN_FILE.length} 条必含模式，${FORBIDDEN.length} 条反面规则）`);
if (problems.length === 0) {
  console.log('✅ 全部功能的接线都在（中枢实现 + 界面调用点）。');
  process.exit(0);
}
console.log('发现断线或缺调用点：');
for (const p of problems) {
  console.log(p);
}
console.log('\n提示：构建查不出"调用点被删"——这正是本门禁存在的理由（见 E135/E258）。');
process.exit(1);
