/**
 * POC-1 验证页：原生协议往返（D4 的「生死门」）。
 *
 * 本页是**验证工具**，不是产品界面。它按 D4 POC-1 的六步判定逐项执行并留下可复制日志：
 *   ① token 换 cookie（含 303 观测）
 *   ② 一元调用 `session/list`（返回信封校验）
 *   ③ 打开 /api/remote.mux 并订阅 $events
 *   ④ 校验首帧为 ready
 *   ⑤ 心跳存活计时（默认 300s 门槛）
 *   ⑥ cancel 生效
 *
 * 日志纪律：不打印 token / cookie 值（D1 §11.5 S4）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  AuthOutcome,
  Connection,
  DiagnosticItem,
  DiagnosticReport,
  EventStreamPhase,
  HostConfig,
  HostFacts,
  RemoteFailure,
  RpcResult
} from 'connection';

const DOMAIN: number = 0xD5D5;
const TAG: string = 'DshPoc1';

/** 日志级别 */
enum LogLevel {
  INFO = 'INFO',
  OK = 'OK',
  FAIL = 'FAIL',
  STEP = 'STEP'
}

interface LogLine {
  level: LogLevel;
  time: string;
  text: string;
}

@Entry
@Component
struct Index {
  @State address: string = '127.0.0.1:3000';
  @State token: string = '';
  @State stateText: string = '未连接';
  @State busy: boolean = false;
  @State lines: LogLine[] = [];
  @State copied: boolean = false;

  private conn: Connection = new Connection();
  private hostFactsText: string = '';
  private heartbeatTimer: number = -1;
  private heartbeatStart: number = 0;
  private disconnectCount: number = 0;
  private endpointUsed: string = '';

  aboutToDisappear(): void {
    this.stopHeartbeatWatch();
    this.conn.stop();
  }

  // ─────────────────────────── 日志 ───────────────────────────

  private log(level: LogLevel, text: string): void {
    const now: Date = new Date();
    const time: string = `${pad2(now.getHours())}:${pad2(now.getMinutes())}:${pad2(now.getSeconds())}`;
    // 单行日志：ArkTS 不允许数组内直接修改，必须整体替换以触发刷新
    const next: LogLine[] = this.lines.slice();
    next.push({ level: level, time: time, text: text });
    this.lines = next;
    hilog.info(DOMAIN, TAG, '%{public}s %{public}s', level, text);
  }

  private clearLog(): void {
    this.lines = [];
    this.copied = false;
  }

  private reportText(): string {
    const parts: string[] = [];
    parts.push(`# POC-1 报告  ${new Date().toISOString()}`);
    parts.push(`地址: ${this.address}`);
    parts.push(`状态: ${this.stateText}`);
    parts.push(`Host 事实: ${this.hostFactsText.length > 0 ? this.hostFactsText : '(未获取)'}`);
    parts.push(`使用的端点: ${this.endpointUsed.length > 0 ? this.endpointUsed : '(未调用)'}`);
    parts.push(`断连次数: ${this.disconnectCount}`);
    parts.push('--- 日志 ---');
    for (let i = 0; i < this.lines.length; i++) {
      const line: LogLine = this.lines[i];
      parts.push(`[${line.time}] ${line.level} ${line.text}`);
    }
    return parts.join('\n');
  }

  // ─────────────────────────── 步骤 ① 认证 ───────────────────────────

  private async runAuth(): Promise<void> {
    this.busy = true;
    this.log(LogLevel.STEP, '步骤①：token → 签名 cookie');
    try {
      const trimmed: string = this.address.trim();
      const rawToken: string = this.token.trim();
      const input: string = rawToken.length > 0 ? `${trimmed}?token=${rawToken}` : trimmed;
      const config: HostConfig | undefined = this.conn.configure(input, 'POC Host');
      if (config === undefined) {
        this.log(LogLevel.FAIL, '地址解析失败：请填写 host:port 或完整启动 URL');
        this.busy = false;
        return;
      }
      this.log(LogLevel.INFO, `authority=${config.authority} loopback=${config.isLoopback} scheme=${config.scheme}`);
      const outcome: AuthOutcome = await this.conn.authenticate();
      if (!outcome.ok) {
        this.log(LogLevel.FAIL, `认证失败（HTTP ${outcome.status}）：${outcome.reason ?? ''}`);
        if (outcome.advice !== undefined) {
          this.log(LogLevel.INFO, `建议：${outcome.advice}`);
        }
        this.stateText = '认证失败';
        this.busy = false;
        return;
      }
      this.log(LogLevel.OK, '① 认证成功：已获得会话 cookie');
      this.log(LogLevel.INFO, `已持 cookie: ${this.conn.hasSession() ? 'yes' : 'no'}`);
      this.stateText = '已认证';
      await this.runUnary();
    } catch (error) {
      this.log(LogLevel.FAIL, `认证异常：${asMessage(error)}`);
    }
    this.busy = false;
  }

  // ─────────────────────────── 步骤 ② 一元调用 ───────────────────────────

  /** 依次尝试候选端点，找到可用的那个（D2 §7 A-6 是未决问题，此处用于探测） */
  private async runUnary(): Promise<void> {
    this.log(LogLevel.STEP, '步骤②：一元 RPC（探测可用端点）');
    const candidates: string[] = ['session/list', 'workspace/list'];
    const noArgs: Record<string, Object> = {};
    for (let i = 0; i < candidates.length; i++) {
      const endpoint: string = candidates[i];
      const result: RpcResult = await this.conn.call(endpoint, noArgs as Object);
      if (result.ok) {
        this.endpointUsed = endpoint;
        const value: Object | undefined = result.value;
        this.log(LogLevel.OK, `② 一元调用成功：${endpoint}`);
        this.log(LogLevel.INFO, `value 类型=${typeof value} 摘要=${summarize(value)}`);
        await this.runEventStream();
        return;
      }
      const failure: RemoteFailure | undefined = result.error;
      this.log(LogLevel.FAIL, `端点半失败：${endpoint} → ${failure?.toString() ?? 'unknown'}`);
    }
    this.log(LogLevel.FAIL, '② 一元调用全部候选失败：请核对 D2 §7 A-6（端点清单）');
  }

  // ─────────────────────────── 步骤 ③④⑤ 事件流 ───────────────────────────

  private async runEventStream(): Promise<void> {
    this.log(LogLevel.STEP, '步骤③：打开 /api/remote.mux 并订阅 $events');
    const started: boolean = await this.conn.start({
      onReady: (facts: HostFacts) => {
        this.hostFactsText = `clientId=${facts.clientId} home=${facts.home}`;
        this.log(LogLevel.OK, `④ 收到 ready 首项：${this.hostFactsText}`);
        this.startHeartbeatWatch();
      },
      onEvent: (event: Object) => {
        this.log(LogLevel.INFO, `事件：${summarize(event)}`);
      },
      onEnd: (error?: string) => {
        this.disconnectCount += 1;
        this.log(LogLevel.FAIL, `事件流终止：${error ?? '(无原因)'}`);
      }
    });
    if (!started) {
      this.log(LogLevel.FAIL, `③ 连接/开流失败：${this.conn.getLastError() ?? '未知'}`);
      return;
    }
    this.log(LogLevel.OK, '③ mux 已建立，开流帧已发送');
    this.log(LogLevel.INFO, `事件流阶段=${this.conn.getEventPhase()}`);
  }

  private startHeartbeatWatch(): void {
    this.stopHeartbeatWatch();
    this.heartbeatStart = Date.now();
    this.log(LogLevel.STEP, '步骤⑤：心跳存活观察开始（建议 ≥300s）');
    this.heartbeatTimer = setInterval(() => {
      const elapsed: number = Math.round((Date.now() - this.heartbeatStart) / 1000);
      if (this.conn.getEventPhase() === EventStreamPhase.LIVE) {
        this.log(LogLevel.INFO, `⑤ 心跳存活 ${elapsed}s（事件流仍为 LIVE）`);
      } else {
        this.log(LogLevel.FAIL, `⑤ 心跳期间事件流失效（${elapsed}s，phase=${this.conn.getEventPhase()}）`);
        this.stopHeartbeatWatch();
      }
    }, 30000);
  }

  private stopHeartbeatWatch(): void {
    if (this.heartbeatTimer >= 0) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  // ─────────────────────────── 步骤 ⑥ + 诊断 ───────────────────────────

  private async runStop(): Promise<void> {
    this.busy = true;
    this.stopHeartbeatWatch();
    const elapsed: number = this.heartbeatStart > 0 ? Math.round((Date.now() - this.heartbeatStart) / 1000) : 0;
    this.log(LogLevel.STEP, `步骤⑥：停止连接（心跳观察时长 ${elapsed}s）`);
    await this.conn.stop();
    this.log(LogLevel.OK, '⑥ 已停止：mux 关闭、逻辑流已 cancel');
    this.stateText = '已停止';
    this.busy = false;
  }

  private async runDiagnose(): Promise<void> {
    this.busy = true;
    this.log(LogLevel.STEP, '生成连接诊断（五项判定）');
    const report: DiagnosticReport = await this.conn.diagnose();
    for (let i = 0; i < report.items.length; i++) {
      const item: DiagnosticItem = report.items[i];
      const level: LogLevel = item.passed ? LogLevel.OK : LogLevel.FAIL;
      this.log(level, `${item.name}: ${item.detail}`);
      if (!item.passed && item.advice !== undefined) {
        this.log(LogLevel.INFO, `  建议：${item.advice}`);
      }
    }
    this.log(report.healthy ? LogLevel.OK : LogLevel.FAIL, `诊断结论：${report.healthy ? '健康' : '存在问题'}`);
    this.busy = false;
  }

  /** 生成报告并复制到系统剪贴板（@kit.BasicServicesKit 的 pasteboard） */
  private async copyReport(): Promise<void> {
    const text: string = this.reportText();
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.copied = true;
      this.log(LogLevel.OK, `报告已复制到剪贴板（${text.length} 字符）`);
    } catch (error) {
      this.log(LogLevel.FAIL, `复制报告失败：${asMessage(error)}`);
    }
  }

  // ─────────────────────────── UI ───────────────────────────

  build() {
    Column({ space: 10 }) {
      Text('DSH 协议往返验证（POC-1）')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      TextInput({ text: this.address, placeholder: 'Host 地址，如 127.0.0.1:3000' })
        .onChange((value: string) => { this.address = value; })
        .width('100%')

      TextInput({ text: this.token, placeholder: 'token（或直接粘贴完整启动 URL 到上一栏）' })
        .onChange((value: string) => { this.token = value; })
        .width('100%')

      Row({ space: 8 }) {
        Button('① 认证并跑通')
          .enabled(!this.busy)
          .onClick(() => { this.runAuth(); })
        Button('诊断')
          .enabled(!this.busy)
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => { this.runDiagnose(); })
        Button('停止')
          .enabled(!this.busy)
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => { this.runStop(); })
        Button('复制报告')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick(() => { this.copyReport(); })
        Button('清空')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick(() => { this.clearLog(); })
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(`状态：${this.stateText}`)
          .fontSize(14)
        Text(this.busy ? '运行中…' : '空闲')
          .fontSize(14)
          .fontColor(Color.Gray)
      }
      .width('100%')

      if (this.hostFactsText.length > 0) {
        Text(this.hostFactsText)
          .fontSize(12)
          .fontColor(Color.Gray)
          .width('100%')
      }

      List({ space: 4 }) {
        ForEach(this.lines, (line: LogLine) => {
          ListItem() {
            Row({ space: 6 }) {
              Text(line.time)
                .fontSize(12)
                .fontColor(Color.Gray)
                .width(64)
              Text(line.level)
                .fontSize(12)
                .fontColor(levelColor(line.level))
                .width(40)
              Text(line.text)
                .fontSize(12)
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
        }, (line: LogLine, index: number) => `${index}-${line.time}-${line.level}`)
      }
      .layoutWeight(1)
      .width('100%')
      .borderWidth(1)
      .borderColor(Color.Gray)
      .borderRadius(6)
      .padding(6)
    }
    .padding(12)
    .width('100%')
    .height('100%')
  }
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function levelColor(level: LogLevel): Color {
  if (level === LogLevel.OK) {
    return Color.Green;
  }
  if (level === LogLevel.FAIL) {
    return Color.Red;
  }
  if (level === LogLevel.STEP) {
    return Color.Blue;
  }
  return Color.Gray;
}

function summarize(value: Object | undefined): string {
  if (value === undefined) {
    return '(undefined)';
  }
  let text: string = '';
  try {
    text = JSON.stringify(value);
  } catch (error) {
    text = '<不可序列化>';
  }
  return text.length > 300 ? `${text.substring(0, 300)}…(共 ${text.length} 字符)` : text;
}

function asMessage(error: Object): string {
  if (error instanceof Error) {
    return (error as Error).message;
  }
  return `${error}`;
}
