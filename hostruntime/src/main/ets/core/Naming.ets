/**
 * 核心分发容器与版本目录的命名规则（纯字符串逻辑，无 IO）。
 *
 * 约定由 hostcore/core-recipe.json 与 tools/pack-core.mjs 定义：
 *   容器名   dsh-core-<version>-openharmony-arm64.zip
 *   顶层目录 dsh-core-<version>/
 *   树内元数据 <top>/hdsh-core.json
 *
 * 为什么单独一层：版本号**会变成目录名**，而它来自一个文件名。
 * 所以"这个名字能不能安全地当目录名用"必须是一个显式的、可单测的判据，
 * 而不是散落在各处的字符串拼接。
 */

export const ARCHIVE_PREFIX: string = 'dsh-core-';
export const ARCHIVE_SUFFIX: string = '-openharmony-arm64.zip';
export const TREE_INFO_FILE: string = 'hdsh-core.json';

/** 版本号长度上限（防止异常文件名撑爆目录名）。 */
const MAX_VERSION_LEN: number = 64;

/**
 * 版本号是否可安全用作目录名。
 * 拒绝：空、过长、含路径分隔符、含 `..`、含首尾空白、含控制字符、含 Windows/Unix 保留字符。
 */
export function isSafeVersion(version: string): boolean {
  if (version.length === 0 || version.length > MAX_VERSION_LEN) {
    return false;
  }
  if (version !== version.trim()) {
    return false;
  }
  if (version.includes('/') || version.includes('\\') || version.includes('..')) {
    return false;
  }
  for (let i = 0; i < version.length; i++) {
    const c: number = version.charCodeAt(i);
    if (c < 0x20 || c === 0x7f) {
      return false;
    }
  }
  const reserved: string[] = [':', '*', '?', '"', '<', '>', '|'];
  for (const r of reserved) {
    if (version.includes(r)) {
      return false;
    }
  }
  return true;
}

/** 从容器文件名解析版本号；不是本项目的容器名则返回空串。 */
export function parseArchiveName(fileName: string): string {
  if (!fileName.startsWith(ARCHIVE_PREFIX) || !fileName.endsWith(ARCHIVE_SUFFIX)) {
    return '';
  }
  const version: string = fileName.substring(ARCHIVE_PREFIX.length, fileName.length - ARCHIVE_SUFFIX.length);
  return isSafeVersion(version) ? version : '';
}

/** 容器内的顶层目录名。 */
export function topDirOf(version: string): string {
  return `${ARCHIVE_PREFIX}${version}`;
}

/** 容器文件名。 */
export function archiveNameOf(version: string): string {
  return `${ARCHIVE_PREFIX}${version}${ARCHIVE_SUFFIX}`;
}
