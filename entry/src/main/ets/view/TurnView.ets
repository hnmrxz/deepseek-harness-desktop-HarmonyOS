/**
 * 会话正文的**回合渲染**（P2-6 第二刀：从 `ConversationPane` 整块搬出）。
 *
 * ## 它拥有什么
 *
 * "一条会话流怎么画成一个回合"这件事的全部：
 *   · **回合骨架** `turnBlock`（用户消息 → 过程分组 → 回答 → 通知；顺序即阅读顺序，不做"智能排序"）；
 *   · **过程分组** `processGroup`（思考 / 工具 / 子代理 / 进度 / 交付物；折叠默认态由模型 `defaultExpanded` 决定）；
 *   · **条目分派** `trajectoryItem`（消息 / 思考 / 工具卡 / 子代理 / 交付物 / 目标或任务 / 错误）；
 *   · **本组件自有的三处呈现**：思考折叠块 `reasoningItem`、目标/任务卡 `goalItem`、错误块 `errorItem`；
 *   · **展开集合**（`expanded`）与它的两个方法（`isExpanded` / `toggle`）；
 *   · **消息反馈**的组件侧辅助（动作清单组装、类别与说明的初值、回执文案、提交）。
 *
 * ## 为什么这一块单独成组件
 *
 * 它此前长在 `ConversationPane`（1093 行）里，与"列表 chrome、滚动跟随、搜索命中、输入区"混在一起。
 * 那四件事**不属于回合**：它们决定"列表怎么滚、什么算命中、输入区在哪"；而这里决定
 * **"一条回合长什么样"**。分开之后两边都能一眼读完（P2-4 / P2-5 同一条理由）。
 *
 * ## 三条边界（有意为之）
 *
 * 1. **展开集合留在本组件，但按钮在父组件的会话头里** ⇒ 通过 `TurnViewController` 把
 *    "全部展开 / 收起全部"两个动作**暴露给父组件**（`aboutToAppear` 注册）。
 *    为什么不把 `expanded` 提成父组件的 prop：那样父组件要维护"哪些条目 id"，而它不渲染条目；
 *    对照 `ToolCard.expanded` —— 那张卡是**跨面板共用**的，所以它的展开态必须由外部给。
 * 2. **"这条消息现在能做什么"**（要不要给"重发 / 撤回评价"）要读中枢的反馈记录 ⇒ 由这里算；
 *    但**持久化**（`feedback/put` 的 CAS 与失败原因）留在中枢，**回执显示**与"成功才关面板"留在父组件。
 * 3. **命中判定（`hitIds`）** 由父组件给：它扫的是整条过程流（含另一个视图的条目），
 *    而这里只看得到一条回合。「这条回合有没有命中」的**色条**判定同样在父组件
 *    （列表项是它画的，命中集合也在它手里）。
 */

import { ActionNotice, FeedbackRow, Fs, Radius, SHARE_TARGET_NONE, SessionHub, ShareTarget, Sp, Speaker, TrajectoryItem, TrajectoryKind, Turn, baseNameOf, defaultExpanded, parseMarkdown, plainTextOf, producedFilesOf, resolveProducedMention, userFacingBodyOf } from 'appstate';
import type { ProducedFile } from 'appstate';
import { presentTool, toolStateLabel } from 'appstate';
import { NativeCard } from './NativePrimitives';
import type { NativeAction } from './NativePrimitives';
import { MessageRow } from './MessageRow';
import { ReasoningRow } from './ReasoningRow';
import { DeliverableCard } from './DeliverableCard';
import { SubagentCard } from './SubagentCard';
import { ToolCard } from './ToolCard';
import { CommandRow } from './CommandRow';
import { RetryRow } from './RetryRow';
import { ProducedFilesRow } from './ProducedFilesRow';

/**
 * 把"全部展开 / 收起全部"从回合渲染里接出去（E351）。
 *
 * 【为什么需要一个控制器对象】这两个动作要改的是**回合渲染内部的**展开集合，而按钮长在
 * **父组件的会话头**里（官方轨迹工具栏的位置）。三条路都权衡过：
 *   · 把 `expanded` 提成父组件 prop —— 父组件就得维护"哪些条目 id"，而它不渲染条目；
 *   · 让父组件持有子组件的回调 —— 父组件渲染时机与子组件注册时机不同，容易拿到过期闭包；
 *   · **控制器对象**：父组件持一个空壳，子组件在 `aboutToAppear` 把实现注册进去。
 * 这个形状与 ArkUI 的 `Scroller` 同源（父组件持句柄、子组件实现行为）。
 *
 * 【未挂载时】父组件只在"对话视图"挂 `TurnView`；而这两个按钮只在"轨迹视图"显示 ⇒
 * 不存在"按钮在、实现没注册"的时刻；真发生也只是安全空操作（不抛、不改错状态）。
 */
export class TurnViewController {
  private expander: () => void = () => {
  };
  private collapser: () => void = () => {
  };

  /** 由 `TurnView.aboutToAppear` 注册实现 */
  register(expandAll: () => void, collapseAll: () => void): void {
    this.expander = expandAll;
    this.collapser = collapseAll;
  }

  expandAll(): void {
    this.expander();
  }

  collapseAll(): void {
    this.collapser();
  }
}

/** 一个回合的渲染（含它内部的展开集合与消息反馈辅助） */
@Component
export struct TurnView {
  /** 要渲染的回合 */
  @Prop turn: Turn;
  /**
   * 打开一枚产出文件（P7-21）。
   *
   * 宿主必须**同时**做两件事：把内容读进预览 + 切到能看见预览的页面。
   * 只读不切在手机上等于"点了没反应"（右栏在单栏形态下不在屏幕上）。
   */
  onOpenProduced: (path: string, name: string) => void = () => {
  };
  /** 一条交付物的分享目标（P9-7；宿主算好传下来，卡片不认识中枢） */
  deliverableShareTarget: (item: TrajectoryItem) => ShareTarget = (item: TrajectoryItem) => {
    return { kind: SHARE_TARGET_NONE, absPath: '', text: '', reason: '' };
  };
  /** 分享这条交付物 */
  onShareDeliverable: (item: TrajectoryItem) => void = () => {
  };
  /**
   * 会话 id（图片读取要用它做**会话作用域**授权）。
   *
   * 由父组件传进来而不是让子组件去问中枢"当前选中哪个会话"：
   * 一条消息属于**它出处的那个会话**，与"此刻选中的是哪个"是两件事。
   */
  @Prop sessionId: string = '';
  /** 展开集合的唯一真值（见文件头第 1 条边界） */
  @Prop expanded: string[] = [];
  /** 展开集合变化（真值在父组件 ⇒ 由它落状态） */
  onExpandedChange: (next: string[]) => void = () => {
  };
  /** 控制器：父组件用"全部展开 / 收起全部"两个动作 */
  @Prop controller: TurnViewController;
  /** 两个输入模态事实（策略模型的输入；本组件只做映射） */
  @Prop hasPointer: boolean = false;
  @Prop hasKeyboard: boolean = false;
  /** 哪个消息的反馈面板开着（空串 = 都没开） */
  @Prop fbFor: string = '';
  /**
   * 当前档位（`Index` 发布）。
   *
   * 口径：**PC / 平板 / 2in1 与官方 1:1 复刻，手机端才做适应性优化**。
   * 这里只用它决定一件事：评价按钮（有帮助/没帮助）在手机上隐藏、其他端保留。
   */
  @StorageProp('dshLayoutMode') layoutMode: string = 'single';
  /** F28④：用户这次点的取向（打开面板时记下；提交时用它，而不是"已存行的取向"） */
  @State private fbRating: string = '';
  /** 反馈回执（提交结果由父组件显示） */
  @Prop fbNote: string = '';
  /** 动作的副作用在父组件：复制 / 引用 / 重发 */
  onCopyMessage: (text: string) => void = () => {
  };
  onQuoteMessage: (item: TrajectoryItem) => void = () => {
  };
  onResendMessage: (item: TrajectoryItem) => void = () => {
  };
  /** 错误块里的「查看诊断」（导航由父组件做——视图不自己跳页） */
  onOpenDetail: () => void = () => {
  };
  /** 反馈面板：打开（父组件记"哪条开着"与取向）/ 写回执 / 关闭 */
  onOpenFeedback: (itemId: string, rating: string) => void = () => {
  };
  onFeedbackNote: (note: string) => void = () => {
  };
  onCloseFeedback: () => void = () => {
  };

  /** 控制器注册：把"全部展开 / 收起全部"交给父组件的会话头按钮 */
  aboutToAppear(): void {
    this.controller.register(() => {
      this.expandAllItems();
    }, () => {
      this.onExpandedChange([]);
    });
  }

  /**
   * 全部展开（E197）：把**本条回合**里所有条目的 id 交回去。
   *
   * 【为什么只给本条回合】`TurnView` 一次只渲染一个回合（对话视图的列表项就是它），
   * "全部展开"于是由每个回合各自上报一次、父组件把结果并起来——这样"展开"这件事
   * 不需要父组件知道条目结构（它只知道 id 列表）。
   */
  private expandAllItems(): void {
    const next: string[] = [];
    const t: Turn = this.turn;
    if (t.user !== undefined) {
      next.push(t.user.id);
    }
    for (let i = 0; i < t.process.length; i++) {
      next.push(t.process[i].id);
    }
    for (let i = 0; i < t.answers.length; i++) {
      next.push(t.answers[i].id);
    }
    for (let i = 0; i < t.notices.length; i++) {
      next.push(t.notices[i].id);
    }
    this.onExpandedChange(next);
  }

  /*
   * 【2026-09-17：`processExpanded()` 已删】它只服务那个已被删掉的过程分组头。
   * `defaultExpanded` 仍然在用——工具卡/思考块的折叠默认态走的就是它（见 `trajectoryItem`）。
   */

  private isExpanded(id: string): boolean {
    return this.expanded.indexOf(id) >= 0;
  }

  private toggle(id: string): void {
    const out: string[] = [];
    let found: boolean = false;
    for (let i = 0; i < this.expanded.length; i++) {
      if (this.expanded[i] === id) {
        found = true;
      } else {
        out.push(this.expanded[i]);
      }
    }
    if (!found) {
      out.push(id);
    }
    this.onExpandedChange(out);
  }

  private speakableText(item: TrajectoryItem): string {
    const who: string = item.speaker === Speaker.USER ? '我说' : '助手回复';
    // 读数用**去标记**的纯文本：否则屏幕阅读器会把 `**`、反引号、链接目标一起念出来
    const plain: string = plainTextOf(parseMarkdown(item.body));
    const head: string = plain.length > 60 ? `${plain.substring(0, 60)}…` : plain;
    return `${who}：${head}（共 ${plain.length} 字）`;
  }

  build() {
    Column({ space: Sp.M }) {
      this.turnBlock(this.turn)
    }
    .width('100%')
  }

  /**
   * 一个回合（§8 的渲染单位）：用户消息 → 过程分组 → 回答 → 通知。
   *
   * 顺序即阅读顺序，且**不做"智能排序"**：官方也是这个次序。
   */
  @Builder
  turnBlock(turn: Turn) {
    Column({ space: Sp.M }) {
      if (turn.user !== undefined) {
        this.trajectoryItem(turn.user)
      }
      /*
       * 【2026-09-17 用户决定：**工具调用全部单栏，不再分组折叠**】
       *
       * 此前这个过程是"一整组折成 `▸ 工具 3 · 其他 1` 一行，点开才看条目"。
       * 用户明确要求按官方来：**工具调用全部单栏**——即每条过程条目自己占一行
       * （思考/工具/子代理/进度各自一行），不再套一层分组壳。
       * 这与官方会话页的形态一致（官方的过程时间线就是一条条平铺，没有分组头）。
       *
       * 省空间的责任移交给了**每一条自己**：`ToolCard` / `ReasoningRow` 的折叠态都是一行，
       * 所以平铺之后竖向占用与"分组折叠"是一个量级，但可读性与官方一致。
       */
      ForEach(turn.process, (it: TrajectoryItem) => {
        this.trajectoryItem(it)
      }, (it: TrajectoryItem) => `proc-${it.id}`)
      // ArkTS 规定：`@Builder` 内只能写 UI 语法，循环必须用 `ForEach`
      ForEach(turn.answers, (it: TrajectoryItem) => {
        this.trajectoryItem(it)
      }, (it: TrajectoryItem) => `ans-${it.id}`)
      ForEach(turn.notices, (it: TrajectoryItem) => {
        this.trajectoryItem(it)
      }, (it: TrajectoryItem) => `note-${it.id}`)
      /*
       * 回合尾部：本回合**产出的文件**（P7-21）。
       *
       * 来源是成功的写类工具调用（`producedFilesOf` 的规则逐条对齐官方 `ui-deliverables`：
       * 不读回答正文、只算成功、首次出现顺序 + 去重）。0 个文件时整行不渲染（官方同）。
       */
      if (this.produced().length > 0) {
        ProducedFilesRow({
          files: this.produced(),
          onOpen: (path: string, name: string) => {
            this.onOpenProduced(path, name);
          }
        })
      }
    }
    .width('100%')
  }

  /** 本回合产出的文件（纯模型给结论；工具条目在过程分组里） */
  private produced(): ProducedFile[] {
    return producedFilesOf(this.turn.process);
  }

  /**
   * 过程分组（思考 / 工具 / 子代理 / 进度 / 交付物）。
   *
   * 折叠默认态由**模型**决定（`defaultExpanded`：进行中展开、已完成折叠），
   * 用户点开才覆盖——而不是"记着用户上次点过什么"当作初值。
   */
  /*
   * 【2026-09-17：`processGroup` 这个 Builder 已删除】用户要求"工具调用全部单栏"（与官方一致），
   * 于是过程条目直接平铺——见 `turnBlock` 里的 `ForEach(turn.process, …)`，
   * 不再有这一层分组壳。`processSummary` / `hasProcessGroup` 随之失去调用点，
   * 已从 import 里移除。`turn.running` 的"进行中"提示改由每条自己的状态呈现
   * （工具卡自带状态徽标）。
   */
  @Builder
  trajectoryItem(item: TrajectoryItem) {
    if (item.kind === TrajectoryKind.MESSAGE) {
      this.messageItem(item)
    } else if (item.kind === TrajectoryKind.REASONING) {
      // 思考块归 ReasoningRow（轨迹视图与过程分组**共用这一份**）
      ReasoningRow({
        item: item,
        expanded: this.isExpanded(item.id),
        onToggle: () => {
          this.toggle(item.id);
        }
      })
    } else if (item.kind === TrajectoryKind.TOOL) {
      // 工具卡归 ToolCard（右栏「工具」面板用**同一份**）
      ToolCard({
        item: item,
        expanded: this.isExpanded(item.id)
          || presentTool(item, toolStateLabel(item.toolState)).defaultExpanded,
        onToggle: () => {
          this.toggle(item.id);
        }
      })
    } else if (item.kind === TrajectoryKind.SUBAGENT) {
      // 子代理卡归 SubagentCard（右栏「子代理」面板用**同一份**）
      SubagentCard({ item: item })
    } else if (item.kind === TrajectoryKind.DELIVERABLE) {
      // 交付物卡归 DeliverableCard（右栏「交付物」面板用**同一份**）
      DeliverableCard({
        item: item,
        shareTarget: this.deliverableShareTarget(item),
        onShare: () => {
          this.onShareDeliverable(item);
        }
      })
    } else if (item.kind === TrajectoryKind.GOAL || item.kind === TrajectoryKind.JOB) {
      this.goalItem(item)
    } else if (item.kind === TrajectoryKind.COMMAND) {
      // 斜杠命令归 CommandRow（P7-13）：命令不是"谁说的话"，是一次操作 + 它的结局
      CommandRow({ item: item })
    } else if (item.kind === TrajectoryKind.ERROR && item.retryAttempt > 0) {
      // 模型请求的重试（P7-18）：单独一行，带"第几次/上限 + 倒计时 + 失败原因"
      RetryRow({ item: item })
    } else if (item.kind === TrajectoryKind.ERROR) {
      this.errorItem(item)
    }
  }

  /**
   * 一条消息（正文 + 行级交互）——**整行归 `MessageRow`**（P2-4）。
   *
   * 【为什么抽出去】这一段此前自己带着五份状态（悬停、菜单开关与归属、反馈面板归属与回执）
   * 加两个 `@Builder`（行内操作条、上下文菜单），与"过程流的分组与顺序"这件事混在一起；
   * 于是任何一处改动都要通读 1400 行。抽出去之后本组件只剩"哪一条放在哪一段"。
   *
   * 【留在父组件的两件事】① 「展开全部 / 收起全部」是**跨行**操作 ⇒ 展开集合的唯一真值在这里；
   * ② 菜单里给不给"重发 / 撤回评价"要读中枢的反馈记录 ⇒ 由这里算好动作清单传进去
   * （`messageActionsOf`）。这也是"判定与呈现分开"的既有规矩。
   */
  @Builder
  messageItem(item: TrajectoryItem) {
    MessageRow({
      item: item,
      sessionId: this.sessionId,
      /*
       * 正文里的文件提及（P9-3）：词汇表 = **本回合产出的文件**（与尾部那行 chip 同一份来源），
       * 打开动作复用同一条链路（`onOpenProduced`：读内容 + 切到能看见预览的页面）。
       * 认不出来的一律保持普通代码（官方："stays inert code"）。
       */
      mentionPath: (token: string) => resolveProducedMention(this.produced(), token),
      onOpenMention: (path: string) => {
        this.onOpenProduced(path, baseNameOf(path));
      },
      a11yText: this.speakableText(item),
      hasPointer: this.hasPointer,
      hasKeyboard: this.hasKeyboard,
      feedbackOpen: this.fbFor === item.id,
      feedbackNotice: this.fbNote,
      /*
       * 【F28④：提交要用**用户这次点的取向**，不是"已存行的取向"】
       *
       * 真机取证：点「有帮助」→ 面板打开 → 点「提交」，**一个请求都没发出去**。
       * 原因是这里传的是 `myRating(item.id)`（已存行的 rating，首评时恒为空串），
       * 而 `putFeedback()` 在 `rating.length === 0` 处直接 return（`feedback.incomplete`）——
       * 静默失败。用户点的那个取向由父组件记着（`onOpenFeedback(it.id, rating)` 的第二个参数），
       * 这里把它取回来交给面板，提交时就有值了。
       * 已存行仍要保留（面板初值要用它做预填），所以两个字段并存、用途不同。
       */
      activeRating: this.activeRatingOf(item.id),
      storedCategory: this.storedCategoryOf(item.id),
      storedNote: this.storedNoteOf(item.id),
      actions: this.messageActionsOf(item),
      onAction: (it: TrajectoryItem, id: string) => {
        this.onMessageAction(it, id);
      },
      onOpenFeedback: (it: TrajectoryItem, rating: string) => {
        // 打开反馈要记"哪条开着、什么取向" ⇒ 那两份状态在父组件
        // F28④：这里同时**就地**记下取向——提交要用它（父组件那份不保证在提交时还拿得到）
        this.fbRating = rating;
        this.onOpenFeedback(it.id, rating);
      },
      onSubmitFeedback: (it: TrajectoryItem, rating: string, category: string, note: string) => {
        this.submitFeedback(it, rating, category, note);
      },
      onCloseFeedback: () => {
        this.onCloseFeedback();
      }
    })
  }

  /** 打开反馈面板：带上该条当前的类别/说明，便于"改主意"而不是从零填 */
  /**
   * 该条**已存**的反馈类别 / 说明（反馈面板的初值）。
   *
   * 【为什么只取两段文字而不是整行】`FeedbackRow` 还带 `version` 等并发令牌字段，
   * 拼一个"假装没有版本"的行等于凭空造一个语义不完整的对象；面板只要这两段。
   */
  private storedCategoryOf(messageId: string): string {
    const row: FeedbackRow | undefined = SessionHub.shared().feedbackOf(messageId);
    return row === undefined ? '' : row.category;
  }

  private storedNoteOf(messageId: string): string {
    const row: FeedbackRow | undefined = SessionHub.shared().feedbackOf(messageId);
    return row === undefined ? '' : row.note;
  }

  /**
   * F28④：提交时用的取向——优先"用户这次点的"，退化到"已存行的"。
   *
   * 退化那一支是给"已评过、再打开面板改说明"的情形：那种情况下用户不会再点一次
   * 有帮助/没帮助，取向只能从已存行取。
   */
  private activeRatingOf(messageId: string): string {
    return this.fbRating.length > 0 ? this.fbRating : this.myRating(messageId);
  }

  private submitFeedback(item: TrajectoryItem, rating: string, category: string, note: string): void {
    SessionHub.shared().putFeedback(item.id, rating, note, category)
      .then((n: ActionNotice) => {
        this.onFeedbackNote(this.feedbackNoticeText(n));
        if (n.code === 'feedback.saved') {
          this.fbFor = '';
        }
      });
  }

  /** 该条消息**宿主记录的**评价（不是"我以为点了什么"） */
  private myRating(messageId: string): string {
    const row: FeedbackRow | undefined = SessionHub.shared().feedbackOf(messageId);
    return row === undefined ? '' : row.rating;
  }

  /**
   * 反馈回执 → 一句话。
   *
   * 【为什么不走 Index 的 noticeText】那是全局回执表，键来自各功能；反馈这几条要贴着面板显示，
   * 且**失败原因必须原样透出**（`friendlyFailure` 已把宿主错误码翻成人话）。
   */
  private feedbackNoticeText(n: ActionNotice): string {
    if (n.code === 'feedback.saved' || n.code === 'feedback.withdrawn') {
      return '';
    }
    if (n.code === 'feedback.failed') {
      return '评价未保存：' + n.params.reason;
    }
    if (n.code === 'feedback.no-version') {
      return '无法撤回：没读到该评价的版本（不猜版本号去删）。';
    }
    if (n.code === 'offline') {
      return '未连接：评价需要连上 Host 才能保存。';
    }
    if (n.code === 'feedback.needs-session') {
      return '这条消息还不属于任何会话，暂时存不了评价。';
    }
    return '';
  }

  @Builder
  goalItem(item: TrajectoryItem) {
    NativeCard({
      iconSymbol: item.kind === TrajectoryKind.GOAL
        ? $r('sys.symbol.checkmark_circle')
        : $r('sys.symbol.list_bullet'),
      title: item.title,
      badge: item.kind === TrajectoryKind.GOAL ? '目标' : '任务',
      tone: 'brand',
      summary: item.progress,
      progress: item.percent,
      a11y: `${item.kind === TrajectoryKind.GOAL ? '目标' : '任务'} ${item.title}`
    })
  }

  @Builder
  errorItem(item: TrajectoryItem) {
    Row({ space: Sp.S }) {
      Divider().vertical(true).color($r('sys.color.alert')).height('100%')
      Column({ space: 2 }) {
        Text('出错了')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.alert'))
          .width('100%')
        Text(item.body)
          .fontSize(Fs.SECONDARY)
          .width('100%')
          .textAlign(TextAlign.Start)
        /*
         * 【P7-18：删掉那个假的「重试」标签】
         * 它长得像按钮却**没有任何 onClick**（只有「查看诊断」接了动作）——
         * 用户点它没有任何反应，而本仓的规矩是"不放点了没反应的假入口"。
         * 真正要重发一条消息，走消息行自己的「重发」（那条路有真实协议面）；
         * 模型请求的自动重试由 Host 负责，界面上不该给一个假的"手动重试"。
         */
        Row({ space: Sp.L }) {
          Text('查看诊断')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              this.onOpenDetail();
            })
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .accessibilityText(`错误：${item.body}`)
  }

  /** 打开上下文菜单（长按/右键都走这里；手势集合来自输入策略） */
  /**
   * 一条消息的**动作清单**（操作条与上下文菜单**共用这一份**）。
   *
   * 【为什么必须是同一份】§10 要的是"统一消息操作"：同一条消息在行内操作条与
   * 长按菜单里必须是同样几项、同样顺序。写成两处必然漂移——一处加了"撤回"，另一处没有，
   * 而用户会在两个入口得到不同答案。
   */
  private messageActionsOf(item: TrajectoryItem): NativeAction[] {
    const out: NativeAction[] = [];
    out.push({ id: 'copy', label: '复制', a11y: '复制这条消息的正文' });
    /*
     * 【2026-09-17 口径更新：评价按钮**只在手机端隐藏**】
     *
     * 用户口径：**PC / 平板 / 2in1 与官方 1:1 复刻，手机端才做适应性优化**。
     * 官方是有评价入口的，所以"去掉有帮助/没帮助"这条**不能全形态生效**——
     * 手机上隐藏（动作条在窄屏里本来就挤），其他端原样给出来。
     *
     * `withdraw`（撤回评价）不用另加条件：它本来就在 `myRating().length > 0` 时才出现。
     */
    if (this.layoutMode !== 'single') {
      out.push({
        id: 'like',
        label: '有帮助',
        active: this.myRating(item.id) === 'positive',
        a11y: '评价为有帮助，可选择原因'
      });
      out.push({
        id: 'dislike',
        label: '没帮助',
        active: this.myRating(item.id) === 'negative',
        a11y: '评价为没帮助，可选择原因'
      });
    }
    out.push({ id: 'quote', label: '引用', a11y: '把这条消息引用到输入框' });
    if (item.speaker === Speaker.USER) {
      // 【为什么只给用户消息】"重发"对用户消息是**把同一句再发一次**（有真实协议面：
      // `session/prompt`）；对助手消息则是"重跑那一轮"，本仓没有对应端点 ⇒ 不给，避免假入口。
      out.push({ id: 'resend', label: '重发', a11y: '重新发送这条消息' });
    }
    // 已评才给"撤回"：没评就没有可撤的（按钮不该假装有事可做）
    if (this.myRating(item.id).length > 0) {
      out.push({ id: 'withdraw', label: '撤回评价', a11y: '撤回这条消息的反馈' });
    }
    return out;
  }

  /** 动作的统一处理（两个入口都走这里） */
  private onMessageAction(item: TrajectoryItem, id: string): void {
    if (id === 'copy') {
      this.onCopyMessage(userFacingBodyOf(item));
    } else if (id === 'like') {
      this.onOpenFeedback(item.id, 'positive');
    } else if (id === 'dislike') {
      this.onOpenFeedback(item.id, 'negative');
    } else if (id === 'quote') {
      this.onQuoteMessage(item);
    } else if (id === 'resend') {
      this.onResendMessage(item);
    } else if (id === 'withdraw') {
      SessionHub.shared().clearFeedback(item.id).then((n: ActionNotice) => {
        this.onFeedbackNote(this.feedbackNoticeText(n));
      });
    }
  }
}
