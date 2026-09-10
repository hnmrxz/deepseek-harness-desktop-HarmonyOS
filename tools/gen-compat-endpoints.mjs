/**
 * 从协议契约数据生成 DSH 兼容面的端点上表（ArkTS 源）。
 *
 * 输入：tools/protocol-contract.mjs 产出的 contracts.json
 * 输出：dshcompat/src/main/ets/Endpoints.ets
 *
 * 为什么生成而不是手写：74 个端点、参数形态与可否取消都必须与上游生成描述符一致，
 * 手写必然漂移。生成物提交进仓库，漂移由 tools/compat-drift.mjs 的门禁检测。
 *
 * 用法：
 *   node tools/protocol-contract.mjs --json .research/protocol/contracts.json
 *   node tools/gen-compat-endpoints.mjs
 */
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const CONTRACTS = join(ROOT, '.research', 'protocol', 'contracts.json');
const OUT = join(ROOT, 'dshcompat', 'src', 'main', 'ets', 'Endpoints.ets');
const DSH_NM = process.env.DSH_NODE_MODULES
  ?? 'C:\\Users\\aotian\\AppData\\Roaming\\io.github.hairyf.deepseek-harness-desktop\\dependencies\\dsh\\node_modules';

/** 读取核心包版本（版本矩阵的判定依据只读它，不读外层打包包） */
function coreVersion() {
  try {
    const pkg = JSON.parse(readFileSync(join(DSH_NM, '@deepseek-ai', 'dsh', 'package.json'), 'utf8'));
    return pkg.version ?? 'unknown';
  } catch {
    return 'unknown';
  }
}

/** 能力映射：产品功能 → 必需/可选端点（缺省端点归入未引用集合） */
const CAPABILITIES = [
  {
    id: 'sessions', label: '会话',
    requires: ['session/list', 'session/create', 'session/prompt', 'session/follow'],
    optional: ['session/page', 'session/search', 'session/rename', 'session/cancel', 'session/fork',
      'session/updateQueue', 'session/modelCatalog', 'session/selectModel'],
    missingHint: '该 Host 未提供会话读写端点，无法收发对话'
  },
  {
    id: 'approvals', label: '审批与提问',
    requires: ['session/control'],
    optional: ['session/prompt'],
    missingHint: '该 Host 未提供审批控制流，无法答复审批与提问'
  },
  {
    id: 'workspaces', label: '工作区与文件',
    requires: ['session/canOpenWorkspacePath'],
    optional: ['workspace/create', 'workspace/rename', 'workspace/delete', 'workspace/follow',
      'directoryPicker/list', 'directoryPicker/pick', 'directoryPicker/createDirectory'],
    missingHint: '该 Host 未提供工作区端点，无法管理目录'
  },
  {
    id: 'agentPresets', label: 'Agent 预设',
    requires: ['agentPresets/list'],
    optional: ['agentPresets/read', 'agentPresets/select', 'agentPresets/copy', 'agentPresets/deletePreset'],
    missingHint: '该 Host 未提供 Agent 预设端点'
  },
  {
    id: 'settings', label: '设置与模型',
    requires: ['settings/describe'],
    optional: ['settings/update', 'settings/replace', 'settings/mutate', 'session/modelCatalog'],
    missingHint: '该 Host 未提供设置端点，设置页不可用'
  },
  {
    id: 'credentials', label: '凭据',
    requires: ['credentials/describe'],
    optional: ['credentials/set', 'credentials/unset'],
    missingHint: '该 Host 未提供凭据端点'
  },
  {
    id: 'plugins', label: '插件',
    requires: ['pluginInventory/list'],
    optional: [],
    missingHint: '该 Host 未提供插件清单端点'
  },
  {
    id: 'goals', label: '目标',
    requires: [],
    optional: ['goals/create', 'goals/edit', 'goals/pause', 'goals/resume', 'goals/complete', 'goals/clear'],
    missingHint: '该 Host 未提供目标端点'
  },
  {
    id: 'subagents', label: '子代理',
    requires: [],
    optional: ['subagents/list', 'subagents/interruptByParent'],
    missingHint: '该 Host 未提供子代理端点'
  },
  {
    id: 'commands', label: '斜杠命令',
    requires: [],
    optional: ['commands/list', 'commands/execute'],
    missingHint: '该 Host 未提供命令端点'
  },
  {
    id: 'skills', label: '技能',
    requires: [],
    optional: ['skills/list'],
    missingHint: '该 Host 未提供技能目录端点'
  },
  {
    id: 'llm', label: '模型发现',
    requires: [],
    optional: ['llm/listProviders', 'llm/listConfigurableProviders', 'llm/discoverModels'],
    missingHint: '该 Host 未提供模型发现端点'
  }
];

const contracts = JSON.parse(readFileSync(CONTRACTS, 'utf8'));

/** 推断参数形态 */
function shapeOf(params) {
  if (params.length === 0) return 'ArgsShape.NONE';
  const names = params.map((p) => p.name);
  if (names.length === 1 && names[0] === 'request') return 'ArgsShape.REQUEST';
  if (names.length === 1 && names[0] === '_request') return 'ArgsShape.UNDERSCORE_REQUEST';
  return 'ArgsShape.NAMED';
}

/**
 * endpoint → 能力 id 集合。
 * 一个端点被多个能力引用是**合法**的（例如 session/prompt 同时属于「会话」与「审批与提问」），
 * 因此这里记录集合而不是单值；DshEndpoint.capability 取排序后的第一个作为「主归属」，
 * 需要完整归属时用 CompatIndex.capabilitiesOf(endpoint)。
 */
const capabilityOf = new Map();
for (const cap of CAPABILITIES) {
  for (const e of [...cap.requires, ...cap.optional]) {
    const set = capabilityOf.get(e) ?? new Set();
    if (set.has(cap.id) === false && cap.requires.includes(e) === false && cap.optional.includes(e) === false) {
      throw new Error(`内部错误：端点在能力 ${cap.id} 中重复声明`);
    }
    set.add(cap.id);
    capabilityOf.set(e, set);
  }
}

const entries = contracts
  .map((d) => {
    const caps = [...(capabilityOf.get(`${d.namespace}/${d.method}`) ?? new Set())].sort();
    return {
      id: d.id,
      ns: d.namespace,
      method: d.method,
      shape: shapeOf(d.params),
      params: d.params.map((p) => p.name),
      stream: d.kind === 'stream',
      cancellable: d.cancellable === true,
      source: d.source ?? '',
      capability: caps.length > 0 ? caps[0] : '',
      capabilities: caps
    };
  })
  .sort((a, b) => `${a.ns}/${a.method}`.localeCompare(`${b.ns}/${b.method}`));

// 校验：能力表引用的端点必须都真实存在（否则是能力表写错，不是上游变化）
const known = new Set(entries.map((e) => `${e.ns}/${e.method}`));
for (const cap of CAPABILITIES) {
  for (const e of [...cap.requires, ...cap.optional]) {
    if (!known.has(e)) console.warn(`WARN 能力 ${cap.id} 引用了不存在的端点 ${e}（将出现在 missing 中）`);
  }
}

const lines = [];
lines.push('/**');
lines.push(' * 【自动生成，请勿手改】DSH 上游端点上表。');
lines.push(' *');
lines.push(' * 生成方式：');
lines.push(' *   node tools/protocol-contract.mjs --json .research/protocol/contracts.json');
lines.push(' *   node tools/gen-compat-endpoints.mjs');
lines.push(' * 漂移检测：node tools/compat-drift.mjs（对当前安装/checkout 的上游重新提取并比对）');
lines.push(' *');
lines.push(` * 采集对象：@deepseek-ai/dsh ${coreVersion()} · ${entries.length} 个 endpoint`);
lines.push(' */');
lines.push('');
lines.push("import { ArgsShape, DshCapability, DshEndpoint, UpstreamIdentity } from './CompatTypes';");
lines.push('');
lines.push(`export const UPSTREAM_IDENTITY: UpstreamIdentity = {`);
lines.push(`  corePackage: '${coreVersion()}',`);
lines.push(`  capturedAt: '${new Date().toISOString()}',`);
lines.push(`  endpointCount: ${entries.length}`);
lines.push('};');
lines.push('');
lines.push('/** 全部 endpoint 调用契约（按 endpoint 名排序） */');
lines.push('export const DSH_ENDPOINTS: DshEndpoint[] = [');
for (const e of entries) {
  const params = e.params.length === 0 ? '[]' : `[${e.params.map((p) => `'${p}'`).join(', ')}]`;
  lines.push('  {');
  lines.push(`    id: '${e.id}',`);
  lines.push(`    ns: '${e.ns}',`);
  lines.push(`    method: '${e.method}',`);
  lines.push(`    shape: ${e.shape},`);
  lines.push(`    params: ${params},`);
  lines.push(`    stream: ${e.stream},`);
  lines.push(`    cancellable: ${e.cancellable},`);
  lines.push(`    source: '${e.source}',`);
  lines.push(`    capability: '${e.capability}',`);
  lines.push(`    capabilities: [${e.capabilities.map((c) => `'${c}'`).join(', ')}]`);
  lines.push('  },');
}
lines.push('];');
lines.push('');
lines.push('/** 能力映射：产品功能 → 必需/可选端点（用于启动探测与入口置灰） */');
lines.push('export const DSH_CAPABILITIES: DshCapability[] = [');
for (const cap of CAPABILITIES) {
  const req = cap.requires.length === 0 ? '[]' : `[${cap.requires.map((e) => `'${e}'`).join(', ')}]`;
  const opt = cap.optional.length === 0 ? '[]' : `[${cap.optional.map((e) => `'${e}'`).join(', ')}]`;
  lines.push('  {');
  lines.push(`    id: '${cap.id}',`);
  lines.push(`    label: '${cap.label}',`);
  lines.push(`    requires: ${req},`);
  lines.push(`    optional: ${opt},`);
  lines.push(`    missingHint: '${cap.missingHint}'`);
  lines.push('  },');
}
lines.push('];');
lines.push('');

writeFileSync(OUT, lines.join('\n'), 'utf8');
console.log(`已生成 ${OUT}`);
console.log(`  端点 ${entries.length} 个；其中流式 ${entries.filter((e) => e.stream).length} 个`);
console.log(`  能力 ${CAPABILITIES.length} 个；未被能力引用的端点 ${entries.filter((e) => e.capability === '').length} 个`);
