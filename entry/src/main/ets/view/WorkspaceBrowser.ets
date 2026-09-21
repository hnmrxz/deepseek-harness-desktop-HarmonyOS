/**
 * 工作区浏览器（`workspaceHub` + `workspaceGroup`）—— P1：Sidebar 信息架构的**第一块**。
 *
 * ## 这一块是什么
 *
 * 官方 `dsh-client-ui-workspace` 是 **Sidebar 里的「工作区→会话」浏览器**：工作区为组、
 * 会话挂在组下（`docs/parity-matrix.md` 的 `sidebar` 行）。本仓原先这段树长在**主区**里
 * （`TabContentView` 的 `workspaceHub`/`workspaceGroup`，285 行），与 Sidebar 是两处；
 * 抽成独立组件之后，它既是主区那个页签的内容，也**可以原样挂进侧栏**——
 * 搬迁动作因而只剩"换个挂载点"，不需要再动树本身。
 *
 * 【为什么这次一行都不用改名】它本来就只经 `this.f.<成员>` 访问宿主 —— 新门面就是那些成员的**子集**
 * （30 个，名字与形状逐条从 `TabContentFacade` 抄来）。这与前三束（要批量改名 + 造 setter）不同：
 * 门面做到位之后，搬迁成本会一路下降。
 *
 * 【`compact` 为什么是入参】"紧凑"取决于**挂载它的那条轨道有多宽**，不是组件的属性：
 * 主区里由 `TabContentView` 给，将来挂进侧栏时由侧栏给（同一个组件，两种宽度）。
 */

import { HubBanner } from './HubBanner';
import { PendingPane } from './PendingPane';
import { SessionSearch } from './SessionSearch';
import { PendingAnswerDraft, PendingAnswerDrafts, CoreViewState, Fs, HarmonyIconSize, HubPhase, PendingItem, Radius, RunMode, isSubagentSession, sessionDisplayTitle, SessionListItem, SessionSearchRow, Sp, Sz, WorkspaceItem, formatClock, relativeTime, sessionEmptyCopy } from 'appstate';

export interface WorkspaceBrowserFacade {
  answerPending: (item: PendingItem, drafts: PendingAnswerDraft[]) => void;
  /** 放弃整组提问（官方 nav.cancel） */
  cancelQuestion: (item: PendingItem) => void;
  /**
   * 待决答复草稿（**宿主所有**，FR-013）。
   *
   * 【为什么门面里也有一份】本组件也挂着一个 `PendingPane`（"待你决定"区块，宽/窄两版共用），
   * 而草稿的真值只有一个（`Index.pendingAnswerDrafts`）——两处入口必须读同一份，
   * 否则从抽屉进来与从会话里进来会看到两套半截答案。
   */
  pendingAnswerDrafts: PendingAnswerDrafts;
  /** 逐题草稿变化（回传宿主保存） */
  onPendingAnswerGroup: (itemId: string, drafts: PendingAnswerDraft[]) => void;
  archiveOpen: boolean;
  archivedSessionIds: string[];
  archivedSessions: () => SessionListItem[];
  /** 归档一个会话（副作用与失败文案留在宿主：宽版与窄版共用） */
  archiveSession: (id: string) => void;
  /** 删除登记的两步确认（判定与提示文案归宿主，宽窄两版共用） */
  toggleDeleteConfirm: (w: WorkspaceItem) => void;
  confirmingDeletePath: string;
  connectBusy: boolean;
  connectSettled: boolean;
  coreView: CoreViewState;
  createSessionIn: (w: WorkspaceItem) => void;
  decidePending: (item: PendingItem, choiceId: string, reason: string) => void;
  hubAuthority: string;
  hubError: string;
  hubPhase: HubPhase;
  hubStreams: number;
  hubTraceTail: () => string[];
  openDiagnostics: () => void;
  openFolderPicker: () => void;
  /**
   * 打开设置（抽屉标题行那颗 Settings 钮，对照 `ChatListDrawer.kt` 的 `onOpenSettings`）。
   *
   * 【为什么是可选的】设置入口是**手机壳（DrawerNav 抽屉）**独有的：桌面形态的原生
   * 设置页不在渲染树上（`WebShell.desktopSurface` 只有 Web / 连接页 / 诊断页三支）。
   * 做成可选字段，其它装配点（不画抽屉标题行的挂载方）就不必伪造一个通道。
   */
  onOpenSettings?: () => void;
  openSession: (id: string) => void;
  openWorkspaceFiles: (w: WorkspaceItem) => void;
  pending: PendingItem[];
  registryIdOf: (w: WorkspaceItem) => string;
  selectedSessionId: string;
  sessionsOf: (w: WorkspaceItem) => SessionListItem[];
  setArchiveOpen: (value: boolean) => void;
  workspaces: WorkspaceItem[];
  /*
   * 会话搜索（P7-1，对齐官方 sidebar 的 search）：结果与降级说明由中枢给
   * （Host 的**内容命中**只有中枢拿得到）；查询经回调交回中枢。
   */
  sessionSearchRows: SessionSearchRow[];
  sessionSearchNote: string;
  onSearchSessions: (query: string) => void;
  /** §FR-060：当前运行模式 */
  runMode: RunMode;
}

@Component
export struct WorkspaceBrowser {

  /** 门面（**每次渲染重建**，同 `MainShell`/`AppShell`） */

  @Prop f: WorkspaceBrowserFacade;
  /** 是否紧凑（由挂载方按轨道宽度给） */

  @Prop compact: boolean = false;

  /** 搜索关键词（**视图自己的状态**：只影响这一页显示；结果由中枢给） */
  @State query: string = '';
  /** §FR-043：折叠的工作区路径集合（视图状态，与中枢无关） */
  @State collapsedGroups: string[] = [];

  /**
   * 搜索结果区（官方 `dsh-client-ui-workspace` 的形态：**扁平的行**，不是树）。
   *
   * 【T023 收尾：已搬走】这段行结构（标题 + 工作区上下文 + 内容片段）此前在这里
   * 与 `ConversationPane` 各写一遍，现在收口到 `SessionSearch` 组件（对照
   * `dshmobile/.../SessionSearch.kt`）——组件版多出的两处是**补全**：
   * ① 上限提示（命中数达 `SESSION_SEARCH_LIMIT` 时说明"列表装不下了"，
   * 对应源码 `SearchResultSet.hasMore`）；② 空查询时不再渲染退化说明。
   * 宿主侧的调用点在下面 `workspaceHub()` 里（`SessionSearch({...})`）。
   */

  @Builder
  workspaceHub(compact: boolean) {
    Column({ space: Sp.S }) {
      // 连接状态条（E111）：**先区分"正在连"与"连不上"**。
      // 启动时要等本机核心就绪（几十秒），这段时间中枢的 lastError 可能带着中间态文本；
      // 无条件渲染它，用户就会看到「无法连接核心」闪一下——那是假报错。
      if (this.f.connectBusy || !this.f.connectSettled) {
        Text($r('app.string.connecting_local_core'))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding(Sp.S)
          .borderRadius(Radius.S)
          .backgroundColor($r('sys.color.background_secondary'))
      /*
       * §FR-037/060：断连横幅的可见性。除了「有错误文本」（本机/远程连接失败的
       * 通常路径），远程 DEGRADED 还有一条**只降级、不写错误文本**的路径
       * （socket 中断 → 传输层转入自动重试）。此时横幅由「运行模式 + 阶段 +
       * 连接已定型（connectSettled：避开启动期中间态，见上面 E111 的说明）」
       * 三元组兜住，文案由 HubBanner 按 runMode 区分（远程 = 自动重试 + 缓存可浏览）。
       */
      } else if (this.f.hubError.length > 0
        || (this.f.runMode === RunMode.REMOTE
        && this.f.hubPhase === HubPhase.DEGRADED
        && this.f.connectSettled)) {
        HubBanner({
          errorText: this.f.hubError, authority: this.f.hubAuthority, phase: this.f.hubPhase,
          streams: this.f.hubStreams, traceTail: this.f.hubTraceTail(),
          runMode: this.f.runMode,
          onOpenDiagnostics: () => {
            this.f.openDiagnostics();
          }
        })
      }

      Row({ space: 4 }) {
        /*
         * E163（用户反馈①）：**顶层不再放「新建会话」**。
         * 用户原话："新建会话应当在工作区文件夹上点击，而不是处在顶层外围，不然不知是给哪个工作区加会话。"
         * 现在入口在每个工作区组头（见 `workspaceGroup`），建会话时会把该工作区注册成目标 ⇒
         * "给哪个工作区加会话"从"猜"变成"看得见"。
         */
        Text('选择工作区后，在其组头点「+ 会话」')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      .height(Sz.TOUCH_MIN)
      Blank()
      Text($r('app.string.action_choose_folder'))
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.brand'))
        .onClick(() => {
          this.f.openFolderPicker();
        })
      .width('100%')
      .height(Sz.TOUCH_MIN)

      /*
       * 会话搜索（P7-1）。放在会话区域的正上方：官方 sidebar 的搜索也贴着会话列表。
       *
       * T023 收尾：这里此前是**内联**渲染（输入框 + 一个 `searchResults()` 私有 Builder
       * 再画一遍命中行），与 `ConversationPane` 的同名区块重复。现在换成 `SessionSearch`
       * 组件（对照 `SessionSearch.kt`：命中行三段、上限提示、退化说明收口在一处）。
       *
       * 【语义保持】查询词仍是本组件的 `query`，结果仍是门面的 `sessionSearchRows` /
       * `sessionSearchNote`（Host 的**内容命中**只有中枢拿得到），查询仍交回
       * `f.onSearchSessions`，命中仍走 `f.openSession`。
       * 【可见性口径不变】内联版把整个结果区挂在 `query` 非空之下，所以这里同样把
       * `rows` / `note` 在查询为空时收成空——否则退化说明（如"Host 不支持内容搜索"）
       * 会在用户还没搜之前就占着版面。
       */
      SessionSearch({
        query: this.query,
        rows: this.query.trim().length > 0 ? this.f.sessionSearchRows : [],
        note: this.query.trim().length > 0 ? this.f.sessionSearchNote : '',
        closable: this.query.trim().length > 0,
        placeholder: '搜索会话（标题或内容）',
        onQuery: (value: string) => {
          this.query = value;
          this.f.onSearchSessions(value);
        },
        onOpenHit: (sessionId: string) => {
          this.f.openSession(sessionId);
        },
        onClose: () => {
          this.query = '';
          this.f.onSearchSessions('');
        }
      })
      .width('100%')

      if (this.f.pending.length > 0) {
        Column({ space: Sp.XS }) {
          Text(`待你决定 · ${this.f.pending.length}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.warning'))
            .width('100%')
          PendingPane({
            items: this.f.pending,
            // T-C：答复草稿从宿主来、经宿主回（见门面字段的说明）
            answerDrafts: this.f.pendingAnswerDrafts,
            onAnswerGroupChange: (itemId: string, drafts: PendingAnswerDraft[]) => {
              this.f.onPendingAnswerGroup(itemId, drafts);
            },
            onDecide: (item: PendingItem, choiceId: string, reason: string) => {
              this.f.decidePending(item, choiceId, reason);
            },
            onAnswer: (item: PendingItem, drafts: PendingAnswerDraft[]) => {
              this.f.answerPending(item, drafts);
            },
            onCancelQuestion: (item: PendingItem) => {
              this.f.cancelQuestion(item);
            }
          })
        }
        .width('100%')
        /*
         * 【F18：同样从 constraintSize(maxHeight) 改成确定高度】
         *
         * 真机读数（**算得出来的边界**）：卡片顶 `[42,935]`，容器下沿 = 1026 + 320vp×3.5 = **2146px**，
         * 而动作行 `放弃整组问题/跳过本题/提交` 在 **2381px** ⇒ 整行落在裁切线之外，
         * 屏幕上不可见、点不到，**而且滑动无效**（与 F12 同一个机理：上限不是高度，
         * 内层 `List` 拿不到视口高度就不会滚）。
         *
         * 这里给 240vp（固定 vp，不用百分比——百分比要先有确定高度的父容器，而"父容器高度不定"
         * 正是这条缺陷的机理）：三类卡片（审批/单题/多题）都装得下，
         * 也给下面的工作区树留下可滚动的高度。
         */
        .height(240)
      }

      /*
       * E134：归档列表（官方语义：注册表全局归档集）。
       *
       * 【为什么是只读】线协议只给了 `workspace/archiveSession`，**没有反向端点**——
       * 所以这里列出它们、可以点开看，但不提供"恢复"（那会是个点不动的按钮）。
       * 归档集为空时整段不出现，不占版面。
       */
      if (this.f.archivedSessionIds.length > 0) {
        /*
         * E165：归档**默认折叠**（反馈②）。这一行是入口；点开才列出已归档会话。
         * 说明文字写清语义，避免"归档了为什么还在这里"的误解。
         */
        Row({ space: Sp.S }) {
          /*
           * 【F5：**不要**把 `$r()` 拼进模板串】
           *
           * 真机读数：这一行渲染成字面量 `[object Object] · 4`。原因很直接——
           * `$r()` 返回的是 **Resource 对象**，模板串会调它的 `toString()`，
           * 整行于是变成"对象转字符串"的结果。`Text($r(...))` 单独用**没问题**
           * （ArkUI 认得 Resource），出事的只有"拼进字符串"这一种写法。
           *
           * 处置：拆成两个 `Text`——两个都是"单独用 Resource / 单独用数字"，
           * 走的是 ArkUI 认识的路径。**不去找 `localized()` 之类的旁路**：
           * 本组件本来就没有那个依赖，为了拼一句话引进一条资源读取链路并不划算。
           */
          Text($r('app.string.section_archive'))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
          Text(`· ${this.f.archivedSessionIds.length}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .layoutWeight(1)
          Text(this.f.archiveOpen ? '收起' : '展开')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
        }
        .width('100%')
        .padding(Sp.M)
        .borderRadius(Radius.S)
        .backgroundColor($r('sys.color.background_secondary'))
        .onClick(() => {
          this.f.setArchiveOpen(!this.f.archiveOpen);
        })

        if (this.f.archiveOpen) {
        Column({ space: Sp.XS }) {
          // F5：同样拆开——`$r()` 不能拼进模板串（理由见上面那一处）
          Row({ space: Sp.S }) {
            Text($r('app.string.section_archive'))
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
            Text(`· ${this.f.archivedSessionIds.length}`)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          ForEach(this.f.archivedSessions(), (s: SessionListItem) => {
            Row({ space: Sp.S }) {
              SymbolGlyph($r('sys.symbol.archivebox')).fontSize(HarmonyIconSize.STATUS)
                .fontColor([$r('sys.color.font_secondary')])
              Text(this.sessionTitleOf(s))
                .fontSize(Fs.SECONDARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(formatClock(s.updatedAt))
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .width('100%')
            .padding(Sp.M)
            .borderRadius(Radius.S)
            .backgroundColor($r('sys.color.background_primary'))
            .onClick(() => {
              this.f.openSession(s.id);
            })
          }, (s: SessionListItem) => s.id)
        }
        .width('100%')
        .padding(Sp.M)
        .borderRadius(Radius.M)
        .backgroundColor($r('sys.color.background_secondary'))
        }
      }

      /*
       * 搜索时**不画树**（官方语义：搜索把"会话区"换成扁平结果列表）。
       *
       * 【为什么用 visibility 而不是把整段挪进 if】树这一段的根节点带着 `layoutWeight(1)`
       * 与列表滚动状态，把它整段包进条件分支要重排上百行（风险远大于收益）。
       * `Visibility.None` 既不可见也不占位 ⇒ 视觉效果与"不渲染"一致。
       * 空白态与树一起隐藏：搜索期间用户要的是结果，不是"还没有工作区"的引导。
       */
      Column() {
      if (this.f.workspaces.length === 0) {
        // 空态按核心阶段分档（D7 §3 第 7 项）：把"看不到会话"引向正确的排查方向
        Column({ space: Sp.S }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(36)   // token-exempt: 空态大图标，仅此一处，不属于排版层级
            .fontColor([$r('sys.color.font_tertiary')])
          Text(sessionEmptyCopy(this.f.coreView.phase).title)
            .fontSize(Fs.BODY)
            .fontColor($r('sys.color.font_secondary'))
          Text(sessionEmptyCopy(this.f.coreView.phase).hint)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: this.compact ? Sp.XS : Sp.M }) {
          ForEach(this.f.workspaces, (w: WorkspaceItem) => {
            ListItem() {
              // 宽窄之别只在这里：树本身（工作区分组、会话归属）两种宽度完全一样
              if (this.compact) {
                this.narrowGroup(w)
              } else {
                this.workspaceGroup(w)
              }
            }
          }, (w: WorkspaceItem) => w.path)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      }
      .width('100%')
      .layoutWeight(1)
      .visibility(this.query.trim().length > 0 ? Visibility.None : Visibility.Visible)
    }
    .width('100%')
    .height('100%')
    .padding(Sp.M)
  }

  @Builder
  workspaceGroup(w: WorkspaceItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        // §FR-043：折叠/展开指示器
        SymbolGlyph(this.isGroupCollapsed(w.path)
          ? $r('sys.symbol.chevron_right')
          : $r('sys.symbol.chevron_down'))
          .fontSize(HarmonyIconSize.STATUS)
          .fontColor([$r('sys.color.font_tertiary')])
        SymbolGlyph($r('sys.symbol.folder')).fontSize(HarmonyIconSize.STATUS)
          .fontColor([w.primary ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
        Column({ space: 2 }) {
          Text(w.name.length > 0 ? w.name : w.path)
            .fontSize(Fs.BODY)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${w.path} · ${w.sessionCount} 会话`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        // E163：**在该工作区里建会话**（反馈①：入口挂在工作区上，用户看得见"给谁加"）
        Text('+ 会话')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.f.createSessionIn(w);
          })
        Text($r('app.string.action_files'))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.f.openWorkspaceFiles(w);
          })
        /*
         * E132：删除工作区（只删**注册**，不删目录）。
         *
         * 【为什么要两步确认】它虽然不动磁盘文件，但会让"这个目录在这里出现过、以及它下面
         * 那些会话的归属"消失——一次误触的代价不小，而 ArkUI 的 Row 里塞不下一个说得清楚的
         * 确认弹窗。所以同一位置先变成「确认删除 / 取消」，用户看清了再按。
         * 【为什么有时不显示】删除需要**注册表 id**；列表里的工作区是由会话 cwd 归并出来的，
         * 只有注册表里登记过的才有 id。没有 id 就**不显示**这个入口（而不是给一个点了没反应的）。
         */
        if (this.f.registryIdOf(w).length > 0) {
          Text(this.f.confirmingDeletePath === w.path
            ? $r('app.string.action_delete_confirm')
            : $r('app.string.action_delete'))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.alert'))
            .onClick(() => {
              this.f.toggleDeleteConfirm(w);
            })
        }
      }
      .width('100%')
      // §FR-043：点击分组标题折叠/展开会话列表
      .onClick(() => {
        this.toggleGroupCollapse(w.path);
      })

      if (!this.isGroupCollapsed(w.path)) {
        ForEach(this.f.sessionsOf(w), (s: SessionListItem) => {
          this.sessionRow(s)
        }, (s: SessionListItem) => s.id)
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  /* ───────────────── 窄版（挂进侧栏时用） ─────────────────
   *
   * 【为什么必须有窄版】侧栏 PANEL 轨道只有 `Sz.NAV_PANEL`（240vp）。宽版把 `+ 会话` / `文件` /
   * `删除` 三个**文字**入口与「路径 · 会话数」挤在名字右侧 ⇒ 240vp 下名字只剩几个字。
   * 窄版的做法是**改行不改树**：
   *   · 第 1 行：图标 + 名字（拿满宽度）+ 会话数；
   *   · 第 2 行：三个动作，各自给足触控高度；
   *   · 会话行与宽版**共用** `sessionRow`（240vp 本来就放得下）。
   *   · 删掉「路径 · 会话数」副标题行里的路径（240vp 下路径会被截成无意义的片段；
   *     路径本身在"浏览文件"视图里完整可见）。
   *
   * 【为什么动作不藏进 `⋯` 菜单】官方 Web 侧栏是"悬停才显出图标按钮"，但那需要一个**能验证**的
   * 悬停/菜单态；本仓当前做不了真机验收（D3 签名阻塞）。而「新建会话 / 浏览文件 / 删除登记」在窄版里
   * 只有这一个入口——菜单一旦在真机上打不开，功能就不可达。宁可先用两行把它们摆在明处，
   * 等能真机验收再谈收进菜单（**不预留"以后会收"的空壳**）。
   */

  /**
   * 会话行（宽版与窄版**共用同一份**：240vp 下这一行本来就放得下——
   * 名字 + 运行中 + 归档，不需要为窄版再写一遍）。
   */
  /**
   * 会话在列表里的标题（F23）：纯模型判"有没有名字"，这里只负责回落同一句文案。
   *
   * 用资源串 `label_unnamed_session` 而不是模型里那个常量：本组件已经有这条资源
   * （三处文案都用它），再引一个常量反而多一条口径。
   */
  private sessionTitleOf(s: SessionListItem): ResourceStr {
    const title: string = sessionDisplayTitle(s);
    return title.length > 0 ? title : $r('app.string.label_unnamed_session');
  }

  /** §FR-043：判断工作区分组是否折叠 */
  private isGroupCollapsed(path: string): boolean {
    for (let i = 0; i < this.collapsedGroups.length; i++) {
      if (this.collapsedGroups[i] === path) {
        return true;
      }
    }
    return false;
  }

  /** §FR-043：切换工作区分组折叠/展开 */
  private toggleGroupCollapse(path: string): void {
    const out: string[] = [];
    let found: boolean = false;
    for (let i = 0; i < this.collapsedGroups.length; i++) {
      if (this.collapsedGroups[i] === path) {
        found = true;
      } else {
        out.push(this.collapsedGroups[i]);
      }
    }
    if (!found) {
      out.push(path);
    }
    this.collapsedGroups = out;
  }

  @Builder
  sessionRow(s: SessionListItem) {        Column({ space: 2 }) {
          Row({ space: Sp.S }) {
            /*
             * F23：标题取 `sessionDisplayTitle()` 的结论——它把"还没有标题"的会话
             * （`blank` 且标题恰好等于 cwd 末段）判成空串，于是这里回落成与 `@` 候选
             * **同一句**「未命名会话」（F15 也是这一句）。判据在纯模型里，视图不自己写。
             */
            Text(this.sessionTitleOf(s))
              .fontSize(Fs.SECONDARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (s.running) {
              Text($r('app.string.status_running'))
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.brand'))
            }
            /*
             * 【F2：子代理会话要**在列表上就看得出来**】
             *
             * 真机读数：子代理会话和普通会话混在同一棵树里，名字看着一样，
             * 点开却是一条**永远读不出轨迹**的会话（宿主回
             * `session/agent-busy … require their durable parent address`）。
             * 用户看到的是"点开一片空白"，而且点几次都这样——因为界面上没有任何线索
             * 告诉他"这条不是能直接打开的会话"。
             *
             * 这里只做**如实标注**（一个徽标），不假装能打开它：
             * 打开子代理会话要带父级地址，那条通路本仓还没有。
             * 标注之后，"点开空白"至少变成"事前就知道为什么"。
             */
            if (isSubagentSession(s)) {
              Text($r('app.string.badge_subagent'))
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
            }
            /*
             * E134：归档会话（官方语义是"注册表全局归档集"）。
             * 【为什么没有"取消归档"】线协议里只有 `workspace/archiveSession`，
             * **没有反向端点**——所以这里只提供归档，不造一个点不动的"恢复"。
             */
            Text($r('app.string.action_archive'))
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .onClick(() => {
                this.f.archiveSession(s.id);
              })
          }
          .width('100%')
          Text(s.blank ? $r('app.string.status_not_started')
            : `${relativeTime(s.updatedAt, Date.now())} · ${formatClock(s.updatedAt)}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .maxLines(1)
        }
        .width('100%')
        .padding({ left: Sp.L, right: Sp.M, top: Sp.S, bottom: Sp.S })
        .borderRadius(Radius.S)
        .backgroundColor(this.f.selectedSessionId === s.id
          ? $r('sys.color.background_secondary')
          : $r('sys.color.background_primary'))
        .onClick(() => {
          this.f.openSession(s.id);
        })
  }

  @Builder
  narrowGroup(w: WorkspaceItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        // §FR-043：折叠/展开指示器
        SymbolGlyph(this.isGroupCollapsed(w.path)
          ? $r('sys.symbol.chevron_right')
          : $r('sys.symbol.chevron_down'))
          .fontSize(HarmonyIconSize.STATUS)
          .fontColor([$r('sys.color.font_tertiary')])
        SymbolGlyph($r('sys.symbol.folder')).fontSize(HarmonyIconSize.STATUS)
          .fontColor([w.primary ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
        Text(w.name.length > 0 ? w.name : w.path)
          .fontSize(Fs.BODY)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`${w.sessionCount} 会话`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
      // §FR-043：点击分组标题折叠/展开会话列表
      .onClick(() => {
        this.toggleGroupCollapse(w.path);
      })

      if (!this.isGroupCollapsed(w.path)) {
        Row({ space: Sp.M }) {
          Text('+ 会话')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .height(Sz.TOUCH_MIN)
            .onClick(() => {
              this.f.createSessionIn(w);
            })
          Text($r('app.string.action_files'))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .height(Sz.TOUCH_MIN)
            .onClick(() => {
              this.f.openWorkspaceFiles(w);
            })
          /*
           * E132：删除工作区（只删**注册**，不删目录）+ 两步确认。
           * 判定与提示文案归宿主（`toggleDeleteConfirm`）——宽窄两版共用同一处，避免写两遍。
           */
          if (this.f.registryIdOf(w).length > 0) {
            Text(this.f.confirmingDeletePath === w.path
              ? $r('app.string.action_delete_confirm')
              : $r('app.string.action_delete'))
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.alert'))
              .height(Sz.TOUCH_MIN)
              .onClick(() => {
                this.f.toggleDeleteConfirm(w);
              })
          }
        }
        .width('100%')

        ForEach(this.f.sessionsOf(w), (s: SessionListItem) => {
          this.sessionRow(s)
        }, (s: SessionListItem) => s.id)
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
  }


  build() {
    this.workspaceHub(this.compact)
  }
}
