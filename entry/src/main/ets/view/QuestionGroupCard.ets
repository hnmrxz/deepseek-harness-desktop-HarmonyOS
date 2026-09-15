/**
 * 提问**整组**卡片（P7-5，对齐官方 `dsh-client-ui-user-questions` 的交互）。
 *
 * ## 官方的交互（读它的字典）
 *
 *   · **一个按钮前进**：`index === questions.length - 1 ? t("submit") : t("action.next")`
 *     —— 不是每题一个提交键；到最后一题，同一个键变成「提交」；
 *   · `nav.prev`（上一题）、`nav.minimize/maximize`（收起/展开）、`nav.cancel`（放弃整组问题）；
 *   · `action.skip`（跳过本题）；
 *   · 提交前逐题校验，拦阻文案**逐字取官方**：`error.incomplete: 请先完成这道问题。` /
 *     `error.unanswered: 请选择一个选项或填写自定义答案。`；
 *   · 自定义答案的占位是 `custom.placeholder: 输入你的答案`。
 *
 * ## 为什么单独一个组件
 *
 * 它自己持有"第几题 / 每题选了什么 / 填了什么"这份**逐题草稿**（与 `PendingPane` 的
 * 审批卡是两件事），而提交只发生一次：整组答案一次性交回宿主
 * （Host 等的是**一个**答复值，见 `SessionHub.answerQuestionGroup`）。
 *
 * ## 我们**没做**的两处（如实登记，不假装）
 *
 *   · `option.recommended`（推荐标记）：上游选项里有没有这个字段我们的投影没带 ⇒ 不画，
 *     而不是拿"第一项"冒充推荐（那会构成引导）；
 *   · `nav.cancel`（放弃整组）：官方这一动作的**线上语义未取证**（它走的是哪条 outcome 我们
 *     在协议面里没找到对应词）⇒ 不做一个语义不明的按钮。
 */

import {
  answerableDrafts,
  planReviewOf,
  parseOptionLabel,
  Border,
  draftAnswered,
  Fs,
  PendingAnswerDraft,
  PendingChoice,
  PendingItem,
  PendingKind,
  PendingQuestion,
  questionIndexStep,
  questionNavLabel,
  Radius,
  RiskLevel,
  Sp,
  Sz,
  submitBlockedText,
  PlanReview
} from 'appstate';
import { NativeButton } from './NativePrimitives';

@Component
export struct QuestionGroupCard {
  /** 待决事项（`kind === QUESTION`，`questions[]` 至少一条） */
  @Prop item: PendingItem = emptyPending();

  /** 整组提交（宿主一次交回 Host） */
  onSubmit: (item: PendingItem, drafts: PendingAnswerDraft[]) => void = () => {
  };
  /**
   * 放弃整组问题（官方 `nav.cancel: 放弃整组问题`）。
   *
   * 线上语义已取证：发 `{kind:'rejected', error:{name:'UserQuestionError',
   * code:'ASK_CANCELLED'}}`（**不是** `{kind:'next'}`——那是"我不处理，交给下一个应答者"）。
   */
  onCancelGroup: (item: PendingItem) => void = () => {
  };

  /** 逐题草稿（本组件状态：切题不丢、提交前校验用） */
  @State drafts: PendingAnswerDraft[] = [];
  /** 草稿属于哪个待决（换了卡片就重建，避免串答案） */
  @State draftsFor: string = '';
  /** 当前第几题 */
  @State index: number = 0;
  /** 拦阻文案（官方那两句） */
  @State blockText: string = '';

  /** 当前题（越界返回 undefined；条目没有整组时退回顶层摘要那条） */
  private currentQuestion(): PendingQuestion | undefined {
    const list: PendingQuestion[] = this.item.questions;
    if (list.length === 0) {
      return undefined;
    }
    const at: number = this.index < list.length ? this.index : list.length - 1;
    return list[at];
  }

  private total(): number {
    return this.item.questions.length;
  }

  /** 这张卡是不是"计划待审"（判定在模型里，这里只读结论） */
  private planReviewOfCurrent(): PlanReview | undefined {
    return planReviewOf(this.item.questions);
  }

  /**
   * 取（必要时初始化）逐题草稿。
   *
   * 【为什么按 item.id 重建】不同待决的答案绝不能互相串 —— 与 `PendingPane` 的
   * `freeTextFor` 同一条纪律（那次是"文本串到别的卡片"的实测缺陷）。
   */
  private ensureDrafts(): PendingAnswerDraft[] {
    if (this.draftsFor === this.item.id && this.drafts.length === this.total()) {
      return this.drafts;
    }
    const out: PendingAnswerDraft[] = [];
    for (let i = 0; i < this.item.questions.length; i++) {
      out.push({ questionId: this.item.questions[i].id, selected: [], custom: '', skipped: false });
    }
    this.draftsFor = this.item.id;
    this.drafts = out;
    return out;
  }

  private draftAt(at: number): PendingAnswerDraft {
    const list: PendingAnswerDraft[] = this.ensureDrafts();
    return list[at];
  }

  /** 写回某一题的草稿（`drafts` 是数组引用，必须整体换新才会触发重绘） */
  private writeDraft(at: number, next: PendingAnswerDraft): void {
    const list: PendingAnswerDraft[] = this.ensureDrafts();
    const out: PendingAnswerDraft[] = [];
    for (let i = 0; i < list.length; i++) {
      out.push(i === at ? next : list[i]);
    }
    this.drafts = out;
  }

  private toggleSelected(at: number, label: string, on: boolean): void {
    const draft: PendingAnswerDraft = this.draftAt(at);
    const selected: string[] = [];
    for (let i = 0; i < draft.selected.length; i++) {
      if (draft.selected[i] !== label) {
        selected.push(draft.selected[i]);
      }
    }
    if (on) {
      selected.push(label);
    }
    this.writeDraft(at, {
      questionId: draft.questionId,
      selected: selected,
      custom: draft.custom,
      skipped: draft.skipped
    });
  }

  /** 主键：不是最后一题 ⇒ 下一题；是最后一题 ⇒ 提交整组 */
  private primaryLabel(): string {
    return this.index >= this.total() - 1 ? '提交' : '下一题';
  }

  /** 主键动作：先校验当前题，再前进或提交（官方 `error.incomplete` 的时机） */
  private primaryAction(): void {
    const at: number = this.index;
    const draft: PendingAnswerDraft = this.draftAt(at);
    if (!draftAnswered(draft)) {
      this.blockText = '请先完成这道问题。';
      return;
    }
    this.blockText = '';
    if (at < this.total() - 1) {
      this.index = at + 1;
      return;
    }
    const blocked: string = submitBlockedText(this.ensureDrafts(), at);
    if (blocked.length > 0) {
      this.blockText = blocked;
      return;
    }
    this.onSubmit(this.item, answerableDrafts(this.ensureDrafts()));
  }

  /**
   * 计划待审面板（官方 `dsh-client-ui-user-questions` 的 `planReviewOf` + 文案）。
   *
   * 官方的三颗按钮与它们的**线上动作**：
   *   · **去聊天里说** ⇒ `pending.cancel()` ⇒ 就是我们上一轮实现的
   *     `{kind:'rejected', error:{name:'UserQuestionError', code:'ASK_CANCELLED'}}`（放弃整组）；
   *   · **拒绝**（只在请求给了第二个选项时出现）⇒ 用那个选项的**标签原文**作答；
   *   · **确认执行** ⇒ 用 `intent.approve` 指名的那个标签作答。
   * 判定（六条收窄规则）在 `model/Trajectory.planReviewOf`，有 fixture 钉住。
   */
  @Builder
  planReview(review: PlanReview) {
    Column({ space: Sp.S }) {
      Row({ space: Sp.S }) {
        Circle({ width: 8, height: 8 })   // token-exempt: 状态点几何（官方 header 前的圆点）
          .fill($r('sys.color.brand'))
        Text('计划待审')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .layoutWeight(1)
      }
      .width('100%')

      Text(review.plan)
        .fontSize(Fs.SECONDARY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      Row({ space: Sp.S }) {
        NativeButton({
          label: '去聊天里说',
          emphasis: 'text',
          tone: 'neutral',
          onTap: () => {
            this.onCancelGroup(this.item);
          }
        })
        Blank()
        if (review.declineLabel.length > 0) {
          NativeButton({
            label: '拒绝',
            emphasis: 'outline',
            tone: 'neutral',
            onTap: () => {
              this.submitSingle(review.declineLabel);
            }
          })
        }
        NativeButton({
          label: '确认执行',
          emphasis: 'solid',
          tone: 'brand',
          onTap: () => {
            this.submitSingle(review.approveLabel);
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.L)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  /** 计划面板的单选作答：把选中的标签交回宿主（仍走整组那条通道，只是组里只有一题） */
  private submitSingle(label: string): void {
    const at: number = 0;
    const questionId: string = this.item.questions.length > 0 ? this.item.questions[0].id : '';
    const drafts: PendingAnswerDraft[] = [{
      questionId: questionId,
      selected: [label],
      custom: '',
      skipped: false
    }];
    this.onSubmit(this.item, drafts);
  }

  build() {
    Column({ space: Sp.S }) {
      if (this.planReviewOfCurrent() !== undefined) {
        this.planReview(this.planReviewOfCurrent()!)
      } else {
        if (this.total() > 1) {
          Text(questionNavLabel(this.index, this.total()))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }

        if (this.currentQuestion() !== undefined) {
          Text((this.currentQuestion() as PendingQuestion).text)
            .fontSize(Fs.BODY)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          if ((this.currentQuestion() as PendingQuestion).detail.length > 0) {
            Text((this.currentQuestion() as PendingQuestion).detail)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          }
          // 选项：单选点一下就记进草稿（**不立即提交** —— 整组要一起交）
          ForEach((this.currentQuestion() as PendingQuestion).choices, (choice: PendingChoice) => {
            Column({ space: 2 }) {
              Row({ space: Sp.S }) {
                /*
                 * 【推荐标记来自**标签后缀**，不是字段】官方 `parseRecommendedLabel`：
                 * 标签以 `(recommended)` / `（推荐）` 结尾 ⇒ 显示时**剥掉后缀**并加「推荐」。
                 * 而**提交必须送原标签**（官方注释：Original option label returned if selected）
                 * ⇒ 选中判定与草稿里存的都是 `choice.label`（原文），只有显示用剥过的版本。
                 */
                Text(parseOptionLabel(choice.label).label)
                  .fontSize(Fs.SECONDARY)
                  .fontColor(this.selectedLabel(choice.label)
                    ? $r('sys.color.brand')
                    : $r('sys.color.font_primary'))
                  .fontWeight(this.selectedLabel(choice.label) ? FontWeight.Bold : FontWeight.Normal)
                  .layoutWeight(1)
                if (parseOptionLabel(choice.label).recommended) {
                  Text('推荐')
                    .fontSize(Fs.CAPTION_XS)
                    .fontColor($r('sys.color.brand'))
                    .padding({ left: 5, right: 5 })   // token-exempt: 徽标药丸内边距
                    .borderRadius(5)   // token-exempt: 徽标药丸圆角
                    .backgroundColor($r('sys.color.background_primary'))
                }
              }
              .width('100%')
              if (choice.detail.length > 0) {
                Text(choice.detail)
                  .fontSize(Fs.CAPTION)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
              }
            }
            .width('100%')
            .padding({ left: Sp.M, right: Sp.M, top: Sp.S, bottom: Sp.S })
            .borderRadius(Radius.S)
            .borderWidth(Border.HAIRLINE)
            .borderColor(this.selectedLabel(choice.label)
              ? $r('sys.color.brand')
              : $r('sys.color.comp_divider'))
            .margin({ top: Sp.XS })
            .onClick(() => {
              const q: PendingQuestion = this.currentQuestion() as PendingQuestion;
              if (q.multiSelect) {
                this.toggleSelected(this.index, choice.label, !this.selectedLabel(choice.label));
              } else {
                this.writeDraft(this.index, {
                  questionId: this.draftAt(this.index).questionId,
                  selected: [choice.label],
                  custom: '',
                  skipped: false
                });
              }
              this.blockText = '';
            })
          }, (choice: PendingChoice) => `${this.item.id}-${this.index}-${choice.id}`)

          // 自定义答案（官方 `custom.placeholder: 输入你的答案`）
          TextInput({
            text: this.draftAt(this.index).custom,
            placeholder: '输入你的答案'
          })
            .fontSize(Fs.CAPTION)
            .height(Sz.TOUCH_MIN)
            .width('100%')
            .onChange((value: string) => {
              const draft: PendingAnswerDraft = this.draftAt(this.index);
              this.writeDraft(this.index, {
                questionId: draft.questionId,
                selected: draft.selected,
                custom: value,
                skipped: false
              });
              this.blockText = '';
            })
        }

        if (this.blockText.length > 0) {
          Text(this.blockText)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.warning'))
            .width('100%')
        }

        Row({ space: Sp.S }) {
          // 官方 `nav.cancel: 放弃整组问题`
          NativeButton({
            label: '放弃整组问题',
            emphasis: 'text',
            tone: 'neutral',
            onTap: () => {
              this.onCancelGroup(this.item);
            }
          })
          NativeButton({
            label: '跳过本题',
            emphasis: 'text',
            tone: 'neutral',
            onTap: () => {
              const draft: PendingAnswerDraft = this.draftAt(this.index);
              this.writeDraft(this.index, {
                questionId: draft.questionId,
                selected: [],
                custom: '',
                skipped: true
              });
              this.blockText = '';
              if (this.index < this.total() - 1) {
                this.index = questionIndexStep(this.index, this.total(), 1);
              } else {
                this.onSubmit(this.item, answerableDrafts(this.ensureDrafts()));
              }
            }
          })
          // 官方 `nav.prev: 上一题`（第一题时不给 —— 到头就停住，不循环）
          if (this.index > 0) {
            NativeButton({
              label: '上一题',
              emphasis: 'text',
              tone: 'neutral',
              onTap: () => {
                this.index = questionIndexStep(this.index, this.total(), -1);
                this.blockText = '';
              }
            })
          }
          Blank()
          NativeButton({
            label: this.primaryLabel(),
            emphasis: 'solid',
            tone: 'brand',
            onTap: () => {
              this.primaryAction();
            }
          })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.L)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  /** 当前题里这个选项是否已被选中（在草稿里） */
  private selectedLabel(label: string): boolean {
    const draft: PendingAnswerDraft = this.draftAt(this.index);
    return draft.selected.indexOf(label) >= 0;
  }
}

/** ArkTS 要求 `@Prop` 有初值；这是"空待决"的显式构造（不参与渲染） */
function emptyPending(): PendingItem {
  return {
    id: '', kind: PendingKind.QUESTION, sessionId: '', sessionTitle: '',
    title: '', detail: '', raw: '', risk: RiskLevel.NORMAL, choices: [],
    multiSelect: false, allowFreeText: false, questions: [], at: 0
  };
}
