/**
 * 由**本项目自己**启动 dsh 核心，并让设备上的应用自动连上它（无需手填地址与令牌）。
 *
 * ───────────────────────── 它解决什么 ─────────────────────────
 *   dsh 是 Host/Client 分离的：客户端必须知道一个地址和一个令牌。开发时这些信息
 *   每次重启核心都会变，手工往手机里粘贴一遍是纯粹的浪费，而且容易粘错。
 *   本脚本把「起核心 → 取地址与令牌 → 启动应用并把两者带进去」合成**一条命令**。
 *
 * ───────────────────────── 为什么由本项目持有核心进程 ─────────────────────────
 *   官方桌面端就是这么做的（它把 dsh 核心作为子进程拉起）。
 *   本项目沿用同一立场：**核心跑在开发机上、由本仓库的脚本负责拉起与回收**，
 *   客户端只是连到它。这与「客户端内置 Node 运行时」是两件事——
 *   后者被 D1 §6.4 明确否决（依赖设备上的 Node/终端/包管理器）。
 *
 * ───────────────────────── 模拟器为什么要改地址 ─────────────────────────
 *   模拟器里的 `127.0.0.1` 是**模拟器自己**，开发机的 loopback 要经 QEMU slirp 网关
 *   `10.0.2.2` 才够得到。因此：
 *     - 监听仍绑 `127.0.0.1`（**绝不绑 0.0.0.0**，D1 §6.4 红线）；
 *     - 用 `--trusted-host 10.0.2.2:<port>` 把这条权威**显式**加进 Host 的信任栅栏
 *       ——这是上游提供的正规开关，不是伪造 `Host` 头；
 *     - 传给客户端的地址是 `http://10.0.2.2:<port>`。
 *   真机（USB/局域网）用 `--host-url` 显式覆盖。
 *
 * 用法：
 *   node tools/dev-host.mjs                 # 起核心 + 启动模拟器上的应用
 *   node tools/dev-host.mjs --dsh <path>    # 指定 dsh 入口（默认用 .research 里的隔离副本）
 *   node tools/dev-host.mjs --port 3115
 *   node tools/dev-host.mjs --no-launch     # 只起核心并打印地址与令牌
 *   node tools/dev-host.mjs --stop          # 停止本项目起的核心
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const args = process.argv.slice(2);
const arg = (n, d) => {
  const i = args.indexOf(n);
  return i >= 0 ? args[i + 1] : d;
};

const PORT = Number(arg('--port', '3115'));
const HOME = arg('--home', join(ROOT, '.research', 'dev-host-home'));
const STATE = join(ROOT, '.research', 'dev-host.json');
const BUNDLE = arg('--bundle', 'com.deepseek.dshharmony');
const ABILITY = arg('--ability', 'EntryAbility');
const NO_LAUNCH = args.includes('--no-launch');
const HDC = arg('--hdc', 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe');

/** 找一个可用的 dsh 入口：优先隔离副本（不碰用户已装的那份），其次本机安装。 */
function findDsh() {
  const explicit = arg('--dsh', '');
  if (explicit.length > 0) {
    return explicit;
  }
  const candidates = [
    join(ROOT, '.research', 'upstream-0.1.5rc2', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'),
    join(ROOT, '.research', 'upstream-0.1.5', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'),
    'C:\\Users\\aotian\\AppData\\Roaming\\io.github.hairyf.deepseek-harness-desktop\\dependencies\\dsh\\node_modules\\@deepseek-ai\\dsh\\lib\\bin.js'
  ];
  for (const c of candidates) {
    if (existsSync(c)) {
      return c;
    }
  }
  return '';
}

/** `--stop`：按我们记下的 pid 停掉自己起的核心（**绝不做按名字杀进程**）。 */
if (args.includes('--stop')) {
  if (!existsSync(STATE)) {
    console.log('没有本项目起的核心记录（.research/dev-host.json 不存在）');
    process.exit(0);
  }
  const state = JSON.parse(readFileSync(STATE, 'utf8'));
  try {
    process.kill(state.pid);
    console.log(`已请求停止 pid=${state.pid}（端口 ${state.port}）`);
  } catch (e) {
    console.log(`pid=${state.pid} 已不存在（${e.code}）`);
  }
  rmSync(STATE, { force: true });
  process.exit(0);
}

/** `--relaunch`：核心已在跑，只把设备上的应用重新拉起（复用已记录的地址与令牌）。 */
if (args.includes('--relaunch')) {
  const TOKEN_FILE = join(ROOT, '.research', 'dev-host-token.txt');
  if (!existsSync(STATE) || !existsSync(TOKEN_FILE)) {
    console.error('缺少 .research/dev-host.json 或 dev-host-token.txt；请先正常运行一次 dev-host.mjs');
    process.exit(2);
  }
  const state = JSON.parse(readFileSync(STATE, 'utf8'));
  const tok = readFileSync(TOKEN_FILE, 'utf8').trim();
  console.log(`复用核心 pid=${state.pid} 地址=${state.url}`);
  const relaunch = spawn(HDC, [
    'shell', 'aa', 'start', '-a', ABILITY, '-b', BUNDLE,
    '--ps', 'dshHost', state.url, '--ps', 'dshToken', tok
  ], { stdio: 'inherit' });
  relaunch.on('exit', (code) => process.exit(code ?? 1));
} else {
  main();
}

function main() {
const dsh = findDsh();
if (dsh.length === 0) {
  console.error('找不到 dsh 入口。用 --dsh <path/to/dsh/lib/bin.js> 指定，或先在 .research 下安装：');
  console.error('  npm install --prefix .research/upstream-0.1.5rc2 @deepseek-ai/dsh@0.1.5-rc.2');
  process.exit(2);
}
mkdirSync(HOME, { recursive: true });

/**
 * 设备侧要用的地址。
 *
 * 模拟器经 slirp 网关访问开发机 loopback；真机需要显式给 `--host-url`
 * （例如 USB 反连或 hostkit 隧道地址）。
 */
const HOST_URL = arg('--host-url', `http://10.0.2.2:${PORT}`);
const trustedHost = new URL(HOST_URL).host;

console.log(`dsh 入口    : ${dsh}`);
console.log(`DSH_HOME    : ${HOME}`);
console.log(`监听        : 127.0.0.1:${PORT}（不绑 0.0.0.0）`);
console.log(`信任的额外权威: ${trustedHost}`);
console.log(`客户端地址  : ${HOST_URL}\n`);

const child = spawn(process.execPath, [
  dsh, 'web', '--no-open', '--port', String(PORT), '--host', '127.0.0.1',
  '--trusted-host', trustedHost
], {
  env: { ...process.env, DSH_HOME: HOME },
  stdio: ['ignore', 'pipe', 'inherit']
});

/**
 * 从核心的 stdout 里抓那一行 `dsh web: http://…/?token=…`。
 *
 * 【为什么要用正则抓而不是自己拼】令牌是**核心生成的**，客户端无从推断；
 * 抓它的打印行是唯一不猜的做法。抓不到就明确失败，而不是拿空令牌去连
 * （那会得到 401，文案会把用户引向「令牌无效」，与真实原因不符）。
 */
const tokenRe = /(https?:\/\/[^\s]*[?&]token=([A-Za-z0-9_\-]+))/;
let token = '';

child.stdout.on('data', async (chunk) => {
  const text = chunk.toString('utf8');
  process.stdout.write(text);
  if (token.length > 0) {
    return;
  }
  const m = tokenRe.exec(text);
  if (m === null) {
    return;
  }
  token = m[2];
  // 令牌同时留一份在文件里（仅本机、仅开发用）：没有它就无法"只重启应用"，
  // 每次都要连核心一起重启。这不是凭据管理，是开发期的便利记录——
  // 真正的令牌存储由应用侧的加密存储负责（HostStore + SecretStore）。
  writeFileSync(join(ROOT, '.research', 'dev-host-token.txt'), token, { mode: 0o600 });
  writeFileSync(STATE, JSON.stringify({
    pid: child.pid, port: PORT, url: HOST_URL, startedAt: Date.now()
  }, null, 2), 'utf8');
  console.log(`\n令牌已取得（长度 ${token.length}）。核心 pid=${child.pid}，记录在 .research/dev-host.json`);
  console.log(`停止：node tools/dev-host.mjs --stop\n`);

  if (NO_LAUNCH) {
    console.log(`客户端命令：hdc shell aa start -a ${ABILITY} -b ${BUNDLE} --ps dshHost ${HOST_URL} --ps dshToken ${token}`);
    return;
  }
  launchApp(token);
});

/** 用启动参数把地址与令牌交给应用（**无需在界面上手填**）。 */
function launchApp(tok) {
  const start = spawn(HDC, [
    'shell', 'aa', 'start', '-a', ABILITY, '-b', BUNDLE,
    '--ps', 'dshHost', HOST_URL, '--ps', 'dshToken', tok
  ], { stdio: 'inherit' });
  start.on('exit', (code) => {
    console.log(code === 0
      ? '\n已启动应用并把 Host 通过启动参数带入（应用会自动连接，无需手填）。'
      : `\n启动应用失败（hdc 退出码 ${code}）。可手动执行 --no-launch 打印的那条命令。`);
  });
}

child.on('exit', (code) => {
  console.log(`\n核心进程退出（code=${code}）`);
});

// 让本脚本常驻（核心生命周期与它绑定：Ctrl+C 即回收）
process.on('SIGINT', () => {
  console.log('\n收到中断，停止核心…');
  child.kill();
  process.exit(0);
});
}
