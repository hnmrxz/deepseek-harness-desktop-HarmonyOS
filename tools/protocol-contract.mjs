/**
 * 从 dsh 的**生成调用描述符**中提取权威的 endpoint 调用契约。
 *
 * 依据：`@deepseek-ai/dsh-api-remotes/lib/client.js` 与各包的 `lib/client.js` 内含
 * 「generated InvocationDescriptor」对象，形如：
 *   {
 *     id: "@deepseek-ai/dsh-api-session-controller#session/list",
 *     service, namespace, method,
 *     invocation: { kind: "direct" | "scoped" },
 *     parameters: [ { name, wire, source, codec }, ... ],
 *     cancellation: { parameter: "signal" },   // 可选
 *     result: { mode, typeSymbol },
 *     sourceLocation: { file, line, column }
 *   }
 *
 * 这是**唯一权威**的调用契约来源：参数名（含 `_request` / `request` 这类包装名）、
 * 是否可取消、返回类型符号，全部取自此处——比反推方法名可靠得多。
 *
 * 用法：node tools/protocol-contract.mjs [--json <outfile>]
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const DSH_NM = process.env.DSH_NODE_MODULES
  ?? 'C:\\Users\\aotian\\AppData\\Roaming\\io.github.hairyf.deepseek-harness-desktop\\dependencies\\dsh\\node_modules';

const jsonIdx = process.argv.indexOf('--json');
const jsonOut = jsonIdx >= 0 ? process.argv[jsonIdx + 1] : undefined;

function walk(dir, acc) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const e of entries) {
    if (e.name === 'node_modules' || e.name === '.git') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (e.isFile() && e.name.endsWith('.js')) acc.push(p);
  }
  return acc;
}

/** 用括号配对从 id 起始位置切出一个完整的 `{...}` 对象字面量文本 */
function sliceObject(src, start) {
  let depth = 0;
  let i = start;
  let inString = false;
  let quote = '';
  let escaped = false;
  for (; i < src.length; i++) {
    const ch = src[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === '\\') escaped = true;
      else if (ch === quote) inString = false;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === '`') {
      inString = true;
      quote = ch;
      continue;
    }
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) return src.slice(start, i + 1);
    }
  }
  return undefined;
}

/** 在对象文本中按深度安全地找某个顶层键的值（字符串感知） */
function topLevelValue(objText, key) {
  let depth = 1;
  let inString = false;
  let quote = '';
  let escaped = false;
  for (let i = 1; i < objText.length - 1; i++) {
    const ch = objText[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === '\\') escaped = true;
      else if (ch === quote) inString = false;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === '`') {
      inString = true;
      quote = ch;
      continue;
    }
    if (ch === '{' || ch === '[') {
      depth++;
      continue;
    }
    if (ch === '}' || ch === ']') {
      depth--;
      continue;
    }
    if (depth === 1 && objText.startsWith(key, i)) {
      const before = objText[i - 1];
      if (before !== undefined && /[A-Za-z0-9_$]/.test(before)) continue;
      let j = i + key.length;
      while (j < objText.length && /\s/.test(objText[j])) j++;
      if (objText[j] !== ':') continue;
      j++;
      while (j < objText.length && /\s/.test(objText[j])) j++;
      const start = j;
      if (objText[j] === '{' || objText[j] === '[') {
        let d = 0;
        let s = false;
        let q = '';
        let esc = false;
        for (; j < objText.length; j++) {
          const c = objText[j];
          if (s) {
            if (esc) esc = false;
            else if (c === '\\') esc = true;
            else if (c === q) s = false;
            continue;
          }
          if (c === '"' || c === "'" || c === '`') { s = true; q = c; continue; }
          if (c === '{' || c === '[') d++;
          else if (c === '}' || c === ']') { d--; if (d === 0) { j++; break; } }
        }
        return objText.slice(start, j);
      }
      // 标量值
      let end = j;
      while (end < objText.length && !/[,}\]]/.test(objText[end])) end++;
      return objText.slice(start, end).trim();
    }
  }
  return undefined;
}

const scope = join(DSH_NM, '@deepseek-ai');
const packages = readdirSync(scope, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name);

const descriptors = [];
const seen = new Set();

for (const pkg of packages) {
  const files = walk(join(scope, pkg), []);
  for (const file of files) {
    let src;
    try {
      src = readFileSync(file, 'utf8');
    } catch {
      continue;
    }
    const re = /\{\s*id:\s*"([^"]+)"\s*,\s*service:\s*"([^"]*)"\s*,\s*namespace:\s*"([^"]*)"\s*,\s*method:\s*"([^"]*)"/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      const id = m[1];
      if (seen.has(id)) continue;
      const objText = sliceObject(src, m.index);
      if (objText === undefined) continue;
      seen.add(id);
      const invocationText = topLevelValue(objText, 'invocation') ?? '';
      const kind = (invocationText.match(/kind:\s*"([^"]+)"/) ?? [, 'unknown'])[1];
      const cancelText = topLevelValue(objText, 'cancellation');
      const paramsText = topLevelValue(objText, 'parameters') ?? '[]';
      const params = [];
      const pre = /name:\s*"([^"]*)"\s*,\s*wire:\s*"([^"]*)"/g;
      let pm;
      while ((pm = pre.exec(paramsText)) !== null) params.push({ name: pm[1], wire: pm[2] });
      const resultText = topLevelValue(objText, 'result') ?? '';
      const resultSymbol = (resultText.match(/typeSymbol:\s*"([^"]+)"/) ?? [, ''])[1];
      const locText = topLevelValue(objText, 'sourceLocation') ?? '';
      const locFile = (locText.match(/file:\s*"([^"]+)"/) ?? [, ''])[1];
      const locLine = (locText.match(/line:\s*(\d+)/) ?? [, ''])[1];
      descriptors.push({
        id, pkg, service: m[2], namespace: m[3], method: m[4],
        kind,
        cancellable: cancelText !== undefined,
        params,
        resultSymbol,
        source: locFile === '' ? '' : `${locFile}:${locLine}`
      });
    }
  }
}

descriptors.sort((a, b) => (a.namespace + '/' + a.method).localeCompare(b.namespace + '/' + b.method));

console.log(`# dsh endpoint 调用契约（${descriptors.length} 个 endpoint）\n`);
const byNs = new Map();
for (const d of descriptors) {
  if (!byNs.has(d.namespace)) byNs.set(d.namespace, []);
  byNs.get(d.namespace).push(d);
}
for (const ns of [...byNs.keys()].sort()) {
  console.log(`## ${ns}`);
  for (const d of byNs.get(ns)) {
    const p = d.params.length === 0 ? '(无参数)' : d.params.map((x) => x.wire).join(', ');
    console.log(`  ${d.method.padEnd(24)} ${d.kind.padEnd(8)} ${d.cancellable ? 'cancel' : '      '}  params: ${p}`);
  }
  console.log('');
}

if (jsonOut) {
  writeFileSync(jsonOut, JSON.stringify(descriptors, null, 2), 'utf8');
  console.log(`已写入 ${jsonOut}`);
}
