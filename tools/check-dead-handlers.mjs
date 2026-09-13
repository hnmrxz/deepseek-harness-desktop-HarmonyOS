/**
 * 死按钮扫描器（E130）。
 *
 * 【为什么需要它】"界面上有、点了没反应"是本项目反复出现的缺陷形态：
 * 早期是「添加」工作区（死入口）、「市场」按钮、`onPickModel` 空实现……
 * 每一次都是**靠人眼在截图里发现**的。这个脚本把这件事变成可复跑的检查：
 * 扫出所有**空箭头函数体**（`=> {}` / 只含注释）与**空方法体**，
 * 它们在 UI 里几乎总意味着一个点了没反应的控件。
 *
 * 用法：node tools/check-dead-handlers.mjs [--all]
 *   默认只报 UI 目录（entry/platform 的 ets 视图与页面）；
 *   `--all` 扫全部 ets 源码（含 appstate/dshcompat，那里的空实现可能是**有意**的默认值）。
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.cwd();
const ALL = process.argv.includes('--all');
const ROOTS = ALL
  ? ['entry/src/main/ets', 'platform/src/main/ets', 'appstate/src/main/ets', 'dshcompat/src/main/ets']
  : ['entry/src/main/ets', 'platform/src/main/ets'];

/** 递归收集 .ets 文件 */
function filesUnder(dir) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const name of entries) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) {
      out.push(...filesUnder(full));
    } else if (name.endsWith('.ets')) {
      out.push(full);
    }
  }
  return out;
}

/**
 * 去掉注释与字符串字面量，避免把 `=> {}` 写在注释里误报。
 *
 * 【必须保留换行】第一版把块注释整段换成空格 ⇒ 行号与原文错位，
 * 于是报出一堆"空实现"其实指向 `@Prop`、注释行（假阳性比漏报更糟：
 * 它会让人不再相信这份报告）。这里按字符替换、**保留每个 `\n`**。
 */
function stripNoise(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/\/\/[^\n]*/g, '');
}

const hits = [];
for (const dir of ROOTS) {
  for (const file of filesUnder(join(ROOT, dir))) {
    const raw = readFileSync(file, 'utf8');
    const clean = stripNoise(raw);
    const lines = clean.split('\n');
    for (let i = 0; i < lines.length; i++) {
      // 空箭头函数体：`=> {}` 或 `=> {` 紧跟 `}`
      if (/=>\s*\{\s*\}/.test(lines[i])) {
        hits.push({ file, line: i + 1, kind: '空箭头函数体', text: raw.split('\n')[i].trim() });
        continue;
      }
      if (/=>\s*\{\s*$/.test(lines[i])) {
        const next = (lines[i + 1] ?? '').trim();
        if (next === '}' || next === '},' || next === '};') {
          hits.push({ file, line: i + 1, kind: '空箭头函数体（跨行）', text: raw.split('\n')[i].trim() });
        }
      }
      // 空方法体：`name(...) {` 紧跟 `}`
      if (/^\s{2,}[a-zA-Z_$][\w$]*\([^)]*\)\s*\{\s*$/.test(lines[i])) {
        const next = (lines[i + 1] ?? '').trim();
        if (next === '}') {
          hits.push({ file, line: i + 1, kind: '空方法体', text: raw.split('\n')[i].trim() });
        }
      }
    }
  }
}

const rel = (f) => relative(ROOT, f).replace(/\\/g, '/');
if (hits.length === 0) {
  console.log(`死按钮扫描：未发现空实现（范围 ${ROOTS.join(', ')}）`);
  process.exit(0);
}
console.log(`死按钮扫描：发现 ${hits.length} 处空实现（需逐条判断：空实现常常就是"点了没反应"）`);
for (const h of hits) {
  console.log(`  ${rel(h.file)}:${h.line}  [${h.kind}]  ${h.text.slice(0, 90)}`);
}
process.exit(1);
