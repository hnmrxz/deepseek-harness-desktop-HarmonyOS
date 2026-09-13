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
  modelSelectionLabel,
  pluginSummary,
  PluginItem,
  // 插件可安装性三态契约（D6 §6.2）：不把"未知"渲染成"可安装"
  PluginNative,
  PluginRow,
  classifyPlugin,
  Radius,
  SettingGroup,
  SettingItem,
  SettingKind,
  SettingOrigin,
  SkillRow,
  splitSettingKey,
  Sp,
  Sz
} from 'appstate';
import type { CoreViewState, SettingsNamespaceState } from 'appstate';
import { CorePane } from './CorePane';

/**
 * 选择项的显示文案：优先用选项自带的显示名，找不到就回退到取值本身。
 *
 * 上游实测**没有**枚举显示名（`const.value` 就是取值），所以 `label` 与
 * `value` 目前相同；但契约里两者是分开的，界面按「优先 label」渲染，
 * 将来上游补上显示名时不需要改这里。
 */
function choiceLabel(item: SettingItem): string {
  for (let i = 0; i < item.choices.length; i++) {
    if (item.choices[i].value === item.textValue) {
      return item.choices[i].label;
    }
  }
  return item.textValue.length > 0 ? item.textValue : '未设置';
}

/**
 * 凭据项右侧的动作文案（模块级纯函数）。
 *
 * 三种情况都必须给出**明确**的一个词，不留空白：
 *   - 线协议支持交互式授权（当前实测没有这个字段，恒为 false）→ 授权/重新授权；
 *   - 只读来源（`writable === false`）→ 「只读」；
 *   - 其余可写项 → 配置/更换（走 `credentials/set`）。
 *
 * 【为什么以前这里是空白】更早的实现只渲染 `interactive` 分支，而线协议里
 * **没有**「是否支持交互式授权」这个字段（`projectCredentials` 因此一律置 false）——
 * 于是每一项既没有按钮也没有说明，用户看到的是「凭据页什么都做不了」。
 *
 * 【为什么是模块级纯函数而不是 struct 方法】实测：写成 struct 方法时，
 * `configured` 变化后 `ForEach` 内的行**不重新求值**（诊断输出显示组件已收到
 * `cfg=true`，按钮文字却仍是「配置」）。同文件里的 `choiceLabel()` 是模块级纯函数、
 * 工作正常。**在 `@Builder` 内联表达式里调用 struct 方法不可靠**——
 * 依赖追踪没有覆盖到方法体内部读的字段。
 * 这与「条件渲染各分支结构相同时会被复用」是同一类问题的两种表现：
 * ArkUI 只在它**看得见的**表达式上建立依赖。
 */
function credentialActionLabel(c: CredentialItem): string {
  if (c.interactive) {
    return c.configured ? '重新授权' : '授权';
  }
  if (!c.writable) {
    return '只读';
  }
  return c.configured ? '更换' : '配置';
}

/**
 * `ForEach` 的行 key。
 *
 * 【为什么不是 `c.ref`】实测：只用 `ref` 作 key 时，`credentials/describe` 回读到
 * `configured` 从 true 变成 false，界面上的按钮文案**仍是「更换」**
 * （诊断输出同时显示组件已收到 `cfg=false`——数据对了，行没重建）。
 * `ref` 在这种变化下**没有变**，于是 ArkUI 认为这一行没变，直接复用了旧节点。
 *
 * 把**影响这一行渲染的字段**都编进 key，等于告诉 ArkUI「这些值变了就要重建」
 * （这里的代价可以忽略：凭据项是个位数量级，重建一行没有可感开销）。
 * 一般化的教训：`ForEach` 的 key 必须覆盖该行的**全部渲染输入**，
 * 只用「业务主键」在数据可变时会得到静默的旧界面。
 */
function credentialRowKey(c: CredentialItem): string {
  return `${c.ref}|${c.configured}|${c.writable}|${c.interactive}|${c.source}`;
}

/**
 * 模型目录按提供方分组后的一组（E96）。
 *
 * 【为什么要有这个类型】官方 Models 页以"提供方"为单位组织（密钥、端点、模型清单都挂它上面）；
 * 拉平成一个模型列表就看不出"这个模型要用哪把密钥"。
 */
export interface ModelProviderGroup {
  provider: string;
  providerName: string;
  models: ModelOption[];
}

/**
 * 设置项的**官方中文措辞**（E120）。
 *
 * 【为什么需要一张表】设置项的 label / 选项值是 **Host 给的**（真机上是英文：
 * `Preference` / `Font size` / `Busy enter` / `Transcript view`，选项 `system` / `compact`），
 * 而官方 web 显示的是它自己内嵌的中文文案。用户要求"设置-通用里默认中文、措辞与官方一致"，
 * 所以这里按 `命名空间.键` 覆盖成官方译名——文案取自官方客户端包内嵌的 locale 表
 * （`dsh-client-ui-theme/lib/client.js` 的 `"appearance.title": "外观"` 等，同一批还给了
 * 选项值「浅色/深色/跟随系统」「字号大小」「语言」「对话显示/标准/紧凑」）。
 * 覆盖不到的键**保持 Host 原文**：宁可显示英文，也不自创一个官方没有的说法。
 */
function officialSettingLabel(ns: string, key: string): string {
  if (ns === 'ui-theme' && key === 'preference') {
    return '外观';
  }
  if (ns === 'ui-theme' && key === 'fontSize') {
    return '字号大小';
  }
  if (ns === 'locale' && key === 'preference') {
    return '语言';
  }
  if (ns === 'ui-chat' && key === 'transcriptView') {
    return '对话显示';
  }
  if (ns === 'ui-conversation' && key === 'busyEnter') {
    return '回车键行为';
  }
  if (ns === 'ui-onboarding' && key === 'welcomeNoticeVersion') {
    return '欢迎提示版本';
  }
  /*
   * E155（用户反馈③）：**预设分区**此前直接显示宿主给的英文键，中文界面里很突兀。
   * 键名取自真机截图（`agent-default-model` / `agent-loop` / `agent-presets`）。
   */
  if (ns === 'agent-default-model' && key === 'provider') {
    return '提供方';
  }
  if (ns === 'agent-default-model' && key === 'model') {
    return '模型';
  }
  if (ns === 'agent-default-model' && key === 'reasoningEffort') {
    return '推理强度';
  }
  if (ns === 'agent-loop' && key === 'maxParallelToolCalls') {
    return '最大并行工具调用数';
  }
  if (ns === 'agent-presets' && key === 'default') {
    return '默认预设';
  }
  if (ns === 'subagent-model-selection' && key === 'enabled') {
    return '允许子代理选模型';
  }
  if (ns === 'subagent-model-selection' && key === 'allowedModels') {
    return '允许的模型';
  }
  return '';
}

/** 官方对**选项值**的中文措辞（取不到就返回空串，由调用方回落原值） */
function officialSettingValue(ns: string, key: string, value: string): string {
  if (ns === 'ui-theme' && key === 'preference') {
    if (value === 'light') {
      return '浅色';
    }
    if (value === 'dark') {
      return '深色';
    }
    if (value === 'system') {
      return '跟随系统';
    }
  }
  if (ns === 'ui-chat' && key === 'transcriptView') {
    if (value === 'normal') {
      return '标准';
    }
    if (value === 'compact') {
      return '紧凑';
    }
  }
  return '';
}

/** 官方对**说明文字**的中文措辞（同上，取不到返回空串） */
function officialSettingHint(ns: string, key: string): string {
  if (ns === 'ui-theme' && key === 'fontSize') {
    return '仅影响会话内容的字号';
  }
  if (ns === 'ui-chat' && key === 'transcriptView') {
    return '控制已完成轮次的过程内容';
  }
  return '';
}

/** 访问模式的中文名（官方译名，取自 `dsh-client-ui-permission-presets` 的 README） */
function permissionModeLabel(value: string): string {
  if (value === 'read-only') {
    return '仅可查看';
  }
  if (value === 'workspace-write') {
    return '工作区内修改';
  }
  if (value === 'danger-full-access') {
    return '完全权限';
  }
  return value;
}

/** 设置面板（E108/E110/E114/E120） */
@Component
export struct SettingsPane {
  /** 宿主报告的权限组合（E124；空串=未投影，界面不显示要切换的假档位） */
  @Prop permissionCurrent: string = '';
  @Prop permissionOptions: string[] = [];

  /** 插件分区子页签（E114：配置 / 列表） */
  @State pluginView: string = 'config';
  /** 插件清单的过滤词（只作用于「列表」子页签） */
  @State pluginFilter: string = '';

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

  @State tab: string = 'general';

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
          if (this.tab === 'skills') {
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
          } else if (this.tab === 'preset') {
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
          } else if (this.tab === 'core') {
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
          } else if (this.tab === 'general') {
            this.generalTab()
          } else if (this.tab === 'model') {
            this.modelTab()
          } else if (this.tab === 'plugins') {
            this.pluginsTab()
          } else {
            this.deviceTab()
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
        // E110：核心（版本/插件/运行时事实）作为设置的一项——它与"这台设备怎么跑"同类
        // E114 顺序对齐官方：官方「通用」是第一个分区，因此通用排在最前
        // E117：分区名走资源（默认中文，英文系统读 en_US）
        this.tabChip('general', $r('app.string.settings_general'))
        // 官方分区就叫「模型」（API 密钥是该分区里的字段，不另立分区）
        this.tabChip('model', $r('app.string.settings_models'))
        this.tabChip('plugins', $r('app.string.settings_plugins'))
        this.tabChip('core', $r('app.string.settings_core'))
        // E129：Agent 预设分区（官方把它放在设置里，用于管理名单与设默认）
        this.tabChip('preset', '预设')
        // E135：技能（官方为 dsh-skill + dsh-client-ui-skill；我们的兼容面已有 skills/list）
        this.tabChip('skills', '技能')
        this.tabChip('device', $r('app.string.settings_device'))
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
      .fontColor(this.tab === key ? Color.White : $r('sys.color.font_secondary'))
      .padding({ left: Sp.M, right: Sp.M, top: Sp.S, bottom: Sp.S })
      .borderRadius(Radius.L)
      .backgroundColor(this.tab === key ? $r('sys.color.brand') : $r('sys.color.background_secondary'))
      .onClick(() => {
        this.tab = key;
      })
  }

  // ───────────── 通用 ─────────────

  @Builder
  generalTab() {
    /*
     * 【权限模式：只读说明，不给假档位（E116）】
     *
     * 官方在这三个标签下提供可切换的预设（仅可查看 / 工作区内修改 / 完全权限），
     * 但端侧**实测**：启用 `dsh-permission-presets` 会让整棵插件树启动失败——
     * 它需要 `shell` 服务，而 shell 只能由 bash/pwsh 沙箱提供，两者在鸿蒙上没有对应物
     * （无法创建进程，E15）。官方规则也写明"宿主没有权限组合时，选择器与设置行都不显示"。
     *
     * 于是这里既**不隐藏**（用户明确问过这三档，藏起来等于让他以为没有这个概念），
     * 也**不给可点的假档位**：只读地说明当前生效的是什么、另外两档为什么不可选。
     */
    Column({ space: 2 }) {
      Row({ space: Sp.XS }) {
        Text('权限模式')
          .fontSize(Fs.BODY)
        Text(this.permissionCurrent.length > 0 ? '宿主报告' : '未报告')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .borderRadius(Radius.S)
          .backgroundColor($r('sys.color.background_primary'))
      }
      .width('100%')
      // E124：显示**宿主真正报告的**当前模式（此前这里是我写死的字符串）
      Text(this.permissionCurrent.length > 0
        ? `${permissionModeLabel(this.permissionCurrent)}（${this.permissionCurrent}）`
        : '宿主暂未报告当前访问模式')
        .fontSize(Fs.SECONDARY)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      if (this.permissionOptions.length > 0) {
        Text(`宿主给出的可选集合：${this.permissionOptions.map((v: string) => permissionModeLabel(v)).join(' / ')}`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
      Text('端侧暂不可切换：把这几档捆绑成可切换预设的插件需要 shell 服务，而鸿蒙不允许应用创建进程（E15）。这里显示的是宿主当前生效的访问模式。')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))

    ForEach(this.groups, (group: SettingGroup) => {
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

    this.diagnosticsEntry()
  }

  /** 行的显示名：有官方中文措辞就用它，否则保持 Host 原文（E120） */
  private labelOf(item: SettingItem): string {
    const parts = splitSettingKey(item.key);
    if (parts === undefined) {
      return item.label;
    }
    const official: string = officialSettingLabel(parts.ns, parts.fieldPath);
    return official.length > 0 ? official : item.label;
  }

  /** 行的说明：官方有 description 就用官方的（如「仅影响会话内容的字号」），否则用 Host 给的 */
  private hintOf(item: SettingItem): string {
    const parts = splitSettingKey(item.key);
    if (parts !== undefined) {
      const official: string = officialSettingHint(parts.ns, parts.fieldPath);
      if (official.length > 0) {
        return `${official} · ${item.hint}`;
      }
    }
    return item.hint;
  }

  /** 选项值的显示：官方译名优先（浅色/深色/跟随系统、标准/紧凑），否则回落既有标签 */
  private valueLabelOf(item: SettingItem): string {
    const parts = splitSettingKey(item.key);
    if (parts !== undefined) {
      const official: string = officialSettingValue(parts.ns, parts.fieldPath, item.textValue);
      if (official.length > 0) {
        return official;
      }
    }
    return choiceLabel(item);
  }

  @Builder
  settingRow(item: SettingItem) {
    Row({ space: Sp.M }) {
      Column({ space: 2 }) {
        Row({ space: Sp.XS }) {
          Text(this.labelOf(item))
            .fontSize(Fs.BODY)
          // 【来源标记是必需信息，不是装饰】本客户端的通知 / 离线缓存等偏好
          // 在上游根本没有对应命名空间；不标出来，用户会以为改它也会影响 Host。
          if (item.origin === SettingOrigin.LOCAL) {
            Text('本机')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(Radius.S)
              .backgroundColor($r('sys.color.background_primary'))
          }
          // 实测 value 是「默认 → 基线 → 用户层」三层合并的结果，
          // 只看 value 无法区分「继承默认」与「用户设成了同一个值」。
          // E114 对齐官方：官方在这一行标明"用户覆盖过哪些值"，并允许**重置为部署默认**。
          if (item.userSet) {
            Text($r('app.string.badge_overridden'))
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.brand'))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(Radius.S)
              .backgroundColor($r('sys.color.background_primary'))
          } else {
            Text($r('app.string.badge_default'))
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(Radius.S)
              .backgroundColor($r('sys.color.background_primary'))
          }
        }
        .width('100%')

        Text(this.hintOf(item))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        // `applies: 'restart'` 的命名空间改完需要重启 Host 才生效。
        // 不提示就是骗用户「已经生效了」。
        if (!item.appliesLive) {
          Text('需重启 Host 后生效')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.warning'))
            .width('100%')
        }

        // 不可编辑的原因必须说清楚，而且**两种原因文案不同**：
        //   - Host 不接受写 → 是权限/来源问题，用户无从改变；
        //   - 本客户端还没做该形态的编辑器 → 是我们的功能缺口，不是 Host 的限制。
        // 把后者写成前者会误导用户去 Host 上找权限开关。
        if (item.readOnly) {
          Text(item.hostWritable ? '此形态暂不支持在本客户端编辑（只读展示）' : 'Host 不接受对此项写入')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
      }
      .layoutWeight(1)

      // 重置为部署默认（只对"已覆盖"的项出现，见 `onResetSetting` 的说明）
      if (item.userSet && item.hostWritable && !item.readOnly) {
        Text($r('app.string.action_reset'))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.onResetSetting(item.key);
          })
      }

      if (item.kind === SettingKind.TOGGLE) {
        Toggle({ type: ToggleType.Switch, isOn: item.boolValue })
          .enabled(!item.readOnly)
          .onChange((on: boolean) => {
            this.onToggleSetting(item.key, on);
          })
      } else if (item.kind === SettingKind.CHOICE) {
        Text(this.valueLabelOf(item))
          .fontSize(Fs.SECONDARY)
          .fontColor(item.readOnly ? $r('sys.color.font_tertiary') : $r('sys.color.brand'))
          .onClick(() => {
            if (!item.readOnly) {
              this.onPickChoice(item.key, item.textValue);
            }
          })
      } else if (item.kind === SettingKind.STRUCT) {
        // 结构化值（数组 / 嵌套对象 / 复杂 union）：整值编辑。
        // 与 TEXT 一样**必须可点**——不可点的控件等于没有这个功能。
        Text(item.textValue)
          .fontSize(Fs.SECONDARY)
          .fontColor(item.readOnly ? ('sys.color.font_tertiary') : ('sys.color.brand'))
          .maxLines(1)
          .constraintSize({ maxWidth: 160 })
          .onClick(() => {
            if (!item.readOnly) {
              this.onEditStruct(item);
            }
          })
      } else {
        // TEXT（字符串 / 数字）：**必须可点**才有编辑入口。
        // 曾经这里只是一个带 `.maxLines(1)` 的静态 `Text`——数据与 kind 都对，
        // 但没有任何点击处理，于是「文本/数字项可编辑」这件事**只存在于代码里**，
        // 界面上看不出可以点（UI 导出里该节点没有 clickable 标记）。
        // 一个不可点的控件等于没有这个功能。
        Text(item.textValue.length > 0 ? item.textValue : '未设置')
          .fontSize(Fs.SECONDARY)
          .fontColor(item.readOnly ? $r('sys.color.font_tertiary') : $r('sys.color.brand'))
          .maxLines(1)
          .constraintSize({ maxWidth: 160 })
          .onClick(() => {
            if (!item.readOnly) {
              this.onEditText(item);
            }
          })
      }
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .accessibilityText(`${item.label}。${item.hint}`)
  }

  @Builder
  diagnosticsEntry() {
    Row({ space: Sp.S }) {
      SymbolGlyph($r('sys.symbol.bell')).fontSize(16)
        .fontColor([$r('sys.color.brand')])
      Column({ space: 2 }) {
        // 原「连接诊断」与「POC 协议验证」合并（E96）：它们都在回答"这台设备上的核心通不通"，
        // 一个给结论、一个给逐步证据；进同一个页面就能从结论下钻到证据。
        Text('本地调试')
          .fontSize(Fs.BODY)
          .width('100%')
        Text('连接诊断（五项判定）+ 协议往返验证（token → cookie → /api → WS 逐步证据）')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
      .layoutWeight(1)
      Text('进入')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.brand'))
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .onClick(() => {
      this.onOpenDiagnostics();
    })
  }

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

  /** 提供方 → 适配器默认凭据引用（官方派生规则 `<ROUTE>_API_KEY`，见 E106） */
  private providerKeyRefOf(provider: string): string {
    const head: string = provider.split('-')[0];
    return `${head.toUpperCase()}_API_KEY`;
  }

  /**
   * 密钥状态点的颜色语义（官方：**只有确认已配置才是绿**，**只有确认缺失才是红**，
   * 其余一律"未知"——不把未知渲染成任一种结论）。
   */
  private providerKeyColor(provider: string): Resource {
    const ref: string = this.providerKeyRefOf(provider);
    for (let i = 0; i < this.credentials.length; i++) {
      const c: CredentialItem = this.credentials[i];
      if (c.ref === ref) {
        return c.configured ? $r('sys.color.confirm') : $r('sys.color.alert');
      }
    }
    return $r('sys.color.font_tertiary');
  }

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
  private providerSettingGroup(provider: string): SettingGroup | undefined {
    const head: string = provider.split('-')[0];
    const candidates: string[] = [`llm-${head}`, 'llm-pi-ai'];
    for (let i = 0; i < candidates.length; i++) {
      for (let j = 0; j < this.allGroups.length; j++) {
        if (this.allGroups[j].title === candidates[i]) {
          return this.allGroups[j];
        }
      }
    }
    return undefined;
  }

  /**
   * 提供方卡片（E128：对齐官方 Models 页的形态）。
   *
   * 官方规格（`dsh-client-ui-settings-models` 的说明）：**每个已配置的提供方一行**，
   * 主字段是**单独一个 API 密钥输入框**（只写，页面从不询问环境变量名），
   * 折叠的「自定义设置」里放 `baseURL` 与**该适配器的模型目录**；
   * **推理等级刻意不在可编辑之列**（它是按模型的能力，提供方级控件只会被某些模型拒绝）。
   * 这里照此组织：状态点 + 密钥动作 + 可展开的自定义设置（直接复用设置项编辑器）。
   */
  @Builder
  providerCards() {
    Text('提供方')
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')

    ForEach(this.providerGroups(), (g: ModelProviderGroup) => {
      Column({ space: Sp.XS }) {
        Row({ space: Sp.S }) {
          Circle({ width: 8, height: 8 })
            .fill(this.providerKeyColor(g.provider))
          Column({ space: 2 }) {
            Text(g.providerName.length > 0 ? g.providerName : g.provider)
              .fontSize(Fs.BODY)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${g.provider} · ${g.models.length} 个模型`)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          Text('配置密钥')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              this.onAuthorizeCredential(this.providerKeyRefOf(g.provider));
            })
        }
        .width('100%')

        Row({ space: Sp.XS }) {
          Text('自定义设置')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_secondary'))
          Blank()
          Text(this.expandedProvider === g.provider ? '收起' : '展开')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
        }
        .width('100%')
        .onClick(() => {
          this.expandedProvider = this.expandedProvider === g.provider ? '' : g.provider;
        })

        if (this.expandedProvider === g.provider) {
          if (this.providerSettingGroup(g.provider) === undefined) {
            Text('宿主没有为这个提供方暴露可编辑的设置分区——端侧只显示它确实报告的东西，不造一个空编辑器。')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          } else {
            ForEach((this.providerSettingGroup(g.provider) as SettingGroup).items, (item: SettingItem) => {
              this.settingRow(item)
            }, (item: SettingItem) => item.key)
          }
          Text('推理等级属于**模型的能力**，官方也不在提供方级编辑（会被部分模型拒绝）；请在下面「新会话默认」里按模型选择。')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
    }, (g: ModelProviderGroup) => g.provider)
  }

  @Builder
  modelTab() {
    /*
     * E128：先按官方形态列出**提供方卡片**（状态点 + 首要的密钥动作 + 可展开的自定义设置），
     * 下面的「模型凭据」「新会话默认」「全部模型」是我们已有的补充信息，保持向后兼容。
     */
    this.providerCards()

    /*
     * 【为什么模型页要带"凭据"区（E96）】官方 Models 页把 **API 密钥**放在编辑卡片的
     * 首要位置（见 `dsh-client-ui-settings-models` 的说明：密钥是每个提供方第一件要配的事，
     * 且只写不读）。而我们的模型页此前只有"选哪个模型"，用户看到"当前模型"却不知道
     * "这个模型现在根本调不通，因为没配密钥"——能力与前置条件分居两页，是最容易让人卡住的地方。
     * 所以这里把可写的凭据引用直接列在模型页顶部，配置动作与「凭据」页共用同一条通道。
     */
    Column({ space: Sp.XS }) {
      Text('模型凭据')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      if (this.credentials.length === 0) {
        Text('Host 没有报告任何凭据引用')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding(Sp.M)
          .borderRadius(Radius.M)
          .backgroundColor($r('sys.color.background_secondary'))
      } else {
        ForEach(this.credentials, (c: CredentialItem) => {
          Row({ space: Sp.M }) {
            SymbolGlyph(c.configured ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_triangle'))
              .fontSize(16)
              .fontColor([c.configured ? $r('sys.color.confirm') : $r('sys.color.warning')])
            Column({ space: 2 }) {
              Text(c.ref)
                .fontSize(Fs.SECONDARY)
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.credentialHint(c))
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            Text(credentialActionLabel(c))
              .fontSize(Fs.CAPTION)
              .fontColor(c.writable ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
              .onClick(() => {
                if (c.writable && !c.interactive) {
                  this.onAuthorizeCredential(c.ref);
                }
              })
          }
          .width('100%')
          .padding(Sp.M)
          .borderRadius(Radius.M)
          .backgroundColor($r('sys.color.background_secondary'))
        }, (c: CredentialItem) => credentialRowKey(c))
      }
      /*
       * 【适配器默认读取的引用（E106，真机踩到）】设置里声明的槽位（`apiKey`）**不是**模型适配器
       * 实际读取的名字：DeepSeek 适配器查的是 `DEEPSEEK_API_KEY`。只按槽位写，界面显示"已配置"，
       * 而模型调用仍然报 `MISSING_CREDENTIAL`（用户看到的仍是"发消息没回复"）。
       * 这里按"提供方 id 的首段 + _API_KEY"给出适配器默认引用（deepseek-official → DEEPSEEK_API_KEY），
       * 与官方 Models 页派生 `<ROUTE>_API_KEY` 的做法一致；写入仍走同一个 `credentials/set`。
       */
      ForEach(this.providerKeyRefs(), (ref: string) => {
        Row({ space: Sp.M }) {
          SymbolGlyph($r('sys.symbol.key')).fontSize(16)
            .fontColor([$r('sys.color.brand')])
          Column({ space: 2 }) {
            Text(ref)
              .fontSize(Fs.SECONDARY)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('模型适配器默认读取的引用（Host 报 MISSING_CREDENTIAL 时说的就是它）')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
              .maxLines(2)
          }
          .layoutWeight(1)
          Text('配置')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              this.onAuthorizeCredential(ref);
            })
        }
        .width('100%')
        .padding(Sp.M)
        .borderRadius(Radius.M)
        .backgroundColor($r('sys.color.background_secondary'))
      }, (ref: string) => ref)
    }
    .width('100%')

    Column({ space: Sp.XS }) {
      Text('当前模型（Host 的默认选择）')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      Row({ space: Sp.S }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(16)
          .fontColor([$r('sys.color.brand')])
        Column({ space: 2 }) {
          Text(modelSelectionLabel(this.selection, this.models))
            .fontSize(Fs.BODY)
            .width('100%')
          Text(this.currentModelDetail())
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
      // 【为什么这里没有"切换"按钮（E96）】官方把"选哪个模型"放在**会话输入区**
      // （`dsh-client-ui-model-selection`），写的是 `session/selectModel`——**按会话生效**；
      // 而设置页管的是提供方与密钥。本机核心的默认选择来自 Host 配置，客户端没有"改全局默认"
      // 的写通道。所以这里**只展示**，并在下面说清去哪改，而不是留一个点了没反应的按钮。
      Text('切换模型在「会话」页的输入区进行（本机核心按会话记录模型选择）。这里显示的是 Host 为未配置会话准备的默认值。')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
    .width('100%')

    Column({ space: Sp.XS }) {
      Text('推理强度（当前默认）')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      if (this.currentEfforts().length === 0) {
        Text('当前模型不支持调整推理强度')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding(Sp.M)
          .borderRadius(Radius.M)
          .backgroundColor($r('sys.color.background_secondary'))
      } else {
        Row({ space: Sp.S }) {
          ForEach(this.currentEfforts(), (effort: string) => {
            // 点档位 = 写默认模型的 reasoningEffort（与官方"能力随模型"的语义一致）
            Text(effort)
              .fontSize(Fs.SECONDARY)
              .fontColor(this.selection.effort === effort ? Color.White : $r('sys.color.font_secondary'))
              .padding({ left: Sp.M, right: Sp.M, top: Sp.S, bottom: Sp.S })
              .borderRadius(Radius.L)
              .backgroundColor(this.selection.effort === effort
                ? $r('sys.color.brand')
                : $r('sys.color.background_secondary'))
              .onClick(() => {
                this.onSelectModel(this.selection.provider, this.selection.modelId, effort);
              })
          }, (effort: string) => effort)
        }
        .width('100%')
      }
    }
    .width('100%')

    Column({ space: Sp.XS }) {
      Text('全部模型')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      /*
       * 【为什么按提供方分组（E96）】官方 Models 页是**以提供方为单位**的：一行一个提供方，
       * 展开才是它的模型与设置。理由很实在——模型总是"某个提供方的模型"，密钥、端点、
       * 计费口径都挂在提供方上；拉平成一个列表会让人看不出"这个模型要用哪把密钥"。
       */
      ForEach(this.providerGroups(), (g: ModelProviderGroup) => {
        Column({ space: Sp.XS }) {
          Row({ space: Sp.S }) {
            Text(g.providerName.length > 0 ? g.providerName : g.provider)
              .fontSize(Fs.SECONDARY)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
            Text(`${g.models.length} 个模型`)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')

          ForEach(g.models, (m: ModelOption) => {
            Column({ space: 2 }) {
              Row({ space: Sp.S }) {
                Text(m.modelName.length > 0 ? m.modelName : m.modelId)
                  .fontSize(Fs.SECONDARY)
                  .layoutWeight(1)
                if (m.provider === this.selection.provider && m.modelId === this.selection.modelId) {
                  Text('当前')
                    .fontSize(Fs.CAPTION)
                    .fontColor($r('sys.color.brand'))
                }
                if (m.efforts.length > 0) {
                  Text(`${m.efforts.length} 档推理`)
                    .fontSize(Fs.CAPTION)
                    .fontColor($r('sys.color.font_tertiary'))
                }
              }
              .width('100%')
              if (m.description.length > 0) {
                Text(m.description)
                  .fontSize(Fs.CAPTION)
                  .fontColor($r('sys.color.font_tertiary'))
                  .width('100%')
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .padding(Sp.M)
            .borderRadius(Radius.M)
            .backgroundColor($r('sys.color.background_secondary'))
            // 点一行模型 = 把它设为**默认模型**（写 agent-default-model；官方的设置页也是这个语义：
            // "当前会话用哪个"在输入区切换，"默认用哪个"在这里定）
            .onClick(() => {
              this.onSelectModel(m.provider, m.modelId, this.effortFor(m));
            })
          }, (m: ModelOption) => `${m.provider}/${m.modelId}`)
        }
        .width('100%')
      }, (g: ModelProviderGroup) => g.provider)
    }
    .width('100%')
  }

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
  private providerKeyRefs(): string[] {
    const out: string[] = [];
    const groups: ModelProviderGroup[] = this.providerGroups();
    for (let i = 0; i < groups.length; i++) {
      const head: string = groups[i].provider.split('-')[0];
      const ref: string = `${head.toUpperCase()}_API_KEY`;
      let known: boolean = false;
      for (let j = 0; j < this.credentials.length; j++) {
        if (this.credentials[j].ref === ref) {
          known = true;
        }
      }
      if (!known && out.indexOf(ref) < 0) {
        out.push(ref);
      }
    }
    return out;
  }

  /**
   * 按提供方把模型目录分组（保持 Host 给的顺序，不重排——顺序本身是 Host 的偏好）。
   */
  private providerGroups(): ModelProviderGroup[] {
    const out: ModelProviderGroup[] = [];
    for (let i = 0; i < this.models.length; i++) {
      const m: ModelOption = this.models[i];
      let found: ModelProviderGroup | undefined = undefined;
      for (let j = 0; j < out.length; j++) {
        if (out[j].provider === m.provider) {
          found = out[j];
        }
      }
      if (found === undefined) {
        out.push({ provider: m.provider, providerName: m.providerName, models: [m] });
      } else {
        found.models.push(m);
      }
    }
    return out;
  }

  /** 换模型时该带哪个推理强度：沿用当前档位（若新模型支持），否则用它的第一档，都没有则为空串 */
  private effortFor(m: ModelOption): string {
    if (m.efforts.length === 0) {
      return '';
    }
    for (let i = 0; i < m.efforts.length; i++) {
      if (m.efforts[i] === this.selection.effort) {
        return this.selection.effort;
      }
    }
    return m.efforts[0];
  }

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

  @Builder
  credentialsTab() {
    Text('凭据只显示配置状态，端侧不保存也不显示明文值。')
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')

    ForEach(this.credentials, (c: CredentialItem) => {
      Row({ space: Sp.M }) {
        SymbolGlyph(c.configured ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_triangle'))
          .fontSize(16)
          .fontColor([c.configured ? $r('sys.color.confirm') : $r('sys.color.warning')])
        Column({ space: 2 }) {
          Text(c.ref)
            .fontSize(Fs.SECONDARY)
            // 【不要在这里写 layoutWeight（E95，真机实测）】外层 Column 里再嵌一层
            // `layoutWeight`，会让内层 Column / 外层 Row 被**撑到父级最大高度**：
            // 真机上的表现是"凭据那一行卡片纵向铺满整屏、ref 居中、说明被挤到底边"。
            // 文本不需要权重——宽度用 width('100%') 就够。模型页没有这层嵌套，所以它是正常的。
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.credentialHint(c))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)

        // 【为什么不写成 if/else 分支】实测：把三个分支各写一个 `Text` 时，
        // `configured` 从 true 变回 false 后界面**仍停留在旧分支**上
        // （诊断输出显示组件已收到 `cfg=false`，而按钮文字还是「更换」）。
        // 三个分支的结构完全相同（都是 `Text`），ArkUI 复用了旧的渲染节点。
        // 压成一个 `Text` 之后，文案随状态重算，不再有分支可被复用。
        // 教训：条件渲染的**各分支结构不同**时才用分支；只是文案不同就用三元表达式。
        Text(credentialActionLabel(c))
          .fontSize(Fs.CAPTION)
          .fontColor(c.writable ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
          .onClick(() => {
            if (c.writable && !c.interactive) {
              this.onAuthorizeCredential(c.ref);
            }
          })
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
    }, (c: CredentialItem) => credentialRowKey(c))
  }

  /** 凭据项的说明文字 */
  private credentialHint(c: CredentialItem): string {
    if (c.configured) {
      const source: string = c.source.length > 0 ? `来源：${c.source}` : '已配置';
      return c.writable ? `${source} · 可修改` : `${source} · 只读`;
    }
    return c.writable ? '未配置 · 可在此授权或设置' : '未配置 · 端侧不可写';
  }

  // ───────────── 插件 ─────────────

  /**
   * 单个插件的可安装性行。
   *
   * 目前**恒为 UNKNOWN**：上游 `pluginInventory.list` 不提供"是否含原生模块"这一信息。
   * 这是**记录事实**而不是偷懒——等能读到插件包清单（package.json / 是否存在 .node）后，
   * 再把真实取值传进来即可，界面与契约都不用改。
   */
  private pluginRowOf(p: PluginItem): PluginRow {
    return classifyPlugin(p.moduleName, '', PluginNative.UNKNOWN);
  }

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
    Row({ space: Sp.S }) {
      this.subChip('config', '配置')
      this.subChip('list', '列表')
      Blank()
      Text(pluginSummary(this.plugins))
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')

    if (this.pluginView === 'config') {
      this.pluginConfigView()
    } else {
      this.pluginListView()
    }
  }

  @Builder
  subChip(value: string, label: string) {
    Text(label)
      .fontSize(Fs.SECONDARY)
      .fontColor(this.pluginView === value ? Color.White : $r('sys.color.font_secondary'))
      .padding({ left: Sp.M, right: Sp.M, top: Sp.XS, bottom: Sp.XS })
      .borderRadius(Radius.L)
      .backgroundColor(this.pluginView === value
        ? $r('sys.color.brand')
        : $r('sys.color.background_secondary'))
      .onClick(() => {
        this.pluginView = value;
      })
  }

  /** 只读清单 + 关键词过滤（官方"插件列表"标签页的语义） */
  @Builder
  pluginListView() {
    TextInput({ placeholder: '按名称或 entryId 过滤…' })
      .fontSize(Fs.SECONDARY)
      .height(40)
      .width('100%')
      .onChange((value: string) => {
        this.pluginFilter = value;
      })

    ForEach(this.filteredPlugins(), (p: PluginItem) => {
      Row({ space: Sp.M }) {
        Circle({ width: 8, height: 8 })
          .fill(p.phase === 'active' ? $r('sys.color.confirm') : $r('sys.color.font_tertiary'))
        Column({ space: 2 }) {
          Text(p.moduleName)
            .fontSize(Fs.SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(`${p.entryId} · ${p.enabled ? '已启用' : '已禁用'}${p.phase.length > 0 ? ` · ${p.phase}` : ''}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        if (p.firstParty) {
          Text('第一方')
            .fontSize(10)
            .fontColor($r('sys.color.font_tertiary'))
            .padding({ left: 5, right: 5 })
            .borderRadius(5)
            .backgroundColor($r('sys.color.background_primary'))
        }
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
    }, (p: PluginItem) => p.entryId)

    Text('只读清单：这里的行不可点击，改动请切到「配置」。')
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
  }

  /** 关键词过滤后的插件清单（空关键词 = 全部） */
  private filteredPlugins(): PluginItem[] {
    const q: string = this.pluginFilter.trim().toLowerCase();
    if (q.length === 0) {
      return this.plugins;
    }
    const out: PluginItem[] = [];
    for (let i = 0; i < this.plugins.length; i++) {
      const p: PluginItem = this.plugins[i];
      if (p.moduleName.toLowerCase().includes(q) || p.entryId.toLowerCase().includes(q)) {
        out.push(p);
      }
    }
    return out;
  }

  @Builder
  pluginConfigView() {
    Row({ space: Sp.S }) {
      Text(pluginSummary(this.plugins))
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .layoutWeight(1)
    }
    .width('100%')

    // 【为什么这里只有说明、没有"市场"按钮】原实现有个「市场」文字，点了没有任何反应——
    // 它是个假入口。而"能不能运行时安装插件"在端侧有一个**硬边界**（E86）：
    // 上游 `dsh plugin add` 的实现是 `spawnSync("pnpm", …)`（`dsh/lib/plugin-Ddi42qoW.js:109`），
    // 而鸿蒙不允许应用创建进程（D6 E15）⇒ 纯 JS 插件同样装不了，"只有原生插件装不了"是**错**的。
    // 所以：不提供任何安装/市场入口，只如实列出随包发版的插件与启停状态。
    // 另外上游清单不含「是否含原生模块」，因此下方一律标「待确认」——不给会失败的承诺（D6 §6.2）。
    Text('端侧无法创建进程（上游安装通道 `dsh plugin add` 经 `spawnSync("pnpm")`，见 D6 E15/E86），因此插件只能随核心包发版，这里不提供安装或市场入口。上游插件清单也不含「是否含原生模块」，故一律标注「待确认」。')
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')

    ForEach(this.plugins, (p: PluginItem) => {
      Row({ space: Sp.M }) {
        Circle({ width: 8, height: 8 })
          .fill(p.phase === 'active' ? $r('sys.color.confirm') : $r('sys.color.font_tertiary'))
        Column({ space: 2 }) {
          Text(p.moduleName)
            .fontSize(Fs.SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(`${p.entryId} · ${p.enabled ? '已启用' : '已禁用'}${p.phase.length > 0 ? ` · ${p.phase}` : ''}`)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
        .layoutWeight(1)
        if (p.firstParty) {
          Text('第一方')
            .fontSize(10)
            .fontColor($r('sys.color.font_tertiary'))
            .padding({ left: 5, right: 5 })
            .borderRadius(5)
            .backgroundColor($r('sys.color.background_primary'))
        }
        // 可安装性徽标：取值由 appstate 的三态契约给出（纯 JS / 需发版 / 待确认）
        Text(this.pluginRowOf(p).badge)
          .fontSize(10)
          .fontColor($r('sys.color.font_tertiary'))
          .padding({ left: 5, right: 5 })
          .borderRadius(5)
          .backgroundColor($r('sys.color.background_primary'))
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
    }, (p: PluginItem) => p.entryId)

    Text('插件的安装与卸载由 Host 侧执行；端侧只展示状态与触发操作（D1 §7.6.4）。')
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
  }

  // ───────────── 设备 ─────────────

  @Builder
  deviceTab() {
    Row({ space: Sp.S }) {
      Text('已配置 Host')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .layoutWeight(1)
      // 措辞刻意写全「远程」：端侧自足运行后，本机核心是默认路径，
      // 连别人的 Host 是**可选能力**，不是"添加 Host 才能用"（D7 §3）
      Text('远程 Host（可选）')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.brand'))
        .onClick(() => {
          this.onPairHost();
        })
    }
    .width('100%')

    ForEach(this.hosts, (h: HostRecord) => {
      Column({ space: Sp.XS }) {
        Row({ space: Sp.S }) {
          Circle({ width: 8, height: 8 })
            .fill(h.authorized ? $r('sys.color.confirm') : $r('sys.color.warning'))
          Text(h.name)
            .fontSize(Fs.BODY)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(h.authorized ? '已授权' : '未授权')
            .fontSize(Fs.CAPTION)
            .fontColor(h.authorized ? $r('sys.color.confirm') : $r('sys.color.warning'))
        }
        .width('100%')

        Text(`${h.authority} · ${h.level}`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
        Text(`核心包版本 ${h.version.length > 0 ? h.version : '未知'}`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')

        if (!h.isLoopback) {
          Row({ space: Sp.L }) {
            Text('忘记此 Host')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.alert'))
              .onClick(() => {
                this.onRevokeHost(h.id);
              })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
    }, (h: HostRecord) => h.id)

    // 版本与兼容面信息（关于）
    Column({ space: Sp.XS }) {
      Text('关于')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      this.aboutRow('客户端版本', this.about.appVersion)
      this.aboutRow('受支持的上游版本', this.about.supportedUpstream)
      this.aboutRow('兼容面上表', this.about.endpointStats)
      this.aboutRow('兼容面采集时间', this.about.compatCapturedAt)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  @Builder
  aboutRow(label: string, value: string) {
    Row({ space: Sp.S }) {
      Text(label)
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
      Text(value.length > 0 ? value : '—')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .constraintSize({ maxWidth: 200 })
    }
    .width('100%')
  }
}
