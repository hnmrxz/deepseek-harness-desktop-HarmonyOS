#!/usr/bin/env node
/*
 * 门禁：代码里用到的 `sys.symbol.*` 必须在系统符号清单里真的存在。
 *
 * 【为什么必须有】图标名写错**不会**让构建变红——它换来的是一个**空白按钮**，
 * 只有在设备上才看得出来（本仓的 E-symbol 教训）。而"猜一个名字"是很容易发生的动作，
 * 因为它看起来跟写 `sys.color.*` 没什么区别。
 *
 * 2026-09-17 用这份清单做过一次全量核对：`entry` / `appstate` / `platform` 三处共 32 个
 * 不同的符号，**全部命中**。也就是说现在是对的——这份门禁的作用是**让它一直是对的**，
 * 特别是手机端"适应性优化"要换图标的时候。
 *
 * 顺带留下两条**不存在**的名字，避免以后再猜：`command`、`terminal`、`shield`。
 *
 * 权威清单来自 DevEco SDK：`.../openharmony/ets/build-tools/ets-loader/sysResource.js`
 * （本机 7251 个符号）。找不到它时**退出码 3 = 没跑成**，而不是"通过"——
 * 与 `check-layout-fixtures.mjs` 同一个口径：环境缺失不等于检查通过。
 *
 * 用法：node tools/check-symbols.mjs
 * 退出码：0 = 全部命中；1 = 有名字不在清单里；3 = 找不到符号清单（没跑成）
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SCAN_DIRS = ['entry/src/main/ets', 'appstate/src/main/ets', 'platform/src/main/ets'];

/** 候选清单路径：环境变量优先，其次是本机 SDK 的常见位置。 */
function findSysResource() {
  const candidates = [];
  const clt = process.env.DEVECO_CLI_CLT_PATH;
  if (clt) {
    candidates.push(join(clt, 'sdk', 'default', 'openharmony', 'ets', 'build-tools', 'ets-loader', 'sysResource.js'));
    candidates.push(join(clt, 'default', 'openharmony', 'ets', 'build-tools', 'ets-loader', 'sysResource.js'));
  }
  for (const drive of ['C:', 'D:', 'E:']) {
    candidates.push(join(drive, '\\', 'Huawei', 'DevEco Studio', 'sdk', 'default', 'openharmony',
      'ets', 'build-tools', 'ets-loader', 'sysResource.js'));
  }
  for (const c of candidates) {
    if (existsSync(c)) {
      return c;
    }
  }
  return '';
}

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

const resourcePath = findSysResource();
if (resourcePath === '') {
  console.error('环境受阻：找不到系统符号清单 sysResource.js。');
  console.error('  设 DEVECO_CLI_CLT_PATH 指向 DevEco Command Line Tools 后重跑，或确认本机装了 DevEco Studio。');
  console.error('  ⚠️ 这是"没跑成"，不是"通过"——退出码 3。');
  process.exit(3);
}

const known = new Set();
for (const m of readFileSync(resourcePath, 'utf8').matchAll(/([A-Za-z0-9_]+)\s*:\s*\d+/g)) {
  known.add(m[1]);
}

const used = new Map();
for (const rel of SCAN_DIRS) {
  const abs = join(ROOT, rel);
  if (!existsSync(abs)) {
    continue;
  }
  for (const file of walk(abs, [])) {
    const text = readFileSync(file, 'utf8');
    for (const m of text.matchAll(/sys\.symbol\.([A-Za-z0-9_]+)/g)) {
      const name = m[1];
      if (!used.has(name)) {
        used.set(name, new Set());
      }
      used.get(name).add(file.slice(ROOT.length + 1).replace(/\\/g, '/'));
    }
  }
}

const unknown = [...used.keys()].filter((n) => !known.has(n)).sort();
console.log(`符号清单：${resourcePath}`);
console.log(`扫描 ${SCAN_DIRS.length} 个目录 · 用到 ${used.size} 个不同符号 · 清单里共 ${known.size} 个`);

if (unknown.length > 0) {
  console.error('');
  console.error(`❌ 有 ${unknown.length} 个符号名不在系统清单里（写错只会得到空白图标，构建不会报错）：`);
  for (const name of unknown) {
    console.error(`  sys.symbol.${name}  <- ${[...used.get(name)].join(', ')}`);
  }
  console.error('');
  console.error('处置：在清单里挑一个真实存在的名字（别猜），或说明为什么需要它。');
  process.exit(1);
}

console.log(`✅ 全部命中：${[...used.keys()].sort().join(' / ')}`);
