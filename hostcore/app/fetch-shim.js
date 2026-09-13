/*
 * jitless 下的 fetch 垫片（D6 E52）
 *
 * 【为什么必须自己垫】`--jitless` 隐含 `--no-expose-wasm` ⇒ `WebAssembly === undefined`。
 * Node 自带的 undici 用 **WASM 版 llhttp** 解析响应，所以它一初始化就抛
 * `WebAssembly is not defined`（触发点是 `node:http` 的惰性 getter → `lazyUndici`，见 E38）。
 * 我们的处置是：入口脚本里封掉那些惰性 getter（E39）+ 用 `--no-experimental-fetch`
 * 让 Node **不安装** globalThis.fetch。这两步能让 Host 起来，但会让 `fetch` 变成 undefined——
 * 而 dsh 调模型正是用 fetch：
 *     @deepseek-ai/dsh-llm-deepseek/lib/index.js:1770
 *       response = await fetch(`${connection.baseURL}/chat/completions`, {method:'POST', headers, body, signal})
 * ⇒ 不垫它，Host 起来了也**调不动模型**，那不算"跑通"。
 *
 * 【为什么垫在 node:http/node:https 上】这两个模块用的是**原生** llhttp（C++），与 WASM 无关；
 * `ReadableStream` 取自 `node:stream/web`（纯 JS）；`AbortSignal`/`URL`/`TextEncoder` 都是原生。
 * 所以整条链路可以在 jitless 下工作。
 *
 * 【覆盖范围】按 dsh 实际用到的面实现：POST JSON + 自定义 headers + `signal` 中止、
 * `response.ok/status/statusText/headers.get/text()/json()/body`（`body` 是 ReadableStream，
 * SSE 流式响应要用）。另外补了 `Headers`/`FormData`/`Blob`/`File` 的最小实现——
 * 它们在 Node 里同样来自 undici，jitless 下都不存在，而 dsh 上传附件要用 FormData。
 *
 * 【已知取舍】① 只跟随最多 5 次重定向，且只对 303 改写成 GET；
 * ② 请求体支持 string/Buffer/TypedArray/FormData/Blob/ReadableStream，够用即可；
 * ③ 不实现 `Response.redirect()` 等构造侧 API（我们用不到）。
 */
'use strict';

const http = require('node:http');
const https = require('node:https');
const { ReadableStream } = require('node:stream/web');

// ── Headers ────────────────────────────────────────────────────────────────
class HdshHeaders {
  constructor(init) {
    this._map = new Map();
    if (init instanceof HdshHeaders) {
      init.forEach((value, name) => this.append(name, value));
    } else if (Array.isArray(init)) {
      for (const pair of init) {
        if (Array.isArray(pair) && pair.length >= 2) this.append(pair[0], pair[1]);
      }
    } else if (init !== undefined && init !== null && typeof init === 'object') {
      for (const name of Object.keys(init)) {
        if (init[name] !== undefined) this.append(name, init[name]);
      }
    }
  }
  append(name, value) {
    const key = String(name).toLowerCase();
    const cur = this._map.get(key);
    if (cur === undefined) this._map.set(key, { name: String(name), values: [String(value)] });
    else cur.values.push(String(value));
  }
  set(name, value) {
    this._map.set(String(name).toLowerCase(), { name: String(name), values: [String(value)] });
  }
  get(name) {
    const cur = this._map.get(String(name).toLowerCase());
    return cur === undefined ? null : cur.values.join(', ');
  }
  has(name) { return this._map.has(String(name).toLowerCase()); }
  delete(name) { this._map.delete(String(name).toLowerCase()); }
  forEach(cb, thisArg) {
    for (const cur of this._map.values()) cb.call(thisArg, cur.values.join(', '), cur.name, this);
  }
  entries() { return Array.from(this._map.values()).map((c) => [c.name, c.values.join(', ')]); }
  keys() { return this.entries().map(([k]) => k); }
  values() { return this.entries().map(([, v]) => v); }
  [Symbol.iterator]() { return this.entries()[Symbol.iterator](); }
}

// ── Blob / File / FormData（Node 里这些也来自 undici，jitless 下不存在）──────
class HdshBlob {
  constructor(parts = [], options = {}) {
    this._parts = parts;
    this.type = options.type === undefined ? '' : String(options.type);
    let size = 0;
    for (const part of parts) {
      if (typeof part === 'string') size += Buffer.byteLength(part);
      else if (Buffer.isBuffer(part)) size += part.length;
      else if (part instanceof ArrayBuffer) size += part.byteLength;
      else if (ArrayBuffer.isView(part)) size += part.byteLength;
      else if (part instanceof HdshBlob) size += part.size;
      else size += Buffer.byteLength(String(part));
    }
    this.size = size;
  }
  _buffer() {
    const out = [];
    for (const part of this._parts) {
      if (typeof part === 'string') out.push(Buffer.from(part, 'utf8'));
      else if (Buffer.isBuffer(part)) out.push(part);
      else if (part instanceof ArrayBuffer) out.push(Buffer.from(part));
      else if (ArrayBuffer.isView(part)) out.push(Buffer.from(part.buffer, part.byteOffset, part.byteLength));
      else if (part instanceof HdshBlob) out.push(part._buffer());
      else out.push(Buffer.from(String(part), 'utf8'));
    }
    return Buffer.concat(out);
  }
  async arrayBuffer() { const b = this._buffer(); return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength); }
  async text() { return this._buffer().toString('utf8'); }
  async bytes() { return new Uint8Array(this._buffer()); }
  slice(start, end, type) { return new HdshBlob([this._buffer().subarray(start, end)], { type: type === undefined ? this.type : type }); }
}

class HdshFile extends HdshBlob {
  constructor(parts, name, options = {}) {
    super(parts, options);
    this.name = String(name);
    this.lastModified = options.lastModified === undefined ? Date.now() : options.lastModified;
  }
}

class HdshFormData {
  constructor() { this._entries = []; }
  append(name, value, filename) { this._entries.push({ name: String(name), value, filename }); }
  set(name, value, filename) {
    this.delete(name);
    this._entries.push({ name: String(name), value, filename });
  }
  delete(name) { this._entries = this._entries.filter((e) => e.name !== String(name)); }
  get(name) { const e = this._entries.find((x) => x.name === String(name)); return e === undefined ? null : e.value; }
  getAll(name) { return this._entries.filter((e) => e.name === String(name)).map((e) => e.value); }
  has(name) { return this._entries.some((e) => e.name === String(name)); }
  forEach(cb, thisArg) { for (const e of this._entries) cb.call(thisArg, e.value, e.name, this); }
  entries() { return this._entries.map((e) => [e.name, e.value]); }
  keys() { return this._entries.map((e) => e.name); }
  values() { return this._entries.map((e) => e.value); }
  [Symbol.iterator]() { return this.entries()[Symbol.iterator](); }
  /** 编成 multipart/form-data 的字节流 + boundary（够 dsh 上传附件用）。异步：原生 Blob 取字节是异步的。 */
  async _encode() {
    const boundary = `----hdsh${Date.now().toString(16)}${Math.floor(Math.random() * 1e9).toString(16)}`;
    const chunks = [];
    const crlf = Buffer.from('\r\n');
    for (const entry of this._entries) {
      const value = entry.value;
      const filename = entry.filename === undefined
        ? (value instanceof HdshFile ? value.name : (typeof value === 'object' && value !== null && typeof value.name === 'string' ? value.name : undefined))
        : entry.filename;
      const isFile = entry.filename !== undefined || isBlobLike(value);
      let head = `--${boundary}\r\nContent-Disposition: form-data; name="${entry.name}"`;
      if (isFile) head += `; filename="${filename === undefined ? 'blob' : filename}"`;
      head += '\r\n';
      if (isFile) {
        const type = typeof value === 'object' && value !== null && typeof value.type === 'string' && value.type !== '' ? value.type : 'application/octet-stream';
        head += `Content-Type: ${type}\r\n`;
      }
      chunks.push(Buffer.from(head, 'utf8'), crlf);
      chunks.push(isFile ? await blobBytes(value) : Buffer.from(String(value), 'utf8'));
      chunks.push(crlf);
    }
    chunks.push(Buffer.from(`--${boundary}--\r\n`, 'utf8'));
    return { data: Buffer.concat(chunks), type: `multipart/form-data; boundary=${boundary}`, stream: null };
  }
}

/** 像 Blob 就行（**不能只用 instanceof**：Node 原生就有 `Blob`/`File`，来自 `node:buffer`，
 *  它们与 undici 无关，因此 `--no-experimental-fetch` 下依然存在，dsh 可能直接把原生 Blob 传进来）。*/
function isBlobLike(value) {
  return value !== null && typeof value === 'object' && typeof value.arrayBuffer === 'function' && typeof value.size === 'number';
}

/** 取 Blob 的字节：自家实现是同步的；原生 Blob 只能异步取。 */
async function blobBytes(value) {
  if (value instanceof HdshBlob) return value._buffer();
  return Buffer.from(await value.arrayBuffer());
}

// ── body 编码（异步：原生 Blob 的字节只能异步取）─────────────────────────────
async function encodeRequestBody(body) {
  if (body === undefined || body === null) return { data: null, type: null, stream: null };
  if (typeof body === 'string') return { data: Buffer.from(body, 'utf8'), type: 'text/plain;charset=UTF-8', stream: null };
  if (Buffer.isBuffer(body)) return { data: body, type: null, stream: null };
  if (body instanceof ArrayBuffer) return { data: Buffer.from(body), type: null, stream: null };
  if (ArrayBuffer.isView(body)) return { data: Buffer.from(body.buffer, body.byteOffset, body.byteLength), type: null, stream: null };
  if (body instanceof HdshFormData) return await body._encode();
  if (isBlobLike(body)) return { data: await blobBytes(body), type: body.type === '' ? null : body.type, stream: null };
  if (typeof body.getReader === 'function') return { data: null, type: null, stream: body };
  return { data: Buffer.from(String(body), 'utf8'), type: null, stream: null };
}

// ── Response ──────────────────────────────────────────────────────────────
class HdshResponse {
  constructor(body, init = {}) {
    /*
     * 【必须是标准 Fetch 签名 `new Response(body, init)`（E76）】dsh 的 web 栈到处这样构造响应：
     *   dsh-host-webserver 侧与本包内：`new Response("not found", { status: 404 })`、
     *   `new Response("content type must be application/json", { status: 415 })`、
     *   `new Response("body is not JSON", { status: 400 })`、`fullResponse(...)` 等。
     * 早先这里写成非标准的 `(stream, init)` 且 `headers = init.headers`（常为 undefined），
     * 于是桥层执行 `Object.fromEntries(response.headers.entries())`
     * （`dsh-client-connection/lib/index.js:83`）时**抛 TypeError** ⇒ 被 webserver 的
     * catch-all 兜成空体 400。表现就是：**任何** /api 请求、任何封装/头/cookie 都是 400 空体。
     */
    this.status = init.status === undefined ? 200 : init.status;
    this.statusText = init.statusText === undefined ? '' : init.statusText;
    this.headers = init.headers instanceof HdshHeaders ? init.headers : new HdshHeaders(init.headers);
    this.url = init.url === undefined ? '' : init.url;
    this.ok = this.status >= 200 && this.status <= 299;
    this.bodyUsed = false;
    this.redirected = false;
    this.type = 'default';
    if (body === undefined || body === null) {
      // 空体：`_buffer` 置为长度 0 的 Buffer（与"未缓冲、需读流"区分开）
      this._buffer = Buffer.alloc(0);
      this.body = null;
    } else if (typeof body === 'string' || Buffer.isBuffer(body) || body instanceof HdshBlob) {
      this._buffer = typeof body === 'string' ? Buffer.from(body, 'utf8')
        : (Buffer.isBuffer(body) ? body : body._buffer());
      const bytes = this._buffer;
      this.body = new ReadableStream({
        start(controller) {
          if (bytes.length > 0) controller.enqueue(new Uint8Array(bytes));
          controller.close();
        },
      });
    } else {
      // 已是 ReadableStream（我们自己的 fetch 走这条）
      this._buffer = null;
      this.body = body;
    }
  }
  /** 读全文并缓存：`text()/json()/arrayBuffer()` 共享同一份，符合 bodyUsed 语义。 */
  async _readAll() {
    if (this._buffer !== null) return this._buffer;
    if (this.body === null) return Buffer.alloc(0);
    const reader = this.body.getReader();
    const chunks = [];
    for (;;) {
      const step = await reader.read();
      if (step.done === true) break;
      chunks.push(Buffer.from(step.value));
    }
    this.bodyUsed = true;
    this._buffer = Buffer.concat(chunks);
    return this._buffer;
  }
  async text() { return (await this._readAll()).toString('utf8'); }
  async arrayBuffer() {
    const b = await this._readAll();
    return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
  }
  async json() { return JSON.parse(await this.text()); }
  async blob() { return new HdshBlob([await this._readAll()], { type: this.headers.get('content-type') || '' }); }
  clone() { throw new Error('HdshResponse.clone() 未实现（jitless fetch 垫片）'); }
  /*
   * 【静态构造器（E78）】dsh 的端点处理器用标准 Fetch 的静态方法构造响应：
   *   `Response.json(data, init)` / 可能还有 `Response.redirect` / `Response.error`。
   * 缺它们时的症状是 **HTTP 500 + `TypeError: Response.json is not a function`**
   * （dsh-client-connection 的处理器把异常包成 500 "handler failure: …"）。
   * 本机实测就是这一条——补上后 /api 才真正可用。
   */
  static json(data, init = {}) {
    const headers = init.headers instanceof HdshHeaders ? init.headers : new HdshHeaders(init.headers);
    if (!headers.has('content-type')) headers.set('content-type', 'application/json');
    const merged = Object.assign({}, init, { headers });
    return new HdshResponse(JSON.stringify(data), merged);
  }
  static redirect(url, status = 302) {
    return new HdshResponse(null, { status: status, headers: new HdshHeaders({ location: String(url) }) });
  }
  static error() {
    return new HdshResponse(null, { status: 0 });
  }
}

// ── fetch ─────────────────────────────────────────────────────────────────
const REDIRECT_STATUS = new Set([301, 302, 303, 307, 308]);

function onceFetch(url, init, headers, encoded, signal, redirectsLeft, timeoutMs) {
  return new Promise((resolve, reject) => {
    let parsed;
    try {
      parsed = new URL(url);
    } catch (error) {
      reject(new TypeError(`Invalid URL: ${url}`));
      return;
    }
    const mod = parsed.protocol === 'https:' ? https : http;
    const options = {
      method: init.method === undefined ? 'GET' : String(init.method).toUpperCase(),
      headers: Object.fromEntries(headers.entries()),
      signal,
      timeout: timeoutMs,
    };
    const req = mod.request(parsed, options, (res) => {
      const status = res.statusCode === undefined ? 0 : res.statusCode;
      const resHeaders = new HdshHeaders();
      for (let i = 0; i + 1 < res.rawHeaders.length; i += 2) resHeaders.append(res.rawHeaders[i], res.rawHeaders[i + 1]);

      if (REDIRECT_STATUS.has(status) && redirectsLeft > 0) {
        const location = resHeaders.get('location');
        res.resume();
        if (location !== null) {
          const nextUrl = new URL(location, parsed).toString();
          const nextInit = { ...init };
          if (status === 303 && options.method !== 'HEAD') nextInit.method = 'GET';
          resolve(onceFetch(nextUrl, nextInit, headers, undefined, signal, redirectsLeft - 1, timeoutMs));
          return;
        }
      }

      const stream = new ReadableStream({
        start(controller) {
          res.on('data', (chunk) => controller.enqueue(new Uint8Array(chunk)));
          res.on('end', () => {
            try {
              controller.close();
            } catch (error) {
              // 已关闭（例如被 cancel）时忽略
            }
          });
          res.on('error', (error) => controller.error(error));
        },
        cancel() { res.destroy(); },
      });
      resolve(new HdshResponse(stream, {
        status,
        statusText: res.statusMessage === undefined ? '' : res.statusMessage,
        headers: resHeaders,
        url: parsed.toString(),
      }));
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error(`fetch 超时（${timeoutMs} ms）：${url}`)));
    if (encoded !== undefined && encoded !== null) {
      if (encoded.stream !== null && encoded.stream !== undefined) {
        const reader = encoded.stream.getReader();
        const pump = () => reader.read().then((step) => {
          if (step.done === true) {
            req.end();
            return;
          }
          req.write(Buffer.from(step.value), pump);
        }, (error) => req.destroy(error));
        pump();
      } else if (encoded.data !== null) {
        req.write(encoded.data);
      }
    }
    req.end();
  });
}

/**
 * `fetch` 的最小可用实现（覆盖 dsh 用到的面）。
 * @param input URL 字符串（或带 `url` 的对象）
 * @param init `{ method, headers, body, signal }`
 * @param options 仅支持 `{ timeoutMs }`（我们内部用；标准 fetch 无此项）
 */
async function hdshFetch(input, init = {}, options = {}) {
  const url = typeof input === 'string' ? input : (input !== null && typeof input === 'object' && typeof input.url === 'string' ? input.url : String(input));
  const headers = new HdshHeaders(init.headers);
  const encoded = await encodeRequestBody(init.body);
  if (encoded !== undefined && encoded !== null && encoded.type !== null && !headers.has('content-type')) {
    headers.set('content-type', encoded.type);
  }
  const timeoutMs = typeof options.timeoutMs === 'number' ? options.timeoutMs : 120000;
  return await onceFetch(url, init, headers, encoded, init.signal, 5, timeoutMs);
}

/**
 * 最小的 `Request` 实现。
 *
 * 【为什么必须有它（E75，本次 400 的真因）】dsh 的 `/api` 挂载点会构造 Fetch 的 `Request`：
 *   dsh-client-connection/lib/index.js:68
 *     request = new Request(url, { method, headers, body: Buffer.concat(chunks), signal });
 * 而 Host 用 `--no-experimental-fetch` 启动（为避开 undici 的 WASM 初始化），此时
 * `globalThis.Request` **不存在** ⇒ `new Request(...)` 抛 `ReferenceError`
 * ⇒ 被 `dsh-host-webserver` 的 catch-all 兜成 **空体 400**（`res.writeHead(400); res.end()`）。
 * 这正是实测现象：`GET /` 正常 200，而**所有** `POST /api/<endpoint>` 都是 400 空体，
 * dsh 侧无可用日志，换封装/cookie/头一律无效。
 * 只实现 dsh 用到的部分：`url/method/headers/signal` 与 `text()/json()/arrayBuffer()`。
 */
class HdshRequest {
  constructor(input, init = {}) {
    this.url = typeof input === 'string' ? input : (input !== null && typeof input === 'object' && typeof input.url === 'string' ? input.url : String(input));
    this.method = init.method === undefined ? 'GET' : String(init.method).toUpperCase();
    this.headers = init.headers instanceof HdshHeaders ? init.headers : new HdshHeaders(init.headers);
    this.signal = init.signal;
    this.bodyUsed = false;
    const raw = init.body;
    if (raw === undefined || raw === null) this._body = null;
    else if (Buffer.isBuffer(raw)) this._body = raw;
    else if (typeof raw === 'string') this._body = Buffer.from(raw, 'utf8');
    else if (raw instanceof ArrayBuffer) this._body = Buffer.from(raw);
    else if (ArrayBuffer.isView(raw)) this._body = Buffer.from(raw.buffer, raw.byteOffset, raw.byteLength);
    else this._body = null; // 流式 body 不支持：dsh 的 /api 走 buffered 模式，用不到
    /*
     * 【诊断（E77）】dsh 的 `bridge` 读请求体后应传 `body: Buffer`；若这里拿到的是空，
     * 就说明体在到达处理器前就没了（或桥没传）。打一行到 Host 输出（本机可直接看到），
     * 用于区分"体丢失"与"体传了但我的解析有误"。
     */
    if (this.method === 'POST') {
      const kind = raw === undefined ? 'undefined' : (raw === null ? 'null'
        : (Buffer.isBuffer(raw) ? 'Buffer' : (typeof raw === 'string' ? 'string'
        : (raw instanceof ArrayBuffer ? 'ArrayBuffer' : (ArrayBuffer.isView(raw) ? 'ArrayBufferView'
        : (raw !== null && typeof raw === 'object' ? `object:${raw.constructor === undefined ? '?' : raw.constructor.name}` : typeof raw))))));
      console.error(`HDSH-REQDIAG body kind=${kind} bodyNull=${this._body === null}`
        + ` content-length=${this.headers.get('content-length') ?? 'none'} url=${this.url}`
        + ` preview=${this._body === null ? '(null)' : JSON.stringify(this._body.toString('utf8').substring(0, 120))}`);
    }
  }
  async text() {
    this.bodyUsed = true;
    return this._body === null ? '' : this._body.toString('utf8');
  }
  async json() { return JSON.parse(await this.text()); }
  async arrayBuffer() {
    const b = this._body === null ? Buffer.alloc(0) : this._body;
    return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
  }
}

/**
 * 安装垫片。
 *
 * 【为什么改成"缺哪个补哪个"】原先以"原生 fetch 是否可用"为唯一开关，于是
 * `--no-experimental-fetch` 之外若缺 `Request`/`Response` 也不会补——而 dsh 的 `/api`
 * 挂载点**必须**有 `Request`（E75）。现在这几个全局只要缺失就补；只有 `fetch` 本身
 * 在原生可用时才不覆盖。
 * @returns 是否安装了 `fetch` 本身（供入口脚本打日志）
 */
function installFetchShim() {
  if (globalThis.Headers === undefined) globalThis.Headers = HdshHeaders;
  if (globalThis.Request === undefined) globalThis.Request = HdshRequest;
  if (globalThis.Response === undefined) globalThis.Response = HdshResponse;
  if (globalThis.FormData === undefined) globalThis.FormData = HdshFormData;
  if (globalThis.Blob === undefined) globalThis.Blob = HdshBlob;
  if (globalThis.File === undefined) globalThis.File = HdshFile;
  if (typeof globalThis.fetch === 'function') return false;
  globalThis.fetch = hdshFetch;
  return true;
}

module.exports = { installFetchShim, hdshFetch, HdshHeaders, HdshFormData, HdshBlob, HdshFile, HdshResponse };
