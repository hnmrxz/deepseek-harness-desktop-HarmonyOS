/**
 * 上游字段别名表与常用 endpoint 便捷入口。
 *
 * 存在理由（回答「方便适配上游升级」）：
 *   投影层需要按字段名取值，而上游可能改名。把「候选名列表」集中在本文件后，
 *   上游改名时只改这里；投影层与 UI 无需改动。
 *   别名顺序 = 优先匹配顺序；通常把当前实测名放第一位。
 *
 * 维护纪律：新增别名必须来自实测或上游源码，不允许凭猜测堆砌
 * （否则会把「字段不存在」误判成「值就是空」）。
 */

import { FieldAliases } from './CompatTypes';
import { buildArgs } from './CompatIndex';

/**
 * 字段别名表类型。
 *
 * 注意：ArkTS 禁止交叉类型（arkts-no-intersection-types），
 * 因此这里用「继承 FieldAliases 的具名接口」表达，而不是 `FieldAliases & Record<...>`。
 */
export interface FieldAliasTable extends FieldAliases {
  /** 会话 id */
  id: string[];
  /** 会话标题 */
  title: string[];
  /** 工作目录 */
  cwd: string[];
  /** 最近活动时间 */
  updatedAt: string[];
  /** 创建时间 */
  createdAt: string[];
  /** 是否运行中 */
  running: string[];
}

/** 会话列表项的字段别名（D2 §8.5 的实际返回结构 + 历史名称容忍） */
export const FIELD_ALIASES: FieldAliasTable = {
  /** 集合容器键 */
  list: ['items', 'sessions', 'data'],
  id: ['id', 'sessionId', 'sid'],
  title: ['title', 'name', 'summary'],
  cwd: ['cwd', 'workspace', 'workspacePath', 'directory'],
  updatedAt: ['updatedAt', 'lastActivityAt', 'lastActiveAt', 'mtime'],
  createdAt: ['createdAt', 'ctime'],
  running: ['running', 'isRunning', 'active']
};

// ─────────────────── 常用 endpoint（避免在各处写字面量） ───────────────────

/** 会话列表（可取消；参数为 `_request`） */
export const SESSION_LIST_ENDPOINT: string = 'session/list';
/** 会话创建 */
export const SESSION_CREATE_ENDPOINT: string = 'session/create';
/** 发送提示词 */
export const SESSION_PROMPT_ENDPOINT: string = 'session/prompt';
/** 会话轨迹流（**流式**，必须走 mux 载体） */
export const SESSION_FOLLOW_ENDPOINT: string = 'session/follow';
/** 审批/提问控制流（**流式**） */
export const SESSION_CONTROL_ENDPOINT: string = 'session/control';
/** 设置描述（无参数） */
export const SETTINGS_DESCRIBE_ENDPOINT: string = 'settings/describe';
/** 模型目录（无参数，只读，适合作连通性探测） */
export const MODEL_CATALOG_ENDPOINT: string = 'session/modelCatalog';
/** 插件清单（无参数，只读） */
export const PLUGIN_INVENTORY_ENDPOINT: string = 'pluginInventory/list';
/** 凭据描述 */
export const CREDENTIALS_DESCRIBE_ENDPOINT: string = 'credentials/describe';

/** 只读探测端点（用于连通性与能力探测；均为无副作用调用） */
export const READONLY_PROBE_ENDPOINTS: string[] = [
  MODEL_CATALOG_ENDPOINT,
  PLUGIN_INVENTORY_ENDPOINT,
  SETTINGS_DESCRIBE_ENDPOINT
];

/**
 * 诊断页「协议旁路日志」的演示行。
 *
 * 放在兼容面而不是 UI：这些行展示的是**上游端点名**，
 * 属于上游知识；UI 不得自行拼写（D5 §1 架构约束）。
 * 接入真实连接后由连接层的 trace 记录替换。
 */
export function demoTraceLines(): string[] {
  return [
    `rpc  ${MODEL_CATALOG_ENDPOINT}  41ms  ok`,
    `rpc  ${PLUGIN_INVENTORY_ENDPOINT}  168ms  ok`,
    `rpc  ${SETTINGS_DESCRIBE_ENDPOINT}  10ms  ok`,
    'ws   frame item (128B)  stream=events',
    'ws   frame ready  clientId=…'
  ];
}

/** 会话列表的 args 载荷（参数形态由生成上表决定，禁止按方法名猜） */
export function sessionListArgs(body: Object): Object | undefined {
  return buildArgs(SESSION_LIST_ENDPOINT, body);
}

/** 任意 endpoint 的 args 载荷 */
export function argsFor(endpoint: string, body: Object): Object | undefined {
  return buildArgs(endpoint, body);
}
