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
  /**
   * 会话 id。实测（0.1.5-rc.1 的 `SessionSummary`）用的名字是 `sessionId`，
   * 因此把它排在第一位——别名表的顺序是匹配优先级，把历史名排在实测名前面
   * 会让投影读到错误字段而不自知。
   */
  id: ['sessionId', 'id', 'sid'],
  /**
   * 顶层标题别名。
   *
   * 注意：**当前上游的标题不在顶层**，在 `projections.values.title`
   * （见 `RemoteEvents.PROJECTION_TITLE`）。投影层必须先读投影、再回落本表，
   * 顺序写在 `appstate/model/SessionList.ets` 的 `pickTitle()` 里。
   * 这里保留顶层候选只为容忍历史/第三方 Host。
   */
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
/** 取消当前轮次 */
export const SESSION_CANCEL_ENDPOINT: string = 'session/cancel';
/** 会话改名 */
export const SESSION_RENAME_ENDPOINT: string = 'session/rename';
/** 会话分叉（从某个事件序号起复制出一个新会话） */
export const SESSION_FORK_ENDPOINT: string = 'session/fork';
/** 修改待发队列中的某一项（编辑 / 移除 / 转为插话） */
export const SESSION_UPDATE_QUEUE_ENDPOINT: string = 'session/updateQueue';
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

// ── 0.1.5-rc.1 新增端点（升级时新增；老 Host 上会 404，由能力探测降级） ──

/** 工作区文件列表（需要的 `workspaceFileScopeId` 来自会话/工作区上下文） */
export const WORKSPACE_FILES_LIST_ENDPOINT: string = 'workspaceFiles/list';
/** 工作区文件元信息 */
export const WORKSPACE_FILES_STAT_ENDPOINT: string = 'workspaceFiles/stat';
/** 工作区文件读取（文本） */
export const WORKSPACE_FILES_READ_ENDPOINT: string = 'workspaceFiles/read';
/** 工作区文件变更流（**流式**） */
export const WORKSPACE_FILES_CHANGES_ENDPOINT: string = 'workspaceFiles/changes';
/** 附件上传（返回的引用随后放入 prompt/命令的附件字段） */
export const FILE_UPLOAD_ENDPOINT: string = 'fileUploads/upload';
/** 读取单个目标 */
export const GOALS_GET_ENDPOINT: string = 'goals/get';
/** 记录会话反馈 */
export const SESSION_FEEDBACK_RECORD_ENDPOINT: string = 'sessionFeedback/record';

/** 斜杠命令执行（参数名在上游发生过改名，见 `PARAM_ALIASES`） */
export const COMMANDS_EXECUTE_ENDPOINT: string = 'commands/execute';

/** 只读探测端点（用于连通性与能力探测；均为无副作用调用） */
export const READONLY_PROBE_ENDPOINTS: string[] = [
  MODEL_CATALOG_ENDPOINT,
  PLUGIN_INVENTORY_ENDPOINT,
  SETTINGS_DESCRIBE_ENDPOINT
];

// ─────────────────── 参数别名（容忍上游参数改名） ───────────────────

/**
 * 一个发生改名的参数。
 *
 * 存在理由（D5 升级手册「降级策略」）：
 *   上游不保证参数名稳定。0.1.5-rc.1 就把 `commands/execute` 的 `images` 改成了
 *   `submittedAttachments`——**形状没变，名字变了**，表现为 `gateway/arguments-invalid`。
 *   这类破坏性改名若靠版本号分支处理，会在「版本号读不到」时失效；
 *   而按别名重试一次是纯粹由**错误码驱动**的，与版本号无关，因此更稳。
 *
 * 用法：先用 `current` 名构造参数调用；若返回 `gateway/arguments-invalid`，
 * 用 `rebuildWithLegacyNames()` 换用 `legacy[0]` 重试一次；再失败则不再重试（是真的不兼容）。
 */
export interface ParamAlias {
  /** 当前（最新已验证上游）使用的参数名 */
  current: string;
  /** 历史参数名，按「最近的旧名优先」排列 */
  legacy: string[];
}

/**
 * endpoint → 该端点上发生过改名的参数。
 *
 * 【唯一的真实条目：`commands/execute` 的 `images` → `submittedAttachments`】
 *   这条是**实测确认**的线上改名，不是形参改名：
 *     - `0.1.2-rc.1` 契约：`params = [agentId<-agent, line<-line, images<-images]`
 *     - `0.1.5-rc.1` 契约：`params = [agentId<-agent, line<-line, submittedAttachments<-submittedAttachments]`
 *   （`wire<-name` 记法；两端点都是 `kind: direct`、`cancellable: true`，其余完全一致。）
 *   我们的上表对准 0.1.5，因此 `current` 是新名、`legacy` 是旧名。
 *
 * 【一次被推翻的「推翻」，留档为教训】
 *   升级过程中曾有一位复核者判定这条是**假阳性**，理由是「该参数的线上名在两版里都是
 *   `submittedAttachments`」。这个结论本身是错的，错因值得记住：
 *   它拿**已提交上表里的 `name`**（当时生成工具有缺陷，存的是 TS 形参名）去比
 *   **契约里的 `wire`**——两个字段不对等。而在这个端点上 `name` 与 `wire` 恰好相同，
 *   所以那次比对看起来「两边都是新名」，实则只证明了「新版的 name 等于新版的 wire」。
 *
 *   教训：**比对必须字段对字段**。跨来源比对时先确认两边取的是同一个字段，
 *   否则会得到一个看起来很有说服力的错误结论——比没有结论更危险。
 *
 * 【怎么加新条目】
 *   1. 只认**线上名**（`protocol-contract.mjs` 提取出的 `wire`）的变化；
 *   2. 必须两端都用 `wire` 比对，并记录两端原始 params 数组作为证据；
 *   3. 形参名（`name`）变化**不得**入表——它对客户端零影响。
 */
export const PARAM_ALIASES: Record<string, ParamAlias[]> = {
  'commands/execute': [{ current: 'submittedAttachments', legacy: ['images'] }]
};

/** 该 endpoint 是否存在参数别名（调用方据此决定要不要在 arguments-invalid 时重试）。 */
export function hasParamAliases(endpoint: string): boolean {
  const list: ParamAlias[] | undefined = PARAM_ALIASES[endpoint];
  return list !== undefined && list.length > 0;
}

/**
 * 用第 `round` 代旧名重建参数体。
 *
 * `round = 0` 表示使用当前名（原样返回）；`round = n > 0` 表示使用第 n 个旧名。
 * 超出旧名列表时返回 `undefined`，调用方据此停止重试。
 *
 * 注意：只处理**顶层**参数名。上游若改的是嵌套字段，需要另加机制——
 * 目前未观察到这种情况，不预先抽象。
 */
export function rebuildWithLegacyNames(endpoint: string, body: Record<string, Object>,
  round: number): Record<string, Object> | undefined {
  if (round === 0) {
    return body;
  }
  const list: ParamAlias[] | undefined = PARAM_ALIASES[endpoint];
  if (list === undefined) {
    return undefined;
  }
  const out: Record<string, Object> = {};
  const keys: string[] = Object.keys(body);
  for (let i = 0; i < keys.length; i++) {
    const key: string = keys[i];
    const renamed: string = legacyNameOf(list, key, round);
    if (renamed.length === 0) {
      return undefined;
    }
    out[renamed] = body[key];
  }
  return out;
}

/** 在第 round 代别名表中查找 key 的旧名；不存在改名时原样返回；超出代数返回空串。 */
function legacyNameOf(list: ParamAlias[], key: string, round: number): string {
  for (let i = 0; i < list.length; i++) {
    const alias: ParamAlias = list[i];
    if (alias.current !== key) {
      continue;
    }
    if (round > alias.legacy.length) {
      return '';
    }
    return alias.legacy[round - 1];
  }
  return key;
}

/** 会话列表的 args 载荷（参数形态由生成上表决定，禁止按方法名猜） */
export function sessionListArgs(body: Object): Object | undefined {
  return buildArgs(SESSION_LIST_ENDPOINT, body);
}

/** 任意 endpoint 的 args 载荷 */
export function argsFor(endpoint: string, body: Object): Object | undefined {
  return buildArgs(endpoint, body);
}

// ─────────────────── 网关边界错误码（上游事实，供上层分支判断） ───────────────────

/**
 * 上游网关的边界错误码。
 *
 * 存在理由：上层（`appstate`）需要**按错误码分支**——例如「控制流被网关拒绝」
 * 与「控制流因网络断开」要区别对待，后者才需要提示用户。
 * 但错误码是上游事实，直接在上层写字面量会违反「上游知识只允许出现在 dshcompat」，
 * 而且上游改码时会**静默失效**（判断永远为假、分支永不触发，且不报错）。
 *
 * 因此在唯一的事实落点导出常量，上层只消费常量。
 * 出处：上游 `dsh-api-gateway` 的 `TypertGatewayErrorCode`（D2 §1.1 已登记该枚举）。
 * 这里只导出**我们真正会分支**的三个，不搬运整个枚举——
 * 未被使用的常量会变成无人维护的噪声。
 */

/** 一元载体上打开了流式端点（调用方错误，绝不重试） */
export const GATEWAY_SIGNATURE_INVALID: string = 'gateway/signature-invalid';
/** 参数名与描述符不符（调用方错误，绝不重试） */
export const GATEWAY_ARGUMENTS_INVALID: string = 'gateway/arguments-invalid';
/** 参数值未通过边界校验（调用方错误，绝不重试） */
export const GATEWAY_INPUT_INVALID: string = 'gateway/input-invalid';

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
