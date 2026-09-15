/**
 * 上架合规对账门禁（P7-11）：**应用里说的**与**包里声明的**必须一致。
 *
 * ## 为什么需要它
 *
 * AppGallery 的材料分两半：控制台里填的（隐私政策、权限说明）与应用里能看到的
 * （设置里的隐私与权限说明）。两半之间最容易出的问题不是"没写"，而是**漂移**：
 * 文档说"只申请两项权限"，而 `module.json5` 里后来悄悄多了一项 ——
 * 文档看不出来、界面也看不出来，只有审核时被问出来。
 *
 * 所以这里做三件事：
 *   1. **逐项对账**：`module.json5` 的 `requestPermissions` 与
 *      `appstate/model/PrivacyDisclosure.PERMISSION_DISCLOSURES` 必须**完全一致**
 *      （多一项、少一项都红）；
 *   2. **禁用清单**：本项目刻意不申请的权限（读剪贴板、位置、相机、通讯录、存储、
 *      设备标识…）一旦出现就红 —— 它们是"最小权限"这条主张的反例；
 *   3. **界面出口存在**：设置里确实渲染了隐私说明（`privacyRow` + 权限条目），
 *      否则"应用里能看到"这句就是空话。
 *
 * 用法：node tools/check-compliance.mjs
 * 退出码：0 通过；1 不一致；3 环境受阻（读不到清单/模型文件）。
 */
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.cwd();
const MANIFEST = join(ROOT, 'entry', 'src', 'main', 'module.json5');
const MODEL = join(ROOT, 'appstate', 'src', 'main', 'ets', 'model', 'PrivacyDisclosure.ets');
const DEVICE_PANE = join(ROOT, 'entry', 'src', 'main', 'ets', 'view', 'SettingsDevice.ets');

for (const f of [MANIFEST, MODEL, DEVICE_PANE]) {
  if (!existsSync(f)) {
    console.error(`环境受阻：找不到 ${f}`);
    process.exit(3);
  }
}

/** `module.json5` 里申请的权限名（按出现顺序） */
function manifestPermissions() {
  const text = readFileSync(MANIFEST, 'utf8');
  const out = [];
  const re = /"name"\s*:\s*"(ohos\.permission\.[A-Z_]+)"/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    out.push(m[1]);
  }
  return out;
}

/** 模型里声明给用户看的权限名 */
function modelPermissions() {
  const text = readFileSync(MODEL, 'utf8');
  const out = [];
  const re = /name:\s*'(ohos\.permission\.[A-Z_]+)'/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    out.push(m[1]);
  }
  return out;
}

/**
 * 本项目刻意**不**申请的权限。
 *
 * 【为什么写死在这里而不是从别处推】它是**主张**（README 设计原则 2"不申请特殊权限"），
 * 不是一个可推导的集合。写在这里，一旦有人为了某个功能顺手加上，门禁当场拦下 ——
 * 那时候需要的是一次**有意识的决定**（改这张表 = 改产品原则），而不是悄悄多一行声明。
 */
const FORBIDDEN = [
  { name: 'ohos.permission.READ_PASTEBOARD', why: '读剪贴板（与"剪贴板只写不读"矛盾；用户粘贴走系统文本域菜单）' },
  { name: 'ohos.permission.APPROXIMATELY_LOCATION', why: '位置' },
  { name: 'ohos.permission.LOCATION', why: '精确位置' },
  { name: 'ohos.permission.CAMERA', why: '相机' },
  { name: 'ohos.permission.MICROPHONE', why: '麦克风' },
  { name: 'ohos.permission.READ_CONTACTS', why: '通讯录' },
  { name: 'ohos.permission.READ_CALENDAR', why: '日历' },
  { name: 'ohos.permission.READ_MEDIA', why: '媒体库（选文件走系统选择器，不需要此权限）' },
  { name: 'ohos.permission.WRITE_MEDIA', why: '写媒体库' },
  { name: 'ohos.permission.READ_HEALTH_DATA', why: '健康数据' },
  { name: 'ohos.permission.GET_WIFI_INFO', why: 'Wi-Fi 信息' },
  { name: 'ohos.permission.DISTRIBUTED_DATASYNC', why: '跨设备数据同步（本应用不做）' },
];

const declared = manifestPermissions();
const disclosed = modelPermissions();
const problems = [];

const declaredSet = new Set(declared);
const disclosedSet = new Set(disclosed);
for (const n of declared) {
  if (!disclosedSet.has(n)) problems.push(`  ✗ 包里申请了 ${n}，但应用内说明里没有它（用户看不到为什么）`);
}
for (const n of disclosed) {
  if (!declaredSet.has(n)) problems.push(`  ✗ 应用内说明写了 ${n}，但 module.json5 里没申请（说明在撒谎）`);
}
for (const f of FORBIDDEN) {
  if (declaredSet.has(f.name)) problems.push(`  ✗ 申请了刻意不申请的权限 ${f.name}（${f.why}）`);
}
// 界面出口：设置里必须真的渲染这两段
const pane = readFileSync(DEVICE_PANE, 'utf8');
for (const anchor of ['privacyRow', 'PERMISSION_DISCLOSURES', 'DATA_PRACTICES']) {
  if (!pane.includes(anchor)) problems.push(`  ✗ 设置页没有渲染隐私说明（缺 ${anchor}）`);
}

/**
 * ───────────────── 包元数据与资源（AGC 提审预检，P7-12） ─────────────────
 *
 * 【为什么与上面那段合在一个门禁里】两者回答同一个问题："这份包能不能提交"。
 * 上面管"说的与声明的一致"，这里管"提审要看的字段与资源真的在且能用"。
 * 拆成两个脚本只会让人少跑一个——而这个项目的教训正是"少跑的那个等于不存在"。
 *
 * 【为什么值得做】这些字段**错了不会构建失败**：
 *   · `deviceTypes` 少写一个 ⇒ 那种设备**装不上**（上架后才发现，看起来像"不兼容"）；
 *   · `abilities[].skills` 少了桌面入口 ⇒ 装上了但**桌面没有图标**；
 *   · `$string:app_name` 指向空串 ⇒ 应用名是空白；
 *   · 图标引用指向不存在的文件 ⇒ 构建期会报错，但**指向存在却非法的文件**不会。
 * 全都可以在本地判定，没有理由留给审核去发现。
 */
const APP_SCOPE = join(ROOT, 'AppScope', 'app.json5');
const BUILD_PROFILE = join(ROOT, 'build-profile.json5');
const APP_SCOPE_RES = join(ROOT, 'AppScope', 'resources');
const ENTRY_RES = join(ROOT, 'entry', 'src', 'main', 'resources');

/** 极简 JSON5 读取：丢掉行注释/块注释与尾逗号（够读这些配置文件，不引入依赖） */
function readJson5(file) {
  const raw = readFileSync(file, 'utf8');
  const stripped = raw
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter((line) => !/^\s*\/\//.test(line))
    .join('\n')
    .replace(/,(\s*[}\]])/g, '$1');
  return JSON.parse(stripped);
}

/** 收集某个 resources 目录下 element/*.json 里的资源名（按类型） */
function elementNames(resDir, kind) {
  const dir = join(resDir, 'base', 'element');
  const out = new Set();
  if (!existsSync(dir)) return out;
  for (const f of readdirSync(dir)) {
    if (!f.endsWith('.json')) continue;
    let parsed;
    try {
      parsed = readJson5(join(dir, f));
    } catch {
      continue;
    }
    const list = parsed[kind];
    if (Array.isArray(list)) {
      for (const item of list) {
        if (item && typeof item.name === 'string') out.add(item.name);
      }
    }
  }
  return out;
}

/** 某个 resources 目录下 media/ 里的资源名（去扩展名） */
function mediaNames(resDir) {
  const dir = join(resDir, 'base', 'media');
  const out = new Set();
  if (!existsSync(dir)) return out;
  for (const f of readdirSync(dir)) {
    out.add(f.replace(/\.[^.]+$/, ''));
  }
  return out;
}

/** `$media:x` / `$string:x` / `$color:x` → `{kind, name}`（不是资源引用则 undefined） */
function resourceRef(value) {
  if (typeof value !== 'string') return undefined;
  const m = /^\$([a-z]+):(.+)$/.exec(value);
  return m === null ? undefined : { kind: m[1], name: m[2] };
}

/** 一个资源引用在 AppScope 与 entry 两处是否至少一处可解析 */
function resourceResolves(ref) {
  for (const resDir of [APP_SCOPE_RES, ENTRY_RES]) {
    if (ref.kind === 'media' && mediaNames(resDir).has(ref.name)) return true;
    if (ref.kind !== 'media' && elementNames(resDir, ref.kind).has(ref.name)) return true;
  }
  return false;
}

/** 某个 `$string:` 引用的全部取值（用于判"存在但是空串"） */
function stringValues(name) {
  const out = [];
  for (const resDir of [APP_SCOPE_RES, ENTRY_RES]) {
    const dir = join(resDir, 'base', 'element');
    if (!existsSync(dir)) continue;
    for (const f of readdirSync(dir)) {
      if (!f.endsWith('.json')) continue;
      let parsed;
      try {
        parsed = readJson5(join(dir, f));
      } catch {
        continue;
      }
      for (const item of parsed.string ?? []) {
        if (item.name === name) out.push(String(item.value ?? ''));
      }
    }
  }
  return out;
}

/** 图标是**合法 PNG** 吗（存在但内容非法不会让构建失败） */
function pngSize(file) {
  if (!existsSync(file)) return undefined;
  const buf = readFileSync(file);
  if (buf.length < 24 || buf[0] !== 0x89 || buf[1] !== 0x50 || buf[2] !== 0x4E || buf[3] !== 0x47) {
    return undefined;
  }
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

const metaProblems = [];
function metaCheck(condition, message) {
  if (!condition) metaProblems.push(message);
}

if (!existsSync(APP_SCOPE) || !existsSync(BUILD_PROFILE)) {
  console.error(`环境受阻：找不到 ${APP_SCOPE} 或 ${BUILD_PROFILE}`);
  process.exit(3);
}

const appConfig = readJson5(APP_SCOPE).app;
const profile = readJson5(BUILD_PROFILE);
const product = (profile.app?.products ?? [])[0];
const moduleConfig = readJson5(MANIFEST).module;

// ① 应用身份
metaCheck(/^[a-z][a-z0-9]*(\.[a-z0-9]+)+$/.test(String(appConfig.bundleName)),
  `  ✗ bundleName 不像反向域名：${appConfig.bundleName}（上架后不可改）`);
metaCheck(typeof appConfig.vendor === 'string' && appConfig.vendor.trim().length > 0,
  '  ✗ app.vendor 为空（AGC 要开发者名）');
metaCheck(Number.isInteger(appConfig.versionCode) && appConfig.versionCode > 0,
  `  ✗ versionCode 必须是正整数：${appConfig.versionCode}`);
metaCheck(/^\d+\.\d+\.\d+$/.test(String(appConfig.versionName)),
  `  ✗ versionName 必须是 x.y.z：${appConfig.versionName}`);
metaCheck(resourceRef(appConfig.icon) !== undefined, '  ✗ app.icon 不是资源引用');
metaCheck(resourceRef(appConfig.label) !== undefined, '  ✗ app.label 不是资源引用');

// ② 构建目标
metaCheck(product?.runtimeOS === 'HarmonyOS',
  `  ✗ products[0].runtimeOS 不是 HarmonyOS：${product?.runtimeOS}`);
metaCheck(typeof product?.targetSdkVersion === 'string' && product.targetSdkVersion.length > 0,
  '  ✗ products[0] 缺 targetSdkVersion');
metaCheck(typeof product?.compatibleSdkVersion === 'string' && product.compatibleSdkVersion.length > 0,
  '  ✗ products[0] 缺 compatibleSdkVersion');
const modes = (profile.app?.buildModeSet ?? []).map((m) => m.name);
metaCheck(modes.includes('release'), `  ✗ buildModeSet 里没有 release：${modes.join('/')}`);

// ③ 模块与形态（**deviceTypes 少一个 = 那种设备装不上**）
metaCheck(moduleConfig.type === 'entry', `  ✗ module.type 应为 entry：${moduleConfig.type}`);
for (const t of ['phone', 'tablet', '2in1']) {
  metaCheck((moduleConfig.deviceTypes ?? []).includes(t),
    `  ✗ deviceTypes 缺 ${t}（本项目三形态目标：手机 / 平板 / PC-2in1）`);
}
metaCheck(moduleConfig.deliveryWithInstall === true, '  ✗ deliveryWithInstall 应为 true');
metaCheck(moduleConfig.installationFree === false, '  ✗ installationFree 应为 false（本应用不是元服务）');

// ④ 桌面入口
const abilities = moduleConfig.abilities ?? [];
const mainAbility = abilities.find((a) => a.name === moduleConfig.mainElement);
metaCheck(mainAbility !== undefined, `  ✗ mainElement(${moduleConfig.mainElement}) 不在 abilities 里`);
if (mainAbility !== undefined) {
  const entities = (mainAbility.skills ?? []).flatMap((s) => s.entities ?? []);
  const actions = (mainAbility.skills ?? []).flatMap((s) => s.actions ?? []);
  metaCheck(entities.includes('entity.system.home') && actions.includes('ohos.want.action.home'),
    '  ✗ 桌面入口缺 entity.system.home / ohos.want.action.home（装上后桌面没有图标）');
  metaCheck(mainAbility.exported === true, '  ✗ 主 ability 的 exported 应为 true');
  for (const field of ['icon', 'label', 'startWindowIcon', 'startWindowBackground']) {
    metaCheck(resourceRef(mainAbility[field]) !== undefined,
      `  ✗ ability.${field} 不是资源引用：${mainAbility[field]}`);
  }
}

// ⑤ 资源引用真的要能解析（并排除"存在但是空串"）
const refs = [appConfig.icon, appConfig.label];
if (mainAbility !== undefined) {
  for (const field of ['icon', 'label', 'startWindowIcon', 'startWindowBackground']) {
    refs.push(mainAbility[field]);
  }
}
for (const value of refs) {
  const ref = resourceRef(value);
  if (ref !== undefined && !resourceResolves(ref)) {
    metaCheck(false, `  ✗ 资源引用解析不到：${value}（AppScope 与 entry 两处都没有）`);
  }
}
for (const [label, value] of [['应用名', appConfig.label], ['ability 名', mainAbility?.label]]) {
  const ref = resourceRef(value);
  if (ref !== undefined && ref.kind === 'string') {
    metaCheck(stringValues(ref.name).some((v) => v.trim().length > 0),
      `  ✗ ${label}（${value}）是空串——审核与用户看到的会是空白`);
  }
}

// ⑥ 图标文件确实是 PNG
const iconFiles = [
  join(APP_SCOPE_RES, 'base', 'media', 'foreground.png'),
  join(APP_SCOPE_RES, 'base', 'media', 'background.png'),
  join(ENTRY_RES, 'base', 'media', 'startIcon.png'),
];
for (const f of iconFiles) {
  metaCheck(pngSize(f) !== undefined, `  ✗ 图标不是合法 PNG：${relative(ROOT, f)}`);
}

console.log('# 上架合规对账（应用内说明 ↔ module.json5）\n');
console.log(`包内申请：${declared.join('、')}`);
console.log(`应用内说明：${disclosed.join('、')}`);
console.log(`禁用清单：${FORBIDDEN.length} 项（读剪贴板 / 位置 / 相机 / 麦克风 / 通讯录 / 媒体 / Wi-Fi / 跨设备…）`);

console.log(`包元数据：bundleName=${appConfig.bundleName} · versionCode=${appConfig.versionCode}`
  + ` · 形态=${(moduleConfig.deviceTypes ?? []).join('/')} · mainElement=${moduleConfig.mainElement}`);
for (const f of iconFiles) {
  const size = pngSize(f);
  if (size !== undefined) console.log(`  · ${relative(ROOT, f)}：${size.width}×${size.height}`);
}

if (problems.length === 0 && metaProblems.length === 0) {
  console.log('\n✅ 通过：权限与应用内说明逐项一致、无禁用权限、设置页有隐私出口；');
  console.log('   包元数据与资源引用全部可解析（bundleName / 三形态 / 桌面入口 / 图标 / 名称非空）。');
  process.exit(0);
}
if (problems.length > 0) {
  console.log('\n发现不一致：');
  for (const p of problems) console.log(p);
}
if (metaProblems.length > 0) {
  console.log('\n包元数据问题（AGC 提审会看到，或某种设备装不上）：');
  for (const p of metaProblems) console.log(p);
}
console.log('\n处置：权限与应用内说明必须同时改（对账门禁不允许单边改动）；'
  + '元数据问题见 docs/70-上架合规自查.md §1 与 §6.4。');
process.exit(1);
