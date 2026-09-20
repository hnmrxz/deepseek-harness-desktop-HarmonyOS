/**
 * 轨迹台账 + 事件详情卡（T022：对照 `ui/screens/main/TrajectoryTab.kt` 复刻）。
 *
 * ## 它对应官方的什么
 *
 * 源码把轨迹做成**逐回合的台账**（"what the agent did, in order, with its inputs and
 * outputs"）：
 *   · `SectionHeader(第 N 回合, action = M 步)`——M 只数工具调用（ToolCallNode）；
 *   · 逐行 `TrajectoryRow`：用户消息 `> 预览`（caption11，**不截断**）、助手消息
 *     160 字纯文本摘要（最多 3 行）、工具行 `ToolLedgerRow`（8dp 状态点 + 展开看输入/输出）；
 *   · 收尾 `TrajectoryTotals`（回合/时序/速度/Token 用量）。
 *
 * 本组件是**聚焦条目所在回合**的台账 + 该条目的事件详情（官方 details.event 的等价物，
 * 判定在 `appstate/model/TrajectoryDetail`，有 fixture 钉住）。
 *
 * ## 文件分工（一个数只在一处出现）
 *
 *   · 回合/步数**总计** —— `MainShell` 的统计行已显示，这里不重复；
 *   · 时序四项（模型/工具用时、TTFT、TPS）—— `TimelineOverview` 的换行统计行已显示；
 *   · Token 用量 —— `TimelineOverview` 的「用量统计」块（TrajectoryTotals 的对位）；
 *   · 回合内的**有序过程**（谁在什么时候做了什么）—— 只有这里有。
 *
 * ## 刻意不做的事（有数据的才做）
 *
 *   · 源码的 `JsonDisclosure`（原始事件 JSON）与 journal 区段：`TrajectoryItem` 投影
 *     已把原始事件收敛成结构化条目，逐条再展开 JSON 属于诊断页职责，不进台账；
 *   · `PtcChildren.kt` 的 parentCallId/subCallId **调用链缩进**：`TrajectoryItem`
 *     没有这两个字段，编不出来；§FR-054 的 indentLevel/collapsed 挂点保留，等数据到位再展开；
 *   · 内部条目（`internal=true`）不进台账：`groupTurns` 已按对话可见性过滤
 *     （`mayExposeBodyToUser` 同样约束正文——台账、详情、对话读的是同一份判定）。
 *     聚焦条目若是内部条目，台账区段不出现，只剩详情卡（诚实降级，不猜）。
 *
 * ## 挂载点（两处共用这一份；v1 行为保留）
 *
 *   · 会话头的轨迹视图里（时间线下面，点格子即聚焦）；
 *   · 右栏「轨迹」面板里（宿主**无条件挂载**，`item` 可能为 undefined——
 *     那时只有详情卡壳；v1 同款语义，不改挂载契约）。
 */

import {
  DsPalette,
  DsSpacing,
  DsThemePreference,
  DsType,
  SessionHub,
  Speaker,
  ToolState,
  TrajectoryKind,
  TRAJECTORY_DETAIL_TITLE,
  formatDuration,
  groupTurns,
  parseMarkdown,
  plainTextOf,
  trajectoryDetailRows,
  userFacingBodyOf,
  dsPaletteOf,
} from 'appstate';
import type { DetailRow, HubSnapshot, HubSubscriber, TrajectoryItem, Turn } from 'appstate';
import {
  DsSectionHeader,
  DsStateDot,
  DsStateDotState,
  dsCardStyle,
  installDsSystemDarkWatch,
} from './NativePrimitives';
import type { DsCardStyle } from './NativePrimitives';

/* ───────── 组件级度量（TrajectoryTab.kt 的 dp/字面量，逐条标注出处） ───────── */

/** TrajectoryTab.kt：LazyColumn `verticalArrangement = Arrangement.spacedBy(2.dp)` */
const TRAJECTORY_ROW_SPACE: number = 2;
/** TrajectoryTab.kt：助手消息摘要 `node.plainText.trim().take(160)` */
const TRAJECTORY_SNIPPET_MAX: number = 160;
/** TrajectoryTab.kt：`StateDot(..., size = 8.dp)` */
const TRAJECTORY_DOT_SIZE: number = 8;
/** Type.kt `codeFont` / system UI stack */
const TRAJECTORY_FONT_MONO: string = 'monospace';
const TRAJECTORY_FONT_SANS: string = 'sans-serif';
/** ArkUI 的 maxLines 没有"不限"档；源码用户行不截断，只能给一个大数 */
const TRAJECTORY_ROW_UNCLIPPED: number = 10000;

/** 台账行（源码 TrajectoryRow 各分支 + ToolLedgerRow 的状态点，收敛成一种行） */
interface LedgerRow {
  id: string;
  text: string;
  /** 是否工具行（领先 8dp 状态点；其余行占同一列宽的对齐位） */
  isTool: boolean;
  toolState: ToolState;
  /** 文字行数上限（0 = 不截断：源码用户行不截断、助手行 3 行） */
  maxLines: number;
  /** 主文字色（用户/助手 = 次级，其余 = 三级；源码同款分工） */
  primary: boolean;
  /** §FR-053：条目独立耗时（0 = 不显示） */
  elapsedMs: number;
  /** 聚焦行高亮（本仓叠加：台账要能看出"点的是哪一条"） */
  focused: boolean;
}

/** 回合作用域（源码「第 N 回合」分组） */
interface TurnScope {
  ordinal: number;
  /** 工具调用数（源码只数 ToolCallNode；这里数 TOOL 类条目，不管有没有可显示的名字） */
  toolCount: number;
  rows: LedgerRow[];
}

/** 字符串内容哈希（重绘键用：内容一变就变，不要求密码学强度） */
function ledgerHashOf(text: string): number {
  let h: number = 0;
  for (let i = 0; i < text.length; i++) {
    h = (h * 31 + text.charCodeAt(i)) % 2147483647;
  }
  return h;
}

/**
 * 台账行文案（源码 TrajectoryRow 的分支逐条对照；'' = 不出这行）。
 * 正文一律过 `userFacingBodyOf`——内部条目不该因为进了台账就绕过可见性判定。
 */
function ledgerTextOf(item: TrajectoryItem): string {
  if (item.kind === TrajectoryKind.MESSAGE) {
    if (item.speaker === Speaker.USER) {
      // 源码：`"> $preview"`，caption11，不截断
      const body: string = userFacingBodyOf(item).trim();
      return body.length > 0 ? `> ${body}` : '';
    }
    // 助手（含系统消息族）：纯文本 160 字摘要（源码 plainText.trim().take(160)）
    const plain: string = plainTextOf(parseMarkdown(userFacingBodyOf(item))).trim();
    if (plain.length === 0) {
      return '';
    }
    return plain.length > TRAJECTORY_SNIPPET_MAX ? plain.substring(0, TRAJECTORY_SNIPPET_MAX) : plain;
  }
  if (item.kind === TrajectoryKind.TOOL) {
    // 源码 ToolLedgerRow 的 DisclosureRow 标题是工具名；空名（只有结果的帧）不出行
    return item.toolName;
  }
  if (item.kind === TrajectoryKind.REASONING) {
    const body: string = userFacingBodyOf(item).trim();
    return body.length > 0 ? `思考 ${body}` : '';
  }
  if (item.kind === TrajectoryKind.SUBAGENT) {
    return item.subagentName.length > 0 ? `子代理 ${item.subagentName}` : '子代理';
  }
  if (item.kind === TrajectoryKind.ERROR) {
    return userFacingBodyOf(item).trim();
  }
  if (item.kind === TrajectoryKind.DELIVERABLE) {
    return item.fileName.length > 0 ? `交付物 ${item.fileName}` : '交付物';
  }
  if (item.kind === TrajectoryKind.GOAL || item.kind === TrajectoryKind.JOB) {
    const label: string = item.kind === TrajectoryKind.GOAL ? '目标' : '任务';
    return item.title.length > 0 ? `${label} ${item.title}` : label;
  }
  if (item.kind === TrajectoryKind.COMMAND) {
    return '斜杠命令';
  }
  return '';
}

/** 工具状态 → 状态点（源码 ToolLedgerRow：没结果=Running、错=Error、其余=Done） */
function ledgerDotState(state: ToolState): DsStateDotState {
  if (state === ToolState.PENDING || state === ToolState.RUNNING) {
    return DsStateDotState.RUNNING;
  }
  if (state === ToolState.FAILED || state === ToolState.REJECTED) {
    return DsStateDotState.ERROR;
  }
  return DsStateDotState.DONE;
}

/** 工具状态 → 排序位（只进重绘版本号） */
function toolStateRank(state: ToolState): number {
  if (state === ToolState.PENDING) {
    return 1;
  }
  if (state === ToolState.RUNNING) {
    return 2;
  }
  if (state === ToolState.SUCCESS) {
    return 3;
  }
  if (state === ToolState.FAILED) {
    return 4;
  }
  return 5;
}

@Component
export struct TrajectoryInspector {
  /** 聚焦的条目；`undefined` = 没有聚焦（详情卡壳仍在，v1 挂载语义） */
  @Prop item: TrajectoryItem | undefined = undefined;
  /** 关闭（清掉聚焦）。空实现 = 不显示关闭入口（右栏那种"一直有焦点"的场景） */
  onClose: () => void = () => {
  };
  /** §FR-054：缩进层级（0 = 顶层，每层嵌套 +1；调用链数据到位前的挂点） */
  @Prop indentLevel: number = 0;
  /** §FR-054：折叠状态（由宿主控制） */
  @Prop collapsed: boolean = false;
  /** §FR-054：切换折叠 */
  onToggleCollapse: () => void = () => {
  };

  @StorageProp('dsSystemDark') systemDark: boolean = false;
  /** 中枢重绘版本（台账跟着回合推进走；item prop 不变时靠它刷新——GoalBar.ets 同款思路） */
  @State private hubRev: number = -1;
  private hubListener?: HubSubscriber;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
    const listener: HubSubscriber = (s: HubSnapshot) => {
      const next: number = this.scopeRevOf(s);
      if (next !== this.hubRev) {
        this.hubRev = next;
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

  /** 卡样式（源码 DsCard：r12 + bgLayer1 + hairline 边——浅色主题里没有边框卡片就不可见） */
  private cardStyle(): DsCardStyle {
    return dsCardStyle(this.palette());
  }

  /** 快照 → 重绘版本（聚焦条目内容 + 轨迹规模 + 运行态） */
  private scopeRevOf(s: HubSnapshot): number {
    let h: number = (s.running ? 1 : 0) + s.trajectory.length * 7;
    const it: TrajectoryItem | undefined = this.item;
    if (it !== undefined) {
      h += (it.at % 49999) + ledgerHashOf(it.body) + ledgerHashOf(it.toolOutput)
        + it.elapsedMs + (it.streaming ? 1 : 0) + toolStateRank(it.toolState) * 13;
    }
    return h;
  }

  /** 详情行（判定在 `appstate/model/TrajectoryDetail`，有 fixture 钉住；有数据的行才出现） */
  private rows(): DetailRow[] {
    return this.item === undefined ? [] : trajectoryDetailRows(this.item);
  }

  /** §FR-053：显示条目独立耗时 */
  private timingText(): string {
    if (this.item === undefined) {
      return '';
    }
    if (this.item.elapsedMs > 0) {
      return formatDuration(this.item.elapsedMs);
    }
    return '-';
  }

  /** §FR-054：判断条目是否可能有子调用（工具调用和子代理会产生嵌套） */
  private hasChildren(): boolean {
    if (this.item === undefined) {
      return false;
    }
    return this.item.kind === TrajectoryKind.TOOL || this.item.kind === TrajectoryKind.SUBAGENT;
  }

  /** 等宽正文行（源码 MonoCaption 只给输入/输出；详情行里对应「参数 / 结果」） */
  private isMonoRow(label: string): boolean {
    return label === '参数' || label === '结果';
  }

  /**
   * 回合作用域：在分组里找到聚焦条目所在的回合，合并 user/process/answers/notices
   * 按 `at` 排序成台账。找不到（含内部条目被 groupTurns 过滤的情形）→ 只出详情卡。
   */
  private turnScope(): TurnScope | undefined {
    const focused: TrajectoryItem | undefined = this.item;
    if (focused === undefined) {
      return undefined;
    }
    const s: HubSnapshot = SessionHub.shared().snapshot();
    const turns: Turn[] = groupTurns(s.trajectory, s.running);
    for (let i = 0; i < turns.length; i++) {
      const turn: Turn = turns[i];
      const merged: TrajectoryItem[] = [];
      if (turn.user !== undefined) {
        merged.push(turn.user);
      }
      for (let j = 0; j < turn.process.length; j++) {
        merged.push(turn.process[j]);
      }
      for (let j = 0; j < turn.answers.length; j++) {
        merged.push(turn.answers[j]);
      }
      for (let j = 0; j < turn.notices.length; j++) {
        merged.push(turn.notices[j]);
      }
      let contains: boolean = false;
      for (let j = 0; j < merged.length; j++) {
        if (merged[j].id === focused.id) {
          contains = true;
          break;
        }
      }
      if (!contains) {
        continue;
      }
      merged.sort((a: TrajectoryItem, b: TrajectoryItem): number => a.at - b.at);
      const rows: LedgerRow[] = [];
      let toolCount: number = 0;
      for (let j = 0; j < merged.length; j++) {
        const it: TrajectoryItem = merged[j];
        if (it.kind === TrajectoryKind.TOOL) {
          // 源码只数 ToolCallNode——不管这条有没有可显示的名字
          toolCount++;
        }
        const text: string = ledgerTextOf(it);
        if (text.length === 0) {
          continue;
        }
        rows.push({
          id: it.id,
          text: text,
          isTool: it.kind === TrajectoryKind.TOOL,
          toolState: it.toolState,
          maxLines: (it.kind === TrajectoryKind.MESSAGE && it.speaker !== Speaker.USER) ? 3 : 0,
          primary: it.kind === TrajectoryKind.MESSAGE,
          elapsedMs: it.elapsedMs,
          focused: it.id === focused.id
        });
      }
      if (rows.length === 0) {
        return undefined;
      }
      return { ordinal: i + 1, toolCount: toolCount, rows: rows };
    }
    return undefined;
  }

  private scopeRows(): LedgerRow[] {
    const sc: TurnScope | undefined = this.turnScope();
    return sc === undefined ? [] : sc.rows;
  }

  private scopeHeader(): string {
    const sc: TurnScope | undefined = this.turnScope();
    return sc === undefined ? '' : `第 ${sc.ordinal} 回合`;
  }

  private scopeAction(): string {
    const sc: TurnScope | undefined = this.turnScope();
    return sc === undefined ? '' : `${sc.toolCount} 步`;
  }

  build() {
    Column({ space: this.cardStyle().space }) {
      this.turnBlock()
      this.detailBlock()
    }
    .width('100%')
    .padding({
      left: this.cardStyle().paddingH,
      right: this.cardStyle().paddingH,
      top: this.cardStyle().paddingV,
      bottom: this.cardStyle().paddingV
    })
    .borderRadius(this.cardStyle().radius)
    .backgroundColor(this.cardStyle().background)
    .borderWidth(this.cardStyle().borderWidth)
    .borderColor(this.cardStyle().borderColor)
  }

  /** 回合台账（源码 TrajectoryTab 的分组区段；作用域 = 聚焦条目所在回合） */
  @Builder
  turnBlock() {
    if (this.scopeRows().length > 0) {
      Column({ space: TRAJECTORY_ROW_SPACE }) {
        DsSectionHeader({
          title: this.scopeHeader(),
          action: this.scopeAction()
        })
        ForEach(this.scopeRows(), (row: LedgerRow) => {
          Row({ space: DsSpacing.XSMALL }) {
            if (row.isTool) {
              DsStateDot({ state: ledgerDotState(row.toolState), dotSize: TRAJECTORY_DOT_SIZE })
            } else {
              // 对齐位：非工具行占住状态点那一列（源码各行无点；本仓取整列对齐，刻意偏离）
              Column().width(TRAJECTORY_DOT_SIZE).height(TRAJECTORY_DOT_SIZE)
            }
            Text(row.text)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontWeight(DsType.CAPTION_11.weight)
              .fontFamily(TRAJECTORY_FONT_SANS)
              .fontColor(row.primary ? this.palette().labelSecondary : this.palette().labelTertiary)
              .maxLines(row.maxLines > 0 ? row.maxLines : TRAJECTORY_ROW_UNCLIPPED)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (row.elapsedMs > 0) {
              Text(formatDuration(row.elapsedMs))
                .fontSize(DsType.CAPTION_11.size)
                .lineHeight(DsType.CAPTION_11.lineHeight)
                .fontWeight(DsType.CAPTION_11.weight)
                .fontFamily(TRAJECTORY_FONT_SANS)
                .fontColor(this.palette().labelCaption)
            }
          }
          .width('100%')
          .padding({ left: DsSpacing.XSMALL, right: DsSpacing.XSMALL })
          .backgroundColor(row.focused ? this.palette().accentTertiary : Color.Transparent)
          .alignItems(VerticalAlign.Center)
        }, (row: LedgerRow) => `${row.id}:${row.focused ? 'f' : 'n'}:${row.toolState}:${ledgerHashOf(row.text)}:${row.elapsedMs}`)
      }
      .width('100%')
    }
  }

  /** 事件详情（v1 的功能面与判定不动，只换 Ds 令牌载体） */
  @Builder
  detailBlock() {
    Column({ space: DsSpacing.XSMALL }) {
      Row({ space: DsSpacing.SMALL }) {
        // §FR-054：缩进指示（嵌套层级）
        if (this.indentLevel > 0) {
          Row()
            .width(this.indentLevel * DsSpacing.MEDIUM)
            .height('100%')
        }
        // §FR-054：折叠/展开切换
        if (this.hasChildren()) {
          SymbolGlyph(this.collapsed
            ? $r('sys.symbol.chevron_right')
            : $r('sys.symbol.chevron_down'))
            .fontSize(DsType.CAPTION_11.size)
            .fontColor([this.palette().labelTertiary])
            .onClick(() => {
              this.onToggleCollapse();
            })
        }
        Text(TRAJECTORY_DETAIL_TITLE)
          .fontSize(DsType.XSMALL_12.size)
          .lineHeight(DsType.XSMALL_12.lineHeight)
          .fontWeight(DsType.XSMALL_12.weight)
          .fontFamily(TRAJECTORY_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
          .layoutWeight(1)
        // §FR-053：每步独立耗时
        Text(this.timingText())
          .fontSize(DsType.XSMALL_12.size)
          .lineHeight(DsType.XSMALL_12.lineHeight)
          .fontWeight(DsType.XSMALL_12.weight)
          .fontFamily(TRAJECTORY_FONT_SANS)
          .fontColor(this.palette().labelSecondary)
        Text('关闭')
          .fontSize(DsType.XSMALL_12.size)
          .lineHeight(DsType.XSMALL_12.lineHeight)
          .fontWeight(DsType.XSMALL_12.weight)
          .fontFamily(TRAJECTORY_FONT_SANS)
          .fontColor(this.palette().accent)
          .constraintSize({ minHeight: DsSpacing.TOUCH_TARGET })
          .padding({ left: DsSpacing.SMALL, right: DsSpacing.SMALL })
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')

      if (!this.collapsed) {
        ForEach(this.rows(), (row: DetailRow) => {
          Column({ space: TRAJECTORY_ROW_SPACE }) {
            Text(row.label)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontWeight(DsType.CAPTION_11.weight)
              .fontFamily(TRAJECTORY_FONT_SANS)
              .fontColor(this.palette().labelTertiary)
              .width('100%')
            Text(row.value)
              .fontSize(DsType.XSMALL_12.size)
              .lineHeight(DsType.XSMALL_12.lineHeight)
              .fontWeight(DsType.XSMALL_12.weight)
              .fontFamily(this.isMonoRow(row.label) ? TRAJECTORY_FONT_MONO : TRAJECTORY_FONT_SANS)
              .fontColor(this.palette().labelSecondary)
              .width('100%')
              .maxLines(6)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
        }, (row: DetailRow) => `${row.label}:${ledgerHashOf(row.value)}`)
      }
    }
    .width('100%')
  }
}
