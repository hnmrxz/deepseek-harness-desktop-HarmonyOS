/**
 * 出**上架包**（release HAP）——一条命令，且**先检查再构建**。
 *
 * ## 为什么要有这个工具
 *
 * release 构建此前只能手工敲：要自己拼 `DEVECO_CLI_CLT_PATH` / `DEVECO_SDK_HOME` / `JAVA_HOME`
 * 三个环境变量，跑完还得自己从 hvigor 的输出里分辨"是编译失败还是签名失败"。
 * 于是它一直被当成"以后再说"的事 —— 而**上架要求的第一条就是"能重复地产出发布包"**。
 *
 * 三件事收在这里：
 *   1. **前置检查签名材料**（`build-profile.json5` 的 signingConfigs 指向的 .p12/.cer/.p7b
 *      在不在本机）。不在就直接说清楚"会产出未签名包 + 上架前还差什么"，而不是让用户
 *      在两分钟构建之后才看到一句 `Invalid storeFile value`；
 *   2. 用**正确的一套环境变量**跑 `hvigorw assembleHap -p buildMode=release`；
 *   3. **报告产物**：签名状态、体积构成（Top 条目）、以及**可疑内容**（sourcemap / 测试包 /
 *      `.ts` 源码）——上架包不该带这些东西。
 *
 * ## 用法
 *
 *   node tools/build-release.mjs            # 检查 + 构建 + 报告
 *   node tools/build-release.mjs --check    # 只做前置检查（不构建，秒级）
 *
 * 退出码：0 = 构建成功（**未签名也返回 0**，因为"没签名"是材料问题不是构建问题，报告里会写清）；
 *        1 = 构建失败；3 = 环境受阻（找不到 CLT / Java / hvigor）。
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const ROOT = process.cwd();
const CHECK_ONLY = process.argv.includes('--check');

function die(message, code) {
  console.error(message);
  process.exit(code);
}

/** 找 DevEco Command Line Tools（与 `check-arkts-entry.mjs` 同一套判据） */
function findClt() {
  const candidates = [];
  if (process.env.DEVECO_CLI_CLT_PATH) candidates.push(process.env.DEVECO_CLI_CLT_PATH);
  candidates.push('/home/node/deveco-clt/command-line-tools');
  for (const c of candidates) {
    if (existsSync(join(c, 'hvigor', 'bin', 'hvigorw.js'))) return c;
  }
  return null;
}

/**
 * 读签名配置里的三个文件路径。
 *
 * 【为什么是正则而不是 JSON5 解析】`build-profile.json5` 带注释与尾逗号，标准 `JSON.parse`
 * 读不了；为此引一个 JSON5 依赖不值当。**本函数只用于"文件在不在"的体检**，
 * 不参与构建 —— 真正的解析由 hvigor 做，所以这里宽松取字符串就够了（缺字段也就是少一条检查）。
 */
function signingPaths() {
  const file = join(ROOT, 'build-profile.json5');
  if (!existsSync(file)) return [];
  const text = readFileSync(file, 'utf8');
  const start = text.indexOf('"signingConfigs"');
  if (start < 0) return [];
  const block = text.slice(start);
  const out = [];
  for (const key of ['certpath', 'profile', 'storeFile']) {
    const re = new RegExp(`"${key}"\\s*:\\s*"([^"]*)"`, 'g');
    const m = re.exec(block);
    if (m !== null && m[1].length > 0) out.push({ key, path: m[1] });
  }
  return out;
}

console.log('# 出上架包（release HAP）\n');

// ───────────────────── ① 前置检查：签名材料 ─────────────────────
const paths = signingPaths();
const missing = paths.filter((p) => !existsSync(p.path));
if (paths.length === 0) {
  console.log('⚠️  build-profile.json5 里没读到 signingConfigs —— 产物会是**未签名包**。');
} else if (missing.length > 0) {
  console.log('⚠️  签名材料不在本机：');
  for (const p of missing) console.log(`     缺 ${p.key}：${p.path}`);
  console.log('    ⇒ 构建仍会进行，但停在 SignHap，产出**未签名 HAP**。');
  console.log('    ⇒ 上架要在 AGC 生成**发布证书**（.cer）与**发布 Profile**（.p7b）并在 DevEco 里配好；');
  console.log('      步骤与注意事项见 docs/70-上架合规自查.md §6.2。');
} else {
  console.log(`✅ 签名材料齐备（${paths.length} 个文件都在本机）。`);
}

if (CHECK_ONLY) {
  console.log('\n（--check：只做前置检查，不构建）');
  process.exit(0);
}

// ───────────────────── ② 构建 ─────────────────────
const clt = findClt();
if (clt === null) die('环境受阻：找不到 DevEco CLT（需含 hvigor/bin/hvigorw.js）。设 DEVECO_CLI_CLT_PATH 后重跑。', 3);
const javaHome = process.env.JAVA_HOME || '/home/node/jdk/jdk-17.0.20.1+1';
if (!existsSync(join(javaHome, 'bin', 'java'))) die(`环境受阻：找不到 Java（${javaHome}）。设 JAVA_HOME 后重跑。`, 3);

const hvigorw = join(clt, 'hvigor', 'bin', 'hvigorw.js');
const childEnv = {
  ...process.env,
  DEVECO_CLI_CLT_PATH: clt,
  DEVECO_SDK_HOME: join(clt, 'sdk'),
  PATH: `${join(javaHome, 'bin')}:${process.env.PATH || ''}`,
};
console.log('\n构建：hvigorw assembleHap --mode module -p buildMode=release（约 1–2 分钟）');
const run = spawnSync(process.execPath,
  [hvigorw, 'assembleHap', '--mode', 'module', '-p', 'product=default', '-p', 'buildMode=release', '--no-daemon'],
  { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, env: childEnv });
const out = `${run.stdout ?? ''}${run.stderr ?? ''}`;
const failed = /BUILD FAILED/.test(out);
const signFailed = /Failed :entry:default@SignHap/.test(out);
const succeeded = /BUILD SUCCESSFUL/.test(out);

// 关键结论行（把 hvigor 的长输出压成几行，失败时再让人去看日志）
for (const line of out.split('\n')) {
  if (/Failed :|BUILD (SUCCESSFUL|FAILED)|Error Message|Invalid storeFile|00303|00304/.test(line)) {
    console.log(`   ${line.replace(/\u001b\[[0-9;]*m/g, '').trim()}`);
  }
}

// ───────────────────── ③ 报告产物 ─────────────────────
function findHaps(dir, out2) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch (error) {
    return out2;
  }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) findHaps(p, out2);
    else if (e.name.endsWith('.hap')) out2.push(p);
  }
  return out2;
}

const haps = findHaps(join(ROOT, 'entry', 'build'), []);
console.log('\n产物：');
if (haps.length === 0) {
  console.log('   （没有 .hap —— 构建没走到打包）');
} else {
  for (const hap of haps) {
    const size = statSync(hap).size;
    const signed = !hap.endsWith('-unsigned.hap');
    console.log(`   ${hap.replace(`${ROOT}/`, '')}`);
    console.log(`     体积 ${(size / 1048576).toFixed(1)} MB · ${signed ? '**已签名**' : '未签名（签名材料缺失，见上）'}`);
    let listing = '';
    try {
      listing = execFileSync('unzip', ['-l', hap], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    } catch (error) {
      console.log('     （unzip 不可用，跳过内容体检）');
      continue;
    }
    const rows = [];
    for (const line of listing.split('\n')) {
      const m = line.match(/^\s*(\d+)\s+\S+\s+\S+\s+(.+)$/);
      if (m !== null) rows.push({ size: Number(m[1]), name: m[2].trim() });
    }
    const top = rows.slice().sort((a, b) => b.size - a.size).slice(0, 5);
    console.log('     Top 体积：');
    for (const r of top) console.log(`       ${(r.size / 1048576).toFixed(1)} MB  ${r.name}`);
    /*
     * 可疑内容体检：上架包里不该有 sourcemap、测试包、TypeScript 源码。
     * 【为什么值得专门看】它们不影响功能，属于"不该发出去的东西"，
     * 一旦发出去就是把内部实现与测试暴露给下载者。
     */
    const suspicious = rows.filter((r) => /\.map$|\/ohosTest\/|\/test\/|\.ts$|\.ets$/.test(r.name));
    console.log(`     可疑内容：${suspicious.length === 0 ? '无（无 sourcemap / 测试包 / 源码）' : suspicious.map((r) => r.name).join('、')}`);
  }
}

if (failed && !succeeded) {
  console.log(signFailed
    ? '\n结论：**编译与打包都通过，只差签名**（签名材料不在本机 ⇒ 产出未签名 HAP 属预期）。'
    : '\n结论：构建失败（不是签名问题）——请按上面的 ERROR 行排查。');
  process.exit(signFailed ? 0 : 1);
}
console.log(succeeded ? '\n结论：release 构建成功。' : '\n结论：没拿到结论行，**不得当作成功**。');
process.exit(succeeded ? 0 : 1);
