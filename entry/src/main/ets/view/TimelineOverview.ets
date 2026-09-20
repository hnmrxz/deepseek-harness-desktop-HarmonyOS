/**
 * 轨迹的**时间总览**（P3-6：从 `ConversationPane` 抽出的**共用**呈现；
 * T022 换 Ds 令牌载体并补「用量统计」块）。
 *
 * 【对照源文件】`.research/deepseek-harness-mobile/app/src/main/java/com/labteto/dshmobile/`
 * `ui/screens/main/TrajectoryTab.kt`（`TrajectoryTotals` 的四类数 + 总览条的画法）。
 * v1 那半（"总计 + 每格比例条 + 拖动聚焦"）的语义另有官方 web `timeline.overviewAria`，
 * 见下一段。
 *
 * ## 它是什么
 *
 * 「总计 + 每格比例条 + 水平拖动可聚焦事件」（官方 `timeline.overviewAria` 的语义，47 条断言在
 * `appstate/model/Timeline`）。此前它只长在主区「轨迹视图」的顶部；现在右栏的「轨迹」面板也用**同一份**
 * ——注意两者的差别：**主区是"全量台账 + 总览"，右栏是"总览"**。官方右栏的 trajectory 是
 * "当前回合的过程"，本仓没有"回合作用域的过程列表"这个概念（`TrajectoryItem` 没有回合字段），
 * 所以右栏只放总览：**宁可少放一份列表，也不把主区那份台账在 320vp 里照抄一遍**。
 *
 * ## 受控项（都因为"别处也要读写"）
 *
 *  · `focusedCellId` —— 主区列表滚动时也会改它（列表 → 条那一路），唯一真值必须留在宿主；
 *  · `dragging` —— 拖动期间宿主**暂停**"列表 → 条"，否则条会被自己的滚动带着抖；
 *  · `onCommit` —— "松手/点击落定才滚列表"是宿主的动作（要拿 `scroller`）。
 *
 * 组件自己只管：比例条宽度（`onAreaChange`）、拖动过程、悬停高亮、详情行文案。
 *
 * ## 用量统计（T022，对照 `TrajectoryTab.kt` 的 TrajectoryTotals）
 *
 * 源码收尾区段有四类数：回合/步数、时序、速度、Token。前三样本仓已各有其家——
 * 回合/步数在 `MainShell` 的统计行、时序与速度就在下面这行可换行统计里（`statsLinesOf`），
 * 再放一份就成了两个来源说同一个数。这里只补**没有家的那一类**：Token 用量
 * （Host 的 E125 字段，经中枢快照读；0 一律表示"没有"，不编占位）。
 */

import {
  DsPalette, DsShape, DsSpacing, DsThemePreference, DsType,
  SessionHub, StatsLine, StatsUnit, TimelineCell, TimelineKind, TimelineScale,
  TimelineSegment, TrajectoryItem, cellIdAtRatio, dsPaletteOf, formatClock,
  formatDuration, formatTokenVolume, segmentOrdinalOf, statsLinesOf, timelineCellsOf,
  timelineKindLabel, timelineScaleOf, timelineStartedLabel, timelineTotalLabel,
} from 'appstate';
import type { HubSnapshot, HubSubscriber, SessionStatsInput } from 'appstate';
import { DsSectionHeader, installDsSystemDarkWatch } from './NativePrimitives';

@Component
export struct TimelineOverview {
  /** 当前会话的过程条目（组件自己算格子与比例） */
  @Prop items: TrajectoryItem[] = [];
  /** 会话统计（时间四项；轮次/步数由会话头承担，这里不重复） */
  @Prop stats: SessionStatsInput;
  /** 聚焦的格子（受控） */
  @Prop focusedCellId: string = '';
  /** 是否正在拖动比例条（受控：宿主据此暂停"列表 → 条"） */
  @Prop dragging: boolean = false;

  /** 聚焦某格（拖动过程中会连续触发） */
  onFocusCell: (cellId: string) => void = () => {
  };
  /** 拖动/点选**落定**（宿主在此把该格滚进视野） */
  onCommit: () => void = () => {
  };
  /** 拖动状态变化（受控项的写回口） */
  onDragChange: (dragging: boolean) => void = () => {
  };

  /** 比例条实测宽度（拖动换算的起点） */
  @State barWidth: number = 0;

  @StorageProp('dsSystemDark') systemDark: boolean = false;
  /** 用量块的重绘版本（props 只带时序统计，token 用量要从快照来——GoalBar.ets 同款思路） */
  @State private usageRev: number = -1;
  private hubListener?: HubSubscriber;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
    const listener: HubSubscriber = (s: HubSnapshot) => {
      const next: number = s.tokensUncachedInput * 7 + s.tokensOutput * 11
        + s.tokensCacheRead * 13 + s.tokensCacheWrite * 17;
      if (next !== this.usageRev) {
        this.usageRev = next;
      }
    };
    this.hubListener = listener;
    SessionHub.shared().subscribe(listener);
    listener(SessionHub.shared().snapshot());
  }

  aboutToDisappear(): void {
    const listener: HubSubscriber | undefined = this.hubListener;
    if (listener !== undefined) {
      SessionHub.shared().unsubscribe(listener);
      this.hubListener = undefined;
    }
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  /**
   * Token 用量一行（TrajectoryTotals 的对位；只在有数据时渲染）。
   * 四项里只列**非零**的——"输入 0"不是信息，是噪声。
   */
  private usageText(): string {
    const s: HubSnapshot = SessionHub.shared().snapshot();
    const parts: string[] = [];
    if (s.tokensUncachedInput > 0) {
      parts.push(`输入 ${formatTokenVolume(s.tokensUncachedInput)}`);
    }
    if (s.tokensOutput > 0) {
      parts.push(`输出 ${formatTokenVolume(s.tokensOutput)}`);
    }
    if (s.tokensCacheRead > 0) {
      parts.push(`缓存读 ${formatTokenVolume(s.tokensCacheRead)}`);
    }
    if (s.tokensCacheWrite > 0) {
      parts.push(`缓存写 ${formatTokenVolume(s.tokensCacheWrite)}`);
    }
    return parts.join(' · ');
  }

  /**
   * 左上角那句话（F11）：官方文案只在**真的什么计时都没有**时用。
   *
   * 判据分两层，都用已有数据：
   *   · 比例条有没有数据 → `timelineScale().hasTiming`（逐条目 `elapsedMs`）
   *   · 会话统计有没有值 → `statsLinesOf(this.stats)` 里有没有非零项
   * 只有两者**都没有**时才是官方的"无计时数据"；否则说清是"条目没有逐条耗时"。
   */
  private totalLabel(): string {
    const label: string = timelineTotalLabel(this.timelineScale());
    if (this.timelineScale().hasData) {
      return label;
    }
    return this.statsHaveValues() ? '条目无逐条耗时' : label;
  }

  /** 会话统计里**有没有**非零项（与 `totalLabel()` 共用同一判据，两处文案因此不会互相打脸） */
  private statsHaveValues(): boolean {
    const lines: StatsLine[] = statsLinesOf(this.stats);
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].value > 0) {
        return true;
      }
    }
    return false;
  }

  build() {
    Column({ space: DsSpacing.TINY }) {
      /*
       * 【为什么可换行】左侧"总计 + N 格"与右侧四项统计在手机宽度下**加起来超过屏宽**，
       * 而这一行既没有 `layoutWeight`、也不换行 ⇒ 末尾的统计（TPS 那项）会被裁掉。
       * 统计是"读过就算"的信息，但它被裁掉时用户**不会知道**少了东西（docs/08 P0 §7）。
       */
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
        Row({ space: DsSpacing.SMALL }) {
          /*
           * 【F11：这句话不能与右边那四项自相矛盾】
           *
           * 真机读数（同一屏）：
           *   左：`无计时数据 · 6 格`
           *   右：`模型用时 2.1 s · 工具调用用时 1.7 s · TTFT 817 ms · TPS 232.1`
           * 左边说"没有计时数据"，右边当场给出四项——两句话互相打脸。
           *
           * 机理：左侧取的是**逐条目**的 `elapsedMs`（比例条要按条分配宽度），
           * 而它**在投影里永远是 0**（F11 的根因）；右侧取的是 Host 给的**会话级**统计，
           * 那是有值的。所以准确的措辞是"**条目**没有逐条耗时"，不是"没有计时数据"。
           *
           * 处置：只有在**右边也没有任何计时**时才用官方那句「无计时数据」；
           * 否则说清楚是"逐条耗时缺失"——**一句准确的话比一句照抄的话有用**。
           * 官方文案本身不动（它是 `timeline.noTimingData` 的逐字译文，仍在真正的空数据时使用）。
           */
          Text(this.totalLabel())
            .fontSize(DsType.XSMALL_12.size)
            .fontColor(this.palette().labelSecondary)
          Text(`${this.timelineScale().count} 格`)
            .fontSize(DsType.XSMALL_12.size)
            .fontColor(this.palette().labelTertiary)
        }
        .margin({ right: DsSpacing.SMALL, bottom: DsSpacing.TINY })

        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          // 会话统计的**时间四项**（轮次/步数由会话头部那行承担，不在这里重复）
          ForEach(statsLinesOf(this.stats), (line: StatsLine) => {
            Row() {
              Text(this.statsLineText(line))
                .fontSize(DsType.XSMALL_12.size)
                .fontColor(this.palette().labelTertiary)
            }
            .margin({ right: DsSpacing.SMALL, bottom: DsSpacing.TINY })
          }, (line: StatsLine) => line.key)
        }
      }
      .width('100%')

      if (this.timelineScale().hasData) {
        // 比例条：每段用**累计起点 + 宽度**摆放（不是浮动相加，避免四舍五入出缝隙）
        Stack({ alignContent: Alignment.Start }) {
          Row() {
            ForEach(this.timelineScale().segments, (seg: TimelineSegment) => {
              Column()
                .width(`${seg.ratio * 100}%`)
                .height(this.focusedCellId === seg.id ? DsSpacing.XLARGE : DsSpacing.MEDIUM)
                .backgroundColor(this.timelineColorOf(seg.kind))
            }, (seg: TimelineSegment) => seg.id)
          }
          .width('100%')
          .height(DsSpacing.MEDIUM)
          .borderRadius(DsShape.CHIP)
          .clip(true)
        }
        .width('100%')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.barWidth = Number(newArea.width);
        })
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionStart(() => {
              this.onDragChange(true);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.focusTimelineAt(event.offsetX);
            })
            .onActionEnd(() => {
              this.onDragChange(false);
              // 松手才滚（见 `scrollToFocusedCell` 的说明）
              this.onCommit();
            })
        )
        .onClick((event: ClickEvent) => {
          // `event.x` 是**相对本组件**的横坐标，正是比例条的换算起点（`displayX` 是相对窗口的）
          this.focusTimelineAt(Number(event.x));
          this.onCommit();
        })

        if (this.focusedTimelineNote().length > 0) {
          Text(this.focusedTimelineNote())
            .fontSize(DsType.XSMALL_12.size)
            .fontColor(this.palette().labelSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      } else {
        /*
         * 【F11 的**第二处**（2026-09-17 真机复验抓出来）】
         *
         * 上面那句标签我上一轮已经改了（`totalLabel()`），但**这一段说明漏了**——
         * 真机上一屏里同时出现：
         *   `条目无逐条耗时` + `模型用时 32.9 s · 工具调用用时 1 分 13 秒 · TTFT 761 ms · TPS 249.9`
         *   紧接着 `这一轮的条目没有计时数据，无法给出时间分布。`
         * ⇒ **还是自相矛盾**，只是换了个位置。这正是"改一处漏一处"的典型。
         *
         * 现在两句用**同一个判据**（`totalLabel()` 的那套）：会话统计里有时值时，
         * 说明也必须说"条目没有逐条耗时"，而不是"没有计时数据"。
         * 官方 `timeline.noTimingData` 那句原话仍保留在**真的什么都没有**的情形。
         */
        Text(this.timelineScale().hasData || !this.statsHaveValues()
          ? '这一轮的条目没有计时数据，无法给出时间分布。'
          : '这一轮的条目没有逐条耗时，画不出时间分布（会话总计见上方）。')
          .fontSize(DsType.XSMALL_12.size)
          .fontColor(this.palette().labelTertiary)
      }

      /*
       * 【用量统计（T022，对照 TrajectoryTab.kt 的 TrajectoryTotals）】
       * 只补"没有家"的那一类数（见文件头注释的分工表）；全为 0 时整块不出现。
       */
      if (this.usageText().length > 0) {
        Column({ space: DsSpacing.TINY }) {
          DsSectionHeader({ title: '用量统计' })
          Text(this.usageText())
            .fontSize(DsType.CAPTION_11.size)
            .fontColor(this.palette().labelTertiary)
            .width('100%')
        }
        .width('100%')
        .margin({ top: DsSpacing.SMALL })
      }
    }
    .width('100%')
    .padding({ left: DsSpacing.MEDIUM, right: DsSpacing.MEDIUM, top: DsSpacing.TINY, bottom: DsSpacing.TINY })
    .backgroundColor(this.palette().bgBase)
  }

  private timelineCells(): TimelineCell[] {
    return timelineCellsOf(this.items);
  }

  private timelineScale(): TimelineScale {
    return timelineScaleOf(this.timelineCells());
  }

  private focusedTimelineNote(): string {
    const cells: TimelineCell[] = this.timelineCells();
    let cell: TimelineCell | undefined = undefined;
    for (let i = 0; i < cells.length; i++) {
      if (cells[i].id === this.focusedCellId) {
        cell = cells[i];
        break;
      }
    }
    if (cell === undefined) {
      return '';
    }
    const parts: string[] = [];
    parts.push(`${timelineKindLabel(cell.kind)} · ${segmentOrdinalOf(this.timelineScale().segments, cell.id)}/${this.timelineScale().segments.length}`);
    const started: string = timelineStartedLabel(cell, (at: number) => (at > 0 ? formatClock(at) : ''));
    if (started.length > 0) {
      parts.push(started);
    }
    if (cell.durationMs > 0) {
      parts.push(formatDuration(cell.durationMs));
    }
    return parts.join(' · ');
  }

  private statsLineText(line: StatsLine): string {
    if (line.unit === StatsUnit.MS) {
      return `${line.label} ${formatDuration(Math.round(line.value))}`;
    }
    if (line.unit === StatsUnit.TPS) {
      return `${line.label} ${line.value.toFixed(1)}`;
    }
    return `${line.label} ${line.value}`;
  }

  private focusTimelineAt(deltaXVp: number): void {
    const scale: TimelineScale = this.timelineScale();
    if (scale.segments.length === 0 || this.barWidth <= 0) {
      return;
    }
    const ratio: number = deltaXVp / this.barWidth;
    const id: string = cellIdAtRatio(scale.segments, ratio);
    if (id.length > 0) {
      this.onFocusCell(id);
    }
  }

  private timelineColorOf(kind: TimelineKind): number {
    if (kind === TimelineKind.TOOL) {
      return this.palette().accent;
    }
    if (kind === TimelineKind.USER) {
      return this.palette().userBubble;
    }
    return this.palette().labelDimmed;
  }
}
