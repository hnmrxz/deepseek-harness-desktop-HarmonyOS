/**
 * WebShell —— PC/平板/2in1/折叠展开形态的官方 Web UI 直载壳（v2 架构转向，US1）。
 *
 * ## 这个组件拥有什么（R&D-001）
 *
 * 「桌面形态里如何呈现端侧 dsh host 伺服的官方 Web UI」的全部呈现与生命周期：
 *   · ArkWeb `Web` 组件 + **私有** `WebviewController`（不外泄；宿主只经门面给事实与回调）；
 *   · HostReadyState 状态机驱动的三态呈现：
 *       - BOOTING → 等待页（启动进度文案 + 进度指示；组件内 120 秒看门狗超时降级为 TIMEOUT）；
 *       - READY   → `loadUrl` 加载 `http://127.0.0.1:3120`（本机；远程地址为预留通道，由 US2 接线）；
 *       - FAILED / TIMEOUT → 错误页（诊断文案 + 重试入口），不白屏；
 *   · 加载失败诊断（`onErrorReceive` / `onHttpErrorReceive` 主文档错误 → HTTP 状态/错误码 + URL + 描述）；
 *   · 系统返回键分流：Web 历史可后退 → `backward()`；否则透传门面 `onBackPress`。
 *
 * ## 门面模式（与 AppShell/RemoteShell 同口径）
 *
 * 值型快照 + 方法型闭包，宿主（Index.ets）每次渲染重建 `WebShellFacade`。
 * `@Prop @Watch` 监听门面刷新，以「相位迁移」判定代替逐帧副作用——宿主每次渲染都会
 * 递新门面对象，只有 `hostReadyState` 真正变化或目标地址变化才触发 `loadUrl`。
 *
 * ## 系统返回键的接线方式（T005 契约：`WebShellBackController`）
 *
 * ArkWeb 的 `Web` 组件**没有** onBackPressed 事件——系统返回键到达的是页面
 * （Index.ets 的 `onBackPress` 生命周期）。宿主持 `WebShellBackController`
 * 句柄传入本组件（模式同 `FolderPickerController`），组件在 `aboutToAppear`
 * 注册实现、`aboutToDisappear` 复位；页面返回键经 `handleBackPress()` 转发：
 * 返回 true 表示 Web 已消费（历史后退），false 表示透传结果取自门面
 * `onBackPress`（宿主自己的返回阶梯）。
 *
 * ## 远程直载与断连横幅（T010/T011，US2）
 *
 * REMOTE 模式优先加载 `remoteBaseUrl`（宿主从 `HubSnapshot.activeRemoteHost`
 * 派生；`normalizeWebBaseUrl` 剥 query/fragment——token 是凭据，不该进 Web
 * 历史，认证由 host webserver 的 token→cookie 流程完成，R&D-006）。
 * 远程断连（REMOTE 且曾连上而降级 DEGRADED）时，宿主经门面 `remoteBanner`
 * 提供横幅事实：本组件在 Web 外层显示 `HubBanner`，**Web 内容保留最后状态**
 * （`pageLoaded` 常驻挂载），横幅里提供重新输入凭据的入口。
 *
 * ## 桌面交互语义（T007，US1）
 *
 * 键鼠/hover/右键/快捷键/文本选择全部走 ArkWeb 内建透传：本组件**不挂任何**
 * 手势/按键/悬停拦截器，也不在 Web 上叠加可点击层（错误/等待态只在 Web 不可用
 * 或未加载完成时出现）。`javaScriptAccess(true)` 是官方 SPA 的硬前提；
 * `domStorageAccess`/`fileAccess` 维持默认关闭，不放宽任何安全域。
 *
 * ## 响应式布局（T009，US1）
 *
 * WebShell 不施加任何固定尺寸约束：根 Stack 与 Web 一律 `100%` 铺满宿主给的区域
 * （宿主在 Index.ets 里用 `layoutWeight(1)` 分配主区）。窗口 resize / 横竖屏 / 分屏
 * → 父容器尺寸变化 → ArkWeb 渲染面跟随组件边界自动重排 → 官方 UI 的媒体查询
 * 重新求值。**不需要也不应添加显式窗口监听**——那只会引入重复布局来源。
 *
 * ## localhost 明文 HTTP（R&D-005）
 *
 * `http://127.0.0.1:3120` 为端侧 host 伺服地址（hostcore main.js 以
 * `--port 3120 --trusted-host 127.0.0.1:3120` 启动 dsh-web-app）。HarmonyOS
 * ArkWeb 对 localhost 明文默认不强制拦截，模块已有 `ohos.permission.INTERNET`，
 * 本波次不新增任何网络放行配置；若真机验证被拦截，再走模块网络配置调整
 * （见 spec.md Edge Cases 与 plan.md R&D-005）。
 *
 * ## 形态参数的消费（T030）
 *
 * 门面 `formFactor` **真的被读**（`overlayInsetVp()`，等待/错误覆盖层的横向留白），
 * 而不是收下就丢——收下不读的契约字段是死码：路由条件改变时它不会跟着变，只会撒谎。
 *
 * ## DESKTOP_LIKE 的「切远程」最小入口（T030）
 *
 * 官方 Web UI 正常呈现时**不叠加任何原生入口**（与官方 100% 一致 + 不与其自带控件打架）。
 * 但 `desktopSurface` 只有 Web / 连接页 / 诊断页三支，原生设置页不在渲染树上 ⇒
 * 桌面形态下用户**没有任何办法**进入远程模式。因此把入口放在"屏幕上本来就是我们自己的
 * 页面"的那两处（host 启动失败/超时、官方前端加载失败）：门面 `onConnectRemote`
 * 给出「连接远程主机…」，「重试 / 重新加载」仍是主按钮。官方 UI 一旦可用，
 * 这颗按钮随之消失——它不是常驻 chrome。
 */

import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Fs, HarmonyIconSize, HubPhase, RunMode, SemanticColor, Sp } from 'appstate';
import { HubBanner } from '../HubBanner';

/*
 * 【旁路诊断（2026-09-21 加）】本组件此前**没有任何日志**，于是"相位到 READY 但 Web 一直是
 * about:blank"在设备上完全不可定位——只能看到屏幕停在等待页。这几行把**相位迁移**与
 * **loadUrl 时序**打到 hilog（前缀 `WEBSHELL`），是这套直载链路唯一的可观测面：
 * 它当场抓到了两个真缺陷（初始 about:blank 抢占导航、直载未带 token），见
 * `webSurface().onPageEnd` 与 `WebShellFacade.localEntryUrl` 的注释。**不要删**：
 * 任何"打不开官方 UI"的回归都会回到这三行读数上。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'HDSH-WebShell';

/**
 * 初始 `about:blank` 抢占导航后的**有界**补发次数（见 `webSurface().onPageEnd`）。
 * 取 3：正常情况第 1 次补发就装上；宿主真的不可达时不会变成无限重载。
 */
const EMPTY_PAGE_PREEMPT_MAX: number = 3;

// ───────────────────────── 契约类型 ─────────────────────────

/**
 * 渲染路线的形态维度（路由矩阵由 Index.ets 终裁；本枚举是 WebShell 契约的入参）。
 *
 * 【为什么本地定义】appstate 的 LayoutController formFactor 判定（T003）与本组件
 * 解耦：路由矩阵算出 DESKTOP_LIKE → 挂 WebShell；本组件只读结论，不参与形态判定。
 */
export enum WebShellFormFactor {
  /** 手机 / 折叠闭合（此形态不挂 WebShell，枚举保留以保证契约完整） */
  PHONE = 'phone',
  /** 平板 / 2in1 / 折叠展开 */
  DESKTOP_LIKE = 'desktop-like'
}

/**
 * host 就绪状态机（plan.md Data Model：BOOTING / READY / FAILED / TIMEOUT）。
 *
 * 【为什么本地定义】appstate 的 `HostReadyState` 是**远程主机 readiness 握手**的
 * 状态（unknown/probing/ready/not-ready），与端侧 host 启动生命周期（BOOTING 起步、
 * 可超时）不是同一台状态机；appstate 本波次冻结，故契约枚举收在组件文件内。
 * TIMEOUT 即可由宿主上报，也可由本组件的启动看门狗在 BOOTING 超过阈值后本地降级。
 */
export enum WebHostReadyState {
  /** 端侧 host 启动中（解包核心 / 拉起进程 / 等待端口就绪） */
  BOOTING = 'booting',
  /** host 就绪，官方 Web UI 可加载 */
  READY = 'ready',
  /** host 启动失败（宿主判定） */
  FAILED = 'failed',
  /** 启动超时（宿主判定或本组件看门狗降级） */
  TIMEOUT = 'timeout'
}

/** Web 加载失败诊断（错误码 + URL + 描述；T008「加载失败诊断信息」的载体） */
export interface WebLoadError {
  /** HTTP 状态码（HTTP 错误）或网络/资源错误码（onErrorReceive） */
  code: number;
  /** 出错的 URL（主文档） */
  url: string;
  /** 原始描述（`getErrorInfo` / `getReasonMessage`，如实透传） */
  description: string;
}

/**
 * 远程断连横幅的事实与动作（T011，US2）。宿主在「REMOTE + 曾连上 + DEGRADED」
 * 时提供；横幅的显示归本组件（Web 外层），判据与副作用归宿主——与全仓的
 * 「呈现归组件、判定归宿主」纪律一致。
 */
export interface WebRemoteBanner {
  /** 已连接 Host 的 authority（横幅事实行） */
  authority: string;
  /** 中枢最近的错误文案（远程降级时横幅主行显示固定文案，此值留作事实行补充） */
  errorText: string;
  /** 活动逻辑流数（横幅事实行） */
  streams: number;
  /** 协议旁路日志尾部（可为空数组） */
  traceTail: string[];
  /** 动作：打开连接诊断页（导航，宿主职责） */
  onOpenDiagnostics: () => void;
  /**
   * 动作：重新输入连接凭据（回连接页，T012 的桌面流程入口）。
   * 远程连接与传输层的自动重试**不受影响**——用户只是去改凭据，不是断开。
   */
  onReenterCredentials: () => void;
}

/** WebShell 的门面契约（plan.md Data Model；宿主 Index.ets 每次渲染重建） */
export interface WebShellFacade {
  /**
   * 渲染形态（路由矩阵结论的只读投影）。
   *
   * 【消费点】`overlayInsetVp()`：等待/错误覆盖层的内容内边距按形态取值。
   * 今天 WebShell 只挂 DESKTOP_LIKE（PHONE 走原生范式），所以这条分支的**实际效果**
   * 是"桌面形态给宽留白、手机形态给窄留白"；保留 PHONE 一支不是为了将来，
   * 而是因为契约里声明的形态必须真的被**读**——写死一个常量会让这个字段沦为死码，
   * 而路由条件一旦变化（如折叠展开态改走原生），死码不会跟着变、只会继续撒谎。
   */
  formFactor: WebShellFormFactor;
  /** 运行模式：LOCAL 加载 localBaseUrl；REMOTE 优先加载 remoteBaseUrl（US2 接线） */
  runMode: RunMode;
  /** host 就绪状态（状态机驱动三态呈现） */
  hostReadyState: WebHostReadyState;
  /** 本机官方 UI 基址（空串时回退 DEFAULT_LOCAL_BASE_URL） */
  localBaseUrl: string;
  /**
   * 本机官方 UI 的**带凭据入口地址**（`dsh web` stdout 打印的那一条：`<base>/?token=…`）。
   *
   * 【为什么不能只用 localBaseUrl（2026-09-21 设备实测）】宿主对**不带 token** 的
   * `GET /` 返回 401，正文是 `dsh web authentication required; reopen the URL printed
   * by dsh web.` ⇒ 用基址直载只会把这一行文本画在屏幕上，官方 UI 起不来（实测读数：
   * 宿主侧 `IN-REQ GET / ... cookie=(none)`，Web 组件拿到 401 页）。
   * 宿主的设计就是"用打印出来的 URL 打开"——token 经 `?token=` 换 cookie 后 SPA 才可用，
   * 官方桌面端（`dsh web` 自动开浏览器）走的也是同一条。空串 = 无凭据可用 ⇒ 退回基址。
   *
   * 【已知代价】token 会进入 Web 历史（`normalizeWebBaseUrl` 对远程地址刻意剥 query 的理由）。
   * 更干净的形态是把宿主下发的会话 cookie 直接喂给 ArkWeb 的 cookie 存储（`WebCookieManager`），
   * 但那需要一个**当前没有暴露**的 cookie 值（连接层的 224B 签名 cookie）——待接线，见 `docs/81` 己档。
   */
  localEntryUrl: string;
  /** 远程官方 UI 基址（activeRemoteHost 派生；本波次预留，空串 = 未连接） */
  remoteBaseUrl: string;
  /**
   * 宿主侧已知加载错误的预留通道（US2 断连/认证失败接线用）。
   * 组件内部 onErrorReceive/onHttpErrorReceive 检测到的错误优先于本字段。
   */
  webLoadError?: WebLoadError;
  /**
   * 远程断连横幅事实（T011）：REMOTE 且曾连上（hubConnected）而中枢降级
   * DEGRADED 时宿主提供；undefined = 不显示。Web 内容保留最后状态，
   * 横幅显示在本组件的 Web 外层（R&D-006）。
   */
  remoteBanner?: WebRemoteBanner;
  /** BOOTING 等待页的进度文案（宿主从 CorePhase 投影，如「正在解包核心」；空/缺省用默认文案） */
  bootStatusText?: string;
  /**
   * 连接远程主机（T030：DESKTOP_LIKE 的**最小原生入口**）。
   *
   * 【为什么只有错误态给】官方 Web UI 正常呈现时不得叠加任何原生入口（与官方
   * 像素级一致 + 不与其自带控件打架）；而错误/超时态屏幕上本来就是我们自己的页面，
   * 此时补一个"本机起不来时还能连远程主机"的逃生梯，既不动官方 UI，也填上真实空白：
   * 桌面形态的原生设置页不在渲染树上，「设置 → 运行模式 → 远程」够不着。
   *
   * 【为什么是可选的】能力未接线（`undefined`）时按钮整颗不渲染——
   * 摆一个点不动的按钮比没有按钮更糟（本仓纪律）。
   */
  onConnectRemote?: () => void;
  /** 重试（错误页按钮）：宿主重新发起 host 就绪检查 */
  onRetry: () => void;
  /** 重新加载（加载失败页按钮）：宿主可借机复检 host / 记录日志 */
  onReload: () => void;
  /**
   * 系统返回键的兜底（Web 历史不可后退时透传）。
   * 返回 true = 宿主已消费；false = 交还系统默认行为。
   */
  onBackPress: () => boolean;
}

// ───────────────────────── 常量 ─────────────────────────

/** 本机官方 Web UI 基址（hostcore 启动参数 `--port 3120 --trusted-host 127.0.0.1:3120` 的既定事实） */
export const DEFAULT_LOCAL_BASE_URL: string = 'http://127.0.0.1:3120';

/**
 * host 启动看门狗阈值（毫秒）。首次启动含核心解包，阈值取宽（120 秒）；
 * 超时后等待页降级为 TIMEOUT 错误页 + 重试，不永久等待（spec.md Edge Case「不白屏」）。
 */
export const HOST_BOOT_TIMEOUT_MS: number = 120000;

/**
 * 系统返回键的宿主侧句柄（T005 契约；模式沿用 `FolderPickerController`：
 * 宿主持句柄、组件注册实现）。
 *
 * ArkWeb 的 `Web` 组件没有 onBackPressed——系统返回键到达的是页面
 * `onBackPress` 生命周期，宿主经本句柄转发给 WebShell：
 * true = Web 已消费（历史后退）；false = 未消费（走宿主自己的返回阶梯）。
 */
export class WebShellBackController {
  private handler: () => boolean = () => false;

  /** 由 `WebShell.aboutToAppear` 注册；`aboutToDisappear` 复位为「未消费」 */
  register(handler: () => boolean): void {
    this.handler = handler;
  }

  /** 页面 `onBackPress` 调用：组件未挂载时恒为 false（不把返回键落进已解绑的 Web） */
  handleBackPress(): boolean {
    return this.handler();
  }
}

/**
 * 远程直载地址规整（T010）：`activeRemoteHost.hostAddress` 可能是
 * `host:port`、`http://host:port/` 或粘贴的完整启动链接（含 `?token=…`）。
 *
 * 【为什么剥掉 query/fragment】token 是**凭据**（D2 §2.1：持有它就等于持有
 * Host 的完整会话权限），不该进 Web 历史/地址栏；认证由 host webserver 的
 * 既有 token→cookie 流程完成，Web 侧无需注入（plan.md R&D-006）。
 * 【为什么补 scheme】`host:port` 形态没有 `://` 时 ArkWeb 无法解析——
 * 补 `http://`（局域网直连场景与 R&D-005 的明文口径一致）。
 */
export function normalizeWebBaseUrl(raw: string): string {
  let url: string = raw.trim();
  if (url.length === 0) {
    return '';
  }
  const cut: number = url.search(/[?#]/);
  if (cut >= 0) {
    url = url.substring(0, cut);
  }
  if (url.indexOf('://') < 0) {
    url = `http://${url}`;
  }
  while (url.length > 0 && url.charAt(url.length - 1) === '/') {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

// ───────────────────────── 组件 ─────────────────────────

@Component
export struct WebShell {
  /** 门面（宿主每次渲染重建；@Watch 以相位迁移判定代替逐帧副作用） */
  @Prop @Watch('onFacadeChanged') f: WebShellFacade;

  /** 返回键句柄（宿主持有、本组件注册实现；页面 onBackPress 经它转发，T005） */
  @Prop backController: WebShellBackController;

  /** Web 控制器——私有持有，不外泄（契约：输出无，内部状态全部内聚） */
  private controller: webview.WebviewController = new webview.WebviewController();
  /** 最近一次成功发起 loadUrl 的目标地址（幂等去重 + 目标变化重载的判定基准） */
  private loadedTarget: string = '';
  /** 上一次见到的相位（迁移检测；宿主每帧递新门面，不能靠"值变了"当迁移） */
  private lastPhaseSeen: WebHostReadyState = WebHostReadyState.BOOTING;
  /** 启动看门狗定时器句柄（-1 = 未挂） */
  private bootWatchdogId: number = -1;

  /** 官方 UI 首屏是否已加载完成（onPageEnd 见证；决定 Web 是否常驻挂载） */
  @State pageLoaded: boolean = false;
  /** 主文档加载失败诊断（内部检测；undefined = 无） */
  @State loadError: WebLoadError | undefined = undefined;
  /** 主文档加载进度（0–100，来自 onProgressChange） */
  @State loadProgress: number = 0;
  /** 看门狗超时标志（BOOTING 超过阈值后置位，等待页降级为 TIMEOUT 错误页） */
  @State bootTimedOut: boolean = false;
  /** 初始空白页抢占导航后的补发计数（有界，见 `EMPTY_PAGE_PREEMPT_MAX`） */
  private preemptRetries: number = 0;

  // ── 生命周期 ──

  aboutToAppear(): void {
    this.lastPhaseSeen = this.f.hostReadyState;
    hilog.info(DOMAIN, TAG, 'WEBSHELL appear phase=%{public}s runMode=%{public}s localBase=%{public}s remoteBase=%{public}s',
      this.f.hostReadyState, this.f.runMode, this.f.localBaseUrl, this.f.remoteBaseUrl);
    if (this.f.hostReadyState === WebHostReadyState.BOOTING) {
      this.startBootWatchdog();
    }
    // T005：注册返回键实现（组件挂载期间，Web 历史后退优先于宿主的返回阶梯）
    this.backController.register(() => this.handleBackPress());
  }

  aboutToDisappear(): void {
    this.clearBootWatchdog();
    // 复位为「未消费」：组件已卸载，宿主的返回键不得再落进已解绑的 Web
    this.backController.register(() => false);
  }

  /** 门面刷新（宿主每次渲染）：只对"真迁移"与"目标地址变化"做功 */
  private onFacadeChanged(propName: string): void {
    const phase: WebHostReadyState = this.f.hostReadyState;
    hilog.info(DOMAIN, TAG, 'WEBSHELL facade prop=%{public}s phase=%{public}s last=%{public}s pageLoaded=%{public}s loadedTarget=%{public}s',
      propName, phase, this.lastPhaseSeen, String(this.pageLoaded), this.loadedTarget);
    if (phase !== this.lastPhaseSeen) {
      if (phase === WebHostReadyState.BOOTING) {
        this.startBootWatchdog();
      } else {
        this.clearBootWatchdog();
      }
      if (phase === WebHostReadyState.READY) {
        this.bootTimedOut = false;
        // 新一轮就绪：补发额度重置（上一轮用掉的不该带到这一轮）
        this.preemptRetries = 0;
        // host 曾失败/超时后恢复：旧页面内容不可信，清空目标强制重载
        if (this.lastPhaseSeen === WebHostReadyState.FAILED
          || this.lastPhaseSeen === WebHostReadyState.TIMEOUT) {
          this.loadedTarget = '';
        }
      }
      this.lastPhaseSeen = phase;
    }
    if (phase === WebHostReadyState.READY) {
      this.maybeLoadTarget();
    }
  }

  // ── 状态机辅助 ──

  /** 生效相位：宿主上报 BOOTING 且看门狗超时 → 本地降级为 TIMEOUT */
  private effectivePhase(): WebHostReadyState {
    if (this.f.hostReadyState === WebHostReadyState.BOOTING && this.bootTimedOut) {
      return WebHostReadyState.TIMEOUT;
    }
    return this.f.hostReadyState;
  }

  /**
   * 加载目标：远程模式优先 remoteBaseUrl（T010：activeRemoteHost 派生，经
   * `normalizeWebBaseUrl` 规整——剥凭据 query、补 scheme），否则本机基址
   * （缺省回退默认端口事实）。目标变化（activeRemoteHost/runMode 变）即重载。
   */
  private targetUrl(): string {
    if (this.f.runMode === RunMode.REMOTE) {
      const remote: string = normalizeWebBaseUrl(this.f.remoteBaseUrl);
      if (remote.length > 0) {
        return remote;
      }
    }
    // 本机：优先带凭据入口（宿主 401 的判据是"有没有 token"，不是"基址对不对"）
    if (this.f.localEntryUrl.length > 0) {
      return this.f.localEntryUrl;
    }
    return this.f.localBaseUrl.length > 0 ? this.f.localBaseUrl : DEFAULT_LOCAL_BASE_URL;
  }

  /** 幂等加载：仅在 READY、目标非空且与已加载目标不同时执行 loadUrl */
  private maybeLoadTarget(): void {
    if (this.f.hostReadyState !== WebHostReadyState.READY) {
      hilog.info(DOMAIN, TAG, 'WEBSHELL maybeLoad skip phase=%{public}s', this.f.hostReadyState);
      return;
    }
    const target: string = this.targetUrl();
    if (target.length === 0 || this.loadedTarget === target) {
      hilog.info(DOMAIN, TAG, 'WEBSHELL maybeLoad skip target=%{public}s loadedTarget=%{public}s',
        target, this.loadedTarget);
      return;
    }
    this.loadedTarget = target;
    this.pageLoaded = false;
    this.loadError = undefined;
    this.loadProgress = 0;
    hilog.info(DOMAIN, TAG, 'WEBSHELL loadUrl target=%{public}s', target);
    try {
      this.controller.loadUrl(target);
      hilog.info(DOMAIN, TAG, 'WEBSHELL loadUrl returned normally target=%{public}s', target);
    } catch (e) {
      // 控制器尚未关联（Web 未挂载）或已解绑：回滚目标，待 onControllerAttached 再试
      hilog.error(DOMAIN, TAG, 'WEBSHELL loadUrl THREW err=%{public}s', JSON.stringify(e));
      this.loadedTarget = '';
    }
  }

  /** 启动看门狗：重置超时标志并重新计时 */
  private startBootWatchdog(): void {
    this.clearBootWatchdog();
    this.bootTimedOut = false;
    this.bootWatchdogId = setTimeout(() => {
      this.bootTimedOut = true;
    }, HOST_BOOT_TIMEOUT_MS);
  }

  private clearBootWatchdog(): void {
    if (this.bootWatchdogId >= 0) {
      clearTimeout(this.bootWatchdogId);
      this.bootWatchdogId = -1;
    }
  }

  /** 仅 http(s) URL 计入加载见证（排除 about:blank 初始页的 onPageBegin/End 噪声） */
  private isHttpUrl(url: string): boolean {
    return url.indexOf('http://') === 0 || url.indexOf('https://') === 0;
  }

  /** 生效的加载错误：内部检测优先，宿主预留通道兜底 */
  private effectiveLoadError(): WebLoadError | undefined {
    if (this.loadError !== undefined) {
      return this.loadError;
    }
    return this.f.webLoadError;
  }

  // ── 动作 ──

  /**
   * 系统返回键分流（公开方法；宿主在页面 onBackPress 里调用）。
   * Web 历史可后退 → backward() 并返回 true；否则透传门面 onBackPress。
   */
  handleBackPress(): boolean {
    if (this.pageLoaded) {
      try {
        if (this.controller.accessBackward()) {
          this.controller.backward();
          return true;
        }
      } catch (e) {
        // 控制器未关联（组件已卸载）——透传给宿主
      }
    }
    return this.f.onBackPress();
  }

  /** 错误页「重试」：复位本地失败态并通知宿主重新发起 host 就绪检查 */
  private retryHost(): void {
    this.pageLoaded = false;
    this.loadError = undefined;
    this.loadProgress = 0;
    this.loadedTarget = '';
    this.startBootWatchdog();
    this.f.onRetry();
  }

  /** 加载失败页「重新加载」：通知宿主（可借机复检 host/记日志）后重新 loadUrl 目标 */
  private reloadWeb(): void {
    this.f.onReload();
    this.loadError = undefined;
    this.pageLoaded = false;
    this.loadProgress = 0;
    this.loadedTarget = '';
    this.maybeLoadTarget();
  }

  // ── 呈现判定 ──

  /**
   * 覆盖层（等待/错误）的内容内边距（vp）——`formFactor` 的**唯一消费点**。
   *
   * 桌面形态的等待/错误页出现在整块大屏中央，文案行若贴着屏边读起来会散；
   * 手机形态没有那么多横向余量（窄屏上大留白会挤掉正文宽度）。取值全部走
   * `Sp` 令牌阶梯，不写裸值（design-token 门禁）。
   */
  private overlayInsetVp(): number {
    return this.f.formFactor === WebShellFormFactor.PHONE ? Sp.L : Sp.XXXL;
  }

  /**
   * 最小原生入口的文案。
   *
   * 【为什么随模式变】本机模式下它是"换个目标试试"（本机核心起不来 ⇒ 远程是第二条路）；
   * 远程模式下本机早已不是问题，同一个动作的实际语义是"重新走一次远程握手/换台主机"。
   * 一颗按钮说两种意思而文案不变，用户只能靠猜。
   */
  private remoteEntryLabel(): string {
    return this.f.runMode === RunMode.REMOTE ? '重新连接远程主机…' : '连接远程主机…';
  }

  /** Web 是否挂载：READY，或首屏已加载完成（保持挂载以保留已加载内容，断连横幅归 T011） */  private showsWeb(): boolean {
    return this.f.hostReadyState === WebHostReadyState.READY || this.pageLoaded;
  }

  private showsBootWait(): boolean {
    return this.effectivePhase() === WebHostReadyState.BOOTING && !this.pageLoaded;
  }

  private showsHostError(): boolean {
    const phase: WebHostReadyState = this.effectivePhase();
    return (phase === WebHostReadyState.FAILED || phase === WebHostReadyState.TIMEOUT)
      && !this.pageLoaded;
  }

  private showsLoadError(): boolean {
    return this.effectivePhase() === WebHostReadyState.READY
      && this.effectiveLoadError() !== undefined;
  }

  private showsWebLoading(): boolean {
    return this.effectivePhase() === WebHostReadyState.READY
      && !this.pageLoaded
      && this.effectiveLoadError() === undefined;
  }

  // ── 文案 ──

  /** 远程模式（文案随路线切换：远程是「连接」，本机才是「启动」——不说谎） */
  private isRemote(): boolean {
    return this.f.runMode === RunMode.REMOTE;
  }

  private bootTitleText(): string {
    const status: string = this.f.bootStatusText !== undefined ? this.f.bootStatusText : '';
    return status.length > 0 ? status : '正在启动本地运行环境…';
  }

  /** BOOTING 等待页次行：远程是网络握手，本机才有「解包核心」这回事 */
  private bootWaitHint(): string {
    return this.isRemote()
      ? '正在与远程 Host 建立连接；网络较慢时可能需要多等一会儿。'
      : '首次启动需要解包核心组件，可能需要一两分钟；就绪后将自动进入界面。';
  }

  private hostErrorTitle(): string {
    if (this.effectivePhase() === WebHostReadyState.FAILED) {
      return this.isRemote() ? '远程连接失败' : '启动失败';
    }
    return this.isRemote() ? '远程连接超时' : '启动超时';
  }

  private hostErrorDetail(): string {
    if (this.effectivePhase() === WebHostReadyState.FAILED) {
      return this.isRemote()
        ? '无法连接远程主机。可点击重试；请确认远程 Host 正在运行、地址正确且网络可达。'
        : '本地运行环境未能启动。可点击重试；若多次失败，请重启应用后再试。';
    }
    return this.isRemote()
      ? `连接远程主机超时（${HOST_BOOT_TIMEOUT_MS / 1000} 秒仍未就绪）。可点击重试；请检查网络后再试。`
      : `本地运行环境启动超时（${HOST_BOOT_TIMEOUT_MS / 1000} 秒仍未就绪）。可点击重试；多次超时请重启应用。`;
  }

  private loadErrorUrlLine(): string {
    const err: WebLoadError | undefined = this.effectiveLoadError();
    return err !== undefined ? err.url : '';
  }

  private loadErrorCodeLine(): string {
    const err: WebLoadError | undefined = this.effectiveLoadError();
    if (err === undefined) {
      return '';
    }
    return err.description.length > 0 ? `错误 ${err.code} · ${err.description}` : `错误 ${err.code}`;
  }

  // ── 视图 ──

  @Builder
  webSurface() {
    /*
     * 官方 Web UI 直载。src 固定 about:blank 占位（ArkWeb 约束：src 不随状态动态改，
     * 一律经 controller.loadUrl）；就绪后由 maybeLoadTarget 装载真实地址。
     *
     * 属性口径（T007）：javaScriptAccess(true) 是官方 SPA 硬前提；domStorageAccess /
     * fileAccess 维持默认关闭，不放宽安全域；不加任何手势/按键/悬停拦截器——
     * 键鼠/hover/右键/快捷键/文本选择全部由 ArkWeb 内建透传给页面。
     */
    Web({ src: 'about:blank', controller: this.controller })
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .fileAccess(false)
      .onControllerAttached(() => {
        // 控制器关联完成是 loadUrl 的合法时机（此前调用会抛 17100001）
        hilog.info(DOMAIN, TAG, 'WEBSHELL controllerAttached phase=%{public}s', this.f.hostReadyState);
        this.maybeLoadTarget();
      })
      .onPageBegin((event: OnPageBeginEvent) => {
        // 新一轮主文档导航开始：清掉上一轮的失败诊断（仅 http(s) 计入）
        hilog.info(DOMAIN, TAG, 'WEBSHELL pageBegin url=%{public}s', event.url);
        if (this.isHttpUrl(event.url)) {
          this.loadError = undefined;
        }
      })
      .onPageEnd((event: OnPageEndEvent) => {
        hilog.info(DOMAIN, TAG, 'WEBSHELL pageEnd url=%{public}s', event.url);
        if (this.isHttpUrl(event.url)) {
          this.pageLoaded = true;
        }
        /*
         * 【2026-09-21 修复：初始 about:blank 抢占导航，导致官方 UI 永远装不上】
         * 实测（2in1 模拟器 + PC 宿主，2026-09-21）：`onControllerAttached` 里调
         * `loadUrl(http://127.0.0.1:3120)` **正常返回**，但紧接着组件自己首帧的
         * `about:blank` 导航才开始并**赢下这次导航**（读数：`pageBegin/End url=about:blank`
         * 晚于 `loadUrl returned normally`）。此后 `loadedTarget` 已等于目标值，
         * `maybeLoadTarget()` 幂等守卫把后续每一次都挡掉（`skip target=… loadedTarget=…`）
         * ⇒ Web 永远停在 about:blank，界面停在"正在加载界面…"。宿主侧可见证据：
         * 全程只有 `ua=libcurl-agent/1.0`（应用原生 HTTP）请求，**没有任何浏览器 UA 请求**。
         *
         * 修法：空白页收尾后若目标仍未装载，清掉幂等标记补发一次。**必须有界**
         * （`EMPTY_PAGE_PREEMPT_MAX`）——否则一旦宿主真的不可达就会变成无限重载。
         */
        if (!this.pageLoaded
          && this.f.hostReadyState === WebHostReadyState.READY
          && this.loadedTarget.length > 0
          && event.url !== this.loadedTarget
          && this.preemptRetries < EMPTY_PAGE_PREEMPT_MAX) {
          this.preemptRetries += 1;
          hilog.info(DOMAIN, TAG, 'WEBSHELL empty-page preempt → retry load (%{public}d/%{public}d)',
            this.preemptRetries, EMPTY_PAGE_PREEMPT_MAX);
          this.loadedTarget = '';
          this.maybeLoadTarget();
        }
      })
      .onProgressChange((event: OnProgressChangeEvent) => {
        this.loadProgress = event.newProgress;
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        hilog.error(DOMAIN, TAG, 'WEBSHELL errorReceive main=%{public}s url=%{public}s code=%{public}d info=%{public}s',
          String(event.request.isMainFrame()), event.request.getRequestUrl(),
          event.error.getErrorCode(), event.error.getErrorInfo());
        // 只把主文档的网络/资源错误升格为整页错误；子资源失败不拦截官方 UI 自身的降级呈现
        if (!event.request.isMainFrame() || !this.isHttpUrl(event.request.getRequestUrl())) {
          return;
        }
        const err: WebLoadError = {
          code: event.error.getErrorCode(),
          url: event.request.getRequestUrl(),
          description: event.error.getErrorInfo()
        };
        this.loadError = err;
      })
      .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
        if (!event.request.isMainFrame() || !this.isHttpUrl(event.request.getRequestUrl())) {
          return;
        }
        const err: WebLoadError = {
          code: event.response.getResponseCode(),
          url: event.request.getRequestUrl(),
          description: event.response.getReasonMessage()
        };
        this.loadError = err;
      })
      // 响应式（T009）：铺满父容器，无固定尺寸；窗口变化 → 组件边界变化 → ArkWeb 自动重排
      .width('100%')
      .height('100%')
  }

  /** BOOTING 等待页：启动进度文案 + 进度指示（host 就绪后自动消失） */
  @Builder
  bootWaitSurface() {
    Column({ space: Sp.M }) {
      LoadingProgress()
        .width(Sp.XXXL)
        .height(Sp.XXXL)
        .color(SemanticColor.BRAND)
      Text(this.bootTitleText())
        .fontSize(Fs.TITLE_S)
        .fontWeight(FontWeight.Medium)
        .fontColor(SemanticColor.TEXT_PRIMARY)
      Text(this.bootWaitHint())
        .fontSize(Fs.SECONDARY)
        .fontColor(SemanticColor.TEXT_TERTIARY)
        .textAlign(TextAlign.Center)
        .padding({ left: this.overlayInsetVp(), right: this.overlayInsetVp() })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(SemanticColor.BG)
  }

  /** FAILED / TIMEOUT 错误页：诊断文案 + 重试（宿主 onRetry → 重新就绪检查） */
  @Builder
  hostErrorSurface() {
    Column({ space: Sp.M }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(HarmonyIconSize.NAV)
        .fontColor([SemanticColor.ALERT])
      Text(this.hostErrorTitle())
        .fontSize(Fs.TITLE_S)
        .fontWeight(FontWeight.Medium)
        .fontColor(SemanticColor.TEXT_PRIMARY)
      Text(this.hostErrorDetail())
        .fontSize(Fs.SECONDARY)
        .fontColor(SemanticColor.TEXT_TERTIARY)
        .textAlign(TextAlign.Center)
        .padding({ left: this.overlayInsetVp(), right: this.overlayInsetVp() })
      Row({ space: Sp.S }) {
        Button('重试')
          .controlSize(ControlSize.NORMAL)
          .onClick(() => {
            this.retryHost();
          })
        /*
         * T030：本机核心起不来时的逃生梯——桌面形态的「设置 → 运行模式 → 远程」
         * 不在渲染树上，没有这一颗按钮用户就彻底切不到远程主机（见门面 `onConnectRemote`）。
         */
        if (this.f.onConnectRemote !== undefined) {
          Button(this.remoteEntryLabel())
            .controlSize(ControlSize.NORMAL)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontColor(SemanticColor.BRAND)
            .onClick(() => {
              const goRemote: (() => void) | undefined = this.f.onConnectRemote;
              if (goRemote !== undefined) {
                goRemote();
              }
            })
        }
      }
      .margin({ top: Sp.S })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(SemanticColor.BG)
  }

  /** 加载失败页：HTTP 状态/错误码 + URL + 原始描述（诊断如实），重新加载动作 */
  @Builder
  loadErrorSurface() {
    Column({ space: Sp.M }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(HarmonyIconSize.NAV)
        .fontColor([SemanticColor.WARNING])
      Text('界面加载失败')
        .fontSize(Fs.TITLE_S)
        .fontWeight(FontWeight.Medium)
        .fontColor(SemanticColor.TEXT_PRIMARY)
      Text(this.loadErrorUrlLine())
        .fontSize(Fs.CODE)
        .fontFamily('monospace')
        .fontColor(SemanticColor.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: this.overlayInsetVp(), right: this.overlayInsetVp() })
      Text(this.loadErrorCodeLine())
        .fontSize(Fs.CAPTION)
        .fontColor(SemanticColor.TEXT_TERTIARY)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: this.overlayInsetVp(), right: this.overlayInsetVp() })
      Row({ space: Sp.S }) {
        Button('重新加载')
          .controlSize(ControlSize.NORMAL)
          .onClick(() => {
            this.reloadWeb();
          })
        // 同 hostErrorSurface：官方前端加载不出来时，远程主机是第二条可用路线
        if (this.f.onConnectRemote !== undefined) {
          Button(this.remoteEntryLabel())
            .controlSize(ControlSize.NORMAL)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontColor(SemanticColor.BRAND)
            .onClick(() => {
              const goRemote: (() => void) | undefined = this.f.onConnectRemote;
              if (goRemote !== undefined) {
                goRemote();
              }
            })
        }
      }
      .margin({ top: Sp.S })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(SemanticColor.BG)
  }

  /** 首屏加载中：Web 已挂载但主文档未完成（about:blank → 官方 UI 之间的过渡态） */
  @Builder
  webLoadingSurface() {
    Column({ space: Sp.S }) {
      LoadingProgress()
        .width(Sp.XXXL)
        .height(Sp.XXXL)
        .color(SemanticColor.BRAND)
      Text(`正在加载界面… ${this.loadProgress}%`)
        .fontSize(Fs.SECONDARY)
        .fontColor(SemanticColor.TEXT_TERTIARY)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(SemanticColor.BG)
  }

  build() {
    /*
     * T011：远程断连横幅显示在 Web 外层（R&D-006）——Web 尽量常驻（pageLoaded 后
     * 即使相位回落也保持挂载，**保留已加载内容**），横幅只是顶部的状态与动作入口，
     * 不与 Web 叠点击层（桌面交互语义不被遮挡，T007）。等待/错误/加载中为覆盖层，
     * 仅在 Web 不可用或未就绪时出现。
     */
    Column() {
      if (this.f.remoteBanner !== undefined) {
        HubBanner({
          errorText: this.f.remoteBanner.errorText,
          authority: this.f.remoteBanner.authority,
          phase: HubPhase.DEGRADED,
          streams: this.f.remoteBanner.streams,
          traceTail: this.f.remoteBanner.traceTail,
          runMode: RunMode.REMOTE,
          webRoute: true,
          onOpenDiagnostics: () => {
            const banner: WebRemoteBanner | undefined = this.f.remoteBanner;
            if (banner !== undefined) {
              banner.onOpenDiagnostics();
            }
          },
          onReenterCredentials: () => {
            const banner: WebRemoteBanner | undefined = this.f.remoteBanner;
            if (banner !== undefined) {
              banner.onReenterCredentials();
            }
          }
        })
      }
      Stack() {
        if (this.showsWeb()) {
          this.webSurface()
        }
        if (this.showsBootWait()) {
          this.bootWaitSurface()
        } else if (this.showsHostError()) {
          this.hostErrorSurface()
        } else if (this.showsLoadError()) {
          this.loadErrorSurface()
        } else if (this.showsWebLoading()) {
          this.webLoadingSurface()
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
