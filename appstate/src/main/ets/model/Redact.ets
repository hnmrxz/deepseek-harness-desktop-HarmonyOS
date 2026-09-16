/**
 * **内容脱敏的唯一真值**（P8-5，从 `model/Notify.ets` 搬出来的纯逻辑）。
 *
 * ## 为什么它要独立成一个零依赖模型
 *
 * 这套规则原本只服务通知（通知在锁屏可见，所以必须脱敏）。但 `docs/09-安全与API错误呈现审计.md`
 * §4 的要求是**所有用户可达的出口**都不许出现凭据：界面文案（Host 错误原文会被我们原样附在文案里）、
 * 剪贴板（诊断报告 / 行复制）、通知。规则留在通知那个文件里，就等于"只有通知这条路脱敏"——
 * 而错误行会把 Host 原文带进对话、诊断报告又会把旁路日志带进剪贴板。
 *
 * 搬成零依赖还有一个直接好处：它能被 `tools/check-layout-fixtures.mjs` **直接执行**，
 * 于是"哪些形状算凭据"这件事变成可断言的，而不是靠人眼审阅文案。
 *
 * ## 判据只看形状，不看语义
 *
 * 我们无法知道用户工作区里哪个词是密钥，但密钥几乎总有可辨认的形状：
 *   1. `sk-` 前缀（本产品自家的 DeepSeek / OpenAI 风格密钥）；
 *   2. 已知服务前缀（`ghp_`/`gho_`/`xox?`/`AKIA`/`AIza`/`glpat-`）；
 *   3. `Bearer <token>` 认证头；
 *   4. `key=value` 形式的赋值（把「名字里带 key/token/secret/password」的值一起吃掉）；
 *   5. 兜底：足够长且混杂大小写/数字的连续串（≥24 位的不透明 token）。
 *
 * 取舍（**刻意宁可多脱敏**）：脱敏会把正常长词误伤成 `[已隐藏凭据]`。
 * 但这条规则服务于安全而非可读性——「偶尔少显示一个长词」远好于「偶尔泄露一个真密钥」，
 * 因此不追求零误伤。
 */

/** 凭据被脱敏后的替换文本（保留占位，让句子仍读得通）。 */
export const REDACTED: string = '[已隐藏凭据]';

export const SENSITIVE_PATTERNS: RegExp[] = [
  /sk-[A-Za-z0-9_-]{8,}/g,
  /\b(?:ghp|gho|ghu|ghs|ghr|glpat|xoxa|xoxb|xoxp|AKIA|AIza)[A-Za-z0-9_-]{8,}/g,
  /\bBearer\s+[A-Za-z0-9._~+/-]{8,}=*/gi,
  /\b[A-Za-z0-9_.-]*(?:key|token|secret|password|passwd|credential)[A-Za-z0-9_.-]*\s*[:=]\s*\S+/gi,
  /(?=[A-Za-z0-9_-]{24,})(?=[A-Za-z0-9_-]*[0-9])(?=[A-Za-z0-9_-]*[A-Z])[A-Za-z0-9_-]{24,}/g
];

/**
 * 是否包含疑似凭据。
 *
 * 存在理由：把「内容纪律」变成**可断言**的谓词，
 * 让测试/评审能对一条已生成的文案直接判定「违规与否」，而不是靠人眼审阅。
 * 返回 true 表示**发现疑似凭据**（即违规）。
 */
export function looksSensitive(text: string): boolean {
  for (let i = 0; i < SENSITIVE_PATTERNS.length; i++) {
    // 每次判定前重置 lastIndex：这些正则带 g 标志，复用同一个对象会留下游标状态。
    SENSITIVE_PATTERNS[i].lastIndex = 0;
    if (SENSITIVE_PATTERNS[i].test(text)) {
      return true;
    }
  }
  return false;
}

/**
 * 把疑似凭据替换成占位符。
 *
 * 为什么需要（而不是「发现疑似就整条丢弃」）：
 *   整条丢弃会让用户看到「什么都没说」的文案；替换占位符仍能传达
 *   「这里原本有一个凭据，我们替你藏了」，信息量更大且不泄露。
 */
export function scrubCredentials(text: string): string {
  let out: string = text;
  for (let i = 0; i < SENSITIVE_PATTERNS.length; i++) {
    SENSITIVE_PATTERNS[i].lastIndex = 0;
    out = out.replace(SENSITIVE_PATTERNS[i], REDACTED);
  }
  return out;
}

/**
 * 折叠空白（换行/制表/连续空格 → 单个空格）。
 *
 * 为什么必须先做这一步：动作摘要来自工具参数或错误信息，天然含换行与缩进；
 * 不折叠的话，截断出来的「前 40 字」可能全是缩进空格——既没信息量，
 * 也容易把多行代码的**第二行**内容带进通知（那正是我们要防的）。
 */
export function collapseWhitespace(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}
