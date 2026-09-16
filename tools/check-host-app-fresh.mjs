#!/usr/bin/env node
/*
 * 门禁：HAP 里的 Host 入口脚本必须与 `hostcore/app/` 逐字节一致（F9 / E148①）。
 *
 * 【为什么必须有】2026-09-16 真机验收第一次装机时，设备日志里 `undici 解析钩子…` 三条
 * 一条都不出现——不是"降级"，而是 HAP 里那份 `main.js` 还是 **2026-09-14** 的旧版，
 * `undici-shim.mjs` / `undici-loader.mjs` 根本没进包。`tools/place-host-app.mjs` 只能手工跑，
 * `devecocli build` 不会替你跑，**而且当时没有任何门禁会红**。
 *
 * 这与 `docs/50` 的 E148① 是同一个坑第二次踩：改了 `hostcore/app/*` 却忘了重放，
 * 表现是"改了、构建绿、设备上没生效"——最难查的一类。
 *
 * 用法：node tools/check-host-app-fresh.mjs
 * 退出码：0 = 一致；1 = 不一致或缺失（并打印怎么修）。
 */
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'hostcore', 'app');
const DEST = join(ROOT, 'entry', 'src', 'main', 'resources', 'resfile', 'resources', 'app');
const FILES = ['main.js', 'fetch-shim.js', 'undici-shim.mjs', 'undici-loader.mjs'];

const problems = [];
for (const name of FILES) {
  const a = join(SRC, name);
  const b = join(DEST, name);
  if (!existsSync(a)) {
    problems.push(`源文件缺失：hostcore/app/${name}`);
    continue;
  }
  if (!existsSync(b)) {
    problems.push(`包里没有：entry/.../resources/app/${name}`);
    continue;
  }
  if (!readFileSync(a).equals(readFileSync(b))) {
    problems.push(`内容不一致：${name}（hostcore/app 与 entry 资源副本不同）`);
  }
}

if (problems.length > 0) {
  console.error('check-host-app-fresh: FAIL —— HAP 里的 Host 入口脚本是旧的：');
  for (const p of problems) console.error('  · ' + p);
  console.error('修法：node tools/place-host-app.mjs  然后重新构建。');
  process.exit(1);
}
console.log(`check-host-app-fresh: OK（${FILES.length} 份与 hostcore/app 逐字节一致）`);
