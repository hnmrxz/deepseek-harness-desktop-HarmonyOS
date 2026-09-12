'use strict';
/**
 * HDSH 端侧 Host 启动脚本（Node 侧，跑在嵌入式 Node 运行时里）。
 *
 * 职责（对应 D6 §4.1 R5/R6 与 §6.1）：
 *   1. 把 HOME / DSH_HOME 指向应用沙箱（鸿蒙的 `os.homedir()` 返回沙箱外目录，会 EPERM）
 *   2. 把核心树里的端侧 profile 装到 $DSH_HOME/profiles/<name>（dsh 只认 $DSH_HOME 下那份）
 *   3. 以**进程内**方式 runProfile 起 Host，只监听 127.0.0.1，不打开浏览器、不开窗口
 *   4. 把实际监听端口打到 stdout（ArkTS 侧据此做健康检查与接线）
 *
 * 为什么不用 child_process 再起一个 node：鸿蒙对创建进程有平台级限制（D6 E15），
 * 而 in-process runProfile 是社区已验证可行的路径。
 *
 * 环境变量（由 ArkTS 侧设置）：
 *   HDSH_CORE_DIR      核心树根目录（内含 node_modules/ 与 profiles/）
 *   HDSH_HOME          $DSH_HOME（跨版本共享的用户数据目录）
 *   HDSH_SANDBOX_HOME  HOME（可写沙箱目录）
 *   HDSH_PORT          监听端口（默认 3120）
 *   HDSH_PROFILE       profile 名（默认 ondevice）
 */
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const CORE_DIR = process.env.HDSH_CORE_DIR || '';
const HOME_DIR = process.env.HDSH_HOME || '';
const SANDBOX_HOME = process.env.HDSH_SANDBOX_HOME || HOME_DIR;
const PORT = process.env.HDSH_PORT || '3120';
const PROFILE = process.env.HDSH_PROFILE || 'ondevice';

function log(msg) {
  // 统一前缀，便于 ArkTS / 诊断页从日志里认出我们的行
  console.log('[hdsh-host] ' + msg);
}

function fail(msg) {
  console.error('[hdsh-host] FATAL ' + msg);
  process.exit(1);
}

if (CORE_DIR.length === 0 || HOME_DIR.length === 0) {
  fail('HDSH_CORE_DIR / HDSH_HOME 未设置，无法启动');
}

// ── 1. 沙箱 HOME ────────────────────────────────────────────────────────
// dsh 的目录选择器以 os.homedir() 为起点；鸿蒙下它指向沙箱外目录（EPERM）。
// 必须在任何 dsh 代码调用 homedir() 之前设置。
process.env.HOME = SANDBOX_HOME;
process.env.USERPROFILE = SANDBOX_HOME;
process.env.DSH_HOME = HOME_DIR;
// 端侧不需要的开关（有实测依据：HMR 依赖 --expose-internals；遥测默认关）
process.env.DSH_DISABLE_HMR = '1';
process.env.DSH_TELEMETRY_DISABLED = '1';

function ensureDir(p) {
  try {
    fs.mkdirSync(p, { recursive: true });
  } catch (e) {
    if (e && e.code !== 'EEXIST') {
      log('mkdir 失败 ' + p + ' : ' + e.message);
    }
  }
}

/** 找到 dsh CLI 的 profile-boot 薄入口（re-export runProfile）。 */
function findProfileBootEntry(cliLibDir) {
  const files = fs.readdirSync(cliLibDir);
  for (const f of files) {
    if (!f.startsWith('profile-boot-') || !f.endsWith('.js')) {
      continue;
    }
    const full = path.join(cliLibDir, f);
    const text = fs.readFileSync(full, 'utf8');
    // 那个 `export { runProfile }` 的薄入口很小（几十字节），据此与实现文件区分
    if (text.includes('runProfile') && text.length < 400) {
      return full;
    }
  }
  return null;
}

/**
 * 把核心树里的端侧 profile 装到 $DSH_HOME/profiles/<name>。
 * 幂等：文件始终用核心树里的最新版覆盖（壳的 patch 层必须随核心版本更新），
 * 但 package.json 若已存在则只补缺失的字段，避免覆盖掉用户装的插件。
 */
function ensureProfile() {
  const src = path.join(CORE_DIR, 'profiles', PROFILE);
  if (!fs.existsSync(src)) {
    fail('核心树里没有 profiles/' + PROFILE + '：' + src);
  }
  const dest = path.join(HOME_DIR, 'profiles', PROFILE);
  ensureDir(dest);
  const srcPkg = path.join(src, 'package.json');
  const destPkg = path.join(dest, 'package.json');
  if (!fs.existsSync(destPkg)) {
    fs.copyFileSync(srcPkg, destPkg);
  } else {
    try {
      const seed = JSON.parse(fs.readFileSync(srcPkg, 'utf8'));
      const cur = JSON.parse(fs.readFileSync(destPkg, 'utf8'));
      cur.dsh = cur.dsh || {};
      cur.dsh.profile = cur.dsh.profile || {};
      const merged = new Set((cur.dsh.profile.bundles || []).concat(seed.dsh.profile.bundles || []));
      cur.dsh.profile.bundles = Array.from(merged);
      cur.dsh.profile.patchReload = seed.dsh.profile.patchReload || cur.dsh.profile.patchReload;
      fs.writeFileSync(destPkg, JSON.stringify(cur, null, 2) + '\n');
    } catch (e) {
      log('合并 profile package.json 失败，沿用已有文件：' + e.message);
    }
  }
  for (const name of fs.readdirSync(src)) {
    if (name === 'package.json') {
      continue;
    }
    fs.copyFileSync(path.join(src, name), path.join(dest, name));
  }
  log('profile 已就位：' + dest);
}

async function start() {
  const cliLibDir = path.join(CORE_DIR, 'node_modules', '@deepseek-ai', 'dsh', 'lib');
  if (!fs.existsSync(cliLibDir)) {
    fail('核心树里找不到 dsh CLI：' + cliLibDir);
  }
  const entry = findProfileBootEntry(cliLibDir);
  if (entry === null) {
    fail('找不到 profile-boot 入口（核心树可能不完整）');
  }
  const appBoot = path.join(CORE_DIR, 'node_modules', '@deepseek-ai', 'dsh-app-boot', 'lib', 'index.js');
  if (!fs.existsSync(appBoot)) {
    fail('找不到 dsh-app-boot：' + appBoot);
  }

  ensureDir(HOME_DIR);
  ensureProfile();

  log('导入 ' + entry);
  const profileBoot = await import(pathToFileURL(entry).href);
  const appBootMod = await import(pathToFileURL(appBoot).href);

  const args = ['--port', PORT, '--host', '127.0.0.1', '--no-open', '--skip-auth'];
  log('runProfile profile=' + PROFILE + ' args=' + args.join(' '));

  const result = await profileBoot.runProfile({
    environment: appBootMod.loadLayeredEnv('dsh'),
    profile: PROFILE,
    patchFiles: [],
    args: args,
  });

  const ctx = result && result.ctx;
  if (!ctx || !ctx.webServer) {
    fail('runProfile 返回了但没有 webServer');
  }
  // 这行是给 ArkTS 侧的机器可读信号：ArkTS 会等到端口可连为止
  console.log('HDSH_READY ' + JSON.stringify({
    port: ctx.webServer.port,
    home: HOME_DIR,
    profile: PROFILE,
  }));
  log('Host 已就绪，端口 ' + ctx.webServer.port);

  const shutdown = result.shutdown;
  process.on('SIGTERM', () => {
    log('收到 SIGTERM，关闭 Host');
    try {
      shutdown.shutdown(0);
    } catch (e) {
      log('shutdown 抛错：' + e.message);
    }
  });
}

process.on('uncaughtException', (e) => {
  console.error('[hdsh-host] uncaughtException: ' + (e && e.stack ? e.stack : String(e)));
});
process.on('unhandledRejection', (e) => {
  console.error('[hdsh-host] unhandledRejection: ' + (e && e.stack ? e.stack : String(e)));
});

start().catch((e) => {
  fail('启动失败：' + (e && e.stack ? e.stack : String(e)));
});
