/**
 * `platform` 模块的 **Node 垫片**：只提供 `check-core-loop.mjs` 需要的那几个符号。
 *
 * ## 为什么不直接把 `platform/` 也编译进来
 *
 * `platform` 是**平台能力层**：窗口、显示、路由、文件选择器、通知、输入设备……每一个都要
 * `@kit.*`。把整层搬进来意味着再写十几个垫片，而这些能力**与"核心使用闭环"无关** ——
 * 闭环只关心「连得上、建得了会话、发得出消息、收得到事件」。
 *
 * ## 因此这里有一条纪律：**用到的每个符号都要能对回真文件**
 *
 * 垫片里的名字若与真文件漂移，编译**不会报错**（`platform` 在这一侧就是本文件）。
 * 所以：
 *   · 每个导出都写清它来自 `platform/` 的哪个文件；
 *   · `MAX_ATTACHMENT_BYTES` 的**值**由检查脚本在启动时与真文件比对（不一致即失败）；
 *   · 其余是**纯类型/枚举**，`tsc` 会按使用点校验形状（字段名写错就编译不过）。
 */

/** 来自 `platform/src/main/ets/system/FilePicker.ets`（值由检查脚本核对） */
export const MAX_ATTACHMENT_BYTES: number = 16 * 1024 * 1024;

/** 来自 `platform/src/main/ets/notify/NotifyTypes.ets` */
export enum NotifyPriority {
  HIGH = 'high',
  NORMAL = 'normal',
  LOW = 'low',
}

/** 来自 `platform/src/main/ets/notify/NotifyTypes.ets` */
export enum NotifySlot {
  DECISION = 'decision',
  OUTCOME = 'outcome',
  SYSTEM = 'system',
}

/**
 * 来自 `platform/src/main/ets/notify/NotifyTypes.ets`。
 * 【注意是**接口**不是枚举】第一版垫片把它写成了枚举，编译立刻报
 * `Property 'hostId' does not exist on type 'NotifyRoute'` —— 垫片的形状必须逐字段照抄。
 */
export interface NotifyRoute {
  /** 目标页：pending / session / diagnostics / settings / workspace */
  page: string;
  /** Host 记录 id（多 Host 时用于切回正确连接） */
  hostId?: string;
  /** 会话 id */
  sessionId?: string;
  /** 待决项 id（审批/提问直达） */
  pendingId?: string;
}

/** 来自 `platform/src/main/ets/notify/NotifyTypes.ets` */
export interface NotificationDraft {
  key: string;
  title: string;
  body: string;
  priority: NotifyPriority;
  slot: NotifySlot;
  route?: NotifyRoute;
  ongoing?: boolean;
  group?: string;
}
