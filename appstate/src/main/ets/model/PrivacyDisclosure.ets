/**
 * 应用内的**隐私与权限说明**（P7-11）—— 上架材料在应用里的那一半。
 *
 * ## 为什么它是代码而不是文档
 *
 * AppGallery 审核会看"应用里能不能看到隐私说明"；而更实际的风险是**漂移**：
 * 文档写"只申请两项权限"，而 `module.json5` 里悄悄多了一项 —— 这类不一致，
 * 文档看不出来，界面也看不出来。所以这里把**事实**写成数据，并由
 * `tools/check-compliance.mjs` 与 `module.json5` **逐项对账**（多一项、少一项都红）。
 *
 * ## 内容的纪律：只写能核实的事实
 *
 * 下面每一条都能在代码里指出处（见 `docs/70-上架合规自查.md` §3/§4）：
 * 无遥测、不采设备标识、数据只在本机沙箱、网络只连回环 Host 或用户自填的远端、
 * 剪贴板只写不读、诊断报告显式剔除凭据与消息内容。**不写"我们很重视隐私"这类话** ——
 * 那是宣传，不是说明。
 */

/** 声明的版本与生效日期（AGC 里那份文本以此为基准，改这里就要同步改那边） */
export const PRIVACY_STATEMENT_VERSION: string = '1.0';
export const PRIVACY_STATEMENT_DATE: string = '2026-09-15';

/** 一条权限说明（`name` 必须与 `module.json5` 的 `requestPermissions` 完全一致） */
export interface PermissionDisclosure {
  /** 权限名（`ohos.permission.*`） */
  name: string;
  /** 一句话用途（**与 module.json5 的 reason 字符串同义**，这里给的是界面用的短句） */
  purpose: string;
}

/**
 * 应用申请的全部权限（**上限就是这两项**）。
 *
 * 【对账门禁】`tools/check-compliance.mjs` 会把它与 `module.json5` 比对：
 * 多申请一项、少写一项都会失败。改动任何一侧都必须同时改另一侧。
 */
export const PERMISSION_DISCLOSURES: PermissionDisclosure[] = [
  {
    name: 'ohos.permission.INTERNET',
    purpose: '连接本机 127.0.0.1 上的 Host，以及你自己填写的远端 Host',
  },
  {
    name: 'ohos.permission.KEEP_BACKGROUND_RUNNING',
    purpose: '长任务在切到后台后继续跑；任务结束即停止，不做常驻保活',
  },
];

/** 一条数据实践说明（标题 + 一句能核实的结论） */
export interface PrivacyPoint {
  title: string;
  detail: string;
}

/** 数据与网络的实际做法（每条都能在代码里找到出处） */
export const DATA_PRACTICES: PrivacyPoint[] = [
  { title: '不收集个人信息', detail: '没有账号体系、没有统计埋点、没有崩溃上报；应用不向外发送任何数据。' },
  { title: '数据只在本机沙箱', detail: '会话、设置与凭据都在应用沙箱内（或由 Host 持有），不经过第三方服务器。' },
  { title: '网络只连两处', detail: '本机回环地址上的 Host（只绑 127.0.0.1），以及你在「连接」页显式填写的远端 Host。' },
  { title: '不读设备标识', detail: '不读 ODID / AAID / 序列号；只读"形态、输入设备、系统语言"这类当下事实用于布局与文案。' },
  { title: '剪贴板只写不读', detail: '复制消息与诊断报告会写剪贴板；应用不读取剪贴板内容（也没有申请读剪贴板的权限）。' },
  { title: '导出内容会剔除敏感项', detail: '复制诊断报告时显式去掉凭据与消息正文，只留判定结论与旁路日志。' },
];

/** 一行摘要（设置页那行"当前状态"用） */
export function privacySummaryLine(): string {
  return `v${PRIVACY_STATEMENT_VERSION}（${PRIVACY_STATEMENT_DATE}）· 不收集个人信息 · 权限 ${PERMISSION_DISCLOSURES.length} 项`;
}
