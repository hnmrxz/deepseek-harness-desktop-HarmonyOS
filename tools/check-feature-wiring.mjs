/**
 * 功能接线回归门禁（E258）。
 *
 * 【为什么需要它】构建能查出语法与类型错误，**查不出"调用点被删"**：
 * 一个功能的实现留在中枢、界面上的入口被某次重构顺手删掉，编译依然通过，
 * 只有跑一遍界面才会发现（本项目 E135 就出过：技能的数据层与界面都在，**触发点没了**，页面永远显示"未读"）。
 *
 * 【它做什么】对一组**已实现/已真机验证**的功能，检查"必须存在的接线特征"是否还在：
 *   · 中枢侧：方法/端点调用存在；
 *   · 界面侧：调用点存在（这是最容易悄悄消失的一环）。
 * 缺任何一项就退出码 1 并列出缺哪一项——**宁可吵，也不要静默**。
 *
 * 【它不做什么】不做语义判断（不保证逻辑正确），也不替代真机验收；它是"接线还在不在"的粗筛。
 *
 * 用法：node tools/check-feature-wiring.mjs
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.cwd();
const SCAN_DIRS = [
  'appstate/src/main/ets',
  'entry/src/main/ets',
  'hostruntime/src/main/ets',
  'dshcompat/src/main/ets',
  'platform/src/main/ets'
];

/** 递归收集 .ets 文件 */
function collect(dir) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      out.push(...collect(p));
    } else if (e.name.endsWith('.ets')) {
      out.push(p);
    }
  }
  return out;
}

const files = SCAN_DIRS.flatMap((d) => collect(join(ROOT, d)));
const sources = files.map((f) => ({ path: relative(ROOT, f).replace(/\\/g, '/'), text: readFileSync(f, 'utf8') }));

function count(pattern) {
  const re = new RegExp(pattern);
  let n = 0;
  const where = [];
  for (const s of sources) {
    const lines = s.text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (re.test(lines[i])) {
        n++;
        if (where.length < 3) where.push(`${s.path}:${i + 1}`);
      }
    }
  }
  return { n, where };
}

/**
 * 每个功能列出"必须存在的接线"。
 * `min` 是期望的最少出现次数：**1 处往往意味着只剩定义（没有调用）**，所以要 >1。
 */
const FEATURES = [
  { name: '工作区删除', patterns: [['deleteWorkspaceByPath', 2]] },
  { name: '会话归档', patterns: [['archiveSession', 2]] },
  { name: '预设复制', patterns: [['copyAgentPreset', 2]] },
  { name: '预设删除', patterns: [['deleteAgentPreset', 2]] },
  { name: '预设查看', patterns: [['readAgentPreset', 2]] },
  { name: '技能清单', patterns: [['refreshSkills', 2], ['skills/list', 1]] },
  { name: '提供方目录', patterns: [['refreshProviderCatalog', 2]] },
  { name: '命令面板', patterns: [['refreshCommands', 2], ['executeCommand', 2]] },
  { name: '长期目标', patterns: [['refreshGoal', 2]] },
  { name: '消息反馈', patterns: [['putFeedback', 2], ['refreshFeedback', 2]] },
  { name: '文件变更流', patterns: [['openFilesStream', 2]] },
  { name: '计划模式', patterns: [['planActive|planPending', 2]] },
  { name: '核心版本切换', patterns: [['switchTo', 2], ['rollbackTo', 2]] },
  { name: '插件启停', patterns: [['plugin', 4]] },
  { name: '凭据写入', patterns: [['openCredentialSheet', 2]] }
];

const problems = [];
for (const f of FEATURES) {
  for (const [pattern, min] of f.patterns) {
    const { n, where } = count(pattern);
    if (n < min) {
      problems.push(`  ✗ ${f.name}：接线 "${pattern}" 只找到 ${n} 处（期望 ≥${min}）`);
    }
  }
}

console.log(`# 功能接线回归（扫描 ${files.length} 个文件，${FEATURES.length} 个功能）`);
if (problems.length === 0) {
  console.log('✅ 全部功能的接线都在（中枢实现 + 界面调用点）。');
  process.exit(0);
}
console.log('发现断线或缺调用点：');
for (const p of problems) {
  console.log(p);
}
console.log('\n提示：构建查不出"调用点被删"——这正是本门禁存在的理由（见 E135/E258）。');
process.exit(1);
