/**
 * Regression check: one REAL model round trip through our embedded jitless host.
 *
 * ---------------------------------------------------------------------------
 * WHY THIS EXISTS
 * ---------------------------------------------------------------------------
 * Everything else in this repo proves *plumbing*: the host boots, HTTP answers,
 * the mux upgrades. None of it proves that a prompt actually reaches a model and
 * that the answer comes back THROUGH OUR CODE. On device that path runs through
 * `--jitless --no-experimental-fetch`, which means:
 *
 *   - `WebAssembly` is undefined  -> Node's undici is unusable
 *   - native `fetch` is therefore disabled -> `hostcore/app/fetch-shim.js`
 *     supplies `fetch/Request/Response/Headers` on top of `node:http(s)`
 *   - SSE streaming, `AbortSignal`, and chunked request bodies all ride that shim
 *
 * A stub can pass every structural test and still break on a real streamed
 * response. So this check drives the REAL provider configured in `--home` with a
 * deliberately tiny prompt and waits for the assistant message to be durable.
 *
 * It runs the same entry script and the same `ondevice` profile as the device,
 * with the same jitless flags, on the host machine - no device required.
 *
 * Usage:
 *   node tools/check-model-roundtrip.mjs                     # uses %USERPROFILE%\.dsh
 *   node tools/check-model-roundtrip.mjs --home <DSH_HOME>   # explicit home (credentials live here)
 *   node tools/check-model-roundtrip.mjs --prompt "..."       # custom (keep it tiny)
 *
 * Exit code 0 = an assistant message came back. Non-zero prints the host log tail,
 * which is where shim/streaming failures surface.
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { pathToFileURL } from 'node:url';
import http from 'node:http';

const ROOT = process.cwd();
const args = process.argv.slice(2);
const arg = (n, d) => {
  const i = args.indexOf(n);
  return i >= 0 ? args[i + 1] : d;
};

const CORE_DIR = join(ROOT, 'dist', 'core', 'work', 'dsh-core-0.1.5-rc.2');
const HOME = arg('--home', process.env.DSH_HOME ?? join(homedir(), '.dsh'));
const SANDBOX = join(ROOT, 'dist', 'localtest', 'model-sandbox');
const PORT = Number(arg('--port', String(3100 + (process.pid % 400))));
const PROMPT = arg('--prompt', 'Reply with exactly: pong');
const ENTRY = join(ROOT, 'hostcore', 'app', 'main.js');
const WAIT_MS = Number(arg('--wait-ms', '150000'));
/** 只读模式：给一个已有 sessionId，只读它的持久化消息，不建会话、不发 prompt。 */
const SESSION = arg('--session', '');

/*
 * 远程模式：不发本地宿主，直接对**已经在跑的一台 Host** 做同一套检查。
 *
 * 【为什么需要它】本机（Windows）跑不出完整的一转：`dsh-win32-process` 依赖 koffi，
 * 而核心树里只保留 OHOS/Linux 的 koffi 预编译（win32 那份被裁剪了），所以本地会在
 * `turn/end … Cannot find the native Koffi module` 上停住——那是**平台差异**，不是我们要查的东西。
 * 真机（arm64）上 koffi 是自建并随 HAP 加载的，所以真正的验证位置在设备上。
 *
 * 用法（先在开发机做端口转发）：
 *   hdc fport tcp:3120 tcp:3120
 *   node tools/check-model-roundtrip.mjs --remote-url http://127.0.0.1:3120 --remote-token <token>
 */
const REMOTE_URL = arg('--remote-url', '');
const REMOTE_TOKEN = arg('--remote-token', '');
const TARGET = REMOTE_URL.length > 0 ? new URL(REMOTE_URL) : undefined;
const TARGET_HOST = TARGET === undefined ? '127.0.0.1' : TARGET.hostname;
const TARGET_PORT = TARGET === undefined ? PORT : Number(TARGET.port.length > 0 ? TARGET.port : '80');

if (!existsSync(CORE_DIR)) {
  console.error(`FAIL: core tree not found: ${CORE_DIR}`);
  process.exit(2);
}
if (!existsSync(join(HOME, '.credentials.yaml')) && !existsSync(join(HOME, 'settings.yaml'))) {
  console.error(`FAIL: --home ${HOME} does not look like a dsh home (no settings.yaml/.credentials.yaml)`);
  process.exit(2);
}
mkdirSync(SANDBOX, { recursive: true });

/*
 * 清掉**上一次运行遗留的宿主**：它由本脚本自己拉起，pid 记在 host-ready.json 里，
 * 所以可以精确地只杀它——**绝不**去按进程名杀 node，那会误伤 DSH 自身的运行时。
 * 端口每轮随机（见上），双重保险：遗留进程占着旧端口，新进程拿新端口。
 */
const READY_PATH = join(HOME, 'host-ready.json');
if (existsSync(READY_PATH)) {
  try {
    const prev = JSON.parse(readFileSync(READY_PATH, 'utf8'));
    if (Number.isInteger(prev.pid) && prev.pid > 0) {
      try { process.kill(prev.pid, 'SIGKILL'); console.log(`killed stale host pid=${prev.pid}`); } catch { /* gone */ }
    }
  } catch { /* unreadable: ignore */ }
}

console.log(`home      ${HOME}`);
console.log(`sandbox   ${SANDBOX}`);
console.log(`port      ${PORT}`);

/** Minimal unary RPC over the /api channel. */
function rpc(endpoint, payload, cookie) {
  const body = Buffer.from(JSON.stringify({
    type: 'client-request',
    rpcId: `c${Date.now()}`,
    method: endpoint,
    payload: { args: payload },
  }), 'utf8');
  return new Promise((resolve) => {
    const req = http.request({
      host: TARGET_HOST,
      port: TARGET_PORT,
      path: `/api/${endpoint}`,
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'content-length': body.length,
        accept: 'application/json',
        ...(cookie === undefined ? {} : { cookie }),
      },
    }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let parsed;
        try { parsed = JSON.parse(text); } catch { parsed = undefined; }
        resolve({ status: res.statusCode, text, parsed });
      });
    });
    req.on('error', (err) => resolve({ status: 0, text: String(err && err.message), parsed: undefined }));
    req.setTimeout(20000, () => { req.destroy(); resolve({ status: 0, text: 'timeout' }); });
    req.end(body);
  });
}

function get(path) {
  return new Promise((resolve) => {
    const req = http.request({ host: TARGET_HOST, port: TARGET_PORT, path, method: 'GET' }, (res) => {
      res.resume();
      resolve({ status: res.statusCode, headers: res.headers });
    });
    req.on('error', () => resolve({ status: 0 }));
    req.setTimeout(5000, () => { req.destroy(); resolve({ status: 0 }); });
    req.end();
  });
}

let child = null;
let hostLog = '';
if (REMOTE_URL.length === 0) {
  child = spawn(process.execPath,
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
} else {
  console.log(`remote    ${REMOTE_URL} (no local host will be started)`);
}

const LOG_PATH = join(ROOT, 'dist', 'localtest', 'model-roundtrip-host.log');
let done = false;
/** 失败时最该看的不是"最后 30 行"，而是**与失败有关的那几行**。 */
function interestingLines() {
  const re = /(error|fail|worker_threads|Worker|zstd|sqlite|persist|llm|model|credential|unauthor|ECONN|stream|WebAssembly|undici|BOOT_ERR)/i;
  return hostLog.split('\n').filter((l) => re.test(l)).slice(-40);
}

function finish(code) {
  if (done) return;
  done = true;
  try { if (child !== null) child.kill('SIGKILL'); } catch { /* already gone */ }
  try { writeFileSync(LOG_PATH, hostLog, 'utf8'); } catch { /* best effort */ }
  if (code !== 0) {
    console.error(`---- host log: ${interestingLines().length} interesting line(s) (full log: ${LOG_PATH}) ----`);
    for (const l of interestingLines()) console.error(l.slice(0, 300));
    console.error('---- last 12 lines ----');
    console.error(hostLog.split('\n').slice(-12).join('\n').slice(0, 2500));
  }
  process.exit(code);
}

/** Does this text look like a model ANSWER (and not our own prompt echoed back)? */
function looksLikeAnswer(value) {
  const s = String(value).trim();
  if (s.length === 0) return false;
  if (s === PROMPT.trim()) return false;
  return /pong/i.test(s);
}

/** Pull every text we can find out of a session page payload. */
function textsOf(page) {
  const out = [];
  const visit = (v) => {
    if (v === null || v === undefined) return;
    if (typeof v === 'string') { out.push(v); return; }
    if (Array.isArray(v)) { v.forEach(visit); return; }
    if (typeof v === 'object') { Object.values(v).forEach(visit); }
  };
  visit(page);
  return out;
}

try {
  // 1. wait until OUR host (not a leftover, not a stray listener) says it is ready
  const until = Date.now() + 90000;
  let up = false;
  let token = REMOTE_TOKEN;
  if (REMOTE_URL.length > 0) {
    // 远程：Host 已经在跑，"能应答"就等于就绪（401 正是未带 cookie 时的正常应答）。
    while (Date.now() < until) {
      const res = await get('/');
      if (res.status > 0) { up = true; break; }
      await new Promise((r) => setTimeout(r, 500));
    }
    if (token.length === 0) {
      console.error('FAIL: --remote-url 需要同时给 --remote-token（Host 的启动链接里那个 token）');
      finish(2);
    }
  } else {
    while (Date.now() < until) {
      if (existsSync(READY_PATH)) {
        try {
          const r = JSON.parse(readFileSync(READY_PATH, 'utf8'));
          if (Number(r.port) === PORT) { up = true; break; }
        } catch { /* partially written */ }
      }
      await new Promise((r) => setTimeout(r, 500));
    }
    if (up) {
      token = String(JSON.parse(readFileSync(READY_PATH, 'utf8')).token ?? '');
    }
  }
  if (!up) { console.error(`FAIL: host never became reachable (${TARGET_HOST}:${TARGET_PORT})`); finish(2); }
  console.log('host is up');

  // 2. mint the browser cookie from the launch token
  const minted = await get(`/?token=${encodeURIComponent(token)}`);
  const setCookie = minted.headers?.['set-cookie'];
  const cookie = (Array.isArray(setCookie) ? setCookie[0] : setCookie)?.split(';')[0];
  if (typeof cookie !== 'string' || cookie.length === 0) {
    console.error(`FAIL: could not mint cookie (status=${minted.status})`);
    finish(2);
  }
  console.log(`cookie ${cookie.length}B`);

  /*
   * 2.5 模型目录：**这一步是零成本的，但能解释"prompt 被接受却永远没回答"**。
   * `ModelCatalog.default` 是"未配置会话"用的默认路由；`routableProviders` 是现在真能
   * 服务的 provider；`failures` 是加载失败的 provider 及其原因。三者合起来回答：
   * 端侧这份 profile 到底有没有可用的模型路由。
   */
  const catalog = await rpc('session/modelCatalog', {}, cookie);
  const catalogValue = catalog.parsed?.result?.value ?? catalog.parsed?.result?.error;
  console.log(`catalog  ${JSON.stringify(catalogValue).slice(0, 500)}`);
  if (args.includes('--catalog-only')) {
    finish(0);
  }

  // 3. target session: inspect an existing one, or create + prompt a fresh one.
  //    `--session` exists so a run that already spent a model call can be re-read
  //    for free (the durable log is the authority, not the poll loop).
  let sessionId = SESSION;
  let t0 = Date.now();
  let mux;
  const frames = [];
  if (sessionId.length === 0) {
    const created = await rpc('session/create', { request: {} }, cookie);
    sessionId = created.parsed?.result?.value?.sessionId
      ?? created.parsed?.value?.sessionId;
    if (typeof sessionId !== 'string' || sessionId.length === 0) {
      console.error(`FAIL: session/create -> ${created.status} ${created.text.slice(0, 400)}`);
      finish(1);
    }
    console.log(`session  ${sessionId}`);

    /*
     * 4. **像真实客户端那样先 follow，再 prompt**。
     *
     * 【为什么这一步不能省】只发 `session/prompt`（HTTP 一元 RPC）时，prompt 会被
     * 收下（`accepted:true`），但 **Agent 那一转并没有跑**：真机与本机都出现过
     * "prompt accepted、此后宿主日志里没有任何模型请求、会话也没有任何持久化记录"。
     * 客户端的真实顺序是：先在 mux 上 `session/follow` 打开这条会话（拿到快照 + 后续帧），
     * 再发 prompt。检查脚本按同样的顺序来，才是在验证**真实链路**而不是半个链路。
     *
     * 帧形状取自 dsh-api-gateway/lib/types/stream-protocol.d.ts：
     *   上行 {type:'open', streamId, endpoint, payload}
     *   下行 {type:'item'|'error'|'end', streamId, value?}
     */
    const wsMod = await import(pathToFileURL(join(CORE_DIR, 'node_modules', 'ws', 'index.js')).href);
    const WebSocket = wsMod.default;
    mux = new WebSocket(`ws://127.0.0.1:${PORT}/api/remote.mux`, { headers: { cookie } });
    mux.on('message', (data) => { frames.push(data.toString()); });
    await new Promise((resolve, reject) => {
      mux.once('open', resolve);
      mux.once('error', reject);
    });
    console.log('mux open');
    mux.send(JSON.stringify({
      type: 'open',
      streamId: 'follow-1',
      endpoint: 'session/follow',
      payload: { args: { request: { address: { kind: 'session', sessionId }, assistantStream: true } } },
    }));

    // 5. send the prompt
    //
    // 【参数必须包在 `request` 里】dsh 的 Typert 描述符把每个端点的参数声明成
    // `parameters: [{ name: 'request', wire: 'request' }]`（typert.host.js:994-1005），
    // 所以线上 args 是 `{ request: <SessionPromptRequest> }`。把字段平铺在 args 上会被
    // 判 `gateway/arguments-invalid: unexpected "…"` —— **而 HTTP 状态仍是 200**，
    // 因此只看状态码会误以为"已接受"。这个坑真踩过一次。
    t0 = Date.now();
    const prompted = await rpc('session/prompt', {
      request: {
        requestId: `req-${t0}`,
        sessionId,
        mode: 'queue',
        content: [{ type: 'text', text: PROMPT }],
      },
    }, cookie);
    if (prompted.status !== 200 || prompted.parsed?.result?.ok === false) {
      console.error(`FAIL: session/prompt -> ${prompted.status} ${prompted.text.slice(0, 500)}`);
      finish(1);
    }
    console.log('prompt accepted; waiting for the assistant message ...');
  } else {
    console.log(`session  ${sessionId}  (inspect only: no prompt will be sent)`);
  }

  // 5. poll the durable session page until an assistant message lands
  const deadline = Date.now() + WAIT_MS;
  let assistant = '';
  let sawModelError = '';
  while (Date.now() < deadline) {
    const page = await rpc('session/page', {
      request: {
        address: { kind: 'session', sessionId },
        // -1 是"取当前游标"的哨兵值（dsh-api-session-controller/lib/index.js:1373）。
        // 传一个很大的数不会"全都要"，而是 gateway/bad-request：through seq … is past cursor。
        throughSeq: -1,
        maxMessages: 50,
      },
    }, cookie);
    if (page.status !== 200 || page.parsed?.result?.ok === false) {
      console.error(`FAIL: session/page -> ${page.status} ${page.text.slice(0, 500)}`);
      finish(1);
    }
    if (args.includes('--dump')) {
      console.log(`dump     ${page.text.slice(0, 900)}`);
      finish(0);
    }
    const raw = page.text;
    // crude but effective: look for assistant-authored text and for provider errors
    const errMatch = raw.match(/"(?:code|message)":"([^"]*(?:unauthorized|invalid|401|403|ECONN|fetch|stream|WebAssembly|undici)[^"]*)"/i);
    if (errMatch !== null) sawModelError = errMatch[1];
    for (const t of textsOf(page.parsed)) {
      if (looksLikeAnswer(t)) assistant = String(t).trim();
    }
    // 同一份判断也用在 mux 帧上：助手流是**先到帧、后落库**的，
    // 只看 page 会晚一拍（并且在流式生成中可能一直是空的）。
    for (const frame of frames) {
      for (const m of frame.matchAll(/"text":"((?:[^"\\]|\\.)*)"/g)) {
        let decoded = m[1];
        try { decoded = JSON.parse(`"${m[1]}"`); } catch { /* keep raw */ }
        if (looksLikeAnswer(decoded)) assistant = String(decoded).trim();
      }
    }
    if (assistant.length > 0) break;
    await new Promise((r) => setTimeout(r, 3000));
  }

  const elapsed = Date.now() - t0;
  if (assistant.length > 0) {
    console.log(`assistant  ${JSON.stringify(assistant.slice(0, 200))}  (+${elapsed}ms)`);
    console.log(`mux frames ${frames.length}`);
    console.log('RESULT: PASS');
    finish(0);
  }
  console.log(`assistant  (none after ${elapsed}ms)`);
  console.log(`mux frames ${frames.length}`);
  for (const f of frames.slice(-2)) console.log(`frame      ${f.slice(0, 400)}`);
  if (sawModelError.length > 0) console.log(`hint       ${sawModelError.slice(0, 200)}`);
  console.log('RESULT: FAIL');
  finish(1);
} catch (err) {
  console.error(`FAIL: ${String(err)}`);
  finish(2);
}
