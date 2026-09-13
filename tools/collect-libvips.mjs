/**
 * 把 libvips 全套依赖搬进 HAP 的 `entry/libs/<abi>/`（E93）。
 *
 * ---------------------------------------------------------------------------
 * WHY THIS EXISTS
 * ---------------------------------------------------------------------------
 * `attachment-local`（图片附件）需要真 sharp；而真 sharp 需要 libvips 及其 46 个
 * 依赖库。之前我们用 stub 让它"能挂载但图片处理不可用"（E79），那是诚实的降级；
 * 这一轮把真件搬进去，把降级取消。
 *
 * 难点有三个，缺一不可（E64 早已量化：46 个文件 / 30.5 MB，且 SONAME 普遍带版本号）：
 *
 *   1. **hvigor 只打包 `libs/<abi>/*.so`（E40 实测）**，而 vips 的依赖文件名带版本号
 *      （`libglib-2.0.so.0.8800.2`）⇒ 必须**改名**成 `*.so`；
 *   2. 改名后**必须同步改它自己的 SONAME**（否则依赖方按新名字 DT_NEEDED 去加载时，
 *      加载器拿库内旧 SONAME 对不上 ⇒ `cannot open shared object`）；
 *   3. **每个依赖方的 DT_NEEDED 也要跟着改**（`libvips-cpp.so.42` → `libvips-cpp.so`），
 *      否则链子在第一环就断。
 *
 * 另外还有一个不注意就会白忙一场的点：sharp 的原生件里写死了一串 **RPATH**
 * （`$ORIGIN/../../sharp-libvips-openharmony-arm64/lib:…`，指向 npm 安装布局），
 * 那个布局在 HAP 里**不存在**。所以还要把 RPATH 改成 **`$ORIGIN`**：让所有依赖
 * 就在它自己旁边解析——这也正是"全部扁平化到同一个目录"的前提。
 *
 * 事实来源：`llvm-readelf` 读出的真实 SONAME/NEEDED/RPATH（ELF 解析复用
 * `tools/patch-native-needed.mjs`，只此一处实现）。本脚本只做**写入**，验证交给
 * `tools/check-native-closure.mjs`（静态依赖闭包检查，可在开发机上跑）。
 *
 * 用法：
 *   node tools/collect-libvips.mjs                 # 收集到 entry/libs/arm64-v8a
 *   node tools/collect-libvips.mjs --abi arm64-v8a --src <libvips lib 目录>
 */
import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const PATCH_TOOL = join(ROOT, 'tools', 'patch-native-needed.mjs');

const args = process.argv.slice(2);
const arg = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
};

const ABI = arg('--abi', 'arm64-v8a');
const SRC = resolve(arg('--src',
  join(ROOT, 'dist', 'core', 'work', 'dsh-core-0.1.5-rc.2', 'node_modules', '@ohos-ports',
    'img-sharp-libvips-openharmony-arm64', 'lib')));
const DEST = resolve(join(ROOT, 'entry', 'libs', ABI));
const MANIFEST = join(ROOT, 'dist', 'core', 'libvips-libs.json');
/** 随包一起改写的消费者（它们 DT_NEEDED 里点名了 vips）。 */
const EXTRA_CONSUMERS = ['libsharp-openharmony-arm64.so'];
/** 这些是系统提供的，我们既不打包也不改写。 */
const SYSTEM_LIBS = new Set([
  'libc.so', 'libc++_shared.so', 'libdl.so', 'libm.so', 'libz.so', 'liblog.so',
  'libhilog.so', 'libhilog_ndk.z.so', 'libace_napi.z.so', 'libuv.so', 'libnode.so.127',
  'ld-musl-aarch64.so.1', 'libpthread.so', 'librt.so', 'libatomic.so',
]);

function die(message) {
  console.error(`collect-libvips: ${message}`);
  process.exit(1);
}

/** 用 patch 工具读一个 ELF 的 SONAME/NEEDED/RPATH（ELF 解析只此一处）。 */
function elfInfo(path) {
  const raw = execFileSync(process.execPath, [PATCH_TOOL, path, '-', '-', '--list'], { encoding: 'utf8' });
  return JSON.parse(raw);
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

if (!existsSync(SRC)) die(`libvips 源目录不存在：${SRC}（先跑 tools/pack-core.mjs 物化核心树？）`);
if (!existsSync(PATCH_TOOL)) die(`缺少 ${PATCH_TOOL}`);
mkdirSync(DEST, { recursive: true });

/*
 * 播种 sharp 原生件（全新克隆时 `entry/libs` 是空的）。
 *
 * `entry/libs/` 在 .gitignore 里（体积与签名考虑），所以这些库必须**能从核心树重建**。
 * sharp 的 `.node` 由我们的原生重定向按 `lib<stem>.so` 规则加载（见 hostcore/app/main.js），
 * 所以这里按那个约定落位；已存在时不覆盖（避免把手工调过的版本冲掉）。
 */
const SHARP_NODE_SRC = join(ROOT, 'dist', 'core', 'work', 'dsh-core-0.1.5-rc.2', 'node_modules',
  '@ohos-ports', 'img-sharp-openharmony-arm64', 'lib', 'sharp-openharmony-arm64.node');
const SHARP_DEST = join(DEST, 'libsharp-openharmony-arm64.so');
if (!existsSync(SHARP_DEST)) {
  if (!existsSync(SHARP_NODE_SRC)) {
    die(`缺少 sharp 原生件源：${SHARP_NODE_SRC}（先跑 tools/pack-core.mjs）`);
  }
  copyFileSync(SHARP_NODE_SRC, SHARP_DEST);
  console.log(`collect-libvips: 播种 ${SHARP_DEST}`);
}

/** 扁平名：SONAME 截到 `.so` 为止（`libglib-2.0.so.0` → `libglib-2.0.so`）。 */
function flatNameOf(soname) {
  const at = soname.indexOf('.so');
  if (at < 0) return soname;
  return `${soname.slice(0, at)}.so`;
}

// ── 1. 读全量事实 ───────────────────────────────────────────────────────────
const sources = [];
const noSoname = [];
for (const name of readdirSync(SRC)) {
  const full = join(SRC, name);
  if (!statSync(full).isFile() || !/\.so(\.|$)/.test(name)) continue;
  const info = elfInfo(full);
  let soname = typeof info.soname === 'string' ? info.soname : '';
  let flat;
  if (soname.length === 0) {
    /*
     * 没有 SONAME 的库是真实存在的（实测 `libsharpyuv.so`）。它**不能**被别人按 SONAME
     * 引用；文件名本身就是扁平形态，直接按文件名收即可。若真有依赖，对方的 DT_NEEDED
     * 写的也是这个文件名，仍然命中。这里如实记下来，而不是"补一个猜出来的 SONAME"。
     */
    if (!name.endsWith('.so')) {
      die(`${name} 既没有 SONAME，文件名也不是扁平 *.so，无法安全收进 HAP`);
    }
    flat = name;
    soname = name;
    noSoname.push(name);
  } else {
    flat = flatNameOf(soname);
  }
  sources.push({ file: name, path: full, soname, flat, needed: info.needed, hadSoname: soname !== name || name.endsWith('.so') ? true : false });
}
if (sources.length === 0) die('源目录里没有可收集的 .so 文件');

const oldToNew = new Map();
for (const s of sources) {
  if (oldToNew.has(s.soname) && oldToNew.get(s.soname) !== s.flat) {
    die(`SONAME ${s.soname} 映射到两个不同新名（${oldToNew.get(s.soname)} / ${s.flat}）`);
  }
  oldToNew.set(s.soname, s.flat);
}
for (const [oldName, newName] of oldToNew) {
  if (newName.length > oldName.length) {
    die(`新名比旧 SONAME 长，无法原地改写：${oldName} → ${newName}`);
  }
}

// ── 2. 拷贝 + 改 SONAME ────────────────────────────────────────────────────
const collected = [];
for (const s of sources) {
  const dest = join(DEST, s.flat);
  copyFileSync(s.path, dest);
  if (s.soname !== s.file || !s.file.endsWith('.so')) {
    // 只有"改过名"的库才需要同步 SONAME；本来就扁平的库不必动它。
    try {
      execFileSync(process.execPath, [PATCH_TOOL, dest, s.soname, s.flat, '--set-soname'],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
      die(`改 SONAME 失败：${s.flat}：${String(e.stderr ?? e.message)}`);
    }
  }
  collected.push({ ...s, dest });
}

// ── 3. 改所有依赖方的 DT_NEEDED + RPATH ───────────────────────────────────
const consumers = [...collected.map((c) => c.dest)];
for (const extra of EXTRA_CONSUMERS) {
  const p = join(DEST, extra);
  if (existsSync(p)) consumers.push(p);
}

let neededRewrites = 0;
let rpathRewrites = 0;
for (const consumer of consumers) {
  let info = elfInfo(consumer);
  for (const needed of info.needed) {
    const flat = oldToNew.get(needed);
    if (flat === undefined || flat === needed) continue;
    try {
      const out = execFileSync(process.execPath, [PATCH_TOOL, consumer, needed, flat],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
      if (out.includes('→')) neededRewrites += 1;
    } catch (e) {
      die(`改 DT_NEEDED 失败：${consumer} ${needed} → ${flat}：${String(e.stderr ?? e.message)}`);
    }
  }
  info = elfInfo(consumer);
  const rpath = info.rpath ?? info.runpath;
  if (typeof rpath === 'string' && rpath.length > 0 && rpath !== '$ORIGIN') {
    try {
      execFileSync(process.execPath, [PATCH_TOOL, consumer, '-', '$ORIGIN', '--set-rpath'],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
      rpathRewrites += 1;
    } catch (e) {
      die(`改 RPATH 失败：${consumer}：${String(e.stderr ?? e.message)}`);
    }
  }
}

// ── 3.5 sharp 原生件必须把 libnode 拉进自己的依赖闭包（E44 的同一课，真机实测） ──
//
// 真机读数（E93 首次上设备）：
//   W MUSL-LDSO: relocating failed: symbol not found.
//     dso=/data/storage/el1/bundle/libs/arm64/libsharp-openharmony-arm64.so
//     s=napi_open_escapable_handle_scope
// 与 koffi 当年**完全同一类**问题：dlopen 出来的对象只按「自身 + 自身依赖闭包 + 全局组」
// 解析符号，而 libnode **既不（有效地）进全局组，也不在 sharp 的闭包里** ⇒ 所有 napi 符号
// 都找不到。修法也同一套：把 `DT_NEEDED libc++_shared.so`（16 字节）原地改成
// `libnode.so.127`（14 字节，更短 ⇒ 零结构风险）；libc++ 不会丢——libnode 自己就
// NEEDED libc++_shared.so，会随之进入闭包。
//
// 【为什么必须写在这里而不是靠"反正是 dlopen"】这一步不做，sharp 在设备上永远加载不了，
// 而症状只有一行 MUSL-LDSO 警告 + 图片附件静默降级——正是最难查的那种。
for (const consumer of consumers) {
  if (!consumer.endsWith('libsharp-openharmony-arm64.so')) continue;
  const info = elfInfo(consumer);
  if (info.needed.includes('libnode.so.127')) continue;
  if (!info.needed.includes('libc++_shared.so')) {
    die('sharp 原生件的 NEEDED 里既没有 libnode.so.127 也没有 libc++_shared.so，无法原地改写（需人工核对）');
  }
  try {
    execFileSync(process.execPath, [PATCH_TOOL, consumer, 'libc++_shared.so', 'libnode.so.127'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    neededRewrites += 1;
  } catch (e) {
    die(`把 libnode 拉进 sharp 依赖闭包失败：${String(e.stderr ?? e.message)}`);
  }
}

// ── 4. 清掉工具留下的 .orig 备份（源文件从未被改动，无需回滚点） ────────────
let removedBackups = 0;
for (const name of readdirSync(DEST)) {
  if (!name.endsWith('.orig')) continue;
  rmSync(join(DEST, name), { force: true });
  removedBackups += 1;
}

// ── 5. 清单（证据：映射 + 新名 + 依赖） ─────────────────────────────────────
const manifest = {
  generatedAt: new Date().toISOString(),
  abi: ABI,
  source: SRC,
  dest: DEST,
  count: collected.length,
  bytes: collected.reduce((sum, c) => sum + statSync(c.dest).size, 0),
  neededRewrites,
  rpathRewrites,
  removedBackups,
  libs: collected.map((c) => {
    const info = elfInfo(c.dest);
    return {
      file: c.flat,
      fromFile: c.file,
      sonameNow: info.soname,
      rpathNow: info.rpath ?? info.runpath ?? '',
      needed: info.needed,
      sha256: sha256(c.dest),
    };
  }),
};
writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');

console.log(`collect-libvips: ${collected.length} 个库 → ${DEST}`);
console.log(`  DT_NEEDED 改写 ${neededRewrites} 处，RPATH→$ORIGIN ${rpathRewrites} 处，清理备份 ${removedBackups} 个`);
console.log(`  体积 ${(manifest.bytes / 1048576).toFixed(1)} MB`);
console.log(`  清单 ${MANIFEST}`);
console.log('');
console.log('下一步：node tools/check-native-closure.mjs   # 静态依赖闭包检查（必须 PASS）');
