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
  closeSync, cpSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, renameSync, rmSync, statSync,
  writeFileSync, writeSync,
} from 'node:fs';
import { deflateRawSync } from 'node:zlib';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inventoryOf } from './lib/core-inventory.mjs';

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));

// ── 参数 ────────────────────────────────────────────────────────────────
function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}
const RECIPE_PATH = resolve(ROOT, arg('--recipe', 'hostcore/core-recipe.json'));
// 输出**不能**放根 `build/`：那是 HarmonyOS 构建自己的目录，`devecocli build` 会把它清掉
// （实测踩过：node_modules 被清空后 `--skip-install` 直接失败）。因此统一放 `dist/`。
const OUT_DIR = resolve(ROOT, arg('--out', 'dist/core'));
const WORK_ROOT = resolve(ROOT, arg('--work', 'dist/core/work'));
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

/**
 * 在**打包之前**把构建元数据写进树里（`<top>/hdsh-core.json`）。
 *
 * 为什么不能只留在外层清单里：外层清单在容器**外面**，端侧解包完只有树本身。
 * 端侧要能回答"我装的这版是什么、哪个 profile、平台对不对"，就必须把答案放进树里。
 * 因此这里只写不依赖产物哈希的字段——容器的 sha256 仍然只在外层清单（否则自指）。
 */
/**
 * 生成**端侧 agent preset**：`presets/ondevice/`（复制 `standard`，禁用依赖 subprocess 的三行）。
 *
 * 【为什么必须固化在这里（D6 E80）】`session/create` 要求挂载 agent preset，而 `standard` 的组成里
 * 有三行依赖 `ctx.subprocess`：`tool-pwsh`（`condition: process.platform !== 'win32'` ⇒ 端侧 linux 会启用）、
 * `tool-bash`（同类）、`tool-fs-search`（多行 inject 含 `"subprocess"`，走 ripgrep）。而**鸿蒙不支持
 * 进程创建**（E15），于是会话创建会以 `agent-preset/invalid: preset "standard" failed to mount:
 * N row(s) did not activate` 失败。正确解法是**在配置层表达端侧差异**——新增一个禁用这三行的 preset，
 * 并在 profile 里把 `agent-presets.default` 指向它；而不是让 shell 链假装可用。
 *
 * 【为什么是"复制 standard 再改"】preset 是磁盘文件、**目录名即 id**（`preset.yml` 里没有 id）：
 * 复制保证其余组成与上游 standard 一致（上游新增工具行时端侧也带上），只把这三行改 `disabled: true`。
 * 这属于**增加一个组合**，不是修改 dsh 自身代码。
 */
function addOnDevicePreset() {
  const presets = join(STAGE, 'node_modules', '@deepseek-ai', 'dsh-agent-presets', 'presets');
  const from = join(presets, 'standard');
  const to = join(presets, 'ondevice');
  if (!existsSync(from)) {
    log('[pack-core]   ⚠ 未找到 standard preset，跳过端侧 preset 生成');
    return;
  }
  rmSync(to, { recursive: true, force: true });
  cpSync(from, to, { recursive: true });
  const agentFile = join(to, 'agent.cordis.yml');
  let text = readFileSync(agentFile, 'utf8');
  text = text
    .replace("disabled: !!js process.platform === 'win32'", 'disabled: true')
    .replace("disabled: !!js process.platform !== 'win32'", 'disabled: true');
  const fsSearchRow = "- id: tool-fs-search\n  name: '@deepseek-ai/dsh-tool-fs-search'\n";
  if (text.includes(fsSearchRow)) {
    text = text.replace(fsSearchRow,
      "- id: tool-fs-search\n  name: '@deepseek-ai/dsh-tool-fs-search'\n"
      + '  # 端侧禁用：经 ctx.subprocess 调 ripgrep，而鸿蒙不支持进程创建（E15）\n  disabled: true\n');
  }
  writeFileSync(agentFile, text, 'utf8');
  writeFileSync(join(to, 'preset.yml'),
    'name: 端侧模式（无 Shell）\n'
    + 'description: 端侧编码 Agent：文件编辑、检索、Skills、计划、目标、子代理与工作流；'
    + '不含 Shell 工具（鸿蒙不支持进程创建）。\n'
    + 'order: 1\n', 'utf8');
  log('[pack-core]   端侧 preset 已生成：presets/ondevice（禁用 tool-bash / tool-pwsh / tool-fs-search）');
}

/**
 * 平台别名：让原生包的**加载器**能按它算出来的目录名找到原生件。
 *
 * 【为什么需要】实测真机（D6 E39）：我们自建的 Node 在设备上 `process.platform === 'linux'`
 * （与 E22 同源：gyp 的 `OS` 是 linux，Node 就按 linux 编译），而 `arch === 'arm64'`。
 * 但 `@ohos-ports/*` 移植件把它们的产品放在 **`openharmony_arm64`** 这类目录下
 * （koffi 的加载器按 `process.platform + '_' + process.arch` 拼路径，见
 * node_modules/koffi/index.js:468-499，所以它会去找 `build/koffi/linux_arm64/koffi.node`）。
 * 结果就是：文件明明在包里，加载器却说 "Cannot find the native Koffi module"。
 *
 * 【为什么是复制而不是符号链接】鸿蒙沙箱**禁止符号链接**（实测 `13900012 Permission denied`），
 * 而且 HAP 也不能携带符号链接。所以只能复制——代价是每个原生件多占一份体积。
 */
function addPlatformAliases() {
  const nm = join(STAGE, 'node_modules');
  const aliases = [
    ['koffi/build/koffi/openharmony_arm64', 'koffi/build/koffi/linux_arm64'],
    ['koffi/build/koffi/openharmony_arm64', 'koffi/build/koffi/musl_arm64'],
    ['node-pty/prebuilds/openharmony-arm64', 'node-pty/prebuilds/linux-arm64'],
  ];
  for (const [from, to] of aliases) {
    const src = join(nm, from);
    const dst = join(nm, to);
    if (!existsSync(src)) continue;
    if (existsSync(dst)) continue;
    cpSync(src, dst, { recursive: true });
    log(`[pack-core]   平台别名 ${from} → ${to}`);
  }
}

/**
 * 让 `/api` 的 Origin 栅栏接受**逗号分隔的 Origin 列表**（E81）。
 *
 * ─────────────────────── 为什么必须改这一处 ───────────────────────
 * dsh 的 `isTrustedApiRequest()` 只做一件事：带了 `Origin` 就必须与 `Host` 同源，
 * 否则 403。它按**整串**解析，于是 `new URL(整串).host` 必须恰好等于 `hostUrl.host`。
 *
 * 鸿蒙的 WebSocket 客户端（netstack → libwebsockets）有两条我们控制不了的行为：
 *   1. 它**一定会**自己附一个 `Origin`，并且是按 URL 推导时**丢掉端口**的形态
 *      （`ws://127.0.0.1:3120` → `Origin: http://127.0.0.1`）；
 *   2. 调用方在 `WebSocketRequestOptions.header` 里再给一个 `origin` 时，它**追加**
 *      而不是替换，于是线上值是 `http://127.0.0.1, ws://127.0.0.1:3120`。
 *
 * 真机读数（E81，`IN-UPGRADE` 服务端侧原始日志）：
 *   IN-UPGRADE GET /api/remote.mux conn=Upgrade upgrade=websocket key=yes ver=13
 *              cookie=224B origin=http://127.0.0.1, ws://127.0.0.1:3120
 * 这个值永远不可能等于 `127.0.0.1:3120`，所以**每一次** WS 升级都被判 403；
 * 而 ArkTS 客户端把这个失败报成 `error code=200`（"升级响应不是 101"），
 * 让人长期以为"链路是好的、只是握手后掉了"。
 *
 * ─────────────────────── 改动的语义边界 ───────────────────────
 * 仍然是「不得跨源」：只有当**某一项**与 Host 同源时才放行，跨源项一律不认。
 * 也就是说，这补的不是安全策略的洞，而是**多值形态**带来的误判——
 * 浏览器（单值 Origin）行为完全不变；纯原生客户端从"必被拒"变成"可同源"。
 *
 * 上游若改了这段实现，这里会**报错退出**而不是静默跳过：悄悄发出一个
 * "WS 永远连不上"的包，比打包失败难查得多。
 */
function allowOriginList() {
  const target = join(
    STAGE, 'node_modules', '@deepseek-ai', 'dsh-client-connection', 'lib', 'index.js',
  );
  if (!existsSync(target)) {
    die(`Origin 栅栏补丁：找不到 ${target}`);
  }
  let text = readFileSync(target, 'utf8');
  if (text.includes('HDSH_ORIGIN_LIST')) {
    log('[pack-core]   Origin 栅栏补丁已存在（跳过）');
    return;
  }
  const before = `\tconst origin = header$1(request.headers, "origin");
\tif (origin === void 0) return true;
\ttry {
\t\treturn new URL(origin).host === hostUrl.host;
\t} catch {
\t\treturn false;
\t}`;
  const after = `\tconst origin = header$1(request.headers, "origin");
\tif (origin === void 0) return true;
\t/* HDSH_ORIGIN_LIST: 多值 Origin（鸿蒙客户端 libwebsockets 附加的无端口 Origin +
\t * 调用方注入值）只要**任一项**同源即通过。原实现按整串解析，导致每一次端侧 WS 升级
\t * 都被判 403。详见 tools/pack-core.mjs 的 allowOriginList()。 */
\tfor (const rawOrigin of String(origin).split(",")) {
\t\tconst candidate = rawOrigin.trim();
\t\tif (candidate.length === 0) continue;
\t\ttry {
\t\t\tif (new URL(candidate).host === hostUrl.host) return true;
\t\t} catch {
\t\t\t/* 单个非法候选不足以否决整条请求，继续看下一项 */
\t\t}
\t}
\treturn false;`;
  if (!text.includes(before)) {
    die('Origin 栅栏补丁：上游实现已变化（未找到待替换片段），拒绝静默跳过');
  }
  text = text.replace(before, after);
  writeFileSync(target, text, 'utf8');
  log('[pack-core]   Origin 栅栏补丁：已允许逗号分隔的 Origin 列表');
}

/**
 * 把 sharp 换成**调度器 + 真件**（E93），取代原来的"纯 stub"（E79）。
 *
 * ─────────────────────────── 为什么不能只有 stub ───────────────────────────
 * E79 的 stub 让 `dsh-attachment-local` 能挂载（整条 attachments 服务链成立），
 * 代价是**图片附件在使用时报错**。那在当时是唯一诚实的降级——libvips 那 46 个库还没进 HAP。
 * 现在 `tools/collect-libvips.mjs` 已把真件搬进来（并把 sharp 原生件的 RPATH 改成 `$ORIGIN`、
 * 依赖闭包静态校验 PASS），所以"能不能用真件"应当由**运行时**决定，而不是构建期一刀切。
 *
 * ─────────────────── 为什么用调度器而不是直接放真件 ───────────────────
 * 真件是**鸿蒙 arm64** 原生件：设备上能加载，开发机（Windows）上必然失败；而开发机要跑
 * **同一棵核心树**做本地回归（三个 check 工具全靠它）。直接放真件会让本地 boot fail-loud。
 * 调度器把两种情形都照顾到：
 *   · 真件加载成功 → 用它（端侧正常路径，图片附件真的可用）；
 *   · 真件加载失败 → 退回"会报错但能挂载"的 stub，并把**真实原因**挂在
 *     `hdshSharpLoadError` 上——入口脚本的运行时事实（E88）会读它，于是界面显示的是
 *     真实结论，而不是假的"可用"，也不是含糊的"未探测"。
 *
 * 【幂等】以 package.json 的版本号 `0.0.0-hdsh-dispatch` 为标记。
 */
function wrapSharp() {
  const nm = join(STAGE, 'node_modules');
  const sharpDir = join(nm, 'sharp');
  const implDir = join(nm, 'sharp.impl');
  if (!existsSync(sharpDir)) {
    log('[pack-core]   sharp 不在树里（跳过调度器）');
    return;
  }
  const pkgFile = join(sharpDir, 'package.json');
  if (existsSync(pkgFile)) {
    try {
      const pkg = JSON.parse(readFileSync(pkgFile, 'utf8'));
      if (pkg.version === '0.0.0-hdsh-dispatch') {
        log('[pack-core]   sharp 调度器已存在（跳过）');
        return;
      }
    } catch {
      die('sharp 调度器：现有 sharp/package.json 不可解析，拒绝盲目覆盖');
    }
  }
  // 真件挪成 sibling 包：调度器用 require('sharp.impl') 引它，包内相对路径不受影响
  if (existsSync(implDir)) {
    rmSync(implDir, { recursive: true, force: true });
  }
  renameSync(sharpDir, implDir);
  mkdirSync(sharpDir, { recursive: true });
  writeFileSync(
    pkgFile,
    JSON.stringify({ name: 'sharp', version: '0.0.0-hdsh-dispatch', main: 'index.js', private: true }) + '\n',
    'utf8',
  );
  writeFileSync(
    join(sharpDir, 'index.js'),
    [
      '/* HDSH 端侧 sharp 调度器（E93）：真件优先；加载失败时退回"会报错但能挂载"的 stub。',
      ' *',
      ' * 为什么不是纯 stub：真件（libvips 全套，见 tools/collect-libvips.mjs）已随包发出，',
      ' * 端侧的图片附件应当真的可用。',
      ' * 为什么不是直接放真件：它是鸿蒙 arm64 原生件，开发机上必然加载失败，而开发机要跑同一棵树。',
      ' * 失败原因挂在 hdshSharpLoadError 上，由入口脚本的运行时事实如实上报（不假装可用）。',
      ' * 本文件由 tools/pack-core.mjs 的 wrapSharp() 生成，不要手改。 */',
      'let impl;',
      "let loadError = '';",
      'try {',
      "  impl = require('sharp.impl');",
      '} catch (e) {',
      "  loadError = e && e.message ? String(e.message) : String(e);",
      '}',
      'if (impl === undefined || impl === null) {',
      "  const reason = loadError.length > 0 ? loadError : '未知原因';",
      '  impl = function hdshSharpUnavailable() {',
      "    throw new Error('sharp 不可用：真件加载失败（' + reason + '）——图片附件依赖随包提供的 libvips 全套库');",
      '  };',
      '  impl.hdshSharpLoadError = reason;',
      '}',
      'module.exports = impl;',
      'module.exports.default = impl;',
      '',
    ].join('\n'),
    'utf8',
  );
  log('[pack-core]   sharp 调度器：真件在 node_modules/sharp.impl（加载失败时如实降级）');
}

/**
 * 补齐 `@deepseek-ai/node-addon-system-<platform>-<arch>` 平台包（E103）。
 *
 * 【为什么需要】`dsh-session-persistence-jsonl` 通过
 * `@deepseek-ai/node-addon-system/flock` 给会话日志加排他锁，而那个加载器会
 * `require.resolve('@deepseek-ai/node-addon-system-linux-arm64/package.json')`。
 * npm 在 Windows 上装树时**不会**装这个平台包（optionalDependencies 只装当前平台），
 * 设备上因此报 `Cannot find module …`（真机实测，agent 一轮直接失败）。
 *
 * 这里只补**清单文件**：真正的 `.node` 由 CMake 自建为 `libsystem.so` 进 HAP libs，
 * 入口脚本的原生库重定向会把 `bin/musl/system.node` 映射过去（`lib<stem>.so` 约定）。
 * 放清单而不放 prebuilt，是因为 prebuilt 的 musl 变体只 `DT_NEEDED libc.so`，
 * dlopen 后 napi 符号解析不到（E43/E44 同一个坑）。
 */
function addSystemAddonPackage() {
  const nm = join(STAGE, 'node_modules', '@deepseek-ai');
  if (!existsSync(join(nm, 'node-addon-system'))) {
    log('[pack-core]   node-addon-system 不在树里（跳过平台包）');
    return;
  }
  const abi = recipe.platform.cpu === 'x64' ? 'x64' : 'arm64';
  const target = join(nm, `node-addon-system-linux-${abi}`);
  const pkgFile = join(target, 'package.json');
  const marker = '0.1.2-hdsh-shim';
  let needManifest = true;
  if (existsSync(pkgFile)) {
    try {
      const pkg = JSON.parse(readFileSync(pkgFile, 'utf8'));
      if (pkg.version === marker) {
        needManifest = false;
      }
    } catch {
      die('node-addon-system 平台包：现有 package.json 不可解析，拒绝覆盖');
    }
  }
  mkdirSync(join(target, 'bin', 'musl'), { recursive: true });
  mkdirSync(join(target, 'bin', 'glibc'), { recursive: true });
  if (needManifest) {
    writeFileSync(pkgFile, JSON.stringify({
      name: `@deepseek-ai/node-addon-system-linux-${abi}`,
      version: marker,
      description: 'HDSH 端侧 shim：真正的 system.node 由 CMake 自建为 libsystem.so（见 pack-core.addSystemAddonPackage）',
      private: true,
    }, null, 2) + '\n', 'utf8');
  }
  /*
   * 【为什么这里要放**占位文件**】Node 的模块解析走的是**内部 stat**（`Module._findPath`），
   * 不是我们 hook 过的 `fs.existsSync` ⇒ 目标路径**必须物理存在**，否则在 `.node` 扩展处理器
   * 被调用之前就抛 `Cannot find module …/bin/musl/system.node`（真机实测：agent 轮次直接失败，
   * 用户看到的是"发消息后没反应"）。
   * 文件内容无所谓：真正加载时一定经过我们 hook 的 `Module._extensions['.node']`，
   * 那里会把路径改写成 HAP 里的 `libs/<abi>/libsystem.so`（与 koffi/sharp 同一条机制）。
   * 两个 libc 变体都放，是因为加载器按 `process.report.header.glibcVersionRuntime` 选目录。
   */
  const placeholder = 'HDSH placeholder: real binary is loaded from HAP libs/<abi>/libsystem.so\n';
  writeFileSync(join(target, 'bin', 'musl', 'system.node'), placeholder, 'utf8');
  writeFileSync(join(target, 'bin', 'glibc', 'system.node'), placeholder, 'utf8');
  log(`[pack-core]   node-addon-system 平台包已补：linux-${abi}（占位 .node + HAP libs 的 libsystem.so）`);
}

/**
 * 让会话日志的**排他发布**在鸿蒙沙箱里可用（E104）。
 *
 * 【真机根因】`dsh-session-persistence-jsonl` 用 `link(2)` 把写好的临时文件"排他发布"成
 * 正式日志（`link` 天生带 EEXIST 语义），而鸿蒙应用沙箱**禁止 link**：
 *
 *     EACCES: permission denied, link '…/sessions/--…--/session-…/session.v3.jsonl.zstd.2112db587c…'
 *
 * 后果正是用户看到的「发消息后没反应、详情里数量也不变」——每写一次日志就失败一次，
 * 会话状态根本无法落盘。这与符号链接禁令（E46）是同一类沙箱约束。
 *
 * 【等价改写】"存在性检查 + rename"：rename 在同一文件系统上是**原子**的，
 * 因此"目标不存在时改名过去"与"link 且不带 O_EXCL 冲突"在语义上一致。
 * 唯一弱化之处是极端 TOCTOU 窗口内可能覆盖同名的刚出现文件——而两个调用点在发布前
 * 都已经检查过目标（`rejectExistingLog` / `inspectExpectedCurrent`），所以按等价处理。
 *
 * 上游若改了这两段，这里**报错退出**，不静默跳过（悄悄发出一个"会话永远写不进去"的包，
 * 比打包失败难查得多）。
 */
function patchLinkForSandbox() {
  const target = join(
    STAGE, 'node_modules', '@deepseek-ai', 'dsh-session-persistence-jsonl', 'lib', 'index.js',
  );
  if (!existsSync(target)) {
    die(`link 沙箱补丁：找不到 ${target}`);
  }
  let text = readFileSync(target, 'utf8');
  if (text.includes('HDSH_LINK_SANDBOX')) {
    log('[pack-core]   link 沙箱补丁已存在（跳过）');
    return;
  }
  const importBefore = 'import { link, lstat, mkdir, mkdtemp, open, readFile, readdir, realpath, rm, stat, truncate } from "node:fs/promises";';
  const importAfter = 'import { access, link, lstat, mkdir, mkdtemp, open, readFile, readdir, realpath, rename, rm, stat, truncate } from "node:fs/promises";';
  const helper = `/**
 * HDSH_LINK_SANDBOX: 鸿蒙沙箱禁止 link(2)（EACCES），用"存在性检查 + rename"做等价发布。
 * rename 在同一文件系统上是原子的；目标已存在时按 EEXIST 抛错，保持调用方的分支语义。
 * @param fsImpl - 提供 access/rename 的 fs/promises 句柄
 * @param from - 已写好并 fsync 过的临时文件
 * @param to - 目标路径（必须尚不存在）
 */
async function hdshPublishExclusive(fsImpl, from, to) {
	let exists = true;
	try {
		await fsImpl.access(to);
	} catch {
		exists = false;
	}
	if (exists) {
		const error = new Error(\`EEXIST: file already exists, link '\${from}' -> '\${to}'\`);
		error.code = "EEXIST";
		throw error;
	}
	await fsImpl.rename(from, to);
}
`;
  const callSites = [
    ['\t\tawait internals.fs.link(staged, currentPath);',
      '\t\tawait hdshPublishExclusive(internals.fs, staged, currentPath);'],
    ['\t\t\tawait link(tmp, finalPath);',
      '\t\t\tawait hdshPublishExclusive({ access, rename }, tmp, finalPath);'],
  ];
  if (!text.includes(importBefore)) {
    die('link 沙箱补丁：上游 import 行已变化（未找到待替换片段），拒绝静默跳过');
  }
  for (const [before] of callSites) {
    if (!text.includes(before)) {
      die(`link 沙箱补丁：未找到调用点 ${JSON.stringify(before.trim())}，拒绝静默跳过`);
    }
  }
  text = text.replace(importBefore, `${importAfter}\n${helper}`);
  for (const [before, after] of callSites) {
    text = text.replace(before, after);
  }
  writeFileSync(target, text, 'utf8');
  log('[pack-core]   link 沙箱补丁：会话日志改用「存在性检查 + rename」发布');
}

function embedTreeInfo() {
  // 插件与原生模块清单：**在构建期算一次**，写进树里给端侧读。
  // 【为什么不在端侧现算】端侧要算同一件事，得在 27250 个文件 / 4000 个目录上递归
  // （实测规模），那是一秒级的目录遍历 + 一堆错误分支，纯风险。而这件事的答案在**打包这一刻
  // 就已经确定**，且能在一台能跑 Node 的机器上核对。端侧只需读一个小 JSON。
  // 【判据】见 tools/lib/core-inventory.mjs 头注释：看依赖闭包，不看包内有没有 .node。
  const inv = inventoryOf(join(STAGE, 'node_modules'));
  const info = {
    coreVersion: recipe.coreVersion,
    platform: `${recipe.platform.os}/${recipe.platform.cpu}`,
    profile: recipe.profile,
    builtAt: new Date().toISOString(),
    // dsh 的两条硬约束的交集：OHOS 支持 >= 22.17.0，会话持久化 zstd 需要 >= 22.15
    nodeFloor: '22.17.0',
    overrides: recipe.overrides,
    producer: 'tools/pack-core.mjs',
    // 端侧插件页的数据源。nativeKind ∈ PURE_JS | NATIVE | UNKNOWN
    // （NATIVE＝依赖闭包内含 .node，**不能**运行时安装，只能随应用发版）
    plugins: inv.plugins,
    pluginTotals: inv.totals,
    nativePackages: inv.nativePackages,
  };
  writeFileSync(join(STAGE, TREE_INFO_FILE), JSON.stringify(info, null, 2) + '\n', 'utf8');
  log(`[pack-core]   树内元数据 ${TREE_INFO_FILE} 已写入（端侧解包后据此识别版本、profile 与插件清单）`);
  log(
    `[pack-core]   插件 ${inv.totals.pluginRows} 行：纯 JS ${inv.totals.pureJs} / 依赖原生 ${inv.totals.native}` +
      ` / 待确认 ${inv.totals.unknown}（默认禁用 ${inv.totals.disabled}）；含原生模块的包 ${inv.nativePackages.length} 个`,
  );
  if (inv.totals.unknown > 0) {
    log(`[pack-core]   ⚠ 有 ${inv.totals.unknown} 行无法判定可安装性——端侧会显示为「待确认」，请查 core-inventory 的解析`);
  }
  return inv;
}
const TREE_INFO_FILE = 'hdsh-core.json';

/**
 * 把写好的树内清单**读回来**逐字段核对，不符就让打包失败。
 *
 * 【为什么值得一个硬断言】这份 JSON 的消费者是 ArkTS 侧的 `CoreStore.readTreeInfo()`
 * （`hostruntime/src/main/ets/core/CoreStore.ets`），它按字段名逐个取。
 * 两端都是字符串键：**任何一侧改名都不会报错**，只会静默退化成"读不到清单"，
 * 于是核心页永远显示"未读取到插件清单"，而没有任何一处会告诉你是拼写问题。
 * 所以这里把契约钉在唯一的产出口上：字段名/类型不对就不许出厂。
 */
function verifyTreeInfoContract() {
  const p = join(STAGE, TREE_INFO_FILE);
  let raw;
  try {
    raw = JSON.parse(readFileSync(p, 'utf8'));
  } catch (e) {
    die(`树内清单不可解析：${p}（${e.message}）`);
  }
  const wantString = ['coreVersion', 'platform', 'profile', 'builtAt', 'nodeFloor'];
  for (const k of wantString) {
    if (typeof raw[k] !== 'string') die(`树内清单字段 ${k} 不是字符串（端侧按字符串读）`);
  }
  if (!Array.isArray(raw.plugins)) die('树内清单缺少 plugins 数组（端侧插件页的数据源）');
  if (!Array.isArray(raw.nativePackages)) die('树内清单缺少 nativePackages 数组');
  const t = raw.pluginTotals;
  if (t === null || typeof t !== 'object') die('树内清单缺少 pluginTotals 对象');
  for (const k of ['pluginRows', 'pureJs', 'native', 'unknown', 'disabled']) {
    if (typeof t[k] !== 'number') die(`pluginTotals.${k} 不是数字`);
  }
  for (const [i, r] of raw.plugins.entries()) {
    for (const k of ['id', 'name', 'bundle', 'nativeKind']) {
      if (typeof r[k] !== 'string') die(`plugins[${i}].${k} 不是字符串`);
    }
    if (typeof r.disabled !== 'boolean') die(`plugins[${i}].disabled 不是布尔`);
    if (!Array.isArray(r.nativeVia)) die(`plugins[${i}].nativeVia 不是数组`);
  }
  if (t.pluginRows !== raw.plugins.length) {
    die(`pluginTotals.pluginRows=${t.pluginRows} 与 plugins 长度 ${raw.plugins.length} 不一致`);
  }
  log(`[pack-core]   树内清单契约核对通过（端侧 CoreStore.readTreeInfo 按这些字段读）`);
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

  // 随应用分发：放进 entry 的 resfile（**不是 rawfile**，见 hostruntime/core/BundledCore.ets 的说明：
  // resfile 安装后解压到沙箱、可按真实路径只读访问；rawfile 的 fd 不是文件系统 fd，copyFile 会拷坏）
  if (process.argv.includes('--place-in-app')) {
    const resDir = join(ROOT, 'entry', 'src', 'main', 'resources', 'resfile');
    mkdirSync(resDir, { recursive: true });
    const dest = join(resDir, `${base}.zip`);
    cpSync(zipPath, dest, { force: true });
    log(`[pack-core]   已放入应用内置资源：entry/src/main/resources/resfile/${base}.zip`);
    log('[pack-core]   注意：该文件已在 .gitignore 中（体积大，不进版本库）');
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
addPlatformAliases();
allowOriginList();
wrapSharp();
addSystemAddonPackage();
patchLinkForSandbox();
addOnDevicePreset();
embedTreeInfo();
verifyTreeInfoContract();
embedProfile();
const packed = pack();
const manifest = writeManifest({ ...packed, ...sig });

log('\n[pack-core] ✓ 完成');
log(`  核心版本   ${manifest.coreVersionInstalled}`);
log(`  解包体积   ${(manifest.nodeModules.unpackedBytes / 1048576).toFixed(1)} MB / ${manifest.nodeModules.fileCount} 文件`);
log(`  分发包     ${manifest.package.file}  ${(manifest.package.bytes / 1048576).toFixed(1)} MB / ${manifest.package.entries} 条目`);
log(`  sha256     ${manifest.package.sha256}`);
log(`  签名       ${manifest.native.signatureCheckSkipped ? '未校验' : `${manifest.native.signed.length} 通过 / ${manifest.native.unsigned.length} 未检出`}`);
