/**
 * 判据类纯函数的用例（hostruntime 的核心版本决策 + appstate 的核心/诊断契约）。
 *
 * 【为什么优先测这些】它们全都是**判据**：什么情况下敢把一个核心版本设为当前、
 * 什么情况下必须回滚、哪些目录永远不能删、"未知"该不该算"可安装"、
 * 本地核心模式下该显示哪几项诊断。这些判断一旦写错，症状是"应用看起来正常但做了错事"
 * ——比崩溃更难发现。而它们都是纯函数，不需要设备就能钉死。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  ActivationAction,
  CoreHealth,
  CoreState,
  emptyState,
  evictionCandidates,
  isSafeVersion,
  parseArchiveName,
  parseState,
  serializeState,
  topDirOf,
  decideActivation,
  decideRollback
} from 'hostruntime';
import {
  CorePhase,
  DiagMode,
  PluginNative,
  classifyPlugin,
  corePhaseOfHostState,
  diagModeOf,
  filterDiagEntries,
  sessionEmptyCopy
} from 'appstate';
import type { DiagEntry } from 'appstate';

function entry(name: string): DiagEntry {
  return { name: name, passed: true, detail: '', advice: '' };
}

export default function coreDecisionTest() {
  describe('CoreDecision', () => {

    // ── 激活事务：只有健康检查通过才敢切当前版本 ────────────────────────
    it('refuses_activation_when_health_not_pass', 0, () => {
      const s: CoreState = emptyState();
      const d = decideActivation(s, '1.0.0', CoreHealth.UNKNOWN, '未检查');
      expect(d.action).assertEqual(ActivationAction.REFUSE);
      // 关键不变式：拒绝时**不许改动状态**（尤其不能把 current 写成候选）
      expect(d.next.current).assertEqual('');
    });

    it('refuses_activation_on_empty_candidate', 0, () => {
      const s: CoreState = { current: '1.0.0', previous: '', history: ['1.0.0'] };
      const d = decideActivation(s, '', CoreHealth.PASS, '');
      expect(d.action).assertEqual(ActivationAction.REFUSE);
      expect(d.next.current).assertEqual('1.0.0');
    });

    it('activates_and_keeps_previous', 0, () => {
      const s: CoreState = { current: '1.0.0', previous: '', history: ['1.0.0'] };
      const d = decideActivation(s, '1.1.0', CoreHealth.PASS, '');
      expect(d.action).assertEqual(ActivationAction.ACTIVATE);
      expect(d.next.current).assertEqual('1.1.0');
      // previous 必须成为回滚目标
      expect(d.next.previous).assertEqual('1.0.0');
      expect(d.next.history[0]).assertEqual('1.1.0');
    });

    it('activation_is_idempotent_for_current', 0, () => {
      const s: CoreState = { current: '1.1.0', previous: '1.0.0', history: ['1.1.0', '1.0.0'] };
      const d = decideActivation(s, '1.1.0', CoreHealth.PASS, '');
      expect(d.action).assertEqual(ActivationAction.ACTIVATE);
      // 幂等：previous 不能被自己顶掉
      expect(d.next.previous).assertEqual('1.0.0');
    });

    // ── 回滚 ────────────────────────────────────────────────────────────
    it('refuses_rollback_without_previous', 0, () => {
      const s: CoreState = { current: '1.0.0', previous: '', history: ['1.0.0'] };
      expect(decideRollback(s, ['1.0.0']).action).assertEqual(ActivationAction.REFUSE);
    });

    it('refuses_rollback_when_previous_dir_missing', 0, () => {
      const s: CoreState = { current: '1.1.0', previous: '1.0.0', history: ['1.1.0', '1.0.0'] };
      // 上一版目录已被删 ⇒ 绝不能把 current 指向一个不存在的版本
      const d = decideRollback(s, ['1.1.0']);
      expect(d.action).assertEqual(ActivationAction.REFUSE);
      expect(d.next.current).assertEqual('1.1.0');
    });

    it('rolls_back_and_swaps_previous', 0, () => {
      const s: CoreState = { current: '1.1.0', previous: '1.0.0', history: ['1.1.0', '1.0.0'] };
      const d = decideRollback(s, ['1.1.0', '1.0.0']);
      expect(d.action).assertEqual(ActivationAction.ROLLBACK);
      expect(d.next.current).assertEqual('1.0.0');
      expect(d.next.previous).assertEqual('1.1.0');
    });

    // ── 清理：当前版与上一版永远不能删 ──────────────────────────────────
    it('never_evicts_current_or_previous', 0, () => {
      const s: CoreState = { current: '1.1.0', previous: '1.0.0', history: ['1.1.0', '1.0.0', '0.9.0'] };
      const doomed = evictionCandidates(s, ['1.1.0', '1.0.0', '0.9.0'], 0);
      expect(doomed.includes('1.1.0')).assertFalse();
      expect(doomed.includes('1.0.0')).assertFalse();
      expect(doomed.includes('0.9.0')).assertTrue();
    });

    // ── 状态序列化：坏文件不能让应用起不来 ──────────────────────────────
    it('tolerates_broken_state_json', 0, () => {
      const s = parseState('{ this is not json');
      expect(s.current).assertEqual('');
      expect(s.history.length).assertEqual(0);
    });

    it('round_trips_state', 0, () => {
      const s: CoreState = { current: '2.0.0', previous: '1.0.0', history: ['2.0.0', '1.0.0'] };
      const back = parseState(serializeState(s));
      expect(back.current).assertEqual('2.0.0');
      expect(back.previous).assertEqual('1.0.0');
    });

    // ── 版本号会变成目录名：路径穿越必须显式拒绝 ────────────────────────
    it('rejects_unsafe_version_names', 0, () => {
      expect(isSafeVersion('../../etc')).assertFalse();
      expect(isSafeVersion('a/b')).assertFalse();
      expect(isSafeVersion('')).assertFalse();
      expect(isSafeVersion('1.0.0')).assertTrue();
      expect(isSafeVersion('0.1.5-rc.2')).assertTrue();
    });

    it('parses_container_name', 0, () => {
      const v = parseArchiveName('dsh-core-0.1.5-rc.2-openharmony-arm64.zip');
      expect(v).assertEqual('0.1.5-rc.2');
      // 不是本项目容器名 ⇒ 空串（不猜）
      expect(parseArchiveName('something-else.zip')).assertEqual('');
      expect(topDirOf('1.2.3')).assertEqual('dsh-core-1.2.3');
    });

    // ── 阶段映射：未知值必须保守落到"未接线" ────────────────────────────
    it('maps_unknown_host_state_conservatively', 0, () => {
      expect(corePhaseOfHostState('ready')).assertEqual(CorePhase.READY);
      expect(corePhaseOfHostState('idle')).assertEqual(CorePhase.IDLE);
      // 拼错/新增的值绝不能谎称就绪
      expect(corePhaseOfHostState('rdy')).assertEqual(CorePhase.UNWIRED);
    });

    // ── 插件三态：未知不等于可安装 ──────────────────────────────────────
    it('unknown_plugin_kind_is_not_installable', 0, () => {
      const unknown = classifyPlugin('p', '1.0.0', PluginNative.UNKNOWN);
      expect(unknown.installable).assertFalse();
      expect(unknown.badge).assertEqual('待确认');
      const pure = classifyPlugin('p', '1.0.0', PluginNative.PURE_JS);
      expect(pure.installable).assertTrue();
      const native = classifyPlugin('p', '1.0.0', PluginNative.NATIVE);
      expect(native.installable).assertFalse();
      expect(native.badge).assertEqual('需发版');
    });

    // ── 诊断模式分流 ────────────────────────────────────────────────────
    it('diag_mode_filters_remote_only_entries', 0, () => {
      const all: DiagEntry[] = [entry('端点'), entry('TLS'), entry('认证'), entry('协议'), entry('Host')];

      // 本地核心：TLS 与认证不适用（回环 + --skip-auth）
      const local = filterDiagEntries(DiagMode.LOCAL_CORE, all);
      expect(local.length).assertEqual(3);
      for (let i = 0; i < local.length; i++) {
        expect(local[i].name === 'TLS' || local[i].name === '认证').assertFalse();
      }

      // 远程：五项全在
      expect(filterDiagEntries(DiagMode.REMOTE_HOST, all).length).assertEqual(5);
      // 未接线：没有可诊断的对象
      expect(filterDiagEntries(DiagMode.UNWIRED, all).length).assertEqual(0);
    });

    it('diag_mode_derivation', 0, () => {
      expect(diagModeOf(true, true)).assertEqual(DiagMode.LOCAL_CORE);
      expect(diagModeOf(false, true)).assertEqual(DiagMode.REMOTE_HOST);
      expect(diagModeOf(false, false)).assertEqual(DiagMode.UNWIRED);
    });

    // ── 空态文案按阶段分档：不同阶段必须给不同下一步 ────────────────────
    it('empty_copy_differs_per_phase', 0, () => {
      const unwired = sessionEmptyCopy(CorePhase.UNWIRED).title;
      const empty = sessionEmptyCopy(CorePhase.EMPTY).title;
      const failed = sessionEmptyCopy(CorePhase.FAILED).title;
      expect(unwired === empty).assertFalse();
      expect(empty === failed).assertFalse();
      // 每一档都要给出"下一步"，而不是只说"没有会话"
      expect(sessionEmptyCopy(CorePhase.UNWIRED).hint.length > 0).assertTrue();
    });
  });
}
