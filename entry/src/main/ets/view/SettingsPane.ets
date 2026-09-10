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
  Sp,
  Sz
} from 'appstate';

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

  onToggleSetting: (key: string, value: boolean) => void = () => {
  };
  onPickChoice: (key: string, current: string) => void = () => {
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
        Text(item.label)
          .fontSize(Fs.BODY)
          .width('100%')
        Text(item.hint)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
      .layoutWeight(1)

      if (item.kind === SettingKind.TOGGLE) {
        Toggle({ type: ToggleType.Switch, isOn: item.boolValue })
          .enabled(!item.readOnly)
          .onChange((on: boolean) => {
            this.onToggleSetting(item.key, on);
          })
      } else if (item.kind === SettingKind.CHOICE) {
        Text(item.textValue)
          .fontSize(Fs.SECONDARY)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.onPickChoice(item.key, item.textValue);
          })
      } else {
        Text(item.textValue)
          .fontSize(Fs.SECONDARY)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .constraintSize({ maxWidth: 160 })
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

        if (c.interactive) {
          Text(c.configured ? '重新授权' : '授权')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.brand'))
            .onClick(() => {
              this.onAuthorizeCredential(c.ref);
            })
        } else if (!c.writable) {
          Text('只读')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
    }, (c: CredentialItem) => c.ref)
  }

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
