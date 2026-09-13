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
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ActivationDecision, ActivationAction, CoreState, CoreVersionRecord } from '../core/Types';
import { CoreStore, CorePluginRow, CorePluginTotals, CoreTreeInfo, OpResult } from '../core/CoreStore';
import { BundledInstallResult, installBundledCores } from '../core/BundledCore';
import { UserPluginRow, clearUserRows, readUserRows, writeUserRows } from '../core/PluginRows';
import { HostHandle, NativeFact, RuntimePort, RuntimeProbe, RuntimeKind } from '../runtime/RuntimePort';

const DOMAIN: number = 0x0000;
const TAG: string = 'HDSH-DshHost';

/**
 * 入口脚本写进 `host-ready.json` 的**实测运行时事实**（E88）。
 *
 * 【为什么由宿主自己报】Node 版本、`process.platform/arch`、是否真的 jitless、
 * `node:zlib` 有没有 zstd、三个硬原生依赖能不能加载——这些只有宿主进程内部知道，
 * 而 ArkTS 侧的原生模块只暴露 `runtimeVersion/startHost/isHostRunning/stopHost`。
 * 于是核心页上那几项长期写着「未探测」：**那是对的**（不猜），但现在有了一份实测来源。
 */
interface HostReadyNative {
  name: string;
  ok: boolean;
  note: string;
}

interface HostReadyRuntime {
  nodeVersion: string;
  platform: string;
  jitless: boolean;
  zstd: boolean;
  listenAddress: string;
  natives: HostReadyNative[];
}

interface HostReadyFile {
  runtime?: HostReadyRuntime;
}

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

/**
 * 插件清单的报告（核心页的插件分区用）。
 *
 * 【为什么带 version 和 note】清单是**某个已安装版本**的属性，不是全局事实。
 * 只给一个数组会让界面无法回答"这是哪一版的插件"。而 note 用来区分两件不同的事：
 * "这个核心包里没有清单"（早于清单内嵌的旧包）与"清单里插件为零"。
 */
export interface HostPluginReport {
  /** 清单来自哪个已安装版本；空串表示没有可用清单 */
  version: string;
  rows: CorePluginRow[];
  totals: CorePluginTotals;
  nativePackages: string[];
  /** 清单为空时说明原因；非空时为空串 */
  note: string;
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
  /** 插件清单（来自树内元数据，打包时算好；端侧不重新遍历目录） */
  plugins: HostPluginReport;
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
    const probed: RuntimeProbe = await this.port.probe();
    // E88：宿主在跑时，用他自己写下的实测事实补齐 probe 里"只有宿主知道"的几项
    const probe: RuntimeProbe = this.mergeRuntimeFacts(probed);
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
    } else if (this.handle !== null || this.port.isRunning()) {
      // 【为什么必须带上 `port.isRunning()`】`handle` 是**本实例**的记忆，而 Host 是
      // 进程级事实：页面每次刷新都会 new 一个 DshHost，用 handle 判断就会在
      // "端口已经在监听"的情况下报"未启动"（端侧实测症状：端口通了，页面说没有启动核心）。
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
      plugins: this.plugins(),
    };
  }

  /**
   * 把入口脚本落盘的**实测事实**并进 probe（E88）。规则：**已有的读数优先**。
   *
   * 【为什么必须判 isRunning 才读文件】`host-ready.json` 是**上一次启动**留下的文件：
   * 宿主没在跑时读它，等于把上一版核心的事实当成现在的事实——那正是本项目一直在拆的
   * "看似有值、其实错位"的坑。所以：没在跑就原样返回 probe（那几项如实保持"未探测"）。
   *
   * 【为什么原生件读数也带进来】koffi / sharp / node-pty 能不能加载，是"端侧核心能不能
   * 真正干活"的硬前提（图片附件、进程类工具都系在这上面）。把它显示出来，
   * 比留一句"未探测"有用得多，也让"端侧能力边界"这件事在界面上可见。
   */
  private mergeRuntimeFacts(probe: RuntimeProbe): RuntimeProbe {
    if (!this.port.isRunning()) {
      return probe;
    }
    const raw: HostReadyRuntime | undefined = this.readHostReadyRuntime();
    if (raw === undefined) {
      return probe;
    }
    const natives: NativeFact[] = [];
    for (const n of raw.natives) {
      natives.push({ name: n.name, loaded: n.ok, note: n.note });
    }
    return {
      kind: probe.kind,
      available: probe.available,
      note: probe.note,
      // Node 版本以原生模块的读数为准：那是"被链接进来的运行时"本身，
      // 而文件里的 process.version 是同一个进程的自述，两者一致时无差别，冲突时前者更硬。
      nodeVersion: probe.nodeVersion.length > 0 ? probe.nodeVersion : raw.nodeVersion,
      platform: probe.platform.length > 0 ? probe.platform : raw.platform,
      zstd: probe.zstd === null ? raw.zstd : probe.zstd,
      jitless: probe.jitless === null ? raw.jitless : probe.jitless,
      natives: probe.natives.length > 0 ? probe.natives : natives,
      listenAddress: probe.listenAddress.length > 0 ? probe.listenAddress : raw.listenAddress,
    };
  }

  /** 读 `<home>/host-ready.json` 里的 runtime 段；任何异常都返回 undefined（不猜）。 */
  private readHostReadyRuntime(): HostReadyRuntime | undefined {
    try {
      const p: string = `${this.store.homeDir()}/host-ready.json`;
      if (!fs.accessSync(p)) {
        return undefined;
      }
      const parsed = JSON.parse(fs.readTextSync(p)) as HostReadyFile;
      if (parsed === null || parsed === undefined || parsed.runtime === undefined) {
        return undefined;
      }
      return parsed.runtime;
    } catch (e) {
      return undefined;
    }
  }

  /** profile 目录（用户行的落点；dsh 读取的用户 patch 层也在这一层）。 */
  private profileDir(): string {
    return `${this.store.homeDir()}/profiles/${DshHost.PROFILE}`;
  }

  /**
   * 已保存的**用户启停**（端侧「插件」页写的那份覆盖）。
   *
   * 【为什么不能让调用方自己拼路径】用户行文件与 dsh 的 profile 分层是同一份契约
   * （`<profile 目录>/cordis.patch.yml` 的追加段），路径知识只应存在于 hostruntime。
   */
  userPluginRows(): UserPluginRow[] {
    return readUserRows(this.profileDir());
  }

  /**
   * 设置某一行的启停（写用户行文件）。
   *
   * 【为什么返回的话里必须带"重启生效"】dsh 的插件树在**启动时**挂载：文件改了但进程没重启，
   * 界面上的状态与运行中的事实会不一致。与其含糊其辞，不如把这件事写在结果里，
   * 由界面直接显示。
   */
  setPluginDisabled(id: string, disabled: boolean): OpResult {
    if (id.length === 0) {
      return { ok: false, message: '行 id 为空，无法设置' };
    }
    const rows: UserPluginRow[] = readUserRows(this.profileDir());
    const next: UserPluginRow[] = [];
    let found: boolean = false;
    for (const row of rows) {
      if (row.id === id) {
        next.push({ id: row.id, disabled: disabled });
        found = true;
      } else {
        next.push(row);
      }
    }
    if (!found) {
      next.push({ id: id, disabled: disabled });
    }
    const written: OpResult = writeUserRows(this.profileDir(), next);
    if (!written.ok) {
      return written;
    }
    return { ok: true, message: `${id} 已${disabled ? '禁用' : '启用'}；重启核心后生效` };
  }

  /** 恢复默认：清空用户启停（核心种子里的启停不受影响）。 */
  resetPluginRows(): OpResult {
    return clearUserRows(this.profileDir());
  }

  /**
   * 插件清单：取自**会被启动的那个版本**的树内元数据（选取规则与 start() 一致）。
   * 【为什么不聚合所有版本】清单回答的是"这一版装了什么"。把两个版本的插件混成一个列表，
   * 用户会以为设备上装着这一份合集——那是编造。
   * 【为什么端侧不自己扫】判据要沿依赖闭包走 518 个包 / 27000 余文件（实测规模）；
   * 而答案在打包那一刻就确定了，所以打包器算好写进树里，端侧只读一个小 JSON。
   */
  plugins(): HostPluginReport {
    const zero: CorePluginTotals = { pluginRows: 0, pureJs: 0, native: 0, unknown: 0, disabled: 0 };
    const installed: string[] = this.store.listInstalled();
    if (installed.length === 0) {
      return {
        version: '', rows: [], totals: zero, nativePackages: [],
        note: '还没有安装核心版本，因此没有插件清单',
      };
    }
    const state: CoreState = this.store.readState();
    const target: string = state.current.length > 0 && installed.includes(state.current)
      ? state.current
      : installed[0];
    const info: CoreTreeInfo = this.store.readTreeInfo(target);
    if (info.plugins.length === 0) {
      return {
        version: target, rows: [], totals: info.pluginTotals, nativePackages: info.nativePackages,
        note: `核心 ${target} 的树内元数据不含插件清单（该包早于"清单随包内嵌"这一改动）；`
          + '重新安装一份较新的核心包即可显示。',
      };
    }
    /*
     * 把**用户启停**覆盖到清单上（E91）。
     *
     * 【为什么必须叠加】清单来自核心包（树内元数据），它只会说"这一版出厂时这一行是开还是关"；
     * 而用户刚在「插件」页改过的那一行，要**重启核心**才真正生效。如果不叠加，界面会显示
     * 出厂状态，用户会以为自己的改动没保存——那是界面在说谎。叠加之后，界面显示的是
     * "重启后会生效的状态"，与提示语（"重启核心后生效"）自洽。
     */
    const rows: CorePluginRow[] = info.plugins;
    const userRows: UserPluginRow[] = readUserRows(this.profileDir());
    if (userRows.length > 0) {
      const byId: Map<string, boolean> = new Map<string, boolean>();
      for (const userRow of userRows) {
        byId.set(userRow.id, userRow.disabled);
      }
      for (const row of rows) {
        const want: boolean | undefined = byId.get(row.id);
        if (want !== undefined) {
          row.disabled = want;
        }
      }
    }
    return {
      version: target,
      rows: rows,
      totals: info.pluginTotals,
      nativePackages: info.nativePackages,
      note: '',
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
    /*
     * 协作式停止（E90）：先把"停止请求"落到 `$DSH_HOME`，再等运行时真的退出。
     *
     * 【为什么由这里写文件】`$DSH_HOME` 的布局是 CoreStore 的知识（`homeDir()`），
     * 机制层（NodeRuntime）不该重复这份知识；它只负责"等原生层确认 Node 结束了"。
     * 【失败时必须把文件清掉】留着请求文件会让**下一次启动**的宿主刚起来就自杀——
     * 那会变成一个"应用再也起不来、且没有任何报错"的故障，比停止失败本身糟得多。
     */
    const requestPath: string = `${this.store.homeDir()}/host-stop-request`;
    let wrote: boolean = false;
    try {
      const f: fs.File = fs.openSync(requestPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(f.fd, `${Date.now()}\n`);
      } finally {
        fs.closeSync(f);
      }
      wrote = true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, '写停止请求失败（将继续尝试等待）：%{public}s', err.message);
    }
    try {
      await this.port.stop();
      this.handle = null;
      this.transient = null;
      this.lastFailureNote = '';
      return { ok: true, message: '核心已停止' };
    } catch (e) {
      const err = e as Error;
      if (wrote) {
        try {
          if (fs.accessSync(requestPath)) {
            fs.unlinkSync(requestPath);
          }
        } catch (e2) {
          // 清不掉也要留下痕迹：下一次启动前 `recoverOrphanLocks` 那类巡检可以考虑它
          hilog.warn(DOMAIN, TAG, '清理停止请求失败，请留意下次启动行为');
        }
      }
      this.lastFailureNote = `停止失败：${err.message}`;
      return { ok: false, message: this.lastFailureNote };
    }
  }

  /** 已安装版本的展示记录（转发仓库；核心页的"核心版本"分区用它）。 */
  records(): CoreVersionRecord[] {
    return this.store.installedRecords();
  }

  /**
   * 安装**随应用内置**的核心包（首启解包；幂等）。
   *
   * 与 start() 的关键区别：这一步**不需要运行时载体**——它只是把 zip 解包落位。
   * 因此运行时还没接线时也应当允许用户先装好（核心页据此把"安装内置核心"设为可用）。
   */
  async installBundled(resourceDir: string, workDir: string): Promise<BundledInstallResult> {
    this.transient = HostState.EXTRACTING;
    this.lastFailureNote = '';
    try {
      const result: BundledInstallResult = await installBundledCores(resourceDir, workDir, this.store);
      if (result.failed.length > 0) {
        this.lastFailureNote = result.note;
      }
      return result;
    } catch (e) {
      const err = e as Error;
      const note: string = `安装内置核心失败：${err.message}`;
      this.lastFailureNote = note;
      return { installed: [], skipped: [], failed: [note], note: note };
    } finally {
      this.transient = null;
    }
  }
}
