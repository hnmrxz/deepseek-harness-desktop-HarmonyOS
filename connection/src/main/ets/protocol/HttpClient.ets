/**
 * HTTP 载体（一元 RPC）。
 *
 * 事实基线（D2 §1.1 / §2.1）：
 *   - `POST <baseUrl>/api/<endpoint>`，`content-type: application/json`
 *   - 实现选择：**每个请求新建 HttpRequest 实例**。理由：
 *     ① 实例 cookie 自动共享（enableAutoCookie）对多 Host 与「绑定 authority」的 cookie 语义不安全，
 *        本项目按 D2 §2.1 自行管理 cookie（见 Cookies.ets）；
 *     ② 实例级配置（connectTimeout/readTimeout）与并发互不干扰，便于按请求定制超时。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { isRecord } from './JsonValue';
import { CookieJar, parseCookieString, parseSetCookieHeader } from './Cookies';

/** HTTP 调用返回（区分「已获响应」与「载体失败」） */
export interface HttpOutcome {
  /** HTTP 状态码；载体失败时为 0 */
  status: number;
  /** 响应体文本；无响应时为 '' */
  body: string;
  /** 是否已获得 HTTP 响应（false = 连接/DNS/TLS/超时等载体失败） */
  responded: boolean;
  /** 载体失败原因（responded=false 时有值） */
  transportError?: string;
  /** 响应头（用于提取 Set-Cookie） */
  responseHeader?: Object;
  /** 服务器返回的原始 cookie 字符串（诊断用） */
  rawCookies: string;
}

/** 从 HttpResponse 中安全取出响应头 */
function readHeader(response: http.HttpResponse): Object | undefined {
  const value: Object = response.header;
  return isRecord(value) ? value : undefined;
}

/** 读取响应体文本（expectDataType=STRING 时 result 为 string） */
function readBody(response: http.HttpResponse): string {
  const result: string | Object | ArrayBuffer = response.result;
  if (typeof result === 'string') {
    return result as string;
  }
  return '';
}

export class HttpClient {
  private jar: CookieJar;

  constructor(jar: CookieJar) {
    this.jar = jar;
  }

  /**
   * 发起一次 HTTP 请求。
   * @param url 完整地址
   * @param authority 规范化 authority（cookie 隔离键）
   * @param post 是否 POST
   * @param body 请求体（POST 时提供）
   * @param timeoutMs 超时毫秒
   * @param collectCookies 是否解析并合并 Set-Cookie
   */
  async send(url: string, authority: string, post: boolean, body: string | undefined,
    timeoutMs: number, collectCookies: boolean): Promise<HttpOutcome> {
    const request: http.HttpRequest = http.createHttp();
    const header: Record<string, string> = {};
    header['accept'] = 'application/json, text/plain, */*';
    if (post) {
      header['content-type'] = 'application/json';
    }
    const cookie: string | undefined = this.jar.headerFor(authority);
    if (cookie !== undefined) {
      header['cookie'] = cookie;
    }

    let outcome: HttpOutcome;
    try {
      const options: http.HttpRequestOptions = {
        method: post ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: header,
        readTimeout: timeoutMs,
        connectTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      };
      if (body !== undefined) {
        options.extraData = body;
      }
      const response: http.HttpResponse = await request.request(url, options);
      outcome = {
        status: response.responseCode as number,
        body: readBody(response),
        responded: true,
        rawCookies: response.cookies ?? ''
      };
      const responseHeader: Object | undefined = readHeader(response);
      if (responseHeader !== undefined) {
        outcome.responseHeader = responseHeader;
      }
      if (collectCookies) {
        this.harvestCookies(responseHeader, outcome.rawCookies, authority);
      }
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      outcome = {
        status: 0,
        body: '',
        responded: false,
        transportError: `code=${businessError.code} message=${businessError.message}`,
        rawCookies: ''
      };
    } finally {
      request.destroy();
    }
    return outcome;
  }

  /** 从响应头或原始 cookie 字符串中收获 cookie 并合并进 jar */
  private harvestCookies(responseHeader: Object | undefined, rawCookies: string, authority: string): void {
    let records = parseSetCookieHeader(responseHeader, authority);
    if (records.length === 0 && rawCookies.length > 0) {
      records = parseCookieString(rawCookies, authority);
    }
    if (records.length > 0) {
      this.jar.merge(records);
    }
  }
}
