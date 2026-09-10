/**
 * 待决聚合页（D3 §3.7）。
 *
 * 排序：危险动作 > 常规审批 > 提问 > 完成通知，再按入队时间（由 appstate.sortPending 提供）。
 * 支持「就地处理」：不进入会话即可答复（审批三选 / 提问单选或多选 + 自由文本）。
 */

import {
  Fs,
  PendingChoice,
  PendingItem,
  PendingKind,
  Radius,
  RiskLevel,
  riskLabel,
  Sp,
  Sz,
  sortPending
} from 'appstate';

@Component
export struct PendingPane {
  @Prop items: PendingItem[] = [];
  /** 自由文本输入（按待决 id 保存） */
  @State freeText: string = '';
  @State freeTextFor: string = '';
  /** 多选状态（仅提问多选使用） */
  @State chosen: string[] = [];
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
              this.pendingCard(item)
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
            .borderRadius(6)
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

      // 选项
      if (item.multiSelect) {
        ForEach(item.choices, (choice: PendingChoice) => {
          this.multiChoiceRow(item, choice)
        }, (choice: PendingChoice) => `${item.id}-${choice.id}`)
        Button('提交选择')
          .width('100%')
          .enabled(this.chosen.length > 0)
          .onClick(() => {
            this.chosen = [];
          })
      } else {
        ForEach(item.choices, (choice: PendingChoice) => {
          this.singleChoiceRow(item, choice)
        }, (choice: PendingChoice) => `${item.id}-${choice.id}`)
      }

      // 自由文本（审批允许附理由 / 提问允许自定义）
      if (item.allowFreeText) {
        this.freeTextBlock(item)
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.L)
    .backgroundColor($r('sys.color.background_secondary'))
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
  singleChoiceRow(item: PendingItem, choice: PendingChoice) {
    Column({ space: 2 }) {
      Text(choice.label)
        .fontSize(Fs.SECONDARY)
        .fontColor(this.primaryChoiceColor(item, choice))
        .fontWeight(this.isPrimaryChoice(item, choice) ? FontWeight.Bold : FontWeight.Normal)
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
    .borderWidth(1)
    .borderColor(this.isPrimaryChoice(item, choice)
      ? $r('sys.color.brand')
      : $r('sys.color.comp_divider'))
    .margin({ top: Sp.XS })
    .onClick(() => {
      // 答复动作在接入真实 Host 后调用审批/提问应答端点（M3）
    })
  }

  @Builder
  multiChoiceRow(item: PendingItem, choice: PendingChoice) {
    Row({ space: Sp.S }) {
      Checkbox({ name: `${item.id}-${choice.id}`, group: item.id })
        .select(this.chosen.indexOf(choice.id) >= 0)
        .onChange((checked: boolean) => {
          this.chosen = this.toggle(this.chosen, choice.id, checked);
        })
      Column({ space: 2 }) {
        Text(choice.label)
          .fontSize(Fs.SECONDARY)
          .width('100%')
        if (choice.detail.length > 0) {
          Text(choice.detail)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: Sp.XS, bottom: Sp.XS })
  }

  @Builder
  freeTextBlock(item: PendingItem) {
    Column({ space: Sp.XS }) {
      Text(item.kind === PendingKind.APPROVAL ? '拒绝理由（可选）' : '其他（自定义回答）')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      TextInput({
        text: this.freeTextFor === item.id ? this.freeText : '',
        placeholder: item.kind === PendingKind.APPROVAL ? '说明为什么拒绝…' : '输入你的回答…'
      })
        .onChange((value: string) => {
          this.freeTextFor = item.id;
          this.freeText = value;
        })
        .width('100%')
    }
    .width('100%')
  }

  private toggle(list: string[], id: string, on: boolean): string[] {
    const out: string[] = [];
    if (on) {
      for (let i = 0; i < list.length; i++) {
        out.push(list[i]);
      }
      if (out.indexOf(id) < 0) {
        out.push(id);
      }
    } else {
      for (let i = 0; i < list.length; i++) {
        if (list[i] !== id) {
          out.push(list[i]);
        }
      }
    }
    return out;
  }

  /**
   * D3 §3.4：危险动作把主按钮权重反转（视觉上「拒绝」为主）。
   * 这里用边框与文字色体现：危险动作下「拒绝」获得品牌色描边。
   */
  private isPrimaryChoice(item: PendingItem, choice: PendingChoice): boolean {
    if (item.kind !== PendingKind.APPROVAL) {
      return choice.id === 'once' || choice.id === 'a';
    }
    if (item.risk === RiskLevel.DANGEROUS) {
      return choice.id === 'deny';
    }
    return choice.id === 'once';
  }

  private primaryChoiceColor(item: PendingItem, choice: PendingChoice): ResourceColor {
    if (this.isPrimaryChoice(item, choice)) {
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
