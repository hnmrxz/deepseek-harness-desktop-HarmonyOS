/**
 * 设置页投影测试（`settings/describe` → 设置项）。
 *
 * 【样本从哪来】
 *   `schema` 与 `value` 全部取自对 0.1.5-rc.1 真实 Host 的只读探测
 *   （`.research/protocol/probe-settings.mjs`，见 `docs/12-设置页契约.md`）。
 *   schema 是 `schemastery` 的 `toJSON()` 结果，**不是嵌套树，而是以 uid 为键的
 *   扁平表**——按嵌套树写的解析会得到一堆空的设置项，而且**不报错**。
 *   所以这里逐条钉住「从哪个结构键读到什么」。
 */

import { describe, expect, it } from '@ohos/hypium';
import { parseJson } from 'connection';
import {
  humanizeKey,
  mergeSettingsGroups,
  projectSettingsGroups,
  projectSettingsNamespace,
  SettingKind,
  SettingOrigin
} from 'appstate';
import type { SettingGroup } from 'appstate';

/** 实测 `ui-theme` 命名空间（union(const×3) + number(12–17)） */
const UI_THEME = '{"ns":"ui-theme","applies":"live","revision":0,"secrets":[],'
  + '"schema":{"uid":231,"refs":{'
  + '"220":{"type":"const","meta":{"required":true},"value":"light"},'
  + '"222":{"type":"const","meta":{"required":true},"value":"dark"},'
  + '"224":{"type":"const","meta":{"required":true},"value":"system"},'
  + '"225":{"type":"union","meta":{"default":"system"},"list":[220,222,224]},'
  + '"230":{"type":"number","meta":{"step":1,"min":12,"max":17,"default":14}},'
  + '"231":{"type":"object","meta":{"default":{}},"dict":{"preference":225,"fontSize":230}}}},'
  + '"value":{"preference":"system","fontSize":14}}';

export default function settingsProjectionTest() {
  describe('SettingsSchema', () => {
    /**
     * 实测 `ui-theme`：`preference` 是 `union(list: const…)` → CHOICE，
     * `fontSize` 是 `number` → TEXT。
     * 这条断言同时证明「按 `dict` 找字段、按 `list` 找枚举分支」这条路是对的。
     */
    it('reads fields from dict and enum branches from union.list', 0, () => {
      const ns = projectSettingsNamespace(parseJson(UI_THEME)!, true);
      expect(ns.ns).assertEqual('ui-theme');
      expect(ns.items.length).assertEqual(2);

      const preference = ns.items[0];
      expect(preference.key).assertEqual('ui-theme.preference');
      expect(preference.kind).assertEqual(SettingKind.CHOICE);
      expect(preference.textValue).assertEqual('system');
      // 三个 const 分支都成了选项
      expect(preference.choices.length).assertEqual(3);
      expect(preference.choices[0].value).assertEqual('light');
      expect(preference.choices[2].value).assertEqual('system');
    });

    it('renders a number field as text and states its range in the hint', 0, () => {
      const ns = projectSettingsNamespace(parseJson(UI_THEME)!, true);
      const fontSize = ns.items[1];
      expect(fontSize.kind).assertEqual(SettingKind.TEXT);
      expect(fontSize.textValue).assertEqual('14');
      // D3 §4：设置项不能只有名字。实测多数字段没有 description，
      // 因此 hint 必须降级到「约束 + 上游字段名」而不是留空。
      expect(fontSize.hint.indexOf('12') >= 0).assertTrue();
      expect(fontSize.hint.indexOf('17') >= 0).assertTrue();
      expect(fontSize.hint.indexOf('ui-theme.fontSize') >= 0).assertTrue();
    });

    /**
     * 实测 `locale`：`value` 是 `{}`（用户没设过）。
     * 「未设」是常态，不能因此丢掉这一项——丢掉会让用户以为 Host 没有这个设置。
     */
    it('keeps a field visible when the value is unset', 0, () => {
      const unset = '{"ns":"locale","applies":"live","revision":0,"secrets":[],'
        + '"schema":{"uid":235,"refs":{'
        + '"234":{"type":"string","meta":{"required":false}},'
        + '"235":{"type":"object","meta":{"default":{}},"dict":{"preference":234}}}},'
        + '"value":{}}';
      const ns = projectSettingsNamespace(parseJson(unset)!, true);
      expect(ns.items.length).assertEqual(1);
      expect(ns.items[0].kind).assertEqual(SettingKind.TEXT);
      expect(ns.items[0].textValue).assertEqual('');
      expect(ns.items[0].userSet).assertFalse();
      expect(ns.items[0].hint.length > 0).assertTrue();
    });

    /**
     * **三层取值的可见性**：`value` 是「默认 → 基线 → 用户层」的合并结果，
     * 所以只有 `user` 层存在该字段才说明「用户显式设过」。
     * 界面靠这个标记区分「继承默认」与「用户设成了同一个值」。
     */
    it('marks a field overridden by the user layer', 0, () => {
      const overridden = '{"ns":"ui-theme","applies":"live","revision":3,"secrets":[],'
        + '"schema":{"uid":231,"refs":{'
        + '"225":{"type":"union","meta":{},"list":[220]},'
        + '"220":{"type":"const","meta":{},"value":"dark"},'
        + '"231":{"type":"object","meta":{},"dict":{"preference":225}}}},'
        + '"value":{"preference":"dark"},'
        + '"user":{"preference":"dark"},'
        + '"base":{"preference":"system"}}';
      const ns = projectSettingsNamespace(parseJson(overridden)!, true);
      expect(ns.items[0].userSet).assertTrue();

      // 同一个值但 user 层没有 → 是继承来的，不能标成「已自定义」
      const inherited = '{"ns":"ui-theme","applies":"live","revision":0,"secrets":[],'
        + '"schema":{"uid":231,"refs":{'
        + '"225":{"type":"union","meta":{},"list":[220]},'
        + '"220":{"type":"const","meta":{},"value":"dark"},'
        + '"231":{"type":"object","meta":{},"dict":{"preference":225}}}},'
        + '"value":{"preference":"dark"},"base":{"preference":"dark"}}';
      const ns2 = projectSettingsNamespace(parseJson(inherited)!, true);
      expect(ns2.items[0].textValue).assertEqual('dark');
      expect(ns2.items[0].userSet).assertFalse();
    });

    /**
     * 实测 `llm-deepseek.apiKeyEnv` 带 `meta.role = 'credential-ref'`——
     * 这是「这一项其实是凭据引用」的机器可读标记，界面要渲染成凭据链接
     * 而不是普通文本框（否则用户会把凭据名当明文往里填）。
     */
    it('detects a credential-reference field from meta.role', 0, () => {
      const withCred = '{"ns":"llm-deepseek","applies":"live","revision":0,"secrets":[],'
        + '"schema":{"uid":374,"refs":{'
        + '"301":{"type":"string","meta":{"role":"credential-ref","default":"DEEPSEEK_API_KEY"}},'
        + '"374":{"type":"object","meta":{},"dict":{"apiKeyEnv":301}}}},'
        + '"value":{"apiKeyEnv":"DEEPSEEK_API_KEY"}}';
      const ns = projectSettingsNamespace(parseJson(withCred)!, true);
      expect(ns.items.length).assertEqual(1);
      expect(ns.items[0].credentialRef).assertTrue();
      expect(ns.items[0].hint.indexOf('凭据') >= 0).assertTrue();
    });

    /**
     * `writable: false` 时**所有**项只读：Host 明确说了不接受写，
     * 界面给出可点的控件就是一个会失败的假入口。
     */
    it('marks every item read-only when the host is not writable', 0, () => {
      const ns = projectSettingsNamespace(parseJson(UI_THEME)!, false);
      for (let i = 0; i < ns.items.length; i++) {
        expect(ns.items[i].readOnly).assertTrue();
      }
    });

    /** `applies: 'restart'` 必须如实传到契约里（界面据此提示「需重启」） */
    it('carries the restart requirement', 0, () => {
      const restart = UI_THEME.replace('"applies":"live"', '"applies":"restart"');
      const ns = projectSettingsNamespace(parseJson(restart)!, true);
      expect(ns.items[0].appliesLive).assertFalse();
    });

    /**
     * 数组 / 嵌套对象**不提供编辑入口**（第一版没有实测过「写数组元素」的线上效果）：
     * 以只读信息行呈现，而不是猜一个编辑器出来。
     *
     * 同时断言 `hostWritable` 仍为 true：**「本客户端没做」不等于「Host 不允许」**。
     * 两者混用会渲染出会撒谎的界面（用户会去 Host 上找一个并不存在的权限开关）。
     */
    it('presents array and object fields read-only without claiming the host refused', 0, () => {
      const withArray = '{"ns":"x","applies":"live","revision":0,"secrets":[],'
        + '"schema":{"uid":1,"refs":{'
        + '"2":{"type":"string","meta":{}},'
        + '"3":{"type":"array","meta":{"default":[]},"inner":2},'
        + '"1":{"type":"object","meta":{},"dict":{"models":3}}}},'
        + '"value":{"models":[{"id":"a"},{"id":"b"}]}}';
      const ns = projectSettingsNamespace(parseJson(withArray)!, true);
      const item = ns.items[0];
      expect(`count=${ns.items.length};kind=${item.kind};readOnly=${item.readOnly};hostWritable=${item.hostWritable}`)
        .assertEqual('count=1;kind=info;readOnly=true;hostWritable=true');
    });

    /** `projectSettingsGroups` 只保留有字段的命名空间，标题就是命名空间名 */
    it('groups namespaces and skips the empty ones', 0, () => {
      const describe = '{"writable":true,"hasDocument":true,"namespaces":['
        + UI_THEME + ','
        + '{"ns":"empty-ns","applies":"live","revision":0,"secrets":[],'
        + '"schema":{"uid":9,"refs":{"9":{"type":"object","meta":{},"dict":{}}}},"value":{}}'
        + ']}';
      const groups = projectSettingsGroups(parseJson(describe));
      expect(groups.length).assertEqual(1);
      expect(groups[0].title).assertEqual('ui-theme');
      expect(groups[0].items[0].origin).assertEqual(SettingOrigin.HOST);
    });

    it('tolerates a missing reply without throwing', 0, () => {
      expect(projectSettingsGroups(undefined).length).assertEqual(0);
      expect(projectSettingsGroups(parseJson('{}')).length).assertEqual(0);
      expect(projectSettingsNamespace(parseJson('{"ns":"x"}')!, true).items.length).assertEqual(0);
    });
  });

  describe('SettingsMerge', () => {
    /**
     * 本地偏好**不能被 Host 设置顶掉**：上游没有「通知」「离线缓存」这些命名空间，
     * 连上后整页替换会让这些开关从界面上消失（用户会以为功能没了）。
     */
    it('keeps local preferences after connecting to a host', 0, () => {
      const host = projectSettingsGroups(parseJson('{"writable":true,"namespaces":[' + UI_THEME + ']}'));
      const localNs = projectSettingsNamespace(parseJson(UI_THEME)!, true);
      // 借同一个 schema 造一批「本地项」，只改来源标记
      const local: SettingGroup[] = [{ title: '本机偏好', items: localNs.items }];
      const merged = mergeSettingsGroups(host, local);
      expect(merged.length).assertEqual(2);
      // Host 分组在前，本地在后
      expect(merged[0].title).assertEqual('ui-theme');
      expect(merged[1].title).assertEqual('本机偏好');
    });

    /** schema 里没有显示名（实测），标签由字段名派生——必须始终非空 */
    it('derives a non-empty label from the field name', 0, () => {
      expect(humanizeKey('fontSize')).assertEqual('Font size');
      expect(humanizeKey('apiKeyEnv')).assertEqual('Api key env');
      expect(humanizeKey('id')).assertEqual('Id');
      expect(humanizeKey('').length).assertEqual(0);
    });
  });
}
