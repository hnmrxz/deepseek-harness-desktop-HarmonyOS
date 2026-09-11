/**
 * 设置 / 凭据 / 插件 / 设备 / 诊断的呈现层契约
 * （D3 §1 信息架构的「设置」与「诊断」分支，对应 D1 §7.6 / §7.8）。
 *
 * 本文件同时承载「上游回复 → 本层契约」的投影函数。放这里的理由：
 * 契约与它的投影住在一起，改名/改形状时改一处即可；投影只依赖 `connection`
 * 的 JSON 取值工具，不认识端点名（端点名一律由调用方从 `dshcompat` 传入）。
 */

import { getArray, getBoolean, getNumber, getRecord, getString, isRecord } from 'connection';

// ─────────────────────────── 设置 ───────────────────────────

/** 设置项类型 */
export enum SettingKind {
  TOGGLE = 'toggle',
  CHOICE = 'choice',
  TEXT = 'text',
  INFO = 'info'
}

/**
 * 设置项来源：**本项目自己定义**的项，还是从 Host 的 `settings/describe` 读来的。
 *
 * 为什么必须区分：本客户端的「通知」「离线缓存」等项属于**本地偏好**，
 * 上游没有对应命名空间；而外观 / 模型 / 重试策略等项来自 Host。
 * 两类项混在一起而不标注，用户会以为改通知开关也会影响 Host——
 * 那是一个**会撒谎的界面**。所以来源是设置项的一等属性，界面上必须显示。
 */
export enum SettingOrigin {
  /** 本客户端本地偏好（Host 不知道它的存在） */
  LOCAL = 'local',
  /** 来自 Host 的 `settings/describe` */
  HOST = 'host'
}

/** 选择项（`value` 发往上游，`label` 给人看） */
export interface SettingChoice {
  value: string;
  label: string;
}

/** 设置项 */
export interface SettingItem {
  /** 上游设置键（ns 内的路径，用 `.` 连接；本地项为本地键） */
  key: string;
  label: string;
  /** 说明文字（必填：设置项不能只有名字，D3 §4 文案纪律） */
  hint: string;
  kind: SettingKind;
  /** 当前值（布尔/字符串） */
  boolValue: boolean;
  textValue: string;
  /** CHOICE 的选项（带显示名）；旧字段 `options` 保留为等价的取值列表 */
  options: string[];
  /** CHOICE 的选项（取值 + 显示名） */
  choices: SettingChoice[];
  /** 是否只读（本客户端目前不提供编辑入口） */
  readOnly: boolean;
  /**
   * Host 是否接受对该命名空间的写。
   *
   * 【为什么与 `readOnly` 分开】两者含义不同，混用会造成**会撒谎的界面**：
   *   - `hostWritable === false`：Host 明确不接受写，控件必须禁用并**说明原因**；
   *   - `readOnly === true` 但 `hostWritable === true`：Host 接受写，只是本客户端
   *     还没做这个形态的编辑器（实测的 `models[]`、`retryPolicy` 就是这种）。
   * 曾经把两者合成一个 `readOnly`，结果是「本客户端没做」被渲染成「Host 不允许」——
   * 用户会以为 Host 限制了权限，而实际上是我们自己的功能缺口。
   */
  hostWritable: boolean;
  /** 是否需要在 Host 侧生效（提示"应用后生效"） */
  appliesLive: boolean;
  /** 来源：本地偏好还是 Host 设置 */
  origin: SettingOrigin;
  /**
   * 是否已被**用户层**显式覆盖。
   *
   * 实测 `value` 是「schema 默认 → 组合基线 → 用户层」三层合并的结果，
   * 所以 `value` 无法区分「继承来的默认值」与「用户显式设成同一个值」。
   * 界面靠这个标记告诉用户「这一项是你在 Host 上改过的」。
   */
  userSet: boolean;
  /** 该设置项是一个凭据引用（实测 `meta.role === 'credential-ref'`） */
  credentialRef: boolean;
}

/** 设置分组 */
export interface SettingGroup {
  /** 分组标题（如「外观」「通知」） */
  title: string;
  items: SettingItem[];
}

/**
 * 一个命名空间的**写状态**（与 `SettingItem` 分开保存）。
 *
 * 为什么必须单独存：`revision` 是**写操作的并发令牌**（实测 `SettingsNamespaceView.revision`，
 * 见 D3b §2 第 3 条）。它属于「命名空间」而不属于「某个设置项」——
 * 同一个命名空间下改哪个字段都要带同一个 revision，且一次成功写会让它 +1。
 * 把它塞进每个 `SettingItem` 会立刻产生**同一份数据的多个副本**，
 * 而副本不同步的后果是：改完 A 字段后改 B 字段带着**过期 revision** → 恒被拒。
 */
export interface SettingsNamespaceState {
  ns: string;
  /** 最近一次读取/写入后的 revision */
  revision: number;
  /** Host 是否接受对该命名空间的写 */
  writable: boolean;
  /** `'live'`（立即生效）或 `'restart'`（需重启 Host） */
  applies: string;
}

/** 设置分组 + 它的命名空间写状态 */
export interface SettingsGroupEntry {
  group: SettingGroup;
  state: SettingsNamespaceState;
}

/** 写操作的结果（用于界面给出**可执行**的提示，而不是笼统的「失败」） */
export enum SettingsWriteOutcome {
  /** 写入成功，Host 已接受 */
  OK = 'ok',
  /** 版本冲突：别的客户端改过，需要重新读取后再改（重试同一请求永远失败） */
  CONFLICT = 'conflict',
  /** Host 拒绝（只读提供方 / schema 校验 / 未注册命名空间） */
  REJECTED = 'rejected',
  /** 载体或其它失败（网络、未连接、端点不存在） */
  FAILED = 'failed'
}

/** 写操作的详细结果 */
export interface SettingsWriteResult {
  outcome: SettingsWriteOutcome;
  /** 用户可读的一句话（含发生了什么事 + 可以做什么） */
  message: string;
  /** 冲突时的实际 revision（若 Host 给出） */
  actualRevision: number;
}

// ───────────────── 从 Host 的 settings/describe 生成设置项 ─────────────────

/**
 * `schemastery` schema 的一个节点（序列化后的形状）。
 *
 * **实测格式（D2b/D3b，必须照此读，不能按嵌套树猜）**：schema 不是树，
 * 而是一张**以 `uid` 为键的扁平表** `refs` + 一个根 `uid`：
 *
 * ```json
 * {"uid":231,"refs":{
 *   "225":{"type":"union","meta":{"default":"system"},"list":[220,222]},
 *   "220":{"type":"const","meta":{"required":true},"value":"light"},
 *   "231":{"type":"object","meta":{"default":{}},"dict":{"preference":225}}}}
 * ```
 *
 * 各结构键：
 *   - `dict`：对象字段名 → 子节点 uid（**设置项就来自这里**）
 *   - `list`：`union` 的候选 uid
 *   - `inner`：`array` 的元素 uid
 *   - `meta`：`required` / `default` / `min` / `max` / `step` / `pattern` / `role` / `description`
 *   - `value`：`const` 的取值
 */
const SCHEMA_KIND_STRING = 'string';
const SCHEMA_KIND_NUMBER = 'number';
const SCHEMA_KIND_BOOLEAN = 'boolean';
const SCHEMA_KIND_CONST = 'const';
const SCHEMA_KIND_UNION = 'union';
const SCHEMA_KIND_ARRAY = 'array';
const SCHEMA_KIND_OBJECT = 'object';
/** 实测值：该字段是一个凭据引用（不是普通字符串） */
const META_ROLE_CREDENTIAL_REF = 'credential-ref';

/** 从 `Record` 取一个字段（`readPath` 只吃点分路径，这里要按任意字符串键取） */
function fieldOf(source: Object | undefined, key: string): Object | undefined {
  if (source === undefined || !isRecord(source)) {
    return undefined;
  }
  return (source as Record<string, Object>)[key];
}

/** 按 `string[]` 路径读取**
 *
 * 为什么不用 `connection.readPath`：那个吃点分**字符串**路径，
 * 而 schema 的字段名里可能含点（`a.b` 会被它当成两段）。这里的路径是
 * 上游直接给出的段数组，必须逐段按字面键取。
 */
function readSegments(source: Object | undefined, segments: string[]): Object | undefined {
  let cursor: Object | undefined = source;
  for (let i = 0; i < segments.length; i++) {
    cursor = fieldOf(cursor, segments[i]);
    if (cursor === undefined) {
      return undefined;
    }
  }
  return cursor;
}

/** `camelCase` / `snake_case` → 人可读标签（schema 里**没有**显示名，实测） */
export function humanizeKey(key: string): string {
  if (key.length === 0) {
    return key;
  }
  let out: string = '';
  for (let i = 0; i < key.length; i++) {
    const ch: string = key.charAt(i);
    const code: number = key.charCodeAt(i);
    const isUpper: boolean = code >= 65 && code <= 90;
    if (i > 0 && isUpper) {
      out += ' ';
    }
    out += isUpper ? ch.toLowerCase() : ch;
  }
  return out.length > 0 ? out.charAt(0).toUpperCase() + out.substring(1) : key;
}

/** 把任意 JSON 标量渲染成一行文本（用于取值展示） */
function scalarText(value: Object | undefined): string {
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

/** 该字段是否被用户层显式覆盖（`user` 里出现同名键即为覆盖） */
function isUserSet(user: Object | undefined, field: string): boolean {
  if (user === undefined || !isRecord(user)) {
    return false;
  }
  return (user as Record<string, Object>)[field] !== undefined;
}

/**
 * 把一棵 schema 子节点的 `union(list:const…)` 展开成选择项。
 * 非枚举（例如 `union` 里混了对象分支）返回空数组，调用方降级为只读展示。
 */
function choicesOf(refs: Object, uid: number): SettingChoice[] {
  const node: Object | undefined = fieldOf(refs, `${uid}`);
  if (node === undefined || getString(node, 'type') !== SCHEMA_KIND_UNION) {
    return [];
  }
  const list: Object[] | undefined = getArray(node, 'list');
  if (list === undefined) {
    return [];
  }
  const out: SettingChoice[] = [];
  for (let i = 0; i < list.length; i++) {
    // `list` 的元素可能是 uid（数字）——实测如此
    const childUid: Object = list[i];
    if (typeof childUid !== 'number') {
      // 内联节点（非 uid）：实测未出现，按不可枚举处理而不是猜
      return [];
    }
    const child: Object | undefined = fieldOf(refs, `${childUid as number}`);
    if (child === undefined || getString(child, 'type') !== SCHEMA_KIND_CONST) {
      return [];
    }
    const value: Object | undefined = fieldOf(child, 'value');
    const text: string = scalarText(value);
    if (text.length === 0) {
      return [];
    }
    // 实测：上游**没有**枚举显示名，显示值就是取值本身
    out.push({ value: text, label: text });
  }
  return out;
}

/** `null` 与 `undefined` 在 JSON 里语义不同，但本层都表示「没有值」 */
function metaOf(refs: Object, uid: number): Object | undefined {
  const node: Object | undefined = fieldOf(refs, `${uid}`);
  return node === undefined ? undefined : fieldOf(node, 'meta');
}

/**
 * 为一个字段生成**非空**的说明文字。
 *
 * D3 §4 要求设置项不能只有名字。实测**多数字段没有 `description`**，
 * 因此这里逐级降级到「上游字段名 + 约束」，而不是留下空串：
 * 空说明比没有说明更糟——它看起来像「这项没什么可说的」。
 */
function hintFor(ns: string, field: string, meta: Object | undefined,
  credentialRef: boolean): string {
  const described: string | undefined = meta === undefined ? undefined : getString(meta, 'description');
  if (described !== undefined && described.length > 0) {
    return described;
  }
  const parts: string[] = [];
  if (credentialRef) {
    parts.push('凭据引用（不是明文；值由「凭据」页管理）');
  }
  const min: number | undefined = meta === undefined ? undefined : getNumber(meta, 'min');
  const max: number | undefined = meta === undefined ? undefined : getNumber(meta, 'max');
  if (min !== undefined || max !== undefined) {
    parts.push(`取值范围 ${min === undefined ? '不限' : min} – ${max === undefined ? '不限' : max}`);
  }
  const step: number | undefined = meta === undefined ? undefined : getNumber(meta, 'step');
  if (step !== undefined && step > 1) {
    parts.push(`步长 ${step}`);
  }
  if (meta !== undefined) {
    const pattern: Object | undefined = fieldOf(meta, 'pattern');
    if (pattern !== undefined) {
      const source: string | undefined = getString(pattern, 'source');
      if (source !== undefined && source.length > 0) {
        parts.push(`须匹配 ${source}`);
      }
    }
    if (getBoolean(meta, 'required') === true) {
      parts.push('必填');
    }
  }
  parts.push(`Host 设置项 ${ns}.${field}`);
  return parts.join('；');
}

/** 一个命名空间的投影结果 */
export interface SettingsNamespaceItems {
  ns: string;
  items: SettingItem[];
}

/**
 * 把 `settings/describe` 的一个命名空间视图投影成设置分组。
 *
 * 只展开 `dict` 的**一级字段**（实测设置项都在这一级）。嵌套对象与数组
 * （如 `llm-deepseek.models`、`retryPolicy`）以只读信息行呈现——
 * **不猜**它们的编辑形态：列表编辑器需要被嵌套 schema 的结构，
 * 而第一版没有实测过「写一个数组项」的线上效果，宁可不给入口。
 *
 * `writable` 为 false 时**所有**项只读（Host 明确说了不接受写）。
 */
export function projectSettingsNamespace(view: Object, writable: boolean): SettingsNamespaceItems {
  const ns: string = getString(view, 'ns') ?? '';
  const out: SettingsNamespaceItems = { ns: ns, items: [] };
  const schema: Object | undefined = getRecord(view, 'schema');
  if (schema === undefined || ns.length === 0) {
    return out;
  }
  const refs: Object | undefined = getRecord(schema, 'refs');
  const rootUid: number | undefined = getNumber(schema, 'uid');
  if (refs === undefined || rootUid === undefined) {
    return out;
  }
  const dict: Object | undefined = fieldOf(fieldOf(refs, `${rootUid}`), 'dict');
  if (dict === undefined || !isRecord(dict)) {
    return out;
  }
  const value: Object | undefined = getRecord(view, 'value');
  const user: Object | undefined = getRecord(view, 'user');
  const applies: string = getString(view, 'applies') ?? 'live';
  const fields: Record<string, Object> = dict as Record<string, Object>;

  for (const field of Object.keys(fields)) {
    const childUid: Object = fields[field];
    if (typeof childUid !== 'number') {
      continue;
    }
    const uid: number = childUid as number;
    const node: Object | undefined = fieldOf(refs, `${uid}`);
    if (node === undefined) {
      continue;
    }
    const type: string = getString(node, 'type') ?? '';
    const meta: Object | undefined = metaOf(refs, uid);
    const credentialRef: boolean =
      (meta === undefined ? '' : (getString(meta, 'role') ?? '')) === META_ROLE_CREDENTIAL_REF;
    const current: Object | undefined = fieldOf(value, field);
    const itemKey: string = `${ns}.${field}`;
    const base: SettingItem = {
      key: itemKey,
      label: humanizeKey(field),
      hint: hintFor(ns, field, meta, credentialRef),
      kind: SettingKind.INFO,
      boolValue: false,
      textValue: '',
      options: [],
      choices: [],
      // Host 不接受写时，任何形态都不可编辑
      readOnly: !writable,
      hostWritable: writable,
      appliesLive: applies !== 'restart',
      origin: SettingOrigin.HOST,
      userSet: isUserSet(user, field),
      credentialRef: credentialRef
    };

    if (type === SCHEMA_KIND_BOOLEAN) {
      base.kind = SettingKind.TOGGLE;
      base.boolValue = current === true;
      out.items.push(base);
      continue;
    }
    const choices: SettingChoice[] = choicesOf(refs, uid);
    if (choices.length > 0) {
      base.kind = SettingKind.CHOICE;
      base.choices = choices;
      base.textValue = scalarText(current);
      for (let c = 0; c < choices.length; c++) {
        base.options.push(choices[c].value);
      }
      out.items.push(base);
      continue;
    }
    if (type === SCHEMA_KIND_STRING || type === SCHEMA_KIND_NUMBER) {
      base.kind = SettingKind.TEXT;
      base.textValue = scalarText(current);
      out.items.push(base);
      continue;
    }
    // `array` / `object` / 复杂 `union`：只读展示，**不提供编辑入口**。
    // 注意这里说的是「本客户端还没做这个形态的编辑器」，不是「Host 不允许写」——
    // 所以 `hostWritable` 保持 Host 的真实答复，靠 `readOnly` 关掉控件，
    // 界面上两者可以给出不同的解释文案。
    base.kind = SettingKind.INFO;
    base.readOnly = true;
    base.textValue = current === undefined
      ? '（未设置）'
      : `${type} · ${scalarText(current).length} 字符`;
    out.items.push(base);
  }
  return out;
}

/**
 * 把所有命名空间投影成分组列表（分组标题 = 命名空间名）。
 *
 * **不硬编码命名空间清单**：实测 Host 上的命名空间集合取决于它装了哪些插件
 * （本机 14 个），硬编码会退化成又一张「猜测表」。
 * 未知命名空间同样展示——只是没有友好标题。
 */
export function projectSettingsGroups(value: Object | undefined): SettingGroup[] {
  const entries: SettingsGroupEntry[] = projectSettingsEntries(value);
  const out: SettingGroup[] = [];
  for (let i = 0; i < entries.length; i++) {
    out.push(entries[i].group);
  }
  return out;
}

/**
 * 与 `projectSettingsGroups` 相同，但**带上每个命名空间的写状态**（revision 等）。
 *
 * 中枢用它保存并发令牌；纯展示路径用上面那个（UI 不需要看见 revision）。
 */
export function projectSettingsEntries(value: Object | undefined): SettingsGroupEntry[] {
  const out: SettingsGroupEntry[] = [];
  if (value === undefined) {
    return out;
  }
  const writable: boolean = getBoolean(value, 'writable') === true;
  const namespaces: Object[] | undefined = getArray(value, 'namespaces');
  if (namespaces === undefined) {
    return out;
  }
  for (let i = 0; i < namespaces.length; i++) {
    const view: Object = namespaces[i];
    const projected: SettingsNamespaceItems = projectSettingsNamespace(view, writable);
    if (projected.items.length === 0) {
      continue;
    }
    const state: SettingsNamespaceState = {
      ns: projected.ns,
      revision: getNumber(view, 'revision') ?? 0,
      writable: writable,
      applies: getString(view, 'applies') ?? 'live'
    };
    out.push({ group: { title: projected.ns, items: projected.items }, state: state });
  }
  return out;
}

/**
 * 构造 `settings/mutate` 的实参：设置项的 key → 有序路径操作。
 *
 * 设置项的 key 形如 `ns.field`。**只切第一个点**：命名空间名不含点（实测 14 个
 * 全部如此，如 `llm-deepseek`），而字段名可能含点（上游 `dict` 的键名无限制），
 * 所以其余点留给字段路径。
 *
 * `expectedRevision` **不能省略**：省略等于放弃乐观并发检查，两个客户端同时改
 * 会互相覆盖（D2b §4）。
 */
export function settingsMutateArgs(ns: string, fieldPath: string, value: Object,
  expectedRevision: number): Object {
  const segments: string[] = [];
  let start: number = 0;
  while (start <= fieldPath.length) {
    const dot: number = fieldPath.indexOf('.', start);
    const end: number = dot < 0 ? fieldPath.length : dot;
    const segment: string = fieldPath.substring(start, end);
    if (segment.length > 0) {
      segments.push(segment);
    }
    if (dot < 0) {
      break;
    }
    start = dot + 1;
  }
  const op: Record<string, Object> = {};
  op['op'] = 'set';
  op['path'] = segments;
  op['value'] = value;
  const ops: Object[] = [op as Object];
  const args: Record<string, Object> = {};
  args['ns'] = ns;
  args['ops'] = ops;
  args['expectedRevision'] = expectedRevision;
  return args as Object;
}

/**
 * 把设置项的 key 拆成「命名空间 + 字段路径」（第一个点之前是命名空间）。
 * 拆不开时返回 undefined——调用方应**拒绝**这次写，而不是猜一个命名空间出来。
 */
export function splitSettingKey(key: string): SettingsKeyParts | undefined {
  const dot: number = key.indexOf('.');
  if (dot <= 0 || dot >= key.length - 1) {
    return undefined;
  }
  return { ns: key.substring(0, dot), fieldPath: key.substring(dot + 1) };
}

/** 设置项 key 的拆分结果 */
export interface SettingsKeyParts {
  ns: string;
  fieldPath: string;
}

/**
 * 合并「来自 Host 的设置」与「本客户端本地偏好」。
 *
 * 【为什么必须合并，而不是二选一】
 *   本客户端的通知、离线缓存等偏好**不存在于上游**——Host 的
 *   `settings/describe` 里没有这些命名空间。若连上 Host 后整页替换成
 *   Host 设置，这些本地偏好就会**从界面上消失**（用户会以为功能没了）；
 *   若反过来只显示本地偏好，用户又无法配置真正生效的 Host 设置。
 *
 * Host 分组在前（那是用户来设置页主要想看的东西），本地分组在后。
 */
export function mergeSettingsGroups(host: SettingGroup[], local: SettingGroup[]): SettingGroup[] {
  const out: SettingGroup[] = [];
  for (let i = 0; i < host.length; i++) {
    out.push(host[i]);
  }
  for (let j = 0; j < local.length; j++) {
    out.push(local[j]);
  }
  return out;
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

/**
 * 从 `settings/describe` 的回复里取出**凭据引用列表**。
 *
 * 这是凭据页的前置：`credentials/describe` **没有「列出全部」模式**——
 * 实测传 `refs: []` 只得到 `{}`。ref 列表的唯一来源就是各命名空间声明的
 * `secrets[].path`（D2 §8.7.2 第 17/19 条）。
 *
 * **ref 的编码是 `path` 用 `.` 连接，不带命名空间前缀**（实测确证，D2 §8.7.2 第 18 条）：
 * `"apiKey"` 命中，而看起来更自然的 `"<ns>:apiKey"` 被 `gateway/bad-request` 拒绝。
 * 这里按实测编码拼接；若上游改变编码，失败会表现为「凭据全部显示未配置」——
 * 一个不报错只撒谎的形态，因此本函数的上游出处必须在升级时重点复核。
 */
export function projectCredentialRefs(value: Object | undefined): string[] {
  const out: string[] = [];
  if (value === undefined) {
    return out;
  }
  const namespaces: Object[] | undefined = getArray(value, 'namespaces');
  if (namespaces === undefined) {
    return out;
  }
  for (let i = 0; i < namespaces.length; i++) {
    const secrets: Object[] | undefined = getArray(namespaces[i], 'secrets');
    if (secrets === undefined) {
      continue;
    }
    for (let j = 0; j < secrets.length; j++) {
      const path: Object[] | undefined = getArray(secrets[j], 'path');
      if (path === undefined || path.length === 0) {
        continue;
      }
      const parts: string[] = [];
      for (let k = 0; k < path.length; k++) {
        const seg: Object = path[k];
        parts.push(typeof seg === 'string' ? seg as string : '');
      }
      const ref: string = parts.join('.');
      if (ref.length > 0 && out.indexOf(ref) < 0) {
        out.push(ref);
      }
    }
  }
  return out;
}

/**
 * 投影 `credentials/describe` 的回复。
 *
 * 实测形状：`{"<ref>": {configured, source?, writable}}`——一个**以 ref 为键的映射**。
 * 因此必须把 `refs` 一起传入：不能靠遍历回复的键还原顺序（Host 只会回应被请求的 ref）。
 *
 * 三个取舍：
 *   - `source` 在**未配置时缺省**（可选字段）。不能当成空串来源，
 *     否则界面会把「没有来源信息」显示成一个来源；这里仅在存在时赋值。
 *   - `interactive`（是否支持交互式授权）**线协议里没有对应字段**，一律置 false
 *     并在此说明——凭空假定为 true 会渲染出一个并不存在的「去授权」按钮。
 *   - Host 未描述某条 ref 时**保留一个「未配置」条目**而不是丢掉：
 *     丢掉会让用户以为 Host 上根本没有这项凭据。
 */
export function projectCredentials(value: Object | undefined, refs: string[]): CredentialItem[] {
  const out: CredentialItem[] = [];
  const map: Record<string, Object> = (value === undefined ? {} : value) as Record<string, Object>;
  for (let i = 0; i < refs.length; i++) {
    const ref: string = refs[i];
    const info: Object | undefined = map[ref];
    if (info === undefined || info === null) {
      out.push({ ref: ref, configured: false, writable: false, source: '', interactive: false });
      continue;
    }
    out.push({
      ref: ref,
      configured: getBoolean(info, 'configured') === true,
      writable: getBoolean(info, 'writable') === true,
      source: getString(info, 'source') ?? '',
      interactive: false
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
