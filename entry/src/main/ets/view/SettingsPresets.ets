/**
 * 设置页「预设」分区（T023：对照 `dshmobile/ui/screens/main/SheetPresets.kt` 的行结构
 * 复刻；选中态与危险确认的语义另对照 `SheetPermission.kt`）。
 *
 * ## 对照结构（SheetPresets.kt）
 *
 * 源码一行一个预设：名字 `std14Strong`（选中 = accent / 可选 = labelPrimary / 其余 =
 * labelTertiary）+ `DsPill` 信任标（随附/自定义）+ `DsPill` 默认标 + 说明 `caption11` +
 * 选中行尾 16dp 对勾；行垂直内距 `small`。本侧同构；**新增可选** `currentPresetId`
 * （宿主不接 = 无选中态，不破坏既有调用）。
 *
 * `SheetPermission.kt` 的两条语义也搬了过来：① 选中行的读法（accent 字 + 对勾，
 * `PermissionMenu` 与 `PresetsSheet` 同一形态；权限预设选择器本体在 `SettingsGeneral`，
 * 不在本文件领地）；② **危险动作要刻意确认**（`FullAccessConfirmDialog` 的复选框门）——
 * 本侧保留 v1 的删除两步确认（先「确认删除 / 取消」），同为"不可逆动作不一次点成"。
 *
 * ## 它拥有什么（保留 v1）
 *
 * 官方 `settings-agent-presets` 这一页的两半：
 *   ① **预设名单卡片**（E161）：名字 / 说明 / id / 默认标记 / 随附或自定义，以及卡片动作；
 *   ② **`agent-*` 设置分区的编辑器**（E129）：让"新建会话用哪个预设"真的可改。
 *
 * ## 被保留下来的语义（都不是装饰）
 *
 * 1. **复制是创建自定义预设的唯一入口**（官方规则）⇒ **每张卡都有**「复制」，
 *    连随附只读预设也能被复制。
 * 2. **删除只对自定义预设开放**：`trust === 'system'` 是随附只读，
 *    连入口都不给（宿主也会拒绝）——而不是给一个点了必被拒的按钮。
 * 3. **删除走两步确认**（先「确认删除 / 取消」）——这是不可逆动作。
 * 4. **查看是只读查看器**（E173，官方对随附预设就是"在只读查看器里打开"）。
 * 5. **"预设没有可读文本"要说清楚**：宿主返回空串时说明可能的原因，不显示空白面板。
 * 6. **预设只在会话创建时固定** ⇒ 这里改的是**此后新建会话**的默认值，已存在的会话不受影响
 *    （这句话必须留在页面上，否则用户会以为改了当前会话）。
 *
 * ## 组件内状态（三个，都不上宿主）
 *
 * `confirmingId` / `viewedId` / `viewedContent` 都是**一次交互内的临时态**，
 * 关掉设置页就没有意义，所以不进 `NavigationState`。
 *
 * ## 一处例外（如实记录）：查看动作直接调中枢
 *
 * 查看是**纯读取**、无副作用、也不改变其它页面状态；为它再往 `Index` 穿一层 prop
 * 只会增加耦合。写入类动作（复制 / 删除）仍走宿主回调，因为它们要影响"下一步做什么"。
 */

import {
  AgentPresetRow,
  DsPalette,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  HarmonyBorder,
  SessionHub,
  SettingGroup,
  SettingItem,
  presetIsBundled,
  dsPaletteOf,
} from 'appstate';
import { DsPill, installDsSystemDarkWatch } from './NativePrimitives';
import { SettingRow } from './SettingRow';

/* ───────── 组件级度量（SheetPresets.kt / SheetPermission.kt 的 dp 字面量，逐条标注出处） ───────── */

/** SheetPresets.kt：选中行尾对勾 16dp（`Icons.Filled.Check`；SheetPermission.kt 同尺寸） */
const PRESET_CHECK_ICON_SIZE: number = 16;
/** 等宽/系统字体栈（Type.kt system UI stack） */
const PRESET_FONT_SANS: string = 'sans-serif';

/** 设置页「预设」分区 */
@Component
export struct SettingsPresets {
  /** Agent 预设名单（E159/E160：`agentPresets/list` 实测形状；`trust === 'system'` = 随附只读） */
  @Prop presets: AgentPresetRow[] = [];
  /** 名单读取结论（非空必须显示：读不到 ≠ 没有预设） */
  @Prop note: string = '';
  /** **全部**设置分区（含被「通用」策展隐藏的 `agent-*`）——预设编辑器要从这里取 */
  @Prop allGroups: SettingGroup[] = [];
  /**
   * 当前选中的预设 id（新增**可选**：对照 SheetPresets.kt 的 `currentPreset` 选中态；
   * 宿主不接 = 无选中行，不破坏既有调用）。
   */
  @Prop currentPresetId: string = '';
  /** 复制（官方唯一的创建入口；随附预设也能复制） */
  onCopy: (from: string, name: string) => void = () => {
  };
  /** 删除（宿主强制"随附预设不可写"，并把它的原话转达给用户） */
  onDelete: (id: string) => void = () => {
  };
  /** 设置项的三个写入口（`agent-*` 分区里会有开关/单选/文本项） */
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

  /** 已按过一次「删除」、等待确认的预设 id（两步确认） */
  @State confirmingId: string = '';
  /** 正在查看的预设 id（空 = 未查看） */
  @State viewedId: string = '';
  /** 只读查看器当前展示的预设内容（E173） */
  @State viewedContent: string = '';

  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
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

  /**
   * 只读查看器要显示的内容。
   *
   * 【为什么把 Promise 留在组件里】它只写组件自己的 `viewedContent`，
   * 失败信息也只对这一次查看有意义 ⇒ 让它出组件反而要往上传错误分支。
   */
  private readPreset(id: string): void {
    this.viewedId = id;
    this.viewedContent = '正在读取…';
    SessionHub.shared().readAgentPreset(id).then((text: string) => {
      this.viewedContent = text.length > 0
        ? text
        : '宿主没有返回内容（可能该预设没有可读的组装文本，或读取被拒）。';
    }).catch((e: Object) => {
      this.viewedContent = `读取失败：${(e as Error).message}`;
    });
  }

  build() {
    Column({ space: DsSpacing.MEDIUM }) {
      if (this.note.length > 0) {
        Text(this.note)
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(PRESET_FONT_SANS)
          .fontColor(this.palette().labelSecondary)
          .width('100%')
          .padding(DsSpacing.MEDIUM)
          .borderRadius(DsShape.BLOCK)
          .backgroundColor(this.palette().bgLayer1)
          .borderWidth(HarmonyBorder.HAIRLINE)
          .borderColor(this.palette().borderL2)
      }
      if (this.presets.length > 0) {
        ForEach(this.presets, (p: AgentPresetRow) => {
          this.presetRow(p)
        }, (p: AgentPresetRow) => `${p.id}:${this.confirmingId}:${this.viewedId === p.id ? 1 : 0}`)
        Text('预设是"这个会话的 Agent 跑哪些插件"的组装；会话创建时固定，改默认只影响此后新建的会话。复制是创建自定义预设的唯一入口；删除只对自定义预设开放（两步确认）。')
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(PRESET_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
          .width('100%')
      }
      if (this.agentGroups().length === 0) {
        Text('宿主没有暴露 agent-* 设置分区（端侧只显示它确实报告的东西）。')
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(PRESET_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
          .width('100%')
      } else {
        ForEach(this.agentGroups(), (group: SettingGroup) => {
          this.agentGroup(group)
        }, (group: SettingGroup) => group.title)
      }
      Text('预设**在会话创建时固定**（官方原话），所以这里设置的是**此后新建会话**用的默认值；已存在的会话不受影响。')
        .fontSize(DsType.CAPTION_11.size)
        .lineHeight(DsType.CAPTION_11.lineHeight)
        .fontWeight(DsType.CAPTION_11.weight)
        .fontFamily(PRESET_FONT_SANS)
        .fontColor(this.palette().labelTertiary)
        .width('100%')
    }
    .width('100%')
  }

  /**
   * 一行预设（对照 SheetPresets.kt：名字 std14Strong（选中 accent）+ DsPill 信任标 +
   * DsPill 默认标 + 说明 caption11 + 选中行尾 16dp 对勾；行垂直内距 small）。
   * v1 的动作行（复制/查看/删除两步）保留，随行语言重绘。
   */
  @Builder
  presetRow(p: AgentPresetRow) {
    Column({ space: DsSpacing.TINY }) {
      Row({ space: DsSpacing.SMALL }) {
        Column({ space: DsSpacing.TINY }) {
          // 名字行：名字 + 信任标 + 默认标（源码同一行；对照 `PresetsSheet` 的 Row）
          Row({ space: DsSpacing.SMALL }) {
            Text(p.name.length > 0 ? p.name : p.id)
              .fontSize(DsType.STD_14_STRONG.size)
              .lineHeight(DsType.STD_14_STRONG.lineHeight)
              .fontWeight(DsType.STD_14_STRONG.weight)
              .fontFamily(PRESET_FONT_SANS)
              .fontColor(this.nameColor(p))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            DsPill({ text: presetIsBundled(p) ? '随附' : '自定义' })
            if (p.isDefault) {
              DsPill({ text: '默认' })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          if (p.description.length > 0) {
            Text(p.description)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontWeight(DsType.CAPTION_11.weight)
              .fontFamily(PRESET_FONT_SANS)
              .fontColor(this.palette().labelTertiary)
              .width('100%')
          }
          Text(p.id)
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontWeight(DsType.CAPTION_11.weight)
            .fontFamily(PRESET_FONT_SANS)
            .fontColor(this.palette().labelCaption)
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.isSelected(p)) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(PRESET_CHECK_ICON_SIZE)
            .fontColor([this.palette().accent])
        }
      }
      .width('100%')
      .padding({ top: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
      .alignItems(VerticalAlign.Top)

      // 动作行（v1 功能面）：复制 / 查看 / 删除（两步确认）。随附预设不可删（连入口都不给）。
      Row({ space: DsSpacing.MEDIUM }) {
        Text('复制')
          .fontSize(DsType.CAPTION_11_STRONG.size)
          .lineHeight(DsType.CAPTION_11_STRONG.lineHeight)
          .fontWeight(DsType.CAPTION_11_STRONG.weight)
          .fontFamily(PRESET_FONT_SANS)
          .fontColor(this.palette().accent)
          .onClick(() => {
            this.onCopy(p.id, p.name);
          })
          .accessibilityText(`复制预设 ${p.name}`)
        Text(this.viewedId === p.id ? '收起内容' : '查看')
          .fontSize(DsType.CAPTION_11_STRONG.size)
          .lineHeight(DsType.CAPTION_11_STRONG.lineHeight)
          .fontWeight(DsType.CAPTION_11_STRONG.weight)
          .fontFamily(PRESET_FONT_SANS)
          .fontColor(this.palette().accent)
          .onClick(() => {
            if (this.viewedId === p.id) {
              this.viewedId = '';
              this.viewedContent = '';
              return;
            }
            this.readPreset(p.id);
          })
          .accessibilityText(`查看预设 ${p.name} 的组装内容`)
        if (!presetIsBundled(p)) {
          Text(this.confirmingId === p.id ? '确认删除' : '删除')
            .fontSize(DsType.CAPTION_11_STRONG.size)
            .lineHeight(DsType.CAPTION_11_STRONG.lineHeight)
            .fontWeight(DsType.CAPTION_11_STRONG.weight)
            .fontFamily(PRESET_FONT_SANS)
            .fontColor(this.confirmingId === p.id ? this.palette().error : this.palette().warnLabel)
            .onClick(() => {
              // 两步确认（对照 SheetPermission.kt：不可逆动作不一次点成）
              if (this.confirmingId === p.id) {
                this.confirmingId = '';
                this.onDelete(p.id);
              } else {
                this.confirmingId = p.id;
              }
            })
            .accessibilityText(this.confirmingId === p.id
              ? `再次点击确认删除预设 ${p.name}` : `删除预设 ${p.name}`)
          if (this.confirmingId === p.id) {
            Text('取消')
              .fontSize(DsType.CAPTION_11_STRONG.size)
              .lineHeight(DsType.CAPTION_11_STRONG.lineHeight)
              .fontWeight(DsType.CAPTION_11_STRONG.weight)
              .fontFamily(PRESET_FONT_SANS)
              .fontColor(this.palette().labelTertiary)
              .onClick(() => {
                this.confirmingId = '';
              })
              .accessibilityText('取消删除')
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 只读查看器（E173）：随附预设"在只读查看器里打开"
      if (this.viewedId === p.id) {
        Text(this.viewedContent)
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(PRESET_FONT_SANS)
          .fontColor(this.palette().labelSecondary)
          .width('100%')
          .padding(DsSpacing.SMALL)
          .borderRadius(DsShape.ROW)
          .backgroundColor(this.palette().bgModulePlatform)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 名字色（对照 SheetPresets.kt：选中 accent / 可选 labelPrimary / 其余 labelTertiary） */
  private nameColor(p: AgentPresetRow): number {
    if (this.isSelected(p)) {
      return this.palette().accent;
    }
    if (presetIsBundled(p)) {
      // 随附预设不可改默认（v1 语义）：读作"只能看"
      return this.palette().labelSecondary;
    }
    return this.palette().labelPrimary;
  }

  private isSelected(p: AgentPresetRow): boolean {
    return this.currentPresetId.length > 0 && this.currentPresetId === p.id;
  }

  /** 一个 `agent-*` 分区（组标题 + 组内设置项） */
  @Builder
  agentGroup(group: SettingGroup) {
    Column({ space: DsSpacing.XSMALL }) {
      Text(group.title)
        .fontSize(DsType.XSMALL_12.size)
        .lineHeight(DsType.XSMALL_12.lineHeight)
        .fontWeight(DsType.XSMALL_12.weight)
        .fontFamily(PRESET_FONT_SANS)
        .fontColor(this.palette().labelTertiary)
        .width('100%')
        .padding({
          left: DsSpacing.SMALL,
          top: DsSpacing.SMALL,
          bottom: DsSpacing.TINY
        })
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
    .width('100%')
  }
}
