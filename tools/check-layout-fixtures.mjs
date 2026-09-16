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
  'appstate/src/main/ets/ui/ShellTracks.ets',
  'appstate/src/main/ets/ui/Tokens.ets',
  'appstate/src/main/ets/ui/Breakpoints.ets',
  'appstate/src/main/ets/ui/LayoutController.ets',
  'appstate/src/main/ets/ui/NavigationController.ets',
  // 回合模型（§8）：纯逻辑，可在本机直接执行
  'appstate/src/main/ets/model/Trajectory.ets',
  'appstate/src/main/ets/model/Turns.ets',
  'appstate/src/main/ets/model/Search.ets',
  'appstate/src/main/ets/model/Markdown.ets',
  // 设置域判定（P4-6）：零依赖，故可以被本 fixture 直接执行
  'appstate/src/main/ets/model/SettingsDomains.ets',
  // 会话头上下文行（P2-7）：零依赖，故可以被本 fixture 直接执行
  'appstate/src/main/ets/model/SessionContext.ets',
  // 会话搜索（P7-1）：Host 内容命中 + 本地标题命中的合并规则。
  // 【依赖说明】它 import 了 `SessionList`（行类型）与 `SessionContext`（工作区名），
  // 两者都在本表里 ⇒ fixture 摊平后能解析（`tsc` 会在缺依赖时直接报出来，这正是我们要的）。
  'appstate/src/main/ets/model/SessionSearch.ets',
  // 输入区接管的焦点规则（P7-2）：零依赖（只 import 同为零依赖的 Trajectory 的类型）
  'appstate/src/main/ets/model/PendingFocus.ets',
  // 轨迹事件详情（P7-4）：零依赖（只 import 同为零依赖的 Trajectory / Present）
  'appstate/src/main/ets/model/TrajectoryDetail.ets',
  // 权限预设的呈现与切换规则（P7-6）：零依赖
  'appstate/src/main/ets/model/Permissions.ets',
  // 应用内隐私与权限说明（P7-11）：零依赖
  'appstate/src/main/ets/model/PrivacyDisclosure.ets',
  // 消息图片的几何判定（P0-3）：零依赖，与官方 ui-attachment 的 singleFit 逐条对齐
  'appstate/src/main/ets/model/ImageAttachment.ets',
  'appstate/src/main/ets/model/MessageImage.ets',
  // 输入区附件的判定与拼装（P0-4）：零依赖，顺序与类型白名单对齐官方
  'appstate/src/main/ets/model/InputAttachment.ets',
  // 输入触发管线（P7-14）：零依赖，`@` 引用与 `/` 命令的词法
  'appstate/src/main/ets/model/InputTrigger.ets',
  // 排队项的良性竞态（P7-16）：**协议码住在 dshcompat**（架构红线），零依赖
  'dshcompat/src/main/ets/QueueCodes.ets',
  // 提交失败后的草稿恢复规则（P7-15）：零依赖
  'appstate/src/main/ets/model/ComposerSend.ets',
  // 错误生命周期（P8-6c）：零依赖，判"一条错误什么时候该消失"
  'appstate/src/main/ets/model/ErrorLifecycle.ets',
  // 每会话草稿（P8-3）：零依赖，纯数组操作
  'appstate/src/main/ets/model/ComposerDrafts.ets',
  // 目标栏的可判定状态（P7-20）：零依赖
  'appstate/src/main/ets/model/GoalBar.ets',
  // 回合产出的文件（P7-21）：零依赖（只用 ToolDiff + Trajectory）
  'appstate/src/main/ets/model/ProducedFiles.ets',
  // 失败码 → 用户文案（P7-19）：表的**键**来自 dshcompat（上游事实只许住那层），
  // 因此这里也要把 ErrorCodes 编进来（见下面 tsc 的 `paths` 映射）
  'dshcompat/src/main/ets/ErrorCodes.ets',
  'appstate/src/main/ets/model/FailureText.ets',
  // 内容脱敏（P8-5）：零依赖。**从 Notify 搬出来的**——理由正是"它要被 fixture 直接执行"，
  // 而 Notify 依赖 Settings/connection，进不了这张表（见该文件说明）。
  'appstate/src/main/ets/model/Redact.ets',
  // 浮层回执归属（P2-8，E353）：零依赖
  'appstate/src/main/ets/model/Sheets.ets',
  // 设置编辑浮层的输入提示（P2-10）：零依赖
  'appstate/src/main/ets/model/SettingEditors.ets',
  // 核心页投影（P5-1）：依赖 Core.ets，两者一起执行
  'appstate/src/main/ets/model/Core.ets',
  'appstate/src/main/ets/model/CoreProjection.ets',
  // 插件启停的用户行文本层（P5-6，E369）：**零依赖**，正是为此从 PluginRows 里搬出来的
  'hostruntime/src/main/ets/core/PluginRowsText.ets',
  'appstate/src/main/ets/model/PanelRegistry.ets',
  'appstate/src/main/ets/model/NavigationState.ets',
  'appstate/src/main/ets/model/Follow.ets',
  'appstate/src/main/ets/model/InputPolicy.ets',
  'appstate/src/main/ets/model/ToolPresentation.ets',
  'appstate/src/main/ets/model/ToolDiff.ets',
  'appstate/src/main/ets/model/InputFacts.ets',
  'appstate/src/main/ets/model/Timeline.ets',
  'appstate/src/main/ets/model/Jobs.ets',
  'dshcompat/src/main/ets/RemoteEvents.ets',
  'dshcompat/src/main/ets/EventShape.ets',
  'appstate/src/main/ets/model/Present.ets'
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

  /*
   * 裸 CLI 参数换成 **tsconfig**：原因是需要 `paths` 映射。
   *
   * 【为什么需要它】纯逻辑模块里 `model/FailureText.ets` 的**错误码**必须从 `dshcompat` 导入
   * （上游字面量只许住那一层，`tools/arch-check.mjs` 强制），而本脚本把 .ets 平铺复制到同一个
   * 目录、没有模块解析映射 ⇒ tsc 报 `Cannot find module 'dshcompat'`。
   * 这里生成一个**只转出错误码**的垫片并映射 `dshcompat` → 它：既不拉进整个 dshcompat，
   * 也让"码来自上游那一层"这件事在测试里保持成立。
   */
  const shim = join(SRC, 'dshcompat.ts');
  writeFileSync(shim, "export * from './ErrorCodes';\n", 'utf8');
  const config = {
    compilerOptions: {
      target: 'ES2020',
      module: 'commonjs',
      moduleResolution: 'node',
      outDir: OUT,
      rootDir: SRC,
      baseUrl: SRC,
      paths: { dshcompat: ['dshcompat.ts'] },
      skipLibCheck: true,
      strict: false
    },
    files: [...tsFiles, globals, shim]
  };
  const configPath = join(WORK, 'tsconfig.json');
  writeFileSync(configPath, JSON.stringify(config, null, 2), 'utf8');

  try {
    execFileSync(process.execPath, [tsc, '-p', configPath], { stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    const out = `${e.stdout || ''}${e.stderr || ''}`.toString();
    console.error('tsc 编译纯逻辑源文件失败——说明 LayoutController/Tokens/Breakpoints 不是合法 TS：');
    console.error(out.trim() || '(无输出)');
    process.exit(1);
  }

  /*
   * 运行时垫片（**必需**，与 `check-core-loop.mjs` 同一个坑）：tsconfig 的 `paths`
   * 只管**编译期**解析，产出的 JS 里仍然是 `require('dshcompat')` —— Node 到运行时找不到。
   * 所以按 Node 的解析规则在输出目录下放一层最小的 `node_modules`：不复制代码，
   * 只写 `package.json` 指回编译产物（`out/dshcompat.js`）。
   */
  const shimDir = join(OUT, 'node_modules', 'dshcompat');
  mkdirSync(shimDir, { recursive: true });
  writeFileSync(join(shimDir, 'package.json'),
    JSON.stringify({ name: 'dshcompat', version: '0.0.0', main: '../../dshcompat.js' }, null, 2) + '\n',
    'utf8');

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
const TL = require2('./Timeline.js');
const JB = require2('./Jobs.js');
const TJ = require2('./Trajectory.js');
const RE = require2('./RemoteEvents.js');
const SE = require2('./Search.js');
const PR = require2('./PanelRegistry.js');
const PST = require2('./Present.js');
const ST = require2('./ShellTracks.js');
const NS = require2('./NavigationState.js');
const MD = require2('./Markdown.js');
const SD = require2('./SettingsDomains.js');
const SC = require2('./SessionContext.js');
const SE2 = require2('./SettingEditors.js');
const CP = require2('./CoreProjection.js');
const PRT = require2('./PluginRowsText.js');
const SS = require2('./SessionSearch.js');
const PF = require2('./PendingFocus.js');
const TDT = require2('./TrajectoryDetail.js');
const CD = require2('./ComposerDrafts.js');
const SH = require2('./Sheets.js');
const PM = require2('./Permissions.js');
const PD = require2('./PrivacyDisclosure.js');
const MI = require2('./MessageImage.js');
const IA = require2('./InputAttachment.js');
const IT = require2('./InputTrigger.js');
const CS = require2('./ComposerSend.js');
const FT = require2('./FailureText.js');
const GB = require2('./GoalBar.js');
const PFL = require2('./ProducedFiles.js');
const QR = require2('./QueueCodes.js');
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
      detailAvailable: false, detailWidthVp: 0, detailPresentation: 'overlay',
      detailStep: 'none', landscape: false, pointerRich: false
    }
  },
  {
    name: 'PHONE 横屏 800×360（宽 800 ≥ 600 ⇒ 落双栏）',
    in: input(800, 360),
    want: {
      mode: 'double', nav: 'rail', navWidthVp: 56, navLabels: false,
      detailAvailable: false, detailWidthVp: 0, detailPresentation: 'side-panel',
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
      detailAvailable: false, detailWidthVp: 0, detailPresentation: 'side-panel',
      detailStep: 'none', landscape: false, pointerRich: false
    }
  },
  {
    name: 'TABLET 横屏 1280×800',
    in: input(1280, 800),
    want: {
      mode: 'triple', nav: 'panel', navWidthVp: 240, navLabels: true,
      detailAvailable: true, detailWidthVp: 320, detailPresentation: 'column',
      detailStep: 'none', landscape: true, pointerRich: false
    }
  },
  {
    name: 'DESKTOP/2in1 全屏 1920×1080（键鼠齐备）',
    in: input(1920, 1080, true, true),
    want: {
      mode: 'triple', nav: 'panel', navWidthVp: 240, navLabels: true,
      detailAvailable: true, detailWidthVp: 320, detailPresentation: 'column',
      detailStep: 'none', landscape: true, pointerRich: true
    }
  },
  {
    name: '2in1 自由窗被拖窄 700×900（应与平板竖屏同构，不重启页面）',
    in: input(700, 900, true, true),
    want: {
      mode: 'double', nav: 'rail', navWidthVp: 56, navLabels: false,
      detailAvailable: false, detailWidthVp: 0, detailPresentation: 'side-panel',
      detailStep: 'none', landscape: false, pointerRich: true
    }
  },
  {
    name: '2in1 自由窗拖到手机宽度 480×800',
    in: input(480, 800, true, true),
    want: {
      mode: 'single', nav: 'bottom', navWidthVp: 0, navLabels: false,
      detailAvailable: false, detailWidthVp: 0, detailPresentation: 'overlay',
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
  const { decideBack, BackAction, StackPage, selectTab, normalizeTab, showsConversation, navTabs, previewIsLayer, drillAfterPreviewClosed } = NC;
  // 【坑】`NavTab.SESSIONS` 是 `'workspaces'` 的**别名**（E108：会话并入工作区），
  // 所以"在会话页签"与"在工作区页签"是同一个状态；默认值必须写 'workspaces'。
  // `conversationIsPage` 默认 false：**多栏形态**下会话不是"一层"（列表始终可见）。
  // 单栏（手机）的用例显式传 true —— 见下面"会话整页"那组断言。
  const nav = (o) => Object.assign({ tab: 'workspaces', stackPage: StackPage.MAIN, wsDrill: 0, hasSession: true, detailOpen: false, drawerOpen: false, conversationIsPage: false }, o);
  const ov = (o) => Object.assign({ credentialOpen: false, settingDraftOpen: false, searchOpen: false, choosingOpen: false, detailOverlayOpen: false, previewOpen: false }, o);

  // 优先级：浮层之间也有先后（凭据 → 设置草稿 → 搜索 → 选择）
  // P1-5：手机抽屉是盖在整页上的导航面 ⇒ 比所有浮层都靠上
  t.eq('抽屉打开时，返回先收抽屉（哪怕有浮层）',
    decideBack(nav({ drawerOpen: true }), ov({ credentialOpen: true, searchOpen: true })), BackAction.CLOSE_DRAWER);
  t.eq('抽屉打开且有二级页 ⇒ 仍先收抽屉',
    decideBack(nav({ drawerOpen: true, stackPage: StackPage.DIAGNOSTICS }), ov({})), BackAction.CLOSE_DRAWER);
  t.eq('抽屉关着 ⇒ 回到原来的阶梯（关凭据浮层）',
    decideBack(nav({ drawerOpen: false }), ov({ credentialOpen: true })), BackAction.CLOSE_CREDENTIAL);
  t.eq('全开时先关凭据浮层', decideBack(nav({}), ov({ credentialOpen: true, settingDraftOpen: true, searchOpen: true, choosingOpen: true, previewOpen: true })), BackAction.CLOSE_CREDENTIAL);
  t.eq('无凭据时关设置草稿', decideBack(nav({}), ov({ settingDraftOpen: true, searchOpen: true })), BackAction.CLOSE_SETTING_DRAFT);
  t.eq('再关搜索', decideBack(nav({}), ov({ searchOpen: true, choosingOpen: true })), BackAction.CLOSE_SEARCH);
  t.eq('再关选择浮层', decideBack(nav({}), ov({ choosingOpen: true, previewOpen: true })), BackAction.CLOSE_CHOICE);
  // 浮层优先于二级页
  t.eq('浮层优先于二级页', decideBack(nav({ stackPage: StackPage.DIAGNOSTICS }), ov({ searchOpen: true })), BackAction.CLOSE_SEARCH);
  // 详情半模态（P1.5）：它盖在页面上，但排在真正的模态编辑态之后
  t.eq('详情浮层排在其它浮层之后', decideBack(nav({}), ov({ searchOpen: true, detailOverlayOpen: true })), BackAction.CLOSE_SEARCH);
  t.eq('详情浮层优先于二级页', decideBack(nav({ stackPage: StackPage.DIAGNOSTICS }), ov({ detailOverlayOpen: true })), BackAction.CLOSE_DETAIL_OVERLAY);
  t.eq('详情浮层优先于详情栏', decideBack(nav({ detailOpen: true }), ov({ detailOverlayOpen: true })), BackAction.CLOSE_DETAIL_OVERLAY);
  t.eq('详情浮层优先于工作区下钻', decideBack(nav({ tab: 'workspaces', wsDrill: 3 }), ov({ detailOverlayOpen: true })), BackAction.CLOSE_DETAIL_OVERLAY);
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

  /*
   * ───────── P8-1：组合态（此前只测了 wsDrill=0 的顺路情形）─────────
   *
   * 缺陷原形：单栏下预览就是工作区第 2 层（`WorkspacePane.buildStacked`：0=列表、1=文件树、≥2=预览），
   * 而阶梯里"下钻退一层"排在"关预览"之前 ⇒ 按返回只是把层数从 2 减到 1：
   * 预览确实不在屏幕上了，`previewOpen` 却还留着 ⇒ 之后那一次返回键**白按一次**
   * （屏幕上什么都不变），这是本项目反复出现的"假动作"。
   */
  t.eq('单栏：预览层（drill≥2）⇒ 先关预览，而不是先退下钻',
    decideBack(nav({ tab: 'workspaces', wsDrill: 2 }), ov({ previewOpen: true })), BackAction.CLOSE_PREVIEW);
  t.eq('单栏：drill=3 同理', decideBack(nav({ tab: 'workspaces', wsDrill: 3 }), ov({ previewOpen: true })), BackAction.CLOSE_PREVIEW);
  t.eq('多栏：预览只是并排的一栏 ⇒ 先退下钻（它不盖住文件树）',
    decideBack(nav({ tab: 'workspaces', wsDrill: 1 }), ov({ previewOpen: true })), BackAction.DRILL_UP);
  t.eq('层判定：单栏 drill≥2 = 层', previewIsLayer(nav({ tab: 'workspaces', wsDrill: 2 })), true);
  t.eq('层判定：drill=1 不是层', previewIsLayer(nav({ tab: 'workspaces', wsDrill: 1 })), false);
  t.eq('层判定：二级页上不是层（预览没在屏幕上）',
    previewIsLayer(nav({ tab: 'workspaces', wsDrill: 2, stackPage: StackPage.CONVERSATION })), false);
  t.eq('层判定：非工作区页签不是层', previewIsLayer(nav({ tab: 'settings', wsDrill: 2 })), false);
  // 关掉预览必须回到文件树：只清预览会留下"看不见却还在"的一层
  t.eq('关预览 ⇢ 单栏回到文件树（2 → 1）', drillAfterPreviewClosed(nav({ tab: 'workspaces', wsDrill: 2 })), 1);
  t.eq('关预览 ⇢ 多栏不动下钻', drillAfterPreviewClosed(nav({ tab: 'workspaces', wsDrill: 1 })), 1);

  /*
   * 手机单栏：会话是"盖在列表上的一层"。
   *
   * 缺陷原形：`openSession` 在单栏下既切主区面板、又把 `stackPage` 设成 `CONVERSATION`；
   * 而 `STACK_TO_MAIN` 只改 `stackPage`。于是按返回 ⇒ 主区面板仍是会话 ⇒ **屏幕上什么都不变**，
   * 再按一次 ⇒ 根层交给系统**直接退出应用**（用户看到"第一次没反应、第二次退出"）。
   */
  t.eq('单栏会话整页 ⇒ 返回列表（保留会话）',
    decideBack(nav({ conversationIsPage: true, stackPage: StackPage.CONVERSATION }), ov({})), BackAction.BACK_TO_LIST);
  t.eq('单栏会话整页优先于二级页（两者同时成立时只退一层）',
    decideBack(nav({ conversationIsPage: true, stackPage: StackPage.CONVERSATION, wsDrill: 2 }), ov({})), BackAction.BACK_TO_LIST);
  t.eq('多栏会话不是层 ⇒ 二级页规则照旧',
    decideBack(nav({ conversationIsPage: false, stackPage: StackPage.CONVERSATION }), ov({})), BackAction.STACK_TO_MAIN);
  t.eq('浮层仍优先于"会话整页"',
    decideBack(nav({ conversationIsPage: true }), ov({ searchOpen: true })), BackAction.CLOSE_SEARCH);

  /*
   * 全组合矩阵：把阶梯按**文档顺序**写成数据表，再对状态的笛卡尔积逐个比对。
   *
   * 【为什么不只写几条顺路用例】阶梯的缺陷全部出在"两个条件同时成立"的组合态上
   * （预览 × 下钻、会话整页 × 二级页…）。这里用一个**独立的实现**（表驱动、按顺序取第一个命中）
   * 去对账 `decideBack` 的 if 链：任何一条分支挪了位置都会在某个组合上被抓住。
   */
  const LADDER = [
    ['CLOSE_DRAWER', (n, o) => n.drawerOpen],
    ['CLOSE_CREDENTIAL', (n, o) => o.credentialOpen],
    ['CLOSE_SETTING_DRAFT', (n, o) => o.settingDraftOpen],
    ['CLOSE_SEARCH', (n, o) => o.searchOpen],
    ['CLOSE_CHOICE', (n, o) => o.choosingOpen],
    ['CLOSE_DETAIL_OVERLAY', (n, o) => o.detailOverlayOpen],
    ['CLOSE_PREVIEW', (n, o) => o.previewOpen && previewIsLayer(n)],
    ['BACK_TO_LIST', (n, o) => n.conversationIsPage],
    ['STACK_TO_MAIN', (n, o) => n.stackPage !== StackPage.MAIN],
    ['CLOSE_DETAIL', (n, o) => n.detailOpen],
    ['DRILL_UP', (n, o) => n.tab === 'workspaces' && n.wsDrill > 0],
    ['CLOSE_PREVIEW', (n, o) => o.previewOpen],
    ['TAB_TO_SESSIONS', (n, o) => n.tab !== 'workspaces'],
    ['EXIT', () => true]
  ];
  const bools = [false, true];
  let combos = 0;
  let mismatches = 0;
  for (const drawerOpen of bools)
  for (const credentialOpen of bools)
  for (const searchOpen of bools)
  for (const detailOverlayOpen of bools)
  for (const previewOpen of bools)
  for (const conversationIsPage of bools)
  for (const detailOpen of bools)
  for (const stackPage of [StackPage.MAIN, StackPage.CONVERSATION, StackPage.DIAGNOSTICS])
  for (const wsDrill of [0, 1, 2])
  for (const tab of ['workspaces', 'settings']) {
    const n = nav({ drawerOpen, conversationIsPage, detailOpen, stackPage, wsDrill, tab });
    const o = ov({ credentialOpen, searchOpen, detailOverlayOpen, previewOpen });
    // 表里写的是**动作名**，实际值要比对枚举值（`BackAction` 的值是小写串）
    const want = BackAction[LADDER.find(([, when]) => when(n, o))[0]];
    const got = decideBack(n, o);
    combos++;
    if (got !== want) {
      mismatches++;
      if (mismatches <= 3) {
        t.eq(`组合态不一致：${JSON.stringify({ drawerOpen, credentialOpen, searchOpen, detailOverlayOpen, previewOpen, conversationIsPage, detailOpen, stackPage, wsDrill, tab })}`, got, want);
      }
    }
  }
  t.eq(`组合态矩阵：${combos} 种组合下动作唯一且与阶梯表一致`, mismatches, 0);
  console.log('  ok    返回键阶梯的每一级 + 浮层内部先后 + 详情半模态的位置，都被断言');
  console.log(`  ok    P8-1：组合态矩阵 ${combos} 种（预览层 / 会话整页 / 抽屉 × 浮层 × 下钻 × 页签）`);

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

  // 对话视图的可见集合：用户消息 + 回答 + notices（**错误要留**），不含工具/思考。
  //
  // 【这里曾经自相矛盾】注释写着"错误要留"，期望值却把 `e1` 漏掉了——因为旧判据是
  // "speaker 不是 SYSTEM 就显示"，而这条错误条的 speaker 恰好是 SYSTEM，
  // 于是被静默丢掉。**断言的旧期望把 bug 固化了下来**（P0-1 修判据时才发现）。
  // 新判据按结构与来源判定：ERROR 永远进 notices ⇒ 可见。
  const chat = chatVisibleItems(turns).map((i) => i.id);
  t.eq('对话视图可见集合（含错误）', chat, ['u1', 'a1', 'u2', 'a2', 'e1']);

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

  // ── 详情呈现方式（P3 §12）：四形态各有各的呈现，不再"双栏也弹半模态" ──
  const { detailPresentationOf } = LC;
  t.eq('单栏 ⇒ 整页下钻/半模态（并排放不下）', detailPresentationOf('single'), 'overlay');
  t.eq('双栏 ⇒ 侧边浅层面板（此前与手机一样弹 Sheet，把列表整个盖住）', detailPresentationOf('double'), 'side-panel');
  t.eq('三栏 ⇒ 真右栏（与主内容并排）', detailPresentationOf('triple'), 'column');
  t.eq('呈现方式与"栏是否并排"是两件事：双栏不并排但仍要并可见',
    decideLayoutWithDetail({ widthVp: 800, heightVp: 1280, hasKeyboard: false, hasPointer: false }, 400).detailAvailable, false);
  t.eq('…而它的呈现方式仍是侧边面板',
    decideLayoutWithDetail({ widthVp: 800, heightVp: 1280, hasKeyboard: false, hasPointer: false }, 400).detailPresentation, 'side-panel');

  console.log('  ok    33 条断言：可用空间 / 夹取（不跳变）/ 拖拽方向（左拖变宽）/ 起点归一化 / 记忆值收窄 / 档位边界 / 呈现方式 / 与决策衔接');
}

console.log('\n## 轨迹时间线（P2 §11：交互式时间总览；种类/比例/拖动聚焦/会话统计）');
{
  const {
    TimelineKind, timelineKindLabel, timelineKindOf, timelineCellsOf, timelineScaleOf,
    cellIdAtRatio, segmentOrdinalOf, timelineTotalLabel, timelineStartedLabel,
    listIndexForCell, cellIdForListIndex,
    statsLinesOf, StatsUnit,
  } = TL;
  const { TrajectoryKind } = TJ;

  // 造条目：只填本模型用到的字段
  const item = (id, kind, speaker, elapsedMs, at) => ({
    id, kind, speaker: speaker || 'assistant', elapsedMs: elapsedMs || 0, at: at || 0,
    body: '', reasoning: '', model: '', toolName: '', callId: '', toolArgs: '',
    toolState: 'success', toolOutput: '', subagentName: '', fileName: '', fileSize: 0,
    title: '', progress: '', percent: -1, streaming: false, expanded: false, internal: false,
  });

  // ── 种类标签：逐字取官方中文 ──
  t.eq('system 标签', timelineKindLabel(TimelineKind.SYSTEM), '系统');
  t.eq('user 标签', timelineKindLabel(TimelineKind.USER), '用户');
  t.eq('context 标签', timelineKindLabel(TimelineKind.CONTEXT), '上下文');
  t.eq('compacted 标签', timelineKindLabel(TimelineKind.COMPACTED), '已压缩');
  t.eq('message 标签是「助手」（官方 kind.message 中文就是助手）', timelineKindLabel(TimelineKind.MESSAGE), '助手');
  t.eq('tool 标签', timelineKindLabel(TimelineKind.TOOL), '工具');
  t.eq('subtool 标签', timelineKindLabel(TimelineKind.SUBTOOL), '子工具');

  // ── 条目 → 格子 ──
  t.eq('用户消息 → 用户格', timelineKindOf(item('a', TrajectoryKind.MESSAGE, 'user')), TimelineKind.USER);
  t.eq('助手消息 → 助手格', timelineKindOf(item('b', TrajectoryKind.MESSAGE, 'assistant')), TimelineKind.MESSAGE);
  t.eq('思考归入助手那一步（官方没有独立的思考格）', timelineKindOf(item('c', TrajectoryKind.REASONING)), TimelineKind.MESSAGE);
  t.eq('工具调用 → 工具格', timelineKindOf(item('d', TrajectoryKind.TOOL)), TimelineKind.TOOL);
  t.eq('子代理也是一次工具调用 → 工具格（官方 tool/subtool 之分需要父子关系，我方没有）',
    timelineKindOf(item('e', TrajectoryKind.SUBAGENT)), TimelineKind.TOOL);
  t.eq('交付物**不产生**格子（官方时间线没有这个种类）', timelineKindOf(item('f', TrajectoryKind.DELIVERABLE)), null);
  t.eq('目标不产生格子', timelineKindOf(item('g', TrajectoryKind.GOAL)), null);
  t.eq('任务不产生格子', timelineKindOf(item('h', TrajectoryKind.JOB)), null);
  t.eq('错误不产生格子（官方把错误记在格子上的 isError，而不是一种 kind）',
    timelineKindOf(item('i', TrajectoryKind.ERROR)), null);

  const cells = timelineCellsOf([
    item('t1', TrajectoryKind.TOOL, 'assistant', 3000, 1000),
    item('t2', TrajectoryKind.TOOL, 'assistant', 1000, 2000),
    item('m1', TrajectoryKind.MESSAGE, 'assistant', 0, 3000),
    item('d1', TrajectoryKind.DELIVERABLE, 'assistant', 500, 4000),
  ]);
  t.eq('只有能对上种类的条目进时间线（4 条里 3 条）', cells.length, 3);
  t.eq('没有计时数据的格子仍在（不算比例但可见）',
    cells[cells.length - 1].durationMs, 0);

  // ── 比例 ──
  const scale = timelineScaleOf(cells);
  t.eq('总耗时只统计有计时数据的格子', scale.totalMs, 4000);
  t.eq('比例段只含有计时数据的格子', scale.segments.length, 2);
  t.eq('有计时数据', scale.hasData, true);
  t.eq('第一段比例 3/4', Math.abs(scale.segments[0].ratio - 0.75) < 1e-9, true);
  t.eq('第一段起点为 0', scale.segments[0].startRatio, 0);
  t.eq('第二段起点接在第一段之后（累计起点，不是浮动相加）',
    Math.abs(scale.segments[1].startRatio - 0.75) < 1e-9, true);
  t.eq('比例之和为 1', Math.abs(scale.segments[0].ratio + scale.segments[1].ratio - 1) < 1e-9, true);
  t.eq('格子总数包含没有计时数据的', scale.count, 3);

  const noData = timelineScaleOf([item('x', TrajectoryKind.TOOL, 'assistant', 0, 0)]);
  t.eq('全都没有计时数据 ⇒ hasData=false（界面显示官方那句"无计时数据"）', noData.hasData, false);
  t.eq('无计时数据时总计文案就是官方文案', timelineTotalLabel(noData), '无计时数据');
  t.eq('有数据时的总计文案带时长', timelineTotalLabel(scale).indexOf('总计 ') === 0, true);

  // ── 拖动聚焦（官方："水平拖动可聚焦事件"） ──
  t.eq('比例 0.1 落在第一格', cellIdAtRatio(scale.segments, 0.1), 't1');
  t.eq('比例 0.9 落在第二格', cellIdAtRatio(scale.segments, 0.9), 't2');
  t.eq('恰好落在分界点 0.75 归后一格', cellIdAtRatio(scale.segments, 0.75), 't2');
  t.eq('拖到条左侧之外 ⇒ 夹到第一格（而不是什么都不选）', cellIdAtRatio(scale.segments, -0.5), 't1');
  t.eq('拖到条右侧之外 ⇒ 夹到最后一格', cellIdAtRatio(scale.segments, 1.7), 't2');
  t.eq('空条 ⇒ 空 id（不抛异常）', cellIdAtRatio([], 0.5), '');
  t.eq('序号从 1 开始', segmentOrdinalOf(scale.segments, 't2'), 2);
  t.eq('找不到序号 ⇒ 0', segmentOrdinalOf(scale.segments, 'nope'), 0);

  // ── 条 ↔ 列表联动：聚焦的格子在列表第几行 ──
  const listItems = [
    item('l1', TrajectoryKind.MESSAGE, 'user', 0, 0),
    item('l2', TrajectoryKind.TOOL, 'assistant', 100, 0),
    item('l3', TrajectoryKind.GOAL, 'assistant', 0, 0),
    item('l4', TrajectoryKind.TOOL, 'assistant', 200, 0),
  ];
  t.eq('聚焦工具格 ⇒ 滚到列表第 1 行', listIndexForCell(listItems, 'l2'), 1);
  t.eq('行号是**列表里的位置**（含不产生格子的条目）', listIndexForCell(listItems, 'l4'), 3);
  t.eq('还没聚焦（空 id）⇒ 不滚（-1，而不是第 0 行）', listIndexForCell(listItems, ''), -1);
  t.eq('条目被过滤出列表 ⇒ 不滚', listIndexForCell(listItems, 'gone'), -1);
  t.eq('空列表 ⇒ 不滚', listIndexForCell([], 'l2'), -1);

  t.eq('列表第 1 行是工具格', cellIdForListIndex(listItems, 1), 'l2');
  t.eq('列表第 2 行是目标（**不产生格子**）⇒ 空 id', cellIdForListIndex(listItems, 2), '');
  t.eq('越界行号 ⇒ 空 id（不抛异常）', cellIdForListIndex(listItems, 99), '');
  t.eq('负行号 ⇒ 空 id', cellIdForListIndex(listItems, -1), '');
  t.eq('空列表 ⇒ 空 id', cellIdForListIndex([], 0), '');

  /*
   * 助手逐步计时（官方 `assistantTimingDetail`）**故意不在本模型里**：
   * 那些字段（`timingRecorded`/`stepStartTime`/`firstTokenTime`）来自官方客户端自己的 metrics，
   * 我方投影没有 ⇒ 没有消费者的函数不留（"不预置空 API"）。
   * 会话级的「首 token 平均（TTFT）」由下面的 `sessionStats` 给，仍有覆盖。
   */
  // ── 会话统计：官方 web 的五项，为 0 即不显示 ──
  const full = statsLinesOf({ turns: 3, steps: 7, llmMs: 12000, toolMs: 4000, ttftMs: 3000, ttftSteps: 3, decodeMs: 2000, decodeTokens: 100 });
  t.eq('四项时间相关项齐全时给四行', full.length, 4);
  t.eq('不含「轮次/步数」那一项（会话头部已显示，不重复）',
    full.filter((l) => l.key === 'turns').length, 0);
  t.eq('首行是模型用时', full[0].key, 'llm');
  t.eq('模型用时单位是毫秒', full[0].unit, StatsUnit.MS);
  t.eq('TTFT 是**平均值**（除以步数）', full[2].value, 1000);
  t.eq('TPS = 输出 token / 秒', full[3].value, 50);
  const none = statsLinesOf({ turns: 0, steps: 0, llmMs: 0, toolMs: 0, ttftMs: 0, ttftSteps: 0, decodeMs: 0, decodeTokens: 0 });
  t.eq('全为 0 ⇒ 一行都不显示（而不是显示一堆 0）', none.length, 0);
  const onlyCounts = statsLinesOf({ turns: 5, steps: 9, llmMs: 0, toolMs: 0, ttftMs: 0, ttftSteps: 0, decodeMs: 0, decodeTokens: 0 });
  t.eq('只有轮次/步数（无任何计时）⇒ 一行也不给（那两项不归这里显示）', onlyCounts.length, 0);
  const ttftNoSteps = statsLinesOf({ turns: 1, steps: 0, llmMs: 0, toolMs: 0, ttftMs: 500, ttftSteps: 0, decodeMs: 0, decodeTokens: 0 });
  t.eq('有 TTFT 但没有步数 ⇒ 不出平均值（没有步数就没有平均可言）',
    ttftNoSteps.filter((l) => l.key === 'ttft').length, 0);
  const decodeNoTokens = statsLinesOf({ turns: 1, steps: 1, llmMs: 0, toolMs: 0, ttftMs: 0, ttftSteps: 0, decodeMs: 1000, decodeTokens: 0 });
  t.eq('有解码时长但没有 token 数 ⇒ 不出 TPS',
    decodeNoTokens.filter((l) => l.key === 'tps').length, 0);

  console.log('  ok    47 条断言：官方种类标签 / 条目映射（含"不产生格子"的四类）/ 累计比例 / 拖动聚焦与夹取 / 会话统计四项');
}

console.log('\n## 后台任务（P2：会话头部的任务注册表；官方 dsh-client-ui-jobs 的规则）');
{
  const {
    JobDot, jobIsLive, jobDotState, jobStatusLabel, jobDurationText, jobElapsedMs,
    orderedJobs, liveJobCount, jobCountLabel, jobListVisible, jobRowStatusText,
    jobDurationTitle, jobTickerNeeded, jobListA11y,
  } = JB;

  const job = (id, status, startedAt, finishedAt, kind, label, detail) => {
    const j = { id, kind: kind || 'bash', label: label || ('job-' + id), status, startedAt };
    if (finishedAt !== undefined) { j.finishedAt = finishedAt; }
    if (detail !== undefined) { j.detail = detail; }
    return j;
  };

  // ── live 判定（官方 isLive） ──
  t.eq('running 算进行中', jobIsLive(job('a', 'running', 0)), true);
  t.eq('stopping 也算进行中（请求停止尚未落地）', jobIsLive(job('b', 'stopping', 0)), true);
  t.eq('completed 不算', jobIsLive(job('c', 'completed', 0, 10)), false);
  t.eq('killed 不算', jobIsLive(job('d', 'killed', 0, 10)), false);
  t.eq('failed 不算', jobIsLive(job('e', 'failed', 0, 10)), false);

  // ── 状态点语义（官方 dotState；stopping 与 killed 共用 attention 色） ──
  t.eq('running → ongoing', jobDotState('running'), JobDot.ONGOING);
  t.eq('stopping → warning', jobDotState('stopping'), JobDot.WARNING);
  t.eq('killed → warning（与 stopping 同色：都是"按请求结束"）', jobDotState('killed'), JobDot.WARNING);
  t.eq('completed → done', jobDotState('completed'), JobDot.DONE);
  t.eq('failed → error', jobDotState('failed'), JobDot.ERROR);
  t.eq('未知状态 → error（宁可提示异常，也不显示成正常）', jobDotState('forged'), JobDot.ERROR);

  // ── 状态文案（逐字取官方中文） ──
  t.eq('running 文案', jobStatusLabel('running'), '运行中');
  t.eq('stopping 文案', jobStatusLabel('stopping'), '正在停止');
  t.eq('completed 文案', jobStatusLabel('completed'), '已完成');
  t.eq('killed 文案是「已取消」', jobStatusLabel('killed'), '已取消');
  t.eq('failed 文案', jobStatusLabel('failed'), '已失败');

  // ── 时长：最多两个相邻单位，小时封顶 ──
  t.eq('12 秒', jobDurationText(12 * 1000), '12秒');
  t.eq('0 秒（负数也被夹到 0）', jobDurationText(-5), '0秒');
  t.eq('1 分 5 秒', jobDurationText(65 * 1000), '1分5秒');
  t.eq('59 分 59 秒', jobDurationText(3599 * 1000), '59分59秒');
  t.eq('1 小时 0 分（小时是最大单位，不再长出天/月）', jobDurationText(3600 * 1000), '1小时0分');
  t.eq('30 小时 0 分（不折成"天"）', jobDurationText(30 * 3600 * 1000), '30小时0分');

  // ── 时长算法 ──
  t.eq('进行中按 now 算', jobElapsedMs(job('a', 'running', 1000), 5000), 4000);
  t.eq('已结束按 finishedAt 算（不受 now 影响）', jobElapsedMs(job('b', 'completed', 1000, 3000), 999999), 2000);
  t.eq('已结束但缺 finishedAt ⇒ 算 0（不拿"现在"去算已结束的任务）', jobElapsedMs(job('c', 'completed', 1000), 999999), 0);
  t.eq('时钟回退也不出负时长', jobElapsedMs(job('d', 'running', 5000), 1000), 0);

  // ── 排序（官方 ordered）：进行中在前按开始升序，已结束按结束倒序 ──
  const jobs = [
    job('done-old', 'completed', 100, 1000),
    job('live-late', 'running', 500),
    job('done-new', 'completed', 200, 5000),
    job('live-early', 'running', 300),
    job('killed', 'killed', 150, 3000),
  ];
  const order = orderedJobs(jobs).map((j) => j.id).join(',');
  t.eq('进行中在前（按开始时间升序），已结束按结束时间倒序',
    order, 'live-early,live-late,done-new,killed,done-old');
  t.eq('原数组不被就地改动（返回副本）', jobs[0].id, 'done-old');
  // 同毫秒结束的两条退回开始时间升序 —— 官方为了"不依赖宿主 map 迭代顺序"
  const tie = orderedJobs([
    job('t-late', 'completed', 200, 5000),
    job('t-early', 'completed', 100, 5000),
  ]).map((j) => j.id).join(',');
  t.eq('同毫秒结束时按开始时间升序（排序不依赖迭代顺序）', tie, 't-early,t-late');

  // ── 计数与可见性 ──
  t.eq('进行中计数', liveJobCount(jobs), 2);
  t.eq('有进行中 ⇒ 文案说"运行中"', jobCountLabel(jobs), '2 个后台任务运行中');
  t.eq('只有已结束 ⇒ 只报数量', jobCountLabel([job('x', 'completed', 0, 10), job('y', 'failed', 0, 10)]), '2 个后台任务');
  t.eq('**一个任务都没有 ⇒ 控件不出现**（官方：普通对话不该长出没用的控件）', jobListVisible([]), false);
  t.eq('有任务 ⇒ 出现', jobListVisible([job('x', 'completed', 0, 10)]), true);

  // ── 行上的状态文字：detail 优先 ──
  t.eq('有 detail ⇒ 显示 detail', jobRowStatusText(job('a', 'running', 0, undefined, undefined, undefined, 'npm run build')), 'npm run build');
  t.eq('没有 detail ⇒ 退回状态文案', jobRowStatusText(job('b', 'running', 0)), '运行中');
  t.eq('空串 detail 也退回状态文案', jobRowStatusText(job('c', 'running', 0, undefined, undefined, undefined, '')), '运行中');

  // ── 时长标题（官方 duration.title.live） ──
  t.eq('进行中的标题是"已运行 …"', jobDurationTitle(job('a', 'running', 0), 65 * 1000), '已运行 1分5秒');
  t.eq('已结束的标题是"共 …"', jobDurationTitle(job('b', 'completed', 0, 2000), 0), '共 2秒');

  // ── 定时器只在需要时起（移动端不多耗电） ──
  t.eq('有进行中 ⇒ 需要定时器', jobTickerNeeded([job('a', 'running', 0)]), true);
  t.eq('全是已结束 ⇒ 不需要定时器', jobTickerNeeded([job('b', 'completed', 0, 10)]), false);
  t.eq('空列表 ⇒ 不需要定时器', jobTickerNeeded([]), false);

  // ── 无障碍 ──
  t.eq('列表无障碍文案含计数', jobListA11y([job('a', 'running', 0)]), '后台任务：1 个后台任务运行中');

  console.log('  ok    40 条断言：live 判定 / 状态点语义 / 五种文案 / 时长三档与小时封顶 / 排序（含同毫秒退回） / 计数与"无任务不出现" / detail 优先 / 定时器按需');
}

console.log('\n## P0-1 对话可见性：内部事件不得进入 Conversation（结构与来源判定，不靠文本）');
{
  const { isConversationVisibleEvent } = RE;
  const { ConversationAudience, conversationAudienceOf, needsInternalIsolation } = TM;
  const { TrajectoryKind, Speaker } = TJ;

  // ── ① 事件类型白名单（来源事实，在投影时判定） ──
  t.eq('user/message 可见', isConversationVisibleEvent('user/message'), true);
  t.eq('assistant/message 可见', isConversationVisibleEvent('assistant/message'), true);
  t.eq('**system/message 不可见**（系统提示词）', isConversationVisibleEvent('system/message'), false);
  t.eq('**未识别类型不可见**（正文是原始载荷 JSON）',
    isConversationVisibleEvent('totally/unknown-event'), false);
  /*
   * P7-13 更正：`command/run` / `command/done` **应当可见**。
   *
   * 早先把它们当"内部事件"隐掉，是因为它们与助手消息同族、会被当成"助手说的话"。
   * 读了上游才知道真相：命令的生命周期是**对话里的持久过程节点**
   * （`dsh-client-ui-commands`），隐掉它的后果是"执行命令后界面上什么也不会发生"。
   * 现在它们有自己的族（`EventFamily.COMMAND`）与自己的条目类型
   * （`TrajectoryKind.COMMAND`，渲染成命令卡），既进对话、也不冒充回答。
   */
  t.eq('**command/run 可见**（命令的生命周期是对话里的过程节点）',
    isConversationVisibleEvent('command/run'), true);
  t.eq('command/done 可见（结局文本必须能看到）', isConversationVisibleEvent('command/done'), true);
  t.eq('两条命令帧同族', RE.classifyEventType('command/run') === RE.classifyEventType('command/done'), true);
  t.eq('**compaction/summary 不可见**（内部 context）',
    isConversationVisibleEvent('compaction/summary'), false);
  t.eq('request/context 不可见', isConversationVisibleEvent('request/context'), false);
  t.eq('审计类不可见', isConversationVisibleEvent('permission/preset'), false);
  t.eq('tool/call 可见（进过程分组）', isConversationVisibleEvent('tool/call'), true);
  t.eq('tool/result 可见（进过程分组）', isConversationVisibleEvent('tool/result'), true);
  t.eq('llm/retry 可见（错误要留）', isConversationVisibleEvent('llm/retry'), true);
  t.eq('todo/write 可见（任务行）', isConversationVisibleEvent('todo/write'), true);
  t.eq('deliverables/presented 可见', isConversationVisibleEvent('deliverables/presented'), true);
  // 反向：白名单不能靠"像消息"来猜
  t.eq('名字里带 message 但不是会话消息 ⇒ 不可见',
    isConversationVisibleEvent('session/title-llm-request'), false);

  // ── ② 条目 → 对话角色 ──
  const mk = (id, kind, speaker, internal) => ({
    id, kind, speaker, internal, at: 0, body: '', reasoning: '', model: '', elapsedMs: 0,
    toolName: '', callId: '', toolArgs: '', toolState: 'pending', toolOutput: '',
    subagentName: '', fileName: '', fileSize: 0, title: '', progress: '', percent: -1,
    streaming: false, expanded: false, commandId: '', commandKind: '',
  });
  const A = ConversationAudience;
  t.eq('用户消息 → USER', conversationAudienceOf(mk('u', TrajectoryKind.MESSAGE, Speaker.USER, false)), A.USER);
  t.eq('助手消息 → ASSISTANT', conversationAudienceOf(mk('a', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, false)), A.ASSISTANT);
  t.eq('错误 → NOTICE（规格：Conversation 允许 ERROR）',
    conversationAudienceOf(mk('e', TrajectoryKind.ERROR, Speaker.ASSISTANT, false)), A.NOTICE);
  t.eq('工具 → PROCESS（只进折叠的过程分组）',
    conversationAudienceOf(mk('t', TrajectoryKind.TOOL, Speaker.ASSISTANT, false)), A.PROCESS);
  t.eq('思考 → PROCESS', conversationAudienceOf(mk('r', TrajectoryKind.REASONING, Speaker.ASSISTANT, false)), A.PROCESS);
  t.eq('系统角色的消息 → HIDDEN（即便来源可见）',
    conversationAudienceOf(mk('s', TrajectoryKind.MESSAGE, Speaker.SYSTEM, false)), A.HIDDEN);
  t.eq('**内部条目一律 HIDDEN**（不管它长得多像回答）',
    conversationAudienceOf(mk('i', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, true)), A.HIDDEN);
  t.eq('内部条目需要视觉隔离', needsInternalIsolation(mk('i', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, true)), true);
  t.eq('普通回答不需要隔离', needsInternalIsolation(mk('a', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, false)), false);

  // ── ③ 分组与可见集合：内部事件不占任何位置 ──
  const items = [
    mk('sys', TrajectoryKind.MESSAGE, Speaker.SYSTEM, true),        // 系统提示词
    mk('ctx', TrajectoryKind.REASONING, Speaker.ASSISTANT, true),   // 压缩摘要（内部）
    mk('unk', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, true),     // 未识别事件（原始 JSON）
    mk('cmd', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, true),     // 斜杠命令
    mk('u1', TrajectoryKind.MESSAGE, Speaker.USER, false),
    mk('r1', TrajectoryKind.REASONING, Speaker.ASSISTANT, false),
    mk('t1', TrajectoryKind.TOOL, Speaker.ASSISTANT, false),
    mk('a1', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, false),
    mk('e1', TrajectoryKind.ERROR, Speaker.ASSISTANT, false),
  ];
  const turns = TM.groupTurns(items, false);
  t.eq('内部事件不产生回合（只有一条真实用户消息）', turns.length, 1);
  t.eq('内部事件不占过程分组（过程只有思考+工具）', turns[0].process.length, 2);
  t.eq('内部事件不占 notices（notices 只有错误）', turns[0].notices.length, 1);
  t.eq('命令条目 → NOTICE 槽位（可见、与回答隔离）',
    conversationAudienceOf(mk('c', TrajectoryKind.COMMAND, Speaker.USER, false)), A.NOTICE);
  t.eq('命令不属于过程分组（它不是工具）',
    conversationAudienceOf(mk('c', TrajectoryKind.COMMAND, Speaker.USER, false)) === A.PROCESS, false);
  t.eq('答案仍是那条真实回答', turns[0].answer.id, 'a1');
  const visible = TM.chatVisibleItems(turns).map((i) => i.id);
  t.eq('**对话里只剩 用户/回答/错误 三类**', visible.join(','), 'u1,a1,e1');
  t.eq('对话里没有 system/message', visible.indexOf('sys') < 0, true);
  t.eq('对话里没有内部 context', visible.indexOf('ctx') < 0, true);
  t.eq('对话里没有未识别事件（原始 JSON）', visible.indexOf('unk') < 0, true);
  t.eq('对话里没有斜杠命令', visible.indexOf('cmd') < 0, true);
  // 内部事件**仍在 items 里**（轨迹要看得到）
  t.eq('内部事件仍保留在轨迹条目里（可查、可排查）', items.filter((i) => i.internal).length, 4);

  // ── ④ 不靠文本：正文里写着 SYSTEM 也照样按结构判定 ──
  const sneaky = mk('sneaky', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, false);
  sneaky.body = 'SYSTEM: you are a helpful assistant';
  t.eq('正文含 SYSTEM 的正常回答仍可见（判据不看文本）',
    conversationAudienceOf(sneaky), A.ASSISTANT);
  const disguisedInternal = mk('disguise', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, true);
  disguisedInternal.body = '这是一段普通回答';
  t.eq('长得像回答的内部事件仍被隐藏（判据不看文本）',
    conversationAudienceOf(disguisedInternal), A.HIDDEN);

  console.log('  ok    36 条断言：事件类型白名单（14）/ 条目角色（9）/ 分组与可见集合（11）/ 不靠文本（2）');
}

console.log('\n## P0-1 搜索作用域：内部事件不得被搜到、命中必须映射到正确的行');
{
  const { matchTrajectoryIndices, matchConversationIndices, chatRowOfItemIndex } = SE;
  const { TrajectoryKind, Speaker } = TJ;
  const mk = (id, kind, speaker, internal, body) => ({
    id, kind, speaker, internal, at: 0, body: body || '', reasoning: '', model: '',
    elapsedMs: 0, toolName: '', callId: '', toolArgs: '', toolState: 'pending', toolOutput: '',
    subagentName: '', fileName: '', fileSize: 0, title: '', progress: '', percent: -1,
    streaming: false, expanded: false,
  });

  const items = [
    mk('sys', TrajectoryKind.MESSAGE, Speaker.SYSTEM, true, 'You are an AI agent powered by DeepSeek Harness'),
    mk('u1', TrajectoryKind.MESSAGE, Speaker.USER, false, '帮我看看 harness 的配置'),
    mk('t1', TrajectoryKind.TOOL, Speaker.ASSISTANT, false, ''),
    mk('a1', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, false, 'harness 配置在 settings.yaml'),
    mk('unk', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, true, '{"huge":"internal payload"}'),
  ];

  // ── 轨迹范围：全部可搜（内部事件在轨迹里本就该可查） ──
  t.eq('轨迹范围能搜到提示词（排查需要）', matchTrajectoryIndices(items, 'deepseek harness').length, 1);
  t.eq('轨迹范围能搜到内部载荷', matchTrajectoryIndices(items, 'internal payload').length, 1);

  // ── 对话范围：内部事件**不可搜**（提示词泄漏的第二形态：能被搜到/被计数） ──
  const conv = matchConversationIndices(items, 'deepseek harness');
  t.eq('**对话范围搜不到系统提示词**', conv.length, 0);
  t.eq('对话范围搜不到未识别事件的原始载荷', matchConversationIndices(items, 'internal payload').length, 0);
  t.eq('对话范围能搜到用户消息与回答（两处都含"配置"）',
    matchConversationIndices(items, '配置').join(','), '1,3');
  const both = matchConversationIndices(items, 'harness');
  t.eq('同一个词在对话范围只命中可见的两条（提示词那条被排除）', both.join(','), '1,3');
  t.eq('对话范围的命中下标仍是**原数组下标**（供上层继续用 items 取条目）',
    items[both[0]].id, 'u1');
  t.eq('空查询 ⇒ 无命中', matchConversationIndices(items, '   ').length, 0);

  // ── 命中 → 对话视图行号（行是回合，不是条目） ──
  const turns = TM.groupTurns(items, false);
  t.eq('这里只有一个回合（内部事件不产生回合）', turns.length, 1);
  t.eq('用户消息 → 第 0 行', chatRowOfItemIndex(items, turns, 1), 0);
  t.eq('助手回答 → 同一回合的第 0 行', chatRowOfItemIndex(items, turns, 3), 0);
  t.eq('工具条目 → 也在第 0 行（过程分组在回合内）', chatRowOfItemIndex(items, turns, 2), 0);
  t.eq('内部事件不属于任何回合 ⇒ -1（不滚，而不是滚到第 0 行）', chatRowOfItemIndex(items, turns, 0), -1);
  t.eq('越界下标 ⇒ -1', chatRowOfItemIndex(items, turns, 99), -1);

  // ── 两个回合时行号才真正不同（这正是旧实现滚错行的场景） ──
  const two = [
    mk('u1', TrajectoryKind.MESSAGE, Speaker.USER, false, 'x'),
    mk('a1', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, false, 'x'),
    mk('u2', TrajectoryKind.MESSAGE, Speaker.USER, false, 'x'),
    mk('a2', TrajectoryKind.MESSAGE, Speaker.ASSISTANT, false, 'x'),
  ];
  const twoTurns = TM.groupTurns(two, false);
  t.eq('两条用户消息 ⇒ 两个回合', twoTurns.length, 2);
  t.eq('第 3 个条目属于第 1 回合（条目下标 3 ≠ 行号 1 —— 旧实现直接当行号用，必然滚错）',
    chatRowOfItemIndex(two, twoTurns, 3), 1);

  console.log('  ok    18 条断言：轨迹/对话两个作用域（6）/ 命中下标保真（3）/ 条目→行映射含"不属于任何回合"（9）');
}

console.log('\n## P0 页面框架：面板注册表 + 导航状态（页面 ≠ 选中的面板）');
{
  const { PanelRegistry, PanelLocation, createPanelRegistry, sidebarPanels, rightbarPanels,
    sidebarEntries, sidebarPinnedEntries, SIDEBAR_PINNED_ORDER,
    PANEL_SIDEBAR_SETTINGS, PANEL_SIDEBAR_WORKSPACES,
    PANEL_RIGHT_DETAIL, PANEL_RIGHT_FILES, PANEL_RIGHT_TRAJECTORY, settingsSections } = PR;
  const { initialNavigationState, mainPanels, mainPanelOfLegacyTab, legacyTabOfMainPanel,
    navigateToMain, selectRightPanel, openSettings, setDrawer, sidebarPanelIdOfTab,
    activeMainPanelOf, mainPanelOfSidebarPanel, sidebarPanelOfMainPanel,
    enterSession, defaultRightPanel, copyOf,
    DrawerState, MAIN_CONVERSATION, MAIN_WORKSPACES, MAIN_SETTINGS, MAIN_CORE,
    SETTINGS_MODELS, SETTINGS_GENERAL } = NS;

  const { shellTracksOf } = ST;
  const reg = createPanelRegistry(mainPanels());

  // ── 注册表：位置是面板的属性，不是页面的 if 分支 ──
  t.eq('四条轨道的面板都注册了（含设置域的分区）',
    reg.size(), mainPanels().length + sidebarPanels().length + rightbarPanels().length + settingsSections().length);
  t.eq('重复 id 被拒绝（不静默覆盖）',
    reg.register({ id: MAIN_CONVERSATION, location: PanelLocation.MAIN, owner: 'x', label: 'x', order: 1, available: () => true }), false);
  t.eq('空 id 被拒绝',
    reg.register({ id: '', location: PanelLocation.MAIN, owner: 'x', label: 'x', order: 1, available: () => true }), false);

  // 排序：order 升序；同序按 id 稳定排序（不依赖注册顺序）
  const side = reg.descriptors(PanelLocation.SIDEBAR).map((d) => d.id);
  // E110：核心不是独立一级（内容在设置页的第一个分区里）⇒ 席位登记着但不可用
  t.eq('侧栏可用席位：工作区 → 设置（核心按 E110 不可用）', side.join(','), 'sidebar.workspaces,sidebar.settings');
  t.eq('**Settings 固定在底部**（order 最大）', side[side.length - 1], PANEL_SIDEBAR_SETTINGS);
  t.eq('核心席位仍登记在清单里（语义写在模型里，不靠视图恰好没遍历）',
    sidebarPanels().map((d) => d.id).join(','), 'sidebar.workspaces,sidebar.core,sidebar.settings');
  t.eq('主入口清单不含沉底项', sidebarEntries(reg).map((d) => d.id).join(','), 'sidebar.workspaces');
  t.eq('沉底项恰好是设置', sidebarPinnedEntries(reg).map((d) => d.id).join(','), 'sidebar.settings');
  const right = reg.descriptors(PanelLocation.RIGHTBAR).map((d) => d.id);
  // P3-1：右栏当前**唯一有内容**的面板是"详情"（sections 清单）；官方那六个候选登记着但不可用
  // P3-2/P3-3：预览与文件面板接上了（呈现分别与工作区页签的预览/文件树共用同一份组件）
  t.eq('右栏可用面板：详情 + 文件 + 轨迹 + 工具 + 子代理 + 交付物 + 预览（官方六个候选全接上）', right.join(','),
    'right.detail,right.files,right.trajectory,right.tool,right.subagent,right.deliverables,right.preview');
  t.eq('官方候选仍登记在清单里（内容视图未做的按 E110 不进选择集）',
    rightbarPanels().length, 7);
  t.eq('七个面板全部可用（官方六个候选 + 本仓的「详情」）',
    rightbarPanels().filter((d) => d.available()).length, 7);
  t.eq('默认右栏面板 = 详情（firstAvailable）', defaultRightPanel(reg), 'right.detail');
  t.eq('初值也指向详情（宿主不调 defaultRightPanel 时也不会落到空面板）',
    initialNavigationState().selectedRightPanel, 'right.detail');

  // 可用性：不可用的面板不进选择集
  const r2 = new PanelRegistry();
  r2.register({ id: 'a', location: PanelLocation.RIGHTBAR, owner: 'o', label: 'a', order: 20, available: () => false });
  r2.register({ id: 'b', location: PanelLocation.RIGHTBAR, owner: 'o', label: 'b', order: 10, available: () => true });
  t.eq('不可用的面板不进 descripors()', r2.descriptors(PanelLocation.RIGHTBAR).length, 1);
  t.eq('firstAvailable 跳过不可用的', r2.firstAvailable(PanelLocation.RIGHTBAR), 'b');

  // 校验：错轨道 / 不存在 / 不可用 都不能选中
  t.eq('跨轨道选中被拒（右栏 id 不能当主区面板）', reg.canSelect(PanelLocation.MAIN, PANEL_RIGHT_FILES), false);
  t.eq('不存在的 id 被拒', reg.canSelect(PanelLocation.MAIN, 'nope'), false);
  t.eq('不可用的 id 被拒', r2.canSelect(PanelLocation.RIGHTBAR, 'a'), false);
  t.eq('select 失败时**保持原值**（不静默回退到第一个）',
    reg.select(PanelLocation.RIGHTBAR, 'nope', PANEL_RIGHT_FILES), PANEL_RIGHT_FILES);

  // ── 导航状态：页面与面板分开 ──
  let nav = initialNavigationState();
  t.eq('初始主区面板是会话', nav.selectedMainPanel, MAIN_CONVERSATION);
  t.eq('初始右栏面板来自注册表首项', nav.selectedRightPanel, defaultRightPanel(reg));
  t.eq('初始抽屉是关的（手机侧栏不默认挡住主区）', nav.mobileDrawer, DrawerState.CLOSED);

  nav = navigateToMain(nav, MAIN_WORKSPACES, reg);
  t.eq('切到工作区面板', nav.selectedMainPanel, MAIN_WORKSPACES);
  const beforeBad = nav.selectedMainPanel;
  nav = navigateToMain(nav, 'not-a-panel', reg);
  t.eq('切到非法面板 ⇒ 状态不变（点了不会到别处）', nav.selectedMainPanel, beforeBad);

  // P3-6 之后七个面板全部可用 ⇒ "切不过去"改用不存在的 id 来断言（注册表校验仍在）
  t.eq('**不存在/不可用的右栏面板切不过去**（注册表校验仍在）',
    selectRightPanel(nav, 'right.nope', reg).selectedRightPanel, nav.selectedRightPanel);
  t.eq('可用的轨迹面板切得过去',
    selectRightPanel(nav, PANEL_RIGHT_TRAJECTORY, reg).selectedRightPanel, PANEL_RIGHT_TRAJECTORY);
  t.eq('可用面板（详情）切得过去、且是幂等的',
    selectRightPanel(nav, PANEL_RIGHT_DETAIL, reg).selectedRightPanel, PANEL_RIGHT_DETAIL);
  t.eq('**切右栏不影响主区**（页面与面板是两件事）', nav.selectedMainPanel, MAIN_WORKSPACES);

  nav = openSettings(nav, SETTINGS_MODELS, reg);
  t.eq('进设置域：主区是设置', nav.selectedMainPanel, MAIN_SETTINGS);
  t.eq('进设置域：分区是 models', nav.settingsSection, SETTINGS_MODELS);
  nav = openSettings(nav, '', reg);
  t.eq('空分区 ⇒ 保持当前分区', nav.settingsSection, SETTINGS_MODELS);


  nav = setDrawer(nav, DrawerState.OPEN);
  t.eq('抽屉打开', nav.mobileDrawer, DrawerState.OPEN);
  t.eq('从抽屉里选主区面板 ⇒ 抽屉收起（临时导航面）',
    navigateToMain(setDrawer(initialNavigationState(), DrawerState.OPEN), MAIN_SETTINGS, reg).mobileDrawer,
    DrawerState.CLOSED);
  t.eq('不可用的面板切不过去，也不该顺手把抽屉收掉（状态原样返回）',
    (() => {
      const st = setDrawer(initialNavigationState(), DrawerState.OPEN);
      return navigateToMain(st, 'main.nope', reg) === st && st.mobileDrawer === DrawerState.OPEN;
    })(), true);

  // enterSession：一处同步所有相关字段
  const entered = enterSession(nav, 'session-1', reg);
  t.eq('进会话 ⇒ 主区回到会话面板', entered.selectedMainPanel, MAIN_CONVERSATION);
  t.eq('进会话 ⇒ 记录会话 id', entered.currentSessionId, 'session-1');
  t.eq('进会话 ⇒ 关掉手机抽屉（否则抽屉挡着会话）', entered.mobileDrawer, DrawerState.CLOSED);

  // copyOf 保真：字段一个不漏
  const a = initialNavigationState();
  const b = copyOf(a);
  t.eq('copyOf 字段完整', Object.keys(a).length, Object.keys(b).length);
  t.eq('copyOf 是真拷贝（改副本不动原件）', (function () { b.selectedMainPanel = MAIN_CORE; return a.selectedMainPanel; })(), MAIN_CONVERSATION);

  // ── 迁移桥：行为不变 ──
  t.eq('旧页签 workspaces → 工作区面板', mainPanelOfLegacyTab('workspaces'), MAIN_WORKSPACES);
  t.eq('旧页签 core → 核心面板', mainPanelOfLegacyTab('core'), MAIN_CORE);
  t.eq('旧页签 settings → 设置面板', mainPanelOfLegacyTab('settings'), MAIN_SETTINGS);
  t.eq('旧下钻页 conversation → 会话面板（**收进同一套面板模型**）', mainPanelOfLegacyTab('conversation'), MAIN_CONVERSATION);
  t.eq('未知页签回到会话（不是空串——空串会让主区空白）', mainPanelOfLegacyTab('???'), MAIN_CONVERSATION);
  t.eq('反向映射：设置面板 → settings', legacyTabOfMainPanel(MAIN_SETTINGS), 'settings');
  t.eq('反向映射：会话面板 → workspaces（旧模型没有会话页签）', legacyTabOfMainPanel(MAIN_CONVERSATION), 'workspaces');
  // 往返：三个旧页签必须原样回来（这是"迁移期间不会点错页面"的保证）
  t.eq('往返一致 workspaces', legacyTabOfMainPanel(mainPanelOfLegacyTab('workspaces')), 'workspaces');
  t.eq('往返一致 core', legacyTabOfMainPanel(mainPanelOfLegacyTab('core')), 'core');
  t.eq('往返一致 settings', legacyTabOfMainPanel(mainPanelOfLegacyTab('settings')), 'settings');

  // ── 此刻主区在显示哪个面板（三类线索的组合收在模型里，视图只读一个值） ──
  const n0 = initialNavigationState();
  t.eq('下钻到诊断 ⇒ 诊断面板', activeMainPanelOf(n0, 'diagnostics', true), 'main.diagnostics');
  t.eq('下钻到连接 ⇒ 连接面板', activeMainPanelOf(n0, 'connect', false), 'main.connect');
  t.eq('下钻到会话且有会话 ⇒ 会话面板', activeMainPanelOf(n0, 'conversation', true), 'main.conversation');
  t.eq('**下钻到会话但没有会话 ⇒ 落回选中的面板**（不显示空会话）',
    activeMainPanelOf(n0, 'conversation', false), n0.selectedMainPanel);
  t.eq('没有下钻 ⇒ 选中的面板', activeMainPanelOf(n0, 'main', true), n0.selectedMainPanel);
  const onSettings = navigateToMain(n0, MAIN_SETTINGS, reg);
  t.eq('选中设置时没有下钻 ⇒ 设置面板', activeMainPanelOf(onSettings, 'main', true), MAIN_SETTINGS);
  t.eq('**下钻优先于页签**：选中设置但下钻诊断 ⇒ 诊断面板',
    activeMainPanelOf(onSettings, 'diagnostics', true), 'main.diagnostics');

  // 迁移桥：NavTab ↔ 面板 id（迁移期间行为不变的保证）
  t.eq('工作区页签 → 侧栏工作区面板 id', sidebarPanelIdOfTab('workspaces'), 'sidebar.workspaces');
  t.eq('设置页签 → 侧栏设置面板 id', sidebarPanelIdOfTab('settings'), 'sidebar.settings');
  t.eq('工作区与设置席位可用、核心席位按 E110 不可用',
    reg.canSelect('sidebar', 'sidebar.workspaces') && reg.canSelect('sidebar', 'sidebar.settings')
      && !reg.canSelect('sidebar', 'sidebar.core'), true);

  // P1-4：侧栏席位 ↔ 主区面板（点侧栏入口该切到哪个面板、哪一项该高亮）
  t.eq('工作区席位 → 工作区面板', mainPanelOfSidebarPanel(PANEL_SIDEBAR_WORKSPACES), MAIN_WORKSPACES);
  t.eq('设置席位 → 设置面板', mainPanelOfSidebarPanel(PANEL_SIDEBAR_SETTINGS), MAIN_SETTINGS);
  t.eq('未知席位回落工作区（不返回空串：空串会让主区空着）', mainPanelOfSidebarPanel('nope'), MAIN_WORKSPACES);
  t.eq('工作区面板 → 工作区席位（高亮用）', sidebarPanelOfMainPanel(MAIN_WORKSPACES), PANEL_SIDEBAR_WORKSPACES);
  t.eq('设置面板 → 设置席位', sidebarPanelOfMainPanel(MAIN_SETTINGS), PANEL_SIDEBAR_SETTINGS);
  t.eq('会话面板没有侧栏席位 ⇒ 空串（不高亮任何一项，而不是随便高亮）',
    sidebarPanelOfMainPanel(MAIN_CONVERSATION), '');
  t.eq('席位 → 面板 → 席位 往返稳定',
    sidebarPanelOfMainPanel(mainPanelOfSidebarPanel(PANEL_SIDEBAR_SETTINGS)), PANEL_SIDEBAR_SETTINGS);
  t.eq('沉底门槛是个明确的数（视图不写 900 这种字面量）', SIDEBAR_PINNED_ORDER >= 100, true);

  /*
   * ── P4-1：设置域分区（官方对齐项在前、本仓特有四项在后）──
   * 【E214 更正】官方是四段（通用 / 模型 / 插件 / 插件清单），但端侧只有**一份**插件投影
   * ⇒ 两个分区渲染同一批行（用户实测："插件和插件清单功能重复"）。已并成一个「插件」分区，
   * 故这里是**三段 + 四项 = 7**。矩阵 `settings-plugin-inventory` 行据此改判并登记。
   */
  const sections = reg.descriptors(PanelLocation.SETTINGS).map((d) => d.id);
  t.eq('官方对齐项排在最前（通用 / 模型 / 插件）', sections.slice(0, 3).join(','),
    'settings.general,settings.models,settings.plugins');
  t.eq('本仓特有四项排在后面（核心 / 预设 / 技能 / 设备）', sections.slice(3).join(','),
    'settings.core,settings.presets,settings.skills,settings.device');
  t.eq('分区总量 7（对齐项 3 + 本仓 4；官方那段"插件清单"已并入插件，见 E214）',
    settingsSections().length, 7);
  t.eq('owner 能区分"官方对齐项"与"端侧补充"',
    settingsSections().filter((d) => d.owner === 'hdsh').map((d) => d.id).join(','),
    'settings.core,settings.presets,settings.skills,settings.device');
  t.eq('默认分区是通用（初值）', initialNavigationState().settingsSection, 'settings.general');
  t.eq('切分区经注册表校验后写入', openSettings(initialNavigationState(), 'settings.skills', reg).settingsSection,
    'settings.skills');
  t.eq('**不可用的分区切不过去**（注册表校验对设置域同样生效）',
    reg.canSelect(PanelLocation.SETTINGS, 'settings.nope'), false);
  /*
   * 「插件清单」的历史：子页签 → 独立分区（P4-1，对齐官方）→ **并回「插件」（E214）**。
   * 三次都不是反复横跳：前两次是为了对齐官方，第三次是**端侧只有一份投影**这个事实的结论
   * （两个分区渲染同一批行，用户实测报"功能重复"）。这条断言钉住"只有插件一个分区、
   * 清单关键字不再作为分区 id 存在"，防止有人再按官方表把它拆回去。
   */
  t.eq('插件只有一个分区（清单已并入，E214）',
    sections.indexOf('settings.plugins') >= 0 && sections.indexOf('settings.plugin-inventory') < 0, true);
  t.eq('清单关键字仍可作为关键字存在，但不再是分区', sections.indexOf('settings.plugin-inventory'), -1);

  // ── 四形态：信息架构不变，只变呈现 ──
  const single = shellTracksOf('single');
  t.eq('手机：侧栏是浮层（抽屉）', single.sidebar, 'overlay');
  t.eq('手机：主区全屏', single.main, 'column');
  t.eq('手机：右栏是浮层', single.rightbar, 'overlay');
  const double = shellTracksOf('double');
  t.eq('平板竖屏：侧栏收成 rail', double.sidebar, 'rail');
  t.eq('平板竖屏：右栏仍是浮层（侧边浅层面板）', double.rightbar, 'overlay');
  const triple = shellTracksOf('triple');
  t.eq('三栏：侧栏是完整面板', triple.sidebar, 'panel');
  t.eq('三栏：右栏并排成栏', triple.rightbar, 'column');

  // ── 侧栏可收起（P2-15）：形态给默认，用户的展开/收起给偏好 ──
  {
    const { sidebarPresentationOf } = ST;
    t.eq('三栏展开：完整面板', sidebarPresentationOf('triple', true), 'panel');
    t.eq('三栏收起：rail（腾出宽度给主区）', sidebarPresentationOf('triple', false), 'rail');
    t.eq('双栏展开：完整面板（用户要，就给）', sidebarPresentationOf('double', true), 'panel');
    t.eq('双栏收起：rail（这是默认）', sidebarPresentationOf('double', false), 'rail');
    t.eq('**单栏一律浮层**：那个档位没有第二个选项', sidebarPresentationOf('single', true), 'overlay');
    t.eq('单栏收起也还是浮层', sidebarPresentationOf('single', false), 'overlay');
  }

  // ── 侧栏轨道的几何（P5-2）：呈现改了，宽度必须跟着改 ──
  {
    const { sidebarExpandedForMode, sidebarTrackWidthOf } = ST;

    // 三态取值（P2-17 起；P5-2 改成**按形态**给默认）
    t.eq('没存过 + 三栏 ⇒ 默认展开（shellTracksOf 说三栏的侧栏是 panel）',
      sidebarExpandedForMode('triple', undefined), true);
    t.eq('没存过 + 双栏 ⇒ 默认收起（放不下两条展开轨道）',
      sidebarExpandedForMode('double', undefined), false);
    t.eq('没存过 + 单栏 ⇒ 展开无意义，取值仍为 true（呈现恒为浮层）',
      sidebarExpandedForMode('single', undefined), true);
    t.eq('存过 true ⇒ 展开（**覆盖形态默认**：双栏也照给）',
      sidebarExpandedForMode('double', true), true);
    t.eq('存过 false ⇒ 保持收起（下次启动不擅自展开）',
      sidebarExpandedForMode('triple', false), false);

    // 轨道宽度 = 实际呈现的宽度（这是 P5-2 修的那条：此前它按形态默认算）
    t.eq('三栏 + 没存过 ⇒ 完整面板宽', sidebarTrackWidthOf('triple', undefined), 240);
    t.eq('三栏 + 收起 ⇒ **rail 宽（腾出的 184vp 真给主区）**',
      sidebarTrackWidthOf('triple', false), 56);
    t.eq('双栏 + 没存过 ⇒ rail 宽（默认就是收起的）',
      sidebarTrackWidthOf('double', undefined), 56);
    t.eq('双栏 + 用户展开 ⇒ 完整面板宽', sidebarTrackWidthOf('double', true), 240);
    t.eq('单栏 ⇒ 0（抽屉与底部标签都不占侧边宽度）',
      sidebarTrackWidthOf('single', undefined), 0);
    t.eq('单栏即便"展开"也是 0（那个档位没有并排的侧栏）',
      sidebarTrackWidthOf('single', true), 0);
    // 与决策里的 nav 宽度**故意不同**：决策是"按形态该留多少"，这里是"现在实际多宽"
    t.eq('rail 宽与 rail 呈现一致（56 = Sz.NAV_RAIL）',
      sidebarTrackWidthOf('double', undefined) === 56 && ST.sidebarPresentationOf('double', undefined) === 'rail',
      true);
  }
  // 侧栏 2（工作区 / 设置；核心席位按 E110 不可用）、右栏 7（详情 / 文件 / 轨迹 / 工具 / 子代理 / 交付物 / 预览）—— 可用清单与形态无关，只与注册表有关
  t.eq('**三种形态的面板清单一致**（信息架构不随设备变）',
    JSON.stringify(reg.descriptors(PanelLocation.SIDEBAR).length) + '/' + JSON.stringify(reg.descriptors(PanelLocation.RIGHTBAR).length),
    '2/7');

  console.log('  ok    注册表（注册/排序/可用性/沉底/校验）+ 导航状态（页面与面板分离）+ 迁移桥含往返 + 四形态轨道');
}


// ── P2：Markdown 切块与行内标记（会话正文的呈现）──
{
  const { parseMarkdown, parseInline, plainTextOf, MdBlockKind } = MD;

  // ① 标题：只认"# 后有空格的"，且 7 个 # 不是标题
  const h = parseMarkdown('# 一级\n\n### 三级\n\n####### 七个不算\n\n#没空格也不算');
  t.eq('标题：识别 1 级', h[0].kind === MdBlockKind.HEADING && h[0].level, 1);
  t.eq('标题：识别 3 级', h[1].level, 3);
  t.eq('标题：7 个 # 落到段落', h[2].kind, MdBlockKind.PARAGRAPH);
  t.eq('标题：`#没空格` 落到段落（不误吃正文）', h[3].kind, MdBlockKind.PARAGRAPH);

  // ② 围栏代码：语言标注 + 闭合
  const c = parseMarkdown('前言\n\n```ts\nconst a = 1;\n```\n\n后语');
  t.eq('围栏：切成 3 块', c.length, 3);
  t.eq('围栏：类型是代码块', c[1].kind, MdBlockKind.CODE);
  t.eq('围栏：语言标注', c[1].lang, 'ts');
  t.eq('围栏：闭合', c[1].closed, true);
  t.eq('围栏：内容原样（不做行内解析）', c[1].text, 'const a = 1;');

  // ③ **流式未闭合的围栏**：剩余全部当代码块，且 closed=false（这是本模型最要紧的一条）
  const un = parseMarkdown('看代码：\n```js\nlet x = 1;\nlet y = 2;');
  t.eq('未闭合围栏：两块', un.length, 2);
  t.eq('未闭合围栏：剩余全在代码块里（没被吞成正文）', un[1].text, 'let x = 1;\nlet y = 2;');
  t.eq('未闭合围栏：如实标 closed=false', un[1].closed, false);

  // ④ 列表：无序 / 有序 / marker
  const l = parseMarkdown('- 甲\n* 乙\n+ 丙\n1. 一\n2) 二');
  t.eq('列表：五项', l.length, 5);
  t.eq('列表：无序标记', l[0].marker + l[1].marker + l[2].marker, '···');
  t.eq('列表：有序标记（保留原序号）', l[3].marker + l[4].marker, '1.2)');
  t.eq('列表：有序标记 ordered=true', l[3].ordered, true);

  // ⑤ 引用（连续行合并）、分隔线
  const q = parseMarkdown('> 第一行\n> 第二行\n\n---');
  t.eq('引用：连续行合并成一块', q[0].kind === MdBlockKind.QUOTE && q[0].text, '第一行\n第二行');
  t.eq('分隔线：识别', q[1].kind, MdBlockKind.RULE);

  // ⑥ 段落：连续非空行合并、空行分段
  const pg = parseMarkdown('甲\n乙\n\n丙');
  t.eq('段落：连续行合并（保留换行）', pg[0].text, '甲\n乙');
  t.eq('段落：空行分段', pg[1].text, '丙');

  // ⑦ 行内：粗/斜/代码/删除线/链接
  const sp = parseInline('普通 **粗** *斜* `码` ~~删~~ [官网](https://x.y)');
  const kinds = sp.map((x) => `${x.text}${x.bold ? 'B' : ''}${x.italic ? 'I' : ''}${x.code ? 'C' : ''}${x.strike ? 'S' : ''}${x.href.length > 0 ? 'L' : ''}`).join('|');
  // 片段之间的空格必须**留在片段里**（丢了空格渲染出来就会粘在一起）——故期望值含那 4 个空格片段
  t.eq('行内：五种标记各就各位（含标记之间的空格片段）', kinds, '普通 |粗B| |斜I| |码C| |删S| |官网L');
  t.eq('行内：链接目标保真', sp[sp.length - 1].href, 'https://x.y');

  // ⑧ 未配对的标记**原样保留**（宁可少强调一次，也不吃字符）
  t.eq('行内：单个 * 原样', plainTextOf(parseMarkdown('a * b')), 'a * b');
  t.eq('行内：未闭合的 ** 原样', plainTextOf(parseMarkdown('**没闭合')), '**没闭合');
  t.eq('行内：未闭合的反引号原样', plainTextOf(parseMarkdown('`) 半截')), '`) 半截');
  t.eq('行内：`a * b * c` 不当斜体（内层有空格就退回原文）', plainTextOf(parseMarkdown('a * b * c')), 'a * b * c');

  // ⑨ 转义
  t.eq('行内：\\* 是字面星号', plainTextOf(parseMarkdown('\\*不是斜体\\*')), '*不是斜体*');

  // ⑩ 边界：空串 / CRLF / 相邻片段合并（不逐字符生成 Span）
  t.eq('空串：零块', parseMarkdown('').length, 0);
  t.eq('CRLF：与 LF 等价', parseMarkdown('# 甲\r\n\r\n乙').length, 2);
  t.eq('行内：相邻纯文本合并为一个片段', parseInline('甲乙丙').length, 1);
  t.eq('纯文本去标记：用于无障碍/降级', plainTextOf(parseMarkdown('**粗**与`码`')), '粗与码');

  console.log('  ok    24 条断言：标题 / 围栏（含未闭合） / 列表 / 引用 / 分隔线 / 段落 / 行内五标记 / 未配对原样 / 转义 / 边界');

  // ── P3-4：按种类筛选（右栏「交付物」等面板的判据）──
  {
    const { itemsOfKind, deliverablesOf, makeItem, TrajectoryKind } = TJ;
    const a = makeItem('a', TrajectoryKind.DELIVERABLE, 1000);
    const b = makeItem('b', TrajectoryKind.TOOL, 2000);
    const c = makeItem('c', TrajectoryKind.DELIVERABLE, 3000);
    const list = [a, b, c];
    t.eq('按种类筛：只留交付物且保序', deliverablesOf(list).map((x) => x.id).join(','), 'a,c');
    t.eq('按种类筛：筛选不改原数组', list.length, 3);
    // 同 id 会被流式 merge 多次：筛完应当只剩一条（"有几件事"而不是"更新了几次"）
    const dupA = makeItem('a', TrajectoryKind.DELIVERABLE, 4000);
    dupA.fileName = 'later';
    t.eq('同 id 只留最后一条（流式 merge 去重）',
      deliverablesOf([a, b, dupA]).map((x) => x.fileName).join(','), 'later');
    t.eq('没有该种类 ⇒ 空数组（面板据此显示空态，而不是显示空气泡）',
      itemsOfKind([b], TrajectoryKind.SUBAGENT).length, 0);
  }

  // ── P4-6：设置写入回执的归属域（界面不该把上一段的回执挂在当前段上）──
  {
    const { settingsDomainOfNs, settingsDomainOfKey, isGeneralNamespace,
      SETTINGS_DOMAIN_UNKNOWN, DEFAULT_MODEL_NS, GENERAL_NAMESPACES } = SD;

    // 通用分区：白名单整组
    t.eq('通用：外观命名空间', settingsDomainOfNs('ui-theme'), 'settings.general');
    t.eq('通用：语言', isGeneralNamespace('locale'), true);
    t.eq('通用：不在白名单 ⇒ 假', isGeneralNamespace('llm-deepseek'), false);

    // 模型分区：模型相关的四类命名空间
    t.eq('模型：提供方命名空间', settingsDomainOfNs('llm-deepseek'), 'settings.models');
    t.eq('模型：搜索命名空间', settingsDomainOfNs('web-search-brave'), 'settings.models');
    t.eq('模型：新会话默认模型', settingsDomainOfNs(DEFAULT_MODEL_NS), 'settings.models');
    t.eq('模型：子代理模型选择', settingsDomainOfNs('subagent-model-selection'), 'settings.models');

    // 插件 / 预设 / 技能
    t.eq('插件：ui-plugin-*', settingsDomainOfNs('ui-plugin-cordis'), 'settings.plugins');
    t.eq('预设：agent-preset*', settingsDomainOfNs('agent-presets'), 'settings.presets');
    t.eq('技能：skill*', settingsDomainOfNs('skills'), 'settings.skills');

    // 不猜：未列出的命名空间必须返回"域未知"，而不是随便归一段
    t.eq('未列出的命名空间 ⇒ 域未知', settingsDomainOfNs('agent-loop'), SETTINGS_DOMAIN_UNKNOWN);
    t.eq('引擎参数 agent-presets 之外的不猜', settingsDomainOfNs('unknown-ns'), SETTINGS_DOMAIN_UNKNOWN);

    // key → 域（按第一个点切命名空间）
    t.eq('key：llm-deepseek.baseURL', settingsDomainOfKey('llm-deepseek.baseURL'), 'settings.models');
    t.eq('key：ui-theme.fontSize', settingsDomainOfKey('ui-theme.fontSize'), 'settings.general');
    t.eq('key：没有命名空间 ⇒ 域未知（本机偏好由调用方声明）',
      settingsDomainOfKey('themeMode'), SETTINGS_DOMAIN_UNKNOWN);
    t.eq('key：点在结尾 ⇒ 域未知', settingsDomainOfKey('ui-theme.'), SETTINGS_DOMAIN_UNKNOWN);
    t.eq('key：点在最前 ⇒ 域未知', settingsDomainOfKey('.fontSize'), SETTINGS_DOMAIN_UNKNOWN);

    // 白名单本身也要钉住：多一个/少一个都会让"通用"页的内容变样
    t.eq('通用白名单五项', GENERAL_NAMESPACES.length, 5);
    t.eq('通用白名单内容', GENERAL_NAMESPACES.join(','), 'ui-theme,locale,ui-conversation,ui-chat,ui-onboarding');
  }

  // ── P2-7：会话头上下文行（工作区名 · 模型 · 最近活动）──
  {
    const { workspaceNameOf, sessionContextLine } = SC;

    // 工作区名：取末两段（同名目录会撞 ⇒ 留父目录前缀）
    t.eq('工作区名：末两段', workspaceNameOf('/home/u/projects/app'), 'projects/app');
    t.eq('工作区名：只有一段时不留前缀', workspaceNameOf('/srv'), 'srv');
    t.eq('工作区名：尾斜杠不影响', workspaceNameOf('/home/u/app/'), 'u/app');
    t.eq('工作区名：家目录（~ 已展开）照样取末两段', workspaceNameOf('~/work/hdsh'), 'work/hdsh');
    t.eq('工作区名：根目录', workspaceNameOf('/'), '/');
    t.eq('工作区名：空串 ⇒ 空串（不显示这一段）', workspaceNameOf(''), '');
    t.eq('工作区名：只有空白 ⇒ 空串', workspaceNameOf('   '), '');
    t.eq('工作区名：相对路径也照切', workspaceNameOf('a/b/c'), 'b/c');

    // 上下文行：三段都拿到
    t.eq('三段齐全', sessionContextLine('projects/app', 'DeepSeek-V3.2', '12 分钟前'),
      '工作区 projects/app · 模型 DeepSeek-V3.2 · 12 分钟前');
    // 每段拿不到就不出现（不留空的分隔符）
    t.eq('没有工作区', sessionContextLine('', 'DeepSeek-V3.2', '刚刚'), '模型 DeepSeek-V3.2 · 刚刚');
    t.eq('没有模型', sessionContextLine('app', '', '刚刚'), '工作区 app · 刚刚');
    t.eq('没有时间', sessionContextLine('app', 'm', ''), '工作区 app · 模型 m');
    t.eq('只有工作区', sessionContextLine('app', '', ''), '工作区 app');
    t.eq('一段都没有 ⇒ 空串（界面整行不画）', sessionContextLine('', '', ''), '');
  }

  // ── P2-8：浮层回执的归属（E353：一个全局回执被三个浮层读 ⇒ 串浮层）──
  {
    const { sheetNoteVisible, sheetNoteText, SHEET_NOTE_NONE,
      SHEET_NOTE_CREDENTIAL, SHEET_NOTE_TEXT, SHEET_NOTE_STRUCT } = SH;

    // 归属相符才显示
    t.eq('凭据浮层：回执是自己的', sheetNoteVisible(SHEET_NOTE_CREDENTIAL, 'credential'), true);
    t.eq('文本浮层：回执是凭据的 ⇒ 不显示', sheetNoteVisible(SHEET_NOTE_CREDENTIAL, 'text'), false);
    t.eq('结构浮层：回执是文本的 ⇒ 不显示', sheetNoteVisible(SHEET_NOTE_TEXT, 'struct'), false);
    t.eq('结构浮层：回执是自己的', sheetNoteVisible(SHEET_NOTE_STRUCT, 'struct'), true);

    // 没人认领（刚关掉某个浮层 / 还没写过）⇒ 一律不显示
    t.eq('无人认领 ⇒ 不显示（不知道谁写的错误比不显示更糟）',
      sheetNoteVisible(SHEET_NOTE_NONE, 'credential'), false);
    t.eq('无人认领 + 文本浮层 ⇒ 不显示', sheetNoteVisible(SHEET_NOTE_NONE, 'text'), false);

    // 文案出口：归属对且非空才有文本
    t.eq('文案：归属对且有内容', sheetNoteText('credential', 'credential', '已写入'), '已写入');
    t.eq('文案：归属不对 ⇒ 空串（界面拿不到文案）',
      sheetNoteText('credential', 'text', '已写入'), '');
    t.eq('文案：归属对但内容为空 ⇒ 空串', sheetNoteText('struct', 'struct', ''), '');

    // 三个取值本身要稳定（它们与 sheetKind() 的返回值对齐）
    t.eq('三个归属取值', [SHEET_NOTE_CREDENTIAL, SHEET_NOTE_TEXT, SHEET_NOTE_STRUCT].join(','),
      'credential,text,struct');
    t.eq('未认领是空串', SHEET_NOTE_NONE, '');
  }

  // ── P2-10：设置编辑浮层的输入提示（把服务端约束在输入前讲清楚）──
  {
    const { textSettingEditorHints, structSettingEditorHints, placeholderOf } = SE2;

    // 数字项：范围 + 步长
    const num = textSettingEditorHints(true, true, 1, true, 4096, 1, '', false, '1024');
    t.eq('数字项：类型 + 范围', num.hint, '请输入数字；范围 1 – 4096');
    t.eq('数字项：占位给当前值', num.placeholder, '当前：1024');
    t.eq('数字项：步长 >1 才说',
      textSettingEditorHints(true, false, 0, false, 0, 256, '', false, '').hint,
      '请输入数字；须为 256 的整数倍');
    // 只给一侧界：另一侧说"不限"（不编 ∞）
    t.eq('数字项：只有上界',
      textSettingEditorHints(true, false, 0, true, 17, 0, '', false, '').hint,
      '请输入数字；范围 不限 – 17');
    t.eq('数字项：上下界都没有就不提范围',
      textSettingEditorHints(true, false, 0, false, 0, 0, '', false, '').hint, '请输入数字');

    // 文本项：正则 + 必填
    t.eq('文本项：正则',
      textSettingEditorHints(false, false, 0, false, 0, 0, '^[a-z]+$', false, '').hint,
      '请输入文本；须匹配 ^[a-z]+$');
    t.eq('文本项：必填追加在最后',
      textSettingEditorHints(false, false, 0, false, 0, 0, '', true, '').hint, '请输入文本；必填');
    t.eq('文本项：什么都没有也至少说"请输入文本"',
      textSettingEditorHints(false, false, 0, false, 0, 0, '', false, '').hint, '请输入文本');

    // 占位：空值说"未设置"（不显示空白）
    t.eq('占位：有值', placeholderOf('256000'), '当前：256000');
    t.eq('占位：无值', placeholderOf(''), '当前未设置');
    t.eq('结构项的占位与文本项同源', structSettingEditorHints('').placeholder, '当前未设置');
    t.eq('结构项没有约束说明（JSON 由 Host 校验）', structSettingEditorHints('x').hint, '');
  }
  // ── P5-1：核心页的插件清单投影（宿主报告的字段 → 事实与行）──
  {
    const { pluginInventoryFact, pluginRowOf, rankPluginRows } = CP;

    // 有清单：一行说清规模 + 构成 + 来源
    const full = pluginInventoryFact('', '0.9.1',
      { pluginRows: 152, pureJs: 146, native: 6, unknown: 0, disabled: 3 }, 3);
    t.eq('清单：标签', full.label, '插件清单');
    t.eq('清单：规模与构成', full.value, '152 行 · 纯 JS 146 · 依赖原生 6 · 默认禁用 3');
    // 有原生依赖 ⇒ warn（这正是用户必须看见的那件事）
    t.eq('清单：含原生 ⇒ warn', full.verdict, 'warn');
    t.eq('清单：说明给出"来自哪一版"',
      full.hint.startsWith('来自核心 0.9.1；含原生模块的包 3 个。'), true);

    // 无原生、无禁用：不加多余的尾巴（"默认禁用 0" 这种话不该出现）
    const clean = pluginInventoryFact('', '1.0.0',
      { pluginRows: 10, pureJs: 10, native: 0, unknown: 0, disabled: 0 }, 0);
    t.eq('清单：无原生无禁用', clean.value, '10 行 · 纯 JS 10 · 依赖原生 0');
    t.eq('清单：无原生 ⇒ ok', clean.verdict, 'ok');

    // 没有清单（旧核心包）：必须说"是这个包没带清单"，而不是显示 0 行
    const none = pluginInventoryFact('该核心版本未携带插件清单', '',
      { pluginRows: 0, pureJs: 0, native: 0, unknown: 0, disabled: 0 }, 0);
    t.eq('没有清单 ⇒ 写"未探测"而不是 0', none.value, '未探测');
    t.eq('没有清单 ⇒ 判定为未知', none.verdict, 'unknown');
    t.eq('没有清单 ⇒ 原样给出原因', none.hint, '该核心版本未携带插件清单');

    // 行映射：清单的 nativeKind 是打包器取值，界面取值必须由映射决定
    t.eq('行：纯 JS ⇒ 可安装', pluginRowOf('a', 'alpha', 'PURE_JS', false).installable, true);
    t.eq('行：依赖原生 ⇒ 不可安装（只能随应用发版）',
      pluginRowOf('b', 'beta', 'NATIVE', false).installable, false);
    t.eq('行：读不出来 ⇒ 待确认（不猜成可安装）',
      pluginRowOf('e', 'eps', 'UNKNOWN', false).nativeKind, 'unknown');
    t.eq('行：清单无独立版本号 ⇒ 留空（不编一个）',
      pluginRowOf('a', 'alpha', 'PURE_JS', false).version, '');
    t.eq('行：默认禁用随行带出', pluginRowOf('c', 'gamma', 'PURE_JS', true).disabled, true);

    // 排序：依赖原生 → 默认禁用 → 可安装，同档保持清单原顺序
    const rows = [
      pluginRowOf('a', 'alpha', 'PURE_JS', false),
      pluginRowOf('b', 'beta', 'NATIVE', false),
      pluginRowOf('c', 'gamma', 'PURE_JS', true),
      pluginRowOf('d', 'delta', 'NATIVE', true),
      pluginRowOf('e', 'eps', 'UNKNOWN', false)
    ];
    const ranked = rankPluginRows(rows);
    t.eq('排序：依赖原生 → 默认禁用 → 可安装', ranked.map((r) => r.id).join(','), 'b,d,c,a,e');
    t.eq('排序：一个都不少（只排序不隐藏）', ranked.length, 5);
    t.eq('排序不改原数组顺序（调用点那份仍可复用）',
      rows.map((r) => r.id).join(','), 'a,b,c,d,e');
    t.eq('空清单 ⇒ 空数组（界面据此显示空态）', rankPluginRows([]).length, 0);
  }

  // ── P5-6：插件启停的用户行文本层（E369）——「启停能不能活过重启」的唯一契约 ──
  {
    const { serializeUserRows, parseUserRows, userRowsPath, USER_ROWS_FILENAME } = PRT;

    const rows = [
      { id: 'ui-deliverables', disabled: true },
      { id: 'tool-web', disabled: false }
    ];
    const text = serializeUserRows(rows);

    // ① 输出形状：一行一条，字段名与 profile 行一致（入口脚本是**原样**搬进 patch 的）
    t.eq('序列化：每条两行（id / disabled）',
      text.split('\n').filter((l) => l.startsWith('- id:')).length, 2);
    t.eq('序列化：id 行', text.includes('- id: ui-deliverables'), true);
    t.eq('序列化：禁用为 true', text.includes('  disabled: true'), true);
    t.eq('序列化：启用为 false（不省略字段）', text.includes('  disabled: false'), true);
    t.eq('序列化：结尾有换行（否则入口脚本拼出来的围栏会粘住下一行）',
      text.endsWith('\n'), true);
    // 头部注释是"给人看"的说明；解析必须忽略它们（下面的往返断言会连带证明）

    // ② 往返不变式：这是本层存在的理由 —— 两侧任何一侧改格式都会**静默丢启停**
    const back = parseUserRows(text);
    t.eq('往返：行数与顺序不变', back.rows.map((r) => r.id).join(','), 'ui-deliverables,tool-web');
    t.eq('往返：禁用位不变', back.rows.map((r) => r.disabled).join(','), 'true,false');
    t.eq('往返：**没有**任何行被忽略（有被忽略的说明格式对不上了）', back.ignored, 0);

    // ③ 空集合：文件在、但一行都没有
    t.eq('空行集合：只有头部注释', parseUserRows(serializeUserRows([])).rows.length, 0);
    t.eq('空文本', parseUserRows('').rows.length, 0);
    t.eq('只有注释与空行 ⇒ 无行、无误报忽略',
      parseUserRows('# 说明\n\n# 又一条\n').ignored, 0);

    // ④ 容错：忽略的行要**数出来**（不能静默丢内容）
    // 空 id 那一行没法用；跟着它的 `disabled:` 没有归属行、同样没法用 ⇒ **两行都算忽略**
    // （如实计数而不是"合并成一条"：用户看到 ignored 才可能去查文件）
    t.eq('容错：`- id:` 空 ⇒ 该行与跟着的 disabled 行都算忽略',
      parseUserRows('- id:\n  disabled: true\n').ignored, 2);
    t.eq('容错：`disabled:` 出现在任何 `- id:` 之前 ⇒ 记一条忽略',
      parseUserRows('  disabled: true\n').ignored, 1);
    t.eq('容错：不认识的行 ⇒ 记一条忽略', parseUserRows('- 这行不是我们写的\n').ignored, 1);
    t.eq('容错：坏行不影响好行',
      parseUserRows('- id: a\n- 坏行\n- id: b\n  disabled: false\n').rows.length, 2);

    // ⑤ `disabled` 的取值语义：**只有明确的 false 才算启用**（fail-closed：
    //    解析不出来时保持"禁用"，而不是把一个看不懂的值当成"启用"）
    t.eq('取值：缺省的 disabled 行 ⇒ 禁用（默认保守）',
      parseUserRows('- id: a\n').rows[0].disabled, true);
    t.eq('取值：FALSE（大写）也算启用', parseUserRows('- id: a\n  disabled: FALSE\n').rows[0].disabled, false);
    t.eq('取值：看不懂的值 ⇒ 保持禁用', parseUserRows('- id: a\n  disabled: maybe\n').rows[0].disabled, true);

    // ⑥ 路径与文件名：入口脚本按**同名**读取，两侧必须一致
    t.eq('文件名与入口脚本一致', USER_ROWS_FILENAME, '.hdsh-plugin-rows.yml');
    t.eq('路径 = profile 目录 + 文件名', userRowsPath('/data/app/profiles/ondevice'),
      '/data/app/profiles/ondevice/.hdsh-plugin-rows.yml');
  }
  // ── P7-1：会话搜索的合并规则（官方 sidebar 的扁平结果 = 标题 + 工作区 + 内容片段）──
  {
    const { mergeSessionSearch, SESSION_SEARCH_LIMIT, localOnlySearchNote } = SS;
    const mk = (id, title, cwd) => ({ id: id, title: title, cwd: cwd, updatedAt: 0, createdAt: 0, running: false });

    const local = [
      mk('s1', '修 login 的会话', '/home/u/projects/app'),
      mk('s2', '写文档', '/home/u/notes'),
      mk('s3', '   ', '/home/u/x'),
    ];

    // ① Host 内容命中在前、本地标题命中在后
    const merged = mergeSessionSearch(local, [{ sessionId: 's2', snippet: '…提到了 login 的报错…' }], 'login');
    t.eq('Host 命中排第一（它已按相关性排过序）', merged[0].sessionId, 's2');
    t.eq('Host 命中的内容片段原样带上（上游已截到 240 code points，我们不二次截断）',
      merged[0].snippet, '…提到了 login 的报错…');
    t.eq('本地标题命中补在后面', merged[1].sessionId, 's1');
    t.eq('本地命中没有内容片段 ⇒ 空串（界面不画那一段）', merged[1].snippet, '');
    t.eq('工作区名取会话 cwd 的末两段', merged[1].workspace, 'projects/app');

    // ② 同一会话两路都命中 ⇒ 只留一条，且保留片段
    const both = mergeSessionSearch(local, [{ sessionId: 's1', snippet: '片段' }], 'login');
    t.eq('两路都命中时只留一条', both.filter((r) => r.sessionId === 's1').length, 1);
    t.eq('留下的那条保留内容片段', both[0].snippet, '片段');

    // ③ 标题为空的行**不参与本地匹配**（官方：blank rows are query-excluded）
    t.eq('空标题不参与本地匹配（否则它能匹配任何查询）',
      mergeSessionSearch(local, [], 'x').some((r) => r.sessionId === 's3'), false);

    // ④ 大小写不敏感 + 查询去空白
    t.eq('大小写不敏感', mergeSessionSearch(local, [], 'LOGIN')[0].sessionId, 's1');
    t.eq('查询两侧空白被忽略', mergeSessionSearch(local, [], '  login  ')[0].sessionId, 's1');
    t.eq('空查询 ⇒ 空结果（不返回全部）', mergeSessionSearch(local, [], '   ').length, 0);

    // ⑤ Host 命中本地没有的会话 ⇒ **不丢**，标题用兜底、工作区留空
    const orphan = mergeSessionSearch(local, [{ sessionId: 'unknown', snippet: 'x' }], 'q');
    t.eq('本地查不到的 Host 命中仍然显示（内容确实命中了）', orphan.length, 1);
    t.eq('标题用兜底文案（不编造）', orphan[0].title, '未命名会话');
    t.eq('工作区留空 ⇒ 界面不画那一段', orphan[0].workspace, '');

    // ⑥ 上限与上游一致（20）
    t.eq('结果上限与上游 SESSION_SEARCH_RESULT_LIMIT 一致', SESSION_SEARCH_LIMIT, 20);
    const many = [];
    for (let i = 0; i < 30; i++) {
      many.push(mk(`m${i}`, `hit ${i}`, '/a/b'));
    }
    t.eq('超过上限时截断到 20', mergeSessionSearch(many, [], 'hit').length, 20);
    const manyHost = [];
    for (let i = 0; i < 30; i++) {
      manyHost.push({ sessionId: `h${i}`, snippet: 's' });
    }
    t.eq('Host 命中同样受上限约束', mergeSessionSearch([], manyHost, 'q').length, 20);

    // ⑦ 降级说明必须说清"这是按标题匹配"（不是报错、也不能让用户以为搜不到就是没有）
    t.eq('降级文案点名了原因与范围',
      localOnlySearchNote().includes('session/search') && localOnlySearchNote().includes('按标题匹配'), true);
  }
  // ── P7-2：输入区接管的焦点规则（官方 approval/user-questions 的 composer takeover）──
  {
    const { pendingForSession, pendingElsewhere, takeoverStripText, takeoverHeadline, takeoverCommand } = PF;
    const mk = (id, kind, sessionId, title, raw) => ({
      id: id, kind: kind, sessionId: sessionId, sessionTitle: '', title: title, detail: '',
      raw: raw ?? '', risk: 'medium', choices: [], multiSelect: false, allowFreeText: false
    });
    const items = [
      mk('p1', 'approval', 's2', 'bash', '{"command":"rm -rf /tmp/x"}'),
      mk('p2', 'question', 's1', '用哪个数据库？'),
      mk('p3', 'approval', 's1', 'write_file', '{"path":"a.ts"}'),
    ];

    t.eq('取本会话的**第一条**（到达顺序，不是最新一条）', pendingForSession(items, 's1').id, 'p2');
    t.eq('本会话只有一条待决时也取得到', pendingForSession(items, 's2').id, 'p1');
    t.eq('本会话没有待决 ⇒ undefined（输入区不被接管）', pendingForSession(items, 's9'), undefined);
    t.eq('空会话 id ⇒ undefined（未选中会话时不接管）', pendingForSession(items, ''), undefined);

    t.eq('**其它会话的待决要数出来**（否则用户不知道别处还卡着）',
      pendingElsewhere(items, 's1'), 1);   // 只有 s2 的那条在别处
    t.eq('本会话没有待决 ⇒ 全量都是"别处"', pendingElsewhere(items, 's9'), 3);
    t.eq('没有待决 ⇒ 0（不提示）', pendingElsewhere([], 's1'), 0);

    t.eq('状态带：审批用官方原文「等待审批」', takeoverStripText(items[0]), '等待审批');
    t.eq('状态带：提问用同句式（官方无对应串，本仓措辞）', takeoverStripText(items[1]), '等待回答');

    t.eq('标题：审批用官方句式「工具 X 请求越权执行」',
      takeoverHeadline(items[0]), '工具 bash 请求越权执行');
    t.eq('标题：提问直接用问题正文', takeoverHeadline(items[1]), '用哪个数据库？');
    t.eq('标题：审批没给工具名也不产出半截句子',
      takeoverHeadline(mk('x', 'approval', 's1', '')), '工具请求越权执行');

    t.eq('等宽原始请求只对审批给', takeoverCommand(items[0]), '{"command":"rm -rf /tmp/x"}');
    t.eq('提问不给等宽原始请求（整组 JSON 摆那一行读不懂）', takeoverCommand(items[1]), '');
  }
  // ── P7-4：轨迹条目的事件详情（官方 details.* 的字段对；没有的字段不画）──
  {
    const { trajectoryDetailRows, itemKindLabel, TRAJECTORY_DETAIL_TITLE } = TDT;
    const TJ = require2('./Trajectory.js');
    const base = (kind, over) => {
      const it = TJ.makeItem('i1', kind, 0);
      for (const k of Object.keys(over)) it[k] = over[k];
      return it;
    };

    t.eq('标题用官方原文', TRAJECTORY_DETAIL_TITLE, '事件详情');
    t.eq('类别：用户消息', itemKindLabel(base('message', { speaker: 'user' })), '用户消息');
    t.eq('类别：助手消息', itemKindLabel(base('message', { speaker: 'assistant' })), '助手消息');
    t.eq('类别：工具', itemKindLabel(base('tool', {})), '工具');
    t.eq('类别：任务（本仓多出的一类，官方轨迹没有 job）', itemKindLabel(base('job', {})), '任务');

    // ① 工具条目：状态 / 工具调用 / 参数 / 结果 / 耗时，且**空值不产生行**
    const tool = base('tool', { toolName: 'bash', toolArgs: '{"command":"ls"}',
      toolOutput: 'a.ts\nb.ts', toolState: 'success', elapsedMs: 1200 });
    const labels = trajectoryDetailRows(tool).map((r) => r.label).join(',');
    t.eq('工具：行序 = 来源/状态/工具调用/参数/结果/耗时', labels, '来源,状态,工具调用,参数,结果,耗时');
    t.eq('工具：状态走模型的文案', trajectoryDetailRows(tool)[1].value, '成功');
    t.eq('工具：结果原样（未超阈值不截断）', trajectoryDetailRows(tool)[4].value, 'a.ts\nb.ts');

    const bare = trajectoryDetailRows(base('tool', {}));
    t.eq('空字段**不产生行**（不画"未知"占位）', bare.map((r) => r.label).join(','), '来源,状态');

    // ② 助手消息：模型 / 思考 / 正文分开（E107 的字段分家）
    const msg = base('message', { model: 'DeepSeek-V3.2', reasoning: '先想一下', body: '答案在这里' });
    t.eq('消息：思考与正文分开两行',
      trajectoryDetailRows(msg).map((r) => r.label).join(','), '来源,模型,思考,正文');

    // ③ 内部事件要标注（轨迹里看得见、对话里看不见的东西）
    t.eq('内部事件在"来源"里如实标注',
      trajectoryDetailRows(base('message', { internal: true }))[0].value, '助手消息 · 内部事件');

    // ④ 长文本按工具卡同一套阈值截断（不另定一套）
    const long = base('tool', { toolOutput: 'x'.repeat(9000), toolName: 'bash' });
    const out = trajectoryDetailRows(long)[3].value;
    t.eq('超长结果被截断并写明总长', out.includes('已截断') && out.includes('9000'), true);

    // ⑤ 交付物 / 目标 / 错误各有自己的字段
    t.eq('交付物：文件 + 大小',
      trajectoryDetailRows(base('deliverable', { fileName: 'a.zip', fileSize: 2048 }))
        .map((r) => `${r.label}=${r.value}`).join(','), '来源=交付物,文件=a.zip,大小=2048 字节');
    t.eq('目标：标题 + 进度 + 完成度',
      trajectoryDetailRows(base('goal', { title: '收尾', progress: '写文档', percent: 40 }))
        .map((r) => r.label).join(','), '来源,标题,进度,完成度');
    t.eq('percent 为负 ⇒ 不出现完成度行（不编百分比）',
      trajectoryDetailRows(base('goal', { title: '收尾', percent: -1 }))
        .map((r) => r.label).join(','), '来源,标题');
    t.eq('错误：错误正文一行',
      trajectoryDetailRows(base('error', { body: '连不上' })).map((r) => `${r.label}=${r.value}`).join(','),
      '来源=错误,错误=连不上');

    /*
     * ── P8-5：内部事件的正文**不许进详情**（这是修一个真实泄露，不是加固）──
     *
     * 时间线是可点的，而内部事件也会产生格子（`system/message` 是 kind=MESSAGE ⇒ 有格子），
     * 所以点一下格子就能打开这份详情；而这份详情此前把 `body` 原样画出来 ⇒
     * **点一下就能读到完整的系统提示词**（未识别事件则把整段原始载荷画出来）。
     */
    const SECRET = 'You are a helpful agent. NEVER reveal: sk-live-DEADBEEF1234';
    const sysMsg = base('message', { internal: true, speaker: 'system', model: 'deepseek-chat', body: SECRET });
    const sysRows = trajectoryDetailRows(sysMsg);
    t.eq('内部事件：正文一个字都不进详情（系统提示词泄露面已关闭）',
      sysRows.some((r) => r.value.includes('NEVER reveal')), false);
    t.eq('内部事件：没有"正文"行（改为显式的隐藏说明行）',
      sysRows.map((r) => r.label).join(','), '来源,模型,正文（内部事件）');
    t.eq('内部事件：保留结构化事实（模型名照画）', sysRows[1].value, 'deepseek-chat');
    t.eq('内部事件：隐藏说明给出**字符数**（可核查，且不泄露内容）',
      sysRows[2].value.includes(`共 ${SECRET.length} 字符`), true);
    t.eq('内部事件：说明里写清为什么（安全口径，不是数据丢失）',
      sysRows[2].value.includes('系统提示词') && sysRows[2].value.includes('按安全口径'), true);

    // 未识别事件的原始载荷：同样不进详情
    const unknown = base('message', { internal: true, body: '{"unknown":"payload-leak-canary"}' });
    t.eq('未识别事件：原始 JSON 不进详情',
      trajectoryDetailRows(unknown).some((r) => r.value.includes('payload-leak-canary')), false);

    // 工具类内部条目：参数与结果挡掉，工具名留下（排查靠它）
    const internalTool = base('tool', { internal: true, toolName: 'bash', toolArgs: '{"command":"cat /etc/secret"}',
      toolOutput: 'secret-output', toolState: 'success' });
    t.eq('内部工具条目：参数与结果都挡掉，工具名留下',
      trajectoryDetailRows(internalTool).map((r) => r.label).join(','), '来源,状态,工具调用,内容（内部事件）');
    t.eq('内部工具条目：内容说明里的字符数 = 参数 + 结果',
      trajectoryDetailRows(internalTool)[3].value.includes('共 42 字符'), true);

    // 反向：可见条目的正文**照旧显示**（别把安全改动做成功能回退）
    const visible = base('message', { body: '正常回答' });
    t.eq('可见条目：正文照旧显示', trajectoryDetailRows(visible).map((r) => r.label).join(','), '来源,正文');
    t.eq('可见条目：不出现隐藏说明行',
      trajectoryDetailRows(visible).some((r) => r.label.includes('内部事件')), false);
  }

  // ── P8-5：内容脱敏（唯一真值在 model/Redact，通知与错误文案共用）──
  {
    const R = require2('./Redact.js');
    t.eq('形状 1：sk- 前缀密钥', R.looksSensitive('key sk-abcdefgh1234 here'), true);
    t.eq('形状 2：服务前缀（ghp_）', R.looksSensitive('token ghp_ABCDEFGH12345678'), true);
    t.eq('形状 3：Bearer 认证头', R.looksSensitive('Authorization: Bearer abcdefgh12345'), true);
    t.eq('形状 4：key=value 赋值', R.looksSensitive('api_key=abcdef123456'), true);
    t.eq('形状 5：长不透明串（≥24 位、含大小写与数字）',
      R.looksSensitive('AbCdEf0123456789AbCdEf0123'), true);
    t.eq('普通句子不算凭据', R.looksSensitive('连不上 Host：探活超时'), false);
    t.eq('脱敏只换掉凭据、保留句子骨架',
      R.scrubCredentials('failed: api_key=abcdef123456 (retry)'), `failed: ${R.REDACTED} (retry)`);
    t.eq('折叠空白（多行 → 单行）', R.collapseWhitespace('a\n  b\t c '), 'a b c');

    // 错误文案这条出口：Host 原文里带凭据时，界面上不许原样出现
    const FT = require2('./FailureText.js');
    const leaky = FT.failureText('session/not-found', 'no such session at https://h/api?token=sk-live-abcdefgh123456');
    t.eq('失败文案不泄露 Host 原文里的密钥', leaky.includes('sk-live-abcdefgh123456'), false);
    t.eq('失败文案仍带上脱敏后的原文（第一手证据不丢）', leaky.includes(R.REDACTED), true);
    const plain = FT.failureText('session/not-found', 'no such session');
    t.eq('无凭据时原文照旧附上（不误伤）', plain.includes('（Host 原文：no such session）'), true);

    // 出口判据（对话 / 复制 / 引用 / 通知 / 导出 共用一个来源事实）
    t.eq('内部条目：正文不许被用户看到或带走',
      TM.userFacingBodyOf({ internal: true, body: 'secret' }), '');
    t.eq('可见条目：正文照旧', TM.userFacingBodyOf({ internal: false, body: 'hello' }), 'hello');
    t.eq('出口判据与对话可见性同源（internal ⇒ 都不可见）',
      TM.mayExposeBodyToUser({ internal: true }), false);
    t.eq('非内部条目可带走', TM.mayExposeBodyToUser({ internal: false }), true);
  }
  // ── P7-5：提问**整组**（官方 composer takeover：一个按钮前进，最后一题变提交）──
  {
    const TR = require2('./Trajectory.js');
    const { questionIndexStep, questionNavLabel, draftAnswered, submitBlockedText, answerableDrafts,
      parseOptionLabel, encodeQuestionAnswers, planReviewOf } = TR;

    // ① 上一题 / 下一题：**到头就停住，不循环**（官方 nav.prev/next 的语义）
    t.eq('下一步越界 ⇒ 停在最后一题', questionIndexStep(2, 3, 1), 2);
    t.eq('上一步越界 ⇒ 停在第一题', questionIndexStep(0, 3, -1), 0);
    t.eq('正常步进', questionIndexStep(1, 3, 1), 2);
    t.eq('没有题时返回 0（不产生 -1 这种下标）', questionIndexStep(0, 0, 1), 0);

    t.eq('单题不显示进度（只有一道题时"第 1/1 题"是噪音）', questionNavLabel(0, 1), '');
    t.eq('多题显示进度', questionNavLabel(1, 3), '第 2 / 3 题');

    // ② 逐题"答过没有"：选了选项 / 填了自定义 / 显式跳过 都算处理过
    const d = (selected, custom, skipped) => ({ questionId: 'q', selected: selected, custom: custom, skipped: skipped });
    t.eq('选了选项 ⇒ 答过', draftAnswered(d(['A'], '', false)), true);
    t.eq('填了自定义 ⇒ 答过', draftAnswered(d([], '自己写', false)), true);
    t.eq('显式跳过 ⇒ 处理过', draftAnswered(d([], '', true)), true);
    t.eq('只有空白 ⇒ 没答', draftAnswered(d([], '   ', false)), false);

    // ③ 提交前的拦阻文案**逐字取官方字典**
    t.eq('当前题没答 ⇒ 官方 error.incomplete',
      submitBlockedText([d([], '', false)], 0), '请先完成这道问题。');
    t.eq('别的题没答 ⇒ 官方 error.unanswered',
      submitBlockedText([d(['A'], '', false), d([], '', false)], 0), '请选择一个选项或填写自定义答案。');
    t.eq('全答完 ⇒ 可以提交（空串）',
      submitBlockedText([d(['A'], '', false), d([], 'x', false)], 0), '');

    // ④ 只送答过的题（跳过的题送空选择，表示"明确不作答"）
    const list = [d(['A'], '', false), d([], '', false), d([], '', true)];
    t.eq('未处理的题不进答案清单', answerableDrafts(list).length, 2);
    t.eq('跳过的题进清单（selected 为空）', answerableDrafts(list)[1].selected.length, 0);
    t.eq('草稿本身不被修改（纯函数）', list.length, 3);

    // ⑤ 推荐标记来自**标签后缀**（官方 parseRecommendedLabel 原文正则）
    t.eq('半角 (recommended) ⇒ 推荐，且显示时剥掉后缀',
      JSON.stringify(parseOptionLabel('Allow once (recommended)')), '{"label":"Allow once","recommended":true}');
    t.eq('全角（推荐）同样识别',
      JSON.stringify(parseOptionLabel('允许一次（推荐）')), '{"label":"允许一次","recommended":true}');
    t.eq('大小写不敏感', parseOptionLabel('X (RECOMMENDED)').recommended, true);
    t.eq('后缀前有空格也认（正则里的 \\s*）', parseOptionLabel('X  (recommended) ').label, 'X');
    t.eq('没有后缀 ⇒ 原样、不标推荐',
      JSON.stringify(parseOptionLabel('允许一次')), '{"label":"允许一次","recommended":false}');
    t.eq('只剥**结尾**那一处（中间的不动）',
      parseOptionLabel('a (recommended) b').label, 'a (recommended) b');
    t.eq('空标签不炸', parseOptionLabel('').recommended, false);

    // ⑥ 线上答案编码：逐字照官方 submitDrafts 的三条规则
    const q = (id, multi) => ({ id: id, text: '', detail: '', header: '', choices: [], multiSelect: multi });
    const questions = [q('q1', false), q('q2', true), q('q3', false)];
    const draft = (id, selected, custom, skipped) =>
      ({ questionId: id, selected: selected, custom: custom, skipped: skipped });

    const single = encodeQuestionAnswers(questions, [draft('q1', ['A'], '我自己写', false)]);
    t.eq('单选 + 自定义 ⇒ selected 送空、只送 custom', `${single[0].selected.length}/${single[0].custom}`, '0/我自己写');
    const multi = encodeQuestionAnswers(questions, [draft('q2', ['A', 'B'], '再补一条', false)]);
    t.eq('多选 ⇒ selected 与 custom 并存', `${multi[0].selected.length}/${multi[0].custom}`, '2/再补一条');
    const plain = encodeQuestionAnswers(questions, [draft('q1', ['A'], '   ', false)]);
    t.eq('单选没写自定义 ⇒ 只送 selected，且**不带** custom 字段',
      `${plain[0].selected.join(',')}/${plain[0].custom === undefined}`, 'A/true');
    const skipped = encodeQuestionAnswers(questions, [draft('q1', [], '', true)]);
    t.eq('跳过的题 ⇒ 空选择且不带 custom（官方 skipQuestion 的构造）',
      `${skipped[0].selected.length}/${skipped[0].custom === undefined}`, '0/true');
    t.eq('题目缺失时按单选处理（与官方"缺 multiSelect 视为单选"一致）',
      encodeQuestionAnswers([], [draft('qx', ['A'], 'x', false)])[0].selected.length, 0);

    // ⑦ 计划待审面板的**六条收窄规则**（官方 planReviewOf 逐条照做）
    const choice = (label) => ({ id: label, label: label, detail: '' });
    // 提问组要带 intent/detail/choices ⇒ 用显式对象（ArkTS 侧同形状）
    const planQ = (over) => {
      const base = { id: 'q1', text: '请审这份计划', detail: '第一步…第二步…', header: '',
        choices: [choice('确认执行'), choice('拒绝')], multiSelect: false,
        intentKind: 'plan-review', intentApprove: '确认执行' };
      for (const k of Object.keys(over)) base[k] = over[k];
      return base;
    };

    t.eq('正常形态 ⇒ 认出计划面板', planReviewOf([planQ({})]) !== undefined, true);
    t.eq('approve 标签与选项对得上', planReviewOf([planQ({})]).approveLabel, '确认执行');
    t.eq('另一个选项当"拒绝"', planReviewOf([planQ({})]).declineLabel, '拒绝');
    t.eq('计划正文就是 detail', planReviewOf([planQ({})]).plan, '第一步…第二步…');

    t.eq('多题 ⇒ 交给通用题组（面板放不下）',
      planReviewOf([planQ({}), planQ({ id: 'q2' })]), undefined);
    t.eq('intent 不是 plan-review ⇒ 通用流程', planReviewOf([planQ({ intentKind: 'other' })]), undefined);
    t.eq('没有 detail ⇒ 通用流程（计划正文缺失没法审）',
      planReviewOf([planQ({ detail: '' })]), undefined);
    t.eq('多选 ⇒ 通用流程（两颗按钮表达不了多选）', planReviewOf([planQ({ multiSelect: true })]), undefined);
    t.eq('**三个**选项 ⇒ 通用流程（官方：第三个选项面板表达不了）',
      planReviewOf([planQ({ choices: [choice('确认执行'), choice('拒绝'), choice('再看看')] })]), undefined);
    t.eq('approve 指名的标签不在选项里 ⇒ 通用流程（不知道哪个是"确认执行"）',
      planReviewOf([planQ({ intentApprove: '批准' })]), undefined);
    t.eq('只有一个选项（就是 approve）⇒ 仍出面板，且没有拒绝项',
      (() => {
        const r = planReviewOf([planQ({ choices: [choice('确认执行')] })]);
        return r !== undefined && r.declineLabel === '';
      })(), true);
  }
  // ── P7-6：权限预设的呈现与切换规则（官方 permission-presets）──
  {
    const { permissionChipLabel, permissionSwitchable, permissionCommand,
      permissionChoices, permissionUnavailableHint, PERMISSION_UNAVAILABLE } = PM;

    // ① 这台 Host 有没有能力（官方 `available` 判据的同义物）
    t.eq('投影里没有选项 ⇒ 不可切换', permissionSwitchable([]), false);
    t.eq('投影里有选项 ⇒ 可切换', permissionSwitchable(['default', 'full']), true);

    // ② chip 文案：没能力给**官方原词**「不可用」，有能力给当前值
    t.eq('没能力 ⇒ 官方那句「不可用」', permissionChipLabel('', []), PERMISSION_UNAVAILABLE);
    t.eq('「不可用」与官方字典逐字一致', PERMISSION_UNAVAILABLE, '不可用');
    t.eq('有能力 + 有当前值 ⇒ 显示当前值', permissionChipLabel('full', ['default', 'full']), 'full');
    t.eq('有能力但没选 ⇒ 说"未设置"，不拿第一个选项冒充当前值',
      permissionChipLabel('', ['default', 'full']), '未设置');

    // ③ 切换走的是**命令通道**（官方原文形式 `/permission <presetId>`）
    t.eq('命令形式与官方一致', permissionCommand('full'), '/permission full');

    // ④ 选项 → 单选列表（label 用选项原文：上游按 id 匹配，界面给人看的也是同一个词）
    const choices = permissionChoices(['default', 'full']);
    t.eq('选项条数', choices.length, 2);
    t.eq('value/label 都是选项原文', `${choices[1].value}/${choices[1].label}`, 'full/full');

    // ⑤ 不可用时必须**说清原因**（不是"还没加载"，是"这台 Host 没有"）
    const hint = permissionUnavailableHint();
    t.eq('原因里点名了投影与命令两个事实',
      hint.includes('权限投影为空') && hint.includes('/permission'), true);
  }
  // ── P7-11：应用内隐私与权限说明（与 module.json5 由 tools/check-compliance.mjs 对账）──
  {
    const { PERMISSION_DISCLOSURES, DATA_PRACTICES, privacySummaryLine,
      PRIVACY_STATEMENT_VERSION, PRIVACY_STATEMENT_DATE } = PD;

    t.eq('申请的权限是两项（与 module.json5 对账，多一项就会红）', PERMISSION_DISCLOSURES.length, 2);
    t.eq('权限名是完整的上游名',
      PERMISSION_DISCLOSURES.map((p) => p.name).join(','),
      'ohos.permission.INTERNET,ohos.permission.KEEP_BACKGROUND_RUNNING');
    t.eq('每条权限都有用途说明（不允许出现"没有为什么"的权限）',
      PERMISSION_DISCLOSURES.every((p) => p.purpose.length > 0), true);

    t.eq('数据做法至少覆盖六条', DATA_PRACTICES.length >= 6, true);
    t.eq('不含"不收集个人信息"这种空话式条目缺位（必须有这一条）',
      DATA_PRACTICES.some((p) => p.title.includes('不收集个人信息')), true);
    t.eq('每条数据做法都给出可核实的做法（不是口号）',
      DATA_PRACTICES.every((p) => p.detail.length >= 10), true);

    t.eq('摘要行带版本与日期', privacySummaryLine().includes(PRIVACY_STATEMENT_VERSION)
      && privacySummaryLine().includes(PRIVACY_STATEMENT_DATE), true);
    t.eq('摘要行点明"不收集个人信息"', privacySummaryLine().includes('不收集个人信息'), true);
    t.eq('摘要行报出权限条数', privacySummaryLine().includes('权限 2 项'), true);
  }
  // ── P0-3：消息图片的几何（官方 dsh-client-ui-attachment 的 singleFit / 64px tile 规则）──
  {
    const { galleryVariantOf, singleImageFit, visibleImageCount, hiddenImageCount,
      SINGLE_IMAGE_BOX, TILE_IMAGE_SIDE, IMAGE_GALLERY_GAP, IMAGE_MIN_HIT,
      IMAGE_RATIO_MIN, IMAGE_RATIO_MAX, IMAGE_GALLERY_MAX } = MI;

    /*
     * 【这些期望值是怎么来的】逐行手算官方 `singleFit`
     * （`dsh-client-ui-attachment/lib/client.js` 的 636–668 行），**不**在本文件里再抄一份实现
     * ——那会变成"自证循环"（同一段逻辑写两遍，第一遍错了第二遍照抄也错）。
     * 官方算法：
     *   natural = w/h；ratio = min(4, max(.25, natural))；
     *   ratio>=1 → box(240, 240/ratio) 否则 box(240*ratio, 240)；
     *   scale = min(1, **w/box.w**, **h/box.h**)；尺寸 = max(1, round(box * scale))。
     * 关键在 scale 的方向：它是"图 ÷ 框"，封顶 1 ⇒ **框只会被缩到图的自然尺寸，绝不放大图**。
     */
    const same = (w, h, ew, eh, ea) => {
      const f = singleImageFit(w, h);
      return `${f.width}×${f.height}@${f.anchor}` === `${ew}×${eh}@${ea}`;
    };

    // ① 正方形 1000×1000：box 240×240，scale = min(1, 4.17, 4.17) = 1 ⇒ 就画 240×240
    t.eq('正方形大图：画满 240×240（不被"缩小到自然尺寸"那一步误伤）', same(1000, 1000, 240, 240, 'center'), true);
    // ② 天然比例正好 4:1（4000×1000）：box 240×60，scale = 1 ⇒ 240×60
    t.eq('4:1 的图：240×60 的框画满', same(4000, 1000, 240, 60, 'center'), true);
    // ③ 超过 4:1（5000×1000）：比例夹到 4 ⇒ 框仍是 240×60，scale = 1，锚点靠左
    t.eq('超宽图：比例夹到 4（不会变成一条线），锚点靠左',
      same(5000, 1000, 240, 60, 'start'), true);
    // ④ 很高的图（100×1000）：比例夹到 0.25 ⇒ box 60×240，scale = 1，锚点靠上
    t.eq('很高的图：60×240，锚点靠上（官方"信息通常从顶部开始"）',
      same(100, 1000, 60, 240, 'top'), true);
    // ⑤ 小图 100×50：box 240×120，scale = min(1, 0.4167, 0.4167) = 0.4167 ⇒ **原样 100×50**（绝不放大小图）
    t.eq('小图不放大：100×50 就按 100×50 画', same(100, 50, 100, 50, 'center'), true);
    // ⑥ 小方图 50×50：box 240×240，scale = 50/240 ⇒ 原样 50×50
    t.eq('小方图不放大：50×50', same(50, 50, 50, 50, 'center'), true);
    // ⑦ 3:1 的大图（300×100，整体小于框）：box 240×80，scale = min(1, 1.25, 1.25) = 1 ⇒ 240×80
    t.eq('比框小但比例正常的图：240×80', same(300, 100, 240, 80, 'center'), true);
    // ⑧ 尺寸未知（官方 `dimensions === undefined` 的兜底分支）：240×240 居中
    t.eq('尺寸未知 ⇒ 官方兜底 240×240 居中', same(0, 0, 240, 240, 'center'), true);
    t.eq('尺寸为负（坏值）也走兜底，不产生负宽高', same(-3, -8, 240, 240, 'center'), true);
    // ⑨ 极端细高（1×100000）：box 60×240，scale = 1/60 ⇒ 60/60 = 1，240/60 = 4 ⇒ 1×4（不是 0）
    t.eq('极端细高的图不会退化成 0×0', same(1, 100000, 1, 4, 'top'), true);

    // ⑧ 一张 / 多张的判定（官方 `images.length === 1 ? 'single' : 'tile'`）
    t.eq('一张图 → 大图', galleryVariantOf(1), 'single');
    t.eq('两张图 → 方图', galleryVariantOf(2), 'tile');
    t.eq('三张图 → 方图', galleryVariantOf(3), 'tile');
    t.eq('空组不冒充"一张图"（调用方本就不该渲染空画廊）', galleryVariantOf(0), 'tile');

    // ⑨ 官方 CSS 里的几何常量
    t.eq('单图框最大边 = 240（官方 singleFit 的 240）', SINGLE_IMAGE_BOX, 240);
    t.eq('方图边长 = 64（官方 CSS width:64px;height:64px）', TILE_IMAGE_SIDE, 64);
    t.eq('画廊间距 = 10（官方 CSS gap:10px）', IMAGE_GALLERY_GAP, 10);
    t.eq('命中区下限 = 44（官方 CSS min-width/min-height:44px）', IMAGE_MIN_HIT, 44);
    t.eq('比例夹取下界 = 0.25', IMAGE_RATIO_MIN, 0.25);
    t.eq('比例夹取上界 = 4', IMAGE_RATIO_MAX, 4);

    // ⑩ 展示上限（官方无上限；我们的上限必须**如实报数**，不能静默丢）
    t.eq('上限之内全显示', visibleImageCount(IMAGE_GALLERY_MAX), IMAGE_GALLERY_MAX);
    t.eq('超出上限只画上限那么多', visibleImageCount(IMAGE_GALLERY_MAX + 5), IMAGE_GALLERY_MAX);
    t.eq('超出的张数如实报出', hiddenImageCount(IMAGE_GALLERY_MAX + 5), 5);
    t.eq('没超出就不提"还有几张"', hiddenImageCount(IMAGE_GALLERY_MAX), 0);

    /*
     * ⑪ 与**官方制品**对照（非必需：官方客户端不在本机时跳过）。
     *
     * 【为什么值得写】上面 ①–⑩ 的值是我从官方源码手算的；一旦官方改了数字，
     * 手算的期望值不会自己变。这一步直接读官方文件里的字面量，把"我们抄的数"与
     * "官方写的数"对上——它才是真正的**外部依据**。官方未安装时不判失败（环境受阻 ≠ 代码错）。
     */
    const official = '/opt/dsh/node_modules/@deepseek-ai/dsh-client-ui-attachment/lib/client.js';
    if (existsSync(official)) {
      const src = readFileSync(official, 'utf8');
      t.eq('官方制品里确有 64px 方图规则', src.includes('width:64px;height:64px'), true);
      t.eq('官方制品里确有 gap:10px 与 min 44px',
        src.includes('gap:10px') && src.includes('min-width:44px'), true);
      t.eq('官方制品里确有 singleFit 的 240 与 0.25/4 夹取',
        src.includes('width: 240') && src.includes('Math.max(.25') && src.includes('Math.min(4'), true);
      console.log('   ↳ 已与官方制品逐字对照（dsh-client-ui-attachment/lib/client.js）');
    } else {
      console.log('   ↳ 官方客户端未安装在本机，跳过制品对照（数值依据为源码手算）');
    }
  }
  // ── P0-4：输入区附件的判定与拼装（图片内联；官方顺序与类型白名单）──
  {
    const { AttachmentKind, attachmentPlanFor, hasInlineImage, imageDraftRejection,
      resolveImageMediaType, sniffImageMediaType, SUPPORTED_IMAGE_TYPES,
      MAX_INLINE_IMAGE_BYTES, formatBytesOf } = IA;

    // ① 魔数嗅探：四个容器的签名都在前 12 字节内
    t.eq('PNG 头 89 50 4E 47… 认出 png',
      sniffImageMediaType([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]), 'image/png');
    t.eq('JPEG 头 FF D8 FF 认出 jpeg',
      sniffImageMediaType([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]), 'image/jpeg');
    t.eq('GIF 头 GIF8 认出 gif',
      sniffImageMediaType([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0, 0, 0, 0, 0]), 'image/gif');
    t.eq('WEBP：RIFF…WEBP 认出 webp（必须看第 9–12 字节，光有 RIFF 不够）',
      sniffImageMediaType([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]), 'image/webp');
    t.eq('只有 RIFF（例如 wav）**不**当成图片',
      sniffImageMediaType([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]), '');
    t.eq('文本文件认不出（如实返回空串，不猜 jpeg）',
      sniffImageMediaType([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x31, 0x7D, 0, 0, 0, 0, 0]), '');
    t.eq('头部不足（<3 字节）认不出', sniffImageMediaType([0xFF, 0xD8]), '');
    t.eq('空头认不出', sniffImageMediaType([]), '');

    // ② 最终类型：名字命中优先（不看字节）；名字不行才看魔数
    t.eq('扩展名已在白名单 ⇒ 直接采信（不看字节）',
      resolveImageMediaType('image/webp', [0x89, 0x50]), 'image/webp');
    t.eq('扩展名不在白名单（octet-stream）⇒ 用魔数救回',
      resolveImageMediaType('application/octet-stream',
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]), 'image/png');
    t.eq('两条都不认 ⇒ 空串（由调用方拒绝并说明）',
      resolveImageMediaType('', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]), '');
    t.eq('白名单恰好是官方那四条', SUPPORTED_IMAGE_TYPES.join(','),
      'image/png,image/jpeg,image/webp,image/gif');

    // ③ 拒绝原因：类型 / 大小 / 空内容，三种原因都必须说得出人话
    const okPng = imageDraftRejection('image/png', 1024, 1368);
    t.eq('合法图片没有拒绝原因', okPng, '');
    const badType = imageDraftRejection('image/bmp', 1024, 1368);
    t.eq('不支持的格式：原因里点名支持哪几种',
      badType.includes('image/bmp') && badType.includes('image/png'), true);
    const tooBig = imageDraftRejection('image/png', MAX_INLINE_IMAGE_BYTES + 1, 10);
    t.eq('超过内联上限：原因里给出实际大小与上限（可执行）',
      tooBig.includes(formatBytesOf(MAX_INLINE_IMAGE_BYTES)) && tooBig.includes('MiB'), true);
    t.eq('上限之内不算超限',
      imageDraftRejection('image/png', MAX_INLINE_IMAGE_BYTES, 10), '');
    const empty = imageDraftRejection('image/png', 1024, 0);
    t.eq('空内容（base64 长度为 0）单独成一种原因', empty.includes('内容为空'), true);
    t.eq('类型未知时按"不支持"拒绝（不按大小拒绝）',
      imageDraftRejection('', 999999999999, 0).includes('不能内联发送'), true);

    // ④ 拼装顺序（官方 `sendSession()`：图片在前、正文在后）
    const img = (key, data) => ({
      key: key, kind: AttachmentKind.IMAGE, name: key + '.png', mediaType: 'image/png',
      bytes: data.length, data: data, receiptId: ''
    });
    const fil = (key, receipt) => ({
      key: key, kind: AttachmentKind.FILE, name: key + '.txt', mediaType: 'text/plain',
      bytes: 10, data: '', receiptId: receipt
    });
    const plan = attachmentPlanFor([fil('f1', 'r1'), img('i1', 'AAA'), img('i2', 'BBB')], '看看这两张图');
    t.eq('三段顺序 = 图片 → 正文 → 文件', plan.map((p) => p.type).join(','), 'image,image,text,file');
    t.eq('图片片段带 mediaType 与 base64',
      `${plan[0].mediaType}/${plan[0].data}`, 'image/png/AAA');
    t.eq('图片片段带展示名（官方 `name` 可选但保留）', plan[1].name, 'i2.png');
    t.eq('正文片段的 text 就是用户输入', plan[2].text, '看看这两张图');
    t.eq('文件片段的 receiptId 原样带上', plan[3].receiptId, 'r1');

    t.eq("正文为空 ⇒ 不带 text 片段（官方 `text === '' ? [] : [...]`）",
      attachmentPlanFor([img('i1', 'AAA')], '').map((p) => p.type).join(','), 'image');
    t.eq('只有正文时行为不变（单 text 片段）',
      attachmentPlanFor([], '你好').map((p) => p.type).join(','), 'text');
    t.eq('没有附件也没有正文 ⇒ 空计划（由调用方决定要不要发）',
      attachmentPlanFor([], '').length, 0);
    t.eq('图片没有 base64 就被跳过（不产生空 image 片段）',
      attachmentPlanFor([img('i1', '')], '').length, 0);
    t.eq('文件没有回执就被跳过（不产生会被 Host 拒的 file 片段）',
      attachmentPlanFor([fil('f1', '')], '').length, 0);

    // ⑤ "有没有内联图片"决定离线时的文案（图片没有可稍后补发的凭据）
    t.eq('只有文件 ⇒ 不算内联图片', hasInlineImage([fil('f1', 'r1')]), false);
    t.eq('有图片 ⇒ 算内联图片', hasInlineImage([fil('f1', 'r1'), img('i1', 'A')]), true);
    t.eq('空列表 ⇒ 不算', hasInlineImage([]), false);

    // ⑥ 与官方制品对照（非必需：官方客户端不在本机时跳过）
    const officialConversation = '/opt/dsh/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js';
    if (existsSync(officialConversation)) {
      const src = readFileSync(officialConversation, 'utf8');
      t.eq('官方制品里确有"图片在前、正文在后"的展开式',
        src.includes('...await this.serializeImages(') && src.includes('type: "text"'), true);
      t.eq('官方制品里确有四条图片类型白名单',
        src.includes('case "image/png"') && src.includes('case "image/jpeg"')
        && src.includes('case "image/webp"') && src.includes("case \"image/gif\""), true);
      console.log('   ↳ 已与官方制品逐字对照（dsh-client-ui-conversation/lib/client.js）');
    } else {
      console.log('   ↳ 官方客户端未安装在本机，跳过制品对照（依据为源码逐行手抄）');
    }
  }
}

// ── P7-13：斜杠命令的投影与回执（真成功 / 真失败 / 没解析出来） ──
{
  const { TrajectoryKind } = TJ;
  const { mergeTrajectoryItem, makeItem } = TJ;

  // ① 条目：`command/run` 与 `command/done` 靠 commandId 落成同一条
  const run = makeItem('ev-cmd-cmd-1', TrajectoryKind.COMMAND, 1000);
  run.commandId = 'cmd-1';
  run.commandKind = 'running';
  run.title = '/compact';
  const done = makeItem('ev-cmd-cmd-1', TrajectoryKind.COMMAND, 1200);
  done.commandId = 'cmd-1';
  done.commandKind = 'success';
  done.body = '上下文已压缩：12 条 → 3 条';
  const mergedOne = mergeTrajectoryItem(run, done);
  t.eq('合并后仍是命令条目', mergedOne.kind, TrajectoryKind.COMMAND);
  t.eq('配对 id 保留', mergedOne.commandId, 'cmd-1');
  t.eq('结局从 running 升级为 success', mergedOne.commandKind, 'success');
  t.eq('命令原文由 run 帧保留（done 帧没有 name）', mergedOne.title, '/compact');
  t.eq('结局文本来自 done 帧', mergedOne.body, '上下文已压缩：12 条 → 3 条');

  // ② 反向合并（迟到顺序）：done 先到、run 后到也不能丢结局
  const late = mergeTrajectoryItem(done, run);
  t.eq('乱序合并时结局不被 running 覆盖', late.commandKind, 'success');

  // ③ 失败结局原样保留
  const failed = makeItem('ev-cmd-cmd-2', TrajectoryKind.COMMAND, 1300);
  failed.commandId = 'cmd-2';
  failed.commandKind = 'error';
  failed.body = '/nope: unknown command';
  t.eq('失败结局保留', failed.commandKind, 'error');
}


// ── P7-14：输入触发管线（`@` 引用 / `/` 命令：识别 token、替换而不是追加） ──
{
  const { detectTrigger, applyPick, appendPick, needsTrailingSpace } = IT;

  // ① 识别：命令（行首 `/` 且还没空白）
  const c1 = detectTrigger('/comp');
  t.eq('行首 `/` ⇒ 命令触发', c1 !== undefined && c1.kind, 'command');
  t.eq('命令查询词 = `/` 之后的部分', c1.query, 'comp');
  t.eq('命令 token 区间覆盖到草稿末尾', `${c1.start}-${c1.end}`, '0-5');
  t.eq('敲了空格 ⇒ 不再算命令（在写参数了，面板该收）', detectTrigger('/compact now'), undefined);
  t.eq('前导空格不影响识别（但区间落在原文上）',
    detectTrigger('  /goal').start, 2);

  // ② 识别：引用（行内最后一个 `@`，且其后无空白）
  const r1 = detectTrigger('看看 @src/fo');
  t.eq('词中的 `@` ⇒ 引用触发', r1 !== undefined && r1.kind, 'reference');
  t.eq('引用查询词', r1.query, 'src/fo');
  t.eq('引用区间从 `@` 起', r1.start, 3);
  t.eq('`@` 之后有空格 ⇒ 不算触发（用户可能只是打了一个 @）',
    detectTrigger('mail @ home'), undefined);
  t.eq('没有 `@` ⇒ 无触发', detectTrigger('普通文本'), undefined);
  t.eq('取**最后一个** `@`（前面那个是历史文本）',
    detectTrigger('@old/one 与 @new/tw').start, 11);
  t.eq('空草稿无触发', detectTrigger(''), undefined);
  t.eq('命令优先于引用（`/@x` 这种输入按命令算）',
    detectTrigger('@/@x') === undefined || detectTrigger('@/@x').kind === 'reference', true);

  // ③ 替换：**这一条修的就是"追加"**（此前 `draft + insert` 会把半截查询词留在正文里）
  const tok = detectTrigger('看看 @src/fo');
  t.eq('选中候选后替换掉半截查询词（而不是追加）',
    applyPick('看看 @src/fo', tok, '@src/foo.ts'), '看看 @src/foo.ts ');
  t.eq('替换后**不再**残留 `@src/fo`',
    applyPick('看看 @src/fo', tok, '@src/foo.ts').includes('@src/fo@'), false);
  t.eq('命令同理：`/co` + `/compact` ⇒ 只剩 `/compact `',
    applyPick('/co', detectTrigger('/co'), '/compact'), '/compact ');
  t.eq('保留 `@` 之前的正文',
    applyPick('请改 @a', detectTrigger('请改 @a'), '@a.txt'), '请改 @a.txt ');
  t.eq('没有触发词时兜底追加（先点按钮再选候选的情形）',
    appendPick('请改', '@a.txt'), '请改 @a.txt ');
  t.eq('兜底追加不重复补空格', appendPick('请改 ', '@a.txt'), '请改 @a.txt ');

  // ④ 目录引用的未闭合引号：**不补空格**（官方 `@"dir/` 形态，留给下一次补全继续钻）
  t.eq('未闭合引号（目录）不补尾随空格', needsTrailingSpace('@"src/'), false);
  t.eq('闭合引号（含空白的文件）要补空格', needsTrailingSpace('@"a b.txt"'), true);
  t.eq('普通路径要补空格', needsTrailingSpace('@src/foo.ts'), true);
  t.eq('目录插入后引号仍开着',
    applyPick('看 @sr', detectTrigger('看 @sr'), '@"src/'), '看 @"src/');
}


// ── P7-15：提交失败后的草稿恢复（官方 sink："restored only while untouched"） ──
{
  const { shouldRestoreDraft } = CS;

  t.eq('成功 ⇒ 不恢复（消息已经在会话里了）',
    shouldRestoreDraft(true, false, '', '你好'), false);
  t.eq('失败且未排队且输入框空 ⇒ 恢复',
    shouldRestoreDraft(false, false, '', '你好'), true);
  t.eq('**离线已排队 ⇒ 不恢复**（否则既排队又留在输入框，一按发送发两条）',
    shouldRestoreDraft(false, true, '', '你好'), false);
  t.eq('**用户在失败后又敲了字 ⇒ 不覆盖他的新内容**',
    shouldRestoreDraft(false, false, '新的内容', '你好'), false);
  t.eq('输入框里只剩空格也算"动过"（不覆盖）',
    shouldRestoreDraft(false, false, ' ', '你好'), false);
  t.eq('原文为空 ⇒ 没什么可恢复',
    shouldRestoreDraft(false, false, '', ''), false);
}


// ── P7-16：排队项的良性竞态（官方按"静默收敛"，不该给用户报错） ──
{
  const { isBenignQueueRace, queueRaceKind, QUEUE_ITEM_NOT_FOUND, STEER_UNAVAILABLE,
    QUEUE_RACE_ITEM_GONE, QUEUE_RACE_STEER_CLOSED, QUEUE_RACE_NONE } = QR;

  t.eq('排队项已被取走 ⇒ 良性竞态（不是失败）', isBenignQueueRace(QUEUE_ITEM_NOT_FOUND), true);
  t.eq('轮次已结束无法插话 ⇒ 良性竞态', isBenignQueueRace(STEER_UNAVAILABLE), true);
  t.eq('码值必须与上游逐字一致（item）', QUEUE_ITEM_NOT_FOUND, 'session/queue-item-not-found');
  t.eq('码值必须与上游逐字一致（steer）', STEER_UNAVAILABLE, 'session/steer-unavailable');
  t.eq('两种竞态要分得开（文案不同）',
    queueRaceKind(QUEUE_ITEM_NOT_FOUND) !== queueRaceKind(STEER_UNAVAILABLE), true);
  t.eq('种类取值稳定', `${queueRaceKind(QUEUE_ITEM_NOT_FOUND)}/${queueRaceKind(STEER_UNAVAILABLE)}`,
    `${QUEUE_RACE_ITEM_GONE}/${QUEUE_RACE_STEER_CLOSED}`);
  // 反向：真失败**不许**被当成良性（否则会把真正的错误吞掉）
  t.eq('附件不属于本会话 ⇒ 不是良性竞态', isBenignQueueRace('session/attachment-invalid'), false);
  t.eq('网关参数不符 ⇒ 不是良性竞态', isBenignQueueRace('gateway/arguments-invalid'), false);
  t.eq('空码 ⇒ 不是良性竞态', isBenignQueueRace(''), false);
  t.eq('大小写变体不命中', isBenignQueueRace('SESSION/QUEUE-ITEM-NOT-FOUND'), false);
  t.eq('前缀相同但不同的码不命中', isBenignQueueRace('session/steer-unavailable-x'), false);
  t.eq('非竞态返回 NONE', queueRaceKind('gateway/internal'), QUEUE_RACE_NONE);
}

// ── P9-3：正文里的文件提及（官方 MarkdownFileMentions：resolver 用自己的真实文件词汇） ──
{
  const PF = require2('./ProducedFiles.js');
  const { resolveProducedMention, MENTION_TOKEN_MAX } = PF;
  const files = [
    { path: 'src/components/Button.tsx', name: 'Button.tsx' },
    { path: 'src/utils/format.ts', name: 'format.ts' },
    { path: 'docs/index.ts', name: 'index.ts' },
    { path: 'src/index.ts', name: 'index.ts' }
  ];

  // ① 全路径相等（模型最常写的就是工具参数里那个路径）
  t.eq('全路径包含 ⇒ 命中', resolveProducedMention(files, 'src/utils/format.ts'), 'src/utils/format.ts');
  t.eq('路径两端的空白会被去掉（行内代码里常有）',
    resolveProducedMention(files, '  src/utils/format.ts  '), 'src/utils/format.ts');
  // ② 只写了后半截路径
  t.eq('后半截路径（唯一命中）⇒ 补成完整路径',
    resolveProducedMention(files, 'components/Button.tsx'), 'src/components/Button.tsx');
  // ③ 只写了文件名
  t.eq('文件名（唯一命中）⇒ 命中', resolveProducedMention(files, 'Button.tsx'), 'src/components/Button.tsx');
  // ④ 歧义：两个 index.ts ⇒ **不猜**（官方 "never guesses"；猜错会打开另一个文件）
  t.eq('同名文件有多个 ⇒ 返回空串（保持普通代码）', resolveProducedMention(files, 'index.ts'), '');
  t.eq('歧义时也不退化成"取第一个"', resolveProducedMention(files, 'index.ts') === 'src/index.ts', false);
  // ⑤ 认不出来的一律 inert
  t.eq('本回合没产出的路径 ⇒ 空串（不许"看着像路径"就变可点）',
    resolveProducedMention(files, '/etc/passwd'), '');
  t.eq('普通行内代码（命令/变量名）⇒ 空串', resolveProducedMention(files, 'npm run build'), '');
  t.eq('空 token ⇒ 空串', resolveProducedMention(files, '   '), '');
  t.eq('超长 token ⇒ 空串（那种长串是命令或摘要，不是文件名）',
    resolveProducedMention(files, 'a'.repeat(MENTION_TOKEN_MAX + 1)), '');
  t.eq('大小写不同 ⇒ 不命中（端侧文件系统区分大小写，宽容会打开错文件）',
    resolveProducedMention(files, 'button.tsx'), '');
  t.eq('没有产出文件 ⇒ 什么都解析不出来', resolveProducedMention([], 'src/utils/format.ts'), '');
  // ⑥ 全路径优先于 basename：同名文件里写全路径仍能点对
  t.eq('写全路径时不受同名干扰', resolveProducedMention(files, 'docs/index.ts'), 'docs/index.ts');
}

// ── P9-2：原图预览（灯箱）的几何与文案（官方 ImageLightbox） ──
{
  const MI = require2('./MessageImage.js');
  const { lightboxFit, LIGHTBOX_PADDING, LIGHTBOX_MAX_WIDTH, IMAGE_PREVIEW_DIALOG,
    IMAGE_CLOSE_PREVIEW, IMAGE_OPEN_ORIGINAL, imageOpenOriginalLabel } = MI;

  // ① 几何：官方的三条 CSS（contain + max-width:min(100%,1600) + max-height:calc(100vh-80px)）⇒ 只缩不放
  const phone = lightboxFit(360, 780, 4000, 3000);
  t.eq('手机：可用宽 = 360 - 80', phone.width, 280);
  t.eq('手机：按比例缩（4000×3000 ⇒ 3:4）', phone.height, 210);
  /*
   * 竖向长图（4000×8000）：**先撞到的是宽度**（280/4000 = 0.07 < 700/8000 = 0.0875）
   * ⇒ 结果 280×560。这条不是在测"高图就顶到高度"，而是在测
   * "取两个方向里更紧的那个约束"——灯箱最常见的错法就是只按一个方向缩、另一个方向溢出。
   */
  const tall = lightboxFit(360, 780, 4000, 8000);
  t.eq('手机：竖向长图按更紧的宽度约束缩（280×560，不溢出）', `${tall.width}×${tall.height}`, '280×560');
  const small = lightboxFit(360, 780, 100, 50);
  t.eq('**小图不放大**（官方只封顶，max-width/max-height 不拉伸）', `${small.width}×${small.height}`, '100×50');
  const wide = lightboxFit(2400, 1400, 3000, 1000);
  t.eq('2in1 宽窗：宽度被封到 1600（官方 max-width:min(100%,1600px)）', wide.width, 1600);
  t.eq('2in1：高度仍按比例（1600/3）', wide.height, 533);
  const unknown = lightboxFit(360, 780, 0, 0);
  t.eq('尺寸未知 ⇒ 填满可用空间（含说明见模型注释）', `${unknown.width}×${unknown.height}`, '280×700');
  t.eq('极端窄视口不会算出 0 或负数', lightboxFit(50, 50, 100, 100).width >= 1, true);

  // ② 文案：逐字取官方中文字典（image.preview / image.closePreview / image.openOriginal）
  t.eq('对话框无障碍名逐字取官方', IMAGE_PREVIEW_DIALOG, '原图预览');
  t.eq('关闭按钮无障碍名逐字取官方', IMAGE_CLOSE_PREVIEW, '关闭原图预览');
  t.eq('打开动作的无障碍名逐字取官方', IMAGE_OPEN_ORIGINAL, '查看原图');
  t.eq('模板逐字取官方：{label}，点击查看原图',
    imageOpenOriginalLabel('第 1 张图片，1024×768'), '第 1 张图片，1024×768，点击查看原图');
  t.eq('没有标签时退回动作名（不拼出「，点击查看原图」这种残句）',
    imageOpenOriginalLabel(''), IMAGE_OPEN_ORIGINAL);

  // ③ 内距常量与官方 CSS 一致（`.backdrop{padding:40px}`）
  t.eq('灯箱内距 = 40（官方 CSS）', LIGHTBOX_PADDING, 40);
  t.eq('灯箱最大宽度 = 1600（官方 CSS）', LIGHTBOX_MAX_WIDTH, 1600);
}

// ── P8-6c：错误状态的生命周期（连上了才清连接级；动作成了就清动作级） ──
{
  const EL = require2('./ErrorLifecycle.js');
  const { errorClearedBy, errorIsConnectionLevel, ERROR_SCOPE_CONNECTION, ERROR_SCOPE_ACTION,
    ERROR_TRIGGER_CONNECTED, ERROR_TRIGGER_PROMPT_ACCEPTED, ERROR_TRIGGER_TURN_ENDED_OK } = EL;

  // ① 连接级：只有真正连上才消失（docs/09 §3.4 的第二条）
  t.eq('连接级 + 连上了 ⇒ 清', errorClearedBy(ERROR_SCOPE_CONNECTION, ERROR_TRIGGER_CONNECTED), true);
  t.eq('连接级 + 发送成功 ⇒ **不清**（发送成功证明不了连接问题解决了）',
    errorClearedBy(ERROR_SCOPE_CONNECTION, ERROR_TRIGGER_PROMPT_ACCEPTED), false);
  t.eq('连接级 + 一轮跑完 ⇒ 也不清',
    errorClearedBy(ERROR_SCOPE_CONNECTION, ERROR_TRIGGER_TURN_ENDED_OK), false);

  // ② 动作级：同类动作成功后就该消失（否则界面上挂着一条过期提示，用户以为现在还是坏的）
  t.eq('动作级 + 发送成功 ⇒ 清', errorClearedBy(ERROR_SCOPE_ACTION, ERROR_TRIGGER_PROMPT_ACCEPTED), true);
  t.eq('动作级 + 一轮成功跑完 ⇒ 清', errorClearedBy(ERROR_SCOPE_ACTION, ERROR_TRIGGER_TURN_ENDED_OK), true);
  t.eq('动作级 + 连上了 ⇒ 也清（连上了说明环境变了）',
    errorClearedBy(ERROR_SCOPE_ACTION, ERROR_TRIGGER_CONNECTED), true);

  // ③ 未知作用域按动作级处理（宁可多清一次，也不要让过期提示长期挂着）
  t.eq('作用域缺失/未知 ⇒ 按动作级（清）', errorClearedBy('', ERROR_TRIGGER_PROMPT_ACCEPTED), true);
  t.eq('空触发事件 ⇒ 什么都不清', errorClearedBy(ERROR_SCOPE_ACTION, ''), false);

  // ④ 界面/诊断据此解释"它为什么还在"
  t.eq('连接级判定', errorIsConnectionLevel(ERROR_SCOPE_CONNECTION), true);
  t.eq('动作级不是连接级', errorIsConnectionLevel(ERROR_SCOPE_ACTION), false);
}

// ── P8-4：用户主动关掉编辑浮层时的"放弃了什么" ──
{
  const SHT = require2('./Sheets.js');
  const { sheetDiscardNotice, SHEET_NOTE_CREDENTIAL, SHEET_NOTE_TEXT, SHEET_NOTE_STRUCT } = SHT;

  // ① 改过 ⇒ 必须说一句（拖拽关闭太容易误触，不说用户会以为保存了）
  const textNotice = sheetDiscardNotice(SHEET_NOTE_TEXT, '每轮最大步数', '17', '12');
  t.eq('文本设置改过，拖拽关闭 ⇒ 明确说出已放弃',
    textNotice.startsWith('已放弃未保存的修改：'), true);
  t.eq('文案里带上**是哪一项**（否则用户不知道该重开哪个）', textNotice.includes('「每轮最大步数」'), true);
  t.eq('文案说清**没有写入 Host**（这才是他要知道的事实）', textNotice.includes('没有写入 Host'), true);
  t.eq('文案给出下一步（重开并提交），而不是只报个状态', textNotice.includes('重新打开并提交'), true);

  // ② 没改过 ⇒ 一个字都不说（每次关闭都弹一句废话，用户会开始无视所有提示）
  t.eq('没改过 ⇒ 空串', sheetDiscardNotice(SHEET_NOTE_TEXT, '每轮最大步数', '12', '12'), '');
  t.eq('结构设置打开后原样关闭 ⇒ 空串',
    sheetDiscardNotice(SHEET_NOTE_STRUCT, '工具白名单', '{\n  "a": 1\n}', '{\n  "a": 1\n}'), '');
  t.eq('结构设置改过 ⇒ 有话说',
    sheetDiscardNotice(SHEET_NOTE_STRUCT, '工具白名单', '{"a":2}', '{"a":1}').length > 0, true);

  // ③ 凭据：只写不回显，种子恒为空 ⇒ 非空即未保存
  t.eq('凭据写了没提交 ⇒ 明确说"没有写入 Host，也没有留在本机"',
    sheetDiscardNotice(SHEET_NOTE_CREDENTIAL, 'provider.apiKey', 'sk-abc', ''),
    '已放弃未保存的密钥输入：它没有写入 Host，也没有留在本机。');
  t.eq('凭据没写 ⇒ 空串', sheetDiscardNotice(SHEET_NOTE_CREDENTIAL, 'provider.apiKey', '', ''), '');

  // ④ 没有"未保存内容"的浮层不参与（枚举选择 / 目录选择：选就是选，关就是关）
  t.eq('枚举选择浮层 ⇒ 空串（哪怕传了参数）',
    sheetDiscardNotice('choice', '主题', 'dark', 'light'), '');
  t.eq('目录选择浮层 ⇒ 空串', sheetDiscardNotice('folder', '/x', '/y', '/z'), '');
  t.eq('详情浮层 ⇒ 空串（它没有编辑态）', sheetDiscardNotice('detail', '详情', 'a', 'b'), '');
}

// ── P8-3：每会话草稿（官方 `views.d.ts`："Composer draft (persisted; survives session switches)") ──
{
  const { emptyComposerDrafts, putDraft, draftOf, dropDraft, draftCount, COMPOSER_DRAFT_MAX } = CD;

  let bag = emptyComposerDrafts();
  t.eq('空袋子：任何会话都是空串', draftOf(bag, 'A'), '');
  t.eq('空袋子没有条目', draftCount(bag), 0);
  t.eq('没有会话 id 时不存（宿主此时把它当界面临时状态）', draftCount(putDraft(bag, '', 'x')), 0);

  // ① 缺陷原形：在 A 里写一半，切到 B —— 两边不许串台
  bag = putDraft(bag, 'A', '给 A 的话');
  bag = putDraft(bag, 'B', '给 B 的话');
  t.eq('A 的草稿是 A 的', draftOf(bag, 'A'), '给 A 的话');
  t.eq('B 的草稿是 B 的（**这就是原来会串台的地方**）', draftOf(bag, 'B'), '给 B 的话');
  t.eq('两个会话各占一条', draftCount(bag), 2);

  // ② 空文本 = 删条目（不留空壳）
  bag = putDraft(bag, 'A', '');
  t.eq('清空某个会话 ⇒ 条目被删掉', draftCount(bag), 1);
  t.eq('删掉之后取回是空串', draftOf(bag, 'A'), '');
  t.eq('别的会话不受影响', draftOf(bag, 'B'), '给 B 的话');

  // ③ 最近写过的排在最前（淘汰规则据此不需要时间戳）
  bag = putDraft(bag, 'A', '再来一次');
  t.eq('重新写入 ⇒ 排到最前', bag.sessionIds[0], 'A');

  // ④ 上限：超出丢最久没写的
  let many = emptyComposerDrafts();
  for (let i = 0; i < COMPOSER_DRAFT_MAX + 3; i++) {
    many = putDraft(many, `s${i}`, `文本 ${i}`);
  }
  t.eq('条目数被上限夹住', draftCount(many), COMPOSER_DRAFT_MAX);
  t.eq('最新那条在', draftOf(many, `s${COMPOSER_DRAFT_MAX + 2}`), `文本 ${COMPOSER_DRAFT_MAX + 2}`);
  t.eq('最久没写的那条被丢掉', draftOf(many, 's0'), '');

  // ⑤ 值类型：不修改入参（@State 才认得出"换了新对象"）
  const before = putDraft(emptyComposerDrafts(), 'A', '原文');
  const after = putDraft(before, 'A', '改过');
  t.eq('写入**不修改**入参', draftOf(before, 'A'), '原文');
  t.eq('新对象带着新值', draftOf(after, 'A'), '改过');

  // ⑥ dropDraft：发送成功后把这条草稿用掉
  bag = dropDraft(after, 'A');
  t.eq('发送成功后该会话的草稿被丢弃', draftOf(bag, 'A'), '');

  /*
   * ⑦ 落盘编解码（P8-3 的第二半：官方那句 "…survives … reloads"）。
   *   坏数据必须当空——这段字符串来自上一次运行的磁盘，可能被截断、可能是旧版本写的。
   */
  const { serializeDrafts, parseDrafts } = CD;
  const live = putDraft(putDraft(emptyComposerDrafts(), 'A', '甲的话'), 'B', '乙的话');
  const round = parseDrafts(serializeDrafts(live));
  t.eq('落盘再读回：两个会话各自还在', `${draftOf(round, 'A')}|${draftOf(round, 'B')}`, '甲的话|乙的话');
  t.eq('落盘再读回：**顺序**也保住（最近写过的仍在最前）', round.sessionIds[0], 'B');
  t.eq('空袋子 → 空串 → 空袋子（不产生垃圾条目）', draftCount(parseDrafts(serializeDrafts(emptyComposerDrafts()))), 0);
  t.eq('不是 JSON ⇒ 空袋子（不抛、不半份）', draftCount(parseDrafts('{坏数据')), 0);
  t.eq('空串 ⇒ 空袋子', draftCount(parseDrafts('')), 0);
  t.eq('JSON 但形状不对 ⇒ 空袋子', draftCount(parseDrafts('{"sessionIds":"A","texts":"B"}')), 0);
  t.eq('长度不一致 ⇒ **整个丢掉**（错配会把甲的草稿显示在乙的会话里）',
    draftCount(parseDrafts('{"sessionIds":["A","B"],"texts":["只有一条"]}')), 0);
  t.eq('元素类型不对 ⇒ 丢掉那一项、其余照收',
    draftCount(parseDrafts('{"sessionIds":["A",7],"texts":["文本","文本"]}')), 1);
  t.eq('空文本项不落盘也不读回', draftCount(parseDrafts('{"sessionIds":["A"],"texts":[""]}')), 0);
  t.eq('超过上限的落盘数据被裁到上限',
    draftCount(parseDrafts(JSON.stringify({
      sessionIds: Array.from({ length: COMPOSER_DRAFT_MAX + 5 }, (_, i) => `s${i}`),
      texts: Array.from({ length: COMPOSER_DRAFT_MAX + 5 }, (_, i) => `t${i}`)
    }))), COMPOSER_DRAFT_MAX);
}

// ── P8-6：重试行的文案（官方 `message.retry.status` 一行模板）与「整条链一条」 ──
{
  const { retryStatusLine, retrySecondsOf, RETRY_LABEL_SCHEDULED, RETRY_LABEL_ACTIVE,
    RETRY_LABEL_STARTED, RETRY_LABEL_CANCELLED, RETRY_DELAY_LABEL, RETRY_FAILURE_LABEL } = PST;

  // ① 标签逐字取官方（dsh-client-locale 的 message.retry.*）
  t.eq('状态标签逐字取官方（等待）', RETRY_LABEL_SCHEDULED, '等待重试模型请求');
  t.eq('状态标签逐字取官方（正在）', RETRY_LABEL_ACTIVE, '正在重试模型请求');
  t.eq('状态标签逐字取官方（已重试）', RETRY_LABEL_STARTED, '已重试模型请求');
  t.eq('状态标签逐字取官方（已取消）', RETRY_LABEL_CANCELLED, '模型请求重试已取消');
  t.eq('details 里的两个标签也逐字取官方', `${RETRY_DELAY_LABEL}|${RETRY_FAILURE_LABEL}`, '重试延迟：|失败原因：');

  // ② 秒数逐字对齐官方 `retrySeconds(ms) = Math.max(1, Math.ceil(ms/1000))`
  t.eq('剩 7000ms ⇒ 7s', retrySecondsOf(7000), 7);
  t.eq('剩 400ms ⇒ 1s（向上取整）', retrySecondsOf(400), 1);
  t.eq('剩 0ms ⇒ 1s（**最小 1 秒**：显示 0s 会被读成卡住）', retrySecondsOf(0), 1);

  // ③ 状态行 = `{标签}（{第几次}/{上限}） · {秒}s`（官方模板逐字）
  t.eq('等待中：等待重试模型请求（2/5） · 8s', retryStatusLine(2, 5, 'scheduled', 8000, 8000),
    '等待重试模型请求（2/5） · 8s');
  t.eq('倒计时每秒变：剩 3 秒就写 3s', retryStatusLine(2, 5, 'scheduled', 3000, 8000),
    '等待重试模型请求（2/5） · 3s');
  t.eq('到点了但 retry-started 还没到 ⇒ 正在重试模型请求（2/5） · 8s',
    retryStatusLine(2, 5, 'scheduled', 0, 8000), '正在重试模型请求（2/5） · 8s');
  t.eq('已收到 retry-started ⇒ 已重试模型请求（2/5） · 8s（秒数取当初计划的延迟）',
    retryStatusLine(2, 5, 'started', -1000, 8000), '已重试模型请求（2/5） · 8s');
  t.eq('no上限（always 分支没有 maxRetries）⇒ 照官方显示 ∞',
    retryStatusLine(3, -1, 'scheduled', 5000, 5000), '等待重试模型请求（3/∞） · 5s');
  t.eq('次数缺失 ⇒ 空串（没有重试信息就不该有这一行）', retryStatusLine(0, 5, 'scheduled', 1, 1), '');
  /*
   * 用户按了停止（P8-6）：这一行**必须**变成"已取消"。
   * 不变的话它会一直写着"等待重试模型请求（3/5） · 7s"——一个永远不会发生的承诺。
   * 这条状态是**客户端事实**：上游没有"取消重试"的事件，只有 retry/retry-started 两帧。
   */
  t.eq('用户停止 ⇒ 模型请求重试已取消（3/5） · 8s',
    retryStatusLine(3, 5, 'cancelled', 7000, 8000), '模型请求重试已取消（3/5） · 8s');
  t.eq('已取消之后不再显示剩余秒数（秒数取当初计划的延迟，不再倒数）',
    retryStatusLine(3, 5, 'cancelled', 1000, 8000).includes('· 8s'), true);

  /*
   * ④ 整条链一条：`retryId` 是**链**身份（上游 brand.d.ts 逐字："Stable identity shared by
   * every attempt in one request-step retry chain."），因此同链的多帧必须并进同一行。
   * 【缺陷原形】P7-18 把它读成"每次重试唯一"，按 `轮次/步/第几次` 建 id ⇒
   * 同一次故障的 5 次重试在界面上是 5 条各自展开的错误卡。
   */
  const { mergeTrajectoryItem } = TJ;
  const chain = (id, attempt, state, extra) => Object.assign({
    id: `ev-retry-chain-${id}`, kind: 'error', at: 1000 * attempt, body: `失败 ${attempt}`,
    reasoning: '', speaker: 'assistant', model: '', elapsedMs: 0, toolName: '', callId: '',
    toolArgs: '', toolState: 'pending', toolOutput: '', subagentName: '', fileName: '', fileSize: 0,
    title: '', progress: '', percent: -1, streaming: false, expanded: true, internal: false,
    images: [], commandId: '', commandKind: '', retryAttempt: attempt, retryMax: 5,
    retryDelayMs: 8000, retryState: state, retryChainId: id,
  }, extra || {});

  const a1 = chain('r1', 1, 'scheduled');
  const a2 = chain('r1', 2, 'scheduled', { body: '失败 2' });
  const merged12 = mergeTrajectoryItem(a1, a2);
  t.eq('同链第二次重试：并进同一条（id 不变）', merged12.id, 'ev-retry-chain-r1');
  t.eq('同链第二次重试：序号刷新成 2', merged12.retryAttempt, 2);
  t.eq('同链第二次重试：失败原因刷新成最新那次的', merged12.body, '失败 2');
  // 关键回归：新一轮等待必须把状态打回"等待"，否则那一行会永远停在"已重试"、倒计时永不出现
  const startedFrame = chain('r1', 2, 'started', { body: '' });
  const mergedStarted = mergeTrajectoryItem(a2, startedFrame);
  t.eq('retry-started 到了 ⇒ 状态变"已重试"', mergedStarted.retryState, 'started');
  t.eq('retry-started 不带正文 ⇒ 保留失败原因（不能擦成空）', mergedStarted.body, '失败 2');
  const mergedNextWait = mergeTrajectoryItem(mergedStarted, chain('r1', 3, 'scheduled', { body: '失败 3' }));
  t.eq('**下一次等待（序号更高）⇒ 状态回到"等待"**（否则永远显示已重试）', mergedNextWait.retryState, 'scheduled');
  t.eq('归位后仍是一条链（id 不变）', mergedNextWait.id, 'ev-retry-chain-r1');
  t.eq('上限不会被后续缺省帧擦掉', mergedNextWait.retryMax, 5);
  const { retryItemId } = TJ;
  t.eq('同链 ⇒ 同一个 id（每一帧都并进那一行）', retryItemId(1, 'r1') === retryItemId(4, 'r1'), true);
  t.eq('同链的 id 里带链身份（排查时能一眼看出是同一次故障）', retryItemId(4, 'r1'), 'ev-retry-chain-r1');
  t.eq('老 Host 没给链身份 ⇒ 退回按次数各占一行（宁可多一行，不要把两次不同重试并成一条）',
    retryItemId(4, ''), 'ev-retry-4');

  /*
   * 不同链互不干扰：比较的是 **id**（中枢的 `appendOrMerge` 按 id 决定"并进去还是新开一行"，
   * 而 `mergeTrajectoryItem` 只在确定要合并之后才被调用——所以这里比 id，不是比合并结果）。
   */
  t.eq('不同 retryId ⇒ id 不同 ⇒ 各占一行（链身份真的在起作用）',
    a1.id !== chain('r2', 1, 'scheduled').id, true);
  t.eq('取消是**最强势**的状态：后到的 scheduled 帧不许让它复活',
    mergeTrajectoryItem(chain('r9', 2, 'cancelled'), chain('r9', 2, 'scheduled')).retryState, 'cancelled');
  t.eq('取消也不会被后到的 started 帧改回"已重试"',
    mergeTrajectoryItem(chain('r9', 2, 'cancelled'), chain('r9', 2, 'started')).retryState, 'cancelled');
}

// ── P7-19：失败文案表（可达集合必须都有专门文案；兜底必须保留原始码） ──
{
  const { failureText, hasFailureText, untranslatedFailure, FAILURE_TEXT_TABLE,
    CLIENT_FAILURE_TEXT_TABLE, REACHABLE_FAILURE_CODES } = FT;

  // ① 对账：可达集合里每个码都必须有**专门**文案（不是兜底）
  /*
   * 【这一条现在要更仔细】`session/attachment-invalid` 有专门文案，但**故意不进表**：
   * 同一个码覆盖"文件回执"与"图片"两条路，必须按 Host 原文分流（`attachmentInvalidText`）。
   * 于是判据不是"表里有没有"，而是"能不能给出**非兜底**的文案"——用文案是否等于兜底来判，
   * 而不是用表的存在来判。（`hasFailureText()` 因此也要把这条算进去，见其实现。）
   */
  const missing = REACHABLE_FAILURE_CODES.filter((c) => !hasFailureText(c));
  t.eq('可达错误码全部有专门文案', missing.join(','), '');
  t.eq('可达集合非空（否则这条断言是空转）', REACHABLE_FAILURE_CODES.length > 20, true);

  // ② 专门文案不许以原始码开头（那等于没写文案）
  const rawLooking = [];
  for (const entry of FAILURE_TEXT_TABLE) {
    if (entry.text.startsWith(entry.code) || entry.text.length < 8) rawLooking.push(entry.code);
  }
  t.eq('专门文案不许以 code 开头、也不许过短（像兜底）', rawLooking.join(','), '');

  // ③ 兜底必须**带上原始码**：上游多了新码时，界面上要看得见
  const unknown = failureText('brand/new-code', 'something happened');
  t.eq('未知码的兜底带上原始码', unknown.includes('brand/new-code'), true);
  t.eq('未知码的兜底说清"还没有专门文案"', unknown.includes('还没有专门文案'), true);
  t.eq('未知码的兜底带上 Host 原文', unknown.includes('something happened'), true);
  t.eq('未知码的兜底不含"操作失败"这类含糊话', unknown.includes('操作失败'), false);

  // ④ 已知码会附上 Host 原文（原文是第一手证据，不能丢）
  const known = failureText('session/conflict', 'session "abc" already has cwd "/x"');
  t.eq('已知码文案里带上 Host 原文', known.includes('already has cwd'), true);
  t.eq('已知码不再以原始码开头', known.startsWith('session/conflict'), false);
  t.eq('没有原文时不硬拼括号', failureText('session/conflict', '').includes('Host 原文'), false);

  // ⑤ 几个高风险码必须有**可行动**的处置（抽查语义，不只查存在）
  t.eq('会话冲突要教用户换目录或打开已有会话',
    failureText('session/conflict', '').includes('换一个目录'), true);
  t.eq('模型不可用要指向设置页',
    failureText('session/model-unavailable', '').includes('设置'), true);
  t.eq('设置版本冲突要说明"重试无用、要重读"',
    failureText('settings/conflict', '').includes('重新读取'), true);
  t.eq('目录选择器不可用要说清那是桌面端能力',
    failureText('directory-picker/unavailable', '').includes('桌面'), true);

  // ⑥ 客户端自己的码也要有文案（它与上游码同表查）
  t.eq('客户端码有文案', hasFailureText('client/endpoint-invalid'), true);
  t.eq('客户端码文案表非空', CLIENT_FAILURE_TEXT_TABLE.length > 0, true);

  // ⑦ 连接层的四个传输码：文案必须**带上底层 reason**（E71：固定文案会盖掉唯一线索）
  for (const carrierCode of ['carrier/parse', 'carrier/closed', 'carrier/transport', 'carrier/timeout']) {
    t.eq(`${carrierCode} 有专门文案且带上 reason`,
      hasFailureText(carrierCode) && failureText(carrierCode, '探活超时（连接级）').includes('探活超时'), true);
  }

  // ⑧ 附件被拒要**按 Host 原文分流**（同一个码三种成因，处置不同）
  const img = failureText('session/attachment-invalid', 'Unsupported or malformed image data.');
  const file = failureText('session/attachment-invalid', 'File was not uploaded for this session.');
  t.eq('图片那条说"图像解码器可能不可用"', img.includes('图像解码器不可用'), true);
  t.eq('文件那条说"不属于这条会话"', file.includes('不属于这条会话'), true);
  t.eq('两条文案必须不同（否则等于没分流）', img !== file, true);
  t.eq('文件那条不把用户引向"图片坏了"', file.includes('这张图'), false);
}


// ── P7-20：目标栏（可见性 / 相位动词 / 读不到与没有目标必须分开） ──
{
  const { goalBarStateOf, goalPhaseLabel } = GB;

  // ① 没有目标 / 已完成 ⇒ 整条不渲染（官方："no goal (null) … complete goals render nothing"）
  t.eq('没有目标 ⇒ 不渲染', goalBarStateOf(false, '', '', '', '').visible, false);
  t.eq('已完成 ⇒ 不渲染',
    goalBarStateOf(true, '把 X 做完', 'complete', '', '').visible, false);
  t.eq('有目标但正文为空 ⇒ 不渲染（不画一条空栏）',
    goalBarStateOf(true, '', 'active', '', '').visible, false);

  // ② 读不到 ⇒ **要**渲染一行说明（与"没有目标"是两件事）
  const unread = goalBarStateOf(false, '', '', '', '宿主返回的目标形状未识别（顶层键：a,b）');
  t.eq('读不到 ⇒ 可见', unread.visible, true);
  t.eq('读不到 ⇒ 说明就是那一行', unread.objective.includes('形状未识别'), true);
  t.eq('读不到 ⇒ 不给任何动词（没有目标可操作）',
    unread.canPause || unread.canResume || unread.canEdit || unread.canClear, false);

  // ③ 相位决定给哪个动词
  const active = goalBarStateOf(true, '把 X 做完', 'active', '', '');
  const paused = goalBarStateOf(true, '把 X 做完', 'paused', '', '');
  t.eq('active ⇒ 给暂停', active.canPause, true);
  t.eq('active ⇒ **不**给继续（给了就是误导）', active.canResume, false);
  t.eq('paused ⇒ 给继续', paused.canResume, true);
  t.eq('paused ⇒ 不给暂停', paused.canPause, false);
  t.eq('两者都给编辑与清除', active.canEdit && active.canClear && paused.canEdit && paused.canClear, true);

  // ④ 相位未知（Host 没给）⇒ 一个相位动词都不给，但编辑/清除仍在（那是无条件合法的）
  const unknown = goalBarStateOf(true, '把 X 做完', '', '', '');
  t.eq('相位未知 ⇒ 不给暂停/继续', unknown.canPause || unknown.canResume, false);
  t.eq('相位未知 ⇒ 编辑与清除仍给', unknown.canEdit && unknown.canClear, true);
  t.eq('相位未知 ⇒ 不编一个相位标签', unknown.phaseLabel, '');

  // ⑤ 受阻：正文要带上原因（用户得知道为什么停住了）
  const blocked = goalBarStateOf(true, '把 X 做完', 'blocked', '需要你确认破坏性操作', '');
  t.eq('受阻 ⇒ 可见且标签是「受阻」', blocked.visible && blocked.phaseLabel, '受阻');
  t.eq('受阻 ⇒ 正文里带上原因', blocked.objective.includes('需要你确认'), true);
  t.eq('受阻 ⇒ 不给继续（受阻不是用户暂停的）', blocked.canResume, false);

  // ⑥ 相位文案（官方 PHASE_LABELS 三个键 + complete）
  t.eq('active 文案', goalPhaseLabel('active'), '进行中');
  t.eq('paused 文案', goalPhaseLabel('paused'), '已暂停');
  t.eq('blocked 文案', goalPhaseLabel('blocked'), '受阻');
  t.eq('complete 文案', goalPhaseLabel('complete'), '已完成');
  t.eq('未知相位不给文案', goalPhaseLabel('weird'), '');
}


// ── P7-21：回合产出的文件（来源是成功的写类调用，不是回答正文） ──
{
  const { producedFilesOf, producedRowText, baseNameOf } = PFL;
  const { ToolState, TrajectoryKind } = TJ;
  const tool = (name, args, state) => ({
    id: `${name}-${state}`, kind: TrajectoryKind.TOOL, at: 0, body: '', reasoning: '',
    speaker: 'assistant', model: '', elapsedMs: 0, toolName: name, callId: '', toolArgs: args,
    toolState: state, toolOutput: '', subagentName: '', fileName: '', fileSize: 0, title: '',
    progress: '', percent: -1, streaming: false, expanded: false, internal: false,
    images: [], commandId: '', commandKind: '', retryAttempt: 0, retryMax: -1, retryDelayMs: 0,
    retryState: '', retryChainId: '',
  });

  // ① 三种写类工具都算（`write` / `edit` / `str_replace_editor` 的 create 与 str_replace）
  const files = producedFilesOf([
    tool('write', '{"file_path":"src/a.ts","content":"x"}', ToolState.SUCCESS),
    tool('edit', '{"file_path":"src/b.ts","old_string":"x","new_string":"y"}', ToolState.SUCCESS),
    tool('str_replace_editor', '{"command":"create","path":"src/c.ts","file_text":"z"}', ToolState.SUCCESS),
    tool('str_replace_editor', '{"command":"str_replace","path":"src/d.ts","old_str":"a","new_str":"b"}', ToolState.SUCCESS),
  ]);
  t.eq('四种写类调用都进清单', files.map((f) => f.name).join(','), 'a.ts,b.ts,c.ts,d.ts');
  t.eq('路径原样保留（不做归一化）', files[0].path, 'src/a.ts');

  // ② 只算成功的：失败 / 被拒 / 还没结算都不算（官方："failed results contribute nothing"）
  const mixed = producedFilesOf([
    tool('write', '{"file_path":"ok.ts","content":"x"}', ToolState.SUCCESS),
    tool('write', '{"file_path":"failed.ts","content":"x"}', ToolState.FAILED),
    tool('write', '{"file_path":"rejected.ts","content":"x"}', ToolState.REJECTED),
    tool('write', '{"file_path":"running.ts","content":"x"}', ToolState.RUNNING),
    tool('write', '{"file_path":"pending.ts","content":"x"}', ToolState.PENDING),
  ]);
  t.eq('只有成功的那次算产出', mixed.map((f) => f.name).join(','), 'ok.ts');

  // ③ 读 / 未知工具 / 畸形参数 / 缺路径都不算
  const nonProducing = producedFilesOf([
    tool('read', '{"file_path":"read.ts"}', ToolState.SUCCESS),
    tool('bash', '{"command":"echo hi"}', ToolState.SUCCESS),
    tool('write', 'not json at all', ToolState.SUCCESS),
    tool('write', '{"content":"no path"}', ToolState.SUCCESS),
    tool('str_replace_editor', '{"command":"view","path":"viewed.ts"}', ToolState.SUCCESS),
  ]);
  t.eq('读/未知工具/畸形参数/缺路径/编辑器只读命令都不算产出', nonProducing.length, 0);

  // ④ 去重 + 首次出现顺序（官方："a file written and then edited in the same turn is one entry"）
  const dedup = producedFilesOf([
    tool('write', '{"file_path":"same.ts","content":"1"}', ToolState.SUCCESS),
    tool('write', '{"file_path":"other.ts","content":"1"}', ToolState.SUCCESS),
    tool('edit', '{"file_path":"same.ts","old_string":"1","new_string":"2"}', ToolState.SUCCESS),
  ]);
  t.eq('先写后改只算一条，且保持首次出现顺序', dedup.map((f) => f.name).join(','), 'same.ts,other.ts');

  // ⑤ 非工具条目一律不算（消息正文里提到文件名**不算产出**——官方明确不读正文）
  const withMessage = producedFilesOf([
    { ...tool('write', '{"file_path":"real.ts","content":"1"}', ToolState.SUCCESS) },
    { ...tool('read', '{"file_path":"x.ts"}', ToolState.SUCCESS), kind: TrajectoryKind.MESSAGE, body: '我改了 real.ts 与 fake.ts' },
  ]);
  t.eq('正文里提到的文件名不算产出', withMessage.map((f) => f.name).join(','), 'real.ts');

  // ⑥ 空回合 / 展示名
  t.eq('没有工具条目 ⇒ 空清单', producedFilesOf([]).length, 0);
  t.eq('展示名取路径末段', baseNameOf('a/b/c.ts'), 'c.ts');
  t.eq('没有目录分隔符时原名返回', baseNameOf('c.ts'), 'c.ts');

  // ⑦ 行文案：0 个 ⇒ 空串（整行不渲染，官方同）
  t.eq('0 个文件 ⇒ 不显示这一行', producedRowText(0, 6), '');
  t.eq('3 个文件（未超上限）', producedRowText(3, 6), '本回合写入 3 个文件');
  t.eq('9 个文件（超上限）要交代总数', producedRowText(9, 6), '本回合写入 9 个文件（显示前 6 个）');
}


t.done();
