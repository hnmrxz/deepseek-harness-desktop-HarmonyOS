/**
 * 设置 / 凭据 / 插件 / 设备 / 诊断的呈现层契约
 * （D3 §1 信息架构的「设置」与「诊断」分支，对应 D1 §7.6 / §7.8）。
 *
 * 本文件同时承载「上游回复 → 本层契约」的投影函数。放这里的理由：
 * 契约与它的投影住在一起，改名/改形状时改一处即可；投影只依赖 `connection`
 * 的 JSON 取值工具，不认识端点名（端点名一律由调用方从 `dshcompat` 传入）。
 */

import { getArray, getBoolean, getRecord, getString } from 'connection';

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

/**
 * 投影 `pluginInventory/list` 的回复。
 *
 * 实测形状（D2 §8.7.2）：`{entries:[{entryId, moduleName, enabled, fiberPhase}]}`，
 * 其中 `fiberPhase` 是 `'active'` 或 `null`（**不是**空串）。
 * `null` 表示「已加载但未进入 active 阶段」，界面上按原样展示，不美化。
 *
 * `firstParty` 由模块名推断（`@deepseek-ai/*`）——这是**本地展示分类**，
 * 不是上游字段；上游没有「第一方」这个概念。注释写清楚以免被当成协议事实。
 */
export function projectPluginInventory(value: Object | undefined): PluginItem[] {
  const out: PluginItem[] = [];
  if (value === undefined) {
    return out;
  }
  const entries: Object[] | undefined = getArray(value, 'entries');
  if (entries === undefined) {
    return out;
  }
  for (let i = 0; i < entries.length; i++) {
    const entry: Object = entries[i];
    const entryId: string = getString(entry, 'entryId') ?? '';
    if (entryId.length === 0) {
      // 无 id 的条目无法在界面上区分，跳过而不是产出一行空卡片
      continue;
    }
    const moduleName: string = getString(entry, 'moduleName') ?? '';
    out.push({
      entryId: entryId,
      moduleName: moduleName,
      enabled: getBoolean(entry, 'enabled') === true,
      // fiberPhase 为 null 时统一成空串：本层契约里 phase 是 string
      phase: getString(entry, 'fiberPhase') ?? '',
      firstParty: moduleName.indexOf('@deepseek-ai/') === 0
    });
  }
  return out;
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

/**
 * 投影 `session/modelCatalog` 的回复。
 *
 * 实测形状（D2 §8.7.2）：
 * `{default:{provider,model,routingEffort?}, routableProviders:[…],
 *   groups:[{id, name, models:[{id, name, description?, reasoning?:{efforts:[{id,name,description?}], defaultEffort?}}]}]}`
 *
 * 投影策略：把两级结构（provider 分组 → 模型）**拍平成 `ModelOption[]`**，
 * 因为本层契约是按「一行一个可选模型」设计的（设置页的模型页签与输入区的
 * 模型 chip 都按这个粒度选择）。provider 名与 id 都保留下来，
 * 以便选择后能构造上游要求的 `{provider, model, reasoningEffort}`。
 *
 * `efforts` 取的是**强度 id 列表**（不是显示名）——下游要把它原样发回上游。
 * 显示名由界面按需查表，不在这里混入。
 */
export function projectModelCatalog(value: Object | undefined): ModelOption[] {
  const out: ModelOption[] = [];
  if (value === undefined) {
    return out;
  }
  const groups: Object[] | undefined = getArray(value, 'groups');
  if (groups === undefined) {
    return out;
  }
  for (let g = 0; g < groups.length; g++) {
    const group: Object = groups[g];
    const providerId: string = getString(group, 'id') ?? '';
    const providerName: string = getString(group, 'name') ?? providerId;
    const models: Object[] | undefined = getArray(group, 'models');
    if (models === undefined) {
      continue;
    }
    for (let m = 0; m < models.length; m++) {
      const model: Object = models[m];
      const modelId: string = getString(model, 'id') ?? '';
      if (modelId.length === 0 || providerId.length === 0) {
        // provider/model 是后续 selectModel 的必需定位信息，缺一不可用
        continue;
      }
      const efforts: string[] = [];
      let defaultEffort: string = '';
      const reasoning: Object | undefined = getRecord(model, 'reasoning');
      if (reasoning !== undefined) {
        const list: Object[] | undefined = getArray(reasoning, 'efforts');
        if (list !== undefined) {
          for (let e = 0; e < list.length; e++) {
            const id: string = getString(list[e], 'id') ?? '';
            if (id.length > 0) {
              efforts.push(id);
            }
          }
        }
        defaultEffort = getString(reasoning, 'defaultEffort') ?? '';
      }
      out.push({
        provider: providerId,
        providerName: providerName,
        modelId: modelId,
        modelName: getString(model, 'name') ?? modelId,
        description: getString(model, 'description') ?? '',
        efforts: efforts,
        defaultEffort: defaultEffort
      });
    }
  }
  return out;
}

/**
 * 投影模型目录里的**默认选择**（Host 为未配置会话准备的默认路由）。
 * 返回 undefined 表示 Host 没给默认值（界面应保持当前选择而不是猜一个）。
 */
export function projectDefaultSelection(value: Object | undefined): ModelSelection | undefined {
  if (value === undefined) {
    return undefined;
  }
  const def: Object | undefined = getRecord(value, 'default');
  if (def === undefined) {
    return undefined;
  }
  const provider: string = getString(def, 'provider') ?? '';
  const model: string = getString(def, 'model') ?? '';
  if (provider.length === 0 || model.length === 0) {
    return undefined;
  }
  return { provider: provider, modelId: model, effort: getString(def, 'reasoningEffort') ?? '' };
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
