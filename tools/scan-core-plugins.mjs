#!/usr/bin/env node
/**
 * 在**已物化的端侧核心树**上离线取三件事实（D6 §6.2 的前置条件）：
 *
 *   1. 插件行清单：bundle 的 `dsh.bundle.patch` 指向的 cordis.patch.yml 里的
 *      `- id:` / `name:` / `disabled:` 行 —— 这才是 profile 实际加载的插件集合
 *      （bundle package.json 的 dependencies 含大量非插件的库，不能当清单用）。
 *   2. 原生模块位置：核心树里哪些包含 `.node`。
 *   3. **传递闭包**依赖原生码的插件：一个插件自己不含 .node，不代表它不依赖原生码
 *      （例如用到 node-pty 的插件）。判据必须沿 dependencies 闭包走到底。
 *      —— 这是"能否在运行时安装"的唯一硬判据：鸿蒙下含原生码的插件不能热更新，
 *      只能随应用发版提供。
 *
 * 输出：
 *   - stdout：ASCII 摘要（避免 Windows 控制台乱码吃掉结论）
 *   - <coreDir>/../plugin-scan.json：结构化结果（UTF-8）
 *   - <coreDir>/../plugin-scan.md  ：可直接抄进文档的证据表（UTF-8）
 *
 * 用法：node tools/scan-core-plugins.mjs [coreDir]
 *   coreDir 默认 dist/core/work/dsh-core-0.1.5-rc.2
 */
import { readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs'
import { join, relative, dirname } from 'node:path'

const coreDir = process.argv[2] ?? join('dist', 'core', 'work', 'dsh-core-0.1.5-rc.2')
const nm = join(coreDir, 'node_modules')
if (!existsSync(nm)) {
  console.error(`FATAL: no node_modules under ${coreDir}`)
  process.exit(1)
}

// ── 1. 包索引 ────────────────────────────────────────────────────────────────
/** relPath（相对 node_modules，如 `a/node_modules/b`）→ 绝对目录 */
const pkgByRel = new Map()

function collectPackages(root) {
  const walk = (dir, prefix) => {
    let entries
    try {
      entries = readdirSync(dir, { withFileTypes: true })
    } catch {
      return
    }
    for (const e of entries) {
      if (!e.isDirectory() && !e.isSymbolicLink()) continue
      if (e.name === '.bin') continue
      if (e.name.startsWith('@')) {
        walk(join(dir, e.name), prefix + e.name + '/')
        continue
      }
      const rel = prefix + e.name
      const abs = join(dir, e.name)
      if (pkgByRel.has(rel)) continue
      pkgByRel.set(rel, abs)
      const nested = join(abs, 'node_modules')
      if (existsSync(nested)) walk(nested, rel + '/node_modules/')
    }
  }
  walk(root, '')
}
collectPackages(nm)
console.log(`packages scanned: ${pkgByRel.size}`)

/** 包名（末段）→ relPath 列表，用于解析依赖时按作用域就近查找 */
const relsByName = new Map()
for (const rel of pkgByRel.keys()) {
  const name = rel.slice(rel.lastIndexOf('node_modules/') + 'node_modules/'.length)
  if (!relsByName.has(name)) relsByName.set(name, [])
  relsByName.get(name).push(rel)
}

// ── 2. 原生模块 ─────────────────────────────────────────────────────────────
function findNative(pkgDir) {
  const hits = []
  const walk = (dir) => {
    let entries
    try {
      entries = readdirSync(dir, { withFileTypes: true })
    } catch {
      return
    }
    for (const e of entries) {
      if (e.isDirectory()) {
        if (e.name === '.git' || e.name === 'deps') continue
        walk(join(dir, e.name))
      } else if (e.name.endsWith('.node')) {
        hits.push(relative(pkgDir, join(dir, e.name)))
      }
    }
  }
  walk(pkgDir)
  return hits
}

const nativeByRel = new Map()
for (const [rel, abs] of pkgByRel) {
  const hits = findNative(abs)
  if (hits.length > 0) nativeByRel.set(rel, hits)
}
console.log(`native (.node)  : ${nativeByRel.size}`)
for (const [rel, hits] of nativeByRel) console.log(`  NATIVE ${rel}  [${hits.join(', ')}]`)

// ── 3. 依赖解析 + 传递闭包 ──────────────────────────────────────────────────
const pkgJsonCache = new Map()
function pkgJson(rel) {
  if (pkgJsonCache.has(rel)) return pkgJsonCache.get(rel)
  const p = join(pkgByRel.get(rel), 'package.json')
  let json = null
  try {
    json = JSON.parse(readFileSync(p, 'utf8'))
  } catch {
    json = null
  }
  pkgJsonCache.set(rel, json)
  return json
}

/** 从包 `fromRel` 里解析依赖 `dep`：沿 /node_modules/ 逐级向上找。 */
function resolveDep(fromRel, dep) {
  const segs = fromRel.split('/node_modules/')
  // segs = [outer..., pkgName]；候选前缀由最长到最短
  for (let i = segs.length - 1; i >= 0; i--) {
    const prefix = segs.slice(0, i).join('/node_modules/')
    const cand = (prefix.length > 0 ? prefix + '/node_modules/' : '') + dep
    if (pkgByRel.has(cand)) return cand
  }
  // 顶层兜底
  if (pkgByRel.has(dep)) return dep
  return null
}

/** entryRel 的依赖闭包里所有含 .node 的包（rel → 命中文件）。 */
function nativeClosure(entryRel) {
  const found = new Map()
  const seen = new Set()
  const queue = [entryRel]
  while (queue.length > 0) {
    const rel = queue.pop()
    if (seen.has(rel)) continue
    seen.add(rel)
    if (nativeByRel.has(rel)) found.set(rel, nativeByRel.get(rel))
    const json = pkgJson(rel)
    if (json === null) continue
    const deps = Object.keys({
      ...(json.dependencies ?? {}),
      ...(json.optionalDependencies ?? {}),
    })
    for (const d of deps) {
      const r = resolveDep(rel, d)
      if (r !== null && !seen.has(r)) queue.push(r)
    }
  }
  return found
}

// ── 4. 解析 bundle patch 行 ─────────────────────────────────────────────────
/**
 * 只做行解析，不引 YAML 库：
 *   `- id: X` 开一行；同行或后续更深的 `name: 'Y'` / `name: Y` 是包的 npm 名；
 *   同一行块内出现 `disabled: true` 则标记禁用。
 * 端侧 ArkTS 也用同一套行解析（不许引 YAML 依赖）。
 */
function parsePatchRows(text) {
  const rows = []
  let cur = null
  let curIndent = -1
  for (const raw of text.split(/\r?\n/)) {
    if (/^\s*#/.test(raw) || raw.trim().length === 0) continue
    const mId = /^(\s*)-\s+id:\s*(\S+)\s*$/.exec(raw)
    const mIdInline = /^(\s*)-\s+id:\s*(\S+)\s+name:\s*['"]?([^'"\s]+)['"]?\s*$/.exec(raw)
    let m
    if (mIdInline) {
      if (cur) rows.push(cur)
      cur = { id: mIdInline[2], name: mIdInline[3], disabled: false }
      curIndent = mIdInline[1].length
      continue
    }
    if (mId) {
      if (cur) rows.push(cur)
      cur = { id: mId[2], name: '', disabled: false }
      curIndent = mId[1].length
      continue
    }
    if (cur === null) continue
    m = /^(\s*)name:\s*['"]?([^'"\s]+)['"]?\s*$/.exec(raw)
    if (m && m[1].length > curIndent) {
      cur.name = m[2]
      continue
    }
    m = /^(\s*)disabled:\s*(true|false)\s*$/.exec(raw)
    if (m && m[1].length > curIndent) {
      cur.disabled = m[2] === 'true'
      continue
    }
  }
  if (cur) rows.push(cur)
  return rows.filter((r) => r.name.length > 0)
}

const bundles = ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app']
const allRows = []
for (const b of bundles) {
  const dir = join(nm, b)
  if (!existsSync(dir)) {
    console.log(`WARN missing bundle: ${b}`)
    continue
  }
  const json = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'))
  const patchRel = json?.dsh?.bundle?.patch ?? './cordis.patch.yml'
  const patchPath = join(dir, patchRel)
  if (!existsSync(patchPath)) {
    console.log(`WARN missing patch: ${b} ${patchRel}`)
    continue
  }
  const rows = parsePatchRows(readFileSync(patchPath, 'utf8'))
  console.log(`rows in ${b}: ${rows.length}`)
  for (const r of rows) allRows.push({ bundle: b, ...r })
}
console.log(`plugin rows total: ${allRows.length}`)

/**
 * 行里的 `name` 可能是**包的子路径导出**（如 `@deepseek-ai/dsh-web-app/startup`），
 * 不是包名本身。此时按"去掉子路径"再解析，否则会得到一个假的「待确认」。
 */
function resolveRowPackage(name) {
  const direct = relsByName.get(name)?.[0] ?? resolveDep('', name) ?? null
  if (direct !== null) return { rel: direct, pkgName: name }
  const slash = name.startsWith('@') ? name.indexOf('/', name.indexOf('/') + 1) : name.indexOf('/')
  if (slash > 0) {
    const pkgName = name.slice(0, slash)
    const r = relsByName.get(pkgName)?.[0] ?? resolveDep('', pkgName) ?? null
    if (r !== null) return { rel: r, pkgName }
  }
  return null
}

const out = []
let unknownPkg = 0
for (const r of allRows) {
  const hit = resolveRowPackage(r.name)
  const entryRel = hit?.rel ?? null
  if (entryRel === null) {
    unknownPkg++
    out.push({ ...r, resolved: false, nativeKind: 'UNKNOWN', nativeVia: [] })
    continue
  }
  const closure = nativeClosure(entryRel)
  out.push({
    ...r,
    resolved: true,
    pkgName: hit.pkgName,
    subpath: hit.pkgName === r.name ? '' : r.name.slice(hit.pkgName.length + 1),
    nativeKind: closure.size > 0 ? 'NATIVE' : 'PURE_JS',
    nativeVia: [...closure.keys()],
  })
}

const pure = out.filter((r) => r.nativeKind === 'PURE_JS')
const nat = out.filter((r) => r.nativeKind === 'NATIVE')
const unk = out.filter((r) => r.nativeKind === 'UNKNOWN')
console.log(`resolved: PURE_JS ${pure.length} / NATIVE ${nat.length} / UNKNOWN ${unk.length}`)
for (const r of nat) console.log(`  PLUGIN-NATIVE ${r.id}  <- ${r.nativeVia.join(', ')}`)
for (const r of unk) console.log(`  PLUGIN-UNKNOWN ${r.id}  (${r.name})`)
const disabled = out.filter((r) => r.disabled)
console.log(`disabled by default: ${disabled.length} -> ${disabled.map((d) => d.id).join(', ')}`)

// ── 5. 落盘 ─────────────────────────────────────────────────────────────────
const base = dirname(coreDir)
const report = {
  coreDir,
  scannedAt: new Date().toISOString(),
  packageCount: pkgByRel.size,
  nativePackages: [...nativeByRel.entries()].map(([rel, files]) => ({ rel, files })),
  pluginRows: out,
  totals: {
    pluginRows: out.length,
    pureJs: pure.length,
    native: nat.length,
    unknown: unk.length,
    disabled: disabled.length,
  },
}
const jsonPath = join(base, 'plugin-scan.json')
writeFileSync(jsonPath, JSON.stringify(report, null, 2), 'utf8')
console.log(`report written: ${jsonPath}`)

const md = []
md.push('# 端侧核心插件扫描（离线，取自真实核心树）')
md.push('')
md.push(`- 核心树：\`${coreDir.replace(/\\/g, '/')}\``)
md.push(`- 包总数：${pkgByRel.size}；含原生模块的包：${nativeByRel.size}`)
md.push(`- 插件行：${out.length}（纯 JS ${pure.length} / 依赖原生 ${nat.length} / 待确认 ${unk.length}；默认禁用 ${disabled.length}）`)
md.push('')
md.push('## 含原生模块的包（发版风险面）')
md.push('')
md.push('| 包（node_modules 相对路径） | 原生文件 |')
md.push('| --- | --- |')
for (const [rel, files] of nativeByRel) md.push(`| \`${rel}\` | \`${files.join('`, `')}\` |`)
md.push('')
md.push('## 依赖原生码的插件行（运行时不可安装，只能随应用发版）')
md.push('')
if (nat.length === 0) {
  md.push('（无）')
} else {
  md.push('| 行 id | 包 | 经由 |')
  md.push('| --- | --- | --- |')
  for (const r of nat) md.push(`| \`${r.id}\` | \`${r.name}\` | ${r.nativeVia.map((v) => `\`${v}\``).join(', ')} |`)
}
md.push('')
md.push('## 全部插件行')
md.push('')
md.push('| 行 id | 包 | bundle | 判定 | 默认 |')
md.push('| --- | --- | --- | --- | --- |')
for (const r of out) {
  md.push(`| \`${r.id}\` | \`${r.name}\` | ${r.bundle.replace('@deepseek-ai/', '')} | ${r.nativeKind} | ${r.disabled ? '禁用' : '启用'} |`)
}
md.push('')
const mdPath = join(base, 'plugin-scan.md')
writeFileSync(mdPath, md.join('\n'), 'utf8')
console.log(`report written: ${mdPath}`)
