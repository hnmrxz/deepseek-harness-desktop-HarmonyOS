/**
 * 一条消息的**行级交互**（P2-4：从 `ConversationPane` 里抽出的一整块）。
 *
 * ## v2 T013：按 DSH Mobile 源码级对照重塑（视觉/交互层）
 *
 * 【对照源文件】`.research/deepseek-harness-mobile/app/src/main/java/com/labteto/dshmobile/ui/screens/main/ChatNodeItem.kt`
 * （用户气泡 `UserBubble` 与助手节点 `AssistantNode` 的形态、动作条显隐交互）。
 *
 * · **用户消息** → 右对齐 `UserBubble`：r22 圆角（`DsShape.BUBBLE`）、`userBubble` 填充、
 *   `borderL3` 发丝边、水平 16 / 垂直 10 内边距、`BUBBLE_TEXT` 字阶、最大宽度 82%。
 *   源码 `widthIn(max = 525.dp)` 的绝对上限在手机宽度下恒不触发（82% ≈ 353dp），此处以
 *   82% 单一约束近似并保留注释；图片仍画在气泡**之前**（`alignEnd: true`，同源码）。
 * · **助手消息** → 不套卡片：正文直接走 `MarkdownRenderer`（源码 `AssistantNode` 无行头、
 *   无容器底色），动作条**点击正文才显露**（源码 `actionsVisible` 由 `onTap` 翻转）。
 * · 长按 / 右键上下文菜单、反馈表单（`MessageFeedback`）、图片（`MessageImages`）、
 *   行内代码 → 本回合产出文件的提及解析（`mentionPath`）——全部保留 v1 接线，只换皮。
 * · 明暗色板：`mediaquery('(prefers-color-scheme: dark)')` 监听 + `dsPaletteOf(SYSTEM, dark)`
 *   自包含解析（MobileTheme 为唯一视觉 token 源，见 v2 plan R&D-003）。
 *
 * ## 边界：反馈的**持久化**不在这里
 *
 * 评价的读写走 `SessionHub` 的 `feedback/put` / `feedback/delete`（CAS 版本、失败原因），
 * 那是**中枢的事**；本组件只把"用户选了什么"转出去，回执（`notice`）与"成功才关面板"
 * 的提交策略由父组件决定。
 *
 * ## 仍归父组件的两件事（有意为之）
 *
 * · **思考块与正文的展开态**：父组件有「展开全部 / 收起全部」，那是**跨行**的操作，
 *   所以展开集合的唯一真值在父组件（与 `ToolCard` 的 `expanded` 同理）；
 * · **菜单动作清单的判定**（要不要给"重发"、要不要给"撤回评价"）：它要读中枢的反馈记录，
 *   属于"这条消息现在能做什么"，由父组件算好传进来（`actions`）。
 */

import {
  Border, DsPalette, DsShape, DsSpacing, DsThemePreference, DsType,
  INTERNAL_BODY_HIDDEN_PREFIX, MenuGesture, Speaker,
  TrajectoryItem, contextMenuGestures, dsPaletteOf, userFacingBodyOf
} from 'appstate';
/** 类型单独 import type（本仓约定：值与类型分开写） */
import type { InputModality } from 'appstate';
import type { NativeAction } from './NativePrimitives';
import { MarkdownRenderer } from './MarkdownRenderer';
import { MessageFeedback } from './MessageFeedback';
import { MessageImages } from './MessageImages';
import { mediaquery } from '@kit.ArkUI';

/** 一条消息的行（用户气泡 / 助手纯 Markdown + 点击显露动作条 + 上下文菜单 + 反馈表单） */
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
  /**
   * F28④：**用户这次点的**取向（父组件在打开面板时记下）。
   *
   * 提交必须用它，而不是"已存行的取向"——首评时已存行不存在，
   * 那个值恒为空串，`putFeedback()` 会在 `rating.length === 0` 处直接 return，
   * 于是"点了提交、一个请求都没发出去"（2026-09-16 真机取证）。
   */
  @Prop activeRating: string = '';
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

  /** 上下文菜单是否已打开 */
  @State menuShown: boolean = false;
  /**
   * 动作条是否显露。对照 `ChatNodeItem.kt` 的 `remember { mutableStateOf(false) }` +
   * `onTap { actionsVisible = !actionsVisible }`——v1 是常驻操作条，Mobile 是**点击正文切换**。
   * 流式中不响应（正文在增长，点击误触率高；流完由父组件重渲染时保持当前值）。
   */
  @State actionsVisible: boolean = false;
  /** 系统是否深色（`prefers-color-scheme`；MobileTheme 色板的解析输入） */
  @State dark: boolean = false;
  /** 深色模式监听（aboutToDisappear 必须注销） */
  private darkQuery: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.darkQuery = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
    this.dark = this.darkQuery.matches;
    this.darkQuery.on('change', (result: mediaquery.MediaQueryResult) => {
      this.dark = result.matches;
    });
  }

  aboutToDisappear(): void {
    this.darkQuery?.off('change');
    this.darkQuery = null;
  }

  /** 当前语义色板（MobileTheme 唯一视觉 token 源；SYSTEM 偏好随系统明暗切换） */
  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.dark);
  }

  /** 输入模态快照（策略模型的输入；本组件只做映射，不做判断） */
  private modality(): InputModality {
    return { hasKeyboard: this.hasKeyboard, hasPointer: this.hasPointer };
  }

  /** 这条消息的**可见正文**（内部条目为空串，见 F22） */
  private bodyFull(): string {
    return userFacingBodyOf(this.item);
  }

  /** 是否支持右键唤起菜单（手势集合来自策略模型，不在视图里散落判断） */
  private rightClickEnabled(): boolean {
    return contextMenuGestures(this.modality()).indexOf(MenuGesture.RIGHT_CLICK) >= 0;
  }

  /** 动作统一出口：评价要开表单（取向先记在父组件），其余走 `onAction` */
  private runAction(id: string): void {
    if (id === 'like' || id === 'dislike') {
      this.onOpenFeedback(this.item, id === 'like' ? 'positive' : 'negative');
      return;
    }
    this.onAction(this.item, id);
  }

  build() {
    /*
     * 【2026-09-17 真机读数：空正文的助手消息要整行不画】
     *
     * 提密度时在真机上看到：连续三条「助手 00:34」下面**只有一排动作条**（复制/引用），
     * 正文一行都没有（消息的 content 只有思考块、没有 text）。它看起来像"消息丢了"，
     * 又白占三行高度——而按官方口径，思考是**单独一行**的条目（我们由 `ReasoningRow` 画），
     * 这里本来就没有可视内容。⇒ 没有正文、没有图片、也不是内部条目时，整行不渲染。
     * （对照 `ChatNodeVisibility.kt` 的 `rendersContent` 同一判定意图。）
     */
    if (this.bodyFull().length === 0 && this.item.images.length === 0
      && this.item.internal !== true) {
      Column() {
      }
    } else {
      this.body()
    }
  }

  @Builder
  body() {
    if (this.item.speaker === Speaker.USER) {
      this.userBody()
    } else {
      this.assistantBody()
    }
  }

  /** 用户消息：右对齐气泡（对照 `ChatNodeItem.kt` 的 `UserBubble` 形态） */
  @Builder
  userBody() {
    Column({ space: DsSpacing.XSMALL }) {
      // ── 图片画在气泡**之前**、靠右（源码 `UserBubble` 前置 images，alignEnd）──
      if (this.item.images.length > 0) {
        MessageImages({
          sessionId: this.sessionId,
          images: this.item.images,
          alignEnd: true
        })
      }
      if (this.bodyFull().length > 0) {
        Row({ space: DsSpacing.XSMALL }) {
          // 占位让气泡靠右（源码用 Arrangement.End；ArkUI Row 用 Blank 撑开）
          Blank()
          Text(this.item.streaming ? this.bodyFull() + ' ▌' : this.bodyFull())
            .fontSize(DsType.BUBBLE_TEXT.size)
            .lineHeight(DsType.BUBBLE_TEXT.lineHeight)
            .fontWeight(DsType.BUBBLE_TEXT.weight)
            .fontColor(this.palette().labelPrimary)
            .textAlign(TextAlign.Start)
            // 源码 `widthIn(max = 525.dp)`：绝对上限只在平板宽度触发，手机上 82% 恒更小，
            // 此处以单一百分比约束近似（验收口径：手机屏逐屏对照）。
            .constraintSize({ maxWidth: '82%' })
            .backgroundColor(this.palette().userBubble)
            .borderRadius(DsShape.BUBBLE)
            .borderWidth(Border.HAIRLINE)
            .borderColor(this.palette().borderL3)
            // 水平 16 = DsSpacing.COMFORTABLE；垂直 10 是源码 UserBubble 写死的 10.dp
            // （DsSpacing 无 10 档，照抄源码值并在此注明出处）。
            .padding({
              left: DsSpacing.COMFORTABLE,
              right: DsSpacing.COMFORTABLE,
              top: 10,
              bottom: 10
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
    .accessibilityText(this.a11yText)
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

  /** 助手消息：无卡片容器，纯 Markdown + 点击显露动作条（对照 `AssistantNode`） */
  @Builder
  assistantBody() {
    Column({ space: DsSpacing.TINY }) {
      if (this.item.images.length > 0) {
        MessageImages({
          sessionId: this.sessionId,
          images: this.item.images,
          alignEnd: false
        })
      }

      /*
       * F22（真机取证 2026-09-16）：**正文渲染也是一条"出口"**（`userFacingBodyOf`）。
       * 内部条目取值是空串：渲染既有的一句说明（复用 `TrajectoryDetail` 的文案），
       * 而不是留一片空白让人以为"这条没有内容"。
       * 【2026-09-17 用户决定：正文一律不折叠】——与官方一致，正文完整渲染。
       */
      if (this.bodyFull().length > 0) {
        MarkdownRenderer({
          text: this.item.streaming ? this.bodyFull() + ' ▌' : this.bodyFull(),
          // 文件提及的词汇表由**回合**给（见 TurnView），这里只透传
          mentionPath: this.mentionPath,
          onOpenMention: this.onOpenMention
        })
          .onClick(() => {
            // 对照源码 `onTap { actionsVisible = !actionsVisible }`
            if (!this.item.streaming) {
              this.actionsVisible = !this.actionsVisible;
            }
          })
      } else if (this.item.internal === true) {
        Text(INTERNAL_BODY_HIDDEN_PREFIX)
          .fontSize(DsType.SMALL_13.size)
          .fontColor(this.palette().labelTertiary)
          .width('100%')
      }

      // ── 动作条：点击正文显露（源码 `AnimatedVisibility(actionsVisible)`）──
      if (this.actionsVisible && this.item.speaker === Speaker.ASSISTANT) {
        Row({ space: DsSpacing.TINY }) {
          ForEach(this.actions, (a: NativeAction) => {
            Text(a.label)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontColor(a.active === true ? this.palette().accent : this.palette().labelTertiary)
              .backgroundColor(a.active === true ? this.palette().accentTertiary : Color.Transparent)
              .borderRadius(DsShape.PILL)
              // 源码动作是 28dp 触达盒（ActionIcon）；文本按钮以最小高度对齐同一触达规格
              .constraintSize({ minHeight: 28 })
              .padding({
                left: DsSpacing.SMALL,
                right: DsSpacing.SMALL,
                top: DsSpacing.TINY,
                bottom: DsSpacing.TINY
              })
              .onClick(() => {
                this.runAction(a.id);
              })
          }, (a: NativeAction) => a.id)
        }
        .width('100%')
      }

      // ── 反馈表单（开与关由父组件的 `feedbackOpen` 决定）──
      if (this.feedbackOpen) {
        MessageFeedback({
          initialCategory: this.storedCategory,
          initialNote: this.storedNote,
          notice: this.feedbackNotice,
          onSubmit: (category: string, note: string) => {
            this.onSubmitFeedback(this.item, this.activeRating, category, note);
          },
          onCancel: () => {
            this.onCloseFeedback();
          }
        })
      }
    }
    .width('100%')
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
      onDisappear: () => {
        this.menuShown = false;
      }
    })
  }

  /** 上下文菜单内容：与动作条同一份动作清单（不显示空气泡） */
  @Builder
  contextMenu() {
    Column({ space: DsSpacing.TINY }) {
      ForEach(this.actions, (a: NativeAction) => {
        Text(a.active === true ? `✓ ${a.label}` : a.label)
          .fontSize(DsType.SMALL_13.size)
          .lineHeight(DsType.SMALL_13.lineHeight)
          .fontColor(a.active === true ? this.palette().accent : this.palette().labelPrimary)
          .width('100%')
          .padding({
            left: DsSpacing.SMALL,
            right: DsSpacing.SMALL,
            top: DsSpacing.XSMALL,
            bottom: DsSpacing.XSMALL
          })
          .borderRadius(DsShape.ROW)
          .onClick(() => {
            this.menuShown = false;
            this.runAction(a.id);
          })
      }, (a: NativeAction) => a.id)
    }
    .width(200)
    .padding(DsSpacing.SMALL)
    .backgroundColor(this.palette().bgLayer2)
    .borderRadius(DsShape.MENU)
    .borderWidth(Border.HAIRLINE)
    .borderColor(this.palette().borderL1)
  }
}
