/**
 * 会话列表模型：会话查询的返回投影。
 *
 * 事实基线（D2 §8.5）：会话查询端点由 `dshcompat` 提供（参数形态为 `_request` 包装，
 * 见该模块的生成上表）；实测返回 `{"items":[...]}`。
 *
 * 分层纪律（回答「方便适配上游升级」）：
 *   本模块**不硬编码** endpoint 名与字段名——
 *   端点与参数形态由 `dshcompat` 的 `sessionListArgs()` 决定，
 *   字段别名由 `dshcompat` 的 `FIELD_ALIASES` 提供。
 *   上游改名/改端点时只改 dshcompat，本文件不动。
 *
 * 投影策略：对每个字段按候选别名依次尝试（容忍上游改名与历史名称），
 * 缺失字段不猜测；同时保留 `raw` 供尚未建模的字段使用。
 */

import { getNumber, getRecord, getString, isRecord } from 'connection';
import { FIELD_ALIASES, SESSION_LIST_ENDPOINT, sessionListArgs } from 'dshcompat';

/** 列表项（宽松投影；未知字段保留在 raw 中） */
export interface SessionListItem {
  /** 会话 id */
  id: string;
  /** 标题（Host 侧生成的标题；缺失时上层用首条用户消息兜底） */
  title: string;
  /** 工作区路径（可空） */
  cwd: string;
  /** 最近活动时间（毫秒时间戳；无则 0） */
  updatedAt: number;
  /** 创建时间（毫秒时间戳；无则 0） */
  createdAt: number;
  /** 是否正在运行（Host 若未提供则为 false） */
  running: boolean;
  /** 原始对象（供尚未建模的字段使用） */
  raw: Object;
}

/** 列表返回 */
export interface SessionListPage {
  items: SessionListItem[];
  /** 是否可能还有更多（Host 若未提供分页信息则为 false） */
  hasMore: boolean;
}

/**
 * 从会话查询的返回投影出列表。
 * 兼容两种形态：`{ items: [...] }`（容器键由 dshcompat 的别名表提供）与直接返回数组。
 */
export function projectSessionList(value: Object | undefined): SessionListPage {
  const items: SessionListItem[] = [];
  let hasMore: boolean = false;

  if (value === undefined) {
    return { items: items, hasMore: hasMore };
  }

  let array: Object[] | undefined;
  if (Array.isArray(value)) {
    array = value as Object[];
  } else {
    // 容器键按别名表依次尝试（上游改名时只改 dshcompat）
    const listKeys: string[] = FIELD_ALIASES.list;
    for (let i = 0; i < listKeys.length; i++) {
      const container: Object | undefined = getRecord(value, listKeys[i]);
      if (container !== undefined && Array.isArray(container)) {
        array = container as Object[];
        break;
      }
    }
    const more: Object | undefined = getRecord(value, 'hasMore');
    if (typeof more === 'boolean') {
      hasMore = more as boolean;
    }
  }

  if (array === undefined) {
    return { items: items, hasMore: hasMore };
  }

  for (let i = 0; i < array.length; i++) {
    const raw: Object = array[i];
    if (!isRecord(raw)) {
      continue;
    }
    const item: SessionListItem = {
      id: pickString(raw, FIELD_ALIASES.id),
      title: pickString(raw, FIELD_ALIASES.title),
      cwd: pickString(raw, FIELD_ALIASES.cwd),
      updatedAt: pickNumber(raw, FIELD_ALIASES.updatedAt),
      createdAt: pickNumber(raw, FIELD_ALIASES.createdAt),
      running: pickBoolean(raw, FIELD_ALIASES.running),
      raw: raw
    };
    if (item.id.length === 0) {
      // 无 id 的条目无法用于后续调用，跳过而不是产出脏数据
      continue;
    }
    items.push(item);
  }

  // 默认按最近活动倒序（Host 若已排序则此步为稳定无操作）
  items.sort((a: SessionListItem, b: SessionListItem) => b.updatedAt - a.updatedAt);
  return { items: items, hasMore: hasMore };
}

/** 本轮会话查询使用的 endpoint（供调用方构造请求，避免在 UI 层写字面量） */
export function sessionListEndpoint(): string {
  return SESSION_LIST_ENDPOINT;
}

/** 会话查询的 args 载荷（形状由 dshcompat 的上表决定） */
export function sessionListPayload(body: Object): Object | undefined {
  return sessionListArgs(body);
}

/** 按候选键名取第一个非空字符串 */
function pickString(source: Object, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const value: string | undefined = getString(source, keys[i]);
    if (value !== undefined && value.length > 0) {
      return value;
    }
  }
  return '';
}

/** 按候选键名取第一个数字 */
function pickNumber(source: Object, keys: string[]): number {
  for (let i = 0; i < keys.length; i++) {
    const value: number | undefined = getNumber(source, keys[i]);
    if (value !== undefined) {
      return value;
    }
  }
  return 0;
}

/** 按候选键名取第一个布尔值 */
function pickBoolean(source: Object, keys: string[]): boolean {
  for (let i = 0; i < keys.length; i++) {
    const holder: Record<string, Object> = source as Record<string, Object>;
    const value: Object | undefined = holder[keys[i]];
    if (typeof value === 'boolean') {
      return value as boolean;
    }
  }
  return false;
}
