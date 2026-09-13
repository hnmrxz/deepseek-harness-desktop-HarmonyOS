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
  /** 编成 multipart/form-data 的字节流 + boundary（够 dsh 上传附件用）。 */
  _encode() {
    const boundary = `----hdsh${Date.now().toString(16)}${Math.floor(Math.random() * 1e9).toString(16)}`;
    const chunks = [];
    const crlf = Buffer.from('\r\n');
    for (const entry of this._entries) {
      const isFile = entry.value instanceof HdshBlob || entry.filename !== undefined;
      const value = entry.value instanceof HdshBlob
        ? entry.value
        : new HdshBlob([typeof entry.value === 'string' ? entry.value : String(entry.value)]);
      const filename = entry.filename === undefined
        ? (entry.value instanceof HdshFile ? entry.value.name : undefined)
        : entry.filename;
      let head = `--${boundary}\r\nContent-Disposition: form-data; name="${entry.name}"`;
      if (isFile) head += `; filename="${filename === undefined ? 'blob' : filename}"`;
      head += '\r\n';
      if (isFile) head += `Content-Type: ${value.type === '' ? 'application/octet-stream' : value.type}\r\n`;
      chunks.push(Buffer.from(head, 'utf8'), crlf, value._buffer(), crlf);
    }
    chunks.push(Buffer.from(`--${boundary}--\r\n`, 'utf8'));
    return { data: Buffer.concat(chunks), type: `multipart/form-data; boundary=${boundary}` };
  }
}

// ── body 编码 ─────────────────────────────────────────────────────────────
function encodeRequestBody(body) {
  if (body === undefined || body === null) return { data: null, type: null, stream: null };
  if (typeof body === 'string') return { data: Buffer.from(body, 'utf8'), type: 'text/plain;charset=UTF-8', stream: null };
  if (Buffer.isBuffer(body)) return { data: body, type: null, stream: null };
  if (body instanceof ArrayBuffer) return { data: Buffer.from(body), type: null, stream: null };
  if (ArrayBuffer.isView(body)) return { data: Buffer.from(body.buffer, body.byteOffset, body.byteLength), type: null, stream: null };
  if (body instanceof HdshFormData) return body._encode();
  if (body instanceof HdshBlob) return { data: body._buffer(), type: body.type === '' ? null : body.type, stream: null };
  if (typeof body.getReader === 'function') return { data: null, type: null, stream: body };
  return { data: Buffer.from(String(body), 'utf8'), type: null, stream: null };
}

// ── Response ──────────────────────────────────────────────────────────────
class HdshResponse {
  constructor(stream, init) {
    this.body = stream;
    this.status = init.status;
    this.statusText = init.statusText === undefined ? '' : init.statusText;
    this.headers = init.headers;
    this.url = init.url === undefined ? '' : init.url;
    this.ok = this.status >= 200 && this.status <= 299;
    this.bodyUsed = false;
    this.redirected = false;
    this.type = 'basic';
    this._buffer = null;
  }
  /** 读全文并缓存：`text()/json()/arrayBuffer()` 共享同一份，符合 bodyUsed 语义。 */
  async _readAll() {
    if (this._buffer !== null) return this._buffer;
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
  const encoded = encodeRequestBody(init.body);
  if (encoded !== undefined && encoded !== null && encoded.type !== null && !headers.has('content-type')) {
    headers.set('content-type', encoded.type);
  }
  const timeoutMs = typeof options.timeoutMs === 'number' ? options.timeoutMs : 120000;
  return await onceFetch(url, init, headers, encoded, init.signal, 5, timeoutMs);
}

/**
 * 安装垫片。**只在原生 fetch 不可用时安装**（例如带 `--no-experimental-fetch` 启动）：
 * 原生实现可用时就该用原生的。
 * @returns 是否真的安装（用于入口脚本打日志）
 */
function installFetchShim() {
  const missing = typeof globalThis.fetch !== 'function';
  if (!missing) return false;
  globalThis.Headers = globalThis.Headers === undefined ? HdshHeaders : globalThis.Headers;
  globalThis.FormData = globalThis.FormData === undefined ? HdshFormData : globalThis.FormData;
  globalThis.Blob = globalThis.Blob === undefined ? HdshBlob : globalThis.Blob;
  globalThis.File = globalThis.File === undefined ? HdshFile : globalThis.File;
  globalThis.Response = globalThis.Response === undefined ? HdshResponse : globalThis.Response;
  globalThis.fetch = hdshFetch;
  return true;
}

module.exports = { installFetchShim, hdshFetch, HdshHeaders, HdshFormData, HdshBlob, HdshFile, HdshResponse };
