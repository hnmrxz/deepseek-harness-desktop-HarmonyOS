/**
 * 诊断报告的**空态**（不是「演示数据」）。
 *
 * 【为什么必须有这个函数而不是让调用方写 `{}`】
 * ArkTS 禁止无法对应到已声明类型的对象字面量（`arkts-no-obj-literals`），
 * 所以空值必须由**显式标注返回类型**的工厂产出。集中于一处也让
 * 「什么算空报告」只有一种定义。
 *
 * 【为什么空报告的每一项都要说实话】
 *   旧实现这里是 `stubDiagnostics()`：五项全绿、`home=D:/work`、
 *   「Host 版本 0.1.2-rc.1 在受支持矩阵内」——**全部编造**。
 *   诊断页的唯一用途就是「出问题时告诉我哪里不对」，
 *   一份编造的全绿报告会把用户引向完全错误的方向。
 *   因此空报告必须是：未运行、无条目、不健康、版本未知。
 */

import { DiagReport } from './Settings';
import { SURFACE, tableStats } from 'dshcompat';
import type { TableStats } from 'dshcompat';

/** 尚未运行诊断时的报告（`generatedAt = 0` 表示「从未生成」） */
export function emptyDiagReport(): DiagReport {
  const stats: TableStats = tableStats();
  return {
    entries: [],
    healthy: false,
    generatedAt: 0,
    versionVerdict: 'unverified',
    versionMessage: '尚未运行诊断',
    versionAdvice: '点击「运行诊断」后会实际探测端点、认证、协议与 Host 信息。',
    tableStats: `${stats.endpoints} 个端点 / ${stats.streamEndpoints} 个流式 / ${stats.capabilities} 个能力`,
    // 接口面从载体常量派生：写死字符串会在上游改路径后继续展示旧路径，
    // 而「接口面」这一行正是用来判断「是不是漏注入/走错路由」的。
    surface: `${SURFACE.apiChannel} · ${SURFACE.muxPath} · ${SURFACE.eventsEndpoint}`
  };
}
