/**
 * 端侧核心的**呈现契约**（D6 §2/§6；体验规范沿用 D3 §4 的「失败必须给下一步」纪律）。
 *
 * 分层规则（D1 §10.1）：视图只认本文件的类型与纯函数；版本仓库/解包/激活事务在 hostruntime；
 * 上游协议事实仍只允许出现在 dshcompat。
 *
 * 这里全部是**纯函数**，因此"某个阶段该显示什么、某个动作能不能点、不能点时说什么"
 * 可以在没有设备、没有核心的情况下被单测钉死——这是本页最容易"说谎"的地方。
 */

/** 核心阶段。注意 UNWIRED 是一等状态：运行时还没接线时必须如实说，而不是假装在初始化。 */
export enum CorePhase {
  /** 运行时载体尚未接线（当前阶段一的真实状态） */
  UNWIRED = 'unwired',
  /** 已接线但一个核心版本都没装 */
  EMPTY = 'empty',
  /** 正在解包核心 */
  EXTRACTING = 'extracting',
  /** 正在启动 Host */
  STARTING = 'starting',
  /** 健康检查通过、可服务 */
  READY = 'ready',
  /** 能跑但能力不全（例如某个原生件没加载） */
  DEGRADED = 'degraded',
  /** 起不来 */
  FAILED = 'failed',
}

export function corePhaseLabel(phase: CorePhase): string {
  if (phase === CorePhase.UNWIRED) {
    return '运行时未接线';
  }
  if (phase === CorePhase.EMPTY) {
    return '尚未安装核心';
  }
  if (phase === CorePhase.EXTRACTING) {
    return '正在解包';
  }
  if (phase === CorePhase.STARTING) {
    return '正在启动';
  }
  if (phase === CorePhase.READY) {
    return '就绪';
  }
  if (phase === CorePhase.DEGRADED) {
    return '降级可用';
  }
  return '启动失败';
}

/** 版本行。 */
export interface CoreVersionRow {
  version: string;
  /** 徽标文案：当前 / 上一版 / 已安装 */
  badge: string;
  /** 该行是否可被选为切换目标 */
  selectable: boolean;
  /** 不可选时的原因（禁止静默禁用） */
  reason: string;
}

/** 运行时事实一行。 */
export interface CoreFact {
  label: string;
  value: string;
  /** 'ok' | 'warn' | 'unknown' */
  verdict: string;
  hint: string;
}

export function fact(label: string, value: string, verdict: string, hint: string): CoreFact {
  return { label: label, value: value, verdict: verdict, hint: hint };
}

/** 未探测事实的标准写法：值说明"没测"，并给出下一步——不要写"未知"就算完。 */
export function unknownFact(label: string, howToProbe: string): CoreFact {
  return { label: label, value: '未探测', verdict: 'unknown', hint: howToProbe };
}

/** 可执行动作。 */
export interface CoreActionSpec {
  id: string;
  label: string;
  enabled: boolean;
  /** 不可用时的原因，会直接显示给用户 */
  reason: string;
}

/** 插件分类（决定"能不能运行时安装"）。 */
export interface PluginRow {
  name: string;
  version: string;
  /** 纯 JS 插件可在运行时安装/停用；含原生 .node 的必须随应用发版（D6 §6.2） */
  hasNative: boolean;
  installable: boolean;
  reason: string;
}

export interface CoreViewState {
  phase: CorePhase;
  /** 阶段徽标文案 */
  badge: string;
  /** 一句话结论 */
  title: string;
  /** 补充说明（建议/下一步） */
  detail: string;
  busy: boolean;
  currentVersion: string;
  previousVersion: string;
  profileName: string;
  versions: CoreVersionRow[];
  facts: CoreFact[];
  actions: CoreActionSpec[];
  plugins: PluginRow[];
}

export interface CoreViewInput {
  phase: CorePhase;
  title: string;
  detail: string;
  busy: boolean;
  installed: string[];
  currentVersion: string;
  previousVersion: string;
  profileName: string;
  facts: CoreFact[];
  plugins: PluginRow[];
}

/**
 * 由事实构造视图模型。
 *
 * 关键判据（都是纯函数，可单测）：
 *  - 只有 READY / DEGRADED 才允许"停止/重启"；
 *  - 只有存在 previous 且 previous 仍是已安装版本时才允许"回滚"；
 *  - UNWIRED 阶段**所有**运行类动作都不可用，且给出的是"运行时未接线"而不是"请稍后"；
 *  - 版本行只在"不是当前版本"时可选。
 */
export function buildCoreView(input: CoreViewInput): CoreViewState {
  const phase: CorePhase = input.phase;
  const running: boolean = phase === CorePhase.READY || phase === CorePhase.DEGRADED;
  const hasPrevious: boolean = input.previousVersion.length > 0
    && input.installed.includes(input.previousVersion)
    && input.previousVersion !== input.currentVersion;

  const actions: CoreActionSpec[] = [];

  if (phase === CorePhase.UNWIRED) {
    actions.push({ id: 'start', label: '启动核心', enabled: false, reason: '运行时载体尚未接线，无法启动（见核心页的运行时事实）' });
  } else if (running) {
    actions.push({ id: 'restart', label: '重启核心', enabled: true, reason: '' });
    actions.push({ id: 'stop', label: '停止核心', enabled: true, reason: '' });
  } else if (input.busy) {
    actions.push({ id: 'start', label: '启动核心', enabled: false, reason: '正在进行中' });
  } else if (input.installed.length === 0) {
    actions.push({ id: 'start', label: '启动核心', enabled: false, reason: '还没有安装任何核心版本' });
  } else {
    actions.push({ id: 'start', label: '启动核心', enabled: true, reason: '' });
  }

  actions.push({
    id: 'rollback',
    label: '回滚到上一版',
    enabled: hasPrevious && !input.busy,
    reason: hasPrevious ? '' : '没有可回滚的上一版本',
  });
  actions.push({ id: 'import', label: '导入核心包', enabled: !input.busy, reason: input.busy ? '正在进行中' : '' });
  actions.push({ id: 'diagnose', label: '导出诊断', enabled: true, reason: '' });

  const versions: CoreVersionRow[] = [];
  for (const v of input.installed) {
    const isCurrent: boolean = v === input.currentVersion;
    const isPrevious: boolean = v === input.previousVersion;
    versions.push({
      version: v,
      badge: isCurrent ? '当前' : (isPrevious ? '上一版' : '已安装'),
      selectable: !isCurrent && !input.busy,
      reason: isCurrent ? '已经是当前版本' : (input.busy ? '正在进行中' : ''),
    });
  }

  return {
    phase: phase,
    badge: corePhaseLabel(phase),
    title: input.title,
    detail: input.detail,
    busy: input.busy,
    currentVersion: input.currentVersion,
    previousVersion: input.previousVersion,
    profileName: input.profileName,
    versions: versions,
    facts: input.facts,
    actions: actions,
    plugins: input.plugins,
  };
}

/** 插件分类：只有"不含原生 .node"的插件才允许运行时安装（D6 §6.2 的硬约束）。 */
export function classifyPlugin(name: string, version: string, hasNative: boolean): PluginRow {
  if (hasNative) {
    return {
      name: name,
      version: version,
      hasNative: true,
      installable: false,
      reason: '含原生模块（.node）。鸿蒙只允许加载随 HAP 打包且已签名的原生库，无法在运行时安装——需随应用发版提供。',
    };
  }
  return { name: name, version: version, hasNative: false, installable: true, reason: '' };
}

/** 初始（未接线）视图：用于运行时还没接上时的如实呈现。 */
export function emptyCoreView(): CoreViewState {
  return buildCoreView({
    phase: CorePhase.UNWIRED,
    title: '端侧核心尚未接线',
    detail: '应用已具备核心管理的骨架（版本仓库、激活事务、端侧 profile），但运行时载体还没接上，因此现在还不能在设备上起 Host。',
    busy: false,
    installed: [],
    currentVersion: '',
    previousVersion: '',
    profileName: 'ondevice',
    facts: [
      unknownFact('Node 运行时', '接上运行时载体后，这里会显示实际版本（要求 ≥ 22.17.0）'),
      unknownFact('zlib zstd 能力', '会话持久化依赖 node:zlib 的 zstd，接线后自动探测'),
      unknownFact('JIT 状态', '本项目统一按 jitless 运行，不申请任何特殊权限'),
      unknownFact('原生件加载', 'koffi / node-pty / sharp 三个鸿蒙移植件的加载结果'),
      unknownFact('监听地址', '核心起来后应只监听 127.0.0.1'),
    ],
    plugins: [],
  });
}
