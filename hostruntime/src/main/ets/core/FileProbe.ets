/**
 * **文件存在性探测**（P8-7）：把 `fs.accessSync` 的"会抛异常"包成"返回布尔"。
 *
 * ## 为什么必须有这一层（这不是风格问题，是一个真实缺陷）
 *
 * `@ohos.file.fs` 的 `accessSync(path, mode?)` 在类型声明里是 `boolean`，但它**会抛**
 * `BusinessError`：`401`（参数错）/ `13900005`（I/O 错误）/ `13900011`（内存不足）/
 * `13900012`（权限不足）/ **`13900018`（Not a directory）** / `13900020`（Invalid argument）…
 * 也就是说，**"哪个组件不是目录"这种情况恰好走的是抛异常这条路**。
 *
 * 而本仓有近二十处把它当**纯布尔谓词**用，其中最关键的是 `CoreStore.verifyStagedTree()`
 * 的三个"关键件哨兵"：
 *   · 它存在的**全部意义**是"解包结果不完整时，给一句说得清的失败"；
 *   · 可当哨兵文件真的缺失（`…/node_modules` 不存在或不是目录）时，`accessSync` **抛**，
 *     于是那句 `fail('解包结果缺少宿主包 @deepseek-ai/dsh')` 根本走不到 ——
 *     用户看到的是一个未处理异常，而不是"缺哪个关键件"。
 * 这正是本仓反复强调的那一类：**守卫本身成了崩溃点，且把失败原因换成了看不懂的东西**。
 *
 * ArkTS 编译器早就报过这个信号（`hostruntime/core/CoreStore.ets:424/430/438`
 * 的 `Function may throw exceptions. Special handling is required.`）——
 * 告警是对的，代码是错的（E402）。
 *
 * ## 与 `fs.accessSync` 的分工
 *
 * 这一层只回答"**在不在**"。权限、路径合法性等语义仍然由调用方决定
 * （例如"权限不足"在这里和"不存在"一样返回 false——对"哨兵齐备吗"这个问题，
 * 两者都意味着"用不了这个树"，如实给 false 而不是把异常抛给上层）。
 * 调用点一律用这两个函数，门禁禁止直接出现 `accessSync`（见 `check-feature-wiring.mjs`）。
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD5A1;
const TAG: string = 'hostruntime/fileprobe';

/**
 * 路径是否存在（文件或目录都算）。
 *
 * 【为什么不把异常吞掉不记】`accessSync` 抛的 `13900012`（权限）与 `13900018`（不是目录）
 * 是有诊断价值的：真机上"明明拷贝了却报缺件"时，这一行日志是唯一能说清原因的。
 * 用 `debug` 级别（不进旁路日志、不打扰用户），因为"文件不存在"是**常态**而非异常。
 */
export function fileExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (err) {
    const e = err as BusinessError;
    hilog.debug(DOMAIN, TAG, 'access 失败，按"不存在"处理：%{public}s（code=%{public}d）',
      path, e.code === undefined ? 0 : e.code);
    return false;
  }
}

/** 目录是否存在（语义同 `fileExists`；分开命名只是为了让调用点读起来是它要问的那件事） */
export function dirExists(path: string): boolean {
  return fileExists(path);
}
