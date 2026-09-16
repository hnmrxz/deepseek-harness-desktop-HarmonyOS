/**
 * 一条消息的**行级交互**（P2-4：从 `ConversationPane` 里抽出的一整块）。
 *
 * ## 它拥有什么（此前散在父组件里的五份状态 + 三段呈现）
 *
 * 1. **悬停态**与它决定的卡片底色；
 * 2. **上下文菜单**（长按 / 右键唤起同一个菜单）与它的开关；
 * 3. **行内操作条**（复制 / 有帮助 / 没帮助 / 引用 / 重发 / 撤回评价）；
 * 4. **反馈表单**（`MessageFeedback`）与本次评价的取向；
 * 5. 手势与菜单的**语义来源**：`InputPolicy` 的三条判定（`hoverEnabled` /
 *    `contextMenuGestures` / `menuGestureHintLabel`）——原先在父组件里散着三个包装方法。
 *
 * ## 为什么"一行里的一件事"要单独成组件
 *
 * 父组件（会话正文）负责的是**过程流的分组与顺序**（回合 / 过程块 / 答案）；
 * 而"这条消息悬停时什么样、长按出什么菜单、评价怎么提交"是**行级**的事。
 * 两者混在一个 1400 行的组件里时，任何一处改动都要通读全文——
 * 这也是本轮拆分的动机（与 `ToolCard` / `DeliverableCard` 同一条规矩）。
 *
 * ## 边界：反馈的**持久化**不在这里
 *
 * 评价的读写走 `SessionHub` 的 `feedback/put` / `feedback/delete`（CAS 版本、失败原因），
 * 那是**中枢的事**；本组件只把"用户选了什么"转出去，回执（`notice`）与"成功才关面板"
 * 的提交策略由父组件决定。代价是两个 prop，收益是：行组件**不持有跨行状态**
 * （一条消息的提交结果不会影响另一条的显示）。
 *
 * ## 仍归父组件的两件事（有意为之）
 *
 * · **思考块与正文的展开态**：父组件有「展开全部 / 收起全部」，那是**跨行**的操作，
 *   所以展开集合的唯一真值在父组件（与 `ToolCard` 的 `expanded` 同理）；
 * · **菜单动作清单的判定**（要不要给"重发"、要不要给"撤回评价"）：它要读中枢的反馈记录，
 *   属于"这条消息现在能做什么"，由父组件算好传进来（`actions`）。
 */

import {
  Fs, HarmonyColor, HarmonyRadius, HarmonySpacing, HarmonyType, INTERNAL_BODY_HIDDEN_PREFIX, MenuGesture,
  Radius, Sp, Speaker,
  TrajectoryItem, contextMenuGestures, formatClock, formatDuration, hoverEnabled, parseMarkdown,
  plainTextOf, userFacingBodyOf
} from 'appstate';
/** 类型单独 import type（本仓约定：值与类型分开写） */
import type { InputModality } from 'appstate';
import type { NativeAction } from './NativePrimitives';
import { NativeActionBar } from './NativePrimitives';
import { MarkdownRenderer } from './MarkdownRenderer';
import { MessageFeedback } from './MessageFeedback';
import { MessageImages } from './MessageImages';

/** 一条消息的卡片（表头 + 图片 + 正文 + 动作条 + 上下文菜单 + 反馈表单） */
@Component
export struct MessageRow {
  /** 这一行的数据 */
  @Prop item: TrajectoryItem;
  /**
   * 会话 id。
   *
   * 【为什么行组件需要它】图片字节要按**会话作用域授权**去读（`session/attachment`），
   * 而会话 id 不在条目里（条目是投影结果，不携带上下文）。传进来而不是让视图去问中枢
   * "当前选中哪个会话"：一条消息属于**它出处的那个会话**，与会话切换无关——
   * 从大厅切到他处再切回来时，"当前选中"可能已经变了，而这条消息没变。
   */
  @Prop sessionId: string = '';
  /** 无障碍文案（父组件按"去标记纯文本"生成） */
  @Prop a11yText: string = '';
  /** 两个输入模态事实（策略模型的输入） */
  @Prop hasPointer: boolean = false;
  @Prop hasKeyboard: boolean = false;
  /**
   * 行内代码 → 本回合产出的文件（空串 = 不是已知文件，保持普通代码）。P9-3。
   *
   * 【为什么由调用方给】官方 `MarkdownFileMentions`："the owner resolves an authored token to
   * the file it names, using its own vocabulary of real files" —— 词汇表属于**回合**，
   * 而 `MessageRow` 只认识"一条消息"。
   */
  mentionPath: (token: string) => string = () => '';

  /** 点一个已知文件（宿主负责打开：读内容 + 切页） */
  onOpenMention: (path: string) => void = () => {
  };
  /** 这条消息正在被评价（父组件持有：它决定"哪条开着"） */
  @Prop feedbackOpen: boolean = false;
  /** 父组件侧的反馈回执（提交结果由父组件决定，这里只显示） */
  @Prop feedbackNotice: string = '';
  /** 该条消息**宿主记录的**评价（决定菜单里要不要给"撤回评价"） */
  @Prop storedRating: string = '';
  /** 该条消息**已存**的反馈类别 / 说明（反馈面板的初值） */
  @Prop storedCategory: string = '';
  @Prop storedNote: string = '';
  /** 动作清单（判定在父组件侧，见 `messageActionsOf`） */
  @Prop actions: NativeAction[] = [];
  /** 动作点击（复制 / 评价 / 引用 / 重发 / 撤回评价 的统一出口） */
  onAction: (item: TrajectoryItem, id: string) => void = () => {
  };
  /** 打开反馈（父组件记"哪条开着"，并把本次取向传回来） */
  onOpenFeedback: (item: TrajectoryItem, rating: string) => void = () => {
  };
  /** 提交评价 */
  onSubmitFeedback: (item: TrajectoryItem, rating: string, category: string, note: string) => void =
    (item: TrajectoryItem, rating: string, category: string, note: string) => {
    };
  /** 关闭反馈面板（含清空它的回执） */
  onCloseFeedback: () => void = () => {
  };

  /** 鼠标是否停在这一行上（只有指针设备才成立——判定见 `isHovered`） */
  @State hovered: boolean = false;
  /** 上下文菜单是否已打开 */
  @State menuShown: boolean = false;
  /** 超长正文是否已展开（默认折叠成一行；见 build 里的长文折叠说明） */
  @State bodyExpanded: boolean = false;

  /** 输入模态快照（策略模型的输入；本组件只做映射，不做判断） */
  private modality(): InputModality {
    return { hasKeyboard: this.hasKeyboard, hasPointer: this.hasPointer };
  }

  /** 悬停态（只有指针设备才可能有"悬停"这个概念） */
  private isHovered(): boolean {
    return hoverEnabled(this.modality()) && this.hovered;
  }

  /** 这条消息的**可见正文**（内部条目为空串，见 F22） */
  private bodyFull(): string {
    return userFacingBodyOf(this.item);
  }

  /** 折叠态要显示的那一行：**纯文本**（不是 Markdown 源文），否则标记会把字数算进去 */
  private bodyPlain(): string {
    return plainTextOf(parseMarkdown(this.bodyFull()));
  }

  /**
   * 是否算"超长"（用户口径：超长的才折，短消息原样）。
   *
   * 阈值：纯文本 > 500 字 **或** 行数 > 6。两个条件都要，是因为
   * "500 字一行写不完"和"6 行短句加起来不到 500 字"都很常见，只用一个会漏。
   */
  private bodyIsLong(): boolean {
    const plain: string = this.bodyPlain();
    if (plain.length > 500) {
      return true;
    }
    let lines: number = 1;
    for (let i = 0; i < plain.length; i++) {
      if (plain.charCodeAt(i) === 10) {
        lines += 1;
      }
    }
    return lines > 6;
  }

  /** 折叠态成立？流式进行中不折（正文还在长，折了会看到"越写越短"） */
  private bodyCollapsed(): boolean {
    return !this.bodyExpanded && !this.item.streaming && this.bodyIsLong();
  }

  /** 是否支持右键唤起菜单（手势集合来自策略模型，不在视图里散落判断） */
  private rightClickEnabled(): boolean {
    return contextMenuGestures(this.modality()).indexOf(MenuGesture.RIGHT_CLICK) >= 0;
  }

  build() {
    Column({ space: Sp.XS }) {
      // ── 表头：谁 · 钟点 · 时长 · 模型 ──
      Row({ space: Sp.S }) {
        Text(this.item.speaker === Speaker.USER ? '我'
          : (this.item.speaker === Speaker.SYSTEM ? '系统' : '助手'))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
        Text(formatClock(this.item.at))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
        if (this.item.elapsedMs > 0) {
          // E204：钟点 + 时长并列（官方"实际时间"的信息，不额外做开关）
          Text(`${formatClock(this.item.at)} · ${formatDuration(this.item.elapsedMs)}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
        Blank()
        if (this.item.model.length > 0) {
          /*
           * 模型名是**次要信息**（切换模型的入口在输入区的工具行），而它可能很长
           * （`provider/model` 两段）。给一个宽度上限并省略：不省略的话，窄屏上它会把
           * 左边的时间/时长挤出屏幕（docs/08 P0 §6：标题可以省略，诊断信息不能只剩省略号——
           * 模型名不属于诊断信息，且这里省略的是尾部）。
           */
          Text(this.item.model)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .constraintSize({ maxWidth: 140 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')

      // ── 图片（P0-3）：官方把图片画在气泡**之前**（用户靠右、助手靠左）──
      if (this.item.images.length > 0) {
        MessageImages({
          sessionId: this.sessionId,
          images: this.item.images,
          alignEnd: this.item.speaker === Speaker.USER
        })
      }

      // ── 正文（Markdown；流式光标跟在句尾）──
      /*
       * F22（真机取证 2026-09-16）：**正文渲染也是一条"出口"**。
       *
       * 此前这里直接渲染 `item.body`，于是轨迹视图里「系统」那一条把**整段系统提示词**
       * 画了出来（不需要点任何格子）。而同一份代码里复制/引用早就走了
       * `userFacingBodyOf()`（P8-5 的"唯一出口取值"）——**只有渲染这一路漏了**。
       *
       * 内部条目取值是空串：此时渲染既有的一句说明（文案复用 `TrajectoryDetail` 里那一份，
       * 不在这里新造第二份），而不是留一片空白让人以为"这条没有内容"。
       */
      /*
       * 【超长正文默认折叠成一行，点击展开】用户要求（2026-09-17）：
       * "对话里超长的应当只显示一行，点击再展开全部内容"。
       *
       * 判据放在**纯文本**上（不是 Markdown 源文）：`plainTextOf(parseMarkdown(…))` 才是用户
       * 真正会看到的字数，用源文长度会把一堆标记算进去、把不该折的折了。
       * 阈值：纯文本 > 500 字 **或** 超过 6 行 ⇒ 视为"超长"。
       * 短消息**原样渲染**——把每一条都折成一行会让整段对话没法读（这是刻意的选择）。
       *
       * 折叠态渲染的是**纯文本单行**（省略号），所以它不可能出现 Markdown 的块级结构；
       * 展开后仍是原来那套 `MarkdownRenderer`（行内强调/代码块/链接提及都在）。
       * 流式进行中不折：正文还在长，折了会看到"越写越短"的怪相。
       */
      if (this.bodyFull().length > 0) {
        if (this.bodyCollapsed()) {
          Row({ space: Sp.S }) {
            Text(this.bodyPlain())
              .fontSize(Fs.BODY)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('展开')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.brand'))
          }
          .width('100%')
          .onClick(() => {
            this.bodyExpanded = true;
          })
        } else {
          MarkdownRenderer({
            text: this.item.streaming ? this.bodyFull() + ' ▌' : this.bodyFull(),
            // 文件提及的词汇表由**回合**给（见 TurnView），这里只透传
            mentionPath: this.mentionPath,
            onOpenMention: this.onOpenMention
          })
          if (this.bodyIsLong()) {
            Text('收起')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.brand'))
              .onClick(() => {
                this.bodyExpanded = false;
              })
          }
        }
      } else if (this.item.internal === true) {
        Text(INTERNAL_BODY_HIDDEN_PREFIX)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }

      // ── 行内动作条（助手消息才有；用户消息的动作在长按菜单里）──
      if (this.item.speaker === Speaker.ASSISTANT) {
        NativeActionBar({
          actions: this.actions,
          onAction: (id: string) => {
            if (id === 'like' || id === 'dislike') {
              // 评价要开表单：取向先记在父组件（它管"哪条开着"），表单本身在这里
              this.onOpenFeedback(this.item, id === 'like' ? 'positive' : 'negative');
              return;
            }
            this.onAction(this.item, id);
          }
        })
          .width('100%')
      }

      // ── 反馈表单（开与关由父组件的 `feedbackOpen` 决定）──
      if (this.feedbackOpen) {
        MessageFeedback({
          initialCategory: this.storedCategory,
          initialNote: this.storedNote,
          notice: this.feedbackNotice,
          onSubmit: (category: string, note: string) => {
            this.onSubmitFeedback(this.item, this.storedRating, category, note);
          },
          onCancel: () => {
            this.onCloseFeedback();
          }
        })
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor(this.isHovered()
      ? HarmonyColor.SURFACE_TERTIARY
      : (this.item.speaker === Speaker.USER ? HarmonyColor.SURFACE_RAISED : HarmonyColor.SURFACE))
    // 悬停反馈：只有指针设备才有"悬停"这个概念（策略模型回答，视图不自己判断）
    .onHover((isHover: boolean) => {
      if (!hoverEnabled(this.modality())) {
        return;
      }
      this.hovered = isHover;
    })
    .accessibilityText(this.a11yText)
    // 触控：长按；指针：右键。**两者唤起同一个菜单**（P3「同一套交互语义」）——
    // 手势集合由输入策略模型决定（`contextMenuGestures`），此处只做映射。
    .gesture(LongPressGesture().onAction(() => {
      this.menuShown = true;
    }))
    .onMouse((e: MouseEvent) => {
      if (this.rightClickEnabled() && e.button === MouseButton.Right) {
        this.menuShown = true;
      }
    })
    .bindContextMenu(this.menuShown, this.contextMenu(), {
      placement: Placement.BottomLeft,
      // 原生关闭（点空白/返回）时要复位，否则菜单再也打不开（与 Sheet 同一个坑）
      onDisappear: () => {
        this.menuShown = false;
      }
    })
  }

  /** 上下文菜单内容：与行内操作条同一份动作清单（不显示空气泡） */
  @Builder
  contextMenu() {
    Column({ space: Sp.XS }) {
      ForEach(this.actions, (a: NativeAction) => {
        Text(a.active === true ? `✓ ${a.label}` : a.label)
          .fontSize(HarmonyType.CAPTION.size)
          .fontColor(a.active === true ? HarmonyColor.BRAND : HarmonyColor.TEXT_PRIMARY)
          .width('100%')
          .padding(HarmonySpacing.CONTROL_INNER)
          .borderRadius(HarmonyRadius.CONTROL)
          .onClick(() => {
            this.menuShown = false;
            if (a.id === 'like' || a.id === 'dislike') {
              this.onOpenFeedback(this.item, a.id === 'like' ? 'positive' : 'negative');
              return;
            }
            this.onAction(this.item, a.id);
          })
      }, (a: NativeAction) => a.id)
    }
    .width(200)
    .padding(HarmonySpacing.CONTROL_INNER)
  }
}
