/**
 * 死按钮扫描器（E130）。
 *
 * 【为什么需要它】"界面上有、点了没反应"是本项目反复出现的缺陷形态：
 * 早期是「添加」工作区（死入口）、「市场」按钮、`onPickModel` 空实现……
 * 每一次都是**靠人眼在截图里发现**的。这个脚本把这件事变成可复跑的检查：
 * 扫出所有**空箭头函数体**（`=> {}` / 只含注释）与**空方法体**，
 * 它们在 UI 里几乎总意味着一个点了没反应的控件。
 *
 * 用法：node tools/check-dead-handlers.mjs [--all]
 *   默认只报 UI 目录（entry/platform 的 ets 视图与页面）；
 *   `--all` 扫全部 ets 源码（含 appstate/dshcompat，那里的空实现可能是**有意**的默认值）。
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.cwd();
const ALL = process.argv.includes('--all');
const ROOTS = ALL
  ? ['entry/src/main/ets', 'platform/src/main/ets', 'appstate/src/main/ets', 'dshcompat/src/main/ets']
  : ['entry/src/main/ets', 'platform/src/main/ets'];

/** 递归收集 .ets 文件 */
function filesUnder(dir) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const name of entries) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) {
      out.push(...filesUnder(full));
    } else if (name.endsWith('.ets')) {
      out.push(full);
    }
  }
  return out;
}

/**
 * 去掉注释与字符串字面量，避免把 `=> {}` 写在注释里误报。
 *
 * 【必须保留换行】第一版把块注释整段换成空格 ⇒ 行号与原文错位，
 * 于是报出一堆"空实现"其实指向 `@Prop`、注释行（假阳性比漏报更糟：
 * 它会让人不再相信这份报告）。这里按字符替换、**保留每个 `\n`**。
 */
function stripNoise(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/\/\/[^\n]*/g, '');
}

/**
 * 【2026-09-17（第 63 轮）：把"可选回调的默认实现"排除掉，让这条门禁重新有用】
 *
 * 原判据报出 **193 处 / 43 个文件**——翻开一看全是同一种写法：
 *
 *     onClose: () => void = () => {
 *     };
 *
 * 这是 ArkUI 里给**回调 prop 声明安全默认值**的标准写法（父组件不传也不能崩），
 * 它**不是**"点了没反应"——真正的死按钮是**调用点**上传了个空实现
 * （`onPickModel: () => {}` 这种，E130 当初要抓的正是它）。
 *
 * 一条**永远红、193 行**的门禁比没有门禁更糟：没人会读它，于是它谁也不保护。
 * 所以这里把判据收窄成"**有类型标注的成员声明 + 空箭头默认值**"这一种形态**不报**，
 * 其余空箭头/空方法照报。
 *
 * 判据长这样：`名字: (…) => 返回类型 = () => {` —— 中间那个 `=` 是"默认值"的信号；
 * 调用点传参不会带这个 `=`（那才是可疑的那种）。
 */
function isOptionalCallbackDefault(line, prevLine) {
  // ① 一行写完：`名字: (…) => 类型 = () => {`
  if (/^\s*(private\s+|public\s+|protected\s+)?[A-Za-z_$][\w$]*\s*:\s*\([^)]*\)\s*=>\s*[^=]+=\s*\([^)]*\)\s*=>\s*\{\s*$/.test(line)) {
    return true;
  }
  // ② 类型标注太长被折行：上一行以 `=` 结尾（默认值另起一行）——
  //    这是同一件事的另一种排版，不认它就会漏掉一批良性项。
  return /=\s*$/.test(prevLine ?? '');
}

/** 容器/构建器的**调用**：`Column() {`、`Row({...}) {` —— 空体是"什么都不画"，不是死方法 */
function isContainerInvocation(line) {
  return /^\s*(Column|Row|Stack|Flex|List|Grid|Scroll|SideBarContainer|RelativeContainer)\s*\(.*\)\s*\{\s*$/.test(line);
}

/** 返回一个"什么都不做"的清理函数（没订阅就没什么可退订）——不是按钮处理器 */
function isReturnedNoop(line) {
  return /^\s*return\s*\([^)]*\)\s*=>\s*\{\s*$/.test(line);
}

const hits = [];
for (const dir of ROOTS) {
  for (const file of filesUnder(join(ROOT, dir))) {
    const raw = readFileSync(file, 'utf8');
    const clean = stripNoise(raw);
    const lines = clean.split('\n');
    for (let i = 0; i < lines.length; i++) {
      // 空箭头函数体：`=> {}` 或 `=> {` 紧跟 `}`
      if (/=>\s*\{\s*\}/.test(lines[i])) {
        hits.push({ file, line: i + 1, kind: '空箭头函数体', text: raw.split('\n')[i].trim() });
        continue;
      }
      if (/=>\s*\{\s*$/.test(lines[i])) {
        const next = (lines[i + 1] ?? '').trim();
        if (next === '}' || next === '},' || next === '};') {
          // 可选回调的默认实现 / 返回的空清理函数：都不报（理由见各自函数头）
          // 或者**上一行有注释**——本仓的规矩是"说不出理由的空实现就是缺陷"，
          // 反过来说：**写明了理由**的空实现（"这是诚实的空实现，因为…"）不报。
          const prevRaw = (raw.split('\n')[i - 1] ?? '').trim();
          const documented = prevRaw.includes('//') || prevRaw.endsWith('*/') || prevRaw.endsWith('*');
          if (!isOptionalCallbackDefault(lines[i], lines[i - 1]) && !isReturnedNoop(lines[i]) && !documented) {
            hits.push({ file, line: i + 1, kind: '空箭头函数体（跨行）', text: raw.split('\n')[i].trim() });
          }
        }
      }
      // 空方法体：`name(...) {` 紧跟 `}`
      if (/^\s{2,}[a-zA-Z_$][\w$]*\([^)]*\)\s*\{\s*$/.test(lines[i]) && !isContainerInvocation(lines[i])) {
        const next = (lines[i + 1] ?? '').trim();
        if (next === '}') {
          hits.push({ file, line: i + 1, kind: '空方法体', text: raw.split('\n')[i].trim() });
        }
      }
    }
  }
}

const rel = (f) => relative(ROOT, f).replace(/\\/g, '/');
if (hits.length === 0) {
  console.log(`死按钮扫描：未发现空实现（范围 ${ROOTS.join(', ')}）`);
  process.exit(0);
}
console.log(`死按钮扫描：发现 ${hits.length} 处空实现（需逐条判断：空实现常常就是"点了没反应"）`);
for (const h of hits) {
  console.log(`  ${rel(h.file)}:${h.line}  [${h.kind}]  ${h.text.slice(0, 90)}`);
}
process.exit(1);
