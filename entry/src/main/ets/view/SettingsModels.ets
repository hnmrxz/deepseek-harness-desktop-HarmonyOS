/**
 * 设置 · 模型（P4-3b：`SettingsPane` 里最大的一块搬成域组件）。
 *
 * ## 这一个域回答什么
 *
 * 官方 Models 页的三件事：**提供方卡片**（状态点 + 首要的密钥动作 + 可展开的自定义设置与模型目录）、
 * **API 密钥（凭据联接）**、**新会话默认模型 + 全量模型目录**。矩阵 `settings-models` 行的口径
 * （「模型设置 + 凭据联接」）与本组件一致 —— 凭据是这个分区里的字段，不另立分区。
 *
 * ## 边界
 *
 *  · 数据（模型目录 / 全量设置分组 / 凭据 / 当前选择）由宿主给；
 *  · 副作用（选模型、授权凭据、写设置、恢复默认）由**回调**交回宿主：组件不决定"写失败要不要提示"；
 *  · 行渲染复用 `SettingRow`（通用段也用同一份）；
 *  · 两个纯展示态（展开哪个提供方、候选模型过滤词）留在组件内 —— 它们只影响这一页的显示；
 *  · 【一处例外，如实记录】`providerCandidates()` 直接读中枢的 `snapshot().providerCatalog`
 *    （提供方目录是**只读查询**，宿主当前没有现成投影）。将来若把目录投影到宿主，这里应改成 prop。
 */
import { CredentialItem, Fs, ModelOption, Radius, SessionHub, SettingGroup, SettingItem, Sp, Sz } from 'appstate';
import type { ModelSelection } from 'appstate';
import { SettingRow } from './SettingRow';


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

export interface ModelProviderGroup {
  provider: string;
  providerName: string;
  models: ModelOption[];
}

@Component
export struct SettingsModels {

  /** 全量设置分组（提供方分区的自定义设置从这里取） */
  @Prop allGroups: SettingGroup[] = [];
  /** 共享模型目录 */
  @Prop models: ModelOption[] = [];
  /** 当前会话/默认的模型选择 */
  @Prop selection: ModelSelection = { provider: '', modelId: '', effort: '' };
  /** 凭据（只显示配置状态，端侧不保存也不显示明文） */
  @Prop credentials: CredentialItem[] = [];

  /** 选模型（宿主写中枢） */
  onSelectModel: (provider: string, model: string, effort: string) => void = () => {
  };
  /** 授权/更新某个凭据引用（宿主打开凭据浮层） */
  onAuthorizeCredential: (ref: string) => void = () => {
  };
  /** 以下五个转给 `SettingRow`（行需要它们才能改设置） */
  onToggleSetting: (key: string, value: boolean) => void = () => {
  };
  onPickChoice: (key: string, current: string) => void = () => {
  };
  onEditText: (item: SettingItem) => void = () => {
  };
  onEditStruct: (item: SettingItem) => void = () => {
  };
  onResetSetting: (key: string) => void = () => {
  };

  /** 展开的提供方（空 = 都收起） */
  @State expandedProvider: string = '';
  /** 候选模型过滤词 */
  @State candidateQuery: string = '';

  // 【ArkUI 约束】组件的 build() 只能有一个根节点 ⇒ 多段内容包进 Column
  build() {
    Column({ space: Sp.L }) {
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
          /*
           * E177（对齐官方 Models 页）：凭据区**只在确有内容时渲染**。
           *
           * 官方 Models 页的密钥入口只有**提供方卡片那一处**（只写不读），设置页不再单列凭据；
           * 我们此前把两个数据源置空（E157/E158）却留下了这个带内边距与底色的列 ⇒ 真机上是一条**空白灰条**。
           * 这里加条件：两个来源都为空的（常态）整段不存在；**万一将来又有未被卡片覆盖的引用**，
           * 它仍会如实出现——这比直接删掉更稳（不是把能力砍掉，而是让空壳不再占位）。
           */
          if (this.orphanCredentials().length > 0 || this.providerKeyRefs().length > 0) {
          Column({ space: Sp.XS }) {
            if (this.orphanCredentials().length > 0) {
              Text('模型凭据')
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
            }
            if (this.credentials.length === 0) {
              Text('Host 没有报告任何凭据引用')
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .width('100%')
                .padding(Sp.M)
                .borderRadius(Radius.M)
                .backgroundColor($r('sys.color.background_secondary'))
            } else {
              /*
               * E157（用户反馈④）：**只列出提供方卡片没有覆盖的凭据引用**。
               *
               * 用户看到的是"同一把密钥要填两次"：提供方卡片有「配置密钥」（走 `<ROUTE>_API_KEY`），
               * 下面这一区又把同一个引用列一遍。**去重的正确做法不是删掉这一区**，
               * 而是让两处各管各的：提供方卡片管"该提供方的适配器引用"，
               * 这里管"其余宿主报告的引用"（例如别的命名空间声明的槽位）——
               * 前者已覆盖的就不在这里重复出现，但**一个引用都不会因此消失**。
               */
              ForEach(this.orphanCredentials(), (c: CredentialItem) => {
                Row({ space: Sp.M }) {
                  SymbolGlyph(c.configured ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.exclamationmark_triangle'))
                    .fontSize(16)   // token-exempt: 行内图标尺寸（搬迁不改视觉）
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
                SymbolGlyph($r('sys.symbol.key')).fontSize(16)   // token-exempt: 行内图标尺寸
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
          }

          /* E208（用户要求：模型页与官方一致）：「当前模型（Host 的默认选择）」只读区块已移除——官方 Models 页只列提供方与密钥；
             默认值在「通用」页的 agent-default-model 项可编辑，本会话切换在会话操作面板（E195/E199）。 */


          /*
           * E207（用户要求：模型页与官方一致）：**「推理强度（当前默认）」区块已移除**。
           *
           * 官方 Models 页只列**提供方与密钥**，"选模型/强度"不在这里。而这个区块与我们已具备的
           * 两条通道重复：① **默认值**在「通用」页有可编辑的 `agent-default-model` 项
           * （Provider / Model / Reasoning effort）；② **本会话切换**由会话操作面板提供
           * （E195 列表 + E199 按会话写 `session/selectModel`）。
           * 留着它只会让"默认"与"本会话"两件事在同一页上混着，看不出在哪改哪一个。
           */

          /*
           * 【E214：这里原本还有一份「各提供方的模型（点选设为新会话默认）」】
           * 用户实测后明确了：**它和提供方展开里的模型目录是同一份东西**（同一 `g.models`、
           * 同样的「当前」标记与点选语义），一页上出现两遍 ⇒ 删掉这一份，
           * models 只在**提供方展开**里出现（E213 先是"搬"，本轮完成"拆"）。
           * 语义提示（点选 = 设新会话默认、推理强度按模型选）跟着搬进 `providerEditor`。
           */
    }
    .width('100%')
  }

  /**
   * 行内动作的可点区域。
   *
   * 【为什么不能只给 `Text` 挂 `.onClick`】真机上"点了没反应"十有八九是**点不中**：
   * 只挂 onClick 的 `Text` 命中区就是那几行字（约 28×14vp），远小于本仓自己的
   * `Sz.TOUCH_MIN`（44vp）纪律。这里统一包一层：44vp 高 + 左右内边距 + 居中，
   * 并按可用状态决定是否响应（不可用时**照常显示原因**，不是把入口藏掉）。
   */
  @Builder
  actionLabel(label: string, enabled: boolean, a11y: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(Fs.CAPTION)
        .fontColor(enabled ? $r('sys.color.brand') : $r('sys.color.font_tertiary'))
    }
    .height(Sz.TOUCH_MIN)
    .padding({ left: Sp.S, right: Sp.S })
    .alignItems(VerticalAlign.Center)
    .borderRadius(Radius.S)
    .accessibilityText(a11y)
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  /**
   * 提供方的编辑区：**可编辑设置字段 + 该提供方的模型目录**。
   *
   * 【为什么抽成一份】"已配置的提供方卡片"与"可添加的提供方"都要展开同一份内容。
   * 两处各写一遍必然走样（本仓的老账），而且**候选那条路此前根本没有落点**：
   * 它的「配置」只把 `expandedProvider` 设成 `g.title`，而展开判定比的是**提供方 id**，
   * 且候选不在 `providerGroups()` 的循环里 ⇒ 点了什么都不会发生（用户报的"全部点不动"）。
   */
  @Builder
  providerEditor(group: SettingGroup | undefined, models: ModelOption[]) {
    if (group === undefined) {
      Text('宿主没有为这个提供方暴露可编辑的设置分区——端侧只显示它确实报告的东西，不造一个空编辑器。')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    } else {
      ForEach(group.items, (item: SettingItem) => {
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
      }, (item: SettingItem) => item.key)
    }
    if (models.length > 0) {
      Text(`模型目录 · ${models.length}`)
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      ForEach(models, (m: ModelOption) => {
        Column({ space: 2 }) {
          Row({ space: Sp.S }) {
            Text(m.modelName.length > 0 ? m.modelName : m.modelId)
              .fontSize(Fs.SECONDARY)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
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
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .padding(Sp.S)
        .borderRadius(Radius.S)
        .backgroundColor($r('sys.color.background_primary'))
        // 点一行模型 = 设为**新会话默认**（写 agent-default-model）。与官方设置页同语义：
        // "当前会话用哪个"在输入区切换，"默认用哪个"在这里定。
        .onClick(() => {
          this.onSelectModel(m.provider, m.modelId, this.effortFor(m));
        })
      }, (m: ModelOption) => `${m.provider}/${m.modelId}`)
      Text('点选 = 设为**新会话默认**（写 `agent-default-model`）；推理强度属于**模型的能力**，在该默认设置项的整值编辑里按模型选择。')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
    }
  }

  @Builder
  providerCards() {
    Text('提供方')
      .fontSize(Fs.CAPTION)
      .fontColor($r('sys.color.font_tertiary'))
      .width('100%')
    /*
     * E181（用户要求）：**添加多个提供方**，形态照官方 `ui-settings-models`
     * （其按钮名即 `addButton` / `addCard` / `candidate` / `candidateId` / `addActions`）。
     *
     * 【候选从哪来】官方把"已注册路由"（`llm/listProviders`）与"声明的可配置提供方"
     * （`llm/listConfigurableProviders`）**联合**成目录；已配置的显示为卡片，**其余显示为候选**。
     * 【为什么点击是"打开设置分区"而不是我们直接写】每个提供方的可写字段（baseURL、apiKey…）
     * 由**它自己的设置分区**声明；我们只把用户带到那个分区（写入仍走既有设置通道），
     * 分区不存在时**如实说明**——不凭猜测往一个不存在的命名空间里写。
     */
    if (this.providerCandidates().length > 0) {
      Text('可添加的提供方')
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .width('100%')
      // E211：候选搜索（官方 candidateSearch）。纯前端过滤——候选多时不必翻找
      TextInput({ text: this.candidateQuery, placeholder: '搜索提供方' })
        .fontSize(Fs.CAPTION)
        .height(Sz.TOUCH_MIN)
        .width('100%')
        .onChange((value: string) => {
          this.candidateQuery = value;
        })
      ForEach(this.filteredCandidates(), (id: string) => {
        Column({ space: Sp.XS }) {
          Row({ space: Sp.S }) {
            SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(16)   // token-exempt: 行内图标尺寸
              .fontColor([$r('sys.color.brand')])
            Text(id)
              .fontSize(Fs.SECONDARY)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            /*
             * 【这里曾经是个死键（用户报「全部点不动」）】原先点它把 `expandedProvider`
             * 设成 `g.title`，而展开判定比的是**提供方 id**；更要紧的是候选**不在**
             * `providerGroups()` 的循环里 ⇒ 就算键对了也没有落点。现在：键用 id，
             * 展开内容用与提供方卡片**同一份** `providerEditor`。
             */
            this.actionLabel(
              this.expandedProvider === id ? '收起' : (this.providerSettingGroup(id) === undefined ? '查看' : '配置'),
              true,
              `展开或收起 ${id} 的设置`,
              () => {
                this.expandedProvider = this.expandedProvider === id ? '' : id;
              })
          }
          .width('100%')
          if (this.expandedProvider === id) {
            this.providerEditor(this.providerSettingGroup(id), this.modelsOfProvider(id))
          }
        }
        .width('100%')
        .padding(Sp.M)
        .borderRadius(Radius.M)
        .backgroundColor($r('sys.color.background_secondary'))
      }, (id: string) => id)
    }
    ForEach(this.providerGroups(), (g: ModelProviderGroup) => {
      Column({ space: Sp.XS }) {
        Row({ space: Sp.S }) {
          Circle({ width: 8, height: 8 })   // token-exempt: 状态点几何
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
          this.actionLabel('配置密钥', true,
            `配置 ${g.providerName.length > 0 ? g.providerName : g.provider} 的密钥`,
            () => {
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
          this.providerEditor(this.providerSettingGroup(g.provider), g.models)
        }
      }
      .width('100%')
      .padding(Sp.M)
      .borderRadius(Radius.M)
      .backgroundColor($r('sys.color.background_secondary'))
    }, (g: ModelProviderGroup) => g.provider)
  }

  /** 某个提供方的模型（候选行展开时用；找不到就是空数组） */
  private modelsOfProvider(provider: string): ModelOption[] {
    const groups: ModelProviderGroup[] = this.providerGroups();
    for (let i = 0; i < groups.length; i++) {
      if (groups[i].provider === provider) {
        return groups[i].models;
      }
    }
    return [];
  }

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

  private providerCandidates(): string[] {
    const catalog: string[] = SessionHub.shared().snapshot().providerCatalog;
    const configured: ModelProviderGroup[] = this.providerGroups();
    const out: string[] = [];
    for (let i = 0; i < catalog.length; i++) {
      const id: string = catalog[i];
      if (id.length === 0) {
        continue;
      }
      let already: boolean = false;
      for (let j = 0; j < configured.length; j++) {
        // 提供方 id 可能带后缀（deepseek-official），按首段比较以避免"已配置的还出现在可添加里"
        if (configured[j].provider === id || configured[j].provider.split('-')[0] === id.split('-')[0]) {
          already = true;
        }
      }
      if (!already) {
        out.push(id);
      }
    }
    return out;
  }

  private filteredCandidates(): string[] {
    const all: string[] = this.providerCandidates();
    const q: string = this.candidateQuery.trim().toLowerCase();
    if (q.length === 0) {
      return all;
    }
    const out: string[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].toLowerCase().includes(q)) {
        out.push(all[i]);
      }
    }
    return out;
  }

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

  private orphanCredentials(): CredentialItem[] {
    /*
     * E175（用户决定）：**模型页不再单独列凭据**。
     *
     * 用户原话："模型提供方里已经配置密钥，不需要额外的模型凭据 apikey 设置了。"
     * 官方 Models 页的密钥入口**只有提供方卡片那一处**（只写不读），
     * 我们之前保留的「模型凭据」区（哪怕去重后只剩孤儿引用）仍然多出一个入口 ⇒ 直接不给。
     * 该区标题已是条件渲染（length > 0 才显示），所以这里返回空即整段消失；
     * 凭据的统一管理仍在「凭据」页（设备的密钥设置），一处都不少。
     */
    const none: CredentialItem[] = [];
    return none;
  }

  private providerKeyRefs(): string[] {
    /*
     * E158（用户反馈④的真因）：**这里返回空**——该列表已被提供方卡片取代。
     *
     * 真机 dump 证据：模型页同时出现 `配置密钥`（提供方卡片）与 `DEEPSEEK_API_KEY / 配置`
     * （本函数生成的旧列表）⇒ 同一引用给了两个入口，用户看到的就是"同一把密钥要填两次"。
     * E106 加这一行时还没有提供方卡片（E128 才有）；现在卡片已经是官方形态、
     * 且按提供方分组，这里再列一遍只会制造重复。
     * **保留函数本身**而不是删掉调用点：万一将来卡片形态被回退，恢复只需改这一处返回值。
     */
    return [];
  }

  private providerKeyRefOf(provider: string): string {
    const head: string = provider.split('-')[0];
    return `${head.toUpperCase()}_API_KEY`;
  }

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

  private credentialHint(c: CredentialItem): string {
    if (c.configured) {
      const source: string = c.source.length > 0 ? `来源：${c.source}` : '已配置';
      return c.writable ? `${source} · 可修改` : `${source} · 只读`;
    }
    return c.writable ? '未配置 · 可在此授权或设置' : '未配置 · 端侧不可写';
  }

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
}
