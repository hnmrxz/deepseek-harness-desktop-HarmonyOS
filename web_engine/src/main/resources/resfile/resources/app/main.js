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

/**
 * 路径从哪来（**这一环不能靠环境变量**）
 *
 * 我们跑在 Electron 主进程里：`runBrowser()` 是 native 侧直接启动的，
 * ArkTS **没有**给这个进程设环境变量的通道。所以路径必须由 Node 侧自己定位。
 * Electron 的 `app.getPath('userData')` 就是应用沙箱内的可写目录（社区已验证可用），
 * 于是约定：`<userData>/dsh/` 下放 cores/ 与 home/。
 * 环境变量仍然优先生效——那是给"宿主侧离线验证 / 调试"用的。
 */
function electronUserData() {
  try {
    // 只有真的在 Electron 主进程里才有这个模块；离线跑 Node 时会抛错，走 env 回退
    const electron = require('electron');
    if (electron && electron.app && typeof electron.app.getPath === 'function') {
      return electron.app.getPath('userData');
    }
  } catch (e) {
    // 忽略：不是 Electron 环境
  }
  return '';
}

const USER_DATA = electronUserData();
const DSH_BASE = USER_DATA.length > 0 ? path.join(USER_DATA, 'dsh') : '';

/** 读我们自己的 state.json，得到"当前版本"，据此拼出核心树目录。 */
function currentCoreDir() {
  if (DSH_BASE.length === 0) {
    return '';
  }
  try {
    const statePath = path.join(DSH_BASE, 'state.json');
    if (!fs.existsSync(statePath)) {
      return '';
    }
    const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
    if (typeof state.current !== 'string' || state.current.length === 0) {
      return '';
    }
    return path.join(DSH_BASE, 'cores', state.current);
  } catch (e) {
    return '';
  }
}

const CORE_DIR = process.env.HDSH_CORE_DIR || currentCoreDir();
const HOME_DIR = process.env.HDSH_HOME || (DSH_BASE.length > 0 ? path.join(DSH_BASE, 'home') : '');
const SANDBOX_HOME = process.env.HDSH_SANDBOX_HOME || USER_DATA || HOME_DIR;
const PORT = process.env.HDSH_PORT || '3120';
const PROFILE = process.env.HDSH_PROFILE || 'ondevice';

function log(msg) {
  // 统一前缀，便于 ArkTS / 诊断页从日志里认出我们的行
  console.log('[hdsh-host] ' + msg);
}

/**
 * 阻止 Electron 的"无窗口即退出"默认行为。
 *
 * 【为什么必须有这一段】Electron 的语义是：若**没有订阅** `window-all-closed`，
 * 且所有窗口都关闭，则默认 **quit**。我们是一个**永不建窗**的 Node 宿主
 * （D6 §4.1.2：只跑 Node，不 new BrowserWindow），所以在它眼里"所有窗口都已关闭"，
 * 于是启动后立刻退出。真机实测到的正是这个：
 *   `APPSPAWN: Unexpected call: exit(1)`  —— 应用进程被自己的运行时结束掉。
 * 订阅一个空监听即可跳过默认行为（Electron 文档明示：订阅了就不执行默认动作）。
 */
function keepAliveWithoutWindows() {
  try {
    const electron = require('electron');
    if (electron && electron.app && typeof electron.app.on === 'function') {
      electron.app.on('window-all-closed', () => {
        log('window-all-closed：按无窗口宿主语义保持存活（不退出）');
      });
      log('已注册 window-all-closed 保活监听');
    }
  } catch (e) {
    log('注册保活监听失败（非 Electron 环境？）：' + e.message);
  }
}

keepAliveWithoutWindows();

function fail(msg) {
  // 【绝不能调 process.exit()】libelectron.so 是**同进程**跑的：
  // 这里的 exit 会连同宿主 ArkUI 应用一起杀掉。
  // 真机实测症状：启动后窗口被销毁、进程消失、hilog 里既没有 JS 异常也没有崩溃记录——
  // 看起来像"莫名其妙退出"，实际是我们自己把进程结束了。
  // 正确做法：把原因打出来、把失败状态留在全局，让进程活着（上层/诊断页据此如实展示）。
  console.error('[hdsh-host] FATAL ' + msg);
  globalThis.__hdshHostError = msg;
  throw new Error('HDSH host fatal: ' + msg);
}

// 【为什么这里不校验、也不 throw】顶层抛异常同样会掀掉整个宿主应用
// （这些行在 process.on('uncaughtException') 注册之前执行）。
// 校验一律放进被 .catch() 包住的 start() 里。
function reportConfigError() {
  const missing = [];
  if (CORE_DIR.length === 0) {
    missing.push('HDSH_CORE_DIR（当前版本的核心树目录）');
  }
  if (HOME_DIR.length === 0) {
    missing.push('HDSH_HOME（$DSH_HOME，跨版本共享的用户数据目录）');
  }
  return missing;
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

/**
 * 让 dsh 走"ESM proxy 目录"而不是"符号链接"来建模块回退。
 *
 * 【为什么必须这么做 —— 有真机证据】
 * dsh 启动时会由 `healProfilesModuleFallback` 在 `$DSH_HOME/profiles/node_modules` 下
 * 建立依赖闭包的链接（`dsh-app-boot` 源码 `resolveModuleFallbackEntries`）：
 *
 *     entries: !isPackagedExecutable()
 *       ? [...].map(... { kind: "symlink" })   // 普通 Node：写符号链接
 *       : [...].flatMap(... { kind: "proxy" }) // pkg 打包：写真实目录 + entry-N.js
 *
 * 而鸿蒙沙箱**全局禁止创建符号链接**：本机真机（Mate 70 Pro+ / API 26）探针实测
 * `filesDir` / `cacheDir` / `tempDir` 三个目录全部返回
 * `13900012 Permission denied`。⇒ 走 symlink 分支必然 boot 失败（D6 §4.1.3）。
 *
 * 【为什么这样绕是合法的，而不是 hack】
 * `isPackagedExecutable()` 的实现只有一句 `process.pkg !== void 0`；而 proxy 分支的实现
 * （`ensureModuleProxy`）**完全基于普通文件系统 API**——`mkdirSync` + `writeFileSync`，
 * 写出的每个 `entry-N.js` 就是 `export * from "<file:// URL>"`。
 * pkg 只出现在那段代码的**动机注释**里，运行路径上没有任何 pkg 虚拟文件系统依赖。
 * 也就是说：proxy 形态在普通 Node 下同样成立，我们只是让 dsh 选对了分支。
 *
 * 【风险（要在真机上验证，别当成已解决）】
 * 1. 其它依赖若也探测 `process.pkg` 并据此改变行为，可能被这一行影响；
 * 2. `$DSH_HOME/profiles/node_modules` 会从"一堆链接"变成"一堆小目录"（文件数变多）。
 * 在真机上跑通 boot 之前，这条只算"有依据的候选方案"。
 */
process.pkg = process.pkg || {};

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
  const missing = reportConfigError();
  if (missing.length > 0) {
    // 不 throw、不 exit：只如实记录。核心还没装好时这就是正常状态，
    // 上层（核心页）据此显示"尚未安装核心"，而不是让应用消失。
    console.error('[hdsh-host] 缺少：' + missing.join('；') + '。核心尚未就绪，Host 不启动。');
    globalThis.__hdshHostError = 'missing-config: ' + missing.join(';');
    return;
  }
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
