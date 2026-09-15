/**
 * 零消费者导出审计（E368）：**声明了、再导出了、全仓没人用**的符号。
 *
 * ## 存在理由
 *
 * 前三轮手工量了三批"有没有消费者"（门面字段 E367、呈现判定 E366、字段无读者 E360），
 * 每一批都查出了真东西。这一轮把同一手法用到"导出符号"上：数**全仓出现次数**，
 * `≤2` 意味着"只有声明 + barrel 再导出"（= 没有任何调用点/引用点），`1` 更彻底
 * （连 barrel 都没有）。本轮据此清掉 23 个符号（含两个级联变死的类型）。
 *
 * ## 为什么是"审计"而不是"门禁"
 *
 * `Wire.ets` 是**上游协议的词汇表**：里面的形状常常先按协议写全、投影用到哪几项是后话，
 * 所以那里天然有一批"暂时没人用"的符号 —— 把它们当缺陷会让门禁天天红。
 * 门禁那一条（`check-dead-code` 规则⑤）因此带**基线**：存量登记、只拦新增。
 *
 * 【它和门禁的差别】门禁那一条认 `// dead-exempt: 理由`（有意保留的导出：文档化数据、
 * 等某个浮层落地才用的表…），审计**不认**——审计是把全量摊开给人看，拍板在人。
 *
 * 用法：
 *   node tools/audit-zero-consumer-exports.mjs            # 打印 ≤2 的全量清单
 *   node tools/audit-zero-consumer-exports.mjs --count    # 只打印数量
 */
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.cwd();
/** 语料 = 全部 .ets 模块 + `tools/`（fixture 是**真实读者**，只在 fixture 里被用的符号不算死） */
const DIRS = ['entry/src/main/ets', 'appstate/src/main/ets', 'platform/src/main/ets',
  'connection/src/main/ets', 'dshcompat/src/main/ets', 'hostruntime/src/main/ets', 'tools'];

function collect(dir) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...collect(p));
    else if (e.name.endsWith('.ets') || e.name.endsWith('.mjs')) out.push(p);
  }
  return out;
}

const files = DIRS.flatMap((d) => collect(join(ROOT, d)));
const sources = files.map((f) => ({ path: relative(ROOT, f).replace(/\\/g, '/'), text: readFileSync(f, 'utf8') }));
const corpus = sources.map((s) => s.text).join('\n');

const countOf = (name) => (corpus.match(new RegExp(`(?<![\\w$])${name}(?![\\w])`, 'g')) || []).length;

const rows = [];
for (const s of sources) {
  if (!s.path.startsWith('appstate/src/main/ets/')) continue;
  for (const m of s.text.matchAll(/^export (?:interface|type|enum|function|class|const) (\w+)/gm)) {
    rows.push({ path: s.path, name: m[1], n: countOf(m[1]) });
  }
}

/** 与门禁共用的判定：`≤2` 视为"零消费者" */
export function zeroConsumer(rowsIn) {
  return rowsIn.filter((r) => r.n <= 2);
}

if (process.argv.includes('--count')) {
  console.log(zeroConsumer(rows).length);
} else {
  const list = zeroConsumer(rows);
  console.log(`# 零消费者导出审计：appstate 导出 ${rows.length} 个，其中全仓出现 ≤2 次的 ${list.length} 个\n`);
  for (const r of list) console.log(`  ${r.n}  ${r.name}  (${r.path})`);
  console.log('\n处置：逐个看"是残留还是缺接线"——真值另有写者的删（E368），只是没人接的补接线。');
  console.log('门禁侧见 `tools/check-dead-code.mjs` 规则⑤（带基线，只拦新增）。');
}
