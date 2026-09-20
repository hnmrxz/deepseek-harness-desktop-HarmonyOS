/**
 * 本会话模型选择（T023：对照 `dshmobile/ui/screens/main/SheetModels.kt` 复刻）。
 *
 * ## 对照结构（SheetModels.kt）
 *
 * 源码按 provider 分组：组名 `xsmall12` + `labelTertiary`（"provider 退后：它只是书架名，
 * 架上的模型才是选项"，源注释照录）；每个模型是一张 `DsShapes.menu`（r12）卡——
 * **每个模型都是卡**（"静止时也得像个控件"，源注释），选中的卡铺 `accentTertiary` 底 +
 * 1dp `accent` 边（"300dp 外的一个对勾只是脚注；染色的卡才是一眼能读的答案"），名字
 * `std14Strong`（选中 = accent）、说明 `caption11` maxLines 2、右侧 16dp 对勾。
 * 行最小高 `touchTarget`、内距水平 `medium` 垂直 `small`。
 *
 * ## 两个决策不是平级（源码核心判定，保留）
 *
 * 选哪个模型，和（对会推理的模型）推理多用力——源码把第二决策**嵌进选中卡内部**
 * （`DsSegmented` 强度档），"档位从属于配置它的模型"；未选中的模型下不画死控件。
 *
 * ## 契约（保留 v1，新增为可选）
 *
 * `sessionId / models / currentModelId / onPick` 不动（宿主 `MainShell` 持有面板开关与
 * 写入副作用）。**新增可选** `currentEffort` + `onPickEffort`（默认不生效）：宿主接上后
 * 强度档才可选；不接 = 只读显示当前档，不破坏既有调用。
 *
 * ## 一条如实说明的语义（保留自原实现）
 *
 * 未选会话时**不显示模型列表**，而是说明原因——`session/selectModel` 需要会话作用域，
 * 列一张点了没反应的模型表比不列更糟。
 */

import {
  DsPalette,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  HarmonyBorder,
  ModelOption,
  dsPaletteOf,
} from 'appstate';
import { DsSegmentData, DsSegmented, installDsSystemDarkWatch } from './NativePrimitives';

/* ───────── 组件级度量（SheetModels.kt 的 dp 字面量，逐条标注出处） ───────── */

/** SheetModels.kt `ModelRow`：选中对勾 16dp（`Icons.Filled.Check`） */
const MODEL_CHECK_ICON_SIZE: number = 16;
/** 等宽/系统字体栈（Type.kt system UI stack） */
const MODEL_FONT_SANS: string = 'sans-serif';

/** 一个 provider 分组（本侧从扁平投影 `ModelOption[]` 按首次出现顺序归并；源码结构同形） */
interface ModelGroup {
  provider: string;
  name: string;
  models: ModelOption[];
}

@Component
export struct SessionModelPicker {
  /** 当前会话 id（空串 = 未选会话） */
  @Prop sessionId: string = '';
  /** 宿主投影好的可选模型 */
  @Prop models: ModelOption[] = [];
  /** 当前选中的模型 id（用于高亮） */
  @Prop currentModelId: string = '';
  /**
   * 当前选中模型的推理强度 id（新增**可选**：空串 = 宿主未接强度选择，
   * 强度档只读显示默认档）。
   */
  @Prop currentEffort: string = '';

  onPick: (option: ModelOption) => void = () => {
  };
  /** 选推理强度（新增**可选**：宿主不接则档位不可写） */
  onPickEffort: (option: ModelOption, effort: string) => void = () => {
  };

  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  /** 按 provider 分组（保持首次出现顺序；组名取 providerName，缺了用 provider） */
  private groups(): ModelGroup[] {
    const out: ModelGroup[] = [];
    const byProvider: Map<string, ModelGroup> = new Map<string, ModelGroup>();
    for (let i = 0; i < this.models.length; i++) {
      const m: ModelOption = this.models[i];
      let g: ModelGroup | undefined = byProvider.get(m.provider);
      if (g === undefined) {
        g = {
          provider: m.provider,
          name: m.providerName.length > 0 ? m.providerName : m.provider,
          models: []
        };
        byProvider.set(m.provider, g);
        out.push(g);
      }
      g.models.push(m);
    }
    return out;
  }

  /** 强度档列表（`efforts` 是 id 列表；显示名沿用 id——上游按 id 原样回传，不在这换名） */
  private effortSegments(m: ModelOption): DsSegmentData[] {
    const out: DsSegmentData[] = [];
    for (let i = 0; i < m.efforts.length; i++) {
      out.push({ key: m.efforts[i], label: m.efforts[i] });
    }
    return out;
  }

  /** 当前生效的强度档：宿主给了用宿主的，否则只读显示模型的默认档 */
  private effectiveEffort(m: ModelOption): string {
    if (this.currentEffort.length > 0) {
      return this.currentEffort;
    }
    return m.defaultEffort;
  }

  build() {
    Column({ space: DsSpacing.XSMALL }) {
      if (this.sessionId.length === 0) {
        Text('请先在工作区里选中一个会话，再切换模型。')
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(MODEL_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
          .width('100%')
      } else if (this.models.length === 0) {
        // 与"两种没有命令"同一条纪律：宿主没报告 ≠ 没有模型。
        Text('宿主没有报告该会话可选的模型（或尚未读取）。')
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(MODEL_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
          .width('100%')
      } else {
        ForEach(this.groups(), (g: ModelGroup) => {
          Column({ space: DsSpacing.TINY }) {
            // 组名退后（源码：xsmall12 + labelTertiary，start small / top small / bottom tiny）
            Text(g.name)
              .fontSize(DsType.XSMALL_12.size)
              .lineHeight(DsType.XSMALL_12.lineHeight)
              .fontWeight(DsType.XSMALL_12.weight)
              .fontFamily(MODEL_FONT_SANS)
              .fontColor(this.palette().labelTertiary)
              .width('100%')
              .padding({
                left: DsSpacing.SMALL,
                top: DsSpacing.SMALL,
                bottom: DsSpacing.TINY
              })
            ForEach(g.models, (m: ModelOption) => {
              this.modelCard(m)
            }, (m: ModelOption) => `${m.provider}/${m.modelId}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (g: ModelGroup) => g.provider)
      }
    }
    .width('100%')
  }

  /**
   * 一张模型卡（对照 `ModelRow`：`DsShapes.menu` 卡，选中铺 accentTertiary + accent 边，
   * 未选中铺 bgModulePlatform——"静止时也得像个控件"；行最小高 touchTarget、
   * 内距水平 medium 垂直 small；选中卡内部嵌强度档 DsSegmented）。
   */
  @Builder
  modelCard(m: ModelOption) {
    Column() {
      Row({ space: DsSpacing.SMALL }) {
        Column({ space: DsSpacing.TINY }) {
          Text(m.modelName.length > 0 ? m.modelName : m.modelId)
            .fontSize(DsType.STD_14_STRONG.size)
            .lineHeight(DsType.STD_14_STRONG.lineHeight)
            .fontWeight(DsType.STD_14_STRONG.weight)
            .fontFamily(MODEL_FONT_SANS)
            .fontColor(this.isSelected(m) ? this.palette().accent : this.palette().labelPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (m.description.length > 0) {
            Text(m.description)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontWeight(DsType.CAPTION_11.weight)
              .fontFamily(MODEL_FONT_SANS)
              .fontColor(this.palette().labelTertiary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.isSelected(m)) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(MODEL_CHECK_ICON_SIZE)
            .fontColor([this.palette().accent])
        }
      }
      .width('100%')
      .constraintSize({ minHeight: DsSpacing.TOUCH_TARGET })
      .padding({
        left: DsSpacing.MEDIUM,
        right: DsSpacing.MEDIUM,
        top: DsSpacing.SMALL,
        bottom: DsSpacing.SMALL
      })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onPick(m);
      })
      .accessibilityText(this.isSelected(m)
        ? `${m.modelName}，当前模型` : (m.description.length > 0 ? `${m.modelName}，${m.description}` : m.modelName))

      // 强度档嵌在选中卡内部（源码：第二决策从属于第一决策；未选中的模型下不画死控件）
      if (this.isSelected(m) && this.effortSegments(m).length > 0) {
        Column({ space: DsSpacing.XSMALL }) {
          Text('推理强度')
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontWeight(DsType.CAPTION_11.weight)
            .fontFamily(MODEL_FONT_SANS)
            .fontColor(this.palette().labelTertiary)
            .width('100%')
          DsSegmented({
            segments: this.effortSegments(m),
            selectedKey: this.effectiveEffort(m),
            onSelect: (key: string) => {
              this.onPickEffort(m, key);
            }
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: DsSpacing.MEDIUM,
          right: DsSpacing.MEDIUM,
          bottom: DsSpacing.MEDIUM
        })
      }
    }
    .width('100%')
    .borderRadius(DsShape.MENU)
    .backgroundColor(this.isSelected(m) ? this.palette().accentTertiary : this.palette().bgModulePlatform)
    .borderWidth(this.isSelected(m) ? HarmonyBorder.HAIRLINE : 0)
    .borderColor(this.palette().accent)
  }

  private isSelected(m: ModelOption): boolean {
    return this.currentModelId.length > 0 && this.currentModelId === m.modelId;
  }
}
