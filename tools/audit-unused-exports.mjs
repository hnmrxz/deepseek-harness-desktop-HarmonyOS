/**
 * 审计：`appstate` / `dshcompat` 对外导出的符号里，**哪些在 `entry`（UI）里从未被引用**。
 *
 * 存在理由：本项目反复出现同一类缺陷——**协议层与状态层实现好了，但界面从未接上**。
 * 已发生的实例：Host 侧待发队列（`session/updateQueue`）、会话分叉（`session/fork`）、
 * 内联图片片段（`imagePart`）、附件上传（`fileUploads/upload`）。
 * 它们的共同点是"代码在、门禁绿、功能不可达"，而不接设备就看不出来。
 *
 * 这个脚本把这类缺口一次列全，不依赖模拟器：把「导出了但没人用」当作**怀疑清单**，
 * 再逐条判断是"该接的没接"还是"给测试/未来预留的"。
 *
 * 用法：node tools/audit-unused-exports.mjs
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/** 递归收集目录下所有 .ets 文件的文本 */
function collect(dir) {
  const out = [];
  const stack = [dir];
  while (stack.length > 0) {
    const cur = stack.pop();
    for (const name of readdirSync(cur)) {
      const p = join(cur, name);
      if (statSync(p).isDirectory()) {
        stack.push(p);
      } else if (name.endsWith('.ets')) {
        out.push(readFileSync(p, 'utf8'));
      }
    }
  }
  return out.join('\n');
}

/** 从 barrel（Index.ets）里抽出所有导出名（值导出 + 类型导出，忽略 `as` 重命名） */
function exportedNames(barrelPath) {
  const text = readFileSync(barrelPath, 'utf8');
  const names = new Set();
  const blocks = text.split('export ');
  for (const block of blocks) {
    // 只看 `export { ... }` / `export type { ... }`
    const open = block.indexOf('{');
    const close = block.indexOf('}');
    if (open < 0 || close < 0 || close < open) {
      continue;
    }
    const inner = block.substring(open + 1, close);
    for (let raw of inner.split(',')) {
      raw = raw.trim();
      if (raw.length === 0) {
        continue;
      }
      // `X as Y` → 外部可见名是 Y
      const asParts = raw.split(/\s+as\s+/);
      const name = asParts[asParts.length - 1].trim();
      if (/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name)) {
        names.add(name);
      }
    }
  }
  return names;
}

const entryText = collect('entry/src/main/ets');
const targets = [
  ['appstate', 'appstate/src/main/ets/Index.ets'],
  ['dshcompat', 'dshcompat/src/main/ets/Index.ets']
];

let total = 0;
for (const [label, barrel] of targets) {
  const names = exportedNames(barrel);
  const unused = [];
  for (const n of names) {
    // 用词边界匹配，避免 `queue` 命中 `queued`
    const re = new RegExp(`\\b${n.replace(/\$/g, '\\$')}\\b`);
    if (!re.test(entryText)) {
      unused.push(n);
    }
  }
  unused.sort();
  console.log(`\n=== ${label}：导出 ${names.size} 个，entry 未引用 ${unused.length} 个 ===`);
  // 分组打印，便于逐条判断
  for (let i = 0; i < unused.length; i += 4) {
    console.log('  ' + unused.slice(i, i + 4).join('  '));
  }
  total += unused.length;
}
console.log(`\n合计未引用 ${total} 个。注意：这是**怀疑清单**，不是缺陷清单——`);
console.log('测试专用/预留的符号也会落在这里，判断标准是"用户能不能触达该功能"。');
