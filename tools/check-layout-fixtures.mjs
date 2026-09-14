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
  'appstate/src/main/ets/model/ToolPresentation.ets'
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
  const { toolKindOf, toolKindLabel, toolToneOf, toolDefaultExpanded, ToolKind } = TP;
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
}

t.done();
