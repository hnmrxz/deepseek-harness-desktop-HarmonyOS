/**
 * 模型请求的**重试行**（P7-18，对齐官方 `ModelRetryItem`）。
 *
 * ## 它替代了什么
 *
 * `llm/retry` 此前只被读了 `retry` 一个字段、拼成 `title = "重试 2"`，正文是空的；
 * 于是在设备网络最差的时候（模型请求失败、Host 排好重试、可能等十几秒），
 * 用户看到的是**一条"出错了"加一片空白**：不知道在重试、不知道第几次、不知道还要等多久。
 * 官方为此专门做了一个带**倒计时**的重试节点：
 *   `const deadline = Date.now() + node.delayMs; … const maximum = node.mode === "normal" ? node.maxRetries : "∞";`
 *
 * ## 两态（与上游两帧一一对应）
 *
 * | 上游事件 | 本组件 |
 * |---|---|
 * | `llm/retry`（记下 plan：第几次 / 上限 / 等多久 / 为什么） | 「正在重试（第 2/5 次）」+ **约 N 秒后重试**（每秒钟自己减） |
 * | `llm/retry-started`（等待结束、请求发出） | 倒计时消失，只剩「正在重试」 |
 *
 * ## 倒计时为什么放在组件里
 *
 * 它需要**每秒重画**，而重画的范围越小越不打扰正文（本仓已有先例：会话头的任务条用
 * `jobTickerNeeded` 决定要不要开定时器）。这里把定时器收在这一行里：挂载时开、卸载时清，
 * 且**只在还没开始重试时**才开（开始的帧到了就没有秒数可减）。一条时间线上通常只有一条重试行。
 *
 * ## 毫秒来源是 `item.at`，不是"现在"
 *
 * 用**事件时间**做起点：`Date.now() + delayMs` 那种写法会把"这条事件是 3 秒前到的"算成"还没过"，
 * 于是倒计时偏大、看起来像卡住。事件时间来自事件的 `time` 字段（`makeItem` 的 `at`），
 * 与投影层用的是同一个数。
 */

import { Fs, HarmonyColor, Radius, Sp, TrajectoryItem, retryCountLine, retryWaitLine } from 'appstate';
import { Border } from 'appstate';

/** 模型请求失败后的一次重试（带倒计时） */
@Component
export struct RetryRow {
  /** 要显示的重试条目（`kind === ERROR` 且 `retryAttempt > 0`） */
  @Prop item: TrajectoryItem;

  /** 每一秒自增一次，驱动倒计时重画（只在"还没开始重试"时运行） */
  @State tick: number = 0;
  /** 定时器句柄（-1 = 没开） */
  private timer: number = -1;

  aboutToAppear(): void {
    this.startTicker();
  }

  aboutToDisappear(): void {
    this.stopTicker();
  }

  /** 只在还需要显示秒数时开定时器；已经在重试（或没有等待信息）就不开 */
  private startTicker(): void {
    if (this.item.retryStarted || this.item.retryDelayMs <= 0) {
      return;
    }
    if (this.timer !== -1) {
      return;
    }
    this.timer = setInterval(() => {
      this.tick = this.tick + 1;
      // 秒数归零后没必要继续跑（"正在重试…"是静态的）
      if (this.remainingMs() <= 0) {
        this.stopTicker();
      }
    }, 1000);
  }

  private stopTicker(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /** 距离"该开始重试了"还剩多少毫秒（负数 = 早该开始了） */
  private remainingMs(): number {
    const elapsed: number = Date.now() - this.item.at;
    return this.item.retryDelayMs - elapsed;
  }

  /** 计数行（第几次 / 上限） */
  private countLine(): string {
    return retryCountLine(this.item.retryAttempt, this.item.retryMax, this.item.retryMode);
  }

  /** 等待行（倒计时 / 正在重试 / 空） */
  private waitLine(): string {
    return retryWaitLine(this.remainingMs(), this.item.retryStarted);
  }

  build() {
    Row({ space: Sp.S }) {
      Divider().vertical(true).color(HarmonyColor.WARNING).height('100%')
      Column({ space: 2 }) {
        Text(this.countLine().length > 0 ? this.countLine() : '正在重试')
          .fontSize(Fs.CAPTION)
          .fontColor(HarmonyColor.WARNING)
          .width('100%')
        // 倒计时（每秒自己减；`tick` 只是让这一行重画）
        if (this.waitLine().length > 0) {
          Text(this.waitLine())
            .fontSize(Fs.SECONDARY)
            .fontColor(HarmonyColor.TEXT_PRIMARY)
            .width('100%')
        }
        // 失败原因（上游 invariant 保证非空；拿不到就不显示这一行，不写"未知原因"）
        if (this.item.body.length > 0) {
          Text(this.item.body)
            .fontSize(Fs.CAPTION)
            .fontColor(HarmonyColor.TEXT_SECONDARY)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor(HarmonyColor.SURFACE_TERTIARY)
    .borderWidth(Border.HAIRLINE)
    .borderColor(HarmonyColor.DIVIDER)
    .accessibilityText(`${this.countLine()}${this.waitLine().length > 0 ? `，${this.waitLine()}` : ''}`
      + (this.item.body.length > 0 ? `，原因：${this.item.body}` : ''))
  }
}
