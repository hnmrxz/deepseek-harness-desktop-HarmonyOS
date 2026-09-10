/**
 * 设置 / 凭据 / 插件 / 设备 / 诊断的呈现层契约
 * （D3 §1 信息架构的「设置」与「诊断」分支，对应 D1 §7.6 / §7.8）。
 */

// ─────────────────────────── 设置 ───────────────────────────

/** 设置项类型 */
export enum SettingKind {
  TOGGLE = 'toggle',
  CHOICE = 'choice',
  TEXT = 'text',
  INFO = 'info'
}

/** 设置项 */
export interface SettingItem {
  /** 上游设置键（ns 内的路径） */
  key: string;
  label: string;
  /** 说明文字（必填：设置项不能只有名字，D3 §4 文案纪律） */
  hint: string;
  kind: SettingKind;
  /** 当前值（布尔/字符串） */
  boolValue: boolean;
  textValue: string;
  /** CHOICE 的选项 */
  options: string[];
  /** 是否只读（写权限来自 Host） */
  readOnly: boolean;
  /** 是否需要在 Host 侧生效（提示"应用后生效"） */
  appliesLive: boolean;
}

/** 设置分组 */
export interface SettingGroup {
  /** 分组标题（如「外观」「通知」） */
  title: string;
  items: SettingItem[];
}

// ─────────────────────────── 凭据 ───────────────────────────

/** 凭据条目（**绝不包含明文值**，只呈现状态，D1 §11.5 S3/S4） */
export interface CredentialItem {
  /** 引用名（如 DEEPSEEK_API_KEY） */
  ref: string;
  /** 是否已配置 */
  configured: boolean;
  /** 是否可写（Host 侧决定） */
  writable: boolean;
  /** 来源说明（file / env / 交互式授权） */
  source: string;
  /** 是否支持交互式授权 flow（如 OAuth / 粘贴码） */
  interactive: boolean;
}

// ─────────────────────────── 插件 ───────────────────────────

/** 插件条目（对应 pluginInventory 的投影） */
export interface PluginItem {
  entryId: string;
  moduleName: string;
  enabled: boolean;
  /** cordis fiber 阶段（active / null） */
  phase: string;
  /** 是否第一方（@deepseek-ai/*） */
  firstParty: boolean;
}

/** 插件健康度（用于设置页的一行摘要） */
export function pluginSummary(items: PluginItem[]): string {
  let enabled: number = 0;
  let active: number = 0;
  for (let i = 0; i < items.length; i++) {
    if (items[i].enabled) {
      enabled++;
    }
    if (items[i].phase === 'active') {
      active++;
    }
  }
  return `${items.length} 个条目 · ${enabled} 已启用 · ${active} 运行中`;
}

// ─────────────────────────── 设备与 Host ───────────────────────────

/** Host 记录（对应 D1 §7.1 的多 Host 管理） */
export interface HostRecord {
  id: string;
  name: string;
  authority: string;
  /** 是否 loopback（决定接入路径 L0/L1，D1 §6.4） */
  isLoopback: boolean;
  /** 接入级别展示文案 */
  level: string;
  /** 是否已授权（持有会话 cookie） */
  authorized: boolean;
  /** Host 核心包版本（用于版本矩阵提示） */
  version: string;
}

/** 连接状态展示（D3 §4 状态与文案规范） */
export interface ConnectionBanner {
  /** 是否已连接 */
  connected: boolean;
  /** 一行状态（如「已连接 · clientId=…」） */
  text: string;
  /** 是否需要用户动作（显示按钮） */
  actionable: boolean;
  /** 动作按钮文案 */
  actionLabel: string;
}

// ─────────────────────────── 诊断 ───────────────────────────

/** 诊断项（与 connection 的 DiagnosticItem 对齐，此处为呈现层副本以避免跨层依赖） */
export interface DiagEntry {
  name: string;
  passed: boolean;
  detail: string;
  advice: string;
}

/** 诊断报告呈现模型 */
export interface DiagReport {
  entries: DiagEntry[];
  healthy: boolean;
  /** 生成时间（毫秒） */
  generatedAt: number;
  /** 上游版本判定结论（来自 dshcompat.checkVersion） */
  versionVerdict: string;
  versionMessage: string;
  versionAdvice: string;
  /** 兼容面上表统计 */
  tableStats: string;
  /** 当前接口面（用于暴露"是否漏注入"） */
  surface: string;
}

// ─────────────────────────── 关于与版本 ───────────────────────────

/** 关于页信息 */
export interface AboutInfo {
  appVersion: string;
  /** 受支持的上游版本矩阵（来自 dshcompat） */
  supportedUpstream: string;
  /** 兼容面采集时间 */
  compatCapturedAt: string;
  /** 端点上表规模描述 */
  endpointStats: string;
}

// ─────────────────────────── 模型选择 ───────────────────────────

/** 模型选项 */
export interface ModelOption {
  provider: string;
  providerName: string;
  modelId: string;
  modelName: string;
  description: string;
  /** 推理强度选项（空 = 不支持） */
  efforts: string[];
  defaultEffort: string;
}

/** 当前模型与推理强度 */
export interface ModelSelection {
  provider: string;
  modelId: string;
  effort: string;
}

/** 当前选择的显示文案 */
export function modelSelectionLabel(selection: ModelSelection, options: ModelOption[]): string {
  for (let i = 0; i < options.length; i++) {
    const o: ModelOption = options[i];
    if (o.provider === selection.provider && o.modelId === selection.modelId) {
      return o.modelName.length > 0 ? o.modelName : o.modelId;
    }
  }
  return selection.modelId.length > 0 ? selection.modelId : '未选择模型';
}
