/** `@kit.BasicServicesKit` 的 Node 垫片：客户端只用它当 `BusinessError` 的类型与构造。 */
export class BusinessError extends Error {
  code: number;

  constructor(code?: number, message?: string) {
    super(message ?? '');
    this.code = code ?? 0;
  }
}
