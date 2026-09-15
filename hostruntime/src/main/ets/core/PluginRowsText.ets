/**
 * 插件启停的**用户行文本层**（E91 / E369）：只做"文本 ↔ 行数组"，零依赖。
 *
 * ─────────────────── 为什么单独一个文件 ───────────────────
 * 这一层（`serializeUserRows` / `parseUserRows`）是「启停能不能活过重启」的**唯一契约**：
 * 应用写出的文本由入口脚本**原样**拼进 `cordis.patch.yml` 的围栏块里
 * （`hostcore/app/main.js` 的 `composeUserRows`，它只搬文本、不看结构），
 * 下次启动再由本层读回来。两侧任何一侧改格式，症状都是**静默丢启停**
 * （文件还在、行数变成 0），界面与既有门禁都看不出来。
 *
 * 放进 `PluginRows.ets` 时它读不到测试 —— 那个文件要 import `@kit.CoreFileKit`
 * 等三个 ArkTS kit，fixture 编译器加载不了。搬到这里之后
 * `tools/check-layout-fixtures.mjs` 能直接执行它（含"序列化 → 解析"往返不变式）。
 */

/** 用户行文件名（相对于 profile 目录）。入口脚本按同一名字读取。 */
export const USER_ROWS_FILENAME: string = '.hdsh-plugin-rows.yml';

/** 一行用户覆盖：只表达"这个行 id 是启用还是禁用"。 */
export interface UserPluginRow {
  id: string;
  disabled: boolean;
}

/** 解析结果：**忽略的行要报出来**，不能静默丢内容。 */
export interface UserPluginRowsParse {
  rows: UserPluginRow[];
  /** 无法识别的非空行数（>0 时界面应如实提示） */
  ignored: number;
}

/** 用户行文件路径（profile 目录下）。 */
/** 用户行文件路径（profile 目录下）。 */
export function userRowsPath(profileDir: string): string {
  return `${profileDir}/${USER_ROWS_FILENAME}`;
}

/**
 * 序列化成**我们自己**的 YAML 片段。
 *
 * 只写两行一个条目，字段名与 profile 行一致（`id` / `disabled`），这样它被拼进
 * `cordis.patch.yml` 之后就是一份普通的 patch 层，人也能读、能改。
 */
export function serializeUserRows(rows: UserPluginRow[]): string {
  const out: string[] = [
    '# 端侧「插件」页维护的用户行：只写「行 id + disabled」。',
    '# 本文件由应用写入；「恢复默认」会删除它（下次启动就不再拼上这段）。',
    '# 入口脚本会把这段追加到 profile 的 cordis.patch.yml 末尾（后写覆盖先写）。',
  ];
  for (const row of rows) {
    out.push(`- id: ${row.id}`);
    out.push(`  disabled: ${row.disabled ? 'true' : 'false'}`);
  }
  out.push('');
  return out.join('\n');
}

/** 解析我们自己的片段。容错，但把无法识别的行数如实回报。 */
export function parseUserRows(text: string): UserPluginRowsParse {
  const rows: UserPluginRow[] = [];
  let ignored: number = 0;
  let current: UserPluginRow | undefined = undefined;
  for (const rawLine of text.split('\n')) {
    const line: string = rawLine.trim();
    if (line.length === 0 || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('- id:')) {
      const id: string = line.substring('- id:'.length).trim();
      if (id.length === 0) {
        ignored++;
        current = undefined;
      } else {
        current = { id: id, disabled: true };
        rows.push(current);
      }
      continue;
    }
    if (line.startsWith('disabled:') && current !== undefined) {
      const value: string = line.substring('disabled:'.length).trim().toLowerCase();
      current.disabled = value !== 'false';
      continue;
    }
    ignored++;
  }
  return { rows: rows, ignored: ignored };
}

/** 读用户行（文件不存在 = 没有用户覆盖，返回空数组而不是失败）。 */
