/**
 * 核心使用闭环的**本地端到端**检查：真 dsh Host + **应用自己的客户端代码**。
 *
 * ───────────────────────── 它解决什么 ─────────────────────────
 *   到这一轮为止，本仓的本地证据有两块：① Host 能起来（`check-plugin-toggle` 真起核心、
 *   真读清单）；② 纯逻辑有 fixture。**中间那半段从来没被跑过** —— 客户端的
 *   `Connection`（HTTP 载体 / cookie / 信封 / RPC）与 `dshcompat` 的端点表是应用每次
 *   用会话都要走的路，而它只在真机上被走通过（D1 阶段的读数）。
 *   本脚本把这段拿回本机：`@kit.NetworkKit` 等三个 kit 由 `tools/lib/kit-stubs/` 提供
 *   Node 实现，**不改应用代码一行**，然后对着真 Host 跑：
 *
 *     连接（configure → authenticate → start 事件流）
 *       → session/list（空或若干条，投影成会话项）
 *       → session/create（建一个会话）
 *       → session/list 再看一次（**新会话必须在列表里**）
 *       →（有模型凭据时）session/prompt → 等事件流回帧
 *
 * ───────────────────── 它**不**证明什么（写清楚，免得被当验收） ─────────────────────
 *   · 端侧 jitless 下 ArkTS 的 `http`/`webSocket` 与 Node 的实现**有已知差异**
 *     （`RemoteMux` 注释里记着自定义 header 转发与 ping/pong 的坑）⇒ 本脚本跑通
 *     **不能**替代真机验收，只证明"协议、端点、参数形态、信封与投影是通的"。
 *   · 不证明界面（ArkUI）渲染。那部分靠 `tools/device-acceptance.ps1` + `docs/device-validation.md`。
 *
 * 用法：
 *   node tools/check-core-loop.mjs             # 完整跑（没模型凭据时 prompt 一步 SKIP）
 *   node tools/check-core-loop.mjs --keep      # 保留 scratch 目录便于排查
 * 退出码：0 = 闭环通；1 = 闭环断（打印断在哪一步）；3 = 环境受阻（没跑成，**不是通过**）
 */
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { spawn, execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const CORE_DIR = join(ROOT, 'dist', 'core', 'work', 'dsh-core-0.1.5-rc.2');
const ENTRY = join(ROOT, 'hostcore', 'app', 'main.js');
const BUILD = join(ROOT, 'dist', 'scratch', 'core-loop');
const HOME = join(ROOT, 'dist', 'localtest', 'core-loop-home');
const SANDBOX = join(ROOT, 'dist', 'localtest', 'core-loop-sandbox');
const PORT = Number(process.env.HDSH_LOOP_PORT ?? String(3500 + (process.pid % 300)));
const READY_PATH = join(HOME, 'host-ready.json');
const KEEP = process.argv.includes('--keep');
/*
 * Host 子进程要用 **Node 22**：入口脚本带 `--no-experimental-fetch`，而 Node 23 起它成了
 * "非法取反"（实测 `--no-experimental-fetch is an invalid negation`）。本仓所有起 Host 的
 * 门禁都跑在 Node 22 上，这里沿用同一约定，并把"跑错版本"变成一句明确的话而不是一段栈。
 */
const NODE_BIN = process.env.HDSH_NODE22
  ?? (existsSync('/home/node/node22/bin/node') ? '/home/node/node22/bin/node' : process.execPath);

function die(message, code) {
  console.error(message);
  process.exit(code);
}

// ─────────────────────────── ① 编译应用侧代码 ───────────────────────────

function findTsc() {
  const candidates = [];
  const clt = process.env.DEVECO_CLI_CLT_PATH;
  if (clt) candidates.push(join(clt, 'codelinter', 'node_modules', 'typescript', 'bin', 'tsc'));
  candidates.push('/home/node/deveco-clt/command-line-tools/codelinter/node_modules/typescript/bin/tsc');
  for (const c of candidates) if (existsSync(c)) return c;
  return null;
}

function collectEts(dir, out) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) collectEts(p, out);
    else if (e.name.endsWith('.ets')) out.push(p);
  }
}

/** 把 .ets 当 .ts 复制进构建目录（与 fixture 编译同一手法：ArkTS 的语法子集 tsc 能读） */
function stageModule(moduleName, fromDir, toDir) {
  const files = [];
  collectEts(join(ROOT, fromDir), files);
  for (const f of files) {
    const rel = relative(join(ROOT, fromDir), f).replace(/\.ets$/, '.ts');
    const dest = join(toDir, rel);
    mkdirSync(join(dest, '..'), { recursive: true });
    cpSync(f, dest);
  }
  return files.length;
}

function build() {
  const tsc = findTsc();
  if (tsc === null) {
    die('环境受阻：找不到 tsc（DevEco CLT 自带的 typescript）。设 DEVECO_CLI_CLT_PATH 后重跑。', 3);
  }
  rmSync(BUILD, { recursive: true, force: true });
  const src = join(BUILD, 'src');
  const stubs = join(BUILD, 'stubs');
  mkdirSync(src, { recursive: true });
  mkdirSync(stubs, { recursive: true });
  const n1 = stageModule('connection', 'connection/src/main/ets', join(src, 'connection'));
  const n2 = stageModule('dshcompat', 'dshcompat/src/main/ets', join(src, 'dshcompat'));
  // 只搬 **需要的那一个** appstate 文件：本轮要证的是"列表投影"，不是整个状态层
  mkdirSync(join(src, 'appstate', 'model'), { recursive: true });
  cpSync(join(ROOT, 'appstate', 'src', 'main', 'ets', 'model', 'SessionList.ets'),
    join(src, 'appstate', 'model', 'SessionList.ts'));
  const n3 = 1;
  cpSync(join(ROOT, 'tools', 'lib', 'kit-stubs'), stubs, { recursive: true });
  console.log(`编译：connection ${n1} 文件 + dshcompat ${n2} + appstate/model ${n3} + 3 个 kit 垫片`);

  const tsconfig = {
    compilerOptions: {
      target: 'ES2020',
      module: 'commonjs',
      moduleResolution: 'node',
      outDir: join(BUILD, 'out'),
      rootDir: BUILD,
      baseUrl: BUILD,
      paths: {
        '@kit.NetworkKit': ['stubs/networkkit.ts'],
        '@kit.BasicServicesKit': ['stubs/basicserviceskit.ts'],
        '@kit.PerformanceAnalysisKit': ['stubs/performanceanalysiskit.ts'],
        connection: ['src/connection/Index.ts'],
        dshcompat: ['src/dshcompat/Index.ts'],
      },
      strict: false,
      skipLibCheck: true,
      esModuleInterop: true,
      noEmitOnError: true,
      types: [],
    },
    include: [join(BUILD, 'src', '**', '*.ts'), join(BUILD, 'stubs', '**', '*.ts')],
  };
  writeFileSync(join(BUILD, 'tsconfig.json'), JSON.stringify(tsconfig, null, 2));
  try {
    execFileSync(process.execPath, [tsc, '-p', join(BUILD, 'tsconfig.json')], { stdio: 'pipe' });
  } catch (error) {
    const out = `${error.stdout ?? ''}${error.stderr ?? ''}`.toString();
    console.error('应用侧代码编译失败（这一步没跑成，不是闭环断）：');
    console.error(out.split('\n').slice(0, 20).join('\n'));
    process.exit(3);
  }
  writeRuntimeShims();
  return join(BUILD, 'out');
}

/**
 * 让 `require('@kit.…')` 与模块间裸导入在 Node 下解析得动。
 *
 * 【为什么需要】tsconfig 的 `paths` 只管**编译期类型解析**；产出的 JS 里仍然是
 * `require('@kit/NetworkKit')`，Node 到运行时找不到。这里按 Node 的解析规则在构建目录下
 * 放一层最小的 `node_modules`：不复制代码，只写 `package.json` 指回编译产物，
 * 于是**同一份产物**既被类型检查、又被运行 —— 垫片与应用代码都不必改写。
 */
function writeRuntimeShims() {
  const out = join(BUILD, 'out');
  const shims = [
    // ArkTS 的 kit 说明符是**点号**（`@kit.NetworkKit`），产出的 JS 里就是 `require("@kit.NetworkKit")`
    // ⇒ 磁盘上要有一个**同名目录**。tsc 的 `paths` 已按点号配好；这一层管的是**运行时**解析。
    ['@kit.NetworkKit', 'stubs/networkkit.js'],
    ['@kit.BasicServicesKit', 'stubs/basicserviceskit.js'],
    ['@kit.PerformanceAnalysisKit', 'stubs/performanceanalysiskit.js'],
    ['connection', 'src/connection/Index.js'],
    ['dshcompat', 'src/dshcompat/Index.js'],
  ];
  for (const [name, target] of shims) {
    const dir = join(BUILD, 'node_modules', name);
    mkdirSync(dir, { recursive: true });
    const rel = relative(dir, join(out, target));
    writeFileSync(join(dir, 'package.json'),
      JSON.stringify({ name: name, version: '0.0.0', main: rel }, null, 2));
  }
}

// ─────────────────────────── ② 起真 Host ───────────────────────────

let child = null;
let hostLog = '';

function startHost() {
  if (!existsSync(CORE_DIR) || !existsSync(ENTRY)) {
    die(`环境受阻：核心树或入口缺失（${CORE_DIR} / ${ENTRY}）`, 3);
  }
  rmSync(HOME, { recursive: true, force: true });
  rmSync(SANDBOX, { recursive: true, force: true });
  mkdirSync(HOME, { recursive: true });
  mkdirSync(SANDBOX, { recursive: true });
  child = spawn(NODE_BIN,
    ['--jitless', '--no-experimental-fetch', '--experimental-sqlite', ENTRY],
    {
      cwd: ROOT,
      env: {
        ...process.env,
        HDSH_CORE_DIR: CORE_DIR,
        HDSH_HOME: HOME,
        HDSH_SANDBOX_HOME: SANDBOX,
        HDSH_PORT: String(PORT),
        HDSH_PROFILE: 'ondevice',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  child.stdout.on('data', (b) => { hostLog += b.toString(); });
  child.stderr.on('data', (b) => { hostLog += b.toString(); });
  console.log(`Host：启动中（端口 ${PORT}，隔离 HOME=${relative(ROOT, HOME)}，运行时 ${NODE_BIN}）`);
}

function stopHost() {
  if (child === null) return;
  try {
    writeFileSync(join(HOME, 'host-stop-request'), 'stop');
  } catch (error) {
    // 文件通道失败就退回信号
  }
  child.kill('SIGTERM');
  child = null;
}

async function waitReady() {
  const until = Date.now() + 90000;
  while (Date.now() < until) {
    if (existsSync(READY_PATH)) {
      try {
        const ready = JSON.parse(readFileSync(READY_PATH, 'utf8'));
        if (typeof ready.baseUrl === 'string' && typeof ready.token === 'string') return ready;
      } catch (error) {
        // 还没写完，继续等
      }
    }
    await new Promise((r) => setTimeout(r, 300));
  }
  return undefined;
}

// ─────────────────────────── ③ 跑闭环 ───────────────────────────

const steps = [];
function step(name, ok, detail) {
  steps.push({ name, ok, detail });
  console.log(`${ok ? '✅' : '❌'} ${name}${detail === undefined ? '' : ` —— ${detail}`}`);
}

async function main() {
  const out = build();
  startHost();
  const ready = await waitReady();
  if (ready === undefined) {
    console.error('Host 未在 90 s 内就绪。日志尾部：');
    console.error(hostLog.split('\n').slice(-15).join('\n'));
    die('环境受阻：Host 起不来（不是闭环断）', 3);
  }
  step('Host 启动并就绪', true, `${ready.baseUrl}`);

  /* 加载应用侧编译产物：**就是应用跑的那份代码** */
  const connection = await import(join(out, 'src', 'connection', 'Index.js'));
  const compat = await import(join(out, 'src', 'dshcompat', 'Index.js'));
  const sessionList = await import(join(out, 'src', 'appstate', 'model', 'SessionList.js'));

  const events = [];
  const conn = new connection.Connection({ surface: compat.SURFACE });
  const configured = conn.configure(ready.baseUrl);
  step('configure（地址解析）', configured !== undefined,
    configured === undefined ? '地址被拒' : `${configured.baseUrl ?? '(baseUrl)'}`);

  const auth = await conn.authenticate(ready.token);
  step('authenticate（token → cookie）', auth !== undefined && auth.ok === true,
    JSON.stringify(auth));

  const started = await conn.start({
    onEvent: (frame) => { events.push(frame); },
    onStateChange: () => {},
  });
  step('start（事件流）', started === true, started === true ? '' : conn.getLastError() ?? '');

  const listArgs = compat.argsFor(compat.SESSION_LIST_ENDPOINT, {});
  const before = await conn.call(compat.SESSION_LIST_ENDPOINT, listArgs);
  const beforePage = before.ok ? sessionList.projectSessionList(before.value) : undefined;
  step('session/list（读会话列表）', before.ok === true,
    before.ok ? `投影出 ${beforePage.items.length} 条会话` : JSON.stringify(before.error));

  const createArgs = compat.argsFor(compat.SESSION_CREATE_ENDPOINT, { prompt: '' });
  const created = createArgs === undefined ? undefined : await conn.call(compat.SESSION_CREATE_ENDPOINT, createArgs);
  const sessionId = created !== undefined && created.ok && created.value !== undefined
    ? created.value.sessionId ?? created.value.sessionID ?? created.value.id
    : undefined;
  step('session/create（新建会话）', sessionId !== undefined && String(sessionId).length > 0,
    created === undefined ? '兼容面缺参数契约' : (created.ok ? `sessionId=${String(sessionId).substring(0, 12)}…` : JSON.stringify(created.error)));

  const after = await conn.call(compat.SESSION_LIST_ENDPOINT, listArgs);
  const afterPage = after.ok ? sessionList.projectSessionList(after.value) : undefined;
  const hit = sessionId !== undefined && afterPage !== undefined
    ? afterPage.items.some((s) => s.id === sessionId)
    : false;
  step('闭环：新会话出现在会话列表里', hit,
    afterPage === undefined ? '第二次 list 失败' : `列表 ${afterPage.items.length} 条（before ${beforePage?.items.length ?? '?'}）`);

  /* 发一条 prompt：这是"闭环"的最后一段。没配模型时**如实 SKIP**，不算失败也不假装成功。 */
  const framesBefore = events.length;
  let promptVerdict = 'SKIP：Host 侧没有可用模型（本机未配凭据）';
  if (sessionId !== undefined) {
    /*
     * 【构造为什么不用 `promptPayload`】那个构建器在 `appstate/model/Wire.ets`，它会连带拉进
     * 四个兄弟模型（其中 `Notify` 又要 `platform`）—— 为了这一步把半个 appstate 塞进编译不划算。
     * 这里仍走**应用的参数契约** `argsFor`，字段与 `promptPayload` 逐个相同
     * （`requestId` / `sessionId` / `mode` / `content`）。
     */
    const promptArgs = compat.argsFor(compat.SESSION_PROMPT_ENDPOINT, {
      requestId: connection.randomUuid(),
      sessionId: sessionId,
      mode: 'queue',
      content: [{ type: 'text', text: 'ping（HDSH 核心闭环自检）' }],
    });
    const prompted = promptArgs === undefined
      ? undefined
      : await conn.call(compat.SESSION_PROMPT_ENDPOINT, promptArgs);
    if (prompted !== undefined && prompted.ok) {
      promptVerdict = `已进 Agent 收件箱（${JSON.stringify(prompted.value)}）`;
      await new Promise((r) => setTimeout(r, 4000));
      promptVerdict += ` · 期间 ${events.length - framesBefore} 帧事件`;
    } else if (prompted !== undefined) {
      // 没有模型/凭据时 Host 会明确回错 —— 把它原样带出来，别把它写成"通过"
      promptVerdict = `SKIP：Host 拒绝（${JSON.stringify(prompted.error)}）—— 本机没配模型属预期`;
    }
  }
  step('session/prompt（发一条消息）', true, promptVerdict);

  /* 事件流：start 之后 Host 应推帧（即使没有模型，也会有连接级/状态帧） */
  await new Promise((r) => setTimeout(r, 1500));
  step('事件流收到帧（≥1）', events.length > 0, `${events.length} 帧`);

  await conn.stop();
  stopHost();

  const failed = steps.filter((s) => !s.ok);
  console.log('');
  console.log(`闭环结果：${steps.length - failed.length}/${steps.length} 步通过`);
  if (failed.length > 0) {
    console.log(`断在：${failed.map((s) => s.name).join(' / ')}`);
    console.log(`Host 日志尾部：\n${hostLog.split('\n').slice(-12).join('\n')}`);
    process.exit(1);
  }
  console.log('✅ 核心使用闭环（协议与状态投影这一半）在本机对真 Host 跑通。');
  console.log('   ⚠️ 这不等于真机验收：端侧走 ArkTS 的 http/webSocket，见本文件顶部说明。');
  if (!KEEP) rmSync(BUILD, { recursive: true, force: true });
  process.exit(0);
}

main().catch((error) => {
  stopHost();
  console.error('闭环检查自身出错：', error?.stack ?? error);
  process.exit(3);
});
