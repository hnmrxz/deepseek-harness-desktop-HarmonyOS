/**
 * 端侧「插件」页维护的**用户行**（E91）。
 *
 * ───────────────────────── 它解决什么 ─────────────────────────
 * 目标里有"插件管理"。而端侧有一条硬边界：上游的安装通道 `dsh plugin add` 是
 * `spawnSync("pnpm", …)`（`dsh/lib/plugin-D42…js`），鸿蒙不允许应用创建进程 ⇒ **安装/卸载
 * 插件永远做不到**。但"**启停已经随包发版的行**"是纯文件操作，可以做——这就是本模块。
 *
 * ───────────────────── 为什么要有"用户行"这份独立文件 ─────────────────────
 * dsh 的 profile 分层里，"用户层"就是 `<profile 目录>/cordis.patch.yml`
 * （`dsh-app-boot/lib/index.js:861`）。而入口脚本**每次启动**都会用核心树里的种子覆盖
 * 那个文件（否则核心升级带来的 profile 变更就进不来），所以直接写它会丢。
 * 于是拆成两件事：
 *   · `cordis.patch.yml`：**每次启动重新拼装** = 核心种子 + 本文件里的用户行；
 *   · `.hdsh-plugin-rows.yml`（本文件）：**只放用户行**，谁都不覆盖它。
 * ⇒ 启停在重启后仍然成立，且核心升级照常流入。"恢复默认"因此是一次**删除**。
 *
 * ─────────────────────────── 行 id 是哪一个 ───────────────────────────
 * 用 **profile 行 id**（如 `ui-deliverables`），不是 Loader 报出来的 entryId
 * （如 `include:ui-deliverables`）——patch 行是按前者匹配的。本机实测（可复跑）：
 * `node tools/check-plugin-toggle.mjs` → `enabled=true` 翻成 `false`、`RESULT: PASS`。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OpResult } from './CoreStore';
// 文本层（序列化 / 解析 / 行类型）零依赖地放在 `PluginRowsText.ets`，以便被 fixture 直接执行（E369）；
// 这里原样再导出，保持本模块的对外面不变（`hostruntime/Index.ets` 用 `export *` 转发）。
import { parseUserRows, serializeUserRows, userRowsPath } from './PluginRowsText';
import type { UserPluginRow, UserPluginRowsParse } from './PluginRowsText';
export { parseUserRows, serializeUserRows, USER_ROWS_FILENAME, userRowsPath } from './PluginRowsText';
export type { UserPluginRow, UserPluginRowsParse } from './PluginRowsText';

const DOMAIN: number = 0x0000;
const TAG: string = 'HDSH-PluginRows';

export function readUserRows(profileDir: string): UserPluginRow[] {
  const path: string = userRowsPath(profileDir);
  try {
    if (!fs.accessSync(path)) {
      return [];
    }
    return parseUserRows(fs.readTextSync(path)).rows;
  } catch (e) {
    const err = e as BusinessError;
    hilog.warn(DOMAIN, TAG, '读用户插件行失败：%{public}s', err.message);
    return [];
  }
}

/** 写用户行（空数组 = 写一个空文件，等价于"没有覆盖"）。 */
export function writeUserRows(profileDir: string, rows: UserPluginRow[]): OpResult {
  const path: string = userRowsPath(profileDir);
  try {
    const f: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(f.fd, serializeUserRows(rows));
    } finally {
      fs.closeSync(f);
    }
    return { ok: true, message: `已保存 ${rows.length} 条插件启停` };
  } catch (e) {
    const err = e as BusinessError;
    return { ok: false, message: `写用户插件行失败：${err.code} ${err.message}` };
  }
}

/** 恢复默认：删除用户行文件（幂等）。 */
export function clearUserRows(profileDir: string): OpResult {
  const path: string = userRowsPath(profileDir);
  try {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
    return { ok: true, message: '已恢复默认（用户启停设置已清除）' };
  } catch (e) {
    const err = e as BusinessError;
    return { ok: false, message: `清除用户插件行失败：${err.code} ${err.message}` };
  }
}
