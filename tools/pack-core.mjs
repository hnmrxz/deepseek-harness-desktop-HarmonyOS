#!/usr/bin/env node
/**
 * pack-core.mjs —— 把 dsh 核心树物化成 **鸿蒙（openharmony / arm64）** 形态并打包。
 *
 * 背景（见 docs/50-端侧核心运行架构.md §4/§6）：
 *   端侧自足运行 dsh 的第一个前提，是有一棵**能在设备上跑起来**的核心树。
 *   这棵树必须是鸿蒙平台形态（原生依赖是 ohos-aarch64 的 .node），而不是桌面形态。
 *
 * 本脚本做四件事，每一步都可独立复跑：
 *   ① 按 hostcore/core-recipe.json 物化：npm install --os=openharmony --cpu=arm64
 *      + overrides 把 node-pty / koffi / sharp 别名到 @ohos-ports 的鸿蒙移植版
 *   ② 裁剪：删掉非鸿蒙平台的二进制（koffi 一个包就自带 19 个平台）
 *   ③ 校验：必需原生产物必须在位；每个原生 ELF 必须带 .codesign
 *      （只有 .note.ohos.ident 不算已签名 —— 实测对照见 D6 §4.2 R4）
 *   ④ 打包：放入端侧 profile，产出 ustar tar.gz + 清单（含 sha256）
 *
 * 用法：
 *   node tools/pack-core.mjs                    # 全流程
 *   node tools/pack-core.mjs --skip-install     # 复用已有 node_modules（快速重打包）
 *   node tools/pack-core.mjs --work <dir> --out <dir>
 *
 * 注意：不修改任何上游文件；不联网取任何"额外"东西（npm 除外）。
 */
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  closeSync, cpSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, rmSync, statSync,
  writeFileSync, writeSync,
} from 'node:fs';
import { deflateRawSync } from 'node:zlib';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));

// ── 参数 ────────────────────────────────────────────────────────────────
function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}
const RECIPE_PATH = resolve(ROOT, arg('--recipe', 'hostcore/core-recipe.json'));
const OUT_DIR = resolve(ROOT, arg('--out', 'build/core'));
const WORK_ROOT = resolve(ROOT, arg('--work', 'build/core/work'));
const SKIP_INSTALL = process.argv.includes('--skip-install');

const recipe = JSON.parse(readFileSync(RECIPE_PATH, 'utf8'));
const STAGE_NAME = `dsh-core-${recipe.coreVersion}`;
const STAGE = join(WORK_ROOT, STAGE_NAME);

const log = (...a) => console.log(...a);
const die = (msg) => { console.error(`\n[pack-core] ✗ ${msg}`); process.exit(1); };

/** 在 PATH 或给定目录里找一个可执行文件（Windows 上带 .exe 也认）。 */
function which(cmd) {
  const exts = process.platform === 'win32' ? ['.exe', '.cmd', ''] : [''];
  for (const dir of (process.env.PATH ?? '').split(process.platform === 'win32' ? ';' : ':')) {
    if (!dir) continue;
    for (const ext of exts) {
      const p = join(dir, cmd + ext);
      if (existsSync(p)) return p;
    }
  }
  return null;
}

/** 找 OHOS NDK 的 llvm-readelf（用于读 ELF 段表判签名）。找不到只影响签名校验。 */
function findReadelf() {
  const sdkHomes = [
    process.env.DEVECO_SDK_HOME,
    process.env.OHOS_SDK_HOME,
    'D:\\Huawei\\DevEco Studio\\sdk',
    'C:\\Program Files\\Huawei\\DevEco Studio\\sdk',
  ].filter(Boolean);
  const rels = [
    ['default', 'openharmony', 'native', 'llvm', 'bin', 'llvm-readelf'],
    ['default', 'hms', 'native', 'llvm', 'bin', 'llvm-readelf'],
  ];
  for (const home of sdkHomes) {
    for (const rel of rels) {
      for (const ext of ['.exe', '']) {
        const p = join(home, ...rel) + ext;
        if (existsSync(p)) return p;
      }
    }
  }
  return which('llvm-readelf');
}

// ── ① 物化 ──────────────────────────────────────────────────────────────
function writeBundlePackageJson() {
  const pkg = {
    name: 'hdsh-core-bundle',
    version: '0.0.0',
    private: true,
    description: `HDSH 端侧 dsh 核心树（${recipe.platform.os}/${recipe.platform.cpu}），由 tools/pack-core.mjs 生成。`,
    dependencies: { '@deepseek-ai/dsh': recipe.coreVersion },
    overrides: recipe.overrides,
  };
  writeFileSync(join(STAGE, 'package.json'), JSON.stringify(pkg, null, 2) + '\n', 'utf8');
}

function materialize() {
  log(`\n[pack-core] ① 物化 ${STAGE_NAME} → ${STAGE}`);
  mkdirSync(STAGE, { recursive: true });
  writeBundlePackageJson();
  if (SKIP_INSTALL) {
    if (!existsSync(join(STAGE, 'node_modules'))) die('--skip-install 但 node_modules 不存在');
    log('[pack-core]   跳过 npm install（--skip-install）');
    return;
  }
  const npm = which('npm');
  if (!npm) die('找不到 npm');
  const args = [
    'install',
    `--os=${recipe.platform.os}`,
    `--cpu=${recipe.platform.cpu}`,
    // 目标平台的原生模块 postinstall 在宿主上跑不了（也不该跑）
    '--ignore-scripts',
    '--no-audit',
    '--no-fund',
    '--loglevel=error',
  ];
  log(`[pack-core]   ${npm} ${args.join(' ')}`);
  // stdio: inherit —— 5 分钟量级的安装，进度要看得到；也避免管道相关限制
  const r = spawnSync(npm, args, { cwd: STAGE, stdio: 'inherit', shell: process.platform === 'win32' });
  if (r.status !== 0) die(`npm install 失败（exit=${r.status}）`);
}

// ── ② 裁剪 ──────────────────────────────────────────────────────────────
function dirSize(p) {
  if (!existsSync(p)) return 0;
  let total = 0;
  const walk = (d) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const f = join(d, e.name);
      if (e.isDirectory()) walk(f);
      else if (e.isFile()) total += statSync(f).size;
    }
  };
  walk(p);
  return total;
}

/** 极简 glob：只支持 `**&#47;` 前缀与 `*` 通配，够本脚本用。 */
function matchGlob(relPath, pattern) {
  const norm = relPath.split(sep).join('/');
  const rx = new RegExp('^' + pattern
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\*\*\//g, '(?:.*/)?')
    .replace(/\*/g, '[^/]*') + '$');
  return rx.test(norm);
}

function listFilesRecursive(base, dir = base, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const f = join(dir, e.name);
    if (e.isDirectory()) listFilesRecursive(base, f, out);
    else if (e.isFile()) out.push(f);
  }
  return out;
}

function prune() {
  const nm = join(STAGE, 'node_modules');
  log('\n[pack-core] ② 裁剪非鸿蒙二进制');
  let before = dirSize(nm);
  let removedBytes = 0;
  let removedCount = 0;

  for (const rule of recipe.prune ?? []) {
    if (rule.dir) {
      const target = join(nm, rule.dir);
      if (!existsSync(target)) continue;
      if (rule.remove) {
        removedBytes += dirSize(target);
        removedCount++;
        rmSync(target, { recursive: true, force: true });
        log(`[pack-core]   - ${rule.dir}/  （${rule.why ?? ''}）`);
      }
      if (rule.keepOnlyDirs) {
        for (const e of readdirSync(target, { withFileTypes: true })) {
          if (!e.isDirectory()) continue;
          if (rule.keepOnlyDirs.includes(e.name)) continue;
          const p = join(target, e.name);
          removedBytes += dirSize(p);
          removedCount++;
          rmSync(p, { recursive: true, force: true });
        }
        log(`[pack-core]   - ${rule.dir}/{除 ${rule.keepOnlyDirs.join(', ')} 外}  （${rule.why ?? ''}）`);
      }
    }
    for (const pattern of rule.removeGlobs ?? []) {
      for (const f of listFilesRecursive(nm)) {
        const rel = f.slice(nm.length + 1);
        if (!matchGlob(rel, pattern)) continue;
        removedBytes += statSync(f).size;
        removedCount++;
        rmSync(f, { force: true });
      }
      log(`[pack-core]   - ${pattern}  （${rule.why ?? ''}）`);
    }
  }
  const after = dirSize(nm);
  log(`[pack-core]   删除 ${removedCount} 项 / ${(removedBytes / 1048576).toFixed(1)} MB；`
    + `node_modules ${(before / 1048576).toFixed(1)} MB → ${(after / 1048576).toFixed(1)} MB`);
}

// ── ③ 校验 ──────────────────────────────────────────────────────────────
function hasCodesign(readelf, file) {
  const out = execFileSync(readelf, ['-S', file], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  return /\.codesign\b/.test(out);
}

function verify() {
  const nm = join(STAGE, 'node_modules');
  log('\n[pack-core] ③ 校验原生产物与签名');

  const missing = (recipe.requiredNative ?? []).filter((r) => !existsSync(join(nm, r)));
  if (missing.length > 0) die(`必需原生产物缺失：\n    ${missing.join('\n    ')}`);
  for (const r of recipe.requiredNative ?? []) log(`[pack-core]   ✓ 必需 ${r}`);

  const readelf = findReadelf();
  if (!readelf) {
    log('[pack-core]   ⚠ 找不到 llvm-readelf，跳过签名校验（这不是通过，只是没验）');
    return { signed: [], unsigned: [], skipped: true };
  }
  log(`[pack-core]   使用 ${readelf}`);

  // 必查：recipe.requiredNative + 所有 .node/.so
  const targets = new Set((recipe.requiredNative ?? []).map((r) => join(nm, r)));
  for (const f of listFilesRecursive(nm)) {
    if (/\.(node|so)(\.\d+)*$/.test(f)) targets.add(f);
  }
  const signed = [];
  const unsigned = [];
  for (const f of targets) {
    if (!existsSync(f)) continue;
    let ok = false;
    try { ok = hasCodesign(readelf, f); } catch { ok = false; }
    (ok ? signed : unsigned).push(f.slice(nm.length + 1));
  }
  for (const s of signed) log(`[pack-core]   ✓ .codesign ${s}`);
  if (unsigned.length > 0) {
    log(`[pack-core]   ⚠ 未检出 .codesign 的原生文件 ${unsigned.length} 个：`);
    for (const u of unsigned) log(`[pack-core]       ${u}`);
    log('[pack-core]   （.note.ohos.ident 单独出现不构成"已签名"的证据，见 D6 §4.2 R4）');
  }
  return { signed, unsigned, skipped: false };
}

// ── ④ 打包 ──────────────────────────────────────────────────────────────
function embedProfile() {
  if (!recipe.profile) return;
  const src = join(ROOT, 'hostcore', 'profile', recipe.profile);
  if (!existsSync(src)) die(`profile 源目录不存在：${src}`);
  const dest = join(STAGE, 'profiles', recipe.profile);
  mkdirSync(dirname(dest), { recursive: true });
  cpSync(src, dest, { recursive: true, force: true });
  log(`\n[pack-core] ④ 端侧 profile 已放入 ${STAGE_NAME}/profiles/${recipe.profile}/`);
}

function sha256(file) {
  const h = createHash('sha256');
  h.update(readFileSync(file));
  return h.digest('hex');
}

// ── 最小 ZIP 写入器（deflate，无 zip64）───────────────────────────────────
// 为什么是 zip 而不是 tar.gz：**鸿蒙侧只有 zip 解压 API**（`@ohos.zlib.decompressFile`），
// 没有 tar/gzip 的等价物。用 tar.gz 就得在 ArkTS 里手写 tar 解析 + gzip 解压，
// 那是纯粹的额外风险与代码量；用 zip 则端侧只调一个系统 API。
// 规模核对：25000 余条目 < 65535，解包约 120 MB < 4 GB ⇒ 不需要 zip64。
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

// 固定时间戳 ⇒ 同一份输入产出逐字节相同的包，便于比对与审计
const DOS_TIME = (12 << 11);
const DOS_DATE = (((2026 - 1980) << 9) | (1 << 5) | 1);

function writeZip(zipPath, baseDir, topName) {
  const fd = openSync(zipPath, 'w');
  const central = [];
  let offset = 0;
  let count = 0;
  let rawBytes = 0;
  let compBytes = 0;

  const put = (buf) => { writeSync(fd, buf); offset += buf.length; };

  const localHeader = (name, method, crc, comp, uncomp) => {
    const nameBuf = Buffer.from(name, 'utf8');
    const h = Buffer.alloc(30);
    h.writeUInt32LE(0x04034b50, 0);
    h.writeUInt16LE(20, 4);          // version needed
    h.writeUInt16LE(0, 6);           // flags
    h.writeUInt16LE(method, 8);
    h.writeUInt16LE(DOS_TIME, 10);
    h.writeUInt16LE(DOS_DATE, 12);
    h.writeUInt32LE(crc, 14);
    h.writeUInt32LE(comp, 18);
    h.writeUInt32LE(uncomp, 22);
    h.writeUInt16LE(nameBuf.length, 26);
    h.writeUInt16LE(0, 28);          // extra len
    return Buffer.concat([h, nameBuf]);
  };

  const addEntry = (name, data, isDir) => {
    const comp = isDir ? Buffer.alloc(0) : deflateRawSync(data, { level: 6 });
    const crc = isDir ? 0 : crc32(data);
    const uncomp = isDir ? 0 : data.length;
    const method = isDir ? 0 : 8;
    if (!isDir) {
      rawBytes += uncomp;
      compBytes += comp.length;
    }
    const start = offset;
    put(localHeader(name, method, crc, comp.length, uncomp));
    if (!isDir) put(comp);
    central.push({
      name, method, crc, comp: comp.length, uncomp, offset: start,
      external: isDir ? 0x10 : 0,
    });
    count++;
  };

  const walk = (dir, rel) => {
    for (const e of readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const full = join(dir, e.name);
      const r = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) {
        addEntry(`${topName}/${r}/`, Buffer.alloc(0), true);
        walk(full, r);
      } else if (e.isFile()) {
        addEntry(`${topName}/${r}`, readFileSync(full), false);
      }
    }
  };

  // 顶层目录自身的条目
  addEntry(`${topName}/`, Buffer.alloc(0), true);
  walk(baseDir, '');

  const cdStart = offset;
  for (const c of central) {
    const nameBuf = Buffer.from(c.name, 'utf8');
    const h = Buffer.alloc(46);
    h.writeUInt32LE(0x02014b50, 0);
    h.writeUInt16LE(20, 4);          // version made by
    h.writeUInt16LE(20, 6);          // version needed
    h.writeUInt16LE(0, 8);
    h.writeUInt16LE(c.method, 10);
    h.writeUInt16LE(DOS_TIME, 12);
    h.writeUInt16LE(DOS_DATE, 14);
    h.writeUInt32LE(c.crc, 16);
    h.writeUInt32LE(c.comp, 20);
    h.writeUInt32LE(c.uncomp, 24);
    h.writeUInt16LE(nameBuf.length, 28);
    h.writeUInt16LE(0, 30);          // extra
    h.writeUInt16LE(0, 32);          // comment
    h.writeUInt16LE(0, 34);          // disk
    h.writeUInt16LE(0, 36);          // internal attrs
    h.writeUInt32LE(c.external, 38);
    h.writeUInt32LE(c.offset, 42);
    put(Buffer.concat([h, nameBuf]));
  }
  const cdSize = offset - cdStart;

  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(count, 8);
  eocd.writeUInt16LE(count, 10);
  eocd.writeUInt32LE(cdSize, 12);
  eocd.writeUInt32LE(cdStart, 16);
  eocd.writeUInt16LE(0, 20);
  put(eocd);

  closeSync(fd);
  return { count, rawBytes, compBytes, bytes: offset };
}

function pack() {
  log('\n[pack-core] ⑤ 打包（zip：鸿蒙侧只有 @ohos.zlib.decompressFile 可用）');
  mkdirSync(OUT_DIR, { recursive: true });
  const base = `${STAGE_NAME}-${recipe.platform.os}-${recipe.platform.cpu}`;
  const zipPath = join(OUT_DIR, `${base}.zip`);
  const z = writeZip(zipPath, STAGE, STAGE_NAME);
  log(`[pack-core]   ${zipPath}`);
  log(`[pack-core]   ${z.count} 条目 / 原始 ${(z.rawBytes / 1048576).toFixed(1)} MB → `
    + `压缩后 ${(z.compBytes / 1048576).toFixed(1)} MB / 整包 ${(z.bytes / 1048576).toFixed(1)} MB`);

  let tarPath = null;
  if (process.argv.includes('--also-tar')) {
    const tar = which('tar');
    if (tar) {
      // 相对文件名 + --force-local：Git 的 tar 会把 "D:\..." 当成远程主机（实测踩过）
      const name = `${base}.tar.gz`;
      const r = spawnSync(tar, ['-czf', name, '--force-local', '--format=ustar', '-C', WORK_ROOT, STAGE_NAME],
        { stdio: 'inherit', cwd: OUT_DIR });
      if (r.status === 0) { tarPath = join(OUT_DIR, name); log(`[pack-core]   另存 ${name}`); }
      else log('[pack-core]   ⚠ tar 失败（非致命，zip 已产出）');
    }
  }
  return { zipPath, bytes: z.bytes, entries: z.count, tarPath };
}

function writeManifest(extra) {
  const nm = join(STAGE, 'node_modules');
  let fileCount = 0;
  for (const f of listFilesRecursive(nm)) { void f; fileCount++; }
  const corePkg = JSON.parse(readFileSync(join(nm, '@deepseek-ai', 'dsh', 'package.json'), 'utf8'));
  const manifest = {
    generatedAt: new Date().toISOString(),
    recipe: RECIPE_PATH.slice(ROOT.length + 1).split(sep).join('/'),
    coreVersion: recipe.coreVersion,
    coreVersionInstalled: corePkg.version,
    platform: recipe.platform,
    overrides: recipe.overrides,
    profile: recipe.profile,
    nodeModules: {
      fileCount,
      unpackedBytes: dirSize(nm),
    },
    package: extra.zipPath ? {
      format: 'zip',
      file: extra.zipPath.slice(ROOT.length + 1).split(sep).join('/'),
      bytes: extra.bytes,
      entries: extra.entries,
      sha256: sha256(extra.zipPath),
      topDir: STAGE_NAME,
      extractWith: '@ohos.zlib.decompressFile',
    } : null,
    tarGz: extra.tarPath ? {
      file: extra.tarPath.slice(ROOT.length + 1).split(sep).join('/'),
      sha256: sha256(extra.tarPath),
    } : null,
    native: {
      signed: extra.signed ?? [],
      unsigned: extra.unsigned ?? [],
      signatureCheckSkipped: extra.skipped ?? false,
    },
  };
  const manifestPath = join(OUT_DIR, `${STAGE_NAME}.manifest.json`);
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  log(`[pack-core] 清单 ${manifestPath}`);
  return manifest;
}

// ── 主流程 ──────────────────────────────────────────────────────────────
log(`[pack-core] 配方 ${RECIPE_PATH}`);
log(`[pack-core] 核心 ${recipe.coreVersion} @ ${recipe.platform.os}/${recipe.platform.cpu}`);
log(`[pack-core] 宿主 Node ${process.version} / ${process.platform}`);

materialize();
prune();
const sig = verify();
embedProfile();
const packed = pack();
const manifest = writeManifest({ ...packed, ...sig });

log('\n[pack-core] ✓ 完成');
log(`  核心版本   ${manifest.coreVersionInstalled}`);
log(`  解包体积   ${(manifest.nodeModules.unpackedBytes / 1048576).toFixed(1)} MB / ${manifest.nodeModules.fileCount} 文件`);
log(`  分发包     ${manifest.package.file}  ${(manifest.package.bytes / 1048576).toFixed(1)} MB / ${manifest.package.entries} 条目`);
log(`  sha256     ${manifest.package.sha256}`);
log(`  签名       ${manifest.native.signatureCheckSkipped ? '未校验' : `${manifest.native.signed.length} 通过 / ${manifest.native.unsigned.length} 未检出`}`);
