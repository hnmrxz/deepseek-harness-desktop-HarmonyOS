/**
 * 待决聚合页（D3 §3.7）。
 *
 * 排序：危险动作 > 常规审批 > 提问 > 完成通知，再按入队时间（由 appstate.sortPending 提供）。
 * 支持「就地处理」：不进入会话即可答复（审批三选 / 提问单选或多选 + 自由文本）。
 */

import {
  PendingAnswerDraft,
  APPROVAL_CHOICE_ALLOW,
  APPROVAL_CHOICE_DENY,
  Fs,
  PendingChoice,
  PendingItem,
  PendingKind,
  Radius,
  RiskLevel,
  riskLabel,
  Sp,
  sortPending,
  Border
} from 'appstate';
import { QuestionGroupCard } from './QuestionGroupCard';

@Component
export struct PendingPane {
  @Prop items: PendingItem[] = [];

  /**
   * 答复审批。`choiceId` 取值来自 `appstate` 的审批选项契约
   * （`APPROVAL_CHOICE_ALLOW` / `APPROVAL_CHOICE_DENY`），`reason` 是可选的拒绝理由（空串表示未填）。
   *
   * **只有两选**（P7-17）：上游结果词表是 `allowed-once | rejected | cancelled | unavailable`，
   * **没有**持久授权；官方审批卡也只有 `reject` / `allowOnce` 两颗按钮。
   * 我们曾经多一颗「本次会话内均允许」，但它在本端什么都没记住（只写一行旁路日志）
   * ⇒ 那是"点了没反应"的假入口，已删。要做持久授权得先有协议侧载体。
   */
  onDecide: (item: PendingItem, choiceId: string, reason: string) => void = () => {
  };

  /**
   * 提交提问的**整组**答案（P7-5）。
   *
   * Host 等的是**一个**答复值 `{answers:[{id,selected,custom?}…]}` ⇒ 逐题各发一次会让
   * "第一次就结掉、后面的答案没处去"。故这里交回的是**逐题草稿**，由宿主一次构造。
   * `selected` 里放的是**选项 label 原文**（上游 `AskUserQuestionAnswerItem.selected` 要 label）。
   */
  onAnswer: (item: PendingItem, drafts: PendingAnswerDraft[]) => void = () => {
  };

  /** 放弃整组提问（官方 `nav.cancel`） */
  onCancelQuestion: (item: PendingItem) => void = () => {
  };

  /** 自由文本输入（按待决 id 保存） */
  @State freeText: string = '';
  @State freeTextFor: string = '';
  /** 多选状态（仅提问多选使用） */
  /** 当前展开原始请求的待决 id（空 = 全部收起） */
  @State rawExpanded: string = '';

  build() {
    Column() {
      if (this.items.length === 0) {
        Column({ space: Sp.M }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(40)
            .fontColor([$r('sys.color.confirm')])
          Text('没有待处理事项')
            .fontSize(Fs.BODY)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: Sp.M }) {
          ForEach(sortPending(this.items), (item: PendingItem) => {
            ListItem() {
              if (item.kind === PendingKind.APPROVAL) {
                this.pendingCard(item)
              } else {
                this.questionCard(item)
              }
            }
          }, (item: PendingItem) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding(Sp.M)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  pendingCard(item: PendingItem) {
    Column({ space: Sp.S }) {
      // 头部：类型 + 风险徽标
      Row({ space: Sp.S }) {
        SymbolGlyph(item.kind === PendingKind.APPROVAL
          ? $r('sys.symbol.exclamationmark_triangle')
          : $r('sys.symbol.questionmark_circle'))
          .fontSize(18)
          .fontColor([item.kind === PendingKind.APPROVAL
            ? $r('sys.color.warning')
            : $r('sys.color.brand')])
        Text(item.kind === PendingKind.APPROVAL ? '需要你的批准' : '有问题需要你回答')
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        if (item.kind === PendingKind.APPROVAL) {
          Text(riskLabel(item.risk))
            .fontSize(Fs.CAPTION)
            .fontColor(this.riskColor(item.risk))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(Radius.XS)
            .backgroundColor($r('sys.color.background_secondary'))
        }
      }
      .width('100%')

      // 会话来源
      Text(item.sessionTitle)
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      // 动作 / 问题正文
      Text(item.title)
        .fontSize(Fs.BODY)
        .fontWeight(FontWeight.Medium)
        .width('100%')

      if (item.detail.length > 0) {
        Text(item.detail)
          .fontSize(Fs.SECONDARY)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }

      // 原始请求（可展开）
      if (item.raw.length > 0) {
        this.rawBlock(item)
      }

      // 选项（审批：三选，点一下即应答）
      if (item.kind === PendingKind.APPROVAL) {
        ForEach(item.choices, (choice: PendingChoice, index: number) => {
          this.singleChoiceRow(item, choice, index)
        }, (choice: PendingChoice) => `${item.id}-${choice.id}`)
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.L)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  /**
   * 提问：**整组**卡片（P7-5，官方 `dsh-client-ui-user-questions` 的交互）。
   *
   * 逐题导航、跳过、提交前的官方拦阻文案都在 `QuestionGroupCard` 自己身上
   * （它持有"第几题 + 每题选了什么"这份逐题草稿）；这里只把整组答案交回宿主。
   */
  @Builder
  questionCard(item: PendingItem) {
    QuestionGroupCard({
      item: item,
      onSubmit: (it: PendingItem, drafts: PendingAnswerDraft[]) => {
        this.onAnswer(it, drafts);
      },
      onCancelGroup: (it: PendingItem) => {
        this.onCancelQuestion(it);
      }
    })
  }

  /** 取当前卡片已填的自由文本（只认属于该卡片的输入，避免串到别的卡片） */
  private textFor(item: PendingItem): string {
    return this.freeTextFor === item.id ? this.freeText : '';
  }

  @Builder
  rawBlock(item: PendingItem) {
    Column({ space: Sp.XS }) {
      Text('▸ 查看原始请求')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.brand'))
        .onClick(() => {
          this.rawExpanded = this.rawExpanded === item.id ? '' : item.id;
        })
      if (this.rawExpanded === item.id) {
        Text(item.raw)
          .fontSize(Fs.CAPTION)
          .fontFamily('monospace')
          .width('100%')
          .padding(Sp.S)
          .borderRadius(Radius.S)
          .backgroundColor($r('sys.color.background_primary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  singleChoiceRow(item: PendingItem, choice: PendingChoice, index: number) {
    Column({ space: 2 }) {
      Text(choice.label)
        .fontSize(Fs.SECONDARY)
        .fontColor(this.primaryChoiceColor(item, choice, index))
        .fontWeight(this.isPrimaryChoice(item, choice, index) ? FontWeight.Bold : FontWeight.Normal)
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
    .borderColor(this.isPrimaryChoice(item, choice, index)
      ? $r('sys.color.brand')
      : $r('sys.color.comp_divider'))
    .margin({ top: Sp.XS })
    .onClick(() => {
      // 这张卡现在只服务**审批**（提问走 `QuestionGroupCard`）⇒ 点一下就是应答
      this.onDecide(item, choice.id, this.textFor(item));
    })
  }

  /**
   * D3 §3.4：危险动作把主按钮权重反转（视觉上「拒绝」为主）。
   * 这里用边框与文字色体现：危险动作下「拒绝」获得品牌色描边。
   *
   * **用 `appstate` 的稳定 id 契约判定，不再用字面量**：
   * 曾经视图判 `choice.id === 'once'`，而中枢产出的是 `'allow'`——
   * 桩数据下看着正常，一接真实 Host 主选样式就静默失效。
   *
   * 提问不给「推荐项」：审批的主选是**安全语义**（危险时把拒绝提为主选），
   * 而提问的选项之间没有安全优劣，替用户高亮一个会构成引导。
   * 因此提问一律不高亮（此前高亮第一项，属于无意的倾向性）。
   */
  private isPrimaryChoice(item: PendingItem, choice: PendingChoice, index: number): boolean {
    if (item.kind !== PendingKind.APPROVAL) {
      return false;
    }
    if (item.risk === RiskLevel.DANGEROUS) {
      return choice.id === APPROVAL_CHOICE_DENY;
    }
    return choice.id === APPROVAL_CHOICE_ALLOW;
  }

  private primaryChoiceColor(item: PendingItem, choice: PendingChoice,
    index: number): ResourceColor {
    if (this.isPrimaryChoice(item, choice, index)) {
      return $r('sys.color.brand');
    }
    return $r('sys.color.font_primary');
  }

  private riskColor(risk: RiskLevel): ResourceColor {
    if (risk === RiskLevel.DANGEROUS) {
      return $r('sys.color.alert');
    }
    if (risk === RiskLevel.ELEVATED) {
      return $r('sys.color.warning');
    }
    return $r('sys.color.font_tertiary');
  }
}
