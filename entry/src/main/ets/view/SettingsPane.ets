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
  Fs,
  HostRecord,
  ModelOption,
  ModelSelection,
  modelSelectionLabel,
  pluginSummary,
  PluginItem,
  Radius,
  SettingGroup,
  SettingItem,
  SettingKind,
  SettingOrigin,
  Sp,
  Sz
} from 'appstate';
import type { SettingsNamespaceState } from 'appstate';

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

@Component
export struct SettingsPane {
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
  onPickModel: () => void = () => {
  };
  onPickEffort: (effort: string) => void = () => {
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
          if (this.tab === 'general') {
            this.generalTab()
          } else if (this.tab === 'model') {
            this.modelTab()
          } else if (this.tab === 'credentials') {
            this.credentialsTab()
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

  @Builder
  tabBar() {
    Scroll() {
      Row({ space: Sp.S }) {
        this.tabChip('general', '通用')
        this.tabChip('model', '模型')
        this.tabChip('credentials', '凭据')
        this.tabChip('plugins', '插件')
        this.tabChip('device', '设备')
      }
      .padding({ left: Sp.M, right: Sp.M })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(Sz.TOUCH_MIN)
  }

  @Builder
  tabChip(key: string, label: string) {
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

  @Builder
  settingRow(item: SettingItem) {
    Row({ space: Sp.M }) {
      Column({ space: 2 }) {
        Row({ space: Sp.XS }) {
          Text(item.label)
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
          if (item.userSet) {
            Text('已自定义')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.brand'))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(Radius.S)
              .backgroundColor($r('sys.color.background_primary'))
          }
        }
        .width('100%')

        Text(item.hint)
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

      if (item.kind === SettingKind.TOGGLE) {
        Toggle({ type: ToggleType.Switch, isOn: item.boolValue })
          .enabled(!item.readOnly)
          .onChange((on: boolean) => {
            this.onToggleSetting(item.key, on);
          })
      } else if (item.kind === SettingKind.CHOICE) {
        Text(choiceLabel(item))
          .fontSize(Fs.SECONDARY)
          .fontColor(item.readOnly ? $r('sys.color.font_tertiary') : $r('sys.color.brand'))
          .onClick(() => {
            if (!item.readOnly) {
              this.onPickChoice(item.key, item.textValue);
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
        Text('连接诊断')
          .fontSize(Fs.BODY)
          .width('100%')
        Text('五项判定：端点 / TLS / 认证 / 协议 / Host 版本')
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

  @Builder
  modelTab() {
    Column({ space: Sp.XS }) {
      Text('当前模型')
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
        Text('切换')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.onPickModel();
          })
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
    }
    .width('100%')

    Column({ space: Sp.XS }) {
      Text('推理强度')
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
            Text(effort)
              .fontSize(Fs.SECONDARY)
              .fontColor(this.selection.effort === effort ? Color.White : $r('sys.color.font_secondary'))
              .padding({ left: Sp.M, right: Sp.M, top: Sp.S, bottom: Sp.S })
              .borderRadius(Radius.L)
              .backgroundColor(this.selection.effort === effort
                ? $r('sys.color.brand')
                : $r('sys.color.background_secondary'))
              .onClick(() => {
                this.onPickEffort(effort);
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
      ForEach(this.models, (m: ModelOption) => {
        Column({ space: 2 }) {
          Row({ space: Sp.S }) {
            Text(m.modelName.length > 0 ? m.modelName : m.modelId)
              .fontSize(Fs.SECONDARY)
              .layoutWeight(1)
            Text(m.providerName.length > 0 ? m.providerName : m.provider)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .width('100%')
          Text(m.description)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
        .width('100%')
        .padding(Sp.M)
        .borderRadius(Radius.M)
        .backgroundColor($r('sys.color.background_secondary'))
      }, (m: ModelOption) => `${m.provider}/${m.modelId}`)
    }
    .width('100%')
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
            .layoutWeight(1)
            .width('100%')
          Text(this.credentialHint(c))
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
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

  @Builder
  pluginsTab() {
    Row({ space: Sp.S }) {
      Text(pluginSummary(this.plugins))
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .layoutWeight(1)
      Text('市场')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.brand'))
    }
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
      Text('添加 / 配对')
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
            Text('吊销设备密钥')
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
