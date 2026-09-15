/**
 * 标签页内容（工作区 / 设置 / 核心）—— P0：主区内容搬迁的**第一束**。
 *
 * 本束 = `@Builder tabContent` + 它调用的 `@Builder workspaceHub` / `workspaceGroup`（462 行）。
 *
 * ## 门面为什么带 setter（本轮实测出来的）
 *
 * 搬走的代码**会写宿主状态**（共 13 个：archiveOpen, choosing, choosingCurrent, choosingKey, choosingLabel …）。
 * 若门面里它们只是普通属性，赋值会写进**门面副本**、宿主收不到 ——
 * **这不是编译错误，而是静默行为错误**（界面看着正常、状态没变）。
 * 故被写成员在门面里成对出现：只读属性 + `setX(v)`，搬走代码里的赋值已改写成 setter 调用（29 处）。
 *
 * 其余成员：只读值给快照、方法给闭包；门面由宿主**每次渲染重建**（缓存它等于放弃"中枢变了界面跟着变"）。
 *
 * 【为什么用门面】把父组件的 `@Builder` 注入子组件再调用会在真机 JS 崩溃（本仓 E118 实测）
 * ⇒ 内容只能靠数据/回调传。本束里唯一被调用的别的 builder 是 `hubBanner`，
 * 而它**已经是组件 `HubBanner`**，故这里直接渲染组件。
 */

import { ActionNotice, HarmonyIconSize, AgentPresetRow, CoreViewState, CredentialItem, FileNode, FilePreview, Fs, HostRecord, HubPhase, LayoutMode, ModelOption, ModelSelection, NavTab, PendingItem, PluginItem, Radius, SessionHub, SessionListItem, SettingGroup, SkillRow, Sp, StackPage, Sz, WorkspaceItem, aboutInfo, formatClock, projectGeneralGroups, relativeTime, sessionEmptyCopy } from 'appstate';
import type { SettingChoice, SettingItem, SettingsNamespaceState } from 'appstate';
import { LocalPrefs } from 'platform';
import { HubBanner } from './HubBanner';
import { PendingPane } from './PendingPane';
import { SettingsPane } from './SettingsPane';
import { WorkspacePane } from './WorkspacePane';

export interface TabContentFacade {
  answerPending: (item: PendingItem, selected: string[], custom: string) => void;
  applyDefaultModel: (provider: string, model: string, effort: string) => void;
  archiveOpen: boolean;
  setArchiveOpen: (value: boolean) => void;
  archivedSessionIds: string[];
  archivedSessions: () => SessionListItem[];
  attachWorkspaceFileToComposer: (node: FileNode) => Promise<void>;
  choosing: SettingChoice[] | undefined;
  setChoosing: (value: SettingChoice[] | undefined) => void;
  choosingCurrent: string;
  setChoosingCurrent: (value: string) => void;
  choosingKey: string;
  setChoosingKey: (value: string) => void;
  choosingLabel: string;
  setChoosingLabel: (value: string) => void;
  confirmingDeletePath: string;
  setConfirmingDeletePath: (value: string) => void;
  connectBusy: boolean;
  connectSettled: boolean;
  coreNotice: string;
  coreView: CoreViewState;
  createSessionIn: (w: WorkspaceItem) => void;
  credentials: CredentialItem[];
  currentTab: () => NavTab;
  decidePending: (item: PendingItem, choiceId: string, reason: string) => void;
  deleteWorkspaceByPath: (w: WorkspaceItem) => void;
  fileTree: FileNode[];
  forgetHost: () => void;
  hosts: HostRecord[];
  hubAuthority: string;
  hubConnected: boolean;
  hubError: string;
  hubPhase: HubPhase;
  hubStreams: number;
  hubTraceTail: () => string[];
  localItemOf: (key: string) => SettingItem | undefined;
  localized: (id: Resource) => string;
  mode: LayoutMode;
  models: ModelOption[];
  noticeText: (n: ActionNotice) => string;
  onCoreAction: (id: string) => void;
  onCoreSelectVersion: (version: string) => void;
  onResetPluginRows: () => void;
  onTogglePlugin: (id: string, disabled: boolean) => void;
  openCredentialSheet: (ref: string) => void;
  openDiagnostics: () => void;
  openFile: (node: FileNode) => void;
  openFolderPicker: () => void;
  openSession: (id: string) => void;
  openStructSettingSheet: (item: SettingItem) => void;
  openTextSettingSheet: (item: SettingItem) => void;
  openWorkspaceFiles: (w: WorkspaceItem) => void;
  pending: PendingItem[];
  pendingWorkspacePick: boolean;
  setPendingWorkspacePick: (value: boolean) => void;
  permissionCurrent: string;
  permissionOptions: string[];
  plugins: PluginItem[];
  presetNote: string;
  presets: AgentPresetRow[];
  preview: FilePreview | undefined;
  registryIdOf: (w: WorkspaceItem) => string;
  resetSetting: (key: string) => void;
  selectedSessionId: string;
  selection: ModelSelection;
  setSelection: (value: ModelSelection) => void;
  sessionForWorkspace: (workspaceId: string) => string;
  sessionsOf: (w: WorkspaceItem) => SessionListItem[];
  settingItemOf: (key: string) => SettingItem | undefined;
  settingWriteNote: string;
  setSettingWriteNote: (value: string) => void;
  settings: SettingGroup[];
  settingsStates: SettingsNamespaceState[];
  skillNote: string;
  skills: SkillRow[];
  stackPage: StackPage;
  setStackPage: (value: StackPage) => void;
  toggleDirectory: (path: string) => void;
  treeEmptyHint: string;
  setTreeEmptyHint: (value: string) => void;
  treeEmptyTitle: string;
  setTreeEmptyTitle: (value: string) => void;
  workspaces: WorkspaceItem[];
  writeSetting: (key: string, value: Object, label: string) => Promise<void>;
  wsDrill: number;
  setWsDrill: (value: number) => void;
}

@Component
export struct TabContentView {
  @Prop f: TabContentFacade;
  /** 是否紧凑（单栏/双栏下少留白）——由宿主给，组件不自己判定形态 */
  @Prop compact: boolean = false;

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
      } else if (this.f.hubError.length > 0) {
        HubBanner({
          errorText: this.f.hubError, authority: this.f.hubAuthority, phase: this.f.hubPhase,
          streams: this.f.hubStreams, traceTail: this.f.hubTraceTail(),
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

      if (this.f.pending.length > 0) {
        Column({ space: Sp.XS }) {
          Text(`待你决定 · ${this.f.pending.length}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.warning'))
            .width('100%')
          PendingPane({
            items: this.f.pending,
            onDecide: (item: PendingItem, choiceId: string, reason: string) => {
              this.f.decidePending(item, choiceId, reason);
            },
            onAnswer: (item: PendingItem, selected: string[], custom: string) => {
              this.f.answerPending(item, selected, custom);
            }
          })
        }
        .width('100%')
        .constraintSize({ maxHeight: 320 })
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
          Text(`${$r('app.string.section_archive')} · ${this.f.archivedSessionIds.length}`)
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
          Text(`${$r('app.string.section_archive')} · ${this.f.archivedSessionIds.length}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
          ForEach(this.f.archivedSessions(), (s: SessionListItem) => {
            Row({ space: Sp.S }) {
              SymbolGlyph($r('sys.symbol.archivebox')).fontSize(HarmonyIconSize.STATUS)
                .fontColor([$r('sys.color.font_secondary')])
              Text(s.title.length > 0 ? s.title : $r('app.string.label_unnamed_session'))
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
        List({ space: Sp.M }) {
          ForEach(this.f.workspaces, (w: WorkspaceItem) => {
            ListItem() {
              this.workspaceGroup(w)
            }
          }, (w: WorkspaceItem) => w.path)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding(Sp.M)
  }
  @Builder
  workspaceGroup(w: WorkspaceItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
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
              if (this.f.confirmingDeletePath === w.path) {
                this.f.setConfirmingDeletePath('');
                this.f.deleteWorkspaceByPath(w);
              } else {
                this.f.setConfirmingDeletePath(w.path);
                // E140：状态字符串经资源管理器取值；并附上名字——确认框必须指名道姓
                const note: string = this.f.localized($r('app.string.confirm_delete_workspace_note'));
                this.f.setSettingWriteNote(note.length > 0
                  ? `${note}（${w.name.length > 0 ? w.name : w.path}）`
                  : `再按一次「确认删除」即移除该工作区的登记；磁盘上的目录与文件不会被删除。（${w.name.length > 0 ? w.name : w.path}）`);
              }
            })
        }
      }
      .width('100%')

      ForEach(this.f.sessionsOf(w), (s: SessionListItem) => {
        Column({ space: 2 }) {
          Row({ space: Sp.S }) {
            Text(s.title.length > 0 ? s.title : $r('app.string.label_unnamed_session'))
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
             * E134：归档会话（官方语义是"注册表全局归档集"）。
             * 【为什么没有"取消归档"】线协议里只有 `workspace/archiveSession`，
             * **没有反向端点**——所以这里只提供归档，不造一个点不动的"恢复"。
             */
            Text($r('app.string.action_archive'))
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .onClick(() => {
                SessionHub.shared().archiveSession(s.id).then((n: ActionNotice) => {
                  this.f.setSettingWriteNote(this.f.noticeText(n));
                }).catch((e: Object) => {
                  const err = e as Error;
                  this.f.setSettingWriteNote(`${this.f.localized($r('app.string.note_archive_failed'))}${err.message}`);
                });
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
      }, (s: SessionListItem) => s.id)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
  }
  @Builder
  tabContent(compact: boolean) {
    /*
     * E108：工作区视图（合并了原来的「会话」与「待决」两个页签）。
     * 官方 web 的侧栏就是"工作区为组、会话挂在组下"；待决属于**当前这次对话**，显示在列表顶部。
     * 文件浏览仍是工作区里的下钻（`wsDrill > 0`，见下一个分支）。
     */
    if (this.f.currentTab() === NavTab.WORKSPACES && this.f.wsDrill === 0) {
      this.workspaceHub(compact)
    } else if (this.f.currentTab() === NavTab.WORKSPACES) {
      WorkspacePane({
        workspaces: this.f.workspaces,
        onPickFolder: () => {
          this.f.openFolderPicker();
        },
        tree: this.f.fileTree,
        selectedPath: this.f.preview === undefined ? '' : this.f.preview.path,
        preview: this.f.preview,
        compact: compact && this.f.mode === LayoutMode.SINGLE,
        drillLevel: this.f.wsDrill,
        treeEmptyTitle: this.f.treeEmptyTitle,
        treeEmptyHint: this.f.treeEmptyHint,
        onSelectWorkspace: (id: string) => {
          const scope: string = this.f.sessionForWorkspace(id);
          // 空态文案按「为什么空」分档（D3 §4：空态要说明可以做什么）
          this.f.setPendingWorkspacePick(true);
          if (scope.length === 0) {
            this.f.setTreeEmptyTitle('该工作区下还没有会话');
            this.f.setTreeEmptyHint('文件浏览的作用域是会话级（workspaceFileScopeId = 会话 id），请先在这个目录里新建一个会话。');
          } else {
            this.f.setTreeEmptyTitle('该目录暂无文件');
            this.f.setTreeEmptyHint('目录确实为空，或 Host 拒绝列出它的内容（详见连接诊断）。');
            if (this.f.hubConnected) {
              SessionHub.shared().openWorkspace(scope);
            }
          }
          if (this.f.mode === LayoutMode.SINGLE) {
            this.f.setWsDrill(1);
          }
        },
        onToggleDirectory: (path: string) => {
          this.f.toggleDirectory(path);
        },
        onOpenFile: (node: FileNode) => {
          this.f.openFile(node);
        },
        onAttachFile: (node: FileNode) => {
          this.f.attachWorkspaceFileToComposer(node);
        },
        onBack: () => {
          this.f.setWsDrill(this.f.wsDrill > 0 ? this.f.wsDrill - 1 : 0);
        }
      })
    } else {
      SettingsPane({
        // E118：核心分区的内容直接由属性传入（不再用 @BuilderParam 注入父 Builder——
        // 真机上点开该分区会 JS 崩溃）
        coreView: this.f.coreView,
        permissionCurrent: this.f.permissionCurrent,
        permissionOptions: this.f.permissionOptions,
        coreNotice: this.f.coreNotice,
        onCoreAction: (id: string) => {
          this.f.onCoreAction(id);
        },
        onCoreSelectVersion: (version: string) => {
          this.f.onCoreSelectVersion(version);
        },
        onTogglePluginRow: (id: string, disabled: boolean) => {
          this.f.onTogglePlugin(id, disabled);
        },
        onResetPluginRowsAction: () => {
          this.f.onResetPluginRows();
        },
        // E114：官方「通用」分区承载的是**用户面向的功能包设置**（外观/语言/会话…），
        // 引擎参数不在其中。这里做同样的策展：白名单命名空间整组显示，
        // 其余命名空间里**用户改过**的项收进「其他已修改项」，既不占版面又撤得回。
        groups: projectGeneralGroups(this.f.settings),
        // E128：模型页要能编辑提供方的设置分区（baseURL / 模型目录），所以另传全量
        allGroups: this.f.settings,
        // E135：技能清单（数据层已就绪；形状未识别时界面如实显示结论）
        skills: this.f.skills,
        skillNote: this.f.skillNote,
        // E161：预设名单（数据层已按真机实测契约接线）
        presets: this.f.presets,
        presetNote: this.f.presetNote,
        /*
         * E170：预设的**复制**（官方唯一创建入口）与**删除**（仅自定义项）。
         * 【为什么自动命名而不弹输入框】官方用复制对话框让我们填"标识 + 名称"；
         * 端侧先做**一步完成**的版本（`<id>-copy` / `<名称> 副本`）——它是一个完整可用的动作，
         * 而不是半成品表单；需要改名时再走查看/编辑那条线（`read` 已就绪）。
         */
        onPresetCopy: (from: string, name: string) => {
          const id: string = `${from}-copy`;
          SessionHub.shared().copyAgentPreset(from, id, `${name.length > 0 ? name : from} 副本`)
            .then((n: ActionNotice) => {
              this.f.setSettingWriteNote(this.f.noticeText(n));
            }).catch((e: Object) => {
              this.f.setSettingWriteNote(`复制预设失败：${(e as Error).message}`);
            });
        },
        onPresetDelete: (id: string) => {
          SessionHub.shared().deleteAgentPreset(id)
            .then((n: ActionNotice) => {
              this.f.setSettingWriteNote(this.f.noticeText(n));
            }).catch((e: Object) => {
              this.f.setSettingWriteNote(`删除预设失败：${(e as Error).message}`);
            });
        },
        credentials: this.f.credentials,
        plugins: this.f.plugins,
        hosts: this.f.hosts,
        models: this.f.models,
        selection: this.f.selection,
        about: aboutInfo(),
        writeNote: this.f.settingWriteNote,
        states: this.f.settingsStates,
        onToggleSetting: (key: string, value: boolean) => {
          if (this.f.settingItemOf(key) === undefined) {
            // 本地偏好：本客户端自己的开关，没有上游写路径。
            // 如实说明它只在本机生效，而不是假装写成功了。
            this.f.setSettingWriteNote(`「${key}」是本机偏好，只在本次运行内生效（尚未做持久化）。`);
            return;
          }
          this.f.writeSetting(key, value as Object, key);
        },
        onPickChoice: (key: string, current: string) => {
          const item: SettingItem | undefined = this.f.settingItemOf(key);
          if (item === undefined) {
            // 本机偏好：没有上游写路径，但**有端侧持久化路径**（`platform/LocalPrefs`）。
            // 仍然复用同一个选中浮层（选项来源换成端侧那一组），提交时由 `applyChoice` 分流。
            const local: SettingItem | undefined = this.f.localItemOf(key);
            if (local === undefined) {
              this.f.setSettingWriteNote(`「${key}」既不属于 Host 设置、也不在本机偏好表里。`);
              return;
            }
            this.f.setChoosingKey(key);
            this.f.setChoosingLabel(local.label);
            this.f.setChoosingCurrent(current);
            this.f.setChoosing(local.choices);
            return;
          }
          if (item.choices.length === 0) {
            // 防御分支：列表里的 TEXT 项已直接走 `onEditText`，不会走到这里。
            this.f.openTextSettingSheet(item);
            return;
          }
          this.f.setChoosingKey(key);
          this.f.setChoosingLabel(item.label);
          this.f.setChoosingCurrent(current);
          this.f.setChoosing(item.choices);
        },
        onEditText: (item: SettingItem) => {
          this.f.openTextSettingSheet(item);
        },
        onEditStruct: (item: SettingItem) => {
          this.f.openStructSettingSheet(item);
        },
        onResetSetting: (key: string) => {
          this.f.resetSetting(key);
        },
        onPickEffort: (effort: string) => {
          this.f.setSelection({
            provider: this.f.selection.provider, modelId: this.f.selection.modelId, effort: effort
          });
        },
        onSelectModel: (provider: string, model: string, effort: string) => {
          this.f.applyDefaultModel(provider, model, effort);
        },
        onAuthorizeCredential: (ref: string) => {
          this.f.openCredentialSheet(ref);
        },
        onPairHost: () => {
          this.f.setStackPage(StackPage.CONNECT);
        },
        onRevokeHost: (id: string) => {
          this.f.forgetHost();
        },
        onOpenDiagnostics: () => {
          this.f.openDiagnostics();
        }
      })
    }
  }

  build() {
    this.tabContent(this.compact)
  }
}
