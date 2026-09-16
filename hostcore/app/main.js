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

/*
 * ── 诊断引导（必须在一切之前）──────────────────────────────────────────────
 *
 * 【为什么需要它】真机崩溃日志（D6 E23）显示：应用起来后 2 秒内以
 *   Reason:Signal:SIGABRT   LastFatalMessage:[appspawn_server.c:69]Unexpected call: exit(1)
 * 结束，调用栈是 node::LoadEnvironment → node::StartExecution → JS → 某个 native → exit()。
 * 也就是说**是 JS 调用了 process.exit(1)**，而不是原生引导崩溃。
 * 但排查被卡住的原因很具体：**Node 的 console.log 走 stdout，在应用进程里不进 hilog**，
 * 所以"看不到日志"被误读成"代码没跑"（这个误判浪费了很久）。
 *
 * 因此这里做两件事：
 *   1. 把 stdout/stderr 与关键里程碑**落进文件**，事后用 `hdc file recv` 取回；
 *   2. 拦截 `process.exit`：先把**调用栈**写进日志，然后**不真的退出**。
 *      理由：OHOS 用 libappspawn_helper 拦截应用进程里的 exit()，真调用它只会换来
 *      SIGABRT（拿不到任何解释）；而"不退出"能让进程活着，把更多信息留下来。
 *      这是**诊断期**的行为，正式形态要不要保留见 D6 的 fail-loud 讨论。
 *
 * 【为什么写在最前面】后面的任何一行都可能抛错或退出；先装好这些，才拿得到原因。
 */
const DIAG_LOG = path.join(
  // 优先落在**调用方传进来的沙箱目录**（阶段二由 buildHostEnv 传 HDSH_SANDBOX_HOME）：
  // 那个目录我们能直接用 `hdc shell ls` 看到并取回，而 os.tmpdir() 落在哪里不好找。
  process.env.HDSH_SANDBOX_HOME && process.env.HDSH_SANDBOX_HOME.length > 0
    ? process.env.HDSH_SANDBOX_HOME
    : (USER_DATA.length > 0 ? USER_DATA : require('node:os').tmpdir()),
  'hdsh-host.log');
let diagStream = null;
function diag(line) {
  const text = `[${new Date().toISOString()}] ${line}\n`;
  try {
    if (diagStream === null) {
      diagStream = fs.createWriteStream(DIAG_LOG, { flags: 'a' });
      diagStream.on('error', () => { diagStream = null; });
    }
    diagStream.write(text);
  } catch (e) {
    // 写不进去也不能让诊断本身把启动搞崩
  }
  // 同时也往 stdout 打：PC 侧离线跑时能直接看见
  try { process.stdout.write(text); } catch (e) { /* ignore */ }
}

diag(`--- boot pid=${process.pid} execPath=${process.execPath} argv=${JSON.stringify(process.argv)}`);
diag(`userData=${USER_DATA} DSH_BASE=${DSH_BASE}`);
// koffi 按 `${root}/build/koffi/${process.platform}_${process.arch}/koffi.node` 找原生模块
// （见 node_modules/koffi/index.js:468-499）。我们随包放的是 `openharmony_arm64`，
// 所以要如实打印这两个值，才能判断它到底在找哪个目录名。
diag(`platform=${process.platform} arch=${process.arch} versions=${JSON.stringify(process.versions)}`);

const realExit = process.exit.bind(process);
/**
 * 是否允许真正退出（E90）。
 *
 * 【为什么需要这个开关】诊断期我们**故意**让 `process.exit` 空转：真退出在 OHOS 上会
 * 变成 SIGABRT 之类"什么都不留下"的结束，而引导阶段的失败信息是当时唯一的线索。
 * 但"停止核心"必须能真的停下来（核心切换/回滚的前置条件），所以给协作式停止留一个
 * **显式**的放行开关：只有停止路径会把它置真，其它任何 `process.exit` 仍被拦住并记录。
 */
let ALLOW_EXIT = false;
process.exit = (code) => {
  if (ALLOW_EXIT) {
    diag(`!! process.exit(${code})：停止路径放行，真正退出`);
    return realExit(code);
  }
  const stack = new Error('process.exit intercepted').stack || '(no stack)';
  diag(`!! process.exit(${code}) called -- intercepted, NOT exiting`);
  diag(`!! stack: ${String(stack).split('\n').join(' | ')}`);
  // 诊断期不退出：真退出在 OHOS 上会变成 SIGABRT，什么解释都留不下
  return undefined;
};

process.on('uncaughtException', (err) => {
  diag(`!! uncaughtException: ${err && err.stack ? err.stack : String(err)}`);
});
process.on('unhandledRejection', (reason) => {
  diag(`!! unhandledRejection: ${reason && reason.stack ? reason.stack : String(reason)}`);
});
process.on('exit', (code) => {
  diag(`!! process 'exit' event, code=${code}`);
});

/*
 * 【必须保留】阻断 `node:http` 的惰性 undici。
 * 关键栈帧（D6 E38）：`at lazyUndici (node:http:123:21)`。Node 22 用 undici 实现
 * `http.Agent`/`globalAgent` 等；只要在任何人访问之前把**所有惰性 getter** 定义掉，
 * 那条路径就不会被触发，也就不需要 WebAssembly（jitless 下它是 undefined）。
 * 不能先读原值（读一下就触发初始化）——只能用 getOwnPropertyDescriptor 看描述符。
 */
try {
  for (const modName of ['node:http', 'node:https']) {
    const mod = require(modName);
    const getters = [];
    for (const name of Object.getOwnPropertyNames(mod)) {
      const desc = Object.getOwnPropertyDescriptor(mod, name);
      if (desc !== undefined && desc.get !== undefined) {
        getters.push(name);
        Object.defineProperty(mod, name, { value: {}, writable: true, configurable: true });
      }
    }
    diag(`${modName} 的惰性 getter（已全部封掉）：${getters.join(', ') || '(无)'}`);
  }
} catch (e) {
  diag(`封掉惰性 getter 失败：${String(e)}`);
}

/*
 * 【诊断（E81）】入站请求观测：把 WS 升级与普通请求的**原始事实**打出来。
 *
 * 【为什么分两档】`upgrade` 事件**罕见且决定性**（一次握手一行），所以永远打；
 * 普通请求每个 RPC 都来一行，长期开着会把 hilog 冲掉——实测它曾经把真正要看的
 * 模型报错挤出窗口。于是普通请求那档用 `HDSH_IN_LOG=1` 显式打开。
 *
 * 为什么要在 `node:http` 这一层做：`dsh-host-webserver` 的升级路由在**未匹配**时
 * 只 `socket.destroy()`（日志里什么都没有），匹配到普通路由时也不打印任何东西。
 * 于是端侧只看到「客户端报 ws 升级响应不是 101、状态码 200」这个**二手的结论**，
 * 无法区分三种完全不同的原因：
 *   (a) 客户端根本没发升级头（服务端按普通 GET 处理，落到 SPA 回退 → 200）；
 *   (b) 升级头发了、路径不对（未匹配路由 → destroy，客户端看到"连接被断"）；
 *   (c) 升级头与路径都对、只是 cookie 没带上（fence 回 401）。
 * 只有服务端侧的原始读数能把它们分开，所以在 `createServer` 上挂自己的监听器
 * ——不改 dsh 一行代码，也不影响任何既有行为。
 */
try {
  for (const modName of ['node:http', 'node:https']) {
    const mod = require(modName);
    const origCreate = mod.createServer;
    if (typeof origCreate === 'function' && origCreate.__hdshWrapped !== true) {
      const wrapped = function (...args) {
        const server = origCreate.apply(this, args);
        try {
          server.on('upgrade', (req) => {
            const h = req.headers || {};
            diag(`IN-UPGRADE ${req.method} ${req.url} conn=${h.connection} upgrade=${h.upgrade}` +
              ` key=${h['sec-websocket-key'] === undefined ? 'no' : 'yes'}` +
              ` ver=${h['sec-websocket-version']} cookie=${h.cookie === undefined ? '(none)' : h.cookie.length + 'B'}` +
              ` origin=${h.origin}`);
          });
          server.on('request', (req) => {
            if (process.env.HDSH_IN_LOG !== '1') return;
            const h = req.headers || {};
            diag(`IN-REQ ${req.method} ${req.url} conn=${h.connection} upgrade=${h.upgrade}` +
              ` cookie=${h.cookie === undefined ? '(none)' : h.cookie.length + 'B'}` +
              ` origin=${h.origin} ua=${h['user-agent']}`);
          });
        } catch (e) {
          diag(`IN-LOG 挂载失败：${String(e)}`);
        }
        return server;
      };
      wrapped.__hdshWrapped = true;
      mod.createServer = wrapped;
    }
  }
  diag('入站请求诊断已安装（IN-UPGRADE / IN-REQ）');
} catch (e) {
  diag(`入站请求诊断安装失败：${String(e)}`);
}

/*
 * 【关键】把"沙箱里的 .node"重定向到 HAP 的 libs/ 下加载。
 *
 * 问题（D6 E39，真机实测）：运行时解包到**沙箱**里的原生库，`dlopen` 会被系统拦：
 *   Error loading shared library …/cores/0.1.5-rc.2/node_modules/koffi/build/koffi/linux_arm64/koffi.node
 *   : No error information
 * 而放在 HAP `libs/` 里的库可以正常加载（E18 已证，即使没有 `.codesign`）。hvigor 又**只打包
 * 扁平的 `libs/<abi>/*.so`**（实测：嵌套的 `.node` 不会被复制进产物），所以没法按 loader 的
 * 候选路径原样摆放。
 *
 * 办法（不碰任何第三方包，也不改 dsh）：原生包的 loader 在 `require` 之前都会先
 * `fs.existsSync(候选路径)`，而真正加载 `.node` 一定经过 `Module._extensions['.node']`。
 * 于是同时接管这两处：
 *   - `existsSync` 对那些"沙箱里不存在、但 libs/ 里有同名平铺文件"的 .node 路径返回 true；
 *   - `.node` 扩展加载器把实际路径改写成 libs/ 下的平铺文件。
 * 这样 koffi / node-pty / sharp 的**原样查找逻辑**就能走到 HAP 里的合法位置。
 */
const NATIVE_LIBS = (() => {
  if (process.env.HDSH_NATIVE_LIBS && process.env.HDSH_NATIVE_LIBS.length > 0) {
    return process.env.HDSH_NATIVE_LIBS;
  }
  // 入口脚本在 <bundle>/entry/resources/resfile/resources/app/main.js，
  // 而原生库在 <bundle>/libs/arm64/（见真机崩溃日志里的 libelectron.so 路径）。
  try {
    const bundleRoot = require('node:path').resolve(__dirname, '../../../../../');
    return require('node:path').join(bundleRoot, 'libs', 'arm64');
  } catch (e) {
    return '';
  }
})();

/** 沙箱内的 .node 路径 → libs/ 下的平铺文件名。约定：`lib<去掉扩展名的包名>.so` */
function flatNativeName(basename) {
  const stem = String(basename).replace(/\.node$/, '');
  return `lib${stem}.so`;
}

(function installNativeRedirect() {
  const fsMod = require('node:fs');
  const pathMod = require('node:path');
  const Module = require('node:module');
  if (NATIVE_LIBS.length === 0 || !fsMod.existsSync(NATIVE_LIBS)) {
    diag(`原生库重定向未启用（NATIVE_LIBS=${NATIVE_LIBS}）`);
    return;
  }
  const realExists = fsMod.existsSync.bind(fsMod);
  const redirect = (p) => {
    try {
      if (typeof p !== 'string' || !p.endsWith('.node')) return null;
      const flat = pathMod.join(NATIVE_LIBS, flatNativeName(pathMod.basename(p)));
      return realExists(flat) ? flat : null;
    } catch (e) {
      return null;
    }
  };
  // 1) 让 loader 的"存在性检查"通过
  fsMod.existsSync = function (p) {
    return redirect(p) !== null ? true : realExists(p);
  };
  // 2) 真正加载时改写到 libs/ 下的合法位置
  const loader = Module._extensions['.node'];
  Module._extensions['.node'] = function (mod, filename) {
    const flat = redirect(filename);
    return loader.call(this, mod, flat !== null ? flat : filename);
  };
  diag(`原生库重定向已启用：libs=${NATIVE_LIBS}`);
})();

/*
 * jitless 下的 fetch 垫片（D6 E52）。
 *
 * 【为什么必须有】`--jitless` 隐含关掉 WASM，而 Node 自带 undici 用 WASM 版 llhttp
 * ⇒ 原生 fetch 在端侧不可用。于是我们既封了 `node:http` 的惰性 getter（E39），
 * 又用 `--no-experimental-fetch` 让 Node 不去装 globalThis.fetch（E34/E35）。
 * 但 dsh **调模型就是用 fetch**（`dsh-llm-deepseek/lib/index.js:1770`）——
 * 不垫它，"Host 起来了"也只是个不能干活的空壳。
 * 垫片基于 `node:http`/`node:https`（原生 llhttp，与 WASM 无关），见 fetch-shim.js 的文件头。
 *
 * 只在原生 fetch 不可用时安装：本机调试（未加 --no-experimental-fetch）时用的仍是原生实现。
 */
(function installJitlessFetch() {
  try {
    // eslint-disable-next-line global-require
    const shim = require('./fetch-shim.js');
    const installed = shim.installFetchShim();
    diag(installed
      ? 'jitless fetch 垫片已安装（基于 node:http/https；原生 fetch 不可用）'
      : '原生 fetch 可用，未安装 jitless 垫片');
  } catch (e) {
    diag(`fetch 垫片安装失败：${e && e.message}`);
  }
})();

/*
 * 鸿蒙沙箱拒绝 `link()` 时的降级垫片（F1，2026-09-16 真机取证）。
 *
 * 【症状】agent 的 `write` 在真机上**必然失败**：
 *   `EACCES: permission denied, link '<workspace>/..x.md.<pid>.<uuid>.tmpdir/x.md.tmp' -> '<workspace>/x.md'`
 * 上游 `@deepseek-ai/dsh-fs-local` 的 `writeFileAtomic()` 走"同目录 staging → 原子发布"：
 * **新建**用 `link()`（no-replace 语义）、覆盖用 `rename()`。真机错在 `link()`，
 * 两端同目录 ⇒ **不是 EXDEV，是沙箱策略拒绝 linkat**。
 *
 * 【为什么在这里降级，而不是改上游】本仓不变式：不改上游源码、不改核心树，端侧差异只走运行期组合
 * （与 `installNativeRedirect` 同一手法）。
 *
 * 【降级成什么】`copyFile(tmp, dst, COPYFILE_EXCL)`：
 *   · **保住**"不覆盖已存在文件"这条语义（`COPYFILE_EXCL` 与 `link` 的 no-replace 等价）；
 *   · **丢掉**原子性与"同 inode" —— 这是实打实的取舍，所以**必须往旁路日志如实打一行**，
 *     并且只在第一次命中时打（不刷屏）。
 *
 * 【为什么要打 errno 原文】不靠猜：第一次命中时把 `code`/`errno`/`syscall` 原样记下来，
 * 万一将来鸿蒙给的是别的码（或 `copyFile` 也被拒），日志里能直接看出是哪一种。
 *
 * 【为什么用 defineProperty 而不是赋值】`node:fs` / `node:fs/promises` 的导出是
 * **getter-only** 属性，直接赋值在非严格模式下会静默失败——那会变成"装了垫片但没生效"，
 * 正是本项目最忌讳的"改了、看起来绿、实际没用"。
 */
(function installLinkFallback() {
  let reported = false;
  const DEGRADE_CODES = ['EACCES', 'EPERM', 'ENOSYS', 'EOPNOTSUPP', 'ENOTSUP'];
  const note = (e, from, to) => {
    if (reported) return;
    reported = true;
    diag('link() 被沙箱拒绝，已降级为 copyFile(COPYFILE_EXCL)：'
      + `${from} -> ${to}（code=${e && e.code} errno=${e && e.errno} syscall=${e && e.syscall}）；`
      + 'no-replace 语义保持，原子性减弱（已登记为端侧已知取舍）');
  };
  try {
    const fsp = require('node:fs/promises');
    const fsMod = require('node:fs');
    const realLink = fsp.link.bind(fsp);
    const realCopyFile = fsp.copyFile.bind(fsp);
    const realLinkSync = fsMod.linkSync.bind(fsMod);
    const realCopyFileSync = fsMod.copyFileSync.bind(fsMod);
    const excl = fsMod.constants.COPYFILE_EXCL;
    const patchedLink = async (from, to) => {
      try {
        return await realLink(from, to);
      } catch (e) {
        if (!e || DEGRADE_CODES.indexOf(e.code) < 0) throw e;
        note(e, from, to);
        return await realCopyFile(from, to, excl);
      }
    };
    const patchedLinkSync = (from, to) => {
      try {
        return realLinkSync(from, to);
      } catch (e) {
        if (!e || DEGRADE_CODES.indexOf(e.code) < 0) throw e;
        note(e, from, to);
        return realCopyFileSync(from, to, excl);
      }
    };
    // `require('node:fs').promises` 与 `require('node:fs/promises')` 在 Node 里是同一个对象，
    // 所以这一处 defineProperty 同时覆盖两条 require 路径。
    Object.defineProperty(fsp, 'link', { value: patchedLink, writable: true, configurable: true, enumerable: true });
    Object.defineProperty(fsMod, 'linkSync', { value: patchedLinkSync, writable: true, configurable: true, enumerable: true });
    diag('link 降级垫片已安装（沙箱拒绝 link 时退回 copyFile EXCL）');
  } catch (e) {
    diag(`link 降级垫片安装失败：${e && e.message}`);
  }
})();

/*
 * jitless 下的 `undici` **模块名**解析钩子（与上面的 fetch 垫片是同一件事的另一半）。
 *
 * 【为什么光有垫片还不够】上面的垫片解决的是"全局 fetch 不可用"，但上游
 * `dsh-web-fetch-http` **不用全局 fetch**：它 `await import("undici")` 自建 Agent，
 * 再把 `dispatcher` 传进 fetch（lib/index.js:154 与 :193）。而 undici 的 HTTP 解析器
 * 是 WASM 版 llhttp（lib/llhttp/llhttp-wasm.js）⇒ jitless 下 `new Agent()` 一连接就抛
 * `fetch failed / cause: WebAssembly is not defined`。
 * 这正是"web_search 正常、web_fetch 打不开任何网页和 ip"的根因：前者走上面的垫片，
 * 后者走 undici。已用对照实验确认（同一核心树、同一个本地 HTTP 服务、只切换 --jitless）。
 *
 * 【怎么修】**运行期组合**，而不是改上游源码或改核心树：注册一个解析钩子，让
 * `import("undici")` 解析到本仓的 undici-shim.mjs。核心树一个字节都不动。
 * 钩子同时翻译 `dispatcher` → 我们垫片认识的 `lookup`，从而**保住上游的 DNS 钉住/
 * SSRF 防护**（它先解析出公开地址再钉住连接，见 fetch-shim.js 里 lookup 的注释）。
 *
 * 【注册条件】只在 WASM 不可用（jitless）时注册。原生 undici 可用时不该被替换——
 * 它的连接池与协议实现比垫片完整得多。
 *
 * 【已知未验项】`register()` 的钩子跑在 Node 的**独立线程**里；端侧嵌入式运行时是否
 * 允许起线程，属真机待验收项（docs/parity-matrix.md §3.2）。故失败时只降级、不阻断
 * 启动——web_fetch 坏掉不该拖垮整个 Host。
 */
(function installUndiciNameHook() {
  if (typeof WebAssembly !== 'undefined') {
    diag('WASM 可用，保留原生 undici（未注册解析钩子）');
    return;
  }
  try {
    // eslint-disable-next-line global-require
    const { register } = require('node:module');
    register(pathToFileURL(path.join(__dirname, 'undici-loader.mjs')).href,
      pathToFileURL(__filename).href);
    diag('undici 解析钩子已注册（web_fetch 走本仓垫片，绕开 WASM）');
  } catch (e) {
    diag(`undici 解析钩子注册失败（web_fetch 将不可用）：${e && e.message}`);
  }
})();

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

/*
 * ── 启动阶段标记（BOOT_xx）────────────────────────────────────────────────
 *
 * 【为什么需要】端侧只有 hilog 可看（应用进程的 stdout 在设备上不可见，D6 E23；
 * 我们把 stdout 重定向到文件再 tail 到 hilog，见 dshhost.cc），而"Host 没起来"
 * 这类问题最贵的成本就是**猜停在哪一步**。所以把启动过程切成显式阶段：
 * 成功的最后一段 + 失败的第一段，本身就是结论。
 *
 * 阶段序列（顺序即因果）：
 *   BOOT_00_NODE_START   入口脚本开始执行（能读到它就说明 libnode + node::Start 成立）
 *   BOOT_10_ENV_READY    环境/路径已解析（打出实际取值，便于核对是否指向错目录）
 *   BOOT_20_CORE_FOUND   核心树与 dsh CLI 入口都在
 *   BOOT_30_PROFILE_READY 端侧 profile 已就位（bundle 列表 + patch 层）
 *   BOOT_40_PROFILE_BOOT 即将 runProfile（插件树从这里开始挂载）
 *   BOOT_50_DSH_INIT     runProfile 返回且拿到 ctx
 *   BOOT_60_HTTP_BIND    ctx.webServer 存在（dsh 已绑定端口）
 *   BOOT_70_HTTP_READY   我们自探一次 HTTP，确认端口**真的应答**（不是"应该应答"）
 *   BOOT_ERR             失败：带上最后一个成功阶段 + 原因
 */
const BOOT_T0 = Date.now();
let bootStage = 'BOOT_00_NODE_START';
function stage(name, extra) {
  bootStage = name;
  const suffix = extra === undefined || extra === '' ? '' : ' ' + extra;
  console.log(`[hdsh-host] ${name}${suffix} (+${Date.now() - BOOT_T0}ms)`);
}
stage('BOOT_00_NODE_START',
  `pid=${process.pid} node=${process.version} platform=${process.platform}/${process.arch} jitless=${process.execArgv.includes('--jitless')}`);

/**
 * 捕获 dsh 打印的 **authenticatedUrl**，并落盘成 `host-ready.json` 供 ArkTS 侧接入。
 *
 * 【为什么必须抓它】dsh 的"认证"不是可以关掉的开关，而是 `/api` 的 **browser-trust fence**：
 * 入口脚本探 `GET /` 得到 401 是**正确**响应，但那意味着**客户端拿不到 token 就只能一直 401**，
 * 会话 UI 根本驱动不起来。token 只出现在 dsh 打印的这一行里（真机读数，D6 E54）：
 *     dsh web: http://127.0.0.1:3120/?token=QMHMWOSL…
 * 而 `libdshhost` 没有"读走 Node 输出"的 API（只有 runtimeVersion/startHost/isHostRunning/stopHost）
 * ⇒ 通道只能是**文件**：这里写，ArkTS 侧读（EntryAbility.adoptLocalHost）。
 *
 * 【为什么在 stdout 上做拦截而不是改 dsh】对上游零 patch 是本项目的纪律；
 * 而且 dsh 的这一行本来就是为"把 URL 交给用户"设计的（`if (config.printUrl) console.log(...)`）。
 * 拦截只做一次匹配、立刻恢复原来的 write，不改变任何输出内容。
 */
function watchdogAuthUrl() {
  const original = process.stdout.write.bind(process.stdout);
  let buffer = '';
  let done = false;
  process.stdout.write = function patchedWrite(chunk, encoding, callback) {
    try {
      if (!done) {
        buffer += typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString('utf8');
        // 只留尾部：dsh 启动期输出量不小，别让 buffer 无限涨
        if (buffer.length > 65536) {
          buffer = buffer.slice(-32768);
        }
        const matched = buffer.match(/dsh web:\s*(https?:\/\/\S+)/);
        if (matched !== null) {
          done = true;
          writeHostReady(matched[1]);
        }
      }
    } catch (e) {
      // 抓不到也不能影响 Host 本身：这一段的失败只是一条诊断信息缺失
    }
    return original(chunk, encoding, callback);
  };
  return function restore() {
    process.stdout.write = original;
  };
}

/**
 * 运行时的**真实事实**（E88）：把核心页上那几项"未探测"变成实测值。
 *
 * 【为什么由入口脚本提供，而不是 ArkTS 侧自己猜】
 * 这些都是**只有宿主进程内部才知道**的事实：Node 版本、`process.platform/arch`、
 * 是否真的跑在 jitless 下、`node:zlib` 有没有 zstd、以及三个硬原生依赖到底能不能加载。
 * ArkTS 侧（`libdshhost`）只有 `runtimeVersion/startHost/isHostRunning/stopHost` 四个 API，
 * 拿不到这些；而"猜"正是本项目一直在拆的坑（`未探测` 比一个可能错的数字诚实）。
 * 入口脚本本来就要写 `host-ready.json`（token 的主通道），顺手把这几个事实一起落盘。
 *
 * 【zstd 为什么要单独探】会话持久化（`session.v3.jsonl.zstd`）依赖它；实测 Node 22.22
 * 默认就有 `zlib.zstdCompressSync`（`--experimental-zstd` 在这个版本上反而是**非法选项**），
 * 所以这一项在本项目里预期恒为 true——但**探一次**比假定它成立强：换 libnode 版本时
 * 这一行会立刻给出结论。
 */
let RUNTIME_FACTS_CACHE = null;
function runtimeFacts() {
  if (RUNTIME_FACTS_CACHE !== null) {
    return RUNTIME_FACTS_CACHE;
  }
  const facts = {
    nodeVersion: process.version,
    platform: `${process.platform}/${process.arch}`,
    jitless: process.execArgv.includes('--jitless'),
    zstd: false,
    listenAddress: `127.0.0.1:${PORT}`,
    natives: [],
  };
  try {
    const zlib = require('node:zlib');
    facts.zstd = typeof zlib.zstdCompressSync === 'function';
  } catch (e) {
    facts.zstd = false;
  }
  /*
   * 三个硬原生依赖：**当场 require 一次**并把结论（含失败原因）带上。
   * 这比在 UI 上写"未探测"有用得多：装错平台 / DT_NEEDED 不对 / 少拷了 .so，
   * 都会在这里留下人话，而不用等到某个功能被使用时才炸。
   */
  const probes = [
    ['koffi', 'koffi'],
    ['sharp', 'sharp'],
    ['node-pty', 'node-pty'],
  ];
  for (const [label, mod] of probes) {
    try {
      const loaded = require(path.join(CORE_DIR, 'node_modules', mod));
      let note = '';
      let ok = loaded !== undefined;
      if (mod === 'sharp') {
        /*
         * sharp 这一件必须**走调度器**探（E384i），不能只 require 原生件本身。
         *
         * 【为什么改】上一版直接 `require('@ohos-ports/img-sharp-openharmony-arm64/lib/*.node')`，
         * 绕过了调度器，也就绕过了真件在 require 时做的三件事：① 为 libvips 建 **soname 软链**
         * （`.node` 的 NEEDED 要 `libvips-cpp.so.42`，而包里只有全版本文件名）；
         * ② 建 **RPATH 兼容软链** `@ohos-ports/sharp-libvips-openharmony-arm64`；
         * ③ 设 `LD_LIBRARY_PATH`。于是**设备上真件本来可用，这条探针也会报失败**
         * ——而 D31 的第 0 步正是看这一行 ⇒ 会把人引向"图片能力不存在"的错误结论。
         *
         * 【探针的三条判据，都能同步拿到】
         *   ① 调度器自己在真件加载失败时把原因挂在 `hdshSharpLoadError` 上；
         *   ② 真件 require 成功时会带 `versions`（桩没有）；
         *   ③ 真件的 require 本身会跑 `sharp.format()` —— libvips 装不全时**当场抛错**，
         *      也就是"require 成功"这次真的能证明可用（这与旧注释的观察不冲突：
         *      旧注释说的是**裸** require 原生件的那条路）。
         */
        try {
          const dispatcher = require(path.join(CORE_DIR, 'node_modules', 'sharp'));
          const loadError = typeof dispatcher.hdshSharpLoadError === 'string'
            ? dispatcher.hdshSharpLoadError : '';
          const versions = dispatcher.versions;
          if (loadError.length > 0) {
            ok = false;
            note = `真件加载失败，图片附件已降级：${loadError.slice(0, 200)}`;
          } else if (versions === undefined || versions === null || typeof versions !== 'object') {
            ok = false;
            note = '调度器拿到的不是真件（没有 versions）——随包的 sharp.impl 可能是桩（E384）';
          } else {
            ok = true;
            note = `真件可用（libvips ${versions.vips ?? '?'}，随包全套）`;
          }
        } catch (e) {
          ok = false;
          const message = e && e.message ? String(e.message) : String(e);
          note = `调度器加载失败，图片附件已降级：${message.slice(0, 200)}`;
        }
      }
      facts.natives.push({ name: label, ok: ok, note: note });
    } catch (e) {
      facts.natives.push({
        name: label,
        ok: false,
        note: (e && e.message ? String(e.message) : String(e)).slice(0, 200),
      });
    }
  }
  // 缓存：这三个 require 是**一次性的重活**，而 `runtimeFacts()` 会在
  // "拦截 stdout 写"的路径上被调用——那条路径上绝不能每次都重新加载原生件。
  RUNTIME_FACTS_CACHE = facts;
  return facts;
}
/** 把 authenticatedUrl 拆成 baseUrl + token，写 `<HOME_DIR>/host-ready.json`。 */
function writeHostReady(authUrl) {
  try {
    const parsed = new URL(authUrl);
    const token = parsed.searchParams.get('token') || '';
    const facts = runtimeFacts();
    const payload = {
      url: authUrl,
      baseUrl: `${parsed.protocol}//${parsed.host}`,
      token: token,
      port: Number(parsed.port),
      profile: PROFILE,
      pid: process.pid,
      startedAt: new Date().toISOString(),
      // E98：客户端建会话时要显式带上它（默认工作区不能是 `/`）
      workspace: WORKSPACE_DIR,
      // E88：给核心页的"运行时事实"提供数据源（全部实测，没有一个默认值）
      runtime: {
        nodeVersion: facts.nodeVersion,
        platform: facts.platform,
        jitless: facts.jitless,
        zstd: facts.zstd,
        listenAddress: facts.listenAddress,
        natives: facts.natives,
      },
    };
    fs.writeFileSync(path.join(HOME_DIR, 'host-ready.json'), JSON.stringify(payload, null, 2) + '\n', 'utf8');
    stage('BOOT_65_AUTH_URL', `port=${payload.port} tokenLen=${token.length} → host-ready.json`
      + ` node=${facts.nodeVersion} zstd=${facts.zstd} jitless=${facts.jitless}`);
  } catch (e) {
    console.error('[hdsh-host] 写 host-ready.json 失败：' + (e && e.message));
  }
}

/** 读回 `host-ready.json` 里的 authenticatedUrl（没抓到就是空串，不抛）。 */
function readHostReadyUrl() {
  try {
    const p = path.join(HOME_DIR, 'host-ready.json');
    if (!fs.existsSync(p)) {
      return '';
    }
    const parsed = JSON.parse(fs.readFileSync(p, 'utf8'));
    return typeof parsed.url === 'string' ? parsed.url : '';
  } catch (e) {
    return '';
  }
}

function fail(msg) {
  // 【绝不能调 process.exit()】libelectron.so 是**同进程**跑的：
  // 这里的 exit 会连同宿主 ArkUI 应用一起杀掉。
  // 真机实测症状：启动后窗口被销毁、进程消失、hilog 里既没有 JS 异常也没有崩溃记录——
  // 看起来像"莫名其妙退出"，实际是我们自己把进程结束了。
  // 正确做法：把原因打出来、把失败状态留在全局，让进程活着（上层/诊断页据此如实展示）。
  console.error(`[hdsh-host] BOOT_ERR after=${bootStage} reason=${msg}`);
  globalThis.__hdshHostError = `${msg}（停在 ${bootStage}）`;
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

/*
 * ── 临时目录与代理例外（E84）─────────────────────────────────────────────
 *
 * 【临时目录为什么必须钉死在沙箱内】鸿蒙下 `os.homedir()` 会指向沙箱外目录（EPERM），
 * `os.tmpdir()` 是**同一类**探测。而 dsh 里真的有人用它：
 *   - `dsh-spill-local`（大工具输出落盘）
 *   - `dsh-workflow-worker-thread` / `dsh-code-runtime-worker-thread`
 * 一旦它解析到沙箱外，这些路径的失败会以"随机某个功能不好用"的形态出现，
 * 而不是一条清晰的启动错误。dsh 自己在 Node 侧看这三个变量，所以设在这里就够。
 *
 * 【NO_PROXY 为什么也要设】回环上的所有流量（HTTP RPC + WS mux）都不该经过任何代理；
 * 开发机或设备若配了系统代理，`127.0.0.1` 被代理走会表现成"端口通了但连不上"。
 * 这是**防御性**设置：没有代理时它没有任何作用。
 */
if (SANDBOX_HOME.length > 0) {
  const tmpDir = path.join(SANDBOX_HOME, 'tmp');
  ensureDir(tmpDir);
  for (const key of ['TMPDIR', 'TMP', 'TEMP']) {
    if (!process.env[key] || process.env[key].length === 0) {
      process.env[key] = tmpDir;
    }
  }
}

/**
 * 沙箱工作区（E98）：**默认工作区必须是一个可写目录**。
 *
 * 【真机证据】设备上建出来的会话，`session/list` 里 `"cwd":"/"` —— 因为宿主进程的工作目录
 * 继承自应用进程（`/`）。后果不是"路径难看"，而是**功能性故障**：
 *   · `session/follow` 在折叠工作区相关投影时抛
 *     `gateway/internal Cannot read properties of undefined (reading 'kind')`
 *     （用户看到的就是「轨迹流失败」横幅）；
 *   · `workspaceFiles/list` 在 `/` 上必然失败（`cannot list`）。
 * 开发机上一直没暴露，是因为我们本地跑时 cwd 恰好是仓库根（一个可读可写目录）——
 * 这正是"开发机跑通、设备上才炸"的典型形态。
 *
 * 【为什么不 `process.chdir()`】Node 里 `process.chdir` 走的是 POSIX `chdir`，
 * 在我们这种"Node 跑在应用进程的一个线程里"的形态下它会改**整个进程**的 cwd，
 * 影响 ArkUI/其它线程。所以不碰 cwd，改为**把这个可写目录作为默认工作区传下去**，
 * 由客户端在建会话时显式指定（`session/create` 的 `cwd`）。
 */
const WORKSPACE_DIR = SANDBOX_HOME.length > 0 ? path.join(SANDBOX_HOME, 'workspace') : '';
if (WORKSPACE_DIR.length > 0) {
  ensureDir(WORKSPACE_DIR);
}

/*
 * 「这是鸿蒙端侧」的**单一事实来源**（E127）。
 *
 * 【为什么需要它】上游有一处平台相关的安全检查在鸿蒙上**永远不可能通过**：
 * `dsh-credentials-local` 的 `assertOwnerOnly()` 要求凭据文件"不能被属主以外读到"，
 * 而 hmfs 把文件权限强制成 **660**（属组可读）⇒ 检查必然抛错，
 * 表现就是"用户明明填了密钥、模型却说没有密钥"。
 * 【为什么不用别的手段探测】端侧 `process.platform` 是 `linux`，与桌面 Linux 无法区分；
 * 这里用**我们自己确知的事实**：应用沙箱路径一定以 `/data/storage` 开头。
 * 显式、可审计，且只在端侧成立——pack-core 的补丁只认这个变量。
 */
if (SANDBOX_HOME.startsWith('/data/storage') || HOME_DIR.startsWith('/data/storage')) {
  process.env.HDSH_PLATFORM = 'ohos';
  diag('平台标识：HDSH_PLATFORM=ohos（鸿蒙应用沙箱路径）');
}
for (const key of ['NO_PROXY', 'no_proxy']) {
  if (!process.env[key] || process.env[key].length === 0) {
    process.env[key] = '127.0.0.1,localhost,::1';
  }
}

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

/**
 * 清理**孤儿写锁**（`<file>.lock`）——不清理，下一次启动就会直接失败（E84）。
 *
 * 【问题（上游的明确设计，不是 bug）】`dsh-atomic-write` 的 `withFileLock` 用
 * `flag:'wx'` 建一个同级 `<file>.lock`，内容就是持有者 pid，释放写在 `finally` 里。
 * 上游注释把边界说得很清楚：
 *
 *     The contender never removes an existing lock because file age cannot prove
 *     that its owner stopped; orphan recovery is an operator action.
 *
 * 也就是说：**锁的持有者被强杀（SIGKILL / 系统回收应用）时，锁会永久留下**，
 * 之后每个新进程都会在 `waitMs` 之后失败，并且失败信息是
 * `atomic-write: timed out waiting for the writer lock at …`。
 *
 * 【为什么端侧必须自己处理】这条在开发机上只是"手工删一下"，在端侧却是**用户级故障**：
 * 用户划掉应用、或系统因内存压力回收应用，宿主进程被直接杀死 → 下次启动起不来，
 * 而用户没有任何手段去删那个文件。所以这一步不是优化，是把一个必然发生的
 * "起不来"变成"自愈"。
 *
 * 【判据为什么是 pid 而不是文件年龄】年龄无法区分"持有者还在慢慢写"和"持有者已死"；
 * 而 pid 可以直接问操作系统。三条保守规则：
 *   1. 内容读不出 pid → **不动**（可能是别的格式/正在写）；
 *   2. pid 就是本进程 → 不动；
 *   3. pid 仍存活（含 EPERM：进程在但不属于我们）→ 不动。
 * 只有"pid 明确已不存在"才删。误判方向永远是"少删"，代价只是回到上游行为。
 */
function recoverOrphanLocks(homeDir) {
  if (homeDir.length === 0) {
    return;
  }
  const locks = [];
  let visited = 0;
  const walk = (dir, depth) => {
    if (depth > 3 || locks.length >= 200 || visited >= 20000) {
      return;
    }
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
      return;
    }
    for (const entry of entries) {
      visited++;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        // node_modules 是唯一确定巨大的子树；其余目录都值得看一眼
        if (entry.name === 'node_modules') {
          continue;
        }
        walk(full, depth + 1);
      } else if (entry.isFile() && entry.name.endsWith('.lock')) {
        locks.push(full);
      }
    }
  };
  walk(homeDir, 0);
  if (locks.length === 0) {
    return;
  }
  let removed = 0;
  let kept = 0;
  for (const lock of locks) {
    let ownerText = '';
    try {
      ownerText = fs.readFileSync(lock, 'utf8');
    } catch (e) {
      kept++;
      continue;
    }
    const owner = Number.parseInt(ownerText.trim(), 10);
    if (!Number.isInteger(owner) || owner <= 0 || owner === process.pid) {
      kept++;
      continue;
    }
    let alive = true;
    try {
      process.kill(owner, 0);
    } catch (e) {
      // ESRCH = 没有这个进程；EPERM = 进程存在但不属于我们（仍算存活）
      alive = !!(e && e.code === 'EPERM');
    }
    if (alive) {
      kept++;
      continue;
    }
    try {
      fs.rmSync(lock, { force: true });
      removed++;
      diag(`孤儿写锁已清理：${lock}（持有者 pid=${owner} 已不存在）`);
    } catch (e) {
      kept++;
    }
  }
  diag(`写锁巡检：发现 ${locks.length} 个，清理孤儿 ${removed} 个，保留 ${kept} 个`);
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
 *
 * ── 用户插件行（E91）────────────────────────────────────────────────────
 *
 * dsh 的 profile 分层里，"用户层"就是 `<profile 目录>/cordis.patch.yml`
 * （`dsh-app-boot/lib/index.js:861-862`：`patchPath = join(dir, 'cordis.patch.yml')`，
 * **不是** `$DSH_HOME/cordis.patch.yml`——早先的注释写错了）。
 *
 * 而这一层**每次启动都被我们用核心树里的种子覆盖**（上面的循环），于是"用户在端侧改的
 * 启停"必然丢。所以把两件事分开：
 *   · `cordis.patch.yml`：始终 = **核心种子 + 用户行**（本函数每次重新拼装，核心升级照常流入）；
 *   · `.hdsh-plugin-rows.yml`：**只放用户行**（`- id:` + `disabled:`），由端侧「插件」页维护，
 *     我们从不覆盖它 ⇒ 启停在重启后仍然成立。
 * "恢复默认"因此是一次**删除**：删掉用户行文件，下次启动拼出来的就是纯种子。
 */
const USER_ROWS_FILENAME = '.hdsh-plugin-rows.yml';
const USER_ROWS_BEGIN = '# >>> hdsh-user-rows（端侧「插件」页写入，勿手工编辑）';
const USER_ROWS_END = '# <<< hdsh-user-rows';

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
  composeUserRows(dest);
  log('profile 已就位：' + dest);
}

/**
 * 把用户行拼到 profile 的 patch 文件末尾（E91）。
 *
 * 【为什么追加而不是替换】`cordis.patch.yml` 里的行是**按顺序覆盖**的：种子先写、
 * 用户行后写，于是用户行天然拥有更高优先级（后写覆盖先写），而种子里的其它内容
 * （bundle 列表之外的覆盖、注释）原样保留。这也让"用户行"与"内核行"在文件里
 * 一眼可分。
 */
function composeUserRows(profileDir) {
  const patchPath = path.join(profileDir, 'cordis.patch.yml');
  const rowsPath = path.join(profileDir, USER_ROWS_FILENAME);
  if (!fs.existsSync(rowsPath)) {
    return;
  }
  let rows = '';
  try {
    rows = fs.readFileSync(rowsPath, 'utf8').trim();
  } catch (e) {
    log('读用户插件行失败（忽略）：' + e.message);
    return;
  }
  if (rows.length === 0) {
    return;
  }
  let seed = '';
  try {
    seed = fs.readFileSync(patchPath, 'utf8');
  } catch (e) {
    log('读 profile patch 失败（忽略用户行）：' + e.message);
    return;
  }
  const composed = `${seed.replace(/\s*$/, '')}\n\n${USER_ROWS_BEGIN}\n${rows}\n${USER_ROWS_END}\n`;
  fs.writeFileSync(patchPath, composed, 'utf8');
  log(`已应用用户插件行：${rowsPath}`);
}

/**
 * 自探 HTTP：确认端口**真的应答**——"dsh 说它绑了端口"与"端口真的通"是两件事。
 *
 * 用 `node:http` 而不是 fetch：这里要的是最原始的事实，不该掺任何 HTTP 客户端层的东西
 * （端侧的 fetch 还是我们垫的，见 fetch-shim.js）；`node:http` 的 llhttp 是原生的，与 WASM 无关。
 * 失败不抛异常、只返回描述串——它的用途是**读数**，不是门禁（门禁在 ArkTS 侧）。
 */
function probeHttpReady(port, attempts = 10, intervalMs = 500) {
  const http = require('node:http');
  const started = Date.now();
  return new Promise((resolve) => {
    const attempt = (left) => {
      const req = http.request({ host: '127.0.0.1', port: port, path: '/', method: 'GET', timeout: 2000 }, (res) => {
        res.resume();
        resolve(`GET / → HTTP ${res.statusCode}（${Date.now() - started}ms）`);
      });
      req.on('error', (e) => {
        if (left <= 1) {
          resolve(`未应答：${e.code === undefined ? e.message : e.code}（${Date.now() - started}ms，共探测 ${attempts} 次）`);
          return;
        }
        setTimeout(() => attempt(left - 1), intervalMs);
      });
      req.on('timeout', () => req.destroy(new Error('timeout')));
      req.end();
    };
    attempt(attempts);
  });
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
  stage('BOOT_10_ENV_READY',
    `core=${CORE_DIR} home=${HOME_DIR} sandbox=${SANDBOX_HOME} port=${PORT} profile=${PROFILE}`);
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

  stage('BOOT_20_CORE_FOUND', `entry=${path.basename(entry)}`);
  ensureDir(HOME_DIR);
  ensureProfile();
  stage('BOOT_30_PROFILE_READY', `home=${HOME_DIR} profile=${PROFILE}`);

  log('导入 ' + entry);
  const profileBoot = await import(pathToFileURL(entry).href);
  const appBootMod = await import(pathToFileURL(appBoot).href);

  /*
   * 【参数表以 dsh-web-app 的 startup.js 为准】
   *   new Command().name("dsh --profile web")
   *     .option("--host <host>").option("--no-open").option("--port <port>")
   *     .option("--trusted-host <authority...>")
   * —— 合法的就这四个。
   *
   * 【曾经写过一个不存在的 `--skip-auth`】实测真机读数（D6 E33）：
   *     error: unknown option '--skip-auth'   → runProfile 直接拒绝，Host 从未起监听（rc=1）
   * 而 dsh 的"认证"不是可以关掉的开关：它是 `/api` 的 **browser-trust fence**，
   * 且 Host 会把**带 token 的 authenticatedUrl** 打到 stdout（startup/index.js 里
   * `if (config.printUrl) console.log(...)`）——我们把 stdout 抓到 hilog 后即可读到那个 URL。
   * 所以端侧客户端该做的是"从 Host 输出里取 URL"，而不是试图关掉认证。
   */
  // `--trusted-host` 属于 dsh 的应用级选项（dsh-web-app 的 startup.js 定义了这四个：
  // --host / --no-open / --port / --trusted-host <authority...>），必须走这里交给
  // `ctx.cmdlineArgs`。**绝不能**放进 buildHostArgv——那是 Node 自身 argv，
  // 实测把 `--trusted-host` 放那儿会得到 `node: bad option` 且 Host 完全起不来（D6 E68）。
  // 端侧是"本机同源、浏览器等价"的场景，所以显式声明回环 authority 为可信来源。
  const args = [
    '--port', PORT,
    '--host', '127.0.0.1',
    '--no-open',
    '--trusted-host', `127.0.0.1:${PORT}`,
  ];
  log('runProfile profile=' + PROFILE + ' args=' + args.join(' '));
  stage('BOOT_40_PROFILE_BOOT', `entry=${path.basename(entry)}`);

  // 抓 dsh 的 authenticatedUrl（含 token）：客户端唯一的凭据来源，落在 host-ready.json。
  // 只装不卸：匹配成功后它只是把 write 原样透传，开销可以忽略；而"URL 恰好晚一拍打印"
  // 这种情况比"卸载时机"更容易出错。
  watchdogAuthUrl();
  recoverOrphanLocks(HOME_DIR);
  // 预热运行时事实：把三个原生 require 挪到写 host-ready.json **之前**，
  // 这样拦截 stdout 写的那条路径上只读缓存（那里不适合做重活）。
  runtimeFacts();
  const result = await profileBoot.runProfile({
    environment: appBootMod.loadLayeredEnv('dsh'),
    profile: PROFILE,
    patchFiles: [],
    args: args,
  });
  stage('BOOT_50_DSH_INIT', 'runProfile 已返回');

  const ctx = result && result.ctx;
  if (!ctx || !ctx.webServer) {
    fail('runProfile 返回了但没有 webServer');
  }
  stage('BOOT_60_HTTP_BIND', `port=${ctx.webServer.port}`);
  // 这行是给 ArkTS 侧的机器可读信号：ArkTS 会等到端口可连为止。
  // authUrl 是**冗余通道**：主通道是 host-ready.json（ArkTS 侧按文件读，见 adoptLocalHost）。
  console.log('HDSH_READY ' + JSON.stringify({
    port: ctx.webServer.port,
    home: HOME_DIR,
    profile: PROFILE,
    authUrl: readHostReadyUrl(),
  }));
  log('Host 已就绪，端口 ' + ctx.webServer.port);
  // 自探一次：确认端口**真的应答**（"dsh 说它绑了"与"端口真的通"是两件事）
  probeHttpReady(ctx.webServer.port).then((note) => {
    stage('BOOT_70_HTTP_READY', note);
  });

  const shutdown = result.shutdown;
  /*
   * ── 协作式停止（E90）─────────────────────────────────────────────────────
   *
   * 【为什么需要它】端侧没有任何办法让这个 Node 线程退出：
   *   · 原生层（`dshhost.cc`）只在 `node::Start` **返回**时才把 `g_running` 置假，
   *     而 `node::Start` 要返回，就得有人让 Node 自己收工；
   *   · ArkTS 侧不能给已经启动的进程发信号、也不能改它的环境变量；
   *   · `dshhost.stopHost()` 因此如实返回"做不到"（这是诚实，但"停止核心"这个
   *     按钮就成了空按钮）。
   * 而**核心切换/回滚必须能停**（`CoreStore.stageFromZip` 明确拒绝覆盖正在使用中的版本），
   * 所以停止通道不是锦上添花，是那条主流程的前置条件。
   *
   * 【为什么用"文件当信号"】已有的事实：ArkTS 能写沙箱目录（`filesDir`），
   * 入口脚本能读它；而两侧之间**没有**其它可用通道（环境变量与 argv 在启动前就固定了，
   * HTTP 侧 dsh 没有 shutdown 端点）。用文件当一个"停止请求"的落点，简单、可观察、
   * 且失败时留下的痕迹（文件还在/日志没有"收到停止请求"）本身就指明断在哪一环。
   */
  let stopRequested = false;
  const requestStop = (reason) => {
    if (stopRequested) {
      return;
    }
    stopRequested = true;
    log(`收到停止请求（${reason}），关闭 Host`);
    try {
      if (shutdown && typeof shutdown.shutdown === 'function') {
        shutdown.shutdown(0);
      }
    } catch (e) {
      log('shutdown 抛错：' + (e && e.message));
    }
    // 兜底：dsh 关掉自己的服务后事件循环通常会自然排空；若 1.5 s 后还活着，
    // 说明仍有句柄（例如我们自己的拦截器/定时器）撑着，那就显式退出——
    // 走到这里已经没有"还没落盘的诊断"需要保护了。
    const t = setTimeout(() => {
      ALLOW_EXIT = true;
      process.exit(0);
    }, 1500);
    t.unref();
  };

  const stopFile = HOME_DIR.length > 0 ? path.join(HOME_DIR, 'host-stop-request') : '';
  if (stopFile.length > 0) {
    const poller = setInterval(() => {
      try {
        if (fs.existsSync(stopFile)) {
          fs.rmSync(stopFile, { force: true });
          requestStop('host-stop-request 文件');
        }
      } catch (e) {
        // 读/删失败下轮再试：这一环不该因为一次 IO 抖动就永久失效
      }
    }, 1500);
    // unref 只表示"它不单独支撑事件循环"，不等于不触发：HTTP 服务还在时它照常轮询。
    poller.unref();
    log(`停止通道已就绪：${stopFile}`);
  }

  process.on('SIGTERM', () => requestStop('SIGTERM'));
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
