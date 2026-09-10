/**
 * 桩数据源（方案 2：设备到位前用桩驱动 UI）。
 *
 * 立场说明：这是**明确的临时数据源**，不是"假实现"。
 * 它与真实数据源实现同一组呈现层契约（`SessionListItem` / `TrajectoryItem` / `PendingItem`），
 * 因此接入真实连接时只需替换数据来源，组件零改动。
 *
 * 覆盖的场景（用于验证 D3 各界面规格）：
 *   - 会话列表：运行中 / 待审核 / 空闲 / 失败四种状态 + 未读
 *   - 轨迹：用户与助手消息、流式输出、思考折叠、工具成功/失败/被拒/运行中、
 *           子代理、交付物、目标进度、任务、错误
 *   - 待决：危险审批 / 常规审批 / 单选提问 / 多选提问
 */

import { SessionListItem } from './SessionList';
import {
  PendingChoice,
  PendingItem,
  PendingKind,
  RiskLevel,
  Speaker,
  ToolState,
  TrajectoryItem,
  TrajectoryKind,
  makeItem
} from './Trajectory';

/** 演示用的基准时间：让相对时间文案稳定可预期 */
const BASE: number = 1757491200000; // 2026-09-10 16:00:00 UTC 附近

function at(minutesAgo: number): number {
  return BASE - minutesAgo * 60 * 1000;
}

/** 演示会话列表 */
export function stubSessions(): SessionListItem[] {
  const raw: Record<string, Object> = {};
  const out: SessionListItem[] = [];
  out.push({
    id: 's-1', title: '给 DSH 鸿蒙端写协议兼容层', cwd: 'deepseek-harness-desktop-HarmonyOS',
    updatedAt: at(2), createdAt: at(180), running: true, blank: false, raw: raw as Object
  });
  out.push({
    id: 's-2', title: '优化会话列表的滑动性能', cwd: 'deepseek-harness-desktop-HarmonyOS',
    updatedAt: at(35), createdAt: at(300), running: false, blank: false, raw: raw as Object
  });
  out.push({
    id: 's-3', title: '排查 API 网关 401 问题', cwd: 'gateway',
    updatedAt: at(140), createdAt: at(400), running: false, blank: false, raw: raw as Object
  });
  out.push({
    id: 's-4', title: '整理鸿蒙一多适配要点', cwd: 'docs',
    updatedAt: at(60 * 25), createdAt: at(60 * 40), running: false, blank: false, raw: raw as Object
  });
  return out;
}

/** 演示轨迹（覆盖 D3 §3.2 / §3.3 的全部条目类型） */
export function stubTrajectory(): TrajectoryItem[] {
  const out: TrajectoryItem[] = [];

  const userMsg = makeItem('t-1', TrajectoryKind.MESSAGE, at(28));
  userMsg.speaker = Speaker.USER;
  userMsg.body = '帮我把协议层的单元测试补上，重点覆盖信封解析的失败分支。';
  out.push(userMsg);

  const reasoning = makeItem('t-2', TrajectoryKind.REASONING, at(27));
  reasoning.body = '先看 Envelope.ets 的解析分支：类型不符、rpcId 不匹配、result 缺失、'
    + 'ok=true 但无 value、ok=false 但 error 畸形、details 缺省。这六条都要有用例。';
  reasoning.elapsedMs = 4200;
  out.push(reasoning);

  const toolRead = makeItem('t-3', TrajectoryKind.TOOL, at(26));
  toolRead.toolName = 'read';
  toolRead.toolArgs = 'connection/src/main/ets/protocol/Envelope.ets';
  toolRead.toolState = ToolState.SUCCESS;
  toolRead.elapsedMs = 42;
  toolRead.toolOutput = '读取 118 行，解析分支已确认 6 处。';
  out.push(toolRead);

  const toolEdit = makeItem('t-4', TrajectoryKind.TOOL, at(25));
  toolEdit.toolName = 'edit';
  toolEdit.toolArgs = 'entry/src/ohosTest/ets/test/Connection.test.ets';
  toolEdit.toolState = ToolState.SUCCESS;
  toolEdit.elapsedMs = 310;
  toolEdit.toolOutput = '新增 12 条断言，覆盖 Envelope 全部失败分支。';
  out.push(toolEdit);

  const toolBuild = makeItem('t-5', TrajectoryKind.TOOL, at(23));
  toolBuild.toolName = 'bash';
  toolBuild.toolArgs = 'devecocli build --modules entry@ohosTest';
  toolBuild.toolState = ToolState.RUNNING;
  toolBuild.elapsedMs = 18000;
  toolBuild.toolOutput = 'CompileArkTS …（输出实时追加）';
  out.push(toolBuild);

  const sub = makeItem('t-6', TrajectoryKind.SUBAGENT, at(20));
  sub.subagentName = 'reviewer';
  sub.body = '检查测试断言是否都指向 D2 的具体条目，发现 2 处断言缺少依据注释。';
  sub.elapsedMs = 26000;
  out.push(sub);

  const assistantMsg = makeItem('t-7', TrajectoryKind.MESSAGE, at(18));
  assistantMsg.speaker = Speaker.ASSISTANT;
  assistantMsg.model = 'deepseek-v4-flash';
  assistantMsg.elapsedMs = 12400;
  assistantMsg.body = '已经补完协议层的失败分支测试。要点：\n\n'
    + '1. `rpcId` 不匹配按**载体级解析失败**处理（`carrier/parse`），不是业务错误；\n'
    + '2. `ok:true` 但没有 `value` 字段同样判为解析失败，但允许 `value` 显式为 `null`；\n'
    + '3. `details` 缺省时收窄为空串，**不因为 details 形状而丢弃整个业务错误**；\n'
    + '4. `gateway/*` 前缀是调用方契约错误，不应重试；域内错误码原样呈现给用户。\n\n'
    + '```ts\n// 断言依据：D2 §1.1 信封校验规则\nconst result = parseConnectionResponse(body, rpcId, endpoint);\n```';
  out.push(assistantMsg);

  const goal = makeItem('t-8', TrajectoryKind.GOAL, at(16));
  goal.title = 'M1 协议层打通';
  goal.progress = '第 1/2 轮 · 单测与编译已通过，待设备验证';
  goal.percent = 50;
  out.push(goal);

  const job = makeItem('t-9', TrajectoryKind.JOB, at(15));
  job.title = '协议探测回归';
  job.progress = '15 个探针 · 10 成功 / 3 业务失败 / 2 HTTP 404';
  job.percent = 100;
  out.push(job);

  const deliverable = makeItem('t-10', TrajectoryKind.DELIVERABLE, at(14));
  deliverable.fileName = 'docs/10-协议兼容事实基线.md';
  deliverable.fileSize = 28672;
  out.push(deliverable);

  const rejected = makeItem('t-11', TrajectoryKind.TOOL, at(12));
  rejected.toolName = 'bash';
  rejected.toolArgs = 'rm -rf .research';
  rejected.toolState = ToolState.REJECTED;
  rejected.toolOutput = '用户拒绝：该目录是调研副本，需保留。';
  rejected.expanded = true;
  out.push(rejected);

  const failed = makeItem('t-12', TrajectoryKind.TOOL, at(10));
  failed.toolName = 'web_fetch';
  failed.toolArgs = 'https://raw.githubusercontent.com/…';
  failed.toolState = ToolState.FAILED;
  failed.toolOutput = 'ERR_HOST_UNRESOLVED：域名解析到非公网地址（198.18.0.11）';
  failed.expanded = true;
  out.push(failed);

  const error = makeItem('t-13', TrajectoryKind.ERROR, at(9));
  error.body = 'HTTP 403：Host/Origin 校验失败。请勿伪造 Host 头，跨设备访问应走隧道。';
  error.expanded = true;
  out.push(error);

  const streaming = makeItem('t-14', TrajectoryKind.MESSAGE, at(1));
  streaming.speaker = Speaker.ASSISTANT;
  streaming.model = 'deepseek-v4-flash';
  streaming.streaming = true;
  streaming.body = '接下来我会把会话列表接到真实数据源：';
  out.push(streaming);

  return out;
}

/** 演示待决事项（覆盖 D3 §3.4 / §3.5 / §3.7 的排序与视觉规则） */
export function stubPending(): PendingItem[] {
  const out: PendingItem[] = [];

  const dangerousChoices: PendingChoice[] = [
    { id: 'deny', label: '拒绝', detail: '不执行该操作，并把理由回传给 agent' },
    { id: 'once', label: '仅本次允许', detail: '只批准这一次调用' },
    { id: 'policy', label: '按策略允许', detail: '把该动作加入允许策略，后续同类不再询问' }
  ];
  out.push({
    id: 'p-1',
    kind: PendingKind.APPROVAL,
    sessionId: 's-1',
    sessionTitle: '给 DSH 鸿蒙端写协议兼容层',
    title: '删除目录 .research/ref-harmony',
    detail: '该目录是社区工程的调研副本，删除后无法离线查阅其构建脚本与 patch。',
    raw: '{\n  "tool": "bash",\n  "command": "rm -rf .research/ref-harmony",\n  "cwd": "D:/dev/deepseek-harness-desktop-HarmonyOS"\n}',
    risk: RiskLevel.DANGEROUS,
    choices: dangerousChoices,
    multiSelect: false,
    allowFreeText: true,
    at: at(3)
  });

  const normalChoices: PendingChoice[] = [
    { id: 'deny', label: '拒绝', detail: '' },
    { id: 'once', label: '允许本次', detail: '' },
    { id: 'policy', label: '始终允许该命令', detail: '' }
  ];
  out.push({
    id: 'p-2',
    kind: PendingKind.APPROVAL,
    sessionId: 's-2',
    sessionTitle: '优化会话列表的滑动性能',
    title: '运行命令 devecocli build',
    detail: '在工作区内执行构建，不修改源码。',
    raw: '{\n  "tool": "bash",\n  "command": "devecocli build"\n}',
    risk: RiskLevel.NORMAL,
    choices: normalChoices,
    multiSelect: false,
    allowFreeText: false,
    at: at(7)
  });

  const questionChoices: PendingChoice[] = [
    { id: 'a', label: '先做手机单栏', detail: '覆盖最广，但需要更多手势与安全区适配' },
    { id: 'b', label: '先做平板三栏', detail: '最接近桌面体验，实现成本最低' },
    { id: 'c', label: '两种一起做', detail: '以让步链一次实现，但联调面更大' }
  ];
  out.push({
    id: 'p-3',
    kind: PendingKind.QUESTION,
    sessionId: 's-4',
    sessionTitle: '整理鸿蒙一多适配要点',
    title: '先实现哪种形态的导航？',
    detail: '这决定断点策略与组件拆分方式。',
    raw: '',
    risk: RiskLevel.NORMAL,
    choices: questionChoices,
    multiSelect: false,
    allowFreeText: true,
    at: at(11)
  });

  const multiChoices: PendingChoice[] = [
    { id: 'ios', label: 'iOS 风格卡片', detail: '' },
    { id: 'md', label: 'Material 风格', detail: '' },
    { id: 'harmony', label: 'HarmonyOS 原生风格', detail: '与系统组件观感一致' }
  ];
  out.push({
    id: 'p-4',
    kind: PendingKind.QUESTION,
    sessionId: 's-3',
    sessionTitle: '排查 API 网关 401 问题',
    title: '审批卡采用哪种视觉风格？（可多选）',
    detail: '',
    raw: '',
    risk: RiskLevel.NORMAL,
    choices: multiChoices,
    multiSelect: true,
    allowFreeText: false,
    at: at(20)
  });

  return out;
}

/** 演示用的 Host 信息（连接页展示） */
export interface StubHostInfo {
  name: string;
  authority: string;
  version: string;
  loopback: boolean;
}

export function stubHost(): StubHostInfo {
  return {
    name: '本机 Host',
    authority: '127.0.0.1:3111',
    version: '0.1.2-rc.1',
    loopback: true
  };
}
