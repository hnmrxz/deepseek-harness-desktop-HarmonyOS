#!/usr/bin/env node
/*
 * 把 Host 入口脚本放进应用内置资源（`entry/src/main/resources/resfile/resources/app/`）。
 *
 * 【为什么入口归 entry 自己所有】此前它靠 `web_engine` 那个 HAR 的 resfile 合并进 HAP
 * （`tools/electron-runtime/place-host-app.ps1` 把 main.js 拷进 web_engine）。阶段一的
 * Electron 链已整体移除（D6 E49），`entry` 也不再依赖 `web_engine` —— 结果就是入口脚本
 * **从 HAP 里消失**（实测：HAP 内不再有 `resources/resfile/resources/app/`），
 * 表现为 Host 永远起不来。所以入口改由 `entry` 自己携带，并用本脚本同步。
 *
 * 【为什么是"拷贝"而不是软链/引用】鸿蒙侧通过 `resourceDir + /resources/app/main.js`
 * 直接按真实路径读取（resfile 安装后会解压到沙箱，可按真实路径只读访问），所以
 * HAP 里必须有这几份真实文件。
 *
 * 产物目录已 gitignore（生成物：字节不进库、方法进库）。
 * 用法：node tools/place-host-app.mjs
 */
import { copyFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SRC_DIR = join(ROOT, 'hostcore', 'app');
const DEST = join(ROOT, 'entry', 'src', 'main', 'resources', 'resfile', 'resources', 'app');

// 入口脚本会 `require('./fetch-shim.js')`（jitless 下垫 fetch，见 D6 E52）⇒ 必须一起进包
const FILES = ['main.js', 'fetch-shim.js'];

mkdirSync(DEST, { recursive: true });

const missing = FILES.filter((name) => !existsSync(join(SRC_DIR, name)));
if (missing.length > 0) {
  console.error(`place-host-app: 源文件缺失：${missing.join('、')}（在 ${SRC_DIR}）`);
  process.exit(1);
}

for (const name of FILES) {
  copyFileSync(join(SRC_DIR, name), join(DEST, name));
  console.log(`placed   : ${name}`);
}

// package.json 刻意**不带** "type" 字段 ⇒ CommonJS（main.js 里用 require/__dirname）
const pkg = {
  name: 'hdsh-host',
  version: '1.0.0',
  private: true,
  description: 'HDSH 端侧 Host 入口（在 libnode.so.127 里运行；不属于任何 npm 包发布物）',
  main: 'main.js',
};
writeFileSync(join(DEST, 'package.json'), JSON.stringify(pkg, null, 2) + '\n', 'utf8');
console.log(`placed   : package.json`);
console.log(`dest     : ${DEST}`);
