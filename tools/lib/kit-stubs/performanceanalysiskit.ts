/**
 * `@kit.PerformanceAnalysisKit` 的 Node 垫片：把 hilog 落到 stdout。
 *
 * 保留 `%{public}s` 这类占位符的**原始语义**（把 `%{public}X` 归一成 `%X` 再按参数插值），
 * 这样从日志里读到的就是我们代码真正写下的那行，而不是被垫片改写过的版本。
 */
export const hilog = {
  debug(domain: number, tag: string, format: string, ...args: any[]): void {
    emit('D', tag, format, args);
  },
  info(domain: number, tag: string, format: string, ...args: any[]): void {
    emit('I', tag, format, args);
  },
  warn(domain: number, tag: string, format: string, ...args: any[]): void {
    emit('W', tag, format, args);
  },
  error(domain: number, tag: string, format: string, ...args: any[]): void {
    emit('E', tag, format, args);
  },
};

function emit(level: string, tag: string, format: string, args: any[]): void {
  let i = 0;
  const text: string = String(format).replace(/%\{public\}([sdx])/g, '%$1')
    .replace(/%([sdx])/g, () => String(args[i++] ?? ''));
  const line: string = `[${level}] ${tag} ${text}`;
  if (level === 'E') {
    console.error(line);
  } else {
    console.log(line);
  }
}
