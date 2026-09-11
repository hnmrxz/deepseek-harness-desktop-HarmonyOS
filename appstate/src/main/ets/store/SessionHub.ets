/**
 * 会话中枢（SessionHub）——全应用**唯一**的连接与会话状态所有者。
 *
 * ────────────────────────────────────────────────────────────────────────
 * 存在理由（D1 §7.7.5b，P0）：
 *   规范原文：「全应用**单一**连接池 + 单一会话状态机 + 单一待发队列；
 *   窗口只是视图，不得各自开连接或各自维护会话状态」。
 *
 *   实现依据（系统事实）：HarmonyOS 的 `specified` 启动模式会为不同 key 创建不同的
 *   UIAbility 实例，但官方文档明确这些实例是在**同一个应用进程**中创建的
 *   （见 `platform/src/main/ets/window/WindowRegistry.ets` 的窗口模型说明）。
 *   同一进程 ⇒ 模块级单例被所有窗口共享 ⇒ 把连接放这里就天然是「单一连接池」。
 *
 *   可核查性：`platform.RuntimeSingleton` 给出进程级 runtimeId 与窗口台账。
 *   诊断页展示它们；若两个窗口显示不同 runtimeId，说明单例假设被推翻，
 *   必须改跨进程方案——本文件不掩盖这种可能性。
 * ────────────────────────────────────────────────────────────────────────
 *
 * 流的所有权（精确到条数，便于抓包核对）：
 *   - 1 条物理 mux 连接（`/api/remote.mux`）
 *   - 1 条 `$events` 逻辑流（由 `Connection.start()` 持有）→ 审批/提问/通知
 *   - 1 条 `session/control` 逻辑流 → 队列/作业/投影基线
 *   - 0 或 1 条 `session/follow` 逻辑流 → 当前选中会话的轨迹
 *   切换会话时**先取消**旧的 follow，再开新的；绝不并发两条 follow。
 *
 * 数据来源纪律：
 *   本文件只做「机制 → 呈现契约」的投影，不认识 UI，也不认识上游字段细节之外的策略。
 *   上游事件名与词汇全部来自 `dshcompat`（`RemoteEvents` / `Aliases`），
 *   本文件不出现任何上游字面量。
 */

import { Connection } from 'connection';
import { ConnectionState } from 'connection';
import type { DiagnosticReport, EventSink, HostFacts, RemoteFailure, RpcResult, StreamSink } from 'connection';
import { EVENTS_RESULT_ENDPOINT, getArray, getBoolean, getNumber, getRecord, getString, readPath } from 'connection';
import {
  APPROVAL_ALLOWED_ONCE,
  APPROVAL_REJECTED,
  argsFor,
  classifyEventType,
  ContentSlot,
  eventShapeOf,
  EventFamily,
  EVENT_CREDENTIALS_REFERENCE_UPDATED,
  EVENT_COMMANDS_CHANGE,
  EVENT_SETTINGS_DOCUMENT_UPDATED,
  GATEWAY_ARGUMENTS_INVALID,
  GATEWAY_INPUT_INVALID,
  GATEWAY_SIGNATURE_INVALID,
  isAuditEventType,
  isKnownEventType,
  isSessionListEvent,
  isUserAuthoredEvent,
  mayChangeSessionTitle,
  mayChangeTurnState,
  CREDENTIALS_DESCRIBE_ENDPOINT,
  CREDENTIALS_SET_ENDPOINT,
  CREDENTIALS_UNSET_ENDPOINT,
  CREDENTIAL_REJECTED,
  MODEL_CATALOG_ENDPOINT,
  PLUGIN_INVENTORY_ENDPOINT,
  PROJECTION_TITLE,
  SETTINGS_DESCRIBE_ENDPOINT,
  SETTINGS_CONFLICT,
  SETTINGS_MUTATE_ENDPOINT,
  SETTINGS_REJECTED,
  RemoteEventFrameType,
  SESSION_CANCEL_ENDPOINT,
  SESSION_CONTROL_ENDPOINT,
  SESSION_CREATE_ENDPOINT,
  SESSION_FOLLOW_ENDPOINT,
  SESSION_LIST_ENDPOINT,
  SESSION_PROMPT_ENDPOINT,
  slotBinding,
  SURFACE,
  WATERFALL_APPROVAL,
  WATERFALL_QUESTION
} from 'dshcompat';
import type { SessionEventShape, SlotBinding } from 'dshcompat';
import { projectSessionList } from '../model/SessionList';
import type { SessionListItem } from '../model/SessionList';
import {
  APPROVAL_CHOICE_ALLOW,
  APPROVAL_CHOICE_ALLOW_ALWAYS,
  APPROVAL_CHOICE_DENY,
  indexOfItem,
  makeItem,
  mergeTrajectoryItem,
  PendingKind,
  RiskLevel,
  Speaker,
  ToolState,
  TrajectoryKind
} from '../model/Trajectory';
import type { PendingChoice, PendingItem, TrajectoryItem } from '../model/Trajectory';
import {
  projectCredentials,
  projectSettingsEntries,
  projectDefaultSelection,
  projectModelCatalog,
  projectPluginInventory,
  projectCredentialRefs,
  settingsMutateArgs,
  settingsUnsetArgs,
  SettingsWriteOutcome,
  splitSettingKey
} from '../model/Settings';
import type {
  CredentialItem,
  CredentialWriteResult,
  ModelOption,
  ModelSelection,
  PluginItem,
  SettingGroup,
  SettingsGroupEntry,
  SettingsKeyParts,
  SettingsNamespaceState,
  SettingsWriteResult
} from '../model/Settings';
import {
  commandsListEndpoint,
  commandsListPayload,
  fileReferencesEndpoint,
  fileReferencesPayload,
  projectCommands,
  projectFileReferences,
  projectSessionReferences,
  projectWorkspaceFailure,
  projectWorkspaceListing,
  projectWorkspaceText,
  sessionReferencesEndpoint,
  sessionReferencesPayload,
  workspaceListEndpoint,
  workspaceListPayload,
  workspaceReadEndpoint,
  workspaceReadPayload,
  WORKSPACE_ROOT_REQUEST_PATH
} from '../model/Wire';
import type { CommandCandidate, ReferenceCandidate } from '../model/Wire';
import type { FileNode, FilePreview } from '../model/Workspace';

/** 中枢运行阶段 */
export enum HubPhase {
  /** 未配置 Host */
  IDLE = 'idle',
  /** 正在认证/连接 */
  CONNECTING = 'connecting',
  /** 已连接，事件流就绪 */
  LIVE = 'live',
  /** 连接失败或降级（仍可看缓存与会话内已有数据） */
  DEGRADED = 'degraded'
}

/** 待发队列里的一条（离线时用户已提交但尚未送达的提示词） */
export interface OutboxEntry {
  /** 客户端生成的请求 id（与 prompt 的 requestId 一致，用于去重与回执匹配） */
  requestId: string;
  sessionId: string;
  text: string;
  at: number;
}

/** 中枢快照：UI 只读它，不直接碰连接 */
export interface HubSnapshot {
  phase: HubPhase;
  hostName: string;
  authority: string;
  sessions: SessionListItem[];
  pending: PendingItem[];
  trajectory: TrajectoryItem[];
  selectedSessionId: string;
  selectedTitle: string;
  running: boolean;
  /** `$events` 是否已收到 ready 帧 */
  eventsReady: boolean;
  /** `session/control` 是否已收到 baseline 帧 */
  controlReady: boolean;
  /**
   * 是否已连上 Host（认证 + 载体验证通过），一元能力可用。
   *
   * **与 `phase === LIVE` 不是一回事**：`phase` 会因事件流终止而降级为 `DEGRADED`，
   * 那时一元调用仍然可用。视图判断「该用真实数据还是桩数据」必须用本字段——
   * 用 `phase` 会让「连上了但事件流恰好断了」的时刻又退回桩数据，等于给用户看假会话。
   */
  connected: boolean;
  /** 当前 mux 上的活动逻辑流数（诊断用；正常为 2 或 3） */
  activeStreams: number;
  /** 离线待发条数 */
  outbox: number;
  lastError: string;
  /** 协议旁路日志（诊断页；仅在开启时累积） */
  trace: string[];
  /** 未识别的上游事件类型（自证缺口：设备上跑一次就能看到真实清单） */
  unknownEventTypes: string[];
  /** 模型目录（来自 `session/modelCatalog`；未连接或能力缺失时为空数组） */
  models: ModelOption[];
  /** Host 为未配置会话准备的默认模型选择（无则 undefined，界面保持当前选择） */
  defaultSelection: ModelSelection | undefined;
  /** 插件清单（来自 `pluginInventory/list`） */
  plugins: PluginItem[];
  /** 凭据状态（来自 `settings/describe` 取 refs + `credentials/describe` 取状态）。**永不含明文** */
  credentials: CredentialItem[];
  /** Host 设置分组（来自 `settings/describe`，每个命名空间一组） */
  settings: SettingGroup[];
  /**
   * 每个设置命名空间的**写状态**（`revision` 是并发令牌）。
   *
   * 为什么要暴露给界面：它是「界面上的值到底对应 Host 的哪一版」的唯一依据。
   * 写操作后 revision 必然 +1；若界面显示的 revision 没变，
   * 就说明**界面拿的是旧视图**——这类不一致不看 revision 无法察觉
   * （值恰好相同的时候尤其如此）。
   */
  settingsStates: SettingsNamespaceState[];
  /** 斜杠命令目录（**全部来自 Host**；未连接或未拉到时为空数组） */
  commands: CommandCandidate[];
  /** `@` 引用候选（来自 Host 的两个候选端点；只对应当前查询串） */
  references: ReferenceCandidate[];
  /** 当前会话工作区的根层文件节点（子层挂在 `children` 上，按需加载） */
  fileNodes: FileNode[];
  /** 根层是否被上游条目上限截断 */
  fileTruncated: boolean;
  /** 当前预览的文件（未打开时为 undefined） */
  filePreview: FilePreview | undefined;
}

/**
 * 订阅者：**每窗口一个**（窗口只是视图）。
 *
 * 为什么是函数类型而不是 `{ onHubSnapshot(s): void }` 这样的单方法接口：
 * ArkTS 的 `arkts-no-untyped-obj-literals` 会拒绝在页面里写
 * `const l: HubListener = { onHubSnapshot: … }`（即使标注完全正确，
 * 编译器仍认为目标不是「已声明的类或接口」）。
 * 函数类型没有这个问题，而且对只有一个方法的订阅者来说更直接。
 */
export type HubSubscriber = (snapshot: HubSnapshot) => void;

/** trace 上限，避免长时间运行吃内存 */
const TRACE_LIMIT: number = 300;
/** 会话列表刷新节流（上游事件可能成串到达） */
const SESSION_REFRESH_THROTTLE_MS: number = 800;
/**
 * 设置刷新节流。
 *
 * 比列表刷新长：实测 `settings/document-updated` 在**每次**提交后都会发，
 * 包括本端自己写的那次。太短会让「本端写 → 事件 → 重拉」与写操作本身的
 * 重拉叠在一起，白白多打一次 RPC。
 */
const SETTINGS_REFRESH_THROTTLE_MS: number = 1200;

export class SessionHub {
  private static instance: SessionHub | undefined;

  /** 全局唯一实例（模块级单例 = 进程级单例，见文件头「实现依据」） */
  static shared(): SessionHub {
    if (SessionHub.instance === undefined) {
      SessionHub.instance = new SessionHub();
    }
    return SessionHub.instance;
  }

  private conn: Connection;
  private listeners: HubSubscriber[] = [];

  // ── 状态 ──
  private phase: HubPhase = HubPhase.IDLE;
  private hostName: string = '';
  private authority: string = '';
  private sessions: SessionListItem[] = [];
  private pendingList: PendingItem[] = [];
  private trajectoryList: TrajectoryItem[] = [];
  private selectedSessionId: string = '';
  private running: boolean = false;
  private eventsReady: boolean = false;
  private controlReady: boolean = false;
  /**
   * **一元能力是否可用**——与「事件流是否存活」解耦。
   *
   * 存在理由（真机验证发现的设计缺陷）：原先 `createSession` / `sendPrompt` 用
   * `phase === LIVE` 作为前置条件，而 `phase` 会在 `$events` 流终止时降级为 `DEGRADED`。
   * 于是「事件流死了」连带把**仍然可用**的一元调用也一起禁掉了——
   * 真机上表现为「连上了、列表能拉（`list ok 4 条`）、但点新建会话毫无反应」。
   *
   * 事实是：一元 RPC 走 HTTP，`$events` 走 WebSocket，**两者是独立的载体**，
   * 一条断了不代表另一条不能用。因此这里用一个独立的标志表示
   * 「认证与载体已就绪，一元调用可以尝试」，只在 `disconnect()` 时清除。
   * 至于调用到底成不成，交给调用本身去回答——**预判可用性比尝试更不可靠**。
   */
  private unaryReady: boolean = false;
  private lastError: string = '';
  private traceLines: string[] = [];
  /**
   * 协议旁路日志开关。
   *
   * **默认开启**（有 300 行上限，不构成内存风险）。理由：连接问题是移动端最难复现的一类，
   * 而「连上了但列表是空的」「连上几秒后掉线」这些症状**无法从界面区分原因**——
   * 必须能看到「list ok 4 条」「list fail gateway/...」「events end ...」这类原始轨迹。
   * 首次真机验证就吃了这个亏：错误只存进状态没渲染，导致「列表为空」被误读成
   * 「Host 上没有会话」。D3 §7.8 的旁路日志本就要求可查，这里只是把默认值改成开。
   */
  private traceEnabled: boolean = true;
  private unknownTypes: string[] = [];
  private outboxList: OutboxEntry[] = [];
  private models: ModelOption[] = [];
  private defaultSelection: ModelSelection | undefined = undefined;
  private plugins: PluginItem[] = [];
  private credentials: CredentialItem[] = [];
  /**
   * Host 设置分组（来自 `settings/describe`，已按命名空间分组）。
   *
   * 与 `credentials` 共享同一次 `settings/describe` 调用：一次 RPC 同时喂两个页面，
   * 而不是为了「干净」再拉一次。
   */
  private settingsGroups: SettingGroup[] = [];
  /**
   * 每个 Host 设置命名空间的写状态（**并发令牌 `revision` 的唯一副本**）。
   *
   * 为什么不能放进 `SettingItem`：revision 属于命名空间而不属于某个字段。
   * 存多份副本必然不同步——改完 A 字段后改 B 字段会带着过期 revision，恒被 Host 拒绝。
   */
  private namespaceStates: SettingsNamespaceState[] = [];
  /** `settings/describe` 的顶层 `writable`（Host 是否整体接受写） */
  private describeWritable: boolean = false;
  /** 从 `settings/describe` 取到的凭据引用（`credentials/describe` 的入参） */
  private credentialRefs: string[] = [];
  /** 斜杠命令目录（来自 `commands/list`，按当前会话的 agentId） */
  private commands: CommandCandidate[] = [];
  /** 命令目录是为哪个会话拉的（切会话后必须重拉，否则命令集是别人的） */
  private commandsFor: string = '';
  /** `@` 引用候选（来自 `fileReferences/list` + `sessionReferenceResolver/candidates`） */
  private references: ReferenceCandidate[] = [];
  /** 引用候选对应的查询串（回包只对得上这个查询，用于丢弃过期回包） */
  private referencesFor: string = '';
  /** 当前工作区文件树的**根层**节点（子层挂在各自的 `children` 上） */
  private fileNodes: FileNode[] = [];
  /** 根层是否被上游截断 */
  private fileTruncated: boolean = false;
  /** 文件树对应的会话（切会话后必须重列，否则看到的是别的会话的工作区） */
  private fileTreeFor: string = '';
  /** 当前预览的文件（未打开时为 undefined） */
  private filePreview: FilePreview | undefined = undefined;

  /** waterfall 待答项：eventId → 呈现项 id（应答时必须原样带回 eventId） */
  private waterfallEventIds: Map<string, string> = new Map();
  /**
   * 逻辑流的取消闭包（`Connection.openStream` 的返回值）。
   *
   * 用闭包而不是记 streamId：流的生命周期由连接层拥有，上层不该知道 streamId 的形态，
   * 也不该能凭一个陈旧 id 去取消一条已经属于别人的流。闭包天然「只能取消自己开的那条」。
   */
  private followCancel: (() => void) | undefined;
  private controlCancel: (() => void) | undefined;
  private lastRefreshAt: number = 0;
  private refreshTimer: number = -1;
  /** 设置刷新自己的节流状态（与列表刷新分开，理由见 `scheduleSettingsRefresh`） */
  private lastSettingsRefreshAt: number = 0;
  private settingsRefreshTimer: number = -1;

  private constructor() {
    this.conn = new Connection({ surface: SURFACE });
    // 【订阅必须只做一次，放在构造里】此前它写在 `connect()` 开头，
    // 而 `connect()` 会被**每次自动重连与手动重连**调用，于是每重连一次就多一个
    // 监听者：同一份降级事件被处理 N 次（N = 重连次数）。这类泄漏不会报错，
    // 只会让日志与状态更新随运行时长越来越重，属于最难在测试里发现的一类。
    this.conn.onStateChange((state: ConnectionState, detail: string) => {
      this.handleConnectionState(state, detail);
    });
  }

  // ───────────────────────── 生命周期 ─────────────────────────

  /** 配置目标 Host。返回规范化后的配置摘要（供 UI 显示 authority）。 */
  configure(address: string, name?: string): boolean {
    const cfg = this.conn.configure(address, name);
    if (cfg === undefined) {
      this.lastError = '地址无法解析：请检查形如 http://主机:端口 的写法';
      this.notify();
      return false;
    }
    this.hostName = cfg.name;
    this.authority = cfg.authority;
    this.lastError = '';
    this.notify();
    return true;
  }

  /**
   * 建立连接并按顺序打开各条流。
   *
   * 顺序有意义：先认证（拿 cookie）→ 再起 `$events`（证明网关事件源可用）
   * → 再开控制流 → 最后拉一次会话列表。
   * 任一步失败都进入 DEGRADED 而不是抛错：移动端网络随时可能不可用，
   * 降级可读比崩溃重要（D3 §4「每处失败都有建议」）。
   */
  async connect(): Promise<boolean> {
    if (this.phase === HubPhase.LIVE || this.phase === HubPhase.CONNECTING) {
      return this.phase === HubPhase.LIVE;
    }
    // 【连接状态订阅已在构造函数里做过一次】这里**不再重复订阅**：
    // 重复订阅会让同一次降级被处理多次，且随重连次数累积。
    this.phase = HubPhase.CONNECTING;
    this.lastError = '';
    this.notify();

    const auth = await this.conn.authenticate();
    if (!auth.ok) {
      this.phase = HubPhase.DEGRADED;
      this.lastError = authAdvice(auth.status, auth.reason === undefined ? '未提供原因' : auth.reason);
      this.notify();
      return false;
    }

    const sink: EventSink = {
      onReady: (facts: HostFacts) => {
        this.eventsReady = true;
        this.record(`events ready clientId=${facts.clientId.substring(0, 8)} home=${facts.home}`);
        this.notify();
      },
      onEvent: (event: Object) => {
        this.handleForwardedEvent(event);
      },
      onEnd: (error?: string) => {
        this.eventsReady = false;
        if (error !== undefined && error.length > 0) {
          this.lastError = `事件流终止：${error}`;
          this.record(`events end ${error}`);
        }
        this.phase = this.phase === HubPhase.LIVE ? HubPhase.DEGRADED : this.phase;
        this.notify();
      }
    };

    const started = await this.conn.start(sink);
    if (!started) {
      this.phase = HubPhase.DEGRADED;
      this.lastError = this.conn.getLastError() ?? '连接未建立：请检查 Host 是否在运行、令牌是否有效';
      this.notify();
      return false;
    }

    this.openControlStream();
    this.phase = HubPhase.LIVE;
    // 认证与载体已就绪：一元能力从此可用，且**不随事件流的生死变化**
    this.unaryReady = true;
    this.notify();
    await this.refreshSessions();
    // 静态事实（模型目录 / 插件清单）随后拉一次：无参只读，失败不影响连接
    await this.loadStaticFacts();
    this.flushOutbox();
    return true;
  }

  /**
   * 把底层的连接状态映射到中枢阶段。
   *
   * 【为什么映射而不是照抄】中枢的阶段是**呈现契约**（IDLE/CONNECTING/LIVE/DEGRADED），
   * 底层的状态是**载体事实**（idle/connecting/connected/disconnected）。
   * 两者不是一回事：底层 `CONNECTING` 在中枢看来是「降级（可读但实时性损失）」
   * 而不是「正在首次连接」——因为此时界面上的数据仍在、只是可能不新。
   * 直接把枚举抄过来会让界面把「重连中」显示成「首次连接中」，误导用户以为
   * 自己从没连上过。
   */
  private handleConnectionState(state: ConnectionState, detail: string): void {
    if (state === ConnectionState.CONNECTED) {
      // 载体恢复：事件流是否也已恢复由 EventStream 自己上报，这里不越权
      return;
    }
    if (state === ConnectionState.DISCONNECTED) {
      this.phase = HubPhase.DEGRADED;
      if (this.lastError.length === 0) {
        this.lastError = detail;
      }
      this.record(`connection disconnected: ${detail}`);
      this.notify();
      return;
    }
    if (state === ConnectionState.CONNECTING && this.phase === HubPhase.LIVE) {
      // 从 LIVE 退回 CONNECTING：载体失效、正在重连 —— 中枢据此显示「降级」
      this.phase = HubPhase.DEGRADED;
      this.eventsReady = false;
      this.record(`connection degraded: ${detail}`);
      this.notify();
    }
  }

  /**
   * 手动重连（D3 §4「已断连」横幅的必需动作）。
   *
   * 【为什么自动重连之外还必须有它】自动重试的档位表**有终点**：
   * 走到「重试已耗尽」就是终态，此后不再有任何自动尝试。
   * 而问题往往只是 Host 刚重启、网络刚恢复——此时用户唯一的动作竟只能是
   * **重启应用**，这显然不合规范，也不合直觉。
   *
   * 【为什么先 `disconnect()` 而不是直接 `connect()`】`connect()` 在
   * `CONNECTING` 时会早退（避免并发连接），而「重试耗尽」后底层可能还留着
   * 半死的 socket 与探活计时器。先显式停干净再重来，重连路径只有一条，
   * 不会出现「旧的探活计时器把新连接判死」这种交叉。
   */
  async reconnect(): Promise<boolean> {
    this.record('手动重连');
    await this.disconnect();
    return await this.connect();
  }

  /** 断开并释放所有流（仅一个窗口会调用；其他窗口只订阅快照） */
  async disconnect(): Promise<void> {    this.cancelFollow();
    this.cancelControl();
    await this.conn.stop();
    this.phase = HubPhase.IDLE;
    this.eventsReady = false;
    this.controlReady = false;
    this.unaryReady = false;
    this.record('connection stopped');
    this.notify();
  }

  private cancelFollow(): void {
    const cancel: (() => void) | undefined = this.followCancel;
    this.followCancel = undefined;
    if (cancel !== undefined) {
      cancel();
    }
  }

  private cancelControl(): void {
    const cancel: (() => void) | undefined = this.controlCancel;
    this.controlCancel = undefined;
    if (cancel !== undefined) {
      cancel();
    }
  }

  // ───────────────────────── 订阅 ─────────────────────────

  subscribe(listener: HubSubscriber): void {
    this.listeners.push(listener);
    listener(this.snapshot());
  }

  unsubscribe(listener: HubSubscriber): void {
    const next: HubSubscriber[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  snapshot(): HubSnapshot {
    return {
      phase: this.phase,
      hostName: this.hostName,
      authority: this.authority,
      sessions: this.sessions,
      pending: this.pendingList,
      trajectory: this.trajectoryList,
      selectedSessionId: this.selectedSessionId,
      selectedTitle: this.titleOf(this.selectedSessionId),
      running: this.running,
      eventsReady: this.eventsReady,
      controlReady: this.controlReady,
      connected: this.unaryReady,
      activeStreams: this.activeStreamCount(),
      outbox: this.outboxList.length,
      lastError: this.lastError,
      trace: this.traceLines,
      unknownEventTypes: this.unknownTypes,
      models: this.models,
      defaultSelection: this.defaultSelection,
      plugins: this.plugins,
      credentials: this.credentials,
      settings: this.settingsGroups,
      settingsStates: this.namespaceStates,
      commands: this.commands,
      references: this.references,
      fileNodes: this.fileNodes,
      fileTruncated: this.fileTruncated,
      filePreview: this.filePreview
    };
  }

  private notify(): void {
    const snap: HubSnapshot = this.snapshot();
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i](snap);
    }
  }

  /** 活动逻辑流数：控制流 + follow（`$events` 由连接层持有，单独看 eventsReady） */
  private activeStreamCount(): number {
    let n: number = 0;
    if (this.eventsReady) {
      n++;
    }
    if (this.controlCancel !== undefined) {
      n++;
    }
    if (this.followCancel !== undefined) {
      n++;
    }
    return n;
  }

  setTraceEnabled(on: boolean): void {
    this.traceEnabled = on;
    this.notify();
  }

  // ───────────────────────── 上游事件处理 ─────────────────────────

  /**
   * 处理一条 `$events` 转发事件。
   *
   * 帧判别（`dshcompat.RemoteEventFrameType`）：`ready` / `emit` / `waterfall` / `cancel`。
   * `emit` 是单向通知，`waterfall` 需要应答（审批与提问走这条）。
   */
  private handleForwardedEvent(raw: Object): void {
    const type: string = getString(raw, 'type') ?? '';
    if (type === RemoteEventFrameType.READY) {
      this.eventsReady = true;
      this.notify();
      return;
    }
    if (type === RemoteEventFrameType.WATERFALL) {
      this.handleWaterfall(raw);
      return;
    }
    if (type === RemoteEventFrameType.CANCEL) {
      // 另一端已处理：撤回卡片与通知（D3 §6「通知去重」、POC-8 步骤 4）
      const eventId: string = getString(raw, 'eventId') ?? '';
      this.resolvePendingById(eventId, '已由其他端处理');
      return;
    }
    if (type === RemoteEventFrameType.EMIT) {
      const name: string = getString(raw, 'event') ?? '';
      this.record(`emit ${name}`);
      // 通知类事件只需触发一次「重新拉取」；具体投影由各页各自负责，
      // 中枢只维护会话列表这一项（它被多个页面共享）。
      if (isSessionListEvent(name)) {
        this.scheduleSessionRefresh();
      }
      // 设置文档 / 凭据引用被别的客户端（或 Host 自身）改了：拉一次最新状态。
      //
      // 【为什么必须处理这两条事件】`settings/describe` 是**读一次就冻结**的快照。
      // 不接它们时，另一个窗口或另一台设备改了设置，本端界面会一直显示旧值，
      // 而且**正在编辑的 revision 已经过期**——用户改一次撞一次
      // `settings/conflict`，却看不出为什么。
      // `credentials/reference-updated` 同理：别的客户端新增/删除凭据后，
      // 本端的 refs 列表（它只来自 `settings/describe`）会多一项或少一项。
      //
      // 【为什么要节流】实测 `settings/document-updated` 在每次提交后都会发
      // （**包括本端自己写的那次**）。不节流会与写操作自身的重拉叠在一起，
      // 白白多打一次 RPC。节流让一串连改合并成一次读取。
      if (name === EVENT_SETTINGS_DOCUMENT_UPDATED || name === EVENT_CREDENTIALS_REFERENCE_UPDATED) {
        this.scheduleSettingsRefresh();
      }
      // 命令目录是插件装的：插件启用/禁用后命令集会变。上游为此发了
      // `commands/change`。不接它，用户会一直看到一批已经失效的命令。
      if (name === EVENT_COMMANDS_CHANGE) {
        this.refreshCommands();
      }
      return;
    }
    this.noteUnknown(`events:${type}`);
  }

  /** 处理 waterfall（审批/提问）——客户端价值的核心路径 */
  private handleWaterfall(raw: Object): void {
    const event: string = getString(raw, 'event') ?? '';
    const eventId: string = getString(raw, 'eventId') ?? '';
    const agentId: string = getString(raw, 'agentId') ?? '';
    const request: Object | undefined = getRecord(raw, 'request');
    if (eventId.length === 0 || request === undefined) {
      this.noteUnknown(`waterfall:${event}:malformed`);
      return;
    }

    if (event === WATERFALL_APPROVAL) {
      this.addApprovalPending(eventId, agentId, request);
      return;
    }
    if (event === WATERFALL_QUESTION) {
      this.addQuestionPending(eventId, agentId, request);
      return;
    }
    // 白名单里将来可能新增 waterfall：不认识就**交还给 Host 链条**，
    // 绝不假装处理（假装会让 Host 以为有人答了，实际没人答）。
    this.declineToHandle(eventId);
    this.noteUnknown(`waterfall:${event}`);
  }

  private addApprovalPending(eventId: string, agentId: string, request: Object): void {
    const toolName: string = getString(request, 'toolName') ?? '未知操作';
    const reason: string = getString(request, 'reason') ?? '';
    const callId: string = getString(request, 'callId') ?? '';

    const item: PendingItem = {
      id: eventId,
      kind: PendingKind.APPROVAL,
      // agentId 在根会话上等于会话 id（实测形态待真机审批场景确认，见 D4 POC-8）
      sessionId: agentId,
      sessionTitle: this.titleOf(agentId),
      title: toolName,
      detail: reason,
      raw: JSON.stringify(request),
      risk: riskOfTool(toolName),
      choices: approvalChoices(),
      multiSelect: false,
      allowFreeText: false,
      at: Date.now()
    };
    this.upsertPending(item);
    this.waterfallEventIds.set(eventId, eventId);
    this.record(`waterfall approval eventId=${eventId.substring(0, 8)} tool=${toolName} callId=${callId.length > 0 ? callId.substring(0, 8) : '-'}`);
  }

  private addQuestionPending(eventId: string, agentId: string, request: Object): void {
    const questions: Object[] | undefined = getArray(request, 'questions');
    if (questions === undefined || questions.length === 0) {
      // 没有问题的请求无法呈现：交还链条比造一张空卡片更正确
      this.declineToHandle(eventId);
      this.noteUnknown(`waterfall:${WATERFALL_QUESTION}:no-questions`);
      return;
    }
    const first: Object = questions[0];
    const qid: string = getString(first, 'id') ?? 'q0';
    const text: string = getString(first, 'question') ?? '';
    const detail: string = getString(first, 'detail') ?? '';
    const header: string = getString(first, 'header') ?? '';
    const multi: boolean = getBoolean(first, 'multiSelect') === true;

    const choices: PendingChoice[] = [];
    const options: Object[] | undefined = getArray(first, 'options');
    if (options !== undefined) {
      for (let i = 0; i < options.length; i++) {
        const opt: Object = options[i];
        choices.push({
          id: getString(opt, 'label') ?? `option-${i}`,
          label: getString(opt, 'label') ?? `选项 ${i + 1}`,
          detail: getString(opt, 'description') ?? ''
        });
      }
    }

    const item: PendingItem = {
      // 同一 waterfall 可能带多个问题：用 eventId + 问题 id 组合，应答时按 question id 回填
      id: `${eventId}#${qid}`,
      kind: PendingKind.QUESTION,
      sessionId: agentId,
      sessionTitle: this.titleOf(agentId),
      title: text.length > 0 ? text : (header.length > 0 ? header : '需要你回答'),
      detail: detail,
      raw: JSON.stringify(first),
      risk: RiskLevel.NORMAL,
      choices: choices,
      multiSelect: multi,
      allowFreeText: true,
      at: Date.now()
    };
    this.upsertPending(item);
    this.waterfallEventIds.set(eventId, item.id);
    this.record(`waterfall question eventId=${eventId.substring(0, 8)} qid=${qid} options=${choices.length} multi=${multi}`);
  }

  // ───────────────────────── 应答（核心价值路径） ─────────────────────────

  /**
   * 答复审批。
   *
   * 词汇纪律（`dshcompat.APPROVAL_OUTCOMES`）：上游只有 `allowed-once` / `rejected` /
   * `cancelled` / `unavailable`，**没有**「始终允许」。
   * 因此 `allowAlways` 在当前实现里只影响**本地**不再重复打扰的策略，
   * 发到 Host 的仍然是 `allowed-once`——绝不伪造一个上游不认识的词。
   */
  async decideApproval(pendingId: string, allow: boolean, allowAlways: boolean): Promise<boolean> {
    const outcome: string = allow ? APPROVAL_ALLOWED_ONCE : APPROVAL_REJECTED;
    if (allowAlways) {
      this.record('注意：上游无持久授权词汇，本次仍按 allowed-once 上报');
    }
    const ok: boolean = await this.answerWaterfall(pendingId, outcome);
    if (ok) {
      this.resolvePending(pendingId, allow ? '已允许' : '已拒绝');
    }
    return ok;
  }

  /** 答复提问（结构化答案：选中项 + 可选自由文本） */
  async answerQuestion(pendingId: string, selected: string[], custom: string): Promise<boolean> {
    const hash: number = pendingId.indexOf('#');
    const eventId: string = hash > 0 ? pendingId.substring(0, hash) : pendingId;
    const qid: string = hash > 0 ? pendingId.substring(hash + 1) : 'q0';
    const answers: Object[] = [];
    const one: Record<string, Object> = {};
    one['id'] = qid;
    one['selected'] = selected;
    if (custom.length > 0) {
      one['custom'] = custom;
    }
    answers.push(one as Object);
    const value: Record<string, Object> = {};
    value['answers'] = answers;
    const ok: boolean = await this.answerWithResultValue(eventId, value as Object);
    if (ok) {
      this.resolvePending(pendingId, '已回答');
    }
    return ok;
  }

  /**
   * 明确「我不处理这一条」，把它交还 Host 的应答者链条。
   *
   * 这是 waterfall 语义允许的**正确**回应之一，也是我们处理未知 waterfall 事件的唯一
   * 正当做法：`{kind:'next'}` 让 Host 继续问下一个应答者。
   * 相比之下「回一个空结果」会让 Host 认为已有人答了，从而丢掉这次审批。
   */
  async declineToHandle(eventId: string): Promise<boolean> {
    const outcome: Record<string, Object> = {};
    outcome['kind'] = 'next';
    return await this.sendEventResult(eventId, outcome as Object);
  }

  private async answerWaterfall(pendingId: string, outcomeValue: string): Promise<boolean> {
    const value: Record<string, Object> = {};
    value['value'] = outcomeValue;
    return await this.answerWithResultValue(pendingId, value as Object);
  }

  /**
   * 发送 `$events/result`。
   *
   * 参数是**扁平**的 `{clientId, eventId, outcome}`（实测：上游
   * `parseRemoteEventResult(payload.args)` 直接读 args，没有 `request` 包装层）。
   * `clientId` 来自 `$events` 的 ready 帧，必须与当前那次事件流 generation 一致——
   * 重连后 clientId 会变，用旧值会被 Host 拒绝（`identifies no active event stream`）。
   * 因此这里每次都向连接层现取。
   */
  private async answerWithResultValue(eventId: string, value: Object): Promise<boolean> {
    if (eventId.length === 0) {
      return false;
    }
    const outcome: Record<string, Object> = {};
    outcome['kind'] = 'result';
    outcome['value'] = value;
    return await this.sendEventResult(eventId, outcome as Object);
  }

  private async sendEventResult(eventId: string, outcome: Object): Promise<boolean> {
    const clientId: string | undefined = this.conn.getHostFactsClientId();
    if (clientId === undefined || clientId.length === 0) {
      this.lastError = '事件流尚未就绪，无法应答；请等待连接恢复后重试';
      this.notify();
      return false;
    }
    const args: Record<string, Object> = {};
    args['clientId'] = clientId;
    args['eventId'] = eventId;
    args['outcome'] = outcome;

    const result: RpcResult = await this.conn.call(EVENTS_RESULT_ENDPOINT, args as Object);
    if (result.ok) {
      this.record(`result ok eventId=${eventId.substring(0, 8)}`);
      return true;
    }
    const failure = result.error;
    const code: string = failure === undefined ? 'unknown' : failure.code;
    const message: string = failure === undefined ? '应答未被 Host 接受' : failure.message;
    this.lastError = `应答失败：${code} ${message}`;
    this.record(`result fail ${code}`);
    this.notify();
    return false;
  }

  // ───────────────────────── 会话与轨迹 ─────────────────────────

  /**
   * 拉取「静态事实」：模型目录 + 插件清单。
   *
   * 这两个端点是**无参只读**的（参数形态 `NONE`，实测可用，见 D2 §8.7.2），
   * 因此可以在连接建立后无条件拉一次，作为模型页/插件页的真实数据来源。
   *
   * 失败不抛也不阻断连接：能力缺失（老 Host 没有这些端点）应当表现为
   * 「对应页面为空 + 可解释」，而不是让整个连接失败。
   */
  async loadStaticFacts(): Promise<void> {
    const empty: Record<string, Object> = {};

    const catalogArgs: Object | undefined = argsFor(MODEL_CATALOG_ENDPOINT, empty as Object);
    if (catalogArgs !== undefined) {
      const result: RpcResult = await this.conn.call(MODEL_CATALOG_ENDPOINT, catalogArgs);
      if (result.ok) {
        this.models = projectModelCatalog(result.value);
        this.defaultSelection = projectDefaultSelection(result.value);
        this.record(`modelCatalog ok ${this.models.length} 个模型`);
      } else {
        const f = result.error;
        this.record(`modelCatalog fail ${f === undefined ? '?' : f.code}`);
      }
    }

    const pluginArgs: Object | undefined = argsFor(PLUGIN_INVENTORY_ENDPOINT, empty as Object);
    if (pluginArgs !== undefined) {
      const result: RpcResult = await this.conn.call(PLUGIN_INVENTORY_ENDPOINT, pluginArgs);
      if (result.ok) {
        this.plugins = projectPluginInventory(result.value);
        this.record(`pluginInventory ok ${this.plugins.length} 个条目`);
      } else {
        const f = result.error;
        this.record(`pluginInventory fail ${f === undefined ? '?' : f.code}`);
      }
    }

    // 凭据：两跳。第一跳 settings/describe 拿 refs（credentials/describe 没有「列出全部」模式），
    // 第二跳 credentials/describe 拿状态。**任何一跳失败都只是让凭据页为空**，
    // 绝不因此把整个连接判为失败。
    const settingsArgs: Object | undefined = argsFor(SETTINGS_DESCRIBE_ENDPOINT, empty as Object);
    if (settingsArgs !== undefined) {
      const described: RpcResult = await this.conn.call(SETTINGS_DESCRIBE_ENDPOINT, settingsArgs);
      if (described.ok) {
        // 同一次回复同时喂设置页与凭据页：两者都来自 settings/describe，
        // 再拉一次只为了「一个函数做一件事」是浪费一次 RPC。
        this.applySettingsDescribe(described.value);
        const refs: string[] = this.credentialRefs;
        let itemCount: number = 0;
        for (let i = 0; i < this.settingsGroups.length; i++) {
          itemCount += this.settingsGroups[i].items.length;
        }
        this.record(`settings/describe ok, ${refs.length} 个凭据引用, ${itemCount} 个设置项`);
        if (refs.length > 0) {
          const credArgs: Record<string, Object> = {};
          credArgs['refs'] = refs;
          const creds: RpcResult = await this.conn.call(CREDENTIALS_DESCRIBE_ENDPOINT, credArgs as Object);
          if (creds.ok) {
            this.credentials = projectCredentials(creds.value, refs);
            this.record(`credentials ok ${this.credentials.length} 条`);
          } else {
            const f = creds.error;
            this.record(`credentials fail ${f === undefined ? '?' : f.code}`);
          }
        } else {
          // 该 Host 没有任何声明了 secret 的命名空间：这是**正常状态**，不是失败
          this.credentials = [];
        }
      } else {
        const f = described.error;
        this.record(`settings/describe fail ${f === undefined ? '?' : f.code}`);
      }
    }

    this.notify();
  }

  /**
   * 节流地重新读取设置。
   *
   * 与 `scheduleSessionRefresh` 同样的形状，但用**独立的计时器与时间戳**：
   * 两类刷新由不同事件驱动、频率也不同（设置改动远少于会话活动）。
   * 共用一个时间戳会让「刚刷过会话列表」把设置刷新一起压掉——
   * 表现为另一个客户端改了设置而本端半天不动。
   */
  private scheduleSettingsRefresh(): void {
    const now: number = Date.now();
    if (now - this.lastSettingsRefreshAt < SETTINGS_REFRESH_THROTTLE_MS) {
      if (this.settingsRefreshTimer !== -1) {
        return;
      }
      const wait: number = SETTINGS_REFRESH_THROTTLE_MS - (now - this.lastSettingsRefreshAt);
      this.settingsRefreshTimer = setTimeout(() => {
        this.settingsRefreshTimer = -1;
        this.lastSettingsRefreshAt = Date.now();
        this.refreshSettings();
      }, wait);
      return;
    }
    this.lastSettingsRefreshAt = now;
    this.refreshSettings();
  }

  /**
   * 写入一个 Host 设置项（`settings/mutate`，按路径 set 单个字段）。
   *
   * 【为什么必须带 `expectedRevision`】上游把「并发写」做成一种**独立结果**
   * （`settings/conflict{expected, actual}`），而不是静默后写覆盖先写。
   * 省略 revision 等于放弃这个保护：两个客户端同时改同一命名空间时，
   * 后提交的人会**无声地抹掉**前一个人的改动。
   *
   * 冲突的处置是**重新读取后再改**，不是重试同一请求——重试必然再次失败，
   * 用户看到的是「点了没反应」。因此冲突分支会主动刷新设置并给出这句建议。
   *
   * @param key - 设置项 key（`ns.field`）
   * @param value - 新值（布尔 / 字符串 / 数字，按 schema 类型由调用方给对）
   * @returns 面向界面的结果（含可执行建议）
   */
  async writeSetting(key: string, value: Object): Promise<SettingsWriteResult> {
    const parts: SettingsKeyParts | undefined = splitSettingKey(key);
    if (parts === undefined) {
      return {
        outcome: SettingsWriteOutcome.FAILED, actualRevision: -1,
        message: `设置项标识「${key}」无法解析出命名空间，已拒绝写入（这属于本客户端的缺陷，请提交诊断报告）。`
      };
    }
    const state: SettingsNamespaceState | undefined = this.namespaceState(parts.ns);
    if (state === undefined) {
      return {
        outcome: SettingsWriteOutcome.FAILED, actualRevision: -1,
        message: `Host 上没有名为「${parts.ns}」的设置命名空间，已拒绝写入。请重新连接以刷新设置清单。`
      };
    }
    if (!state.writable) {
      return {
        outcome: SettingsWriteOutcome.REJECTED, actualRevision: state.revision,
        message: 'Host 不接受对这项设置的写入（可能是只读来源，例如环境变量或文件基线）。'
      };
    }
    if (!this.unaryReady) {
      return {
        outcome: SettingsWriteOutcome.FAILED, actualRevision: state.revision,
        message: '尚未连接 Host，改动没有生效。请先完成连接后重试。'
      };
    }

    const args: Object = settingsMutateArgs(parts.ns, parts.fieldPath, value, state.revision);
    const result: RpcResult = await this.conn.call(SETTINGS_MUTATE_ENDPOINT, args);
    if (result.ok) {
      // 【为什么写成功后要整页重拉，而不是用回复里的视图局部替换】
      //   局部替换只在「界面当前持有的视图确实来自 Host」时才安全。
      //   而写操作前后可能已经被其它刷新（定时列表刷新、事件触发的重载）改过
      //   `settingsGroups`，此时局部替换会把旧的分组原样保留下来——
      //   表现就是「Host 说写入成功、界面值却没变」，而且**不报错**。
      //   实测就踩到了：写了两次，第二次界面仍显示旧值。
      //   整页重拉的代价是一次 RPC；换来的是「界面一定等于 Host 的当前状态」这个不变量。
      await this.refreshSettings();
      this.record(`settings/mutate ok ${key}`);
      this.notify();
      return {
        outcome: SettingsWriteOutcome.OK, actualRevision: this.namespaceState(parts.ns) === undefined
          ? state.revision : (this.namespaceState(parts.ns) as SettingsNamespaceState).revision,
        message: `已写入 ${key}。`
      };
    }

    const failure: RemoteFailure | undefined = result.error;
    const code: string = failure === undefined ? 'unknown' : failure.code;
    if (code === SETTINGS_CONFLICT) {
      const actual: number = this.conflictActualRevision(failure);
      this.record(`settings/mutate conflict ${key} expected=${state.revision} actual=${actual}`);
      // 冲突后必须刷新：用户手上的界面已经过期，让他们在旧值上继续改只会连撞冲突
      await this.refreshSettings();
      return {
        outcome: SettingsWriteOutcome.CONFLICT, actualRevision: actual,
        message: '这项设置已被其他客户端改过，你的界面是旧的。已为你重新读取最新值，请确认后再改一次。'
      };
    }
    if (code === SETTINGS_REJECTED) {
      this.record(`settings/mutate rejected ${key}`);
      await this.refreshSettings();
      return {
        outcome: SettingsWriteOutcome.REJECTED, actualRevision: state.revision,
        message: 'Host 拒绝了这个值（可能不符合该设置的类型或取值范围）。已重新读取最新值，请检查后重试。'
      };
    }
    this.record(`settings/mutate fail ${key} ${code}`);
    return {
      outcome: SettingsWriteOutcome.FAILED, actualRevision: state.revision,
      message: `写入未生效：${friendlyFailure(code, failure === undefined ? '' : failure.message)}`
    };
  }

  /**
   * 删除一个 Host 设置项在**用户层**的取值（`settings/mutate` 的 `unset`）。
   *
   * 语义是「恢复默认」而不是「清空」：实测该键的用户层被移除后，
   * 值回落到 schema 默认（`.research/protocol/probe-deep-path.mjs`）。
   * 这一点必须在界面文案上说清——用户以为自己在清空、实际在恢复默认
   * （或反过来）都会造成困惑。
   */
  async unsetSetting(key: string): Promise<SettingsWriteResult> {
    const parts: SettingsKeyParts | undefined = splitSettingKey(key);
    if (parts === undefined) {
      return {
        outcome: SettingsWriteOutcome.FAILED, actualRevision: -1,
        message: `设置项标识「${key}」无法解析出命名空间，已拒绝操作。`
      };
    }
    const state: SettingsNamespaceState | undefined = this.namespaceState(parts.ns);
    if (state === undefined) {
      return {
        outcome: SettingsWriteOutcome.FAILED, actualRevision: -1,
        message: `Host 上没有名为「${parts.ns}」的设置命名空间。请重新连接以刷新设置清单。`
      };
    }
    if (!state.writable) {
      return {
        outcome: SettingsWriteOutcome.REJECTED, actualRevision: state.revision,
        message: 'Host 不接受对这项设置的写入（可能是只读来源）。'
      };
    }
    if (!this.unaryReady) {
      return {
        outcome: SettingsWriteOutcome.FAILED, actualRevision: state.revision,
        message: '尚未连接 Host，未做改动。请先完成连接后重试。'
      };
    }
    const args: Object = settingsUnsetArgs(parts.ns, parts.fieldPath, state.revision);
    const result: RpcResult = await this.conn.call(SETTINGS_MUTATE_ENDPOINT, args);
    if (result.ok) {
      await this.refreshSettings();
      this.record(`settings/unset ok ${key}`);
      this.notify();
      return { outcome: SettingsWriteOutcome.OK, actualRevision: state.revision, message: `已恢复 ${key} 的默认值。` };
    }
    const failure: RemoteFailure | undefined = result.error;
    const code: string = failure === undefined ? 'unknown' : failure.code;
    if (code === SETTINGS_CONFLICT) {
      const actual: number = this.conflictActualRevision(failure);
      this.record(`settings/unset conflict ${key} expected=${state.revision} actual=${actual}`);
      await this.refreshSettings();
      return {
        outcome: SettingsWriteOutcome.CONFLICT, actualRevision: actual,
        message: '这项设置已被其他客户端改过，你的界面是旧的。已重新读取最新值，请确认后再操作。'
      };
    }
    if (code === SETTINGS_REJECTED) {
      this.record(`settings/unset rejected ${key}`);
      await this.refreshSettings();
      return {
        outcome: SettingsWriteOutcome.REJECTED, actualRevision: state.revision,
        message: 'Host 拒绝了这个操作（该键可能不允许删除，或是必填项）。已重新读取最新值。'
      };
    }
    this.record(`settings/unset fail ${key} ${code}`);
    return {
      outcome: SettingsWriteOutcome.FAILED, actualRevision: state.revision,
      message: `未生效：${friendlyFailure(code, failure === undefined ? '' : failure.message)}`
    };
  }

  /** 重新拉一次 `settings/describe`（只刷新设置页与凭据，不做其它副作用） */
  async refreshSettings(): Promise<void> {    const empty: Record<string, Object> = {};
    const args: Object | undefined = argsFor(SETTINGS_DESCRIBE_ENDPOINT, empty as Object);
    if (args === undefined) {
      return;
    }
    const described: RpcResult = await this.conn.call(SETTINGS_DESCRIBE_ENDPOINT, args);
    if (!described.ok) {
      return;
    }
    this.applySettingsDescribe(described.value);
    this.notify();
  }

  /**
   * 写入一份凭据（`credentials/set`）。
   *
   * 【本客户端**绝不保存**这份明文】它只在一次 `set` 调用里存在，
   * 之后立刻从内存里消失（D1 §11.5 S3/S4：端侧不保存也不显示明文值）。
   * 真正持有它的是 Host 的凭据存储。
   *
   * 【成功回复是 `{ok:true}`——没有 `value` 键】不能用「有没有 value」判成败：
   * 那会把每一次成功都判为畸形响应（D2b §4.1 / D2 §8.7.6 缺陷 2）。
   * 解析层已按键存在性处理，这里只看 `result.ok`。
   *
   * @param ref - 凭据引用（实测编码：`path.join('.')`，**不带命名空间前缀**）
   * @param value - 明文值；调用方用完即弃，不要存进任何状态
   */
  async setCredential(ref: string, value: string): Promise<CredentialWriteResult> {
    if (ref.length === 0 || value.length === 0) {
      return { ok: false, message: '凭据引用或值不能为空。' };
    }
    if (!this.unaryReady) {
      return { ok: false, message: '尚未连接 Host，值没有写入。请先完成连接后重试。' };
    }
    const args: Record<string, Object> = {};
    args['ref'] = ref;
    args['value'] = value;
    const result: RpcResult = await this.conn.call(CREDENTIALS_SET_ENDPOINT, args as Object);
    if (result.ok) {
      // 写完立刻回读状态：界面要显示的是**Host 的实际状态**，
      // 而不是「我们认为写成功了」。实测 `source` 会变成写入目标（如 `file`）。
      await this.refreshCredentials();
      this.record(`credentials/set ok ${ref} 快照已配置=${this.countConfiguredCredentials()}`);
      this.notify();
      return { ok: true, message: `已写入 ${ref}。明文没有留在本机。` };
    }
    const failure: RemoteFailure | undefined = result.error;
    const code: string = failure === undefined ? 'unknown' : failure.code;
    this.record(`credentials/set fail ${ref} ${code}`);
    if (code === CREDENTIAL_REJECTED) {
      // 上游只回传 `ref`，不回传任何值——这里也不能把它打印出来
      return {
        ok: false,
        message: `${ref} 被 Host 拒绝：可能是只读来源（例如环境变量）遮蔽了这个引用。`
          + '请在 Host 侧检查该引用的来源后重试。'
      };
    }
    return { ok: false, message: `写入未生效：${friendlyFailure(code, failure === undefined ? '' : failure.message)}` };
  }

  /**
   * 删除一份凭据（`credentials/unset`）。
   *
   * 【为什么需要显式确认】这是**破坏性**操作：Host 侧的值会被删除，
   * 依赖它的功能（例如联网搜索）会立刻失效。调用方必须来自一次明确的用户确认。
   */
  async unsetCredential(ref: string): Promise<CredentialWriteResult> {
    if (ref.length === 0) {
      return { ok: false, message: '凭据引用不能为空。' };
    }
    if (!this.unaryReady) {
      return { ok: false, message: '尚未连接 Host，未做改动。请先完成连接后重试。' };
    }
    const args: Record<string, Object> = {};
    args['ref'] = ref;
    const result: RpcResult = await this.conn.call(CREDENTIALS_UNSET_ENDPOINT, args as Object);
    if (result.ok) {
      await this.refreshCredentials();
      this.record(`credentials/unset ok ${ref} 快照已配置=${this.countConfiguredCredentials()}`);
      this.notify();
      return { ok: true, message: `已清除 ${ref}。` };
    }
    const failure: RemoteFailure | undefined = result.error;
    const code: string = failure === undefined ? 'unknown' : failure.code;
    this.record(`credentials/unset fail ${ref} ${code}`);
    if (code === CREDENTIAL_REJECTED) {
      return { ok: false, message: `${ref} 被 Host 拒绝删除：该引用由只读来源提供。` };
    }
    return { ok: false, message: `清除未生效：${friendlyFailure(code, failure === undefined ? '' : failure.message)}` };
  }

  /** 已配置的凭据数（诊断用；凭据写入后界面没变时靠它区分「Host 说没配置」与「我们没刷新」） */
  private countConfiguredCredentials(): number {
    let configured: number = 0;
    for (let i = 0; i < this.credentials.length; i++) {
      if (this.credentials[i].configured) {
        configured++;
      }
    }
    return configured;
  }

  /** 重新拉一次凭据状态（`settings/describe` 取 refs → `credentials/describe` 取状态） */
  async refreshCredentials(): Promise<void> {
    if (this.credentialRefs.length === 0) {
      this.credentials = [];
      return;
    }
    const credArgs: Record<string, Object> = {};
    credArgs['refs'] = this.credentialRefs;
    const creds: RpcResult = await this.conn.call(CREDENTIALS_DESCRIBE_ENDPOINT, credArgs as Object);
    if (creds.ok) {
      this.credentials = projectCredentials(creds.value, this.credentialRefs);
      // 记下**回读到的**状态：凭据写入成功但界面没变时，这行是唯一能区分
      // 「Host 说没配置」与「我们没刷新」的证据（实测靠它定位过）。
      let configured: number = 0;
      for (let i = 0; i < this.credentials.length; i++) {
        if (this.credentials[i].configured) {
          configured++;
        }
      }
      this.record(`credentials 回读 refs=${this.credentialRefs.length} 已配置=${configured}`);
    } else {
      const f = creds.error;
      this.record(`credentials 回读失败 ${f === undefined ? '?' : f.code}`);
    }
  }

  /** 在命名空间台账里找写状态 */
  private namespaceState(ns: string): SettingsNamespaceState | undefined {
    for (let i = 0; i < this.namespaceStates.length; i++) {
      if (this.namespaceStates[i].ns === ns) {
        return this.namespaceStates[i];
      }
    }
    return undefined;
  }


  /** 从冲突错误的 details 里取实际 revision（取不到返回 -1，不猜） */
  private conflictActualRevision(failure: RemoteFailure | undefined): number {
    if (failure === undefined) {
      return -1;
    }
    const details: Object | undefined = failure.details;
    if (details === undefined) {
      return -1;
    }
    return getNumber(details, 'actual') ?? -1;
  }

  /** 把一次 `settings/describe` 回复应用到设置页与凭据页 */
  private applySettingsDescribe(value: Object | undefined): void {
    const entries: SettingsGroupEntry[] = projectSettingsEntries(value);
    const groups: SettingGroup[] = [];
    const states: SettingsNamespaceState[] = [];
    for (let i = 0; i < entries.length; i++) {
      groups.push(entries[i].group);
      states.push(entries[i].state);
    }
    this.settingsGroups = groups;
    this.namespaceStates = states;
    this.describeWritable = value === undefined ? false : getBoolean(value, 'writable') === true;
    const refs: string[] = projectCredentialRefs(value);
    this.credentialRefs = refs;
  }

  /**
   * 新建会话。
   *
   * 上游 `session/create` 的 `request` 字段**全部可选**，传 `{}` 即
   * 「用默认工作区建一个新会话」——已实测（D2 §8.7.2）：返回 `{sessionId, agentPreset}`。
   * 不传 `cwd` 是刻意的：`cwd` 由 Host 的默认工作区决定，客户端不该猜一个路径塞过去。
   *
   * 建好后立刻拉一次列表并选中它：新会话在 Host 上 `blank: true`、`title: null`，
   * 界面上会显示为「新会话 + cwd 末段」，用户马上就能往里发消息。
   *
   * @returns 新会话 id；失败或未连接时返回 undefined（错误已写入 lastError 并广播）
   */
  async createSession(): Promise<string | undefined> {
    if (!this.unaryReady) {
      this.lastError = '尚未连接 Host，无法新建会话。请先在「添加 Host」里完成连接。';
      this.notify();
      return undefined;
    }
    // 空对象也要有声明类型：ArkTS 禁止无类型对象字面量
    const inner: Record<string, Object> = {};
    const body: Record<string, Object> = {};
    body['request'] = inner as Object;
    const args: Object | undefined = argsFor(SESSION_CREATE_ENDPOINT, body as Object);
    if (args === undefined) {
      this.lastError = '兼容面缺少会话创建端点的参数契约（上表未生成？）';
      this.notify();
      return undefined;
    }
    const result: RpcResult = await this.conn.call(SESSION_CREATE_ENDPOINT, args);
    if (!result.ok) {
      const failure = result.error;
      const code: string = failure === undefined ? 'unknown' : failure.code;
      this.lastError = `新建会话失败：${friendlyFailure(code, failure === undefined ? '' : failure.message)}`;
      this.record(`create fail ${code}`);
      this.notify();
      return undefined;
    }
    const value: Object | undefined = result.value;
    const sessionId: string | undefined = value === undefined ? undefined : getString(value, 'sessionId');
    this.record(`create ok ${sessionId === undefined ? '(无 sessionId)' : sessionId.substring(0, 12)}`);
    await this.refreshSessions();
    if (sessionId !== undefined && sessionId.length > 0) {
      await this.selectSession(sessionId);
    }
    return sessionId;
  }

  /**
   * 拉取会话列表
   */
  async refreshSessions(): Promise<void> {
    const body: Record<string, Object> = {};
    const args: Object | undefined = argsFor(SESSION_LIST_ENDPOINT, body as Object);
    if (args === undefined) {
      this.lastError = '兼容面缺少会话列表端点的参数契约（上表未生成？）';
      this.notify();
      return;
    }
    const result: RpcResult = await this.conn.call(SESSION_LIST_ENDPOINT, args);
    if (!result.ok) {
      const failure = result.error;
      const code: string = failure === undefined ? 'unknown' : failure.code;
      this.lastError = `会话列表获取失败：${friendlyFailure(code, failure === undefined ? '' : failure.message)}`;
      this.record(`list fail ${code}`);
      this.notify();
      return;
    }
    const page = projectSessionList(result.value);
    this.sessions = page.items;
    this.record(`list ok ${page.items.length} 条`);
    this.notify();
  }

  private scheduleSessionRefresh(): void {
    const now: number = Date.now();
    if (now - this.lastRefreshAt < SESSION_REFRESH_THROTTLE_MS) {
      if (this.refreshTimer !== -1) {
        return;
      }
      const wait: number = SESSION_REFRESH_THROTTLE_MS - (now - this.lastRefreshAt);
      this.refreshTimer = setTimeout(() => {
        this.refreshTimer = -1;
        this.lastRefreshAt = Date.now();
        this.refreshSessions();
      }, wait);
      return;
    }
    this.lastRefreshAt = now;
    this.refreshSessions();
  }

  /**
   * 选中会话并打开它的轨迹流。
   *
   * 「先取消旧 follow、再开新 follow」是硬约束：并发两条 follow 会让同一个会话的轨迹
   * 被写两遍，且抓包会看到多于一条 follow 流，直接违反 D1 §7.7.5b 的验收点。
   */
  async selectSession(sessionId: string): Promise<void> {
    if (this.selectedSessionId === sessionId) {
      return;
    }
    this.cancelFollow();
    this.selectedSessionId = sessionId;
    this.trajectoryList = [];
    this.running = false;
    this.notify();
    if (sessionId.length === 0) {
      return;
    }

    const address: Record<string, Object> = {};
    address['kind'] = 'session';
    address['sessionId'] = sessionId;
    const request: Record<string, Object> = {};
    request['address'] = address as Object;
    request['maxMessages'] = 60;
    // assistantStream:true 让 Host 额外推送「正在进行中的助手输出」，
    // 这样流式光标与逐字输出才有数据（否则只能等整条消息落盘）。
    request['assistantStream'] = true;
    const body: Record<string, Object> = {};
    body['request'] = request as Object;
    const args: Object | undefined = argsFor(SESSION_FOLLOW_ENDPOINT, body as Object);
    if (args === undefined) {
      this.lastError = '兼容面缺少轨迹流端点的参数契约';
      this.notify();
      return;
    }

    const sink: StreamSink = {
      onItem: (value: Object) => {
        this.handleFollowFrame(value);
      },
      onError: (code: string, message: string) => {
        this.followCancel = undefined;
        this.lastError = `轨迹流失败：${code} ${message}`;
        this.record(`follow error ${code}`);
        this.notify();
      },
      onEnd: () => {
        // 正常结束（上游会显式发 `end` 帧）：不是错误，不触发重连
        this.followCancel = undefined;
        this.record('follow end');
        this.notify();
      }
    };
    const cancel = this.conn.openStream(SESSION_FOLLOW_ENDPOINT, args, sink);
    if (cancel === undefined) {
      this.lastError = '无法打开轨迹流：连接尚未就绪';
      this.notify();
      return;
    }
    this.followCancel = cancel;
    this.record(`follow open ${sessionId.substring(0, 12)}`);
    this.notify();
    // 命令目录与文件树都是**会话作用域**的（`commands/list` 要 agentId，
    // `workspaceFiles/*` 要 workspaceFileScopeId = sessionId）。
    // 因此切会话必须重拉：不重拉的话新会话会用着上一个会话的命令集与目录树。
    this.refreshSessionScoped();
  }

  /**
   * 拉取与「当前选中会话」绑定的三类数据：命令目录、文件树根、`@` 引用候选。
   *
   * 三个调用都是只读的，且互不依赖，所以顺序发起即可，不需要并发原语。
   */
  private refreshSessionScoped(): void {
    this.refreshCommands();
    this.openWorkspace(this.selectedSessionId);
    this.refreshReferences('');
  }

  // ─────────────────── 斜杠命令（commands/list） ───────────────────

  /**
   * 拉取当前会话的斜杠命令目录。
   *
   * 【为什么按会话拉，而不是拉一次全局共用】上游 `commands/list` 的第一个参数是
   * `agentId`——命令集是**每个 agent 的**（插件可对单个会话禁用命令）。
   * 用别人的结果会让界面显示一批发出去必然失败的命令。
   */
  async refreshCommands(): Promise<void> {
    const agentId: string = this.selectedSessionId;
    if (!this.unaryReady || agentId.length === 0) {
      this.commands = [];
      this.commandsFor = '';
      this.notify();
      return;
    }
    const payload: Object | undefined = commandsListPayload(agentId);
    if (payload === undefined) {
      // 能力缺失（老 Host 没有这个端点）：**清空而不是保留旧值**，
      // 否则界面上会留着一份来自上一个会话/上一个 Host 的命令集。
      this.commands = [];
      this.commandsFor = '';
      this.record('commands 端点不在兼容上表');
      this.notify();
      return;
    }
    const result: RpcResult = await this.conn.call(commandsListEndpoint(), payload);
    if (!result.ok) {
      const failure = result.error;
      const code: string = failure === undefined ? 'unknown' : failure.code;
      this.commands = [];
      this.commandsFor = '';
      this.record(`commands fail ${code}`);
      this.notify();
      return;
    }
    const list: CommandCandidate[] = projectCommands(result.value);
    // 回包可能晚于一次切会话：只接受仍然对应当前会话的结果。
    if (this.selectedSessionId !== agentId) {
      return;
    }
    this.commands = list;
    this.commandsFor = agentId;
    this.record(`commands ok ${list.length} 条`);
    this.notify();
  }

  // ─────────────────── @ 引用候选（两个候选端点） ───────────────────

  /**
   * 拉取 `@` 引用候选。
   *
   * 【两个端点都发，合并结果】文件候选与会话候选是**两个不同端点**
   * （`fileReferences/list` / `sessionReferenceResolver/candidates`），
   * 没有哪一个能替代另一个。任一失败都只用另一个的结果，
   * 不用「失败的那个」的旧数据充数。
   *
   * `query` 是用户在输入框里已经打出的前缀：上游按它做**服务端筛选**，
   * 因此本地不再二次筛选（本地筛会与 Host 的排序/匹配规则不一致）。
   */
  async refreshReferences(query: string): Promise<void> {
    const agentId: string = this.selectedSessionId;
    this.referencesFor = query;
    if (!this.unaryReady || agentId.length === 0) {
      this.references = [];
      this.notify();
      return;
    }
    const filePayload: Object | undefined = fileReferencesPayload(agentId, query);
    const sessionPayload: Object | undefined = sessionReferencesPayload(agentId, query);
    const merged: ReferenceCandidate[] = [];
    if (filePayload !== undefined) {
      const files: RpcResult = await this.conn.call(fileReferencesEndpoint(), filePayload);
      if (files.ok) {
        const list: ReferenceCandidate[] = projectFileReferences(files.value);
        for (let i = 0; i < list.length; i++) {
          merged.push(list[i]);
        }
      } else {
        this.record(`refs(file) fail ${files.error === undefined ? 'unknown' : files.error.code}`);
      }
    }
    if (sessionPayload !== undefined) {
      const sessions: RpcResult = await this.conn.call(sessionReferencesEndpoint(), sessionPayload);
      if (sessions.ok) {
        const list: ReferenceCandidate[] = projectSessionReferences(sessions.value);
        for (let i = 0; i < list.length; i++) {
          merged.push(list[i]);
        }
      } else {
        this.record(`refs(session) fail ${sessions.error === undefined ? 'unknown' : sessions.error.code}`);
      }
    }
    // 丢弃过期回包：用户已经又敲了一个字符，这批候选对应的不是当前查询。
    if (this.referencesFor !== query || this.selectedSessionId !== agentId) {
      return;
    }
    this.references = merged;
    this.notify();
  }

  // ─────────────────── 工作区文件（workspaceFiles/*） ───────────────────

  /**
   * 打开某个会话的工作区根目录（设置文件浏览的**作用域**）。
   *
   * 【为什么文件浏览的作用域必须显式设置，而不能「跟着当前会话」】
   *   文件端点的作用域参数是 `workspaceFileScopeId`，而它**就是会话 id**（D2b §2.0）。
   *   用户在「工作区」页选的是一个**目录**，此时并没有「当前会话」——
   *   靠当前会话会让工作区页永远显示空目录（没有任何会话作用域），
   *   而空目录看起来只是「这个目录是空的」，是个看不见的缺陷。
   *   所以这里把作用域与会话选择**解耦**：会话是「在看哪个对话」，
   *   作用域是「在浏览哪个目录」，两者可以不同。
   */
  async openWorkspace(sessionId: string): Promise<void> {
    this.filePreview = undefined;
    this.fileTruncated = false;
    if (!this.unaryReady || sessionId.length === 0) {
      this.fileNodes = [];
      this.fileTreeFor = '';
      this.notify();
      return;
    }
    this.fileTreeFor = sessionId;
    const listing: FileNode[] | undefined =
      await this.listDirectory(WORKSPACE_ROOT_REQUEST_PATH, '', sessionId);
    if (listing === undefined) {
      this.fileNodes = [];
      this.fileTreeFor = '';
      this.notify();
      return;
    }
    // 期间用户又换了一个工作区：这次回包作废（否则文件树会串到别的工作区）
    if (this.fileTreeFor !== sessionId) {
      return;
    }
    this.fileNodes = listing;
    this.notify();
  }

  /**
   * 列出一层目录。
   *
   * `requestPath` 是**发给 Host 的路径**，`parentPath` 是**用来拼子节点路径的
   * 工作区相对路径**。两者在根目录上**不相等**：请求必须用
   * `WORKSPACE_ROOT_REQUEST_PATH`（空串会被 `gateway/bad-request: path is required`
   * 拒绝），而子节点前缀必须是空串（回复词法里工作区根就是空串）。
   * 合并成一个参数会让根目录要么列不出来、要么子节点路径变成 `./docs`。
   *
   * 返回 `undefined` 表示**调用失败**（与「目录为空」严格区分）：
   * 把失败当成空目录会让用户以为目录里没有文件。
   */
  private async listDirectory(requestPath: string, parentPath: string,
    scope: string): Promise<FileNode[] | undefined> {
    const payload: Object | undefined = workspaceListPayload(scope, requestPath);
    if (payload === undefined) {
      this.record('workspaceFiles 端点不在兼容上表');
      return undefined;
    }
    const result: RpcResult = await this.conn.call(workspaceListEndpoint(), payload);
    if (!result.ok) {
      const code: string = result.error === undefined ? 'unknown' : result.error.code;
      const message: string = result.error === undefined ? '' : result.error.message;
      // 把上游的 message 一起记下来：`gateway/bad-request` 的成因可能是
      // 「path 必填」（根写成空串）或别的参数问题，而错误码本身不区分它们。
      this.record(`ws list fail ${code} ${message}`);
      return undefined;
    }
    const projection = projectWorkspaceListing(result.value, parentPath, this.deliverablePaths());
    if (projection.truncated) {
      this.fileTruncated = true;
    }
    return projection.nodes;
  }

  /** 交付物相对路径（来自当前轨迹的 `deliverables/presented`），用于给文件树打标。 */
  private deliverablePaths(): string[] {
    const out: string[] = [];
    for (let i = 0; i < this.trajectoryList.length; i++) {
      const item: TrajectoryItem = this.trajectoryList[i];
      if (item.kind === TrajectoryKind.DELIVERABLE && item.fileName.length > 0) {
        out.push(item.fileName);
      }
    }
    return out;
  }

  /**
   * 展开/折叠一个目录。
   *
   * **懒加载**：首次展开才发 `workspaceFiles/list`。上游没有「整棵树」端点
   * （D2b §2.1：只有某一层的直接子项），预先递归会在大仓库上打出成百上千次 RPC。
   */
  async toggleDirectory(path: string): Promise<void> {
    const scope: string = this.fileTreeFor.length > 0 ? this.fileTreeFor : this.selectedSessionId;
    if (scope.length === 0) {
      return;
    }
    const node: FileNode | undefined = findNode(this.fileNodes, path);
    if (node === undefined) {
      return;
    }
    if (node.loaded) {
      this.fileNodes = replaceNode(this.fileNodes, path, collapseNode(node));
      this.notify();
      return;
    }
    const children: FileNode[] | undefined = await this.listDirectory(path, path, scope);
    if (children === undefined) {
      this.lastError = `目录「${path}」列表获取失败（详见诊断页旁路日志）`;
      this.notify();
      return;
    }
    this.fileNodes = replaceNode(this.fileNodes, path, expandNode(node, children));
    this.notify();
  }

  /**
   * 打开一个文件并取回文本。
   *
   * 失败时给出**上游的拒绝理由**（如 `workspace-file/not-text`），
   * 而不是一个空白预览：静默空白会被读成「文件是空的」。
   */
  async openFile(path: string, name: string): Promise<void> {
    const scope: string = this.fileTreeFor.length > 0 ? this.fileTreeFor : this.selectedSessionId;
    if (!this.unaryReady || scope.length === 0) {
      this.filePreview = undefined;
      this.notify();
      return;
    }
    const payload: Object | undefined = workspaceReadPayload(scope, path, 0);
    if (payload === undefined) {
      this.filePreview = projectWorkspaceFailure(path, name, '该 Host 不提供文件读取端点');
      this.notify();
      return;
    }
    const result: RpcResult = await this.conn.call(workspaceReadEndpoint(), payload);
    if (!result.ok) {
      const failure = result.error;
      const code: string = failure === undefined ? 'unknown' : failure.code;
      const message: string = failure === undefined ? '' : failure.message;
      this.record(`ws read fail ${code}`);
      this.filePreview = projectWorkspaceFailure(path, name, friendlyWorkspaceFailure(code, message));
      this.notify();
      return;
    }
    this.filePreview = projectWorkspaceText(result.value, path, name, 0);
    this.record(`ws read ok ${path}`);
    this.notify();
  }

  /** 关闭当前预览。 */
  closeFilePreview(): void {
    this.filePreview = undefined;
    this.notify();
  }

  /** 处理 `session/follow` 的一帧：snapshot / event / assistant-stream */
  private handleFollowFrame(value: Object): void {
    const type: string = getString(value, 'type') ?? '';
    if (type === 'snapshot') {
      const records: Object[] | undefined = getArray(value, 'records');
      const items: TrajectoryItem[] = [];
      if (records !== undefined) {
        for (let i = 0; i < records.length; i++) {
          const projected: TrajectoryItem | undefined = projectWireRecord(records[i]);
          if (projected !== undefined) {
            appendOrMerge(items, projected);
          }
        }
      }
      this.trajectoryList = items;
      this.applySessionProjections(value);
      this.record(`follow snapshot records=${records === undefined ? 0 : records.length}`);
      this.notify();
      return;
    }
    if (type === 'event') {
      const projected: TrajectoryItem | undefined = projectWireRecord(value);
      if (projected !== undefined) {
        const next: TrajectoryItem[] = this.trajectoryList.slice();
        appendOrMerge(next, projected);
        this.trajectoryList = next;
      }
      const event: Object | undefined = getRecord(value, 'event');
      if (event !== undefined) {
        const eventType: string = getString(event, 'type') ?? '';
        // 未识别的事件类型要汇总到诊断页供回填形状表。
        // 判据是 `isKnownEventType()` 而**不是** `classifyEventType()` 的返回值：
        // 后者对未知类型刻意降级为 MESSAGE，用返回值判断会把「新事件」
        // 和「已知但不占行的内容事件」混为一谈，于是升级永远静默通过。
        if (!isKnownEventType(eventType)) {
          this.noteUnknown(`event:${eventType}`);
        }
        // 运行态与标题都可能因事件变化；标题取投影，需要重新拉列表才准，
        // 这里只在「轮次结束」类事件上做一次轻量刷新，避免每个 token 都拉一次列表。
        if (mayChangeTurnState(eventType) || mayChangeSessionTitle(eventType)) {
          this.scheduleSessionRefresh();
        }
      }
      this.notify();
      return;
    }
    if (type === 'assistant-stream') {
      // 进行中的助手输出：当前只用于把「运行中」点亮，逐块文本渲染待事件契约确认后接入
      this.running = true;
      this.notify();
      return;
    }
    this.noteUnknown(`follow:${type}`);
  }

  /** 从 snapshot 里读投影，更新运行态（标题等由列表投影负责） */
  private applySessionProjections(value: Object): void {
    const projections: Object | undefined = getRecord(value, 'projections');
    if (projections === undefined) {
      return;
    }
    const values: Object | undefined = getRecord(projections, 'values');
    if (values === undefined) {
      return;
    }
    const typed: Record<string, Object> = values as Record<string, Object>;
    const title: Object | undefined = typed[PROJECTION_TITLE];
    if (typeof title === 'string') {
      const text: string = title as string;
      this.updateSessionTitle(this.selectedSessionId, text);
    }
  }

  private updateSessionTitle(sessionId: string, title: string): void {
    let changed: boolean = false;
    const next: SessionListItem[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const s: SessionListItem = this.sessions[i];
      if (s.id === sessionId && s.title !== title) {
        changed = true;
        next.push({
          id: s.id, title: title, cwd: s.cwd, updatedAt: s.updatedAt, createdAt: s.createdAt,
          running: s.running, blank: s.blank, raw: s.raw
        });
      } else {
        next.push(s);
      }
    }
    if (changed) {
      this.sessions = next;
    }
  }

  // ───────────────────────── 控制流（队列/作业/投影） ─────────────────────────

  private openControlStream(): void {
    this.cancelControl();
    const sink: StreamSink = {
      onItem: (value: Object) => {
        const type: string = getString(value, 'type') ?? '';
        if (type === 'baseline') {
          this.controlReady = true;
          this.record('control baseline');
          this.notify();
          return;
        }
        if (type === 'queue' || type === 'jobs' || type === 'projection') {
          // 队列与作业属于会话内视图，由对应页面按需读取；中枢只确认流是活的
          this.record(`control ${type}`);
          return;
        }
        this.noteUnknown(`control:${type}`);
      },
      onError: (code: string, message: string) => {
        this.controlCancel = undefined;
        this.record(`control error ${code}`);
        if (code !== GATEWAY_SIGNATURE_INVALID) {
          this.lastError = `控制流失败：${code} ${message}`;
        }
        this.notify();
      },
      onEnd: () => {
        this.controlCancel = undefined;
        this.record('control end');
        this.notify();
      }
    };
    // 空参数也要有声明类型：ArkTS 禁止无类型对象字面量（arkts-no-untyped-obj-literals）
    const emptyArgs: Record<string, Object> = {};
    const args: Object | undefined = argsFor(SESSION_CONTROL_ENDPOINT, emptyArgs as Object);
    if (args === undefined) {
      this.noteUnknown('control:no-args-contract');
      return;
    }
    const cancel = this.conn.openStream(SESSION_CONTROL_ENDPOINT, args, sink);
    this.controlCancel = cancel;
    this.record(`control open ${cancel === undefined ? 'failed' : 'ok'}`);
  }

  // ───────────────────────── 发送与取消 ─────────────────────────

  /**
   * 发送提示词。
   *
   * 离线时进入待发队列（D3 §3.6「离线排队」）：网络恢复后由 `flushOutbox()` 按序补发。
   * `requestId` 由客户端生成，用于把乐观回显与最终落盘消息对上（上游 `SessionPromptRequest`
   * 的 `requestId` 就是为这个用途存在的）。
   */
  async sendPrompt(text: string): Promise<boolean> {
    const sessionId: string = this.selectedSessionId;
    if (sessionId.length === 0) {
      this.lastError = '尚未选择会话';
      this.notify();
      return false;
    }
    const trimmed: string = text;
    if (trimmed.trim().length === 0) {
      return false;
    }
    const requestId: string = mintRequestId();
    if (!this.unaryReady) {
      this.outboxList.push({ requestId: requestId, sessionId: sessionId, text: trimmed, at: Date.now() });
      this.lastError = '当前离线：已加入待发队列，连接恢复后自动发送';
      this.notify();
      return false;
    }
    return await this.sendPromptNow(requestId, sessionId, trimmed);
  }

  private async sendPromptNow(requestId: string, sessionId: string, text: string): Promise<boolean> {
    const part: Record<string, Object> = {};
    part['type'] = 'text';
    part['text'] = text;
    const content: Object[] = [part as Object];
    const request: Record<string, Object> = {};
    request['requestId'] = requestId;
    request['sessionId'] = sessionId;
    request['mode'] = 'queue';
    request['content'] = content;
    const body: Record<string, Object> = {};
    body['request'] = request as Object;
    const args: Object | undefined = argsFor(SESSION_PROMPT_ENDPOINT, body as Object);
    if (args === undefined) {
      this.lastError = '兼容面缺少提示词端点的参数契约';
      this.notify();
      return false;
    }
    const result: RpcResult = await this.conn.call(SESSION_PROMPT_ENDPOINT, args);
    if (result.ok) {
      this.running = true;
      this.record(`prompt accepted ${requestId.substring(0, 8)}`);
      this.notify();
      return true;
    }
    const failure = result.error;
    this.lastError = `发送失败：${friendlyFailure(failure === undefined ? 'unknown' : failure.code, failure === undefined ? '' : failure.message)}`;
    this.record(`prompt fail ${failure === undefined ? '?' : failure.code}`);
    this.notify();
    return false;
  }

  /** 网络恢复后按序补发待发队列 */
  private async flushOutbox(): Promise<void> {
    if (!this.unaryReady || this.outboxList.length === 0) {
      return;
    }
    const queue: OutboxEntry[] = this.outboxList;
    this.outboxList = [];
    for (let i = 0; i < queue.length; i++) {
      const entry: OutboxEntry = queue[i];
      await this.sendPromptNow(entry.requestId, entry.sessionId, entry.text);
    }
    this.notify();
  }

  /** 取消当前轮次（D3 §5.1 Esc / 停止按钮） */
  async cancelTurn(): Promise<boolean> {
    const sessionId: string = this.selectedSessionId;
    if (sessionId.length === 0) {
      return false;
    }
    const request: Record<string, Object> = {};
    request['sessionId'] = sessionId;
    const body: Record<string, Object> = {};
    body['request'] = request as Object;
    const args: Object | undefined = argsFor(SESSION_CANCEL_ENDPOINT, body as Object);
    if (args === undefined) {
      return false;
    }
    const result: RpcResult = await this.conn.call(SESSION_CANCEL_ENDPOINT, args);
    if (result.ok) {
      this.running = false;
      this.record('cancel accepted');
      this.notify();
      return true;
    }
    const failure = result.error;
    this.lastError = `取消失败：${friendlyFailure(failure === undefined ? 'unknown' : failure.code, failure === undefined ? '' : failure.message)}`;
    this.notify();
    return false;
  }

  // ───────────────────────── 诊断 ─────────────────────────

  /** 连接诊断 + 中枢自身事实（D1 §7.8 五项的落点） */
  async diagnose(): Promise<DiagnosticReport> {
    return await this.conn.diagnose();
  }

  // ───────────────────────── 内部工具 ─────────────────────────

  private titleOf(sessionId: string): string {
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === sessionId) {
        return this.sessions[i].title;
      }
    }
    return '';
  }

  private upsertPending(item: PendingItem): void {
    const next: PendingItem[] = [];
    let replaced: boolean = false;
    for (let i = 0; i < this.pendingList.length; i++) {
      if (this.pendingList[i].id === item.id) {
        next.push(item);
        replaced = true;
      } else {
        next.push(this.pendingList[i]);
      }
    }
    if (!replaced) {
      next.push(item);
    }
    this.pendingList = next;
    this.notify();
  }

  private resolvePending(pendingId: string, note: string): void {
    this.record(`pending resolved ${pendingId.substring(0, 8)} ${note}`);
    this.removePending(pendingId);
  }

  private resolvePendingById(eventId: string, note: string): void {
    const renderId: string | undefined = this.waterfallEventIds.get(eventId);
    this.waterfallEventIds.delete(eventId);
    if (renderId !== undefined) {
      this.resolvePending(renderId, note);
      return;
    }
    this.removePending(eventId);
  }

  private removePending(pendingId: string): void {
    const next: PendingItem[] = [];
    for (let i = 0; i < this.pendingList.length; i++) {
      if (this.pendingList[i].id !== pendingId) {
        next.push(this.pendingList[i]);
      }
    }
    this.pendingList = next;
    this.notify();
  }

  private record(line: string): void {
    if (!this.traceEnabled) {
      return;
    }
    const next: string[] = this.traceLines.slice();
    next.push(`${new Date().toISOString().substring(11, 23)}  ${line}`);
    while (next.length > TRACE_LIMIT) {
      next.shift();
    }
    this.traceLines = next;
  }

  /**
   * 记录一条我们**不认识**的上游事件类型。
   *
   * 存在理由：轨迹的事件类型清单无法从「我们没有的文档」里得到，
   * 但我们可以在真实设备上**观测**到它。把未识别类型汇总在诊断页，
   * 一次真机运行就能得到权威清单——把「未知」变成可观测、可收敛的缺口，
   * 而不是让它静默丢失。
   */
  private noteUnknown(kind: string): void {
    for (let i = 0; i < this.unknownTypes.length; i++) {
      if (this.unknownTypes[i] === kind) {
        return;
      }
    }
    const next: string[] = this.unknownTypes.slice();
    next.push(kind);
    this.unknownTypes = next;
    this.record(`unknown ${kind}`);
    this.notify();
  }
}

// ───────────────────────── 纯函数：线上事件 → 呈现契约 ─────────────────────────

/**
 * 把一条 `session/follow` 记录投影成轨迹条目。
 *
 * 【取值路径从哪来（这一版的关键变化）】
 *   字段名与取值路径**全部**来自 `dshcompat` 的实测形状表
 *   （`SESSION_EVENT_SHAPES`，见 D2 §8.7.7：逐帧解码 Host 落盘日志取得）。
 *   本文件不再持有任何字段名——这不是纪律上的洁癖：**写错字段名不会报错，
 *   只会让正文永远是空的**，这种失效必须在编译期与门禁上被拦住。
 *
 *   上一版这里把整段 `data` 用 `JSON.stringify` 塞进正文，理由是
 *   「字段名还没有实测证据」。证据现已取得，那条妥协随之失效：
 *   用户该看到的是消息正文，不是一段 JSON。
 *
 * 【未识别事件怎么办】
 *   形状表里没有的类型（升级后新出现的）**不静默丢弃**：仍按消息呈现原始
 *   `data` 并标记展开，同时由 `noteUnknown()` 汇总到诊断页，
 *   让下次升级时能回填形状表。宁可多一行「未识别」，也不要让对话少一截。
 */
export function projectWireRecord(record: Object): TrajectoryItem | undefined {
  const type: string = getString(record, 'type') ?? '';
  if (type !== 'event') {
    return undefined;
  }
  const event: Object | undefined = getRecord(record, 'event');
  if (event === undefined) {
    return undefined;
  }
  const eventType: string = getString(event, 'type') ?? '';
  const seq: number = getNumber(event, 'seq') ?? 0;
  const time: number = getNumber(event, 'time') ?? 0;
  const data: Object | undefined = getRecord(event, 'data');
  const shape: SessionEventShape | undefined = eventShapeOf(eventType);

  // 审计类事件不进轨迹：它们没有用户可读内容，放进去只会淹没对话
  if (isAuditEventType(eventType)) {
    return undefined;
  }
  // 边界事件（轮次/步/标题…）驱动状态但不占行——一次对话会被它们刷屏
  if (shape !== undefined && !shape.standalone) {
    return undefined;
  }

  const family: EventFamily = classifyEventType(eventType);
  const kind: TrajectoryKind = familyKind(family);
  const item: TrajectoryItem = makeItem(`ev-${seq}`, kind, time);
  item.speaker = isUserAuthoredEvent(eventType) ? Speaker.USER : Speaker.ASSISTANT;

  if (shape === undefined) {
    // 未识别类型：如实呈现原始载荷（不是猜测，也不丢弃）
    item.body = data === undefined ? '' : (JSON.stringify(data) ?? '');
    item.expanded = true;
    return item;
  }

  const text: ResolvedSlot = resolveSlot(data, shape, ContentSlot.CONTENT_BLOCKS);
  if (text.found) {
    item.body = textFromBlocks(text.value);
  }
  const model: ResolvedSlot = resolveSlot(data, shape, ContentSlot.MODEL);
  if (model.found) {
    item.model = asText(model.value);
  }

  if (kind === TrajectoryKind.TOOL) {
    applyToolSlots(item, data, shape);
    // 用调用 id 作条目 id：`tool/call` 与 `tool/result` 因此落到同一张工具卡
    const callId: ResolvedSlot = resolveSlot(data, shape, ContentSlot.CALL_ID);
    if (callId.found) {
      item.callId = asText(callId.value);
      item.id = `ev-call-${item.callId}`;
    }
  } else if (kind === TrajectoryKind.SUBAGENT) {
    const label: ResolvedSlot = resolveSlot(data, shape, ContentSlot.SUBAGENT_LABEL);
    if (label.found) {
      item.title = asText(label.value);
    }
    item.subagentName = item.title;
  } else if (kind === TrajectoryKind.GOAL) {
    const objective: ResolvedSlot = resolveSlot(data, shape, ContentSlot.GOAL_TITLE);
    if (objective.found) {
      item.title = asText(objective.value);
    }
    const phase: ResolvedSlot = resolveSlot(data, shape, ContentSlot.GOAL_PHASE);
    if (phase.found) {
      item.progress = asText(phase.value);
    }
  } else if (kind === TrajectoryKind.JOB) {
    applyTodoSlots(item, data, shape);
  } else if (kind === TrajectoryKind.DELIVERABLE) {
    applyDeliverableSlots(item, data, shape);
  } else if (!text.found) {
    // 压缩摘要等「有正文但无 role」的事件：摘要就是正文
    const summary: ResolvedSlot = resolveSlot(data, shape, ContentSlot.SUMMARY);
    if (summary.found) {
      item.body = asText(summary.value);
    }
  }

  if (kind === TrajectoryKind.ERROR) {
    // 失败信号默认展开：D3 §4 要求失败必须可见，而不是等用户点开
    item.expanded = true;
    const retry: ResolvedSlot = resolveSlot(data, shape, ContentSlot.RETRY);
    if (retry.found) {
      item.title = `重试 ${asText(retry.value)}`;
    }
  }
  return item;
}

/**
 * 把投影结果并入列表：同 id 则合并，否则追加。
 *
 * 为什么不是简单 `push`：`tool/call` 与 `tool/result` 共享同一个条目 id
 * （由 `callId` 派生），而**只有 call 携带工具名**。若各占一行，
 * 用户看到的是「没有名字的工具卡 + 不知出处的输出」。
 * 合并策略与到达顺序无关（见 `mergeTrajectoryItem`）。
 */
function appendOrMerge(items: TrajectoryItem[], incoming: TrajectoryItem): void {
  const at: number = indexOfItem(items, incoming.id);
  if (at < 0) {
    items.push(incoming);
    return;
  }
  items[at] = mergeTrajectoryItem(items[at], incoming);
}

/**
 * 在文件树里找一个节点（深度优先）。
 *
 * 为什么按路径找而不是持有节点引用：ArkUI 的 `@State` 在更新时**复制数组**
 * （`this.fileNodes = next`），旧引用会指向被替换掉的旧树。
 * 按路径查找与「树被重建过几次」无关，因此不会拿到失效引用。
 */
function findNode(nodes: FileNode[], path: string): FileNode | undefined {
  for (let i = 0; i < nodes.length; i++) {
    if (nodes[i].path === path) {
      return nodes[i];
    }
    const hit: FileNode | undefined = findNode(nodes[i].children, path);
    if (hit !== undefined) {
      return hit;
    }
  }
  return undefined;
}

/** 不可变替换：返回一棵把 `path` 处节点换成 `next` 的新树。 */
function replaceNode(nodes: FileNode[], path: string, next: FileNode): FileNode[] {
  const out: FileNode[] = [];
  for (let i = 0; i < nodes.length; i++) {
    const node: FileNode = nodes[i];
    if (node.path === path) {
      out.push(next);
      continue;
    }
    if (node.children.length === 0) {
      out.push(node);
      continue;
    }
    out.push({
      name: node.name, path: node.path, kind: node.kind, size: node.size,
      modifiedAt: node.modifiedAt, loaded: node.loaded,
      children: replaceNode(node.children, path, next), deliverable: node.deliverable
    });
  }
  return out;
}

/** 展开：挂上子节点并标记已加载。 */
function expandNode(node: FileNode, children: FileNode[]): FileNode {
  return {
    name: node.name, path: node.path, kind: node.kind, size: node.size,
    modifiedAt: node.modifiedAt, loaded: true, children: children, deliverable: node.deliverable
  };
}

/**
 * 折叠：**保留**已加载的子节点。
 *
 * 保留的理由：折叠只是视觉状态，丢弃子节点会让再次展开又打一次 RPC；
 * 而 `loaded` 已经表达了「拉过了」，清空它等于把一次成功的结果扔掉。
 */
function collapseNode(node: FileNode): FileNode {
  return {
    name: node.name, path: node.path, kind: node.kind, size: node.size,
    modifiedAt: node.modifiedAt, loaded: node.loaded, children: node.children,
    deliverable: node.deliverable
  };
}

/**
 * 文件读取失败的上游错误码 → 用户可读理由。
 *
 * 上游对不可预览的文件是**明确拒绝**（D2b §2.3），拒绝理由本身就是给用户的信息；
 * 但要翻译成「发生了什么 + 可以做什么」，而不是把错误码抛到界面上（D3 §4 文案纪律）。
 */
function friendlyWorkspaceFailure(code: string, message: string): string {
  if (code === 'workspace-file/not-text') {
    return '二进制文件（非 UTF-8 文本），端侧不预览。可在 Host 侧用工具读取。';
  }
  if (code === 'workspace-file/too-large') {
    return '文件超过 Host 的单页上限，端侧不预览。可在 Host 侧用工具分段读取。';
  }
  if (code === 'workspace-file/not-regular-file') {
    return '不是一个普通文件（可能是目录或符号链接），无法预览。';
  }
  if (code === 'workspace-file/not-found') {
    return '文件不存在或已被移动。';
  }
  if (code === 'workspace-file/outside-workspace') {
    return '该路径在会话工作区之外，Host 拒绝访问。';
  }
  return message.length > 0 ? `读取失败：${message}（${code}）` : `读取失败：${code}`;
}

/** 形状表里一个槽位的解析结果 */
interface ResolvedSlot {
  /** 是否命中了某条路径（命中但值为空串也算命中——空串是有效内容） */
  found: boolean;
  value: Object | undefined;
}

/**
 * 按形状表取一个槽位的值。
 *
 * 只走形状表给出的那**一条**路径。**不做任何类型转换、不做候选回退**：
 * 取到的可能是字符串、数组、对象，由调用方按槽位语义解释。
 * 路径取不到就如实「没取到」——静默回退到别的字段名比取不到更危险。
 */
function resolveSlot(data: Object | undefined, shape: SessionEventShape,
  slot: ContentSlot): ResolvedSlot {
  const binding: SlotBinding | undefined = slotBinding(shape, slot);
  if (binding === undefined || data === undefined) {
    return { found: false, value: undefined };
  }
  const value: Object | undefined = readPath(data, binding.path);
  if (value === undefined) {
    return { found: false, value: undefined };
  }
  return { found: true, value: value };
}

/**
 * `content` 块数组 → 文本。
 *
 * 实测形状（D2 §8.7.7）：`array<{type:'text', text}>`。
 * 需要处理两种真实的嵌套：
 *   1. `tool/result` 的块是 `{type:'tool-result', content:[…]}`——正文在**内层** `content`；
 *   2. 非文本块的内部形状**仍未实测**，因此按块类型名占位，
 *      而不是猜它的字段名去渲染（猜错只会显示空白，且不报错）。
 * 若整段根本不是数组（旧版或异常），按字符串处理。
 */
function textFromBlocks(value: Object | undefined): string {
  if (typeof value === 'string') {
    return value as string;
  }
  if (!Array.isArray(value)) {
    return asText(value);
  }
  const blocks: Object[] = value as Object[];
  const parts: string[] = [];
  for (let i = 0; i < blocks.length; i++) {
    const block: Object = blocks[i];
    // 工具结果块：正文在内层 content 里（实测）
    const nested: Object[] | undefined = getArray(block, 'content');
    if (nested !== undefined && getString(block, 'type') === 'tool-result') {
      const inner: string = textFromBlocks(nested);
      if (inner.length > 0) {
        parts.push(inner);
      }
      continue;
    }
    const text: string | undefined = getString(block, 'text');
    if (text !== undefined) {
      parts.push(text);
      continue;
    }
    const blockType: string = getString(block, 'type') ?? '';
    if (blockType.length > 0 && blockType !== 'text') {
      // 非文本块：显示类型占位，不猜内部结构
      parts.push(`[${blockType}]`);
    }
  }
  return parts.join('\n');
}

/** 把任意 JSON 值渲染成一行可读文本（用于标题类槽位） */
function asText(value: Object | undefined): string {
  if (value === undefined) {
    return '';
  }
  if (typeof value === 'string') {
    return value as string;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return `${value}`;
  }
  return JSON.stringify(value) ?? '';
}

/** 工具类事件的槽位填充（名称 / 参数 / 输出 / 配对 id） */
function applyToolSlots(item: TrajectoryItem, data: Object | undefined,
  shape: SessionEventShape): void {
  const name: ResolvedSlot = resolveSlot(data, shape, ContentSlot.TOOL_NAME);
  if (name.found) {
    item.toolName = asText(name.value);
  }
  const args: ResolvedSlot = resolveSlot(data, shape, ContentSlot.TOOL_ARGS);
  if (args.found) {
    // 实测：`arguments` 已是 JSON 编码后的**字符串**；直接显示，不要二次编码
    item.toolArgs = asText(args.value);
  }
  const output: ResolvedSlot = resolveSlot(data, shape, ContentSlot.TOOL_OUTPUT);
  if (output.found) {
    item.toolOutput = asText(output.value);
  } else {
    const blocks: ResolvedSlot = resolveSlot(data, shape, ContentSlot.CONTENT_BLOCKS);
    if (blocks.found) {
      item.toolOutput = textFromBlocks(blocks.value);
    }
  }
  const callId: ResolvedSlot = resolveSlot(data, shape, ContentSlot.CALL_ID);
  if (callId.found) {
    item.callId = asText(callId.value);
  }

  if (item.toolState === ToolState.PENDING) {
    // 形状里有没有「工具名」绑定，决定这是调用帧还是结果帧——
    // 不去看工具名**字符串**是否为空：结果帧本来就不携带工具名（实测），
    // 用字符串判空会把每个结果都当成「还没开始的调用」。
    item.toolState = slotBinding(shape, ContentSlot.TOOL_NAME) === undefined
      ? ToolState.SUCCESS
      : ToolState.RUNNING;
  }

  // 实测：失败的结果帧同时带内层 `isError:true` 与顶层 `error{name,code}`。
  // 只看 `message.content` 会把失败显示成成功——最典型的静默错误。
  const isError: boolean | undefined = boolSlot(data, shape, ContentSlot.TOOL_IS_ERROR);
  const errorCode: ResolvedSlot = resolveSlot(data, shape, ContentSlot.TOOL_ERROR_CODE);
  const errorName: ResolvedSlot = resolveSlot(data, shape, ContentSlot.TOOL_ERROR_NAME);
  if (isError === true || errorCode.found || errorName.found) {
    item.toolState = ToolState.FAILED;
    const label: string = errorName.found ? asText(errorName.value) : asText(errorCode.value);
    if (label.length > 0 && item.toolOutput.indexOf(label) < 0) {
      item.toolOutput = item.toolOutput.length === 0 ? label : `${item.toolOutput}\n[${label}]`;
    }
    // D3 §4：失败默认展开
    item.expanded = true;
  }
}

/** 读一个布尔槽位（值不是布尔时视为未取到） */
function boolSlot(data: Object | undefined, shape: SessionEventShape,
  slot: ContentSlot): boolean | undefined {
  const resolved: ResolvedSlot = resolveSlot(data, shape, slot);
  if (!resolved.found) {
    return undefined;
  }
  return typeof resolved.value === 'boolean' ? resolved.value as boolean : undefined;
}

/** 交付物类事件的槽位填充（实测：`files` 是数组，取第一项） */
function applyDeliverableSlots(item: TrajectoryItem, data: Object | undefined,
  shape: SessionEventShape): void {
  const path: ResolvedSlot = resolveSlot(data, shape, ContentSlot.DELIVERABLE_FILE);
  const desc: ResolvedSlot = resolveSlot(data, shape, ContentSlot.DELIVERABLE_DESC);
  if (path.found) {
    const full: string = asText(path.value);
    item.fileName = full;
    item.title = full;
  }
  if (desc.found) {
    item.progress = asText(desc.value);
    item.body = item.progress;
  }
  if (item.title.length === 0) {
    item.title = '交付物';
  }
}

/** 任务清单类事件的槽位填充（`array<{content,status}>`） */
function applyTodoSlots(item: TrajectoryItem, data: Object | undefined,
  shape: SessionEventShape): void {
  const list: ResolvedSlot = resolveSlot(data, shape, ContentSlot.TODO_LIST);
  if (!list.found || !Array.isArray(list.value)) {
    return;
  }
  const todos: Object[] = list.value as Object[];
  const lines: string[] = [];
  let done: number = 0;
  for (let i = 0; i < todos.length; i++) {
    const content: string = getString(todos[i], 'content') ?? '';
    const status: string = getString(todos[i], 'status') ?? '';
    if (status === 'completed') {
      done++;
    }
    const mark: string = status === 'completed' ? '✓' : (status === 'in_progress' ? '▸' : '·');
    lines.push(`${mark} ${content}`);
  }
  item.body = lines.join('\n');
  item.title = `任务清单（${done}/${todos.length}）`;
  item.progress = item.title;
  item.percent = todos.length === 0 ? -1 : Math.round(done * 100 / todos.length);
}

/** 上游呈现家族（`dshcompat.EventFamily`）→ 本层轨迹枚举 */
function familyKind(family: EventFamily): TrajectoryKind {
  if (family === EventFamily.REASONING) {
    return TrajectoryKind.REASONING;
  }
  if (family === EventFamily.TOOL) {
    return TrajectoryKind.TOOL;
  }
  if (family === EventFamily.SUBAGENT) {
    return TrajectoryKind.SUBAGENT;
  }
  if (family === EventFamily.GOAL) {
    return TrajectoryKind.GOAL;
  }
  if (family === EventFamily.JOB) {
    return TrajectoryKind.JOB;
  }
  if (family === EventFamily.ERROR) {
    return TrajectoryKind.ERROR;
  }
  if (family === EventFamily.DELIVERABLE) {
    return TrajectoryKind.DELIVERABLE;
  }
  return TrajectoryKind.MESSAGE;
}

/**
 * 审批的三选。
 *
 * id 取自 `Trajectory.ets` 的稳定契约（桩数据与中枢必须一致，否则「主选项判定」会失效——
 * 真实发生过：桩用 `once`、中枢用 `allow`，导致真机上危险动作的拒绝按钮拿不到主选样式）。
 *
 * 上游只有一次性授权与拒绝（见 `decideApproval` 的词汇纪律说明），
 * 因此第三项「本次会话内均允许」必须是**本地策略**，文案如实说明，
 * 不能让用户以为它改变了 Host 的行为。
 */
function approvalChoices(): PendingChoice[] {
  return [
    { id: APPROVAL_CHOICE_ALLOW, label: '允许一次', detail: '仅本次放行' },
    { id: APPROVAL_CHOICE_ALLOW_ALWAYS, label: '本次会话内均允许', detail: '仅在本客户端生效，Host 侧仍逐次询问' },
    { id: APPROVAL_CHOICE_DENY, label: '拒绝', detail: '阻止该操作' }
  ];
}

/** 由工具名推断风险等级（D3 §3.4「危险动作视觉权重反转」） */
function riskOfTool(toolName: string): RiskLevel {
  const lower: string = toolName.toLowerCase();
  if (lower.indexOf('bash') >= 0 || lower.indexOf('pwsh') >= 0 || lower.indexOf('shell') >= 0
    || lower.indexOf('delete') >= 0 || lower.indexOf('rm') >= 0 || lower.indexOf('write') >= 0
    || lower.indexOf('edit') >= 0) {
    return RiskLevel.DANGEROUS;
  }
  if (lower.indexOf('web') >= 0 || lower.indexOf('fetch') >= 0 || lower.indexOf('git') >= 0) {
    return RiskLevel.ELEVATED;
  }
  return RiskLevel.NORMAL;
}

/** 生成客户端请求 id（用于乐观回显与落盘消息对账） */
function mintRequestId(): string {
  const hex: string = '0123456789abcdef';
  let out: string = '';
  for (let i = 0; i < 32; i++) {
    out += hex.charAt(Math.floor(Math.random() * 16));
  }
  return `req-${out.substring(0, 8)}-${out.substring(8, 12)}-${out.substring(12, 16)}-${out.substring(16, 20)}-${out.substring(20)}`;
}

/**
 * 认证失败的用户可见建议。
 *
 * D3 §4 纪律：错误文案必须包含「发生了什么 + 可以做什么」，
 * 禁止裸抛技术栈信息。因此这里把状态码翻译成可执行动作。
 */
function authAdvice(status: number, message: string): string {
  if (status === 401) {
    return 'Host 拒绝了本次访问（未认证）。请回到「添加 Host」重新粘贴带令牌的启动链接。';
  }
  if (status === 403) {
    return 'Host 的信任栅栏拒绝了该来源。请确认你是通过本机回环地址或已配对的隧道访问，而不是直接暴露 Host。';
  }
  if (status === 404) {
    return '该地址上没有 dsh Web 服务。请确认 Host 已启动，且端口与链接中的一致。';
  }
  return `连接失败（HTTP ${status}）：${message}。请检查网络与 Host 状态后重试。`;
}

/**
 * 把载体层失败码翻译成「发生了什么 + 可以做什么」。
 *
 * 为什么必须做这层翻译（有实测驱动）：首次真机端到端验证时，界面显示的是
 * `carrier/parse invalid JSON body for session/list`。这条消息对用户毫无用处——
 * 它既不说清是网络问题还是 Host 问题，也指不出下一步。而 D3 §4 明确要求
 * 每条失败文案都要给出可执行动作。
 *
 * 这几条翻译背后是一个**真实的排查结论**：`carrier/parse` 与 `carrier/closed`
 * 同时出现，说明载体链路本身不可靠（典型场景是用 `hdc rport` 之类的开发转发
 * 通道承载多条并发长连接），而不是 Host 或协议栈的问题——
 * 同样的调用从宿主直连全部成功。文案要能把用户引向这个判断。
 */
function friendlyFailure(code: string, message: string): string {
  if (code === 'client/endpoint-invalid') {
    return `客户端拼装了一个 Host 不认识的 endpoint（${message}）。这是本客户端的兼容面缺陷，`
      + '请提交诊断报告以便修正上表——重试与换网络都不会有用。';
  }
  if (code === 'carrier/parse') {
    return '响应无法解析——通常是中间转发通道截断了连接（开发期的端口转发常见）。'
      + '请改用直连本机回环，或使用 hostkit 的加密隧道。';
  }
  if (code === 'carrier/closed' || code === 'carrier/transport') {
    return '连接在传输中断开——中间转发通道不稳定，或 Host 已停止。'
      + '请检查 Host 是否仍在运行；若经端口转发访问，请改用 hostkit 隧道。';
  }
  if (code === 'carrier/timeout') {
    return '请求超时。请检查网络连通性；若 Host 负载很高可稍后重试。';
  }
  if (code === GATEWAY_ARGUMENTS_INVALID || code === GATEWAY_INPUT_INVALID) {
    return `调用参数与 Host 的契约不符（${message}）。这是客户端兼容面的问题，请提交诊断报告以便修正上表。`;
  }
  return `${code} ${message}`;
}
