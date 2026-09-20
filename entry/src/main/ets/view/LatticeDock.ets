/**
 * 底部 Dock（T021：对照 `dshmobile/ui/screens/main/Docks.kt` 的 GoalBar + QueueDock 复刻）。
 *
 * ## 对照结构（源码逐段）
 *
 *   · `GoalBar`（ChatScreen.kt 里在 QueueDock **之前**）：`StateDot(8dp)` + 目标正文 +
 *     相位 pill + 暂停/继续/编辑/清除动词（源码收在 DsMenu 里，**没有 busy 守卫**）。
 *   · `QueueDock`：`DisclosureRow(标题, summary=条数)` 折叠头部 + 展开体——
 *     「全部插话」Ghost 按钮（不缩进）+ 逐条行（缩进 28dp：预览文本 + placement pill +
 *     编辑/移除/插话动词）。展开态键在 `queue.size` 上（源码 `remember(queue.size)`）：
 *     队列条数一变就收回展开。busy 期间动词整组隐藏（源码 `!busy && placement != "steering"`）。
 *   · `StatsFooter` / `TodoDock` / `GoalSummary`：分别由 `MainShell` 的统计行、任务卡与
 *     目标卡承担（一个数只在一处出现），本 Dock 不重复。
 *
 * ## 刻意偏离（每条都有理由）
 *
 *   · `DsMenu` → 平铺文字动词（本文件的 `DockVerb`）：本仓没有菜单基元，且 E118 禁
 *     @Builder 注入；触控底线 32vp + 品牌色/危险色（源码 MenuItem(danger=true) 的对位）。
 *   · `DsDialog` 编辑 → **行内表单**：`GoalBar.ets`（v1）的同款先例。
 *   · 源码 `blocked` 参数（目标受阻时禁队列操作）没有宿主事实支撑，**不实现**——
 *     编一个开关等于给用户看假状态。
 *   · 队列动词失败**不弹本地提示**：与 `MainShell` 的队列操作同款 fire-and-forget，
 *     失败反馈走中枢 `setActionError` 通道；成功与否的权威呈现是 Host 推回来的下一帧队列。
 *     目标动词保留本地回执（`GoalBar.ets` 同款）。
 *   · 文案对齐本仓词表：标题「待发队列」、动词「插话/移除」（`Composer` 已用同一套词，
 *     同一个概念只用一套词）；源码字串是「待处理回合 / 引导正在进行的回合」。
 *
 * ## §FR-057
 *
 * 手机端远程模式底部的固定 Dock 区：队列操作（编辑/移除/插话）与目标操作
 * （暂停/继续/编辑/清除）。
 *
 * ## 数据与重绘
 *
 * 真值全部来自 `SessionHub` 快照（`queued` / `goalText` / `goalPhase` / `goalRevision`）。
 * 组件像 `GoalBar.ets` 一样**自己订阅中枢**——它没有会变的 props，父组件重绘不会
 * 带上它；`@Prop goalText` 仅为既有挂载契约保留（`RemoteShell` 仍在传），不参与渲染判定。
 *
 * ## 已知的重叠（留给后续收敛，不在本任务领土内）
 *
 * `Composer` 的排队项面板与本 Dock 的队列区是**同一份数据的两处操作面**；
 * `Composer` 不在本任务的可改清单里，此处如实登记。
 */

import {
  ActionNotice,
  DsPalette,
  DsSpacing,
  DsThemePreference,
  DsType,
  GOAL_PHASE_ACTIVE,
  GOAL_PHASE_BLOCKED,
  GOAL_PHASE_COMPLETE,
  GoalBarState,
  QueuedItem,
  SessionHub,
  dsPaletteOf,
  goalBarStateOf,
} from 'appstate';
import type { HubSnapshot, HubSubscriber } from 'appstate';
import {
  DsButton,
  DsButtonSize,
  DsButtonVariant,
  DsDisclosureRow,
  DsPill,
  DsStateDot,
  DsStateDotState,
  installDsSystemDarkWatch,
} from './NativePrimitives';

/* ───────── 组件级度量（Docks.kt 的 dp 字面量，逐条标注出处） ───────── */

/** Docks.kt 队列行：子项缩进 28dp（`padding(start = 28.dp)`） */
const DOCK_CHILD_INDENT: number = 28;
/** Docks.kt 队列行：行距 2dp（`padding(top = 2.dp)` + 尾部 `Spacer(2.dp)`，合并为列间距） */
const DOCK_CHILD_GAP: number = 2;
/** Docks.kt GoalBar：`StateDot(..., size = 8.dp)` */
const DOCK_STATE_DOT_SIZE: number = 8;
/**
 * 文字动词的触控底线：源码 DsMenu 的每一项是整行菜单项；平铺成行内动词后，
 * 用 32vp 保住可点面积（`NativePrimitives` 头注释的规矩：可点面积 ≥ 触控底线）。
 */
const DOCK_VERB_TOUCH_MIN: number = 32;
/** Type.kt system UI stack（非等宽角色一律用它） */
const DOCK_FONT_SANS: string = 'sans-serif';

/** 字符串内容哈希（只用于重绘键/版本号：内容一变就变，不要求密码学强度） */
function dockHashOf(text: string): number {
  let h: number = 0;
  for (let i = 0; i < text.length; i++) {
    h = (h * 31 + text.charCodeAt(i)) % 2147483647;
  }
  return h;
}

/** 快照 → 重绘版本号（队列 + 目标相关字段全进来；`GoalBar.ets` 同款思路的加强版） */
function dockRev(s: HubSnapshot): number {
  let h: number = s.running ? 1 : 0;
  h = (h * 3 + s.goalRevision) % 2147483647;
  h = (h * 5 + dockHashOf(s.goalText)) % 2147483647;
  h = (h * 7 + dockHashOf(s.goalPhase)) % 2147483647;
  h = (h * 11 + dockHashOf(s.goalNote)) % 2147483647;
  h = (h * 13 + s.queued.length) % 2147483647;
  for (let i = 0; i < s.queued.length; i++) {
    h = (h * 17 + dockHashOf(s.queued[i].id)) % 2147483647;
    h = (h * 29 + dockHashOf(s.queued[i].text)) % 2147483647;
    h = (h * 37 + dockHashOf(s.queued[i].placement)) % 2147483647;
  }
  return h;
}

/** 队列里还有没有这个 id（编辑态的清理判据：别给一个"保存到幽灵"的表单） */
function dockQueuedContains(items: QueuedItem[], id: string): boolean {
  for (let i = 0; i < items.length; i++) {
    if (items[i].id === id) {
      return true;
    }
  }
  return false;
}

/**
 * 文字动词（源码 DsMenu 菜单项的平铺等价物）。
 * caption11Strong + 品牌色；危险动作（移除/清除）用 error 色（源码 `danger = true`）。
 * 独立 struct 而不是 @Builder：带 onTap 回调的子组件是本仓验证过的形态（NativeChip 同款）。
 */
@Component
struct DockVerb {
  @Prop label: string = '';
  /** 危险动作（移除/清除）：error 色 */
  @Prop danger: boolean = false;
  onTap: () => void = () => {
  };
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Text(this.label)
      .fontSize(DsType.CAPTION_11_STRONG.size)
      .lineHeight(DsType.CAPTION_11_STRONG.lineHeight)
      .fontWeight(DsType.CAPTION_11_STRONG.weight)
      .fontFamily(DOCK_FONT_SANS)
      .fontColor(this.danger ? this.palette().error : this.palette().accent)
      .maxLines(1)
      .constraintSize({ minHeight: DOCK_VERB_TOUCH_MIN })
      .padding({ left: DsSpacing.XSMALL, right: DsSpacing.XSMALL })
      .accessibilityText(this.label)
      .onClick(() => {
        this.onTap();
      })
  }
}

/** 底部 Dock：目标栏（对照 GoalBar）+ 待发队列（对照 QueueDock） */
@Component
export struct LatticeDock {
  /** 既有挂载契约（`RemoteShell` 仍在传）；真值以中枢快照为准，不参与渲染判定 */
  @Prop goalText: string = '';

  /** 中枢重绘版本（本组件无可变 props，父组件重绘不会带上它——`GoalBar.ets` 同款取证） */
  @State private hubRev: number = -1;
  /** 队列折叠态（源码 `remember(queue.size)`：条数一变即收回） */
  @State private queueExpanded: boolean = false;
  /** 正在编辑的队列项 id（'' = 没有在编辑） */
  @State private editingQueueId: string = '';
  /** 队列编辑草稿 */
  @State private queueDraft: string = '';
  /** 队列操作进行中（源码 busyState：动词隐藏/按钮禁用） */
  @State private busy: boolean = false;
  /** 目标编辑态（源码 DsDialog 的行内表单等价物） */
  @State private goalEditing: boolean = false;
  /** 目标编辑草稿 */
  @State private goalDraft: string = '';
  /** 目标动作回执（失败原因写在这里，成功则清空；`GoalBar.ets` 同款） */
  @State private goalNotice: string = '';

  @StorageProp('dsSystemDark') systemDark: boolean = false;
  private hubListener?: HubSubscriber;
  private lastQueueSize: number = -1;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
    const listener: HubSubscriber = (s: HubSnapshot) => {
      const next: number = dockRev(s);
      if (next !== this.hubRev) {
        this.hubRev = next;
      }
      // 源码 expanded = remember(queue.size)：队列条数一变，展开态收回
      if (s.queued.length !== this.lastQueueSize) {
        this.lastQueueSize = s.queued.length;
        this.queueExpanded = false;
      }
      // 正在编辑的项被（别处）移除：退出编辑态
      if (this.editingQueueId.length > 0 && !dockQueuedContains(s.queued, this.editingQueueId)) {
        this.editingQueueId = '';
        this.queueDraft = '';
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

  private snap(): HubSnapshot {
    return SessionHub.shared().snapshot();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  /** 目标栏状态（判定全在 `appstate/model/GoalBar.ets` 纯模型里，被 fixture 钉住） */
  private goalState(): GoalBarState {
    const s: HubSnapshot = this.snap();
    return goalBarStateOf(s.goalText.length > 0, s.goalText, s.goalPhase, '', s.goalNote);
  }

  /** 相位 → 状态点（源码 GoalBar 的 when 分支逐条对照） */
  private goalDotState(): DsStateDotState {
    const phase: string = this.snap().goalPhase;
    if (phase === GOAL_PHASE_ACTIVE) {
      return DsStateDotState.RUNNING;
    }
    if (phase === GOAL_PHASE_BLOCKED) {
      return DsStateDotState.WARNING;
    }
    if (phase === GOAL_PHASE_COMPLETE) {
      // complete 时模型判不可见，这里仅为映射完整
      return DsStateDotState.DONE;
    }
    return DsStateDotState.IDLE; // paused / 未知
  }

  /** 整个 Dock 是否出现（源码 `if (queue.isEmpty()) return` + GoalBar 的 render-nothing 规则） */
  private dockVisible(): boolean {
    return this.snap().queued.length > 0 || this.goalState().visible;
  }

  /**
   * 队列动词：fire-and-forget（`MainShell` 的队列操作同款）。
   * 失败不弹本地提示——中枢 setActionError 是这条链路的统一反馈通道；
   * 权威呈现是 Host 推回来的下一帧队列（不做乐观改，但"不做乐观改"不等于"不刷新"）。
   */
  private changeQueue(op: () => Promise<boolean>): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    op().then((_ok: boolean) => {
      this.busy = false;
    }).catch(() => {
      this.busy = false;
    });
  }

  /** 全部插话：先取快照 id 再逐条 await（源码 `ids.forEach { store.updateQueue(it, "steer") }`） */
  private async steerAllInner(ids: string[]): Promise<void> {
    this.busy = true;
    try {
      for (let i = 0; i < ids.length; i++) {
        await SessionHub.shared().steerQueuedItem(ids[i]);
      }
    } finally {
      this.busy = false;
    }
  }

  private steerAll(): void {
    if (this.busy) {
      return;
    }
    const queued: QueuedItem[] = this.snap().queued;
    const ids: string[] = [];
    for (let i = 0; i < queued.length; i++) {
      ids.push(queued[i].id);
    }
    if (ids.length === 0) {
      return;
    }
    this.steerAllInner(ids).catch(() => {
      // 失败反馈走中枢通道（见 changeQueue 的说明）
    });
  }

  /** 保存队列项编辑（源码：updateQueue 成功才关编辑框） */
  private saveQueueEdit(itemId: string): void {
    const text: string = this.queueDraft;
    if (text.trim().length === 0 || this.busy) {
      return;
    }
    this.busy = true;
    SessionHub.shared().editQueuedItem(itemId, text).then((ok: boolean) => {
      this.busy = false;
      if (ok) {
        this.editingQueueId = '';
        this.queueDraft = '';
      }
    }).catch(() => {
      this.busy = false;
    });
  }

  /**
   * 目标动词：带本地回执（`GoalBar.ets` 同款）。
   * 写完从 Host 拉一次真值——不做乐观改，但界面要跟得上 Host 的下一版。
   */
  private runGoal(action: Promise<ActionNotice>): void {
    action.then((n: ActionNotice) => {
      this.goalNotice = n.code === 'command.executed' ? '' : `未生效：${n.code}`;
      SessionHub.shared().refreshGoal();
    }).catch(() => {
      this.goalNotice = '未生效：动作没能送出去';
      SessionHub.shared().refreshGoal();
    });
  }

  build() {
    if (this.dockVisible()) {
      Column({ space: DsSpacing.SMALL }) {
        // 源码顺序（ChatScreen.kt L457-459）：GoalBar 在前、QueueDock 在后
        this.goalDock()
        this.queueDock()
      }
      .width('100%')
      .padding({ left: DsSpacing.MEDIUM, right: DsSpacing.MEDIUM, top: DsSpacing.TINY, bottom: DsSpacing.TINY })
    }
  }

  /** 目标栏（对照 Docks.kt GoalBar：状态点 + 正文 + 相位 pill + 动词 + 行内编辑） */
  @Builder
  goalDock() {
    if (this.goalState().visible) {
      Column({ space: DOCK_CHILD_GAP }) {
        if (this.goalEditing) {
          Row({ space: DsSpacing.XSMALL }) {
            TextInput({ text: this.goalDraft })
              .fontSize(DsType.STD_14.size)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.goalDraft = value;
              })
              .accessibilityText('目标正文')
            DsButton({
              text: '保存',
              variant: DsButtonVariant.INFO,
              buttonSize: DsButtonSize.SMALL,
              disabled: this.goalDraft.trim().length === 0 || this.busy,
              onTap: () => {
                this.runGoal(SessionHub.shared().editGoal(this.goalDraft));
                this.goalEditing = false;
              }
            })
            DsButton({
              text: '取消',
              variant: DsButtonVariant.GHOST,
              buttonSize: DsButtonSize.SMALL,
              onTap: () => {
                this.goalEditing = false;
              }
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else {
          Row({ space: DsSpacing.SMALL }) {
            DsStateDot({ state: this.goalDotState(), dotSize: DOCK_STATE_DOT_SIZE })
            Text(this.goalState().objective)
              .fontSize(DsType.SMALL_13.size)
              .lineHeight(DsType.SMALL_13.lineHeight)
              .fontWeight(DsType.SMALL_13.weight)
              .fontFamily(DOCK_FONT_SANS)
              .fontColor(this.palette().labelSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.goalState().phaseLabel.length > 0) {
              DsPill({ text: this.goalState().phaseLabel })
            }
            // 源码 GoalBar 的 DsMenu 没有 busy 守卫——目标动词始终在场
            if (this.goalState().canPause) {
              DockVerb({
                label: '暂停',
                onTap: () => {
                  this.runGoal(SessionHub.shared().pauseGoal());
                }
              })
            }
            if (this.goalState().canResume) {
              DockVerb({
                label: '继续',
                onTap: () => {
                  this.runGoal(SessionHub.shared().resumeGoal());
                }
              })
            }
            if (this.goalState().canEdit) {
              DockVerb({
                label: '编辑',
                onTap: () => {
                  this.goalDraft = this.snap().goalText;
                  this.goalEditing = true;
                }
              })
            }
            if (this.goalState().canClear) {
              DockVerb({
                label: '清除',
                danger: true,
                onTap: () => {
                  this.runGoal(SessionHub.shared().clearGoal());
                }
              })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        if (this.goalNotice.length > 0) {
          Text(this.goalNotice)
            .fontSize(DsType.CAPTION_11.size)
            .fontColor(this.palette().error)
            .width('100%')
        }
      }
      .width('100%')
    }
  }

  /** 待发队列（对照 Docks.kt QueueDock：披露行 + 全部插话 + 逐条行） */
  @Builder
  queueDock() {
    if (this.snap().queued.length > 0) {
      Column() {
        DsDisclosureRow({
          title: '待发队列',
          summary: `${this.snap().queued.length}`,
          expanded: this.queueExpanded,
          canToggle: true,
          onToggle: () => {
            this.queueExpanded = !this.queueExpanded;
          }
        })
        if (this.queueExpanded) {
          Column({ space: DOCK_CHILD_GAP }) {
            // 全部插话（源码：Ghost 按钮，不缩进、busy 时禁用）
            DsButton({
              text: '全部插话',
              variant: DsButtonVariant.GHOST,
              buttonSize: DsButtonSize.SMALL,
              disabled: this.busy,
              onTap: () => {
                this.steerAll();
              }
            })
            ForEach(this.snap().queued, (item: QueuedItem) => {
              if (this.editingQueueId === item.id) {
                Row({ space: DsSpacing.XSMALL }) {
                  TextInput({ text: this.queueDraft })
                    .fontSize(DsType.STD_14.size)
                    .layoutWeight(1)
                    .onChange((value: string) => {
                      this.queueDraft = value;
                    })
                    .accessibilityText('排队消息正文')
                  DsButton({
                    text: '保存',
                    variant: DsButtonVariant.INFO,
                    buttonSize: DsButtonSize.SMALL,
                    disabled: this.queueDraft.trim().length === 0 || this.busy,
                    onTap: () => {
                      this.saveQueueEdit(item.id);
                    }
                  })
                  DsButton({
                    text: '取消',
                    variant: DsButtonVariant.GHOST,
                    buttonSize: DsButtonSize.SMALL,
                    onTap: () => {
                      this.editingQueueId = '';
                      this.queueDraft = '';
                    }
                  })
                }
                .width('100%')
                .padding({ left: DOCK_CHILD_INDENT })
                .alignItems(VerticalAlign.Center)
              } else {
                Row({ space: DsSpacing.SMALL }) {
                  Text(item.text)
                    .fontSize(DsType.SMALL_13.size)
                    .lineHeight(DsType.SMALL_13.lineHeight)
                    .fontWeight(DsType.SMALL_13.weight)
                    .fontFamily(DOCK_FONT_SANS)
                    .fontColor(this.palette().labelSecondary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  // placement 原样带出（源码 DsPill(text = item.placement)）
                  DsPill({ text: item.placement })
                  // 源码：`!busy && !blocked && placement != "steering"` 才出菜单；
                  // blocked 无宿主事实不实现（见文件头"刻意偏离"）
                  if (!this.busy && item.placement !== 'steering') {
                    DockVerb({
                      label: '编辑',
                      onTap: () => {
                        this.editingQueueId = item.id;
                        this.queueDraft = item.text;
                      }
                    })
                    DockVerb({
                      label: '移除',
                      danger: true,
                      onTap: () => {
                        this.changeQueue(() => SessionHub.shared().removeQueuedItem(item.id));
                      }
                    })
                    DockVerb({
                      label: '插话',
                      onTap: () => {
                        this.changeQueue(() => SessionHub.shared().steerQueuedItem(item.id));
                      }
                    })
                  }
                }
                .width('100%')
                .padding({ left: DOCK_CHILD_INDENT })
                .alignItems(VerticalAlign.Center)
              }
            }, (item: QueuedItem) => `${item.id}:${dockHashOf(item.text)}:${this.editingQueueId === item.id ? 'e' : 'r'}`)
          }
          .width('100%')
        }
      }
      .width('100%')
    }
  }
}
