/**
 * 标签页内容（工作区 / 设置 / 核心）—— P0：主区内容搬迁的**第一束**。
 *
 * 本束 = `@Builder tabContent` + 它调用的 `@Builder workspaceHub` / `workspaceGroup`（277 行）。
 *
 * ## 门面为什么带 setter（本轮实测出来的）
 *
 * 搬走的代码**会写宿主状态**（共 17 个：attachNotice, connectAddress, connectAdvice, connectBusy, connectOk …）。
 * 若门面里它们只是普通属性，赋值会写进**门面副本**、宿主收不到 ——
 * **这不是编译错误，而是静默行为错误**（界面看着正常、状态没变）。
 * 故被写成员在门面里成对出现：只读属性 + `setX(v)`，搬走代码里的赋值已改写成 setter 调用（33 处）。
 *
 * 其余成员：只读值给快照、方法给闭包；门面由宿主**每次渲染重建**（缓存它等于放弃"中枢变了界面跟着变"）。
 *
 * 【为什么用门面】把父组件的 `@Builder` 注入子组件再调用会在真机 JS 崩溃（本仓 E118 实测）
 * ⇒ 内容只能靠数据/回调传。本束里唯一被调用的别的 builder 是 `hubBanner`，
 * 而它**已经是组件 `HubBanner`**，故这里直接渲染组件。
 */

import { ActionNotice, COMMAND_PICK_DRAFT, CommandCandidate, DiagEntry, DiagMode, DiagReport, Fs, HostRecord, HubPhase, MAIN_CONNECT, MAIN_CONVERSATION, ModelOption, ModelSelection, PanelRegistry, PendingAttachment, PendingItem, Radius, ReferenceCandidate, ScrollSpot, SessionHub, SessionJob, ShareTarget, Sp, StackPage, TrajectoryItem, commandDraftText, commandInputNotice, commandPickAction, diagHintOf, diagTitleOf, filterDiagEntries, openSettings } from 'appstate';
import hilog from '@ohos.hilog';
import { CommandList } from '../CommandList';
import { ConnectPane } from '../ConnectPane';
import { ConversationPane } from '../ConversationPane';
import { DiagnosticsPane } from '../DiagnosticsPane';
import { GoalBar } from '../GoalBar';
import { SessionModelPicker } from '../SessionModelPicker';
import { copyText } from 'platform';
import type { PendingAnswerDraft, HubSnapshot, InputModality, NavigationState, SessionStatsInput } from 'appstate';
import { TabContentView } from '../TabContentView';
import { extractToken } from 'connection';
import type { TabContentFacade } from '../TabContentView';

export interface MainShellFacade {
  TAG: string;
  DOMAIN: number;
  composeHostUrl: (address: string, token: string) => string;
  storageBaseUrl: (url: string) => string;
  reportConnectedHost: (baseUrl: string, token: string) => void;
  activePanel: () => string;
  answerPending: (item: PendingItem, drafts: PendingAnswerDraft[]) => void;
  /** 放弃整组提问（官方 nav.cancel） */
  cancelQuestion: (item: PendingItem) => void;
  attachNotice: string;
  setAttachNotice: (value: string) => void;
  attachments: PendingAttachment[];
  commands: CommandCandidate[];
  connectAddress: string;
  setConnectAddress: (value: string) => void;
  connectAdvice: string;
  setConnectAdvice: (value: string) => void;
  connectBusy: boolean;
  setConnectBusy: (value: boolean) => void;
  connectOk: boolean;
  setConnectOk: (value: boolean) => void;
  connectResult: string;
  setConnectResult: (value: string) => void;
  connectToken: string;
  setConnectToken: (value: string) => void;
  decidePending: (item: PendingItem, choiceId: string, reason: string) => void;
  detailOverlayOpen: boolean;
  setDetailOverlayOpen: (value: boolean) => void;
  diag: DiagReport;
  diagMode: () => DiagMode;
  diagRunning: boolean;
  draft: string;
  setDraft: (value: string) => void;
  /** 上次离开会话时的滚动位置（P9-6；由宿主保管，见 `Index.scrollSpot`） */
  scrollSpot: ScrollSpot;
  /** 一条交付物的分享目标（P9-7，纯模型判档；宿主补会话工作目录与沙箱根） */
  deliverableShareTarget: (item: TrajectoryItem) => ShareTarget;
  /** 拉起系统分享面板分享这条交付物 */
  onShareDeliverable: (item: TrajectoryItem) => void;
  /** 记下离开时的位置（`sessionId` + 顶部下标 + 当时是否贴底跟随） */
  onRememberSpot: (sessionId: string, top: number, following: boolean) => void;
  exportDiagnostics: () => void;
  hosts: HostRecord[];
  hubAuthority: string;
  hubConnected: boolean;
  hubError: string;
  hubPhase: HubPhase;
  hubStreams: number;
  hubTraceTail: () => string[];
  modality: InputModality;
  modalityEntry: () => DiagEntry;
  models: ModelOption[];
  /** 后台任务（官方会话头的任务条）；判定全在 `appstate/model/Jobs`，视图只画 */
  jobs: SessionJob[];
  nav: NavigationState;
  setNav: (value: NavigationState) => void;
  noticeText: (n: ActionNotice) => string;
  offline: boolean;
  openDiagnostics: () => void;
  openPoc: () => void;
  paletteOpen: boolean;
  setPaletteOpen: (value: boolean) => void;
  panelRegistry: PanelRegistry;
  pending: PendingItem[];
  permissionCurrent: string;
  /** 权限 chip 的显示文案（宿主用 `permissionChipLabel` 算好） */
  permissionLabel: string;
  /** 这台 Host 能不能切权限 */
  permissionSwitchableNow: boolean;
  /** 不能切时的原因（无障碍文案） */
  permissionHint: string;
  /** 点权限 chip（宿主开单选浮层 → `/permission <id>`） */
  onPickPermission: () => void;
  pickAndAttach: () => Promise<void>;
  /** 加一张图片（P0-4：图库 → **内联**发送，不走上传） */
  pickAndAttachImage: () => Promise<void>;
  /** 打开一枚产出文件（P7-21）：读内容 + 切到能看见预览的页面 */
  openProducedFile: (path: string, name: string) => void;
  planActive: boolean;
  planPending: boolean;
  queuedCount: number;
  quoteIntoDraft: (item: TrajectoryItem) => void;
  references: ReferenceCandidate[];
  resendMessage: (item: TrajectoryItem) => void;
  runDiagnostics: () => Promise<void>;
  running: boolean;
  setRunning: (value: boolean) => void;
  searchOpen: boolean;
  setSearchOpen: (value: boolean) => void;
  selectedSessionId: string;
  /** 会话头上下文行的工作区名（从选中会话的 cwd 派生；空 = 不知道，不显示） */
  sessionWorkspaceName: string;
  /** 品牌名（宿主给的事实；空会话空态里居中显示，对应官方新会话页的品牌区） */
  appName: string;
  /** 选中会话的最近活动时间（毫秒；0 = 不知道 ⇒ 不显示「多久没动」） */
  sessionUpdatedAt: number;
  selection: ModelSelection;
  sendDraft: () => void;
  sessionStats: SessionStatsInput;
  settingWriteNote: string;
  /** 这条设置写入回执属于哪个分区（E347；空串 = 判不出来） */
  settingWriteDomain: string;
  setSettingWriteNote: (value: string) => void;
  stackPage: StackPage;
  /** 「退回一层」（P8-1）：与系统返回键共用同一个执行点（见 `AppShellFacade.backOneLayer`） */
  backOneLayer: () => void;
  statsLine: string;
  /**
   * 主区**剩下三类面板**（工作区 / 设置 / 核心）的门面——交给 `TabContentView` 渲染。
   *
   * 本组件自己分派「诊断 / 连接 / 会话」，其余落进兜底分支由这一束接管（见 `mainContent` 的 else，E343）。
   * 曾经它是**零消费者**（本组件根本没用过，只有宿主在造）；E343 修完后它才真正被用上。
   */
  tabFacade: TabContentFacade;
  togglePlan: () => void;
  traceEnabled: boolean;
  setTraceEnabled: (value: boolean) => void;
  traceLines: string[];
  setTraceLines: (value: string[]) => void;
  trajectoryItems: TrajectoryItem[];
}

@Component
export struct MainShell {
  @Prop f: MainShellFacade;
  /** 是否紧凑（单栏/双栏下少留白）——由宿主给，组件不自己判定形态 */
  @Prop compact: boolean = false;
  /**
   * 当前档位（`Index` 发布到 AppStorage）。
   *
   * 本组件只用它决定统计行**贴顶还是沉底**——与 `Composer` / `MessageRow` /
   * `ConversationHeader` 用的是**同一个**来源，不在这里另立一套"单栏"判断
   * （另立一套正是"同一件事两套口径"的起点，本仓已经因此吃过 F15/F23）。
   */
  @StorageProp('dshLayoutMode') layoutMode: string = 'single';

  @Builder
  mainContent(compact: boolean) {
    // E190：命令面板（列表来自宿主：CommandCandidate 的 name/args/detail；选中即执行）
    if (this.f.paletteOpen) {
      Column({ space: Sp.XS }) {
        Row({ space: Sp.S }) {
          Text('命令面板')
            .fontSize(Fs.BODY)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              this.f.setPaletteOpen(false);
            })
        }
        .width('100%')
        // 长期目标栏归 GoalBar 所有（官方 ui-goal 的目标栏形态）；它自足读中枢快照，无需 props。
        GoalBar()
        /*
         * E195（§13 第 3 项）：**本会话的模型**。
         *
         * 官方把它做成会话输入区的选择器（`dsh-client-ui-model-selection`，写 `session/selectModel`）。
         * 这里放在同一个面板里而不是再造入口：面板本就是"会话操作"的地方、快捷键已绑定
         * ⇒ **可发现、不新增状态**。选中即调 `hub.selectSessionModel`（E194）；
         * 未选会话时如实说明（那条端点也要会话）。
         */
        // 本会话模型选择归 SessionModelPicker 所有（官方 ui-model-selection）；
        // 组件只管呈现，选中后的副作用（关面板 / 调中枢 / 写提示）留在宿主。
        SessionModelPicker({
          sessionId: this.f.selectedSessionId,
          models: this.f.models,
          currentModelId: this.f.selection.modelId,
          onPick: (m: ModelOption) => {
            this.f.setPaletteOpen(false);
            SessionHub.shared().selectSessionModel(m.provider, m.modelId, m.defaultEffort)
              .then((n: ActionNotice) => {
                this.f.setAttachNotice(this.f.noticeText(n));
              }).catch((e: Object) => {
                this.f.setSettingWriteNote('切换会话模型失败：' + (e as Error).message);
              });
          }
        })
        // 命令列表归 CommandList 所有（官方 ui-commands）；执行副作用留在宿主。
        CommandList({
          sessionId: this.f.selectedSessionId,
          commands: this.f.commands,
          onRun: (c: CommandCandidate) => {
            this.f.setPaletteOpen(false);
            /*
             * 【P9-4：要参数的命令不许"直接执行"】Host 的 `CommandDescriptor.input.hint`
             * 是权威信号（我们投影成 `c.args`）：它非空就表示这条命令需要一段自由文本。
             * 此前无论要不要参数都直接发出去 ⇒ 选 `/feedback` 会拿到 Host 那句英文 usage、
             * 面板关了、输入框空着（用户以为命令坏了）。
             * 现在按规则分流：要参数 ⇒ 填进输入框 + 说明；不要参数 ⇒ 照旧执行。
             * 判定在 `appstate/model/InputTrigger`（纯函数，有 fixture）。
             */
            if (commandPickAction(c.args) === COMMAND_PICK_DRAFT) {
              this.f.setDraft(commandDraftText(c.name));
              this.f.setAttachNotice(commandInputNotice(c.name, c.args));
              return;
            }
            SessionHub.shared().executeCommand(c.name).then((n: ActionNotice) => {
              this.f.setAttachNotice(this.f.noticeText(n));
            }).catch((e: Object) => {
              this.f.setAttachNotice('命令执行失败：' + (e as Error).message);
            });
          }
        })
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_primary'))
    }
    if (this.f.stackPage === StackPage.DIAGNOSTICS) {
      DiagnosticsPane({
        report: this.f.diag,
        running: this.f.diagRunning,
        // 判定项按模式裁剪（D7 §3 第 4 项）：本地核心模式下 TLS / 认证不适用
        entries: filterDiagEntries(this.f.diagMode(), this.f.diag.entries).concat([this.f.modalityEntry()]),
        modeTitle: diagTitleOf(this.f.diagMode()),
        modeHint: diagHintOf(this.f.diagMode()),
        traceEnabled: this.f.traceEnabled,
        traceLines: this.f.traceLines,
        onRerun: () => {
          this.f.runDiagnostics();
        },
        onToggleTrace: (on: boolean) => {
          this.f.setTraceEnabled(on);
          // 打开时显示**中枢的真实旁路日志**，而不是演示行。
          // 演示行只在未连接时作为布局示例出现（见 `applyHubSnapshot`）。
          this.f.setTraceLines(on
            ? SessionHub.shared().snapshot().trace
            : []);
        },
        onExportLog: () => {
          this.f.exportDiagnostics();
        },
        onClearCache: () => {
          // E130：此前是空实现（点了没反应）。清理的是**我们自己缓存的东西**：
          // 旁路日志 / 未识别事件清单 / 缓存的会话与轨迹。
          // **不碰 Host 上的任何数据**——诊断页不该有"顺手删远端东西"的按钮。
          SessionHub.shared().clearLocalCache();
          hilog.info(this.f.DOMAIN, this.f.TAG, 'HDSH-DIAG 已清理本机缓存');
        },
        onOpenPoc: () => {
          this.f.openPoc();
        },
        onBack: () => {
          this.f.backOneLayer();
        }
      })
    } else if (this.f.activePanel() === MAIN_CONNECT) {
      ConnectPane({
        hosts: this.f.hosts,
        address: this.f.connectAddress,
        token: this.f.connectToken,
        busy: this.f.connectBusy,
        resultText: this.f.connectResult,
        resultOk: this.f.connectOk,
        resultAdvice: this.f.connectAdvice,
        discoveryAvailable: false,
        onAddressChange: (v: string) => {
          this.f.setConnectAddress(v);
        },
        onTokenChange: (v: string) => {
          this.f.setConnectToken(v);
        },
        onSubmit: () => {
          this.f.setConnectBusy(true);
          this.f.setConnectResult('');
          this.f.setConnectAdvice('');
          const hub: SessionHub = SessionHub.shared();
          const url: string = this.f.composeHostUrl(this.f.connectAddress, this.f.connectToken);
          if (!hub.configure(url, undefined)) {
            this.f.setConnectOk(false);
            this.f.setConnectBusy(false);
            this.f.setConnectResult('地址无法解析');
            this.f.setConnectAdvice('请填形如 http://主机:端口 的地址；token 可单独填，也可直接粘贴完整启动链接（含 ?token=…）。');
            return;
          }
          hub.connect().then((ok: boolean) => {
            this.f.setConnectBusy(false);
            this.f.setConnectOk(ok);
            const snap: HubSnapshot = hub.snapshot();
            this.f.setConnectResult(ok
              ? `已连接 ${snap.authority}，收到 ${snap.sessions.length} 个会话`
              : (snap.lastError.length > 0 ? snap.lastError : '连接未建立'));
            this.f.setConnectAdvice(ok
              ? '真实数据已接管会话列表与待决；可在「连接诊断」页查看五项判定。'
              : '请确认 Host 已启动且令牌有效；模拟器/真机访问宿主回环需先做端口转发（hdc fport）。');
            if (ok) {
              // 只报告**成功的**连接：失败的地址/token 不该被记住，
              // 否则下次启动会拿一个已知无效的 token 去自动重连，用户看到的是
              // 「自动重连失败」——而正确行为是回到「添加 Host」。
              //
              // token 来自**解析后的 URL**，而不是 token 输入框：
              // 用户用的是「① 粘贴启动 URL」这条路径，token 输入框是空的。
              // 曾因此把空串当 token 存进去，表现为「保存失败 + 下次读不到 token」。
              this.f.reportConnectedHost(this.f.storageBaseUrl(url), extractToken(url) ?? this.f.connectToken.trim());
            }
          });
        },
        /*
         * 「开始发现」是**诚实的空实现**：那枚按钮的可用性由 `ConnectPane.discoveryAvailable`
         * 决定，不可用时它显示「发现不可用」且 `enabled(false)`——**不是"点了没反应"**。
         * 这台设备上没有可用的发现通道（E130 起本应用也只记一个 Host），
         * 所以宿主侧交一个空实现。写在这里，免得死按钮扫描器把它当缺陷再报一次。
         */
        onStartDiscovery: () => {
        },
        onOpenDiagnostics: () => {
          this.f.openDiagnostics();
        },
        onBack: () => {
          this.f.backOneLayer();
        }
      })
    } else if (this.f.activePanel() === MAIN_CONVERSATION) {
      /*
       * E125：会话统计行（官方措辞），数据来自投影，没有就不占位置。
       *
       * 【位置按形态分档（2026-09-17，对标官方 ⑧）】
       * 官方把这一行放在**窗口最底部**（输入区下方，横跨主区）——截图里看得很清楚：
       * `14 轮 754 步 · 259 tok/s · 292M tok · 缓存命中 99.9%`。
       * 我们此前一律贴在会话页**头部**。
       *
       * 分档理由：非单栏（PC/平板/2in1）要 1:1 ⇒ 挪到底部（见本分支末尾那一段）；
       * 单栏（手机）保持贴顶——底部紧挨输入区与软键盘，那一行的可读性反而更差，
       * 而"手机端适应性优化"正是允许这种差异的地方。
       */
      if (this.layoutMode === 'single' && this.f.statsLine.length > 0) {
        Text(this.f.statsLine)
          .fontSize(Fs.CAPTION)
          .fontColor(('sys.color.font_tertiary'))
          .width('100%')
          .padding({ left: Sp.M, right: Sp.M, top: Sp.XS })
      }
      ConversationPane({
        appName: this.f.appName,
        itemCount: this.f.trajectoryItems.length,
        // E115：审批/提问直接弹在会话里（官方 web 的形态），一次点击即可放行
        pending: this.f.pending,
        onDecidePending: (item: PendingItem, choiceId: string, reason: string) => {
          this.f.decidePending(item, choiceId, reason);
        },
        onAnswerPending: (item: PendingItem, drafts: PendingAnswerDraft[]) => {
          this.f.answerPending(item, drafts);
        },
        onCancelQuestion: (item: PendingItem) => {
          this.f.cancelQuestion(item);
        },
        sessionId: this.f.selectedSessionId,
        workspaceName: this.f.sessionWorkspaceName,
        sessionUpdatedAt: this.f.sessionUpdatedAt,
        jobs: this.f.jobs,
        items: this.f.trajectoryItems,
        running: this.f.running,
        offline: this.f.offline,
        queuedCount: this.f.queuedCount,
        draft: this.f.draft,
        scrollSpot: this.f.scrollSpot,
        deliverableShareTarget: (item: TrajectoryItem) => this.f.deliverableShareTarget(item),
        onShareDeliverable: (item: TrajectoryItem) => {
          this.f.onShareDeliverable(item);
        },
        onRememberSpot: (sessionId: string, top: number, following: boolean) => {
          this.f.onRememberSpot(sessionId, top, following);
        },
        attachments: this.f.attachments,
        models: this.f.models,
        selection: this.f.selection,
        references: this.f.references,
        commands: this.f.commands,
        notice: this.f.attachNotice,
        planActive: this.f.planActive,
        planPending: this.f.planPending,
        permissionLabel: this.f.permissionLabel,
        permissionSwitchableNow: this.f.permissionSwitchableNow,
        permissionHint: this.f.permissionHint,
        onPickPermission: this.f.onPickPermission,
        onDraftChange: (text: string) => {
          this.f.setDraft(text);
        },
        onSend: () => {
          this.f.sendDraft();
        },
        onStop: () => {
          // 连上后停止 = 真的取消当前轮次；未连接时只熄灭本地指示
          if (this.f.hubConnected) {
            SessionHub.shared().cancelTurn();
          }
          this.f.setRunning(false);
        },
        onAddAttachment: () => {
          this.f.pickAndAttach();
        },
        onAddImage: () => {
          this.f.pickAndAttachImage();
        },
        onOpenProduced: (path: string, name: string) => {
          this.f.openProducedFile(path, name);
        },
        onRemoveAttachment: (key: string) => {
          // 参数是**行身份**（文件=回执、图片=草稿 id），见 `Composer.onRemoveAttachment`
          SessionHub.shared().removeAttachment(key);
        },
        onPickModel: () => {
          this.f.setNav(openSettings(this.f.nav, '', this.f.panelRegistry));
        },
        onTogglePlan: () => {
          this.f.togglePlan();
        },
        // 输入模态：有指针才启用右键菜单与悬停（策略模型决定，见 appstate/model/InputPolicy）。
        // 两个事实**分开传**：合成来源见本文件 `recomputeModality()`。
        hasPointer: this.f.modality.hasPointer,
        hasKeyboard: this.f.modality.hasKeyboard,
        // 轨迹的时间总览要用的统计（数字，不是拼好的字符串）
        stats: this.f.sessionStats,
        onQuoteMessage: (item: TrajectoryItem) => {
          this.f.quoteIntoDraft(item);
        },
        onResendMessage: (item: TrajectoryItem) => {
          this.f.resendMessage(item);
        },
        // 消息操作条的「复制」：剪贴板是平台能力，回调由宿主提供（视图层不依赖 platform）
        onCopyMessage: (text: string) => {
          if (text.length === 0) {
            this.f.setAttachNotice('这条消息没有可复制的正文。');
            return;
          }
          copyText(text).then((ok: boolean) => {
            this.f.setAttachNotice(ok ? '已复制到剪贴板。' : '复制失败：剪贴板不可用。');
          });
        },
        onReferenceQuery: (query: string) => {
          if (this.f.hubConnected) {
            SessionHub.shared().refreshReferences(query);
          }
        },
        onPullQueued: (itemId: string, text: string) => {
          // 「取回编辑」= 移除该队列项 + 把正文放回草稿。
          // 移除走 Host（否则用户会在界面上看不到它、而它仍会被发送），
          // 放回草稿是本地动作。**先放回再移除**：即使移除失败，
          // 用户也已经拿回了文本，不会丢内容。
          this.f.setDraft(text);
          SessionHub.shared().removeQueuedItem(itemId).then((ok: boolean) => {
            if (!ok) {
              this.f.setAttachNotice('已把内容取回输入框，但队列项移除失败——它仍可能被 Host 发送，请检查诊断页。');
            }
          });
        },
        onRemoveQueued: (itemId: string) => {
          SessionHub.shared().removeQueuedItem(itemId);
        },
        onSteerQueued: (itemId: string) => {
          SessionHub.shared().steerQueuedItem(itemId);
        },
        onOpenDetail: () => {
          this.f.setDetailOverlayOpen(true);
        },
        searchOpen: this.f.searchOpen,
        onCloseSearch: () => {
          this.f.setSearchOpen(false);
        },
        // 触屏入口：手机上没有 Ctrl/Cmd+F，而官方轨迹页的搜索框是常驻可见的
        onOpenSearch: () => {
          this.f.setSearchOpen(true);
        }
      })

      /*
       * 非单栏：统计行放**输入区下方、主区最底部**——与官方 1:1（见本分支开头那段说明）。
       * 放在 `ConversationPane` **之后**，所以它在纵向排布上就在输入区下面。
       */
      if (this.layoutMode !== 'single' && this.f.statsLine.length > 0) {
        Text(this.f.statsLine)
          .fontSize(Fs.CAPTION)
          .fontColor(('sys.color.font_tertiary'))
          .width('100%')
          .padding({ left: Sp.M, right: Sp.M, bottom: Sp.XS })
      }
    } else {
      /*
       * 兜底分支：**不许再调 `mainContent`**（E343）。
       *
       * 这里曾经是 `this.mainContent(this.compact)`，真机上点一下就 `RangeError: Stack overflow!`
       * 直接杀进程——栈里成对出现 `MainShell.ets:405`（这句）与 `:404`（`else` 本身），
       * 即"兜底又把自己叫了一遍"，而 `mainContent` 每次都会重新走到这条 `else`。
       *
       * 【为什么会走到 else】主区还剩工作区 / 核心 / 设置三类面板，它们过去由**主区的第二束**
       * （`TabContentView`）直接渲染，搬迁后本组件忘了把这一束接上。
       * 静态阅读时它看着像"交回给上面继续分派"，实际是**自递归**。
       *
       * 【正确形态】兜底 = 把剩下的面板交给**真正拥有它们的那一束**，而不是回头再问自己：
       * 这里直接渲染 `TabContentView`（工作区 / 设置 / 核心的既有分派点，自带兜底、不再外调）。
       * 门禁 `tools/check-builder-recursion.mjs` 守着这条规矩：`@Builder` 体内不许出现自己的名字。
       */
      TabContentView({ f: this.f.tabFacade, compact: this.compact })
    }
  }

  build() {
    this.mainContent(this.compact)
  }
}
