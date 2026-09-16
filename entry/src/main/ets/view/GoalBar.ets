/**
 * 长期目标栏（P7-20，对齐官方 `dsh-client-ui-goal` 的 `GoalBar`）。
 *
 * ## 它现在能做什么（此前只能看）
 *
 * 官方的目标栏是**可操作的**：`phase` 决定给哪个动词（`active` → 暂停；`paused` → 继续），
 * 外加**编辑**（同一行内的内联表单）与**清除**；**创建**刻意不在这条栏里（走 `/goal` 命令）。
 * 我们此前只把目标正文读出来显示，四个动词一个都没有 —— 用户能在网页上暂停/改目标，
 * 在这里只能干看着。
 *
 * ## 什么时候**不**渲染（官方规则，逐字）
 *
 *   > "loading (undefined), **no goal (null)**, and **complete goals render nothing**."
 *
 * 也就是说：没有目标、加载中、已完成 —— 整条栏不出现。我们此前不管有没有目标都画一行
 * （空态写"该会话当前没有长期目标"），在手机上就是白占一行。
 * **唯一保留的空态**是"读不到"（形状未识别/读失败）：那时显示一句说明，
 * 因为把"读不到"说成"没有目标"会让用户以为目标丢了（本仓踩过这条）。
 *
 * ## 判定全在 `appstate/model/GoalBar.ets`
 *
 * 相位文案、给哪几个动词、可不可见，都由那个纯模型给出（被 fixture 钉住）；
 * 本组件只负责画与转发动作 —— 与 `ToolCard` / `DeliverableCard` 同一条规矩。
 */

import {
  ActionNotice, Border, Fs, GoalBarState, HarmonyColor, Radius, SessionHub, Sp, goalBarStateOf
} from 'appstate';
import type { HubSnapshot, HubSubscriber } from 'appstate';
import { NativeChip } from './NativePrimitives';

/** 长期目标栏：相位 + 正文 + 暂停/继续/编辑/清除 */
@Component
export struct GoalBar {
  /** 正在编辑（内联表单） */
  @State editing: boolean = false;
  /** 编辑中的草稿 */
  @State draft: string = '';
  /** 动作回执（失败原因写在这里，成功则清空） */
  @State notice: string = '';
  /** 每敲一个字就重画整个会话列表不值得 —— 用本地草稿 + 提交时一次性写 */

  /** 从快照算出的状态（唯一真值在纯模型里） */
  private state(): GoalBarState {
    const s = SessionHub.shared().snapshot();
    return goalBarStateOf(s.goalText.length > 0, s.goalText, s.goalPhase, '', s.goalNote);
  }

  /**
   * 【为什么要自己订阅中枢（2026-09-17 真机取证）】
   *
   * 这个组件**没有任何 props**（它自足读快照），于是被放进会话页之后，ArkUI 在父组件重绘时
   * **不会因为它没有变化而重新执行它的 build()** —— 真机表现就是：Host 侧明明有目标
   * （旁路日志 `goals/get ok present=true phase=active rev=1`），栏却一行都不出现。
   *
   * 修法：像 `Index` 那样**自己订阅中枢**，把快照的版本号放进一个 `@State`，
   * 目标一变就重绘自己。这与"视图只读快照"的既有纪律不冲突——订阅的仍然是同一个快照。
   */
  @State private goalRev: number = 0;
  private hubListener?: HubSubscriber;

  aboutToAppear(): void {
    const listener: HubSubscriber = (s: HubSnapshot) => {
      // 只用一个会变的标量驱动重绘：目标正文 / 相位 / 长度的组合
      const next: number = (s.goalText.length * 31) + s.goalPhase.length + (s.goalText.length > 0 ? 100000 : 0);
      if (next !== this.goalRev) {
        this.goalRev = next;
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

  /**
   * 跑一个动作并把回执变成一句人话。
   *
   * 【为什么动作完了要再拉一次目标（2026-09-17 真机取证）】
   * 此前这里只写回执、**不刷新**：真机上点「暂停」客户端确实发了 `goals/pause`，
   * 点「清除」Host 也回了 `goals/clear ok present=false`（**真的清掉了**），
   * 可进度条一直显示「进行中 · 暂停 · 编辑 · 清除」——状态是旧的，用户以为没生效。
   * 写动词不做乐观改（这是对的），但"不做乐观改"不等于"不刷新"：
   * 写完就从 Host 取一次真值，界面才跟得上。
   */
  private run(action: Promise<ActionNotice>): void {
    action.then((n: ActionNotice) => {
      this.notice = n.code === 'command.executed' ? '' : `未生效：${n.code}`;
      SessionHub.shared().refreshGoal();
    }).catch(() => {
      this.notice = '未生效：动作没能送出去';
      SessionHub.shared().refreshGoal();
    });
  }

  build() {
    Column({ space: Sp.XS }) {
      if (this.state().visible) {
        if (this.editing) {
          this.editRow()
        } else {
          this.stripRow()
        }
        if (this.notice.length > 0) {
          Text(this.notice)
            .fontSize(Fs.CAPTION_XS)
            .fontColor(HarmonyColor.ALERT)
            .width('100%')
        }
      }
    }
    .width('100%')
  }

  /** 常态：相位 + 正文 + 动作 */
  @Builder
  stripRow() {
    Row({ space: Sp.S }) {
      Text('目标')
        .fontSize(Fs.CAPTION_XS)
        .fontColor(HarmonyColor.TEXT_TERTIARY)
      if (this.state().phaseLabel.length > 0) {
        Text(this.state().phaseLabel)
          .fontSize(Fs.CAPTION_XS)
          .fontColor(this.state().canResume ? HarmonyColor.WARNING : HarmonyColor.BRAND)
      }
      Text(this.state().objective)
        .fontSize(Fs.CAPTION)
        .fontColor(HarmonyColor.TEXT_SECONDARY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      // 只有 `active` 才给「暂停」、只有 `paused` 才给「继续」（相位未知时一个都不给）
      if (this.state().canPause) {
        this.actionChip('暂停', () => {
          this.run(SessionHub.shared().pauseGoal());
        })
      }
      if (this.state().canResume) {
        this.actionChip('继续', () => {
          this.run(SessionHub.shared().resumeGoal());
        })
      }
      if (this.state().canEdit) {
        this.actionChip('编辑', () => {
          this.draft = SessionHub.shared().snapshot().goalText;
          this.editing = true;
        })
      }
      if (this.state().canClear) {
        this.actionChip('清除', () => {
          this.run(SessionHub.shared().clearGoal());
        })
      }
    }
    .width('100%')
    .padding({ left: Sp.M, right: Sp.M, top: Sp.XS, bottom: Sp.XS })
    .borderRadius(Radius.S)
    .backgroundColor(HarmonyColor.SURFACE_TERTIARY)
    .borderWidth(Border.HAIRLINE)
    .borderColor(HarmonyColor.DIVIDER)
    .accessibilityText(`长期目标：${this.state().phaseLabel}${this.state().objective}`)
  }

  /** 编辑态：同一行内的内联表单（官方也是"inline form in the same strip"） */
  @Builder
  editRow() {
    Row({ space: Sp.S }) {
      TextInput({ text: this.draft })
        .fontSize(Fs.CAPTION)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.draft = value;
        })
        .accessibilityText('目标正文')
      this.actionChip('保存', () => {
        this.run(SessionHub.shared().editGoal(this.draft));
        this.editing = false;
      })
      this.actionChip('取消', () => {
        this.editing = false;
      })
    }
    .width('100%')
    .padding({ left: Sp.M, right: Sp.M, top: Sp.XS, bottom: Sp.XS })
    .borderRadius(Radius.S)
    .backgroundColor(HarmonyColor.SURFACE_TERTIARY)
    .borderWidth(Border.HAIRLINE)
    .borderColor(HarmonyColor.DIVIDER)
  }

  /** 一个文字动作（小目标：用既有 chip 原语，不新造按钮样式） */
  @Builder
  actionChip(label: string, onTap: () => void) {
    NativeChip({
      label: label,
      active: false,
      a11y: label,
      onTap: onTap
    })
  }
}
