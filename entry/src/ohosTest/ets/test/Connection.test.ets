/**
 * 协议兼容层单元测试。
 *
 * 覆盖对象是**纯逻辑**部分（不依赖网络、不依赖设备能力），因此可在设备/模拟器上稳定运行：
 *   - HostAddress：地址规范化、authority 生成、loopback 判定、token 提取
 *   - RpcTypes：endpoint/channel 目标校验（对齐上游 assertTarget 语义）
 *   - Envelope：一元信封构造与解析（含全部失败分支）
 *   - Cookies：Set-Cookie 多形态解析、按 authority 隔离的合并与清除
 *   - Backoff：D2 §3 的逐档延迟与抖动边界
 *
 * 每条断言的依据都指向 D2 的具体条目，失败即意味着实现与协议基线不一致。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  API_CHANNEL,
  backoffDelayMs,
  BACKOFF_STEPS_MS,
  checkTarget,
  CookieJar,
  buildClientRequest,
  endpointOf,
  extractStartupUrl,
  extractToken,
  isRetryable,
  parseConnectionResponse,
  parseCookieString,
  parseHostAddress,
  parseTarget,
  getString,
  getArray,
  isRecord,
  parseJson
} from 'connection';

function sampleArgs(): Record<string, Object> {
  const inner: Record<string, Object> = {};
  const args: Record<string, Object> = { 'args': inner as Object };
  return args;
}

export default function connectionTest() {
  describe('HostAddress', () => {
    it('parses host:port with default http scheme', 0, () => {
      const a = parseHostAddress('127.0.0.1:3000');
      expect(a !== undefined).assertTrue();
      expect(a!.hostname).assertEqual('127.0.0.1');
      expect(a!.port).assertEqual(3000);
      expect(a!.scheme).assertEqual('http');
      expect(a!.authority).assertEqual('127.0.0.1:3000');
      expect(a!.baseUrl).assertEqual('http://127.0.0.1:3000');
      expect(a!.wsBaseUrl).assertEqual('ws://127.0.0.1:3000');
      expect(a!.isLoopback).assertTrue();
    });

    it('derives ws/wss from scheme', 0, () => {
      const https = parseHostAddress('https://dsh.example.com');
      expect(https !== undefined).assertTrue();
      expect(https!.port).assertEqual(443);
      expect(https!.wsBaseUrl).assertEqual('wss://dsh.example.com:443');
      expect(https!.isLoopback).assertFalse();

      const plain = parseHostAddress('http://dsh.example.com');
      expect(plain!.port).assertEqual(80);
      expect(plain!.wsBaseUrl).assertEqual('ws://dsh.example.com:80');
    });

    it('strips path, query and credentials from the authority', 0, () => {
      const a = parseHostAddress('http://user:pass@10.0.0.5:8080/api/foo?x=1');
      expect(a !== undefined).assertTrue();
      expect(a!.authority).assertEqual('10.0.0.5:8080');
      expect(a!.baseUrl).assertEqual('http://10.0.0.5:8080');
    });

    it('handles IPv6 literals with brackets retained', 0, () => {
      const withPort = parseHostAddress('[::1]:8080');
      expect(withPort !== undefined).assertTrue();
      expect(withPort!.hostname).assertEqual('[::1]');
      expect(withPort!.port).assertEqual(8080);
      expect(withPort!.authority).assertEqual('[::1]:8080');
      expect(withPort!.isLoopback).assertTrue();

      const noPort = parseHostAddress('http://[fe80::1]');
      expect(noPort !== undefined).assertTrue();
      expect(noPort!.port).assertEqual(80);
      expect(noPort!.isLoopback).assertFalse();
    });

    it('classifies loopback variants', 0, () => {
      expect(parseHostAddress('localhost:1')!.isLoopback).assertTrue();
      expect(parseHostAddress('127.0.0.1:1')!.isLoopback).assertTrue();
      expect(parseHostAddress('127.9.9.9:1')!.isLoopback).assertTrue();
      expect(parseHostAddress('128.0.0.1:1')!.isLoopback).assertFalse();
      expect(parseHostAddress('192.168.1.5:1')!.isLoopback).assertFalse();
    });

    it('rejects malformed input', 0, () => {
      expect(parseHostAddress('')).assertUndefined();
      expect(parseHostAddress('   ')).assertUndefined();
      expect(parseHostAddress('host:0')).assertUndefined();
      expect(parseHostAddress('host:70000')).assertUndefined();
      expect(parseHostAddress('host:abc')).assertUndefined();
      expect(parseHostAddress('http://')).assertUndefined();
      expect(parseHostAddress('[::1')).assertUndefined();
      expect(parseHostAddress('bad host:80')).assertUndefined();
    });

    it('extracts token and startup url', 0, () => {
      const url = 'dsh web: http://127.0.0.1:3111/?token=abc123';
      expect(extractStartupUrl(url)).assertEqual('http://127.0.0.1:3111/?token=abc123');
      expect(extractToken('http://127.0.0.1:3111/?token=abc123')).assertEqual('abc123');
      expect(extractToken('http://127.0.0.1:3111/')).assertUndefined();

      const target = parseTarget('http://127.0.0.1:3111/?token=abc123');
      expect(target !== undefined).assertTrue();
      expect(target!.address.authority).assertEqual('127.0.0.1:3111');
      expect(target!.token).assertEqual('abc123');

      const noToken = parseTarget('192.168.1.5:3000');
      expect(noToken !== undefined).assertTrue();
      expect(noToken!.token).assertUndefined();
    });
  });

  describe('RpcTypes', () => {
    it('accepts a valid namespace/method endpoint', 0, () => {
      expect(checkTarget(API_CHANNEL, 'session/list').ok).assertTrue();
      expect(checkTarget(API_CHANNEL, 'settings/canOpenAgentPresetDirectory').ok).assertTrue();
      expect(checkTarget(API_CHANNEL, '$events').ok).assertTrue();
      expect(checkTarget(API_CHANNEL, 'dynamicCordisRunner/getClientCode').ok).assertTrue();
    });

    it('rejects the reserved /api channel', 0, () => {
      const r = checkTarget('/api', 'session/list');
      expect(r.ok).assertFalse();
    });

    it('rejects invalid endpoint shapes', 0, () => {
      expect(checkTarget(API_CHANNEL, '').ok).assertFalse();
      expect(checkTarget(API_CHANNEL, 'session/').ok).assertFalse();
      expect(checkTarget(API_CHANNEL, '/list').ok).assertFalse();
      expect(checkTarget(API_CHANNEL, 'session/./x').ok).assertFalse();
      expect(checkTarget(API_CHANNEL, 'session/../x').ok).assertFalse();
      expect(checkTarget(API_CHANNEL, 'session li/st').ok).assertFalse();
      expect(checkTarget(API_CHANNEL, 'session/li%20st').ok).assertFalse();
    });

    it('rejects invalid channels', 0, () => {
      expect(checkTarget('api', 'session/list').ok).assertFalse();
      expect(checkTarget('', 'session/list').ok).assertFalse();
      expect(checkTarget('/ap i', 'session/list').ok).assertFalse();
    });

    it('builds endpoints from namespace and method', 0, () => {
      expect(endpointOf('session', 'list')).assertEqual('session/list');
      expect(endpointOf('directoryPicker', 'createDirectory')).assertEqual('directoryPicker/createDirectory');
    });
  });

  describe('Envelope', () => {
    it('builds the client-request envelope with named args', 0, () => {
      const inner: Record<string, Object> = {};
      const args: Record<string, Object> = { '_request': inner as Object };
      const text = buildClientRequest('rpc-1', 'session/list', args as Object);
      expect(text !== undefined).assertTrue();
      const parsed = parseJson(text!);
      expect(parsed !== undefined).assertTrue();
      expect(getString(parsed, 'type')).assertEqual('client-request');
      expect(getString(parsed, 'rpcId')).assertEqual('rpc-1');
      expect(getString(parsed, 'method')).assertEqual('session/list');
      expect(isRecord(parsed!)).assertTrue();
    });

    it('parses an ok response and preserves the value', 0, () => {
      const body = '{"type":"server-response","rpcId":"r1","result":{"ok":true,"value":{"items":[]}}}';
      const result = parseConnectionResponse(body, 'r1', 'session/list');
      expect(result.ok).assertTrue();
      expect(isRecord(result.value!)).assertTrue();
      expect(getArray(result.value, 'items')!.length).assertEqual(0);
    });

    it('parses a business failure into code/message', 0, () => {
      const body = '{"type":"server-response","rpcId":"r1","result":{"ok":false,'
        + '"error":{"code":"gateway/arguments-invalid","message":"missing _request","details":{}}}}';
      const result = parseConnectionResponse(body, 'r1', 'session/list');
      expect(result.ok).assertFalse();
      expect(result.error!.code).assertEqual('gateway/arguments-invalid');
      expect(result.error!.message).assertEqual('missing _request');
      expect(result.error!.isCarrierFailure()).assertFalse();
    });

    it('tolerates a missing details object without dropping the failure', 0, () => {
      const body = '{"type":"server-response","rpcId":"r1","result":{"ok":false,'
        + '"error":{"code":"llm/model-discovery-rejected","message":"nope"}}}';
      const result = parseConnectionResponse(body, 'r1', 'llm/discoverModels');
      expect(result.ok).assertFalse();
      expect(result.error!.code).assertEqual('llm/model-discovery-rejected');
      expect(result.error!.details).assertEqual('');
    });

    it('rejects rpcId mismatch (carrier-level parse failure)', 0, () => {
      const body = '{"type":"server-response","rpcId":"other","result":{"ok":true,"value":1}}';
      const result = parseConnectionResponse(body, 'r1', 'session/list');
      expect(result.ok).assertFalse();
      expect(result.error!.code).assertEqual('carrier/parse');
      expect(result.error!.isCarrierFailure()).assertTrue();
    });

    it('rejects wrong envelope type', 0, () => {
      const body = '{"type":"client-request","rpcId":"r1","result":{"ok":true,"value":1}}';
      expect(parseConnectionResponse(body, 'r1', 'x/y').ok).assertFalse();
    });

    it('rejects malformed JSON and missing result', 0, () => {
      expect(parseConnectionResponse('not json', 'r1', 'x/y').ok).assertFalse();
      expect(parseConnectionResponse('{"type":"server-response","rpcId":"r1"}', 'r1', 'x/y').ok).assertFalse();
      expect(parseConnectionResponse(
        '{"type":"server-response","rpcId":"r1","result":{}}', 'r1', 'x/y').ok).assertFalse();
    });

    it('requires a value field when ok is true', 0, () => {
      const body = '{"type":"server-response","rpcId":"r1","result":{"ok":true}}';
      const result = parseConnectionResponse(body, 'r1', 'x/y');
      expect(result.ok).assertFalse();
      expect(result.error!.code).assertEqual('carrier/parse');
    });

    it('accepts an explicit null value', 0, () => {
      const body = '{"type":"server-response","rpcId":"r1","result":{"ok":true,"value":null}}';
      const result = parseConnectionResponse(body, 'r1', 'x/y');
      expect(result.ok).assertTrue();
    });

    it('rejects malformed error objects', 0, () => {
      const noError = '{"type":"server-response","rpcId":"r1","result":{"ok":false}}';
      expect(parseConnectionResponse(noError, 'r1', 'x/y').ok).assertFalse();
      const noCode = '{"type":"server-response","rpcId":"r1","result":{"ok":false,"error":{"message":"m"}}}';
      expect(parseConnectionResponse(noCode, 'r1', 'x/y').ok).assertFalse();
    });
  });

  describe('Cookies', () => {
    it('parses a single Set-Cookie with attributes', 0, () => {
      const records = parseCookieString(
        'dsh-auth-abc=xyz; Path=/; HttpOnly; SameSite=Strict', '127.0.0.1:3111');
      expect(records.length).assertEqual(1);
      expect(records[0].name).assertEqual('dsh-auth-abc');
      expect(records[0].value).assertEqual('xyz');
      expect(records[0].authority).assertEqual('127.0.0.1:3111');
    });

    it('parses newline-separated multiple cookies', 0, () => {
      const records = parseCookieString('a=1; Path=/\nb=2; HttpOnly', 'h:1');
      expect(records.length).assertEqual(2);
      expect(records[0].name).assertEqual('a');
      expect(records[1].name).assertEqual('b');
    });

    it('parses double-semicolon separated multiple cookies', 0, () => {
      const records = parseCookieString('a=1;; b=2', 'h:1');
      expect(records.length).assertEqual(2);
    });

    it('ignores attribute-only tokens', 0, () => {
      const records = parseCookieString('Path=/; HttpOnly; Secure', 'h:1');
      expect(records.length).assertEqual(0);
    });

    it('returns nothing for empty input', 0, () => {
      expect(parseCookieString('', 'h:1').length).assertEqual(0);
    });

    it('isolates cookies per authority', 0, () => {
      const jar = new CookieJar();
      jar.merge(parseCookieString('a=1', 'host-a:1'));
      jar.merge(parseCookieString('b=2', 'host-b:1'));
      expect(jar.headerFor('host-a:1')).assertEqual('a=1');
      expect(jar.headerFor('host-b:1')).assertEqual('b=2');
      expect(jar.headerFor('host-c:1')).assertUndefined();
      expect(jar.hasFor('host-a:1')).assertTrue();
      expect(jar.hasFor('host-c:1')).assertFalse();
      expect(jar.namesFor('host-a:1').length).assertEqual(1);
    });

    it('overwrites same-name cookie within the same authority', 0, () => {
      const jar = new CookieJar();
      jar.merge(parseCookieString('a=1', 'h:1'));
      jar.merge(parseCookieString('a=2', 'h:1'));
      expect(jar.headerFor('h:1')).assertEqual('a=2');
    });

    it('clears only the targeted authority', 0, () => {
      const jar = new CookieJar();
      jar.merge(parseCookieString('a=1', 'host-a:1'));
      jar.merge(parseCookieString('b=2', 'host-b:1'));
      jar.clearFor('host-a:1');
      expect(jar.hasFor('host-a:1')).assertFalse();
      expect(jar.hasFor('host-b:1')).assertTrue();
    });

    it('round-trips through snapshot and replaceAll', 0, () => {
      const jar = new CookieJar();
      jar.merge(parseCookieString('a=1', 'h:1'));
      const snapshot = jar.snapshot();
      const other = new CookieJar();
      other.replaceAll(snapshot);
      expect(other.headerFor('h:1')).assertEqual('a=1');
    });
  });

  describe('Backoff', () => {
    it('follows the documented step table (D2 §3)', 0, () => {
      expect(BACKOFF_STEPS_MS.length).assertEqual(6);
      expect(BACKOFF_STEPS_MS[0]).assertEqual(500);
      expect(BACKOFF_STEPS_MS[1]).assertEqual(1000);
      expect(BACKOFF_STEPS_MS[2]).assertEqual(2000);
      expect(BACKOFF_STEPS_MS[3]).assertEqual(4000);
      expect(BACKOFF_STEPS_MS[4]).assertEqual(8000);
      expect(BACKOFF_STEPS_MS[5]).assertEqual(10000);
    });

    it('applies 50%-100% jitter bounds per step', 0, () => {
      for (let step = 1; step <= BACKOFF_STEPS_MS.length; step++) {
        const base = BACKOFF_STEPS_MS[step - 1];
        expect(backoffDelayMs(step, 0)).assertEqual(Math.round(base * 0.5));
        expect(backoffDelayMs(step, 1)).assertEqual(base);
      }
    });

    it('clamps out-of-range random values', 0, () => {
      expect(backoffDelayMs(1, -5)).assertEqual(250);
      expect(backoffDelayMs(1, 5)).assertEqual(500);
    });

    it('clamps attempts beyond the last step to the 10s ceiling', 0, () => {
      expect(backoffDelayMs(99, 1)).assertEqual(10000);
      expect(backoffDelayMs(0, 1)).assertEqual(500);
    });

    it('reports retryability up to the step count', 0, () => {
      expect(isRetryable(1)).assertTrue();
      expect(isRetryable(6)).assertTrue();
      expect(isRetryable(7)).assertFalse();
    });
  });

  describe('JsonValue', () => {
    it('narrows values safely and never throws', 0, () => {
      const obj = parseJson('{"s":"x","n":1,"b":true,"arr":[1],"o":{"k":"v"}}');
      expect(obj !== undefined).assertTrue();
      expect(getString(obj, 's')).assertEqual('x');
      expect(getString(obj, 'missing')).assertUndefined();
      expect(getString(obj, 'n')).assertUndefined();
      expect(getArray(obj, 'arr')!.length).assertEqual(1);
      expect(getArray(obj, 's')).assertUndefined();
      expect(isRecord(parseJson('[1,2]'))).assertFalse();
      expect(parseJson('{bad')).assertUndefined();
    });
  });
}
