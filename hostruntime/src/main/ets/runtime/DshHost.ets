/**
 * 端侧核心的生命周期（DshHost）—— 把「核心版本仓库」与「运行时载体」合成一个可查询的状态。
 *
 * 它对外只给两样东西：
 *   - `status()`：现在处于什么状态、为什么、下一步是什么（**不含任何猜测值**）
 *   - `start()/stop()`：起停核心，失败时返回可读原因而不是抛异常给 UI
 *
 * 状态机的设计要点（对应核心页的阶段徽标）：
 *   未接线 (UNWIRED)  运行时载体还没接上 —— 这是当前的真实状态，不是错误
 *   未安装 (EMPTY)    载体有了，但一个核心版本都没装
 *   待启动 (IDLE)     已安装、未运行
 *   就绪   (READY)    已启动且健康检查通过
 *   解包中 / 启动中    瞬态，由操作设置
 *   降级 / 失败        由运行结果设置
 *
 * 分层：本层不依赖 appstate / UI；核心页的阶段由 appstate 的
 * `corePhaseOfHostState()` 映射（纯函数，可单测）。
 */
import { ActivationDecision, ActivationAction, CoreState, CoreVersionRecord } from '../core/Types';
import { CoreStore, OpResult } from '../core/CoreStore';
import { HostHandle, RuntimePort, RuntimeProbe, RuntimeKind } from '../runtime/RuntimePort';

/** 端侧 Host 的状态。字符串值与 appstate 的 CorePhase 一一对应（映射见 appstate）。 */
export enum HostState {
  UNWIRED = 'unwired',
  EMPTY = 'empty',
  EXTRACTING = 'extracting',
  IDLE = 'idle',
  STARTING = 'starting',
  READY = 'ready',
  DEGRADED = 'degraded',
  FAILED = 'failed',
}

/** 状态快照。全部字段都是"事实或空值"，没有默认假值。 */
export interface HostStatus {
  state: HostState;
  /** 一句话原因/结论（用于核心页标题下方） */
  note: string;
  installed: string[];
  currentVersion: string;
  previousVersion: string;
  profile: string;
  probe: RuntimeProbe;
  /** 已启动时的句柄；未启动为空 */
  handle: HostHandle | null;
}

/** 瞬态状态（正在解包 / 正在启动）：核心页据此显示"进行中"并禁用会冲突的动作。 */
export function hostStateIsTransient(state: HostState): boolean {
  return state === HostState.EXTRACTING || state === HostState.STARTING;
}

export interface HostStartResult {
  ok: boolean;
  note: string;
  handle: HostHandle | null;
}

export class DshHost {
  /** 端侧使用的 profile 名（与 hostcore/profile/<name> 一致） */
  static readonly PROFILE: string = 'ondevice';

  private readonly store: CoreStore;
  private readonly port: RuntimePort;
  private handle: HostHandle | null = null;
  private transient: HostState | null = null;
  private lastFailureNote: string = '';

  constructor(filesDir: string, port: RuntimePort) {
    this.store = new CoreStore(filesDir);
    this.port = port;
  }

  store_(): CoreStore {
    return this.store;
  }

  runtimeLabel(): string {
    return this.port.label();
  }

  /** 查状态。**先探测运行时**——没接线就如实说未接线，不看仓库里有没有版本。 */
  async status(): Promise<HostStatus> {
    const probe: RuntimeProbe = await this.port.probe();
    const state: CoreState = this.store.readState();
    const installed: string[] = this.store.listInstalled();

    let phase: HostState;
    let note: string;

    if (this.transient !== null) {
      phase = this.transient;
      note = this.lastFailureNote.length > 0 ? this.lastFailureNote : '正在进行中';
    } else if (!probe.available) {
      phase = HostState.UNWIRED;
      note = probe.note.length > 0 ? probe.note : `运行时载体（${this.port.label()}）尚未接线`;
    } else if (installed.length === 0) {
      phase = HostState.EMPTY;
      note = '运行时已就绪，但还没有安装任何核心版本';
    } else if (this.handle !== null) {
      phase = HostState.READY;
      note = `核心已在运行（${this.port.label()}）`;
    } else if (this.lastFailureNote.length > 0) {
      phase = HostState.FAILED;
      note = this.lastFailureNote;
    } else {
      phase = HostState.IDLE;
      note = '核心已安装但未启动';
    }

    return {
      state: phase,
      note: note,
      installed: installed,
      currentVersion: state.current,
      previousVersion: state.previous,
      profile: DshHost.PROFILE,
      probe: probe,
      handle: this.handle,
    };
  }

  /**
   * 启动核心。
   * 目标版本的选取顺序：当前版本（若已安装）→ 第一个已安装版本。
   * **不做健康检查的臆测**：健康检查属于"起完之后能不能用"，由上层在拿到句柄后做。
   */
  async start(): Promise<HostStartResult> {
    const probe: RuntimeProbe = await this.port.probe();
    if (!probe.available) {
      const note: string = probe.note.length > 0 ? probe.note : '运行时载体尚未接线，无法启动核心';
      this.lastFailureNote = note;
      return { ok: false, note: note, handle: null };
    }
    const layout: OpResult = this.store.ensureLayout();
    if (!layout.ok) {
      this.lastFailureNote = layout.message;
      return { ok: false, note: layout.message, handle: null };
    }
    const installed: string[] = this.store.listInstalled();
    if (installed.length === 0) {
      const note: string = '还没有安装任何核心版本，无法启动';
      this.lastFailureNote = note;
      return { ok: false, note: note, handle: null };
    }
    const state: CoreState = this.store.readState();
    let target: string = state.current.length > 0 && installed.includes(state.current)
      ? state.current
      : installed[0];

    this.transient = HostState.STARTING;
    this.lastFailureNote = '';
    try {
      const handle: HostHandle = await this.port.start(
        this.store.coreDir(target), this.store.homeDir(), DshHost.PROFILE);
      this.handle = handle;
      this.transient = null;
      return { ok: true, note: `核心 ${target} 已启动`, handle: handle };
    } catch (e) {
      const err = e as Error;
      const note: string = `启动失败：${err.message}`;
      this.handle = null;
      this.transient = null;
      this.lastFailureNote = note;
      return { ok: false, note: note, handle: null };
    }
  }

  /** 停止核心（幂等）。 */
  async stop(): Promise<OpResult> {
    try {
      await this.port.stop();
      this.handle = null;
      this.transient = null;
      this.lastFailureNote = '';
      return { ok: true, message: '核心已停止' };
    } catch (e) {
      const err = e as Error;
      return { ok: false, message: `停止失败：${err.message}` };
    }
  }

  /** 已安装版本的展示记录（转发仓库；核心页的"核心版本"分区用它）。 */
  records(): CoreVersionRecord[] {
    return this.store.installedRecords();
  }
}
