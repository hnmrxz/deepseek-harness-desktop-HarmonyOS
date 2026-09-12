/**
 * 运行时载体接口（RuntimePort）—— 端侧核心"跑在什么上面"的抽象（D6 §4）。
 *
 * 为什么要有这一层：D6 把运行时分成两阶段——
 *   阶段一（开发期验证通道）：复用 Electron-on-鸿蒙 运行时，只当 Node 用
 *   阶段二（上架形态）：自建 `libnode.so` + NAPI 引导，可 jitless
 * 上层（DshHost / 核心页）**只认本文件**，换载体不动上层。这也是 D6 §4.0 的硬要求：
 * "阶段一的产物不能泄漏到状态层与 UI 层"。
 *
 * 纪律：
 *  1. `probe()` 必须如实报告"没探测到"，不允许用默认值伪装成已探测（`unknownFact` 同源纪律）；
 *  2. `available === false` 时**必须**给出 `note` 说明原因与下一步；
 *  3. 本层不依赖 appstate / UI（分层规则 D1 §10.1；D6 §2）。
 */

/** 运行时载体种类。 */
export enum RuntimeKind {
  /** 还没接任何载体 */
  NONE = 'none',
  /** 阶段一：Electron-on-鸿蒙 运行时（只当 Node 用） */
  ELECTRON_OHOS = 'electron-ohos',
  /** 阶段二：自建 libnode.so + NAPI 引导（上架形态，可 jitless） */
  LIBNODE = 'libnode',
}

/** 一个原生模块的加载事实。 */
export interface NativeFact {
  name: string;
  loaded: boolean;
  note: string;
}

/** 运行时探测结果。字段为空串/undefined 一律表示"未探测"，不要填猜测值。 */
export interface RuntimeProbe {
  kind: RuntimeKind;
  /** 载体是否**已被接线并可尝试启动** */
  available: boolean;
  /** 未接线时的原因与下一步 */
  note: string;
  /** Node 版本（要求 >= 22.17.0）；空串 = 未探测 */
  nodeVersion: string;
  /** process.platform（鸿蒙上应为 openharmony）；空串 = 未探测 */
  platform: string;
  /** node:zlib 的 zstd 能力（会话持久化依赖）；null = 未探测 */
  zstd: boolean | null;
  /** 是否以 jitless 运行（本项目各端统一 jitless，不申请特殊权限）；null = 未探测 */
  jitless: boolean | null;
  /** 三个硬原生依赖的加载事实 */
  natives: NativeFact[];
  /** 实际监听地址（应只有 127.0.0.1）；空串 = 未启动 */
  listenAddress: string;
}

/** 起核心后拿到的句柄。 */
export interface HostHandle {
  port: number;
  /** 客户端可直接用的基址（含 token 时也在这里，交给调用方决定怎么用） */
  url: string;
}

/** 运行时载体接口。 */
export interface RuntimePort {
  kind(): RuntimeKind;

  /** 人类可读的载体名（用于诊断页与核心页） */
  label(): string;

  /** 探测（不启动）。允许开销小；未接线的实现应立刻返回 available=false。 */
  probe(): Promise<RuntimeProbe>;

  /** 启动 Host。coreDir 是某一版核心的根（内含 node_modules 与 profiles/）。 */
  start(coreDir: string, homeDir: string, profile: string): Promise<HostHandle>;

  /** 停止 Host。未启动时应是幂等的 no-op。 */
  stop(): Promise<void>;
}

/** 未接线载体的探测结果：**如实**说明"还没接"，并给出下一步。 */
export function notWiredProbe(note: string): RuntimeProbe {
  return {
    kind: RuntimeKind.NONE,
    available: false,
    note: note,
    nodeVersion: '',
    platform: '',
    zstd: null,
    jitless: null,
    natives: [],
    listenAddress: '',
  };
}

// ── Host 启动契约：argv 与 env ──────────────────────────────────────────────
//
// 【为什么要在这里、以纯函数的形式定下来】端侧 Host 的配置通道**是环境变量而不是 argv**：
// `hostcore/app/main.js` 读 HDSH_CORE_DIR / HDSH_HOME / HDSH_SANDBOX_HOME / HDSH_PORT /
// HDSH_PROFILE，而 ArkTS 侧**没有任何办法设置原生进程的环境变量**——只能由引导层
// （`hostruntime/src/main/cpp/dshhost.cc` 的 startHost）在 node::Start 之前 setenv()。
// 于是"该传哪些键、argv 该带什么"就成了两端之间最容易写错、且写错了**不会报错**的接口：
// 键名拼错 → Host 用上默认目录，表面上起来了、实际指向错的 $DSH_HOME。
// 所以这两条契约必须是可单测的纯函数，而不是散在实现里的字符串拼接。

/** 端侧 Host 的回环端口。与 main.js 的 HDSH_PORT 默认值一致，但**显式传**，不依赖默认值。 */
export const HOST_DEFAULT_PORT: number = 3120;

/**
 * `startHost()` 的 argv（**不含 argv[0]**；引导层会补一个 "node"）。
 *
 * `entryScript` 是 Host 入口脚本（main.js）的绝对路径。它**不属于任何一版核心树**：
 * 核心树是可切换/回滚的，而入口脚本随应用发版，两者生命周期不同，混在一起会导致
 * "回滚核心版本把入口脚本也换掉了"。
 */
export function buildHostArgv(entryScript: string): string[] {
  return [
    // **必须**：这是"不申请 ALLOW_WRITABLE_CODE_MEMORY"能成立的前提。
    // 少了它，V8 会在初始化时申请可写可执行内存而被系统拦（D6 §4.4）。
    // 它必须排在脚本路径**之前**：Node 把第一个非选项参数当脚本。
    '--jitless',
    entryScript,
  ];
}

/**
 * `startHost()` 的环境变量，每项是 `KEY=VALUE`。
 *
 * 用"KEY=VALUE"字符串而不是两个平行数组：两端都不必维护下标对应关系，
 * 少一类"键值错位"的错法。
 */
export function buildHostEnv(coreDir: string, homeDir: string, sandboxHome: string,
  port: number, profile: string): string[] {
  return [
    `HDSH_CORE_DIR=${coreDir}`,
    `HDSH_HOME=${homeDir}`,
    `HDSH_SANDBOX_HOME=${sandboxHome}`,
    `HDSH_PORT=${port}`,
    `HDSH_PROFILE=${profile}`,
  ];
}

/**
 * 一条 `KEY=VALUE` 是否合法：必须有 `=`，且键非空。
 *
 * 【为什么要有这个判据】引导层据此决定"跳过并计数"。**不允许静默忽略**：
 * 被忽略的 HDSH_HOME 会让 Host 悄悄用上默认目录，看上去一切正常却写错了地方。
 * 规则只有这一份，C++ 侧（dshhost.cc 的 startHost）按同一规则处理并把条数回报给上层。
 */
export function isWellFormedEnvPair(pair: string): boolean {
  const eq: number = pair.indexOf('=');
  return eq > 0;
}

/**
 * 未接线载体的实现。
 *
 * 它存在的意义不是"占位"，而是让**当前真实状态**（运行时还没接上）在类型系统里成立，
 * 从而核心页与诊断页可以照常渲染"未接线 + 原因 + 下一步"，而不是靠 if 判空。
 */
export class NotWiredRuntime implements RuntimePort {
  private readonly note: string;

  constructor(note: string) {
    this.note = note;
  }

  kind(): RuntimeKind {
    return RuntimeKind.NONE;
  }

  label(): string {
    return '未接线';
  }

  async probe(): Promise<RuntimeProbe> {
    return notWiredProbe(this.note);
  }

  async start(coreDir: string, homeDir: string, profile: string): Promise<HostHandle> {
    throw new Error(`运行时载体尚未接线，无法启动核心（${coreDir} / ${profile}）`);
  }

  async stop(): Promise<void> {
    // 未启动 ⇒ 停止是 no-op，且**不报错**（幂等）
  }
}
