/**
 * 设置页（T024：对照 `dshmobile/ui/screens/settings/SettingsScreen.kt` 复刻本文件拥有的部分）。
 *
 * ## 对照结构（SettingsScreen.kt）
 *
 * 源码是一条滚动长页：`SettingsCard`（`SectionHeader` + `bgLayer1` r12 卡体）分节成卡。
 * 本仓的设置页是**注册表驱动的分区页**（`sections` + `section`，唯一真值在
 * `NavigationState.settingsSection`）——分区内容归各域组件渲染（通用/模型/预设/技能/
 * 核心/插件/设备），它们不在本任务领地；本文件拥有并重塑的是三块：
 *   ① **分区切换条**——选中语言对照源码 `AppearanceChip`（选中 = `accentTertiary` 底 +
 *      `accent` 字，r16；未选 = `bgModulePlatform` 底 + `labelSecondary` 字）；
 *   ② **写入回执面**——容器语言对照源码"横幅/通知面"（`bgLayer1` r12 面 +
 *      `small13` `labelSecondary`）；
 *   ③ **内容滚动列**——内距对照源码页面（水平 `comfortable`、块距 `comfortable`）。
 *
 * ## 页签与源码的取舍（如实记录）
 *
 * 源码设置页没有分区页签（单页滚动、卡即分区）；本仓的分区是**导航状态**（深链/返回
 * 都依赖它，见 `section` 的注释），改成单页会改掉导航契约——保留页签条，只换它的视觉。
 *
 * ## 规格要点（保留 v1）
 *   - 每个设置项都带**说明文字**（D3 §4 文案纪律：不能只有名字）；
 *   - 凭据**只呈现状态，绝不含明文值**（D1 §11.5 S3/S4）；
 *   - 写入回执只在"属于当前分区"时显示（E347，域判不出来时宁可显示）。
 */

import {
  AboutInfo,
  AgentPresetRow,
  CredentialItem,
  DsPalette,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  HarmonyBorder,
  HostRecord,
  ModelOption,
  ModelSelection,
  PluginItem,
  RunMode,
  SettingGroup,
  SettingItem,
  SkillRow,
  dsPaletteOf,
  emptyCoreView,
  settingsSectionLabelRes,
} from 'appstate';
import type { CoreViewState, PanelDescriptor } from 'appstate';
import { installDsSystemDarkWatch } from './NativePrimitives';
import { SettingsGeneral } from './SettingsGeneral';
import { SettingsDevice } from './SettingsDevice';
import { SettingsModels } from './SettingsModels';
import { SettingsPlugins } from './SettingsPlugins';
import { SettingsPresets } from './SettingsPresets';
import { SettingsSkills } from './SettingsSkills';
import { SettingsCore } from './SettingsCore';

/* ───────── 组件级度量（SettingsScreen.kt 的 dp 字面量，逐条标注出处） ───────── */

/** SettingsScreen.kt `AppearanceChip`：水平内距 14dp */
const SETTINGS_CHIP_PAD_H: number = 14;
/** 等宽/系统字体栈（Type.kt system UI stack） */
const SETTINGS_FONT_SANS: string = 'sans-serif';

/** 设置面板（E108/E110/E114/E120） */
@Component
export struct SettingsPane {
  /** 宿主报告的权限组合（E124；空串=未投影，界面不显示要切换的假档位） */
  @Prop permissionCurrent: string = '';
  @Prop permissionOptions: string[] = [];

  /** §FR-058：当前运行模式 */
  @Prop runMode: RunMode = RunMode.LOCAL;

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
  /**
   * 这条回执**属于哪个分区**（E347：空串 = 判不出来 ⇒ 照常显示）。
   *
   * 【为什么必须带域】写入回执原本是一个全局字符串，而它唯一的读取点在这里。
   * 于是"在通用改了外观、切到模型"会让那条回执还挂在模型页上方——看起来像模型页
   * 刚写出来的结果（失败回执更糟：像是**这一页**的操作被拒了）。界面不该这样撒谎。
   * 域由 key 的命名空间判定（`settingsDomainOfNs`，纯函数、有 fixture）；
   * 判不出来时**宁可显示**——隐藏一条用户正需要的失败回执，比多显示一条更糟。
   */
  @Prop writeDomain: string = '';
  /** 各命名空间的写状态（仅用于诊断显示 revision） */

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
  /** §FR-058：切换运行模式 */
  onSwitchRunMode: (mode: RunMode) => void = () => {
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

  /**
   * 核心分区（E110/E118：原「核心」一级页签并入这里）。
   *
   * 【为什么不用 `@BuilderParam` 注入】原先由宿主注入一个 `@Builder`（`coreSlot`），
   * 真机上点开「核心」分区**直接 JS 崩溃**（`AppKilledReporter: reason: JsError`）。
   * 改为把 `CorePane` 需要的属性直接传进来：数据流一眼能看完，
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

  /**
   * **全部**设置分区（含被「通用」策展隐藏的 `llm-*` 等）。
   *
   * 官方 Models 页的编辑卡片直接读写提供方的设置分区（`baseURL`、模型目录…），
   * 所以模型页必须能看到这些分区；「通用」页继续用策展后的 `groups`（见 E114）。
   * 预设段（`SettingsPresets`）吃的是同一份"全部"——`agent-*` 分区同样不在策展结果里。
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
   *
   * 三个临时态（两步确认 / 只读查看的 id 与内容）**不在本组件**：它们随预设段
   * 一起归 `SettingsPresets`（P4-5）——一次交互内的临时态不该跨段落存活。
   */
  onPresetCopy: (from: string, name: string) => void = () => {
  };
  onPresetDelete: (id: string) => void = () => {
  };

  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Column() {
      this.tabBar()

      // 写入结果回显：成功 / 冲突 / 被拒 / 本机偏好都走这里。
      // 不做乐观更新，所以这里是用户唯一能看到「Host 到底接受了没有」的地方。
      //
      // 【只在"这条回执属于当前分区"时显示】否则切分区会把上一段的回执带过来，
      // 看起来像当前分区刚写出来的结果（域判不出来时空串 ⇒ 照常显示，见 writeDomain）。
      if (this.writeNote.length > 0 && (this.writeDomain.length === 0 || this.writeDomain === this.section)) {
        Text(this.writeNote)
          .fontSize(DsType.SMALL_13.size)
          .lineHeight(DsType.SMALL_13.lineHeight)
          .fontWeight(DsType.SMALL_13.weight)
          .fontFamily(SETTINGS_FONT_SANS)
          .fontColor(this.palette().labelSecondary)
          .width('100%')
          .padding(DsSpacing.MEDIUM)
          .borderRadius(DsShape.BLOCK)
          .backgroundColor(this.palette().bgLayer1)
          .borderWidth(HarmonyBorder.HAIRLINE)
          .borderColor(this.palette().borderL2)
      }

      Scroll() {
        Column({ space: DsSpacing.COMFORTABLE }) {
          if (this.section === 'settings.skills') {
            // 技能段归 SettingsSkills（P4-5 拆出的域组件）：它只吃清单 + 读取结论两个 prop，
            // 没有任何写入动作与组件内状态——「读不到就说读不到」的判定留在数据层（E135）。
            SettingsSkills({
              skills: this.skills,
              note: this.skillNote
            })
          } else if (this.section === 'settings.presets') {
            // 预设段归 SettingsPresets（P4-5 拆出的域组件）：两半（名单卡片 + agent-* 编辑器）、
            // 三个组件内临时态（两步确认 / 只读查看）与「查看」的中枢直读都随之搬走。
            SettingsPresets({
              presets: this.presets,
              note: this.presetNote,
              allGroups: this.allGroups,
              onCopy: (from: string, name: string) => {
                this.onPresetCopy(from, name);
              },
              onDelete: (id: string) => {
                this.onPresetDelete(id);
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
          } else if (this.section === 'settings.core') {
            // 核心段归 SettingsCore（P4-6 拆出的域组件）：它包住 `CorePane` 并承载两块提示。
            // 不用 `@BuilderParam` 注入（E118：真机上点开这一分区会 JS 崩溃）——属性直传。
            SettingsCore({
              view: this.coreView,
              notice: this.coreNotice,
              pluginNotice: this.pluginNotice,
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
              }
            })
          } else if (this.section === 'settings.general') {
            // 通用段归 SettingsGeneral（P4-4 拆出的域组件）
            SettingsGeneral({
              groups: this.groups,
              permissionCurrent: this.permissionCurrent,
              permissionOptions: this.permissionOptions,
              runMode: this.runMode,
              onOpenDiagnostics: () => {
                this.onOpenDiagnostics();
              },
              onSwitchRunMode: (mode: RunMode) => {
                this.onSwitchRunMode(mode);
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
        .padding(DsSpacing.MEDIUM)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }

  /** 分区切换条（保留 v1 的注册表驱动 + 横向滚动；选中语言对照 AppearanceChip） */
  @Builder
  tabBar() {
    Scroll() {
      Row({ space: DsSpacing.SMALL }) {
        /*
         * 分区清单来自注册表（`settingsSections`，官方四段在前、本仓特有四项在后）。
         * 文案走 `settingsSectionLabelRes`（跟随系统语言），与侧栏入口同一套做法。
         */
        ForEach(this.sections, (d: PanelDescriptor) => {
          this.tabChip(d.id, settingsSectionLabelRes(d.id))
        }, (d: PanelDescriptor) => d.id)
      }
      .padding({ left: DsSpacing.MEDIUM, right: DsSpacing.MEDIUM })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .constraintSize({ minHeight: DsSpacing.TOUCH_TARGET })
  }

  /**
   * 一个分区 chip（对照 SettingsScreen.kt `AppearanceChip`：选中 = accentTertiary 底 +
   * accent 字 + r16；未选 = bgModulePlatform 底 + labelSecondary 字 + r16；
   * 水平内距 14dp、垂直内距 small）。
   */
  @Builder
  tabChip(key: string, label: ResourceStr) {
    Text(label)
      .fontSize(DsType.SMALL_13.size)
      .lineHeight(DsType.SMALL_13.lineHeight)
      .fontWeight(DsType.SMALL_13.weight)
      .fontFamily(SETTINGS_FONT_SANS)
      .fontColor(this.section === key ? this.palette().accent : this.palette().labelSecondary)
      .padding({
        left: SETTINGS_CHIP_PAD_H,
        right: SETTINGS_CHIP_PAD_H,
        top: DsSpacing.SMALL,
        bottom: DsSpacing.SMALL
      })
      .borderRadius(DsShape.CUBE)
      .backgroundColor(this.section === key
        ? this.palette().accentTertiary : this.palette().bgModulePlatform)
      .onClick(() => {
        this.onSelectSection(key);
      })
      .accessibilityText(this.section === key ? `${label}，已选中` : `${label}`)
  }

  /*
   * 【曾经的 `settingRow` 薄包装已删除】P4-3 抽 `SettingRow` 组件时，宿主留了它把 5 个回调转过去
   * （当时通用段与预设段有多个调用点）。P4-5 把那两段搬进 `SettingsSkills`/`SettingsPresets` 之后，
   * **它一个调用点都没有了**——而它的文档还写着"多个调用点"，读者会以为这里还在用。
   * 由 E350 的死代码门禁查出并删除；`SettingRow` 的导入也随之摘掉。
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
}
