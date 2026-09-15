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
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

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

console.log('# 上架合规对账（应用内说明 ↔ module.json5）\n');
console.log(`包内申请：${declared.join('、')}`);
console.log(`应用内说明：${disclosed.join('、')}`);
console.log(`禁用清单：${FORBIDDEN.length} 项（读剪贴板 / 位置 / 相机 / 麦克风 / 通讯录 / 媒体 / Wi-Fi / 跨设备…）`);

if (problems.length === 0) {
  console.log('\n✅ 通过：声明的权限与应用内说明逐项一致，没有出现刻意不申请的权限，设置页有隐私说明出口。');
  process.exit(0);
}
console.log('\n发现不一致：');
for (const p of problems) console.log(p);
console.log('\n处置：权限与应用内说明必须同时改（对账门禁不允许单边改动）。');
process.exit(1);
