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
  parseSettingInput,
  projectSettingsEntries,
  projectSettingsGroups,
  projectSettingsNamespace,
  SettingKind,
  SettingOrigin,
  SettingValueType,
  settingsMutateArgs,
  splitSettingKey
} from 'appstate';
import type { SettingGroup, SettingItem } from 'appstate';

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

/** 实测 `locale` 命名空间（string + pattern，且 `value` 为 `{}`） */
const LOCALE_NS = '{"ns":"locale","applies":"live","revision":0,"secrets":[],'
  + '"schema":{"uid":235,"refs":{'
  + '"234":{"type":"string","meta":{"pattern":{"source":"^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$","flags":"u"},'
  + '"required":false}},'
  + '"235":{"type":"object","meta":{"default":{}},"dict":{"preference":234}}}},'
  + '"value":{}}';

/** 从实测 schema 造一个设置项，只覆盖要断言的那部分字段 */
function itemOf(valueType: SettingValueType, text: string, min: number, max: number,
  step: number, pattern: string, required: boolean): SettingItem {
  return {
    key: 'ns.field', label: 'F', hint: 'h', kind: SettingKind.TEXT,
    boolValue: false, textValue: text, options: [], choices: [],
    readOnly: false, hostWritable: true, appliesLive: true,
    origin: SettingOrigin.HOST, userSet: false, credentialRef: false,
    valueType: valueType, minValue: min, maxValue: max, stepValue: step,
    hasMin: min !== 0, hasMax: max !== 0, pattern: pattern, required: required
  };
}

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

  describe('SettingsWrite', () => {
    /**
     * `settings/mutate` 的实参构造：`path` 是**分段数组**，`op` 是 `set`。
     *
     * 这三条断言背后是上游三个写端点的语义差异（D2b §4）：
     * `update` 的 patch 是浅覆盖、`replace` 会**删掉未出现的键**——
     * 只有 `mutate` 能只改一个字段而不动其它。选错会静默删掉用户的其他设置。
     */
    it('builds a path-addressed mutate operation', 0, () => {
      const args = settingsMutateArgs('ui-theme', 'fontSize', 16 as Object, 3) as Record<string, Object>;
      expect(args['ns'] as string).assertEqual('ui-theme');
      expect(args['expectedRevision'] as number).assertEqual(3);
      const ops = args['ops'] as Object[];
      expect(ops.length).assertEqual(1);
      const op = ops[0] as Record<string, Object>;
      expect(op['op'] as string).assertEqual('set');
      expect(op['value'] as number).assertEqual(16);
      const path = op['path'] as Object[];
      expect(path.length).assertEqual(1);
      expect(path[0] as string).assertEqual('fontSize');
    });

    /**
     * `expectedRevision` **必须带上**：省略等于放弃乐观并发检查，
     * 两个客户端同时改会互相覆盖（Host 把并发冲突做成了独立结果
     * `settings/conflict`，不传令牌就永远不会触发它）。
     */
    it('always carries the concurrency token', 0, () => {
      const args = settingsMutateArgs('ui-theme', 'preference', 'dark' as Object, 0) as Record<string, Object>;
      expect(args['expectedRevision'] !== undefined).assertTrue();
      expect(args['expectedRevision'] as number).assertEqual(0);
    });

    /** 字段名可能含点（上游 `dict` 键名无限制）：路径必须逐段切 */
    it('splits a dotted field path into segments', 0, () => {
      const args = settingsMutateArgs('ns', 'a.b.c', 'v' as Object, 1) as Record<string, Object>;
      const path = (args['ops'] as Object[])[0] as Record<string, Object>;
      const segs = path['path'] as Object[];
      expect(segs.length).assertEqual(3);
      expect(segs[2] as string).assertEqual('c');
    });

    /**
     * **只切第一个点**：命名空间名不含点（实测 14 个皆如此），字段名可能含点。
     * 若按最后一个点切，`llm-deepseek.retryPolicy.mode` 会被拆成
     * 命名空间 `llm-deepseek.retryPolicy`（不存在）——写必然被拒。
     */
    it('splits the setting key at the first dot only', 0, () => {
      const parts = splitSettingKey('llm-deepseek.retryPolicy.mode');
      expect(parts !== undefined).assertTrue();
      expect(parts!.ns).assertEqual('llm-deepseek');
      expect(parts!.fieldPath).assertEqual('retryPolicy.mode');
    });

    /** 拆不开的 key 必须返回 undefined（调用方据此拒绝写，而不是猜命名空间） */
    it('refuses a key it cannot split', 0, () => {
      expect(splitSettingKey('nodot') === undefined).assertTrue();
      expect(splitSettingKey('.leading') === undefined).assertTrue();
      expect(splitSettingKey('trailing.') === undefined).assertTrue();
      expect(splitSettingKey('') === undefined).assertTrue();
    });

    /** 写状态（revision 是并发令牌）跟着命名空间走，投影时必须一并取出 */
    it('carries the namespace write state alongside the group', 0, () => {
      const describe = '{"writable":true,"hasDocument":true,"namespaces":['
        + UI_THEME.replace('"revision":0', '"revision":7')
        + ']}';
      const entries = projectSettingsEntries(parseJson(describe));
      expect(entries.length).assertEqual(1);
      expect(entries[0].state.ns).assertEqual('ui-theme');
      expect(entries[0].state.revision).assertEqual(7);
      expect(entries[0].state.writable).assertTrue();
      expect(entries[0].state.applies).assertEqual('live');
      // 纯展示路径不暴露 revision
      expect(projectSettingsGroups(parseJson(describe)).length).assertEqual(1);
    });
  });

  describe('SettingsInput', () => {
    /**
     * **数字字段必须发数字，不能发字符串。**
     * 实测 `ui-theme.fontSize` 的 schema 是 `{"type":"number"}`：
     * 发 `"16"` 会被 Host 的 schema 校验拒绝，而错误只说「不符合 schema」——
     * 用户看到一个自己按提示填的数字被拒，无从下手。
     */
    it('converts a numeric input to a JSON number', 0, () => {
      const item = itemOf(SettingValueType.NUMBER, '14', 12, 17, 1, '', false);
      const r = parseSettingInput(item, '16');
      expect(r.ok).assertTrue();
      expect(typeof r.value).assertEqual('number');
      expect(r.value as number).assertEqual(16);
    });

    it('keeps a string input as a string', 0, () => {
      const item = itemOf(SettingValueType.STRING, '', 0, 0, 0, '', false);
      const r = parseSettingInput(item, 'deepseek-chat');
      expect(r.ok).assertTrue();
      expect(typeof r.value).assertEqual('string');
    });

    /** 客户端先校验：给出**具体**原因，而不是把 Host 的「不符合 schema」转给用户 */
    it('rejects a number outside the measured range with a specific reason', 0, () => {
      const item = itemOf(SettingValueType.NUMBER, '14', 12, 17, 1, '', false);
      const low = parseSettingInput(item, '11');
      expect(low.ok).assertFalse();
      expect(low.message.indexOf('12') >= 0).assertTrue();
      const high = parseSettingInput(item, '18');
      expect(high.ok).assertFalse();
      expect(high.message.indexOf('17') >= 0).assertTrue();
      // 边界值本身必须放行
      expect(parseSettingInput(item, '12').ok).assertTrue();
      expect(parseSettingInput(item, '17').ok).assertTrue();
    });

    it('rejects a non-numeric input for a numeric field', 0, () => {
      const item = itemOf(SettingValueType.NUMBER, '14', 0, 0, 1, '', false);
      const r = parseSettingInput(item, 'abc');
      expect(r.ok).assertFalse();
      expect(r.message.indexOf('数字') >= 0).assertTrue();
    });

    /** 空串对数字字段永远非法（JSON 里没有「空数字」） */
    it('rejects an empty value for a numeric field', 0, () => {
      const item = itemOf(SettingValueType.NUMBER, '14', 0, 0, 1, '', false);
      expect(parseSettingInput(item, '   ').ok).assertFalse();
    });

    /**
     * `step` 只在 >1 时当约束：实测多数项的 `step` 是 1，
     * 把 step=1 也拿来提示会变成无意义的噪音（「须为 1 的整数倍」）。
     */
    it('enforces step only when it is greater than one', 0, () => {
      const stepped = itemOf(SettingValueType.NUMBER, '', 0, 20, 5, '', false);
      expect(parseSettingInput(stepped, '15').ok).assertTrue();
      expect(parseSettingInput(stepped, '13').ok).assertFalse();
      const unit = itemOf(SettingValueType.NUMBER, '', 0, 20, 1, '', false);
      expect(parseSettingInput(unit, '13').ok).assertTrue();
    });

    /** 字符串字段的 `pattern`（实测形如 `{source, flags}`）要被真正执行 */
    it('enforces a string pattern', 0, () => {
      const item = itemOf(SettingValueType.STRING, '', 0, 0, 0,
        '^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$', false);
      expect(parseSettingInput(item, 'zh-Hans').ok).assertTrue();
      const bad = parseSettingInput(item, '中文');
      expect(bad.ok).assertFalse();
      expect(bad.message.indexOf('格式') >= 0).assertTrue();
    });

    it('rejects an empty value only when the field is required', 0, () => {
      const req = itemOf(SettingValueType.STRING, '', 0, 0, 0, '', true);
      expect(parseSettingInput(req, '').ok).assertFalse();
      const opt = itemOf(SettingValueType.STRING, '', 0, 0, 0, '', false);
      expect(parseSettingInput(opt, '').ok).assertTrue();
    });

    /**
     * 上游 schema 里的正则若本身非法，**不能**因此拦下用户输入——
     * 那会让这一项永远改不了（一个坏 schema 就锁死一个设置）。
     * 放行并交给 Host 判定。
     */
    it('does not block input when the schema pattern is itself invalid', 0, () => {
      const item = itemOf(SettingValueType.STRING, '', 0, 0, 0, '([unclosed', false);
      expect(parseSettingInput(item, 'anything').ok).assertTrue();
    });

    /**
     * `valueType` 必须由 schema 决定：实测 `ui-theme.fontSize` 是 number，
     * 而 `llm-deepseek.apiKeyEnv` 是 string。投影时搞错类型，
     * 表现就是「按提示填的数字被 Host 拒绝」。
     */
    it('derives the wire value type from the schema', 0, () => {
      const ns = projectSettingsNamespace(parseJson(UI_THEME)!, true);
      // items[0] = preference（union → CHOICE），items[1] = fontSize（number）
      expect(ns.items[1].valueType).assertEqual(SettingValueType.NUMBER);
      expect(ns.items[1].hasMin).assertTrue();
      expect(ns.items[1].minValue).assertEqual(12);
      expect(ns.items[1].maxValue).assertEqual(17);
    });

    /** 实测 `locale.preference` 带 pattern，投影要把它取出来 */
    it('carries the pattern from meta into the item', 0, () => {
      const ns = projectSettingsNamespace(parseJson(LOCALE_NS)!, true);
      expect(ns.items.length).assertEqual(1);
      expect(ns.items[0].pattern.indexOf('^[A-Za-z]') === 0).assertTrue();
      expect(ns.items[0].valueType).assertEqual(SettingValueType.STRING);
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
