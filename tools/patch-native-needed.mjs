#!/usr/bin/env node
/*
 * 原地改写 ELF 共享库的某个 DT_NEEDED 字符串。
 *
 * 【为什么需要它】真机实测（D6 E44/E45）：
 *   koffi 的 .node 由 Node 的 `process.dlopen` 载入时，报
 *       Error relocating …/libs/arm64/libkoffi.so: napi_fatal_error: symbol not found
 *   读数（同一进程内并列打印）：
 *       dlsym(RTLD_DEFAULT, "napi_fatal_error")  -> /system/lib64/platformsdk/libace_napi.z.so
 *       dlsym(RTLD_DEFAULT, "napi_get_undefined") -> 同一个
 *       dlopen(libkoffi.so)                        -> 仍然 symbol not found
 *   而 `napi_fatal_error` 是 libkoffi.dynsym 里**序号最小的** napi 符号（index 5，紧随其后的
 *   index 15/16 是 `uv_poll_start`/`uv_strerror`）⇒ 加载器只是报了第一个失败者，真实情况是
 *   **koffi 的重定位作用域里一个 Node 运行期符号都没有**：dlopen 出来的对象只按
 *   「自身 + 自身依赖闭包 + 全局组」解析，而 libnode 既不（有效地）进全局组，也不在它的闭包里。
 *
 * 【为什么改写而不是新增】新增一条 DT_NEEDED 要动 .dynamic/.dynstr 的结构（需要 patchelf）；
 * 而 `libc++_shared.so`（16 字节）比 `libnode.so.127`（14 字节）长，**原地替换 + NUL 补齐**
 * 不改变任何长度与偏移，是零结构风险的改动。libc++ 不会因此丢失：libnode.so.127 自己就
 * DT_NEEDED libc++_shared.so，会随 libnode 一起进入 koffi 的依赖闭包（传递依赖同样参与解析）。
 *
 * 用法：
 *   node tools/patch-native-needed.mjs <so 路径> <原 NEEDED> <新 NEEDED> [--check|--revert]
 *   --check   只报告当前值，不写文件
 *   --revert  从 <so>.orig 备份还原
 * 幂等：已是目标值时直接跳过；原值不存在时报错而非静默成功。
 */
import { copyFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';

const ELF_MAGIC = 0x7f454c46;
const SHT_STRTAB = 3;
const DT_NULL = 0;
const DT_NEEDED = 1;

function fail(message) {
  console.error(`patch-native-needed: ${message}`);
  process.exit(1);
}

/** 解析 ELF64 LE 的节表，返回 [{name, offset, size, type}] 与总入口数。 */
function readSections(buf) {
  if (buf.readUInt32BE(0) !== ELF_MAGIC) fail('不是 ELF 文件');
  if (buf[4] !== 2) fail('只支持 ELF64');
  if (buf[5] !== 1) fail('只支持小端');
  const eShoff = Number(buf.readBigUInt64LE(0x28));
  const eShentsize = buf.readUInt16LE(0x3a);
  const eShnum = buf.readUInt16LE(0x3c);
  const eShstrndx = buf.readUInt16LE(0x3e);
  if (eShoff === 0 || eShnum === 0) fail('没有节表（被 strip 掉的库无法用本工具）');
  const raw = [];
  for (let i = 0; i < eShnum; i += 1) {
    const base = eShoff + i * eShentsize;
    raw.push({
      nameOff: buf.readUInt32LE(base),
      type: buf.readUInt32LE(base + 4),
      offset: Number(buf.readBigUInt64LE(base + 0x18)),
      size: Number(buf.readBigUInt64LE(base + 0x20)),
    });
  }
  if (eShstrndx >= raw.length) fail('e_shstrndx 越界');
  const shstr = raw[eShstrndx];
  const nameOf = (off) => {
    const start = shstr.offset + off;
    let end = start;
    while (end < buf.length && buf[end] !== 0) end += 1;
    return buf.toString('utf8', start, end);
  };
  for (const section of raw) section.name = nameOf(section.nameOff);
  return raw;
}

const [soPath, oldNeeded, newNeeded, mode] = process.argv.slice(2);
if (!soPath || !oldNeeded || !newNeeded) {
  fail('用法：patch-native-needed.mjs <so 路径> <原 NEEDED> <新 NEEDED> [--check|--revert]');
}
if (newNeeded.length > oldNeeded.length) {
  fail(`新串更长（${newNeeded.length} > ${oldNeeded.length}），原地改写放不下`);
}
if (!existsSync(soPath)) fail(`文件不存在：${soPath}`);

const backupPath = `${soPath}.orig`;
if (mode === '--revert') {
  if (!existsSync(backupPath)) fail(`没有备份可还原：${backupPath}`);
  copyFileSync(backupPath, soPath);
  console.log(`已还原 ${soPath} ← ${backupPath}`);
  process.exit(0);
}

const buf = readFileSync(soPath);
const sections = readSections(buf);
const dynstr = sections.find((s) => s.name === '.dynstr');
const dynamic = sections.find((s) => s.name === '.dynamic');
if (dynstr === undefined || dynamic === undefined) fail('缺少 .dynstr 或 .dynamic');

/** 逐个读 .dynamic 里的 DT_NEEDED，返回 {entryOffset, strOffset, value}。 */
function neededEntries() {
  const out = [];
  for (let off = dynamic.offset; off + 16 <= dynamic.offset + dynamic.size; off += 16) {
    const tag = Number(buf.readBigUInt64LE(off));
    if (tag === DT_NULL) break;
    if (tag !== DT_NEEDED) continue;
    const value = Number(buf.readBigUInt64LE(off + 8));
    const strOffset = dynstr.offset + value;
    let end = strOffset;
    while (end < buf.length && buf[end] !== 0) end += 1;
    out.push({ entryOffset: off, strOffset, value, name: buf.toString('utf8', strOffset, end) });
  }
  return out;
}

const entries = neededEntries();
const names = entries.map((e) => e.name);
const target = entries.find((e) => e.name === oldNeeded);
const already = entries.find((e) => e.name === newNeeded);

if (mode === '--check') {
  console.log(`${soPath} DT_NEEDED = [${names.join(', ')}]`);
  const ok = already !== undefined || target !== undefined;
  console.log(ok ? '补丁可用（原值存在或已是目标值）' : `原值 ${oldNeeded} 不存在，无法改写`);
  process.exit(ok ? 0 : 1);
}

if (already !== undefined && target === undefined) {
  console.log(`${soPath} 已是 ${newNeeded}，跳过`);
  process.exit(0);
}
if (target === undefined) {
  fail(`DT_NEEDED 里找不到 ${oldNeeded}（现有：${names.join(', ')}）`);
}

if (!existsSync(backupPath)) {
  copyFileSync(soPath, backupPath);
  console.log(`已备份 → ${backupPath}`);
}
buf.write(newNeeded, target.strOffset, 'utf8');
// NUL 补齐到原串长度：多余字节必须清零，否则读出来是原串的尾巴
buf.fill(0, target.strOffset + newNeeded.length, target.strOffset + oldNeeded.length);
writeFileSync(soPath, buf);

const after = neededEntries().map((e) => e.name);
console.log(`${soPath} DT_NEEDED: [${names.join(', ')}] → [${after.join(', ')}]`);
if (!after.includes(newNeeded)) fail('改写后校验失败');
