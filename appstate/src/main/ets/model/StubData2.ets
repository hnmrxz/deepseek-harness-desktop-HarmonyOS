/**
 * 桩数据源 · 第二批（覆盖工作区 / 设置 / 凭据 / 插件 / 设备 / 诊断 / 模型）。
 *
 * 与 StubData.ets 同一立场：这是**明确的临时数据源**，
 * 与真实数据源实现同一组呈现层契约，接入真实连接时只替换数据来源。
 */

import {
  NodeKind,
  PreviewKind,
  WorkspaceItem,
  FileNode,
  FilePreview
} from './Workspace';
import {
  AboutInfo,
  CredentialItem,
  DiagReport,
  HostRecord,
  ModelOption,
  ModelSelection,
  PluginItem,
  SettingChoice,
  SettingGroup,
  SettingItem,
  SettingKind,
  SettingOrigin,
  SettingValueType,
  DiagEntry
} from './Settings';
import { supportedVersionsText, tableStats, upstreamCapturedAt } from 'dshcompat';
import type { TableStats } from 'dshcompat';

const BASE: number = 1757491200000;
function at(minutesAgo: number): number {
  return BASE - minutesAgo * 60 * 1000;
}

function file(name: string, path: string, size: number, deliverable: boolean): FileNode {
  return {
    name: name, path: path, kind: NodeKind.FILE, size: size, modifiedAt: at(60),
    loaded: true, children: [], deliverable: deliverable
  };
}

function dir(name: string, path: string, childCount: number): FileNode {
  const children: FileNode[] = [];
  for (let i = 0; i < childCount; i++) {
    children.push(file(`item-${i + 1}.ets`, `${path}/item-${i + 1}.ets`, 1024 * (i + 1), false));
  }
  return {
    name: name, path: path, kind: NodeKind.DIRECTORY, size: 0, modifiedAt: at(120),
    loaded: true, children: children, deliverable: false
  };
}

/** 演示：工作区列表 */
export function stubWorkspaces(): WorkspaceItem[] {
  return [
    {
      id: 'w-1', name: 'deepseek-harness-desktop-HarmonyOS',
      path: 'D:/dev/deepseek-harness-desktop-HarmonyOS',
      sessionCount: 2, primary: true
    },
    {
      id: 'w-2', name: 'gateway', path: 'D:/work/gateway', sessionCount: 1, primary: false
    },
    {
      id: 'w-3', name: 'docs', path: 'D:/work/docs', sessionCount: 1, primary: false
    }
  ];
}

/** 演示：文件树根（含交付物标记） */
export function stubFileTree(): FileNode[] {
  return [
    dir('AppScope', 'D:/dev/deepseek-harness-desktop-HarmonyOS/AppScope', 3),
    dir('appstate', 'D:/dev/deepseek-harness-desktop-HarmonyOS/appstate', 5),
    dir('connection', 'D:/dev/deepseek-harness-desktop-HarmonyOS/connection', 9),
    dir('dshcompat', 'D:/dev/deepseek-harness-desktop-HarmonyOS/dshcompat', 6),
    {
      name: 'docs', path: 'D:/dev/deepseek-harness-desktop-HarmonyOS/docs',
      kind: NodeKind.DIRECTORY, size: 0, modifiedAt: at(30), loaded: true, deliverable: false,
      children: [
        file('00-开发任务书.md', 'D:/dev/deepseek-harness-desktop-HarmonyOS/docs/00-开发任务书.md', 56483, true),
        file('10-协议兼容事实基线.md', 'D:/dev/deepseek-harness-desktop-HarmonyOS/docs/10-协议兼容事实基线.md', 28672, true),
        file('40-上游升级手册.md', 'D:/dev/deepseek-harness-desktop-HarmonyOS/docs/40-上游升级手册.md', 9100, true)
      ]
    },
    dir('entry', 'D:/dev/deepseek-harness-desktop-HarmonyOS/entry', 12),
    dir('tools', 'D:/dev/deepseek-harness-desktop-HarmonyOS/tools', 6),
    file('README.md', 'D:/dev/deepseek-harness-desktop-HarmonyOS/README.md', 8192, false),
    file('build-profile.json5', 'D:/dev/deepseek-harness-desktop-HarmonyOS/build-profile.json5', 1800, false)
  ];
}

/** 演示：文件预览（协议基线里的 §8 片段） */
export function stubPreview(path: string, name: string): FilePreview {
  const text: string =
    '# 8. 附录：远程端点枚举与 ArkTS 侧实测结论\n' +
    '\n' +
    '> 采集方式：tools/protocol-enum.mjs --json .research/protocol/endpoints.json\n' +
    '> 采集对象：本机 @deepseek-ai/dsh 0.1.2-rc.1（223 个 @deepseek-ai/* 包）\n' +
    '\n' +
    '## 8.4 对真实 Host 的实测矩阵\n' +
    '\n' +
    '| 场景 | 观测 | 语义 |\n' +
    '|---|---|---|\n' +
    '| 端点不存在 | **HTTP 404**（无信封） | 未认领的 endpoint |\n' +
    '| 参数不匹配 | 200 + gateway/arguments-invalid | 参数校验在网关层 |\n' +
    '| 流式走一元 | 200 + gateway/signature-invalid | 载体必须区分 |\n' +
    '| 无 cookie | **401** | Host 可信但未认证 |\n' +
    '| 伪造 Host 头 | **403** | 信任栅栏生效 |\n';
  return {
    path: path, name: name, kind: PreviewKind.MARKDOWN, text: text, language: 'markdown',
    size: text.length, truncated: false, note: ''
  };
}

// ─────────────────────────── 设置 ───────────────────────────

/**
 * 桩数据的设置项一律标记为 `SettingOrigin.LOCAL`。
 *
 * 【为什么桩数据也必须标来源】桩数据的用途是「未连接时界面仍然完整可看」，
 * 而来源标记正是界面上一等重要的信息（本地偏好 vs Host 设置）。
 * 如果桩数据留空，未连接状态下的界面会与连接后长得不一样——
 * 那就失去了桩数据的意义：它要证明的是**布局**，不是内容。
 */
function stubItem(key: string, label: string, hint: string, kind: SettingKind,
  boolValue: boolean, textValue: string, options: string[], readOnly: boolean,
  appliesLive: boolean): SettingItem {
  const choices: SettingChoice[] = [];
  for (let i = 0; i < options.length; i++) {
    choices.push({ value: options[i], label: options[i] });
  }
  return {
    key: key, label: label, hint: hint, kind: kind,
    boolValue: boolValue, textValue: textValue, options: options, choices: choices,
    readOnly: readOnly, hostWritable: !readOnly, appliesLive: appliesLive,
    origin: SettingOrigin.LOCAL, userSet: false, credentialRef: false,
    valueType: kind === SettingKind.TOGGLE ? SettingValueType.BOOLEAN : SettingValueType.STRING,
    minValue: 0, maxValue: 0, stepValue: 0, hasMin: false, hasMax: false,
    pattern: '', required: false, rawJson: '', structType: ''
  };
}

function toggle(key: string, label: string, hint: string, value: boolean): SettingItem {
  return stubItem(key, label, hint, SettingKind.TOGGLE, value, '', [], false, true);
}

function choice(key: string, label: string, hint: string, value: string, options: string[]): SettingItem {
  return stubItem(key, label, hint, SettingKind.CHOICE, false, value, options, false, true);
}

function info(key: string, label: string, hint: string, value: string): SettingItem {
  return stubItem(key, label, hint, SettingKind.INFO, false, value, [], true, false);
}

/** 演示：设置分组 */
export function stubSettings(): SettingGroup[] {
  return [
    {
      title: '通用',
      items: [
        choice('general.theme', '主题', '跟随系统或强制浅色/深色', '跟随系统', ['跟随系统', '浅色', '深色']),
        choice('general.fontScale', '字号', '影响消息与代码的字号', '100%', ['100%', '125%', '150%']),
        toggle('general.sendOnEnter', '回车发送',
          '开启后回车直接发送，Shift+回车换行；关闭则相反', true),
        toggle('general.showReasoning', '默认展开思考过程',
          '关闭时思考过程折叠为一行「已思考 N 秒」', false),
        toggle('general.reduceMotion', '减弱动效',
          '关闭流式光标与页面切换动效（无障碍）', false)
      ]
    },
    {
      title: '通知',
      items: [
        toggle('notify.approval', '审批请求通知', '高优先级渠道，可绕过静默时段', true),
        toggle('notify.question', '提问通知', '高优先级渠道', true),
        toggle('notify.turnDone', '轮次完成通知', '普通优先级', true),
        toggle('notify.failure', '失败与中断通知', '普通优先级，红色标识', true),
        toggle('notify.connection', '连接断开通知', '低优先级、静默', false)
      ]
    },
    {
      title: '会话与数据',
      items: [
        toggle('session.offlineCache', '离线缓存最近会话',
          '缓存最近 50 条会话，飞行模式下可读（D1 G5）', true),
        info('session.cacheSize', '当前缓存占用', '可在诊断页清理', '12.4 MB'),
        toggle('session.queueOffline', '离线时排队发送',
          '连接恢复后按序提交，不重复发送', true)
      ]
    }
  ];
}

/** 演示：凭据（只呈现状态，不含值） */
export function stubCredentials(): CredentialItem[] {
  return [
    { ref: 'DEEPSEEK_API_KEY', configured: false, writable: true, source: '', interactive: true },
    { ref: 'BROWSER_SESSION', configured: true, writable: false, source: 'file', interactive: false }
  ];
}

/** 演示：插件清单 */
export function stubPlugins(): PluginItem[] {
  const names: string[] = [
    'cordis:include', '@deepseek-ai/cordis-plugin-timer', '@deepseek-ai/cordis-plugin-hmr',
    '@deepseek-ai/dsh-llm', '@deepseek-ai/dsh-session', '@deepseek-ai/dsh-host-webserver',
    '@deepseek-ai/dsh-client-connection', '@deepseek-ai/dsh-api-gateway',
    '@deepseek-ai/dsh-api-session-controller', '@deepseek-ai/dsh-tool-fs',
    '@deepseek-ai/dsh-tool-bash', '@deepseek-ai/dsh-tool-web'
  ];
  const out: PluginItem[] = [];
  for (let i = 0; i < names.length; i++) {
    const name: string = names[i];
    out.push({
      entryId: `include:${i + 1}`,
      moduleName: name,
      enabled: name.indexOf('hmr') < 0,
      phase: name.indexOf('hmr') < 0 ? 'active' : '',
      firstParty: name.startsWith('@deepseek-ai/')
    });
  }
  return out;
}

// ─────────────────────────── 设备与 Host ───────────────────────────

/** 演示：Host 记录 */
export function stubHosts(): HostRecord[] {
  return [
    {
      id: 'h-1', name: '本机 Host', authority: '127.0.0.1:3111', isLoopback: true,
      level: 'L0 · 直连 loopback', authorized: true, version: '0.1.2-rc.1'
    },
    {
      id: 'h-2', name: '工作站', authority: '192.168.1.20:3111', isLoopback: false,
      level: 'L1 · 加密隧道', authorized: false, version: '0.1.2-rc.1'
    }
  ];
}

// ─────────────────────────── 诊断 ───────────────────────────

/** 演示：诊断报告 */
export function stubDiagnostics(): DiagReport {
  const entries: DiagEntry[] = [
    { name: '端点', passed: true, detail: '127.0.0.1:3111 可达', advice: '' },
    { name: 'TLS', passed: true, detail: 'HTTP（dsh 默认 loopback 姿态，不设 Secure cookie）', advice: '' },
    { name: '认证', passed: true, detail: '已持有会话 cookie（dsh-auth-…）', advice: '' },
    { name: '协议', passed: true, detail: 'WebSocket 已建立；事件流 live', advice: '' },
    { name: 'Host', passed: true, detail: 'clientId=… home=D:/work', advice: '' }
  ];
  return {
    entries: entries,
    healthy: true,
    generatedAt: at(1),
    versionVerdict: 'supported',
    versionMessage: 'Host 版本 0.1.2-rc.1 在受支持矩阵内',
    versionAdvice: '',
    tableStats: '74 个端点（3 个流式）· 12 个能力',
    surface: '/api · /api/remote.mux · $events'
  };
}

/** 演示：关于页 */
/**
 * 关于信息。
 *
 * **这不是桩数据**（尽管住在 StubData2 里，因为原先的调用方只从本文件取数据）：
 * 上游版本矩阵、采集时间、端点上表规模全部**从 `dshcompat` 实时派生**。
 *
 * 为什么必须派生而不能写死：这些数字是「兼容面到底覆盖了什么」的唯一用户可见凭据。
 * 曾经硬编码过——上游基线从 0.1.2-rc.1（74 端点 / 3 流式 / 12 能力）升到
 * 0.1.5-rc.1（84 / 4 / 15）之后，页面仍在显示旧数字。
 * 那是**界面在说谎**：用户看到「74 个端点」而实际可用 84 个，排查问题会被这条假信息带偏。
 * 改为派生之后，升级上表即自动同步，不会再出现第二次。
 */
export function aboutInfo(): AboutInfo {
  const stats: TableStats = tableStats();
  return {
    appVersion: '1.0.0 (1000000)',
    supportedUpstream: supportedVersionsText(),
    compatCapturedAt: upstreamCapturedAt(),
    endpointStats: `${stats.endpoints} 个端点 / ${stats.streamEndpoints} 个流式 / ${stats.capabilities} 个能力`
  };
}

// ─────────────────────────── 模型 ───────────────────────────

/** 演示：可选模型（结构对应宿主侧模型目录端点的投影形状） */
export function stubModels(): ModelOption[] {
  return [
    {
      provider: 'deepseek-official', providerName: 'DeepSeek', modelId: 'deepseek-v4-flash',
      modelName: 'DeepSeek-V4-Flash',
      description: '快速、经济，适合聚焦任务、例行工作或并行任务',
      efforts: ['low', 'medium', 'high'], defaultEffort: 'high'
    },
    {
      provider: 'deepseek-official', providerName: 'DeepSeek', modelId: 'deepseek-v4-pro',
      modelName: 'DeepSeek-V4-Pro',
      description: '更强的推理与长上下文能力，成本更高',
      efforts: ['low', 'medium', 'high'], defaultEffort: 'medium'
    }
  ];
}

/** 演示：当前模型选择 */
export function stubModelSelection(): ModelSelection {
  return { provider: 'deepseek-official', modelId: 'deepseek-v4-flash', effort: 'high' };
}

// ─────────────────────────── 会话详情栏 ───────────────────────────

/** 详情栏分区标题 */
export interface DetailSection {
  title: string;
  /** 条数（0 = 显示空态） */
  count: number;
  /** 每行摘要 */
  lines: string[];
  /** 空态说明（D3 §4 文案纪律） */
  emptyHint: string;
}

/** 演示：详情栏分区（工具 / 子代理 / 交付物 / 目标 / 任务） */
export function stubDetailSections(): DetailSection[] {
  return [
    {
      title: '工具调用', count: 4,
      lines: ['read · 成功 · 42ms', 'edit · 成功 · 310ms', 'bash · 运行中 · 18s', 'rm -rf .research · 被拒'],
      emptyHint: '本次会话还没有工具调用'
    },
    {
      title: '子代理', count: 1,
      lines: ['reviewer · 26s · 已结束'],
      emptyHint: '本次会话还没有子代理'
    },
    {
      title: '交付物', count: 3,
      lines: ['10-协议兼容事实基线.md · 28 KB', '40-上游升级手册.md · 9 KB', 'Endpoints.ets · 26 KB'],
      emptyHint: '本次会话还没有产出文件'
    },
    {
      title: '目标', count: 1,
      lines: ['M1 协议层打通 · 第 1/2 轮 · 50%'],
      emptyHint: '本次会话还没有设定目标'
    },
    {
      title: '任务', count: 1,
      lines: ['协议探测回归 · 15 探针 · 10 成功'],
      emptyHint: '本次会话还没有后台任务'
    }
  ];
}

// ─────────────────────────── 输入区辅助 ───────────────────────────

/** 输入区 @ 引用候选 */
export interface ReferenceCandidate {
  /** 引用类型：workspace / file / skill / session */
  kind: string;
  label: string;
  /** 插入到输入框的引用文本 */
  insert: string;
  detail: string;
}

/** 演示：@ 引用候选 */
export function stubReferences(): ReferenceCandidate[] {
  return [
    {
      kind: 'workspace', label: 'deepseek-harness-desktop-HarmonyOS',
      insert: '@workspace:deepseek-harness-desktop-HarmonyOS',
      detail: 'D:/dev/deepseek-harness-desktop-HarmonyOS'
    },
    {
      kind: 'file', label: 'docs/10-协议兼容事实基线.md',
      insert: '@file:docs/10-协议兼容事实基线.md', detail: '协议事实基线 D2'
    },
    {
      kind: 'file', label: 'dshcompat/src/main/ets/Endpoints.ets',
      insert: '@file:dshcompat/src/main/ets/Endpoints.ets', detail: '端点上表（自动生成）'
    },
    {
      kind: 'skill', label: 'deveco-cli', insert: '@skill:deveco-cli',
      detail: '鸿蒙构建 / 部署 / 调试 / 文档'
    },
    {
      kind: 'session', label: '给 DSH 鸿蒙端写协议兼容层',
      insert: '@session:s-1', detail: '当前会话'
    }
  ];
}

/** 输入区斜杠命令候选（语义与 Host 侧命令集一致） */
export interface CommandCandidate {
  name: string;
  args: string;
  detail: string;
}

/** 演示：斜杠命令 */
export function stubCommands(): CommandCandidate[] {
  return [
    { name: '/compact', args: '', detail: '压缩当前会话上下文' },
    { name: '/goal', args: '<目标描述>', detail: '创建或更新本会话目标' },
    { name: '/plan', args: '', detail: '进入计划模式' },
    { name: '/feedback', args: '<内容>', detail: '对最近一次回答给出反馈' },
    { name: '/clear', args: '', detail: '清空会话视图（不删除历史）' },
    { name: '/model', args: '<模型>', detail: '切换模型' }
  ];
}
