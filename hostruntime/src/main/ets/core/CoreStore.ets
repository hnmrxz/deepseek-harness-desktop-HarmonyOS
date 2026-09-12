/**
 * 端侧核心仓库（CoreStore）：把 tools/pack-core.mjs 产出的 zip 落成"可运行的某一版核心"，
 * 并维护"当前版本 / 上一版本"的状态与激活事务。
 *
 * 层级：`<filesDir>/dsh/`
 *   ├── cores/<version>/        已安装的核心树（内含 hdsh-core.json 元数据）
 *   ├── cores/<version>.staging/  正在解包/校验，**未激活**（放在 cores 下是为了同文件系统 rename）
 *   ├── home/                   $DSH_HOME：会话/设置/凭据/工作区注册（**跨版本共享，唯一一份**）
 *   └── state.json              { current, previous, history }
 *
 * 纪律：
 *  1. 所有失败都返回 OpResult/Decision，**不抛异常给上层**（上层要能如实展示失败原因）；
 *  2. 任何"写 current"的动作都必须先过 Types.decideActivation 的健康检查判据；
 *  3. 解包失败/校验失败一律清掉 staging，绝不留半成品被误认为已安装；
 *  4. 永远不删 current 与 previous 对应的目录（见 Types.evictionCandidates）。
 *
 * 设计依据：docs/50-端侧核心运行架构.md §6.1。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ActivationDecision, ActivationAction, CoreHealth, CoreState, CoreVersionRecord, decideActivation, decideRollback, emptyState, evictionCandidates, parseState, serializeState } from './Types';
import { TREE_INFO_FILE, isSafeVersion, topDirOf } from './Naming';

const TAG: string = 'HDSH-CoreStore';
const DOMAIN: number = 0x0000;

export interface OpResult {
  ok: boolean;
  message: string;
}

function ok(message: string): OpResult {
  return { ok: true, message: message };
}

function fail(message: string): OpResult {
  return { ok: false, message: message };
}

/** 树内元数据（打包器写入 <top>/hdsh-core.json）。字段全部按"可能缺失"处理。 */
export interface CoreTreeInfo {
  coreVersion: string;
  platform: string;
  profile: string;
  builtAt: string;
  /** 该版本要求的 Node 版本下限（来自配方）；空串表示未记录 */
  nodeFloor: string;
}

export class CoreStore {
  private readonly filesDir: string;

  constructor(filesDir: string) {
    this.filesDir = filesDir;
  }

  // ── 路径 ──────────────────────────────────────────────────────────────
  baseDir(): string {
    return `${this.filesDir}/dsh`;
  }

  coresDir(): string {
    return `${this.baseDir()}/cores`;
  }

  coreDir(version: string): string {
    return `${this.coresDir()}/${version}`;
  }

  stagingDir(version: string): string {
    return `${this.coresDir()}/${version}.staging`;
  }

  /** $DSH_HOME：**跨版本共享的唯一一份用户数据**。 */
  homeDir(): string {
    return `${this.baseDir()}/home`;
  }

  statePath(): string {
    return `${this.baseDir()}/state.json`;
  }

  treeInfoPath(version: string): string {
    return `${this.coreDir(version)}/${TREE_INFO_FILE}`;
  }

  // ── 布局 ──────────────────────────────────────────────────────────────
  ensureLayout(): OpResult {
    try {
      fs.mkdirSync(this.coresDir(), true);
      fs.mkdirSync(this.homeDir(), true);
      return ok(`布局就绪：${this.baseDir()}`);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      return fail(`建立端侧核心目录失败：${err.code} ${err.message}`);
    }
  }

  // ── 状态 ──────────────────────────────────────────────────────────────
  readState(): CoreState {
    try {
      if (!fs.accessSync(this.statePath())) {
        return emptyState();
      }
      return parseState(fs.readTextSync(this.statePath()));
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.warn(DOMAIN, TAG, '读 state.json 失败，按"从未激活"处理：%{public}s', `${err.code} ${err.message}`);
      return emptyState();
    }
  }

  private writeState(state: CoreState): OpResult {
    try {
      const file: fs.File = fs.openSync(this.statePath(), fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, serializeState(state));
      } finally {
        fs.closeSync(file);
      }
      return ok('state.json 已写入');
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      return fail(`写 state.json 失败：${err.code} ${err.message}`);
    }
  }

  // ── 已安装版本 ────────────────────────────────────────────────────────
  /** 列出已安装版本。`.staging` 与 `.tmp` 后缀的目录**不算**已安装。 */
  listInstalled(): string[] {
    const out: string[] = [];
    try {
      if (!fs.accessSync(this.coresDir())) {
        return out;
      }
      const names: string[] = fs.listFileSync(this.coresDir());
      for (const name of names) {
        if (name.endsWith('.staging') || name.endsWith('.tmp')) {
          continue;
        }
        if (!isSafeVersion(name)) {
          continue;
        }
        if (!fs.statSync(this.coreDir(name)).isDirectory()) {
          continue;
        }
        out.push(name);
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.warn(DOMAIN, TAG, '列已安装版本失败：%{public}s', `${err.code} ${err.message}`);
    }
    return out;
  }

  readTreeInfo(version: string): CoreTreeInfo {
    const empty: CoreTreeInfo = { coreVersion: version, platform: '', profile: '', builtAt: '', nodeFloor: '' };
    try {
      if (!fs.accessSync(this.treeInfoPath(version))) {
        return empty;
      }
      const raw: CoreTreeInfo = JSON.parse(fs.readTextSync(this.treeInfoPath(version))) as CoreTreeInfo;
      return {
        coreVersion: typeof raw.coreVersion === 'string' ? raw.coreVersion : version,
        platform: typeof raw.platform === 'string' ? raw.platform : '',
        profile: typeof raw.profile === 'string' ? raw.profile : '',
        builtAt: typeof raw.builtAt === 'string' ? raw.builtAt : '',
        nodeFloor: typeof raw.nodeFloor === 'string' ? raw.nodeFloor : '',
      };
    } catch (e) {
      return empty;
    }
  }

  /**
   * 已安装版本的展示记录。
   * 健康状态取自 state.json 的历史（当前版本视为 pass；其余按 unknown 处理——
   * **不编造**"曾经健康"这种无法验证的结论）。
   */
  installedRecords(): CoreVersionRecord[] {
    const state: CoreState = this.readState();
    const out: CoreVersionRecord[] = [];
    for (const v of this.listInstalled()) {
      const info: CoreTreeInfo = this.readTreeInfo(v);
      out.push({
        version: v,
        installedAt: info.builtAt,
        health: v === state.current ? CoreHealth.PASS : CoreHealth.UNKNOWN,
        healthNote: v === state.current ? '当前版本' : '',
        sha256: '',
      });
    }
    return out;
  }

  // ── 解包（stage）──────────────────────────────────────────────────────
  /**
   * 把容器解包并落成 `cores/<version>`。
   * 注意：本方法**只负责让它"存在且看起来完整"**，健康检查由调用方做，
   * 通过后才调用 activate()。这样"装上了"与"敢用它"是两件事。
   */
  async stageFromZip(zipPath: string, version: string): Promise<OpResult> {
    if (!isSafeVersion(version)) {
      return fail(`版本号不可用作目录名：${version}`);
    }
    const layout: OpResult = this.ensureLayout();
    if (!layout.ok) {
      return layout;
    }
    const staging: string = this.stagingDir(version);
    const target: string = this.coreDir(version);
    const inner: string = `${staging}/${topDirOf(version)}`;

    try {
      if (fs.accessSync(staging)) {
        fs.rmdirSync(staging);
      }
      fs.mkdirSync(staging, true);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      return fail(`准备 staging 目录失败：${err.code} ${err.message}`);
    }

    try {
      // 解压目标是**已存在的目录**（系统 API 要求），容器内的顶层目录会被创建在其下
      await zlib.decompressFile(zipPath, staging);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.dropStaging(staging);
      return fail(`解压失败：${err.code} ${err.message}`);
    }

    // 校验：顶层目录与元数据必须都在（否则这不是我们的容器，或解包不完整）
    try {
      if (!fs.accessSync(inner)) {
        this.dropStaging(staging);
        return fail(`容器内缺少顶层目录 ${topDirOf(version)}`);
      }
      if (!fs.accessSync(`${inner}/${TREE_INFO_FILE}`)) {
        this.dropStaging(staging);
        return fail(`容器内缺少元数据 ${TREE_INFO_FILE}`);
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.dropStaging(staging);
      return fail(`校验 staging 失败：${err.code} ${err.message}`);
    }

    // 落位：目标已存在时，只有"它不是当前运行版本"才允许替换
    const state: CoreState = this.readState();
    try {
      if (fs.accessSync(target)) {
        if (state.current === version) {
          this.dropStaging(staging);
          return fail(`版本 ${version} 正在使用中，拒绝覆盖（请先切到别的版本）`);
        }
        fs.rmdirSync(target);
      }
      fs.renameSync(inner, target);
      fs.rmdirSync(staging);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.dropStaging(staging);
      return fail(`落位到 ${target} 失败：${err.code} ${err.message}`);
    }
    return ok(`已落位 ${version}`);
  }

  private dropStaging(staging: string): void {
    try {
      if (fs.accessSync(staging)) {
        fs.rmdirSync(staging);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '清理 staging 失败（残留目录不会被当作已安装版本）');
    }
  }

  // ── 激活事务 ──────────────────────────────────────────────────────────
  /**
   * 激活：**只有健康检查为 PASS 才会写 current**（判据在 Types.decideActivation，可单测）。
   * 返回决策本身，调用方据此决定是否重启核心。
   */
  activate(candidate: string, health: string, note: string): ActivationDecision {
    const state: CoreState = this.readState();
    const decision: ActivationDecision = decideActivation(state, candidate, health, note);
    if (decision.action === ActivationAction.REFUSE) {
      hilog.warn(DOMAIN, TAG, '拒绝激活 %{public}s：%{public}s', candidate, decision.reason);
      return decision;
    }
    if (decision.next.current === state.current && decision.next.previous === state.previous) {
      return decision; // 幂等，不必写盘
    }
    const w: OpResult = this.writeState(decision.next);
    if (!w.ok) {
      return { action: ActivationAction.REFUSE, reason: `状态写入失败，保持原版本：${w.message}`, next: state };
    }
    return decision;
  }

  /** 回滚：当前版本启动失败时调用（判据在 Types.decideRollback，可单测）。 */
  rollback(): ActivationDecision {
    const state: CoreState = this.readState();
    const decision: ActivationDecision = decideRollback(state, this.listInstalled());
    if (decision.action === ActivationAction.REFUSE) {
      return decision;
    }
    const w: OpResult = this.writeState(decision.next);
    if (!w.ok) {
      return { action: ActivationAction.REFUSE, reason: `状态写入失败，保持原版本：${w.message}`, next: state };
    }
    return decision;
  }

  /** 清理旧版本；返回真正被删掉的版本号（current/previous 永不删）。 */
  evict(keep: number): string[] {
    const state: CoreState = this.readState();
    const removed: string[] = [];
    for (const v of evictionCandidates(state, this.listInstalled(), keep)) {
      try {
        fs.rmdirSync(this.coreDir(v));
        removed.push(v);
      } catch (e) {
        const err: BusinessError = e as BusinessError;
        hilog.warn(DOMAIN, TAG, '删除旧版本 %{public}s 失败：%{public}s', v, `${err.code} ${err.message}`);
      }
    }
    return removed;
  }
}
