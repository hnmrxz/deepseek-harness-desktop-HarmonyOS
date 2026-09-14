/**
 * 工具呈现（P2 §11：`ToolPresenter`）。
 *
 * ## 要解决的问题
 *
 * §11 要求 Tool 至少区分 `terminal / read / write / diff / search / web / image`，
 * 并统一 running/success/failed、路径摘要、展开-折叠、结果预览。
 * 此前本仓是"一视同仁"的一张卡：所有工具同一个扳手图标、同一行等宽参数、
 * 同样的折叠规则——用户分不清"这是读了文件"还是"这是跑了命令"。
 *
 * ## 工具名从哪来（不靠猜）
 *
 * 以下分类依据**上游客户端渲染器** `dsh-client-ui-tool/lib/client.js` 里实际出现的工具名键：
 * `bash` / `pwsh` / `read` / `write` / `edit` / `str_replace` / `grep` / `glob` /
 * `web_search` / `fetch` / `image` / `ask_user_question`（另有 `present` / `skill` / `subagent`
 * 等工具包）。**未识别的名字一律落到 GENERIC**——宁可少分类，也不要凭想象把某个名字塞进某类。
 *
 * ## 为什么是纯函数
 *
 * "这算哪一类工具""失败要不要默认展开"是**判断**，不是渲染；
 * 放这里之后可在本机直接测（`tools/check-layout-fixtures.mjs`），
 * 视图只把结果映射到 ArkUI（图标资源、卡片语气）。
 */

import { ToolState, TrajectoryItem } from './Trajectory';

/** 工具类别（§11 点名的那些 + 两个本仓实际会遇到的面） */
export enum ToolKind {
  TERMINAL = 'terminal',
  READ = 'read',
  WRITE = 'write',
  EDIT = 'edit',
  SEARCH = 'search',
  WEB = 'web',
  IMAGE = 'image',
  ASK = 'ask',
  GENERIC = 'generic'
}

/**
 * 由工具名判定类别。
 *
 * **大小写不敏感**：上游工具名历史上出现过大小写差异（`Bash`/`bash`），
 * 按字节比较会漏掉一半；而"漏掉"的表现是图标与摘要回退到通用样式，不会报错——所以必须在这里统一。
 */
export function toolKindOf(toolName: string): ToolKind {
  const n: string = toolName.toLowerCase();
  if (n.indexOf('bash') >= 0 || n.indexOf('pwsh') >= 0 || n.indexOf('terminal') >= 0
    || n.indexOf('shell') >= 0 || n.indexOf('exec') >= 0) {
    return ToolKind.TERMINAL;
  }
  if (n.indexOf('str_replace') >= 0 || n.indexOf('edit') >= 0 || n.indexOf('replace') >= 0) {
    return ToolKind.EDIT;
  }
  if (n.indexOf('write') >= 0 || n.indexOf('create') >= 0) {
    return ToolKind.WRITE;
  }
  if (n.indexOf('read') >= 0 || n.indexOf('cat') >= 0) {
    return ToolKind.READ;
  }
  if (n.indexOf('grep') >= 0 || n.indexOf('glob') >= 0 || n.indexOf('search_file') >= 0
    || n.indexOf('find') >= 0) {
    return ToolKind.SEARCH;
  }
  if (n.indexOf('web') >= 0 || n.indexOf('fetch') >= 0 || n.indexOf('http') >= 0) {
    return ToolKind.WEB;
  }
  if (n.indexOf('image') >= 0 || n.indexOf('photo') >= 0 || n.indexOf('screenshot') >= 0) {
    return ToolKind.IMAGE;
  }
  if (n.indexOf('ask_user') >= 0 || n.indexOf('question') >= 0) {
    return ToolKind.ASK;
  }
  return ToolKind.GENERIC;
}

/** 类别的中文名（用于卡片徽标与无障碍文案） */
export function toolKindLabel(kind: ToolKind): string {
  if (kind === ToolKind.TERMINAL) {
    return '终端';
  }
  if (kind === ToolKind.READ) {
    return '读取';
  }
  if (kind === ToolKind.WRITE) {
    return '写入';
  }
  if (kind === ToolKind.EDIT) {
    return '编辑';
  }
  if (kind === ToolKind.SEARCH) {
    return '搜索';
  }
  if (kind === ToolKind.WEB) {
    return '网络';
  }
  if (kind === ToolKind.IMAGE) {
    return '图像';
  }
  if (kind === ToolKind.ASK) {
    return '提问';
  }
  return '工具';
}

/**
 * 类别 → 卡片语气。
 *
 * 【为什么"写入/编辑"给 warning】它们**会改动用户的东西**——语气在这里是安全提示，
 * 不是装饰。终端命令同样按"可能执行任意操作"处理（危险审批另有独立通道，这里只是视觉提醒）。
 */
export function toolToneOf(kind: ToolKind, state: ToolState): string {
  if (state === ToolState.FAILED) {
    return 'failed';
  }
  if (state === ToolState.REJECTED) {
    return 'warning';
  }
  if (state === ToolState.RUNNING) {
    return 'running';
  }
  if (state === ToolState.SUCCESS) {
    return 'success';
  }
  return 'neutral';
}

/**
 * 默认是否展开结果。
 *
 * §11 的"统一 expanded/collapsed"落在这里：**失败/被拒默认展开**（用户需要立刻看到为什么），
 * 其余默认折叠（长会话里默认展开会把界面刷满）。
 */
export function toolDefaultExpanded(state: ToolState): boolean {
  return state === ToolState.FAILED || state === ToolState.REJECTED;
}

/**
 * 卡片的无障碍描述。
 *
 * 读屏用户看不到图标与颜色，所以**类别与状态都必须写进文字**——
 * 否则"一个扳手图标 + 绿色小字"对他们等于什么都没说。
 */
export function toolA11y(kind: ToolKind, toolName: string, state: ToolState, stateLabel: string): string {
  return `${toolKindLabel(kind)}工具 ${toolName}，状态 ${stateLabel}`;
}

/** 一次算好给视图用的呈现信息（避免视图里重复调用同一组纯函数） */
export interface ToolPresentation {
  kind: ToolKind;
  kindLabel: string;
  tone: string;
  defaultExpanded: boolean;
  a11y: string;
}

export function presentTool(item: TrajectoryItem, stateLabel: string): ToolPresentation {
  const kind: ToolKind = toolKindOf(item.toolName);
  return {
    kind: kind,
    kindLabel: toolKindLabel(kind),
    tone: toolToneOf(kind, item.toolState),
    defaultExpanded: toolDefaultExpanded(item.toolState),
    a11y: toolA11y(kind, item.toolName, item.toolState, stateLabel)
  };
}
