#!/usr/bin/env node
/*
 * 门禁：**图标不得按形态分叉**。
 *
 * 【口径】PC / 平板 / 2in1 与官方 1:1 复刻；**手机端做适应性优化，但图标与整体风格必须一致**。
 * 也就是说：`LayoutMode` 可以决定**文字、宽度、可见性、动作清单**，
 * 但**不可以决定用哪个图标**——那会立刻让"手机端和桌面端不是同一个产品"。
 *
 * 【为什么做成门禁】2026-09-17 做过一次全量核对：整个 UI 层里所有与形态有关的分支
 * （见下）里**没有一个**在挑图标——这条一致性当时是"恰好成立"的。
 * 门禁的作用是让它**继续**成立：以后有人在手机分支里换一个图标，这里会红。
 *
 * 检查方式（刻意做窄，宁可漏报也不要误报）：
 *   同一行里同时出现 `sys.symbol.` 与形态判据（`layoutMode` / `LayoutMode` / `mode ===`）
 *   ⇒ 报错。**只看同一行**，因为"图标按形态分叉"最自然的写法就是三元表达式写在一行里。
 *
 * 用法：node tools/check-icon-parity.mjs
 * 退出码：0 = 无分叉；1 = 有分叉（打印位置）。
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SCAN_DIRS = ['entry/src/main/ets', 'appstate/src/main/ets', 'platform/src/main/ets'];

/** 形态判据的写法（与代码里实际用的一致） */
const MODE_MARKERS = ['layoutMode', 'LayoutMode', 'mode ===', 'mode !=='];

function walk(dir, out) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) {
      walk(full, out);
    } else if (name.endsWith('.ets')) {
      out.push(full);
    }
  }
  return out;
}

const bad = [];
let scanned = 0;
for (const rel of SCAN_DIRS) {
  const abs = join(ROOT, rel);
  if (!existsSync(abs)) {
    continue;
  }
  for (const file of walk(abs, [])) {
    scanned++;
    const lines = readFileSync(file, 'utf8').split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (!line.includes('sys.symbol.')) {
        continue;
      }
      // 注释行不算（本仓大量注释在解释"为什么不用某个图标"）
      const trimmed = line.trim();
      if (trimmed.startsWith('*') || trimmed.startsWith('//') || trimmed.startsWith('/*')) {
        continue;
      }
      for (const marker of MODE_MARKERS) {
        if (line.includes(marker)) {
          bad.push(`${file.slice(ROOT.length + 1).replace(/\\/g, '/')}:${i + 1}  [${marker}]  ${trimmed}`);
          break;
        }
      }
    }
  }
}

console.log(`扫描 ${scanned} 个 .ets 文件 · 判据：同一行同时出现 sys.symbol 与形态条件`);

if (bad.length > 0) {
  console.error('');
  console.error(`❌ ${bad.length} 处图标按形态分叉（手机端与桌面端会用不同的图标）：`);
  for (const b of bad) {
    console.error(`  ${b}`);
  }
  console.error('');
  console.error('处置：图标必须与形态无关。形态可以决定文字、宽度、可见性与动作清单，但不决定图标。');
  process.exit(1);
}

console.log('✅ 无分叉：没有任何一处按形态挑图标（文字/宽度/可见性/动作清单分叉是允许的）。');
