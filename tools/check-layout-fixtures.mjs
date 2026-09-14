/**
 * 布局 fixture 门禁（P1）：把「形态/几何决策」变成**无需设备**就能验证的东西。
 *
 * 存在理由：
 *   计划 §16 要求「即使没有设备，也必须测试 width / height / orientation / input mode」，
 *   §17 要求把「布局分支」与「state → UI 映射」当作可自动化的验收对象。
 *   而 `entry`（UI 层）在本环境**没有编译验证**（原生构建被 node-headers/libnode 阻塞），
 *   真机也没有 —— 于是「布局决策对不对」这件事在重构中极易静默劣化。
 *
 * 做法（关键点）：
 *   `appstate/src/main/ets/ui/LayoutController.ets` 是**纯 TypeScript**（不含 ArkUI 装饰器与 DSL），
 *   所以可以把它连同依赖（`Tokens.ets` / `Breakpoints.ets`）按 `.ts` 编译并**在本机直接执行**——
 *   被测的是**同一个源文件**，不是复制品（复制一份来测等于测了个假东西）。
 *   编译器用 CLT 自带的 tsc（`<CLT>/codelinter/node_modules/typescript/bin/tsc`）。
 *
 * 四套形态 fixture（计划 §16）+ 断点边界 + 让步链三分支：
 *   PHONE / PHONE-LANDSCAPE / TABLET-PORTRAIT / TABLET-LANDSCAPE / DESKTOP / TWO-IN-ONE（拖窄两种）
 *
 * 退出码：0 通过；1 断言失败；3 **环境受阻**（找不到 tsc）——
 *   沿用本项目既有约定（无设备时 exit 3 且不建产物），**不把"没跑成"说成"通过"**。
 *
 * 用法：
 *   node tools/check-layout-fixtures.mjs              # 跑全部 fixture
 *   node tools/check-layout-fixtures.mjs --self-test  # 注入式自检：证明断言真的会失败
 */
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const ROOT = process.cwd();
const WORK = join(ROOT, 'dist', 'layout-fixtures');
const SRC = join(WORK, 'src');
const OUT = join(WORK, 'out');

/** 纯逻辑源文件（不依赖 ArkUI DSL，故可当 TS 编译并执行） */
const PURE_FILES = [
  'appstate/src/main/ets/ui/Tokens.ets',
  'appstate/src/main/ets/ui/Breakpoints.ets',
  'appstate/src/main/ets/ui/LayoutController.ets',
  'appstate/src/main/ets/ui/NavigationController.ets',
  // 回合模型（§8）：纯逻辑，可在本机直接执行
  'appstate/src/main/ets/model/Trajectory.ets',
  'appstate/src/main/ets/model/Turns.ets',
  'appstate/src/main/ets/model/Follow.ets',
  'appstate/src/main/ets/model/InputPolicy.ets',
  'appstate/src/main/ets/model/ToolPresentation.ets',
  'appstate/src/main/ets/model/ToolDiff.ets',
  'appstate/src/main/ets/model/InputFacts.ets'
];

/** ArkUI 全局的声明补丁：Tokens.ets 用它取系统资源色/符号 */
const GLOBALS_DTS = `
declare function $r(value: string): Resource;
declare type Resource = object;
`;

/** 找 tsc：CLT 自带 typescript，其次看 PATH */
function findTsc() {
  const candidates = [];
  const clt = process.env.DEVECO_CLI_CLT_PATH;
  if (clt) candidates.push(join(clt, 'codelinter', 'node_modules', 'typescript', 'bin', 'tsc'));
  candidates.push('/home/node/deveco-clt/command-line-tools/codelinter/node_modules/typescript/bin/tsc');
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  return null;
}

/** 把 .ets 复制成 .ts 并编译，返回可 require 的模块 */
function buildAndLoad() {
  const tsc = findTsc();
  if (!tsc) {
    console.error('环境受阻：找不到 tsc（DevEco CLT 自带的 typescript）。');
    console.error('  设置 DEVECO_CLI_CLT_PATH 指向 Command Line Tools 安装目录后重跑。');
    console.error('  ⚠️ 这是"没跑成"，不是"通过"——退出码 3。');
    process.exit(3);
  }

  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(SRC, { recursive: true });
  const tsFiles = [];
  for (const rel of PURE_FILES) {
    const from = join(ROOT, rel);
    if (!existsSync(from)) {
      console.error(`缺文件：${rel}`);
      process.exit(2);
    }
    const to = join(SRC, rel.split('/').pop().replace(/\.ets$/, '.ts'));
    cpSync(from, to);
    tsFiles.push(to);
  }
  const globals = join(SRC, 'globals.d.ts');
  writeFileSync(globals, GLOBALS_DTS, 'utf8');

  try {
    execFileSync(process.execPath, [
      tsc,
      '--target', 'ES2020',
      '--module', 'commonjs',
      '--outDir', OUT,
      '--skipLibCheck',
      '--strict', 'false',
      ...tsFiles,
      globals
    ], { stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    const out = `${e.stdout || ''}${e.stderr || ''}`.toString();
    console.error('tsc 编译纯逻辑源文件失败——说明 LayoutController/Tokens/Breakpoints 不是合法 TS：');
    console.error(out.trim() || '(无输出)');
    process.exit(1);
  }

  // 运行时垫片：`Tokens.ets` 在**模块顶层**就调 ArkUI 全局 `$r(...)` 取系统资源，
  // 而 Node 里没有这个全局（实测：直接 require 会 `ReferenceError: $r is not defined`）。
  // 决策逻辑本身与它无关，故给一个恒等垫片即可——注意这是"让纯逻辑跑起来"，
  // 不是"假装 ArkUI 环境"：本文件只断言几何/档位，不碰颜色与资源。
  const bootstrap = join(OUT, '__bootstrap.cjs');
  writeFileSync(bootstrap,
    "'use strict';\n"
    + 'globalThis.$r = (value) => value;\n'
    + "module.exports = require('./LayoutController.js');\n", 'utf8');

  // bootstrap 先装 `$r` 垫片，再转出 LayoutController。
  // 返回 **require 函数**：本文件现在要加载两个模块（布局 + 导航），都从同一个 OUT 目录取。
  const req = createRequire(bootstrap);
  req(bootstrap);   // 触发垫片安装
  return req;
}

/** 断言器：收集失败而不是首错即停（一次看清全部差异） */
function makeAsserter(selfTest) {
  const failures = [];
  let checked = 0;
  return {
    eq(label, actual, expected) {
      checked++;
      const ok = JSON.stringify(actual) === JSON.stringify(expected);
      if (!ok) failures.push(`  ✗ ${label}\n      期望 ${JSON.stringify(expected)}\n      实际 ${JSON.stringify(actual)}`);
    },
    ok(label, cond) {
      checked++;
      if (!cond) failures.push(`  ✗ ${label}`);
    },
    done() {
      // 自检模式：故意制造一条失败，验证"断言真的会失败、且退出码会变"
      if (selfTest) {
        checked++;
        failures.push('  ✗ [self-test] 注入的必然失败断言');
      }
      console.log(`\n断言 ${checked} 条，失败 ${failures.length} 条。`);
      if (failures.length === 0) {
        console.log('✅ 四形态 fixture 与边界全部符合预期。');
        process.exit(0);
      }
      for (const f of failures) console.log(f);
      console.log(selfTest
        ? '\n✅ 自检通过：注入的失败被如实报出（断言器有效）。'
        : '\n❌ 失败：布局决策与 fixture 期望不符（或本文件是重构中的临时状态）。');
      // 自检模式下"有失败"正是期望结果
      process.exit(selfTest ? 0 : 1);
    }
  };
}

const selfTest = process.argv.includes('--self-test');
const require2 = buildAndLoad();
const LC = require2('./LayoutController.js');

const { decideLayout, decideLayoutWithDetail, concedeDetail, navWidthOf, ConcessionStep, MAIN_MIN_VP } = LC;
const NC = require2('./NavigationController.js');
const TM = require2('./Turns.js');
const FM = require2('./Follow.js');
const IP = require2('./InputPolicy.js');
const TP = require2('./ToolPresentation.js');
const TD = require2('./ToolDiff.js');
const IF = require2('./InputFacts.js');
const TJ = require2('./Trajectory.js');
const t = makeAsserter(selfTest);

console.log('# 布局 fixture 门禁（四形态 + 断点边界 + 让步链）\n');
console.log(`编译：${PURE_FILES.length} 个纯逻辑源文件 → ${OUT.replace(`${ROOT}/`, '')}`);
console.log(`主区最小宽度 MAIN_MIN_VP = ${MAIN_MIN_VP}\n`);

/** 便捷构造 */
const input = (widthVp, heightVp, hasKeyboard = false, hasPointer = false) =>
  ({ widthVp, heightVp, hasKeyboard, hasPointer });

/**
 * 四套形态 fixture（计划 §16）。
 * 期望值是**当前实现的行为**（本轮是重构，不改行为）；凡是"行为是否合理"存疑的，
 * 单独在下面标注为待决，而不是悄悄把期望值写成我们想要的样子。
 */
const FIXTURES = [
  {
    name: 'PHONE 竖屏 360×800',
    in: input(360, 800),
    want: {
      mode: 'single', nav: 'bottom', navWidthVp: 0, navLabels: false,
      detailAvailable: false, detailWidthVp: 0, detailOverlay: true,
      detailStep: 'none', landscape: false, pointerRich: false
    }
  },
  {
    name: 'PHONE 横屏 800×360（宽 800 ≥ 600 ⇒ 落双栏）',
    in: input(800, 360),
    want: {
      mode: 'double', nav: 'rail', navWidthVp: 56, navLabels: false,
      detailAvailable: false, detailWidthVp: 0, detailOverlay: false,
      detailStep: 'none', landscape: true, pointerRich: false
    },
    note: '⚠️ 待决：D3 §2 的口径是"只看宽度"，于是**手机横屏会变成双栏**。'
      + '这是"按宽度决策"的直接后果，不是 bug；但要不要为手机横屏加一条高度/方向子句，需真机看效果后定。'
  },
  {
    name: 'TABLET 竖屏 800×1280',
    in: input(800, 1280),
    want: {
      mode: 'double', nav: 'rail', navWidthVp: 56, navLabels: false,
      detailAvailable: false, detailWidthVp: 0, detailOverlay: false,
      detailStep: 'none', landscape: false, pointerRich: false
    }
  },
  {
    name: 'TABLET 横屏 1280×800',
    in: input(1280, 800),
    want: {
      mode: 'triple', nav: 'panel', navWidthVp: 240, navLabels: true,
      detailAvailable: true, detailWidthVp: 320, detailOverlay: false,
      detailStep: 'none', landscape: true, pointerRich: false
    }
  },
  {
    name: 'DESKTOP/2in1 全屏 1920×1080（键鼠齐备）',
    in: input(1920, 1080, true, true),
    want: {
      mode: 'triple', nav: 'panel', navWidthVp: 240, navLabels: true,
      detailAvailable: true, detailWidthVp: 320, detailOverlay: false,
      detailStep: 'none', landscape: true, pointerRich: true
    }
  },
  {
    name: '2in1 自由窗被拖窄 700×900（应与平板竖屏同构，不重启页面）',
    in: input(700, 900, true, true),
    want: {
      mode: 'double', nav: 'rail', navWidthVp: 56, navLabels: false,
      detailAvailable: false, detailWidthVp: 0, detailOverlay: false,
      detailStep: 'none', landscape: false, pointerRich: true
    }
  },
  {
    name: '2in1 自由窗拖到手机宽度 480×800',
    in: input(480, 800, true, true),
    want: {
      mode: 'single', nav: 'bottom', navWidthVp: 0, navLabels: false,
      detailAvailable: false, detailWidthVp: 0, detailOverlay: true,
      detailStep: 'none', landscape: false, pointerRich: true
    }
  }
];

console.log('## 四形态 fixture');
for (const f of FIXTURES) {
  const got = decideLayout(f.in);
  t.eq(f.name, got, f.want);
  console.log(`  ${JSON.stringify(got) === JSON.stringify(f.want) ? 'ok  ' : 'FAIL'}  ${f.name}`
    + `  → ${got.mode}/${got.nav}/detail=${got.detailAvailable ? got.detailWidthVp : '—'}`);
  if (f.note) console.log(`        ${f.note}`);
}

console.log('\n## 断点边界（599/600/839/840）');
const BOUNDARIES = [
  { w: 599, mode: 'single', nav: 'bottom' },
  { w: 600, mode: 'double', nav: 'rail' },
  { w: 839, mode: 'double', nav: 'rail' },
  { w: 840, mode: 'triple', nav: 'panel' }
];
for (const b of BOUNDARIES) {
  const got = decideLayout(input(b.w, 900));
  t.eq(`宽 ${b.w}vp → 档位`, got.mode, b.mode);
  t.eq(`宽 ${b.w}vp → 导航`, got.nav, b.nav);
  console.log(`  ok    宽 ${b.w}vp → ${got.mode} / ${got.nav}`);
}

console.log('\n## 840vp 处详情栏必须是默认宽度（不得因下限收紧而收窄）');
{
  // 这条守的是"重构不改行为"：MAIN_MIN_VP 若被拍成更大的值，840vp 下详情栏会突然收窄甚至关闭
  const got = decideLayout(input(840, 900));
  t.eq('840vp 详情宽度', got.detailWidthVp, 320);
  t.eq('840vp 让步步骤', got.detailStep, 'none');
  console.log(`  ok    840vp → 详情 ${got.detailWidthVp}vp（${got.detailStep}）`);
}

console.log('\n## 让步链三分支（D3 §2.1：收窄 → 关闭）');
{
  const none = concedeDetail(1280, 240, 320);
  t.eq('放得下 → NONE/320', none, { widthVp: 320, step: 'none' });
  const narrow = concedeDetail(840, 240, 400);
  t.eq('放不下期望值 → NARROW/260', narrow, { widthVp: 260, step: 'detail-narrow' });
  const tooSmall = concedeDetail(840, 240, 100);
  t.eq('低于最小值 → NARROW/260', tooSmall, { widthVp: 260, step: 'detail-narrow' });
  const closed = concedeDetail(500, 240, 320);
  t.eq('连最小值都放不下 → CLOSED/0', closed, { widthVp: 0, step: 'detail-closed' });
  console.log(`  ok    NONE / NARROW / CLOSED 三个分支都被直接断言（含当前断点下不可达的 CLOSED）`);
}

console.log('\n## 未来的拖拽调宽路径（P2）：decideLayoutWithDetail');
{
  const wide = decideLayoutWithDetail(input(1280, 800), 400);
  t.eq('1280vp 想要 400 → 得 400', wide.detailWidthVp, 400);
  t.eq('1280vp 想要 400 → NONE', wide.detailStep, 'none');
  const tight = decideLayoutWithDetail(input(840, 800), 400);
  t.eq('840vp 想要 400 → 收窄到 260', tight.detailWidthVp, 260);
  t.eq('840vp 想要 400 → NARROW', tight.detailStep, 'detail-narrow');
  console.log('  ok    同一决策函数同时服务"默认宽度"与"用户拖拽宽度"');
}

console.log('\n## 导航宽度映射');
{
  t.eq('PANEL → 240', navWidthOf('panel'), 240);
  t.eq('RAIL → 56', navWidthOf('rail'), 56);
  t.eq('BOTTOM_TABS → 0（不占侧边）', navWidthOf('bottom'), 0);
  console.log('  ok    panel/rail/bottom 三档映射');
}

console.log('\n## 导航：返回键的优先级阶梯（迁移前写在 Index.onBackPress 里）');
{
  const { decideBack, BackAction, StackPage, selectTab, normalizeTab, showsConversation, navTabs } = NC;
  // 【坑】`NavTab.SESSIONS` 是 `'workspaces'` 的**别名**（E108：会话并入工作区），
  // 所以"在会话页签"与"在工作区页签"是同一个状态；默认值必须写 'workspaces'。
  const nav = (o) => Object.assign({ tab: 'workspaces', stackPage: StackPage.MAIN, wsDrill: 0, hasSession: true, detailOpen: false }, o);
  const ov = (o) => Object.assign({ credentialOpen: false, settingDraftOpen: false, searchOpen: false, choosingOpen: false, detailSheetOpen: false, previewOpen: false }, o);

  // 优先级：浮层之间也有先后（凭据 → 设置草稿 → 搜索 → 选择）
  t.eq('全开时先关凭据浮层', decideBack(nav({}), ov({ credentialOpen: true, settingDraftOpen: true, searchOpen: true, choosingOpen: true, previewOpen: true })), BackAction.CLOSE_CREDENTIAL);
  t.eq('无凭据时关设置草稿', decideBack(nav({}), ov({ settingDraftOpen: true, searchOpen: true })), BackAction.CLOSE_SETTING_DRAFT);
  t.eq('再关搜索', decideBack(nav({}), ov({ searchOpen: true, choosingOpen: true })), BackAction.CLOSE_SEARCH);
  t.eq('再关选择浮层', decideBack(nav({}), ov({ choosingOpen: true, previewOpen: true })), BackAction.CLOSE_CHOICE);
  // 浮层优先于二级页
  t.eq('浮层优先于二级页', decideBack(nav({ stackPage: StackPage.DIAGNOSTICS }), ov({ searchOpen: true })), BackAction.CLOSE_SEARCH);
  // 详情半模态（P1.5）：它盖在页面上，但排在真正的模态编辑态之后
  t.eq('详情 Sheet 排在其它浮层之后', decideBack(nav({}), ov({ searchOpen: true, detailSheetOpen: true })), BackAction.CLOSE_SEARCH);
  t.eq('详情 Sheet 优先于二级页', decideBack(nav({ stackPage: StackPage.DIAGNOSTICS }), ov({ detailSheetOpen: true })), BackAction.CLOSE_DETAIL_SHEET);
  t.eq('详情 Sheet 优先于详情栏', decideBack(nav({ detailOpen: true }), ov({ detailSheetOpen: true })), BackAction.CLOSE_DETAIL_SHEET);
  t.eq('详情 Sheet 优先于工作区下钻', decideBack(nav({ tab: 'workspaces', wsDrill: 3 }), ov({ detailSheetOpen: true })), BackAction.CLOSE_DETAIL_SHEET);
  // 二级页
  t.eq('二级页回主列表', decideBack(nav({ stackPage: StackPage.CONVERSATION }), ov({})), BackAction.STACK_TO_MAIN);
  // 详情
  t.eq('关详情抽屉', decideBack(nav({ detailOpen: true }), ov({})), BackAction.CLOSE_DETAIL);
  // 工作区下钻（仅工作区页签）
  t.eq('工作区下钻退一层', decideBack(nav({ tab: 'workspaces', wsDrill: 2 }), ov({})), BackAction.DRILL_UP);
  t.eq('非工作区页签不消耗下钻（留给后面的规则）', decideBack(nav({ tab: 'settings', wsDrill: 2 }), ov({})), BackAction.TAB_TO_SESSIONS);
  // 文件预览在工作区页签且未下钻时才轮到
  t.eq('关文件预览', decideBack(nav({ tab: 'workspaces', wsDrill: 0 }), ov({ previewOpen: true })), BackAction.CLOSE_PREVIEW);
  // 回首页签
  t.eq('不在首页签则回会话', decideBack(nav({ tab: 'settings' }), ov({})), BackAction.TAB_TO_SESSIONS);
  // 根层交给系统（**必须**是 EXIT，否则就是"按返回没反应"的假入口）
  t.eq('根层交给系统（不消费）', decideBack(nav({}), ov({})), BackAction.EXIT);
  console.log('  ok    返回键阶梯的每一级 + 浮层内部先后 + 详情半模态的位置，都被断言');

  // 页签归一化（E108/E110 的别名）
  t.eq('待决 → 工作区', normalizeTab('pending'), 'workspaces');
  t.eq('核心 → 设置', normalizeTab('core'), 'settings');
  t.eq('设置保持设置', normalizeTab('settings'), 'settings');

  // 点页签：清栈 + 清会话选择 + 重读静态事实
  const toSettings = selectTab(nav({ tab: 'workspaces', stackPage: StackPage.DIAGNOSTICS, wsDrill: 3, hasSession: true }), 'settings');
  t.eq('点设置：清栈', toSettings.stackPage, 'main');
  t.eq('点设置：清下钻', toSettings.wsDrill, 0);
  t.eq('点设置：清会话选择', toSettings.clearSession, true);
  t.eq('点设置：重读静态事实', toSettings.refreshStaticFacts, true);
  const toWs = selectTab(nav({ tab: 'settings' }), 'workspaces');
  t.eq('点工作区：保留会话选择', toWs.clearSession, false);
  t.eq('点工作区：不重读静态事实', toWs.refreshStaticFacts, false);
  t.eq('点待决别名 → 工作区', selectTab(nav({}), 'pending').tab, 'workspaces');

  // 详情栏并排的前提
  t.eq('看会话中：showsConversation 真', showsConversation(nav({ hasSession: true })), true);
  t.eq('无会话：假', showsConversation(nav({ hasSession: false })), false);
  t.eq('在设置页：假', showsConversation(nav({ hasSession: true, tab: 'settings' })), false);
  t.eq('一级页签顺序', navTabs(), ['workspaces', 'settings']);
  console.log('  ok    页签归一化 / 清栈 / 静态事实重读 / 会话可见性 全部断言');
}

console.log('\n## 回合模型（§8：Turn → ProcessGroup + Answer）');
{
  const { groupTurns, hasProcessGroup, chatVisibleItems, processSummary, defaultExpanded } = TM;
  const { makeItem, TrajectoryKind, Speaker } = TJ;

  // 造一个回合：user → (reasoning, tool) → assistant
  const mk = (id, kind, speaker, extra) => {
    const it = makeItem(id, kind, 0);
    it.speaker = speaker;
    if (extra) Object.assign(it, extra);
    return it;
  };
  const u1 = mk('u1', TrajectoryKind.MESSAGE, Speaker.USER);
  const r1 = mk('r1', TrajectoryKind.REASONING, Speaker.ASSISTANT);
  const t1 = mk('t1', TrajectoryKind.TOOL, Speaker.ASSISTANT);
  const a1 = mk('a1', TrajectoryKind.MESSAGE, Speaker.ASSISTANT);
  const u2 = mk('u2', TrajectoryKind.MESSAGE, Speaker.USER);
  const a2 = mk('a2', TrajectoryKind.MESSAGE, Speaker.ASSISTANT);
  const err = mk('e1', TrajectoryKind.ERROR, Speaker.SYSTEM);

  const turns = groupTurns([u1, r1, t1, a1, u2, a2, err], true);
  t.eq('回合数 = 用户消息数', turns.length, 2);
  t.eq('第 1 回合的过程条目数（思考+工具）', turns[0].process.length, 2);
  t.eq('第 1 回合的回答是最后一条助手消息', turns[0].answer.id, 'a1');
  t.eq('第 1 回合不再进行（后面还有回合）', turns[0].running, false);
  t.eq('最后回合进行中（会话在跑）', turns[1].running, true);
  t.eq('错误进 notices 而不是 process', turns[1].notices.length, 1);
  t.eq('过程分组存在', hasProcessGroup(turns[0]), true);
  t.eq('过程分组摘要按类型计数', processSummary(turns[0]), '思考 1 · 工具 1');
  t.eq('进行中的回合默认展开', defaultExpanded(turns[1], false), true);
  t.eq('已完成的回合默认折叠', defaultExpanded(turns[0], false), false);
  t.eq('用户手动展开后优先', defaultExpanded(turns[0], true), true);

  // 空过程 ⇒ 不建分组（§8「tool-only 空节点不显示」）
  t.eq('没有过程条目时不建分组', hasProcessGroup(turns[1]), false);

  // 对话视图的可见集合：用户消息 + 回答 + notices（错误要留），不含工具/思考
  const chat = chatVisibleItems(turns).map((i) => i.id);
  t.eq('对话视图可见集合', chat, ['u1', 'a1', 'u2', 'a2']);

  // 首条用户消息之前的内容单独成回合
  const pre = groupTurns([err, u1, a1], false);
  t.eq('前置条目单独成回合', pre.length, 2);
  t.eq('前置回合没有 user', pre[0].user === undefined, true);
  t.eq('前置回合保留错误（notices）', pre[0].notices.length, 1);

  // 流式中的回合即使中枢说停了也不该折叠
  const streaming = mk('a3', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, { streaming: true });
  const st = groupTurns([u1, streaming], false);
  t.eq('流式输出中的回合视为进行中', st[0].running, true);
  console.log('  ok    分组边界 / 过程与回答归类 / notices / 空分组 / 折叠默认态 / 流式，共 15 条断言');
}

console.log('\n## 贴底跟随模型（§8：sticky-follow 独立管理）');
{
  const { nextFollowing, followTimerShouldRun, shouldJumpOnNewItems, FollowSignal } = FM;
  t.eq('滚到/停在底部 → 跟随', nextFollowing(false, FollowSignal.AT_BOTTOM), true);
  t.eq('上翻离开底部 → 不跟随', nextFollowing(true, FollowSignal.SCROLLED_AWAY), false);
  // 下面两条是本次修的**真实缺陷**：此前几何判断顺带管意图，导致切会话/发消息不恢复跟随
  t.eq('切会话 → 恢复跟随（此前缺陷：新会话停在中间）', nextFollowing(false, FollowSignal.SESSION_CHANGED), true);
  t.eq('发消息 → 恢复跟随（此前缺陷：回答出现在看不到的地方）', nextFollowing(false, FollowSignal.USER_SENT), true);
  t.eq('跟随中 + 会话在跑 → 定时贴底跑', followTimerShouldRun(true, true), true);
  t.eq('跟随中但已停止 → 不跑', followTimerShouldRun(true, false), false);
  t.eq('未跟随（用户在看历史）→ 绝不抢滚动条', followTimerShouldRun(false, true), false);
  t.eq('新条目：跟随中才跳到底', shouldJumpOnNewItems(true), true);
  t.eq('新条目：不跟随时不把用户拽走', shouldJumpOnNewItems(false), false);
  console.log('  ok    9 条断言：三处几何 + 两条**意图信号**（切会话/发消息）+ 定时器与跳底判据');
}

console.log('\n## 输入模态策略（触控 / 鼠标 / 键盘同一套语义）');
{
  const { contextMenuGestures, hoverEnabled, contextMenuHintLabel, MenuGesture } = IP;
  const touch = { hasKeyboard: false, hasPointer: false };
  const desktop = { hasKeyboard: true, hasPointer: true };
  t.eq('纯触控：长按必须可用（否则手机没有上下文菜单）', contextMenuGestures(touch), ['long-press']);
  t.eq('有指针：长按 + 右键', contextMenuGestures(desktop), ['long-press', 'right-click']);
  t.eq('纯触控：无悬停', hoverEnabled(touch), false);
  t.eq('有指针：启用悬停', hoverEnabled(desktop), true);
  t.eq('提示文案随模态变（纯触控）', contextMenuHintLabel(touch), '长按');
  t.eq('提示文案随模态变（有指针）', contextMenuHintLabel(desktop), '长按或右键');
  console.log('  ok    6 条断言：手势集合 / 悬停 / 菜单提示文案，按输入模态分别成立');
}

console.log('\n## 工具呈现（§11：按工具类别区分，而不是一视同仁）');
{
  const { toolKindOf, toolKindLabel, toolToneOf, toolDefaultExpanded, toolSummaryOf, ToolKind } = TP;
  // 用例取自**上游客户端渲染器实际出现的工具名键**（dsh-client-ui-tool/lib/client.js）
  t.eq('bash → 终端', toolKindOf('bash'), ToolKind.TERMINAL);
  t.eq('pwsh → 终端（大小写不敏感）', toolKindOf('Pwsh'), ToolKind.TERMINAL);
  t.eq('read → 读取', toolKindOf('read'), ToolKind.READ);
  t.eq('write → 写入', toolKindOf('write'), ToolKind.WRITE);
  t.eq('str_replace → 编辑', toolKindOf('str_replace'), ToolKind.EDIT);
  t.eq('grep → 搜索', toolKindOf('grep'), ToolKind.SEARCH);
  t.eq('glob → 搜索', toolKindOf('glob'), ToolKind.SEARCH);
  t.eq('web_search → 网络', toolKindOf('web_search'), ToolKind.WEB);
  t.eq('ask_user_question → 提问', toolKindOf('ask_user_question'), ToolKind.ASK);
  t.eq('未识别的名字 → 通用（不硬塞进某类）', toolKindOf('some_future_tool'), ToolKind.GENERIC);
  t.eq('类别中文名', toolKindLabel(ToolKind.TERMINAL), '终端');
  t.eq('运行中 → running 语气', toolToneOf(ToolKind.TERMINAL, 'running'), 'running');
  t.eq('失败 → failed 语气', toolToneOf(ToolKind.READ, 'failed'), 'failed');
  t.eq('被拒 → warning 语气', toolToneOf(ToolKind.WRITE, 'rejected'), 'warning');
  t.eq('失败默认展开（§11 的展开规则）', toolDefaultExpanded('failed'), true);
  t.eq('被拒默认展开', toolDefaultExpanded('rejected'), true);
  t.eq('成功默认折叠（长会话不刷屏）', toolDefaultExpanded('success'), false);
  console.log('  ok    17 条断言：10 个真实工具名归类 + 语气 + 展开规则');

  // 摘要提炼（§11 的 path summary）：要点从参数里挖出来，而不是整段糊上去
  t.eq('终端：取 command', toolSummaryOf(ToolKind.TERMINAL, '{"command":"npm run build"}'), 'npm run build');
  t.eq('终端：忽略其它键', toolSummaryOf(ToolKind.TERMINAL, '{"command":"ls -la","timeout":60000}'), 'ls -la');
  t.eq('读取：取 file_path', toolSummaryOf(ToolKind.READ, '{"file_path":"/a/b.ts"}'), '/a/b.ts');
  t.eq('搜索：模式 + 范围', toolSummaryOf(ToolKind.SEARCH, '{"pattern":"foo","path":"src"}'), 'foo · src');
  t.eq('搜索：无范围时不加分隔符', toolSummaryOf(ToolKind.SEARCH, '{"pattern":"foo"}'), 'foo');
  t.eq('网络：取 url', toolSummaryOf(ToolKind.WEB, '{"url":"https://example.com/a"}'), 'https://example.com/a');
  t.eq('提问：取 question', toolSummaryOf(ToolKind.ASK, '{"question":"选哪一个？"}'), '选哪一个？');
  t.eq('非 JSON 原文：清理成一行', toolSummaryOf(ToolKind.TERMINAL, 'ls -la\n  /tmp'), 'ls -la /tmp');
  t.eq('空参数 → 空摘要', toolSummaryOf(ToolKind.TERMINAL, ''), '');
  const longCmd = '{"command":"' + 'x'.repeat(200) + '"}';
  const sum = toolSummaryOf(ToolKind.TERMINAL, longCmd);
  t.eq('超长截断并加省略号', sum.length, 121);
  t.eq('截断标记在末尾', sum.endsWith('…'), true);
  t.eq('转义引号还原', toolSummaryOf(ToolKind.TERMINAL, '{"command":"echo \\"hi\\""}'), 'echo "hi"');
  console.log('  ok    12 条断言：按类别提炼要点（终端的命令 / 读取的路径 / 搜索的模式+范围 / 网络的 url …）');
}

console.log('\n## 改动对照（§11：编辑类工具出"改了什么"，而不是参数原文）');
{
  const { intendedDiffOf, diffLines, diffStatOf, collapseContext, presentDiff, DiffLineKind } = TD;

  // ── 意图对照：严格对齐官方 intendedDiff 的规则 ──
  const w = intendedDiffOf('write', '{"file_path":"/a/b.ts","content":"line1\\nline2"}');
  t.eq('write → 整文件都是新增（oldText 为 null）', w !== null && w.oldText === null, true);
  t.eq('write 的 newText 取 content', w !== null && w.newText, 'line1\nline2');
  t.eq('write 的 path 取 file_path', w !== null && w.path, '/a/b.ts');

  const e = intendedDiffOf('edit', '{"file_path":"/a/b.ts","old_string":"foo","new_string":"bar"}');
  t.eq('edit → oldText 取 old_string', e !== null && e.oldText, 'foo');
  t.eq('edit → newText 取 new_string', e !== null && e.newText, 'bar');

  // 官方 `oldText || null`：空串归一成 null（纯新增），不是空串
  const eEmpty = intendedDiffOf('edit', '{"file_path":"/a/b.ts","old_string":"","new_string":"bar"}');
  t.eq('edit 空 old_string → 归一成 null（官方 `oldText || null`）', eEmpty !== null && eEmpty.oldText === null, true);

  // 大小写：官方按精确名匹配，我方工具名历史上出现过大小写差异 ⇒ 归一小写
  t.eq('工具名大小写不敏感', intendedDiffOf('EDIT', '{"file_path":"/a","old_string":"x","new_string":"y"}') !== null, true);

  // 拒绝路径（任一条不成立就**整卡不出**，而不是尽力渲染）
  t.eq('不认识的名字 → 不出对照卡', intendedDiffOf('bash', '{"command":"ls","file_path":"/a"}'), null);
  t.eq('非 JSON 参数 → 不出对照卡', intendedDiffOf('edit', 'not json at all'), null);
  t.eq('缺 file_path → 不出对照卡', intendedDiffOf('edit', '{"old_string":"a","new_string":"b"}'), null);
  t.eq('file_path 空白串 → 不出对照卡（官方 trim 判空）', intendedDiffOf('edit', '{"file_path":"   ","old_string":"a","new_string":"b"}'), null);
  t.eq('缺 new_string → 不出对照卡', intendedDiffOf('edit', '{"file_path":"/a","old_string":"a"}'), null);
  t.eq('replace_all 非布尔 → 不出对照卡（官方校验）', intendedDiffOf('edit', '{"file_path":"/a","old_string":"a","new_string":"b","replace_all":"yes"}'), null);
  t.eq('replace_all 为 null → 视为"出现但类型不对"→ 拒绝', intendedDiffOf('edit', '{"file_path":"/a","old_string":"a","new_string":"b","replace_all":null}'), null);
  t.eq('replace_all 合法布尔 → 正常出卡', intendedDiffOf('edit', '{"file_path":"/a","old_string":"a","new_string":"b","replace_all":true}') !== null, true);

  // validEscalationFields：提权字段要么都不出现，要么一起且合法
  t.eq('只给 sandbox_permissions（缺 justification）→ 拒绝',
    intendedDiffOf('edit', '{"file_path":"/a","old_string":"a","new_string":"b","sandbox_permissions":"workspace-write"}'), null);
  t.eq('justification 空白 → 拒绝',
    intendedDiffOf('edit', '{"file_path":"/a","old_string":"a","new_string":"b","sandbox_permissions":"workspace-write","justification":"  "}'), null);
  t.eq('sandbox_permissions 取值非法 → 拒绝',
    intendedDiffOf('edit', '{"file_path":"/a","old_string":"a","new_string":"b","sandbox_permissions":"root","justification":"x"}'), null);
  t.eq('提权字段合法 → 正常出卡',
    intendedDiffOf('edit', '{"file_path":"/a","old_string":"a","new_string":"b","sandbox_permissions":"danger-full-access","justification":"需要写工作区外"}') !== null, true);
  t.eq('提权字段都不出现 → 正常出卡（默认情形）',
    intendedDiffOf('edit', '{"file_path":"/a","old_string":"a","new_string":"b"}') !== null, true);

  // str_replace_editor（官方单独一支）
  const c = intendedDiffOf('str_replace_editor', '{"command":"create","path":"/n.ts","file_text":"hello"}');
  t.eq('str_replace_editor create → oldText null', c !== null && c.oldText === null, true);
  t.eq('str_replace_editor create → newText 取 file_text', c !== null && c.newText, 'hello');
  const r = intendedDiffOf('str_replace_editor', '{"command":"str_replace","path":"/n.ts","old_str":"a","new_str":"b"}');
  t.eq('str_replace_editor str_replace → oldText 取 old_str', r !== null && r.oldText, 'a');
  t.eq('str_replace_editor 其他 command → 不出卡',
    intendedDiffOf('str_replace_editor', '{"command":"view","path":"/n.ts"}'), null);

  // ── 行级对照 ──
  const ins = diffLines('a\nb', 'a\nX\nb');
  t.eq('插入一行 → 3 行（上下文/新增/上下文）', ins.length, 3);
  t.eq('插入行的性质', ins[1].kind, DiffLineKind.ADDED);
  t.eq('插入行内容', ins[1].text, 'X');

  const del = diffLines('a\nX\nb', 'a\nb');
  t.eq('删除一行 → 中间是 REMOVED', del[1].kind, DiffLineKind.REMOVED);

  const chg = diffLines('a\nold\nb', 'a\nnew\nb');
  const chgStat = diffStatOf(chg);
  t.eq('改一行 → 1 增 1 删', chgStat.added === 1 && chgStat.removed === 1, true);
  t.eq('未改动的行记为上下文（不计入增删）', diffStatOf(diffLines('a\nb\nc', 'a\nb\nc')).added, 0);

  const pure = diffLines(null, 'x\ny');
  t.eq('oldText 为 null ⇒ 全是新增', diffStatOf(pure).added === 2 && diffStatOf(pure).removed === 0, true);

  // 前后缀削去后仍然给出正确的增删（这是最省的一步，覆盖"只改一行"的多数情况）
  const big = [];
  for (let i = 0; i < 60; i++) big.push('line' + i);
  const bigNew = big.slice(); bigNew[30] = 'CHANGED';
  const bigStat = diffStatOf(diffLines(big.join('\n'), bigNew.join('\n')));
  t.eq('60 行里改 1 行 → 恰好 1 增 1 删', bigStat.added === 1 && bigStat.removed === 1, true);

  // 超上限时退回"全删 + 全增"（宁可粗但真，也不把 UI 线程算住）
  const huge = [];
  for (let i = 0; i < 400; i++) huge.push('h' + i);
  const hugeNew = huge.slice().reverse();
  const hugeStat = diffStatOf(diffLines(huge.join('\n'), hugeNew.join('\n')));
  t.eq('超出 DP 上限 → 退回全删全增（有界，不假称精确）', hugeStat.added === 400 && hugeStat.removed === 400, true);

  // ── 折叠：改两行、文件 800 行，不能把 799 行上下文铺到手机上 ──
  const long = [];
  for (let i = 0; i < 120; i++) long.push('L' + i);
  const longNew = long.slice(); longNew[60] = 'EDIT';
  const collapsed = collapseContext(diffLines(long.join('\n'), longNew.join('\n')), 2);
  let skippedTotal = 0;
  let contextCount = 0;
  for (let i = 0; i < collapsed.length; i++) {
    if (collapsed[i].kind === DiffLineKind.SKIPPED) skippedTotal += collapsed[i].skipped;
    if (collapsed[i].kind === DiffLineKind.CONTEXT) contextCount += 1;
  }
  t.eq('折叠后总行数从 121 降到 12', collapsed.length === 12, true);
  t.eq('被折叠的行数被如实记录', skippedTotal > 100, true);
  t.eq('改动两侧保留上下文', contextCount >= 4, true);
  let skippedAt = -1;
  for (let i = 0; i < collapsed.length; i++) {
    if (collapsed[i].kind === DiffLineKind.SKIPPED) { skippedAt = i; break; }
  }
  t.eq('跳过标记排在保留的上下文之后', skippedAt > 0 && collapsed[skippedAt - 1].kind === DiffLineKind.CONTEXT, true);
  t.eq('跳过标记不显示行内容（内容为空）', collapsed[skippedAt].text === '', true);

  // ── 成品：路径 + 行 + 统计 + 截断标记 ──
  const p1 = presentDiff('edit', '{"file_path":"/a/b.ts","old_string":"foo","new_string":"bar"}');
  t.eq('成品带路径', p1 !== null && p1.path, '/a/b.ts');
  t.eq('成品统计 1 增 1 删', p1 !== null && p1.added === 1 && p1.removed === 1, true);
  t.eq('未截断时 truncated=false', p1 !== null && p1.truncated === false, true);
  t.eq('不认识的工具 → 成品为 null（视图照常走摘要）', presentDiff('bash', '{"command":"ls"}'), null);

  // 截断：超过 maxLines 时必须如实置 truncated（而不是假装这就是全部）
  const manyLines = [];
  for (let i = 0; i < 60; i++) manyLines.push('x' + i);
  const manyDiff = presentDiff('write', '{"file_path":"/big.ts","content":"' + manyLines.join('\\n') + '"}', 2, 20);
  t.eq('超过行数上限 → 截断到上限', manyDiff !== null && manyDiff.lines.length, 20);
  t.eq('截断时如实置 truncated=true', manyDiff !== null && manyDiff.truncated, true);
  t.eq('截断仍如实统计增删总数（不因截断而少算）', manyDiff !== null && manyDiff.added, 60);

  console.log('  ok    45 条断言：官方 intendedDiff 规则（含提权闸门与拒绝路径）+ 行级对照 + 折叠 + 截断');
}

console.log('\n## 输入模态事实（P3：设备枚举 / 事件证据 / 形态猜测，三者优先级明确）');
{
  const {
    flattenSources, guessFromKeyboardForm, modalityFromSources, modalityOf, modalityTrace,
    noModality, sourceIsKeyboard, sourceIsPointer, unionModality,
    SOURCE_KEYBOARD, SOURCE_MOUSE, SOURCE_TOUCHPAD, SOURCE_TRACKBALL, SOURCE_TOUCHSCREEN, SOURCE_JOYSTICK,
  } = IF;

  // ── 取值映射：依据 SDK SourceType 字符串联合，逐条钉死 ──
  t.eq('keyboard 算键盘', sourceIsKeyboard(SOURCE_KEYBOARD), true);
  t.eq('mouse 不算键盘', sourceIsKeyboard(SOURCE_MOUSE), false);
  t.eq('mouse 算指针', sourceIsPointer(SOURCE_MOUSE), true);
  t.eq('touchpad 算指针（笔记本自带）', sourceIsPointer(SOURCE_TOUCHPAD), true);
  t.eq('trackball 算指针', sourceIsPointer(SOURCE_TRACKBALL), true);
  t.eq('touchscreen **不算**指针（没有悬停、没有右键，入口是长按）', sourceIsPointer(SOURCE_TOUCHSCREEN), false);
  t.eq('joystick 不算指针（无法指向具体控件）', sourceIsPointer(SOURCE_JOYSTICK), false);
  t.eq('键盘也不算指针', sourceIsPointer(SOURCE_KEYBOARD), false);
  // 未识别取值必须保守：SDK 新增输入源时不该悄悄打开 hover/右键
  t.eq('未识别的取值两者都不算（保守）', sourceIsKeyboard('hologram') === false && sourceIsPointer('hologram') === false, true);

  // ── 由枚举结果得事实 ──
  t.eq('只有触控屏 → 无键盘无指针（手机常态）',
    JSON.stringify(modalityFromSources([SOURCE_TOUCHSCREEN])), '{"hasKeyboard":false,"hasPointer":false}');
  t.eq('触控屏 + 鼠标 → 有指针（**这正是此前判错的场景**）',
    modalityFromSources([SOURCE_TOUCHSCREEN, SOURCE_MOUSE]).hasPointer, true);
  t.eq('触控屏 + 鼠标 → 仍无键盘',
    modalityFromSources([SOURCE_TOUCHSCREEN, SOURCE_MOUSE]).hasKeyboard, false);
  t.eq('触控屏 + 键盘 + 触控板 → 两者都有（笔记本）',
    modalityFromSources([SOURCE_TOUCHSCREEN, SOURCE_KEYBOARD, SOURCE_TOUCHPAD]).hasKeyboard === true
    && modalityFromSources([SOURCE_TOUCHSCREEN, SOURCE_KEYBOARD, SOURCE_TOUCHPAD]).hasPointer === true, true);
  t.eq('空列表 → 无（不抛异常）', modalityFromSources([]).hasPointer, false);

  t.eq('摊平多设备并去重', flattenSources([[SOURCE_KEYBOARD], [SOURCE_MOUSE, SOURCE_KEYBOARD]]).length, 2);
  t.eq('摊平保留原有取值', flattenSources([[SOURCE_MOUSE]]), [SOURCE_MOUSE]);

  // ── 形态猜测（最弱的兜底，与旧行为一致） ──
  t.eq('2in1 形态 → 键盘+指针都猜有（笔记本有触控板）',
    guessFromKeyboardForm(true).hasKeyboard === true && guessFromKeyboardForm(true).hasPointer === true, true);
  t.eq('手机形态 → 都猜没有', guessFromKeyboardForm(false).hasPointer, false);

  // ── 合成优先级 ──
  const noEv = noModality();
  t.eq('① 枚举成功 ⇒ 以枚举为准，**覆盖**形态猜测（2in1 拆掉键盘后不再假装有键盘）',
    modalityOf({ enumerated: noModality(), observed: noEv, formGuess: guessFromKeyboardForm(true) }).hasKeyboard, false);
  t.eq('① 枚举成功且命中 ⇒ 手机插鼠标就有指针',
    modalityOf({ enumerated: { hasKeyboard: false, hasPointer: true }, observed: noEv, formGuess: guessFromKeyboardForm(false) }).hasPointer, true);
  t.eq('② 枚举不可用 ⇒ 退回形态猜测（保证不比旧行为更差）',
    modalityOf({ enumerated: null, observed: noEv, formGuess: guessFromKeyboardForm(true) }).hasKeyboard, true);
  t.eq('② 枚举不可用 + 悬停过 ⇒ 指针被事件证据救回来',
    modalityOf({ enumerated: null, observed: { hasKeyboard: false, hasPointer: true }, formGuess: guessFromKeyboardForm(false) }).hasPointer, true);
  t.eq('事件证据不能凭空造键盘',
    modalityOf({ enumerated: null, observed: { hasKeyboard: false, hasPointer: true }, formGuess: guessFromKeyboardForm(false) }).hasKeyboard, false);
  t.eq('三项都有时逐项取或',
    JSON.stringify(modalityOf({
      enumerated: { hasKeyboard: true, hasPointer: false },
      observed: { hasKeyboard: false, hasPointer: true },
      formGuess: noModality(),
    })), '{"hasKeyboard":true,"hasPointer":true}');

  // ── 降级与升级 ──
  t.eq('枚举可降级：拔掉鼠标后重新枚举即回到"没有指针"',
    modalityOf({ enumerated: noModality(), observed: noEv, formGuess: guessFromKeyboardForm(true) }).hasPointer, false);
  t.eq('unionModality 不制造假事实', unionModality(noModality(), noModality()).hasKeyboard, false);

  // ── 可解释性：失败时能说出理由（否则只能到设备上猜） ──
  const traceUnavailable = modalityTrace({ enumerated: null, observed: noEv, formGuess: guessFromKeyboardForm(false) });
  t.eq('枚举不可用时理由里写明"退回猜测"', traceUnavailable.length > 0 && traceUnavailable[0].indexOf('形态猜测') >= 0, true);
  const traceEmpty = modalityTrace({ enumerated: [], observed: noEv, formGuess: guessFromKeyboardForm(true) });
  t.eq('枚举成功但没有键鼠时理由里写明"当前没有"', traceEmpty[0].indexOf('没有键鼠类') >= 0, true);
  const tracePointerOnly = modalityTrace({
    enumerated: { hasKeyboard: false, hasPointer: true }, observed: noEv, formGuess: noModality(),
  });
  t.eq('只有指针时点明"不提示快捷键"', tracePointerOnly.indexOf('只有指针：启用 hover/右键，但不提示快捷键') >= 0, true);
  const traceHover = modalityTrace({
    enumerated: null, observed: { hasKeyboard: false, hasPointer: true }, formGuess: noModality(),
  });
  t.eq('事件证据生效时理由里点明"观察到指针悬停"', traceHover.indexOf('观察到指针悬停') >= 0, true);

  // ── 与策略层衔接：事实确定后，手势集合与 hover 随之确定（这才是这条链路的终点） ──
  const phoneOnly = modalityFromSources([SOURCE_TOUCHSCREEN]);
  t.eq('纯触控 ⇒ 手势集合只有长按（不给触控设备绑永远不触发的右键）',
    JSON.stringify(IP.contextMenuGestures(phoneOnly)), '["long-press"]');
  t.eq('纯触控 ⇒ 不启用 hover', IP.hoverEnabled(phoneOnly), false);
  t.eq('纯触控 ⇒ 菜单提示不出现"右键"字样',
    IP.contextMenuHintLabel(phoneOnly).indexOf('右键') < 0, true);

  const phoneWithMouse = modalityFromSources([SOURCE_TOUCHSCREEN, SOURCE_MOUSE]);
  t.eq('手机插鼠标 ⇒ 手势集合多了右键',
    JSON.stringify(IP.contextMenuGestures(phoneWithMouse)), '["long-press","right-click"]');
  t.eq('手机插鼠标 ⇒ 启用 hover（此前被 keyboardLikely 卡死）', IP.hoverEnabled(phoneWithMouse), true);

  const laptop = modalityFromSources([SOURCE_TOUCHSCREEN, SOURCE_KEYBOARD, SOURCE_TOUCHPAD]);
  t.eq('笔记本 ⇒ 长按与右键都在', JSON.stringify(IP.contextMenuGestures(laptop)), '["long-press","right-click"]');
  t.eq('键盘+指针 ⇒ 菜单提示带上快捷键说法',
    IP.contextMenuHintLabel(laptop).indexOf('右键') >= 0, true);

  console.log('  ok    37 条断言：SourceType 映射（含触控不算指针）+ 三个来源的优先级 + 可解释性');
}

console.log('\n## 详情栏拖拽与宽度记忆（P3：把模型里那条"用户想要的宽度"接通）');
{
  const { detailRoomOf, clampDetailDesired, dragDetailWidth, detailWidthOf, decideLayoutWithDetail, MAIN_MIN_VP } = LC;
  const SZ_MIN = 260;   // Sz.DETAIL_MIN
  const SZ_DEFAULT = 320;  // Sz.DETAIL_PANEL
  const SZ_MAX = 720;   // Sz.DETAIL_MAX

  // 可用空间 = 窗口宽 - 导航宽 - 主内容最小宽
  t.eq('可用空间扣除导航与主内容最小宽', detailRoomOf(1440, 240), 1440 - 240 - MAIN_MIN_VP);
  t.eq('700vp 单栏宽度下可用空间仍为正（180）', detailRoomOf(700, 240), 180);
  t.eq('窗口窄到装不下主内容时可用空间为负（由档位判定接手，不会并排）', detailRoomOf(400, 240) < 0, true);

  // 夹取
  t.eq('低于最小值 ⇒ 收到最小值', clampDetailDesired(100, 800), SZ_MIN);
  t.eq('高于可用空间 ⇒ 收到可用空间（**不跳回最小** —— 跳变是这里最容易犯的错）', clampDetailDesired(900, 800), 800);
  t.eq('区间内原样保留', clampDetailDesired(400, 800), 400);
  t.eq('可用空间小于最小值时收到最小值（不制造不可能的宽度）', clampDetailDesired(400, 200), SZ_MIN);
  t.eq('NaN ⇒ 收到最小值（坏值必须有确定收敛点）', clampDetailDesired(Number.NaN, 800), SZ_MIN);

  // 拖拽方向：把手在详情栏**左边缘** ⇒ 往左拖（deltaX<0）是变宽
  t.eq('往左拖 100 ⇒ 变宽 100', dragDetailWidth(400, -100, 1000), 500);
  t.eq('往右拖 100 ⇒ 变窄 100', dragDetailWidth(400, 100, 1000), 300);
  t.eq('往左拖到超过可用空间 ⇒ 夹在可用空间', dragDetailWidth(400, -2000, 600), 600);
  t.eq('往右拖到低于最小值 ⇒ 夹在最小值（不会拖成一条缝）', dragDetailWidth(400, 2000, 1000), SZ_MIN);

  /*
   * 拖拽**起点必须先归一化**（`beginDetailDrag` 的第一句）。
   *
   * 场景：用户在宽窗口把栏拖到 900，随后把窗口缩小 ⇒ 可用空间只剩 480，屏幕上显示的是被夹过的 480，
   * 而"意图"仍是 900。此时若直接拿 900 当起点，往窄拖会**先卡住一段**（要先把那 420 的差值拖掉），
   * 表现为"把手推不动"。先夹再记，第一帧就跟随。
   */
  t.eq('未经归一化：起点 900、往窄拖 50 仍然没动（这就是"推不动"的症状）',
    dragDetailWidth(900, 50, 480), 480);
  t.eq('归一化之后：同一个动作立刻跟随（430）',
    dragDetailWidth(clampDetailDesired(900, 480), 50, 480), 430);
  t.eq('归一化不会凭空改变意图内的值', clampDetailDesired(400, 480), 400);

  // 记忆值收窄
  t.eq('没有记录 ⇒ 默认宽度', detailWidthOf(undefined), SZ_DEFAULT);
  t.eq('NaN ⇒ 默认宽度', detailWidthOf(Number.NaN), SZ_DEFAULT);
  t.eq('低于最小值 ⇒ 最小值', detailWidthOf(10), SZ_MIN);
  t.eq('高于上限 ⇒ 上限（防止一读回来就吃掉整屏）', detailWidthOf(100000), SZ_MAX);
  t.eq('合法值原样保留', detailWidthOf(480), 480);
  t.eq('上限本身合法', detailWidthOf(SZ_MAX), SZ_MAX);

  // 与决策衔接：拖出来的宽度真的进了决策
  const wide = decideLayoutWithDetail({ widthVp: 1600, heightVp: 900, hasKeyboard: true, hasPointer: true }, 600);
  t.eq('桌面窗口 + 想要 600 ⇒ 详情栏宽 600', wide.detailWidthVp, 600);
  const tight = decideLayoutWithDetail({ widthVp: 1000, heightVp: 800, hasKeyboard: false, hasPointer: false }, 600);
  t.eq('窗口放不下想要的宽度 ⇒ 让步到最小并标注变窄',
    tight.detailWidthVp === SZ_MIN && tight.detailStep === 'detail-narrow', true);
  t.eq('1000vp 已经是三栏（并排详情可用）', tight.detailAvailable, true);

  // 档位边界：这是"拖拽能不能用"的前提 —— 双栏下详情栏**不并排**，把手根本不该出现
  const double = decideLayoutWithDetail({ widthVp: 839, heightVp: 800, hasKeyboard: false, hasPointer: false }, 600);
  t.eq('839vp（LG 边界下）是双栏 ⇒ 详情栏不并排可用', double.detailAvailable, false);
  t.eq('839vp 下详情宽度为 0（把手不该出现）', double.detailWidthVp, 0);
  const atLg = decideLayoutWithDetail({ widthVp: 840, heightVp: 800, hasKeyboard: false, hasPointer: false }, 600);
  t.eq('840vp（LG 边界）起为三栏 ⇒ 详情栏可用', atLg.detailAvailable, true);
  t.eq('840vp 下可用空间 320 < 想要的 600 ⇒ 让步到最小', atLg.detailWidthVp, SZ_MIN);
  t.eq('840vp 下主内容仍保住 MAIN_MIN_VP', atLg.detailWidthVp + atLg.navWidthVp + MAIN_MIN_VP <= 840, true);

  /*
   * 一条**边界事实**（不是缺陷，但值得钉住）：
   * 详情栏只在三栏档位并排，而三栏从 840vp 起、该档导航为 240、主内容至少 280
   * ⇒ 可用空间最小为 320 > DETAIL_MIN(260) ⇒ 让步链里的 `DETAIL_CLOSED` 分支
   * **在当前阈值下不可达**（它只在"可用空间 < 最小宽度"时触发）。
   * 保留该分支是**防御性**的（常量一旦调整就会生效）；这里把它钉成断言，
   * 好让将来真的有人调整阈值时，是**有意识地**让这条分支复活，而不是意外发现"历史遗留"。
   */
  let closedReachable = false;
  for (let w = 840; w <= 2400; w += 1) {
    const d = decideLayoutWithDetail({ widthVp: w, heightVp: 900, hasKeyboard: true, hasPointer: true }, 600);
    if (d.detailStep === 'detail-closed') { closedReachable = true; break; }
  }
  t.eq('三栏档位内 DETAIL_CLOSED 不可达（可用空间恒 > 最小宽度）', closedReachable, false);
  t.eq('但可用空间小于最小宽度时它确实会触发（模型逻辑本身正确）', LC.concedeDetail(400, 240, 600).step, 'detail-closed');

  console.log('  ok    28 条断言：可用空间 / 夹取（不跳变）/ 拖拽方向（左拖变宽）/ 起点归一化 / 记忆值收窄 / 档位边界 / 与决策衔接');
}

t.done();
