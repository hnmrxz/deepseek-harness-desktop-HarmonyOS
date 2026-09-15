/**
 * 设置页（D1 §7.6 / D3 §1）。
 *
 * 五个页签：通用 / 模型 / 凭据 / 插件 / 设备。
 *
 * 规格要点：
 *   - 每个设置项都带**说明文字**（D3 §4 文案纪律：不能只有名字）；
 *   - 凭据**只呈现状态，绝不含明文值**（D1 §11.5 S3/S4）；
 *   - 插件页展示 cordis fiber 阶段与启用状态；
 *   - 设备页列出 Host、接入级别（L0/L1）与授权状态，并给出配对/吊销入口（D1 §6.4）。
 */

import {
  AboutInfo,
  CredentialItem,
  emptyCoreView,
  Fs,
  HostRecord,
  ModelOption,
  ModelSelection,
  Radius,
  PluginItem,
  SettingGroup,
  SettingItem,
  SkillRow,
  AgentPresetRow,
  presetIsBundled,
  Sp,
  Sz,
  settingsSectionLabelRes
} from 'appstate';
import type { CoreViewState, PanelDescriptor, SettingsNamespaceState } from 'appstate';
import { SessionHub } from 'appstate';
import { SettingRow } from './SettingRow';
import { SettingsInventory } from './SettingsInventory';
import { SettingsGeneral } from './SettingsGeneral';
import { SettingsDevice } from './SettingsDevice';
import { SettingsModels } from './SettingsModels';
import { SettingsPlugins } from './SettingsPlugins';
import { CorePane } from './CorePane';

/** 设置面板（E108/E110/E114/E120） */
@Component
export struct SettingsPane {
  /** 宿主报告的权限组合（E124；空串=未投影，界面不显示要切换的假档位） */
  @Prop permissionCurrent: string = '';
  @Prop permissionOptions: string[] = [];

  /** 插件分区子页签（E114：配置 / 列表） */
  /** 插件清单的过滤词（只作用于「列表」子页签） */

  @Prop groups: SettingGroup[] = [];
  @Prop credentials: CredentialItem[] = [];
  @Prop plugins: PluginItem[] = [];
  @Prop hosts: HostRecord[] = [];
  @Prop models: ModelOption[] = [];
  @Prop selection: ModelSelection = { provider: '', modelId: '', effort: '' };
  @Prop about: AboutInfo = {
    appVersion: '', supportedUpstream: '', compatCapturedAt: '', endpointStats: ''
  };
  /** 最近一次设置写入的结果回显（由页面注入；空串表示不显示） */
  @Prop writeNote: string = '';
  /** 各命名空间的写状态（仅用于诊断显示 revision） */
  @Prop states: SettingsNamespaceState[] = [];

  onToggleSetting: (key: string, value: boolean) => void = () => {
  };
  onPickChoice: (key: string, current: string) => void = () => {
  };
  /** 打开文本 / 数字设置项的编辑浮层 */
  onEditText: (item: SettingItem) => void = () => {
  };
  /** 打开结构化值（数组/对象）的整值编辑浮层 */
  onEditStruct: (item: SettingItem) => void = () => {
  };
  /**
   * 重置为**部署默认**（E114，对齐官方插件卡片的"重置"）。
   *
   * 只对"已覆盖"的项出现：没有覆盖过就没有可重置的东西，摆一个点了没反应的按钮更糟。
   * 实现走 `settings/unset`（上游语义：删掉用户层的这一项，值立刻回落到基线/默认）。
   */
  onResetSetting: (key: string) => void = () => {
  };
  onPickEffort: (effort: string) => void = () => {
  };
  /**
   * 选择**默认模型**（provider/model/effort 三个字段一起写 `agent-default-model`）。
   *
   * 【为什么是"默认"而不是"当前会话"】官方把"当前会话用哪个模型"放在会话输入区
   * （`session/selectModel`，按会话生效）；而**设置页**管的是"新会话默认用什么"，
   * 落在 `agent-default-model` 命名空间。两者都对齐官方：这里写默认，输入区切换单次会话。
   */
  onSelectModel: (provider: string, model: string, effort: string) => void = () => {
  };
  /** 凭据：发起交互式授权（D1 §7.6.3） */
  onAuthorizeCredential: (ref: string) => void = () => {
  };
  /** 设备：发起配对 */
  onPairHost: () => void = () => {
  };
  /** 设备：吊销设备密钥 */
  onRevokeHost: (id: string) => void = () => {
  };
  /** 打开诊断页 */
  onOpenDiagnostics: () => void = () => {
  };

  /**
   * 当前分区（P4-1：**唯一真值在 `NavigationState.settingsSection`**，由宿主传进来）。
   *
   * 【为什么不再是视图里的 `@State tab`】设置分区是**导航状态**的一部分：从侧栏「设置」进来、
   * 从别处深链到某一分区、以及"返回"该回到哪一段，都要看它。视图自己存一份，
   * 等于让导航状态与显示内容两处各说一套。
   */
  @Prop section: string = 'settings.general';
  /** 可用分区清单（注册表给；切换器按它画，顺序也由它定） */
  @Prop sections: PanelDescriptor[] = [];
  /** 选一个分区（宿主经注册表校验后写进 `settingsSection`） */
  onSelectSection: (sectionId: string) => void = () => {
  };

  build() {
    Column() {
      this.tabBar()
      Divider().color($r('sys.color.comp_divider'))

      // 写入结果回显：成功 / 冲突 / 被拒 / 本机偏好都走这里。
      // 不做乐观更新，所以这里是用户唯一能看到「Host 到底接受了没有」的地方。
      if (this.writeNote.length > 0) {
        Text(this.writeNote)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: Sp.M, right: Sp.M, top: Sp.S, bottom: Sp.S })
          .backgroundColor($r('sys.color.background_secondary'))
      }

      Scroll() {
        Column({ space: Sp.L }) {
          if (this.section === 'settings.skills') {
            /*
             * E135：技能分区。
             *
             * 【读不到就说读不到】`skills/list` 的回复外层键我们没有确证（类型定义只给了单个
             * 技能摘要的形状）⇒ 数据层容忍三种形状，都不中时把**真实顶层键**记进旁路日志、
             * 并在这里显示结论。绝不把"没读出来"渲染成"没有技能"——那会让人以为宿主没装技能。
             */
            if (this.skillNote.length > 0) {
              Text(this.skillNote)
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
                .padding(Sp.M)
                .borderRadius(Radius.M)
                .backgroundColor($r('sys.color.background_secondary'))
            }
            if (this.skills.length === 0) {
              if (this.skillNote.length === 0) {
                Text('宿主报告没有可用技能。')
                  .fontSize(Fs.CAPTION)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
              }
            } else {
              ForEach(this.skills, (s: SkillRow) => {
                Column({ space: 2 }) {
                  Row({ space: Sp.S }) {
                    Text(s.name)
                      .fontSize(Fs.SECONDARY)
                      .fontWeight(FontWeight.Medium)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (s.provider.length > 0) {
                      Text(s.provider)
                        .fontSize(Fs.CAPTION)
                        .fontColor($r('sys.color.font_tertiary'))
                    }
                  }
                  .width('100%')
                  if (s.description.length > 0) {
                    Text(s.description)
                      .fontSize(Fs.CAPTION)
                      .fontColor($r('sys.color.font_secondary'))
                      .width('100%')
                  }
                  if (s.whenToUse.length > 0) {
                    Text(`适用：${s.whenToUse}`)
                      .fontSize(Fs.CAPTION)
                      .fontColor($r('sys.color.font_tertiary'))
                      .width('100%')
                  }
                }
                .width('100%')
                .padding(Sp.M)
                .borderRadius(Radius.M)
                .backgroundColor($r('sys.color.background_secondary'))
              }, (s: SkillRow) => `${s.provider}/${s.name}`)
            }
            Text('技能由宿主的技能提供方给出（`dsh-skill` / `dsh-skill-filesystem`）；端侧只读展示，不在这里编辑技能正文。')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          } else if (this.section === 'settings.presets') {
            /*
             * E161：**预设名单卡片**（官方形态）。
             *
             * 预设 = 会话的 Agent 所运行的**插件组装**（工具/提示词/能力），名称与描述**由预设自带**
             * （真机上就是中文），我们只做展示与动作。官方规则：**复制**是创建自定义预设的**唯一入口**；
             * **随附预设只读**（`trust === 'system'`）；删除只对自定义项开放。
             *
             * 【还没接的动作】复制/删除/打开位置需要 `agentPresets/copy|deletePreset|read`，
             * 其**参数形状尚未探针确证**（E159 的教训：形状不能推）⇒ 本版只做**名单展示**，
             * 不摆点不动的按钮；确证后补齐。
             */
            if (this.presetNote.length > 0) {
              Text(this.presetNote)
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
                .padding(Sp.M)
                .borderRadius(Radius.M)
                .backgroundColor($r('sys.color.background_secondary'))
            }
            if (this.presets.length > 0) {
              Text('Agent 预设')
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
              ForEach(this.presets, (p: AgentPresetRow) => {
                Column({ space: 2 }) {
                  Row({ space: Sp.S }) {
                    Text(p.name.length > 0 ? p.name : p.id)
                      .fontSize(Fs.BODY)
                      .fontWeight(FontWeight.Medium)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (p.isDefault) {
                      Text('默认')
                        .fontSize(Fs.CAPTION)
                        .fontColor($r('sys.color.brand'))
                    }
                    Text(presetIsBundled(p) ? '随附' : '自定义')
                      .fontSize(Fs.CAPTION)
                      .fontColor($r('sys.color.font_tertiary'))
                  }
                  .width('100%')
                  if (p.description.length > 0) {
                    Text(p.description)
                      .fontSize(Fs.CAPTION)
                      .fontColor($r('sys.color.font_secondary'))
                      .width('100%')
                  }
                  Text(p.id)
                    .fontSize(Fs.CAPTION)
                    .fontColor($r('sys.color.font_tertiary'))
                    .width('100%')
                  /*
                   * E170：卡片动作。
                   * · 「复制」**每张都有**——官方只读预设也能被复制来自定义（这就是创建的唯一入口）；
                   * · 「删除」**只有自定义预设才有**（`trust !== 'system'`）——随附预设删不掉，
                   *   连入口都不该给（宿主也会拒绝，见 deletePreset 的实测返回）。
                   * · 删除走**两步确认**：先变成「确认删除 / 取消」。
                   */
                  Row({ space: Sp.M }) {
                    Text('复制')
                      .fontSize(Fs.CAPTION)
                      .fontColor($r('sys.color.brand'))
                      .onClick(() => {
                        this.onPresetCopy(p.id, p.name);
                      })
                    /*
                     * E173：**查看**（只读）。官方对随附预设就是"在只读查看器里打开"
                     * ——复制对话框之外的第二个允许动作。参数名 `agentPreset` 由宿主 schema 确证。
                     */
                    Text(this.presetViewedId === p.id ? '收起内容' : '查看')
                      .fontSize(Fs.CAPTION)
                      .fontColor($r('sys.color.brand'))
                      .onClick(() => {
                        if (this.presetViewedId === p.id) {
                          this.presetViewedId = '';
                          this.presetContent = '';
                          return;
                        }
                        this.presetViewedId = p.id;
                        this.presetContent = '正在读取…';
                        SessionHub.shared().readAgentPreset(p.id).then((text: string) => {
                          this.presetContent = text.length > 0
                            ? text
                            : '宿主没有返回内容（可能该预设没有可读的组装文本，或读取被拒）。';
                        }).catch((e: Object) => {
                          this.presetContent = `读取失败：${(e as Error).message}`;
                        });
                      })
                    if (!presetIsBundled(p)) {
                      Text(this.confirmingPresetId === p.id ? '确认删除' : '删除')
                        .fontSize(Fs.CAPTION)
                        .fontColor($r('sys.color.alert'))
                        .onClick(() => {
                          if (this.confirmingPresetId === p.id) {
                            this.confirmingPresetId = '';
                            this.onPresetDelete(p.id);
                          } else {
                            this.confirmingPresetId = p.id;
                          }
                        })
                      if (this.confirmingPresetId === p.id) {
                        Text('取消')
                          .fontSize(Fs.CAPTION)
                          .fontColor($r('sys.color.font_tertiary'))
                          .onClick(() => {
                            this.confirmingPresetId = '';
                          })
                      }
                    }
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(Sp.M)
                .borderRadius(Radius.M)
                .backgroundColor($r('sys.color.background_secondary'))
              }, (p: AgentPresetRow) => p.id)
              Text('预设是"这个会话的 Agent 跑哪些插件"的组装；会话创建时固定，改默认只影响此后新建的会话。复制 / 打开位置 / 删除待接线（形状需先探针确证）。')
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
            }
            /*
             * E129：Agent 预设分区（对齐官方「设置分区把名单呈现为卡片」的**一半**）。
             *
             * 官方那一页管理的是 preset **目录**（复制/删除/定位/只读查看随附项），
             * 那需要一次 Remote 查询与文件级操作；我们端侧先做**能确证的一半**：
             * 把宿主真正暴露的 `agent-*` 设置分区（含 `agent-presets.default`）按原有编辑器呈现，
             * 让"新建会话用哪个预设"这件事真的可改；找不到任何分区时如实说明。
             */
            if (this.agentGroups().length === 0) {
              Text('宿主没有暴露 agent-* 设置分区（端侧只显示它确实报告的东西）。')
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
            } else {
              ForEach(this.agentGroups(), (group: SettingGroup) => {
                Column({ space: Sp.XS }) {
                  Text(group.title)
                    .fontSize(Fs.CAPTION)
                    .fontColor($r('sys.color.font_tertiary'))
                    .width('100%')
                  ForEach(group.items, (item: SettingItem) => {
                    this.settingRow(item)
                  }, (item: SettingItem) => item.key)
                }
                .width('100%')
              }, (group: SettingGroup) => group.title)
            }
            Text('预设**在会话创建时固定**（官方原话），所以这里设置的是**此后新建会话**用的默认值；已存在的会话不受影响。')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          } else if (this.section === 'settings.core') {
            // 核心分区：与原来的一级「核心」页内容一致（版本切换/回滚、插件、运行时事实）
            Column({ space: Sp.S }) {
              if (this.coreNotice.length > 0) {
                Text(this.coreNotice)
                  .fontSize(Fs.CAPTION)
                  .fontColor($r('sys.color.font_secondary'))
                  .width('100%')
                  .padding(Sp.S)
                  .borderRadius(Radius.S)
                  .backgroundColor($r('sys.color.background_secondary'))
              }
              CorePane({
                view: this.coreView,
                onAction: (id: string) => {
                  this.onCoreAction(id);
                },
                onSelectVersion: (version: string) => {
                  this.onCoreSelectVersion(version);
                },
                onTogglePlugin: (id: string, disabled: boolean) => {
                  this.onTogglePluginRow(id, disabled);
                },
                onResetPluginRows: () => {
                  this.onResetPluginRowsAction();
                },
                pluginNotice: this.pluginNotice
              })
            }
            .width('100%')
          } else if (this.section === 'settings.general') {
            // 通用段归 SettingsGeneral（P4-4 拆出的域组件）
            SettingsGeneral({
              groups: this.groups,
              permissionCurrent: this.permissionCurrent,
              permissionOptions: this.permissionOptions,
              onOpenDiagnostics: () => {
                this.onOpenDiagnostics();
              },
              onToggleSetting: (key: string, value: boolean) => {
                this.onToggleSetting(key, value);
              },
              onPickChoice: (key: string, current: string) => {
                this.onPickChoice(key, current);
              },
              onEditText: (item: SettingItem) => {
                this.onEditText(item);
              },
              onEditStruct: (item: SettingItem) => {
                this.onEditStruct(item);
              },
              onResetSetting: (key: string) => {
                this.onResetSetting(key);
              }
            })
          } else if (this.section === 'settings.models') {
            // 模型域归 SettingsModels（P4-3b 拆出的域组件）
            SettingsModels({
              allGroups: this.allGroups,
              models: this.models,
              selection: this.selection,
              credentials: this.credentials,
              onSelectModel: (provider: string, model: string, effort: string) => {
                this.onSelectModel(provider, model, effort);
              },
              onAuthorizeCredential: (ref: string) => {
                this.onAuthorizeCredential(ref);
              },
              onToggleSetting: (key: string, value: boolean) => {
                this.onToggleSetting(key, value);
              },
              onPickChoice: (key: string, current: string) => {
                this.onPickChoice(key, current);
              },
              onEditText: (item: SettingItem) => {
                this.onEditText(item);
              },
              onEditStruct: (item: SettingItem) => {
                this.onEditStruct(item);
              },
              onResetSetting: (key: string) => {
                this.onResetSetting(key);
              }
            })
          } else if (this.section === 'settings.plugins') {
            this.pluginsTab()
          } else if (this.section === 'settings.plugin-inventory') {
            // 只读清单独立成分区（官方 `settings-plugin-inventory`）：它是"这家宿主装了什么"，
            // 与"哪些插件可以配置"是两件事（此前是插件段里的一个子页签）
            // 只读清单归 SettingsInventory（官方 settings-plugin-inventory）
            SettingsInventory({ plugins: this.plugins })
          } else {
            // 设备段归 SettingsDevice（P4-4 拆出的域组件）
            SettingsDevice({
              about: this.about,
              hosts: this.hosts,
              onPairHost: () => {
                this.onPairHost();
              },
              onRevokeHost: (id: string) => {
                this.onRevokeHost(id);
              }
            })
          }
        }
        .width('100%')
        .padding(Sp.M)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 核心分区（E110/E118：原「核心」一级页签并入这里）。
   *
   * 【为什么不用 `@BuilderParam` 注入】原先由宿主注入一个 `@Builder`（`coreSlot`），
   * 真机上点开「核心」分区**直接 JS 崩溃**（`AppKilledReporter: reason: JsError`，
   * 23:57:10 的 `JS_ERROR…` faultlog），而只改这一处即可回避。
   * 改为把 `CorePane` 需要的 6 个属性直接传进来：数据流一眼能看完，
   * 也不再依赖"父 Builder 在子组件里被调用"这条容易踩坑的机制。
   */
  @Prop coreView: CoreViewState = emptyCoreView();
  /** 核心页顶部的一次性提示（宿主维护） */
  @Prop coreNotice: string = '';
  /** 插件行操作的结果提示（核心页里的插件分区会显示） */
  @Prop pluginNotice: string = '';
  onCoreAction: (id: string) => void = () => {
  };
  onCoreSelectVersion: (version: string) => void = () => {
  };
  onTogglePluginRow: (id: string, disabled: boolean) => void = () => {
  };
  onResetPluginRowsAction: () => void = () => {
  };

  @Builder
  tabBar() {
    Scroll() {
      Row({ space: Sp.S }) {
        /*
         * 分区清单来自注册表（`settingsSections`，官方四段在前、本仓特有四项在后）。
         * 文案走 `settingsSectionLabelRes`（跟随系统语言），与侧栏入口同一套做法。
         */
        ForEach(this.sections, (d: PanelDescriptor) => {
          this.tabChip(d.id, settingsSectionLabelRes(d.id))
        }, (d: PanelDescriptor) => d.id)
      }
      .padding({ left: Sp.M, right: Sp.M })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(Sz.TOUCH_MIN)
  }

  @Builder
  tabChip(key: string, label: ResourceStr) {
    Text(label)
      .fontSize(Fs.SECONDARY)
      .fontColor(this.section === key ? Color.White : $r('sys.color.font_secondary'))
      .padding({ left: Sp.M, right: Sp.M, top: Sp.S, bottom: Sp.S })
      .borderRadius(Radius.L)
      .backgroundColor(this.section === key ? $r('sys.color.brand') : $r('sys.color.background_secondary'))
      .onClick(() => {
        this.onSelectSection(key);
      })
  }

  /**
   * 设置项的一行（P4-3：渲染归 `SettingRow` 组件，宿主只把回调转过去）。
   *
   * 【为什么留这个薄包装】通用段与预设段有多个调用点，逐个写 5 个回调转接会重复 5 行 × N 处；
   * 包装一次之后调用点仍是 `this.settingRow(item)`，改动面最小。
   */
  @Builder
  settingRow(item: SettingItem) {
    SettingRow({
      item: item,
      onToggleSetting: (key: string, value: boolean) => {
        this.onToggleSetting(key, value);
      },
      onPickChoice: (key: string, current: string) => {
        this.onPickChoice(key, current);
      },
      onEditText: (it: SettingItem) => {
        this.onEditText(it);
      },
      onEditStruct: (it: SettingItem) => {
        this.onEditStruct(it);
      },
      onResetSetting: (key: string) => {
        this.onResetSetting(key);
      }
    })
  }
  // ───────────── 通用 ─────────────


  /** 行的显示名：有官方中文措辞就用它，否则保持 Host 原文（E120） */

  /** 行的说明：官方有 description 就用官方的（如「仅影响会话内容的字号」），否则用 Host 给的 */

  /** 选项值的显示：官方译名优先（浅色/深色/跟随系统、标准/紧凑），否则回落既有标签 */



  // ───────────── 模型 ─────────────

  /** 模型页「自定义设置」展开到哪个提供方（官方：一次只展开一张卡） */
  @State expandedProvider: string = '';
  /**
   * **全部**设置分区（含被「通用」策展隐藏的 `llm-*` 等）。
   *
   * 官方 Models 页的编辑卡片直接读写提供方的设置分区（`baseURL`、模型目录…），
   * 所以模型页必须能看到这些分区；「通用」页继续用策展后的 `groups`（见 E114）。
   */
  @Prop allGroups: SettingGroup[] = [];
  /** 技能清单（E135）与读取结论：结论非空必须显示，不假装"没有技能" */
  @Prop skills: SkillRow[] = [];
  @Prop skillNote: string = '';
  /**
   * Agent 预设名单（E159/E160：`agentPresets/list` 实测形状）。
   *
   * 语义：预设 = **一个会话的 Agent 所运行的插件组装**（工具/提示词/能力）。
   * `name` / `description` 由**预设自带**（真机上就是中文），我们不自编文案；
   * `trust === 'system'` 是**随附只读**预设（官方不给复制/删除）。
   */
  @Prop presets: AgentPresetRow[] = [];
  @Prop presetNote: string = '';
  /**
   * 预设动作（E170）。**复制**是官方唯一的创建入口；**删除**只对自定义预设开放，
   * 且"随附预设不可写"由**宿主**强制（我们只是把它的原话转达给用户）。
   */
  onPresetCopy: (from: string, name: string) => void = () => {
  };
  onPresetDelete: (id: string) => void = () => {
  };
  /** 已按过一次「删除」、等待确认的预设 id（两步确认；状态留在组件内，不牵动宿主页） */
  @State confirmingPresetId: string = '';
  /** 候选提供方的搜索词（E211：对齐官方 `candidateSearch`——候选多时靠它筛） */
  @State candidateQuery: string = '';
  /**
   * 只读查看器当前展示的预设内容（E173）。
   *
   * 【为什么视图直接调中枢】查看是**纯读取**、无副作用、也不改变其它页面状态；
   * 为它再往 Index 穿一层 prop 只会增加耦合。写入类动作（复制/删除）仍走回调，
   * 因为它们要影响"下一步做什么"（例如提示语落在宿主页上）。
   */
  @State presetContent: string = '';
  /** 正在查看/已查看的预设 id（空=未查看） */
  @State presetViewedId: string = '';

  /** 提供方 → 适配器默认凭据引用（官方派生规则 `<ROUTE>_API_KEY`，见 E106） */

  /**
   * 未被任何提供方卡片覆盖的凭据引用（E157：模型页去重的关键）。
   *
   * 提供方卡片用 `<ROUTE>_API_KEY` 这一个引用；宿主还会报告别的引用
   * （例如设置命名空间里声明的槽位）。把前者已覆盖的过滤掉，
   * 用户就不会看到"同一把密钥填两次"，同时**没有任何引用被隐藏**。
   */

  /**
   * 密钥状态点的颜色语义（官方：**只有确认已配置才是绿**，**只有确认缺失才是红**，
   * 其余一律"未知"——不把未知渲染成任一种结论）。
   */

  /** `agent-*` 设置分区（E129：Agent 预设相关，官方在设置里有专门分区） */
  private agentGroups(): SettingGroup[] {
    const out: SettingGroup[] = [];
    for (let i = 0; i < this.allGroups.length; i++) {
      const g: SettingGroup = this.allGroups[i];
      if (g.title.startsWith('agent-')) {
        out.push(g);
      }
    }
    return out;
  }

  /** 提供方的设置分区（先试 `llm-<提供方首段>`，再退到通用 pi-ai 分区；找不到就返回 undefined，不猜） */
  /**
   * 目录里**尚未配置**的提供方（E181）。
   *
   * 【为什么读中枢快照而不是再加一个 prop】目录是"静态事实"，由进入设置页时触发读取
   * （`Index.selectTab` → `refreshProviderCatalog()`），读取后中枢通知、本组件随之重建；
   * 为它单独再穿一层 prop 只增加耦合，不会带来额外正确性。
   * 【已配置怎么判定】`providerGroups()` 是"宿主设置里已出现的提供方" ⇒ 从目录里减掉它们。
   */
  /**
   * 候选提供方（E211）：在 `providerCandidates()` 之上套一层**搜索过滤**。
   *
   * 对齐官方 `candidateSearch`（其候选区带搜索框与工具栏）。纯前端过滤、不涉端点；
   * 大小写不敏感，空词返回全部。
   */



  /**
   * 提供方卡片（E128：对齐官方 Models 页的形态）。
   *
   * 官方规格（`dsh-client-ui-settings-models` 的说明）：**每个已配置的提供方一行**，
   * 主字段是**单独一个 API 密钥输入框**（只写，页面从不询问环境变量名），
   * 折叠的「自定义设置」里放 `baseURL` 与**该适配器的模型目录**；
   * **推理等级刻意不在可编辑之列**（它是按模型的能力，提供方级控件只会被某些模型拒绝）。
   * 这里照此组织：状态点 + 密钥动作 + 可展开的自定义设置（直接复用设置项编辑器）。
   */


  /**
   * 适配器**默认读取**的凭据引用（E106）。
   *
   * 【为什么必须有这一行】设置里声明的槽位（`apiKey`）不是模型适配器实际查的名字：
   * 真机上按槽位写完之后，轮次仍然报
   *   `llm-deepseek: no API key for provider route "deepseek-official"; store DEEPSEEK_API_KEY …`
   * 即"界面说已配置、模型说没有密钥"。这里按"提供方 id 首段 + `_API_KEY`"给出适配器默认引用
   * （`deepseek-official` → `DEEPSEEK_API_KEY`），与官方 Models 页派生 `<ROUTE>_API_KEY` 一致；
   * 写入走同一个 `credentials/set`（真机实测该引用可写且立刻生效）。
   */

  /** 该函数原先的实现（保留在注释里，便于回退与查阅派生规则） */
  /* E158 的旧实现（providerKeyRefsLegacy）已删除：它无人调用（E228 自检发现），
     且 git 历史里查得到，不需要在代码里留一份不调用的副本。 */

  /**
   * 按提供方把模型目录分组（保持 Host 给的顺序，不重排——顺序本身是 Host 的偏好）。
   */

  /** 换模型时该带哪个推理强度：沿用当前档位（若新模型支持），否则用它的第一档，都没有则为空串 */

  private currentModelDetail(): string {
    for (let i = 0; i < this.models.length; i++) {
      const m: ModelOption = this.models[i];
      if (m.provider === this.selection.provider && m.modelId === this.selection.modelId) {
        const provider: string = m.providerName.length > 0 ? m.providerName : m.provider;
        return `${provider} · ${m.description}`;
      }
    }
    return '未在模型目录中找到该模型';
  }

  private currentEfforts(): string[] {
    for (let i = 0; i < this.models.length; i++) {
      const m: ModelOption = this.models[i];
      if (m.provider === this.selection.provider && m.modelId === this.selection.modelId) {
        return m.efforts;
      }
    }
    return [];
  }

  // ───────────── 凭据 ─────────────


  /** 凭据项的说明文字 */

  // ───────────── 插件 ─────────────

  /**
   * 单个插件的可安装性行。
   *
   * 目前**恒为 UNKNOWN**：上游 `pluginInventory.list` 不提供"是否含原生模块"这一信息。
   * 这是**记录事实**而不是偷懒——等能读到插件包清单（package.json / 是否存在 .node）后，
   * 再把真实取值传进来即可，界面与契约都不用改。
   */

  /**
   * 插件分区（E114 对齐官方：官方在这里分**配置**与**列表**两个子页签）。
   *
   * 【为什么分】两者回答的问题不同、风险也不同：
   *   - **配置**：我要改什么（启停 + 恢复部署默认）——写操作，改动会影响运行；
   *   - **列表**：这里到底有什么（只读清单 + 过滤）——查证用，152 行时不加过滤根本找不到东西。
   * 官方把只读清单单独成页，正是为了让"看一眼清单"不必冒误触的风险。
   */
  @Builder
  pluginsTab() {
    /*
     * 摘要行与卡片都归 `SettingsPlugins`。
     *
     * 【顺带修掉的一处重复】此前这里画了一行摘要、组件里又画了一行（同一句话出现两次）——
     * 抽取组件时才发现：**"这段内容到底归谁"写清楚之后，重复自己就露出来了**。
     */
    SettingsPlugins({ plugins: this.plugins })
  }

  /** 只读清单 + 关键词过滤（官方"插件列表"标签页的语义） */

  /** 关键词过滤后的插件清单（空关键词 = 全部） */


  // ───────────── 设备 ─────────────


}
