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
import type { DiagnosticReport, EventSink, HostFacts, RpcResult, StreamSink } from 'connection';
import { EVENTS_RESULT_ENDPOINT, getArray, getBoolean, getNumber, getRecord, getString } from 'connection';
import {
  APPROVAL_ALLOWED_ONCE,
  APPROVAL_REJECTED,
  argsFor,
  classifyEventType,
  EventFamily,
  isAuditEventType,
  isSessionListEvent,
  isUserAuthoredEvent,
  mayChangeSessionTitle,
  mayChangeTurnState,
  MODEL_CATALOG_ENDPOINT,
  PLUGIN_INVENTORY_ENDPOINT,
  PROJECTION_TITLE,
  RemoteEventFrameType,
  SESSION_CANCEL_ENDPOINT,
  SESSION_CONTROL_ENDPOINT,
  SESSION_CREATE_ENDPOINT,
  SESSION_FOLLOW_ENDPOINT,
  SESSION_LIST_ENDPOINT,
  SESSION_PROMPT_ENDPOINT,
  SURFACE,
  WATERFALL_APPROVAL,
  WATERFALL_QUESTION
} from 'dshcompat';
import { projectSessionList } from '../model/SessionList';
import type { SessionListItem } from '../model/SessionList';
import {
  APPROVAL_CHOICE_ALLOW,
  APPROVAL_CHOICE_ALLOW_ALWAYS,
  APPROVAL_CHOICE_DENY,
  makeItem,
  PendingKind,
  RiskLevel,
  Speaker,
  ToolState,
  TrajectoryKind
} from '../model/Trajectory';
import type { PendingChoice, PendingItem, TrajectoryItem } from '../model/Trajectory';
import {
  projectDefaultSelection,
  projectModelCatalog,
  projectPluginInventory
} from '../model/Settings';
import type { ModelOption, ModelSelection, PluginItem } from '../model/Settings';

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

  private constructor() {
    this.conn = new Connection({ surface: SURFACE });
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

  /** 断开并释放所有流（仅一个窗口会调用；其他窗口只订阅快照） */
  async disconnect(): Promise<void> {
    this.cancelFollow();
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
      plugins: this.plugins
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

    this.notify();
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
            items.push(projected);
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
        next.push(projected);
        this.trajectoryList = next;
      }
      const event: Object | undefined = getRecord(value, 'event');
      if (event !== undefined) {
        const eventType: string = getString(event, 'type') ?? '';
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
        if (code !== 'gateway/signature-invalid') {
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
 * 【重要说明 · 为什么不在这里猜字段名】
 *   上游事件形状是 `{type: string, seq, time, data: JsonValue}`，其中 `type` 的取值域
 *   来自 `dsh-session` 的 `SessionEventMap`（各插件通过 declaration merging 扩展），
 *   实测已确认存在的类型包括 `permission/preset`、`sandbox/mode`、`approval/policy`。
 *   这些是**审计类**事件，不构成会话内容。
 *
 *   会话内容类事件（用户消息 / 助手消息 / 思考 / 工具调用 / 子代理 / 目标 / 任务）
 *   的**具体字段名**尚未取得实测证据（见 `docs/11-请求载荷契约.md` 与 D4 POC-1）。
 *   在拿到证据前，本函数只做两件**可确定**的事：
 *     1. 按事件名的**命名空间前缀**（`family/name` 是上游的稳定结构约定）归类；
 *     2. 把整段 `data` 作为原始 JSON 放进条目正文，并标记为「待解析」。
 *   这样做不会在真机上显示错误内容，也不会静默丢事件；
 *   而且 `SessionHub.noteUnknown()` 会把未识别类型汇总出来，
 *   真机跑一次即可得到权威清单，随后按清单补 `data` 字段映射即可——改动只在本函数内。
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

  // 审计类事件不进轨迹：它们没有用户可读内容，放进去只会淹没对话
  if (isAuditEventType(eventType)) {
    return undefined;
  }

  const kind: TrajectoryKind = kindOfFamily(classifyEventType(eventType));
  const item: TrajectoryItem = makeItem(`ev-${seq}`, kind, time);
  item.body = data === undefined ? '' : JSON.stringify(data);
  item.speaker = isUserAuthoredEvent(eventType) ? Speaker.USER : Speaker.ASSISTANT;
  // 工具类事件在数据尚未解析时不显示状态徽标，避免把未知误显示成「运行中」
  item.toolState = ToolState.PENDING;
  if (kind === TrajectoryKind.ERROR) {
    item.expanded = true;
  }
  return item;
}

/** 上游呈现家族（`dshcompat.EventFamily`）→ 本层轨迹枚举 */
function kindOfFamily(family: EventFamily): TrajectoryKind {
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
  if (code === 'gateway/arguments-invalid' || code === 'gateway/input-invalid') {
    return `调用参数与 Host 的契约不符（${message}）。这是客户端兼容面的问题，请提交诊断报告以便修正上表。`;
  }
  return `${code} ${message}`;
}
