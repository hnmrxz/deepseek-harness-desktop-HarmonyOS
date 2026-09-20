/**
 * 命令列表（T023：对照 `dshmobile/ui/screens/main/SheetCommands.kt` 的行结构复刻，
 * 过滤与执行的判定语义对照 `SlashAdjudication.kt`）。
 *
 * ## 对照结构（SheetCommands.kt）
 *
 * 源码是一张 bottom sheet：可搜索（条目 > 12 时出搜索框，`filterByQuery` = 名字**子序列**
 * 模糊匹配 + 说明大小写不敏感包含）+ `SheetRow`（`std14Strong` 标题 maxLines 1 /
 * `caption11` 副题 maxLines 2 / 尾部参数提示 `caption11` **等宽** `labelCaption`、
 * `widthIn(max = 120.dp)`——"提示给说明让路"，见源注释）。
 * 本侧同构：行 = `Row` + `DsShape.ROW` 圆角 + 垂直内距 `small`；标题/副题/尾注三槽一一对应
 * （v1 的「参数：xxx」改为**尾部等宽提示**，不再占一整行）。
 *
 * ## 判定仍归宿主（视图不重写，对照 SlashAdjudication.kt）
 *
 * 源码里"这条命令能不能直接执行"由 `command.input == null` 决定、在**点击时**分派
 * （`onRunCommand` vs `onPrefillDraft`）；本仓对应判定（`commandPickAction`）在宿主
 * `MainShell` 里，本组件保持 v1 契约：`onRun(c)` / `onRunWithArg(c, arg)` 只报"用户点了什么"。
 *
 * ## 两种"没有命令"要分开说（保留 v1）
 *
 * 未选会话时说"命令取决于具体会话"，已选会话但宿主没报告时说"宿主没有报告该会话可用的
 * 命令（或尚未读取）"。**不把"还没读到"说成"这个会话没有命令"**——那是让人们去排查一个
 * 不存在的权限问题（对照源码 `chat_commands_unavailable` 的"承认不知道"纪律）。
 *
 * ## §FR-006：popupSelect 类型命令（保留 v1）
 *
 * 官方客户端用 `CommandDecoration.popupSelect` 为需要选值的命令（如 `/model`、`/permission`）
 * 提供选项列表。本组件在检测到 `kind === 'popupSelect'` 且有选项时，展开选项列表供用户
 * 点击（`onRunWithArg`），而不是直接执行。
 */

import {
  CommandCandidate,
  CommandOption,
  DsPalette,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  dsPaletteOf,
} from 'appstate';
import { installDsSystemDarkWatch } from './NativePrimitives';

/* ───────── 组件级度量（SheetCommands.kt 的 dp 字面量，逐条标注出处） ───────── */

/** SheetCommands.kt `SheetRow` 尾部提示 `widthIn(max = 120.dp)`——长提示给名字让路 */
const CMD_TRAILING_MAX_WIDTH: number = 120;
/** SheetCommands.kt `val searchable = commands.size + skills.size > 12`（本侧无技能区，只数命令） */
const CMD_SEARCHABLE_THRESHOLD: number = 12;
/** 等宽/系统字体栈（Type.kt `codeFont` / system UI stack） */
const CMD_FONT_MONO: string = 'monospace';
const CMD_FONT_SANS: string = 'sans-serif';

/**
 * 子序列模糊匹配（对照 `JsonDisclosure.kt` 的 `fuzzyContains`：名字里**按顺序**出现查询的
 * 全部字符即命中；空查询恒真）。说明走普通包含（源码 `filterByQuery` 同款双轨）。
 */
function commandFuzzyContains(name: string, query: string): boolean {
  const needle: string = query.trim().toLowerCase();
  if (needle.length === 0) {
    return true;
  }
  const hay: string = name.toLowerCase();
  let index: number = 0;
  for (let i = 0; i < hay.length; i++) {
    if (hay.charAt(i) === needle.charAt(index)) {
      index++;
    }
    if (index === needle.length) {
      return true;
    }
  }
  return false;
}

@Component
export struct CommandList {
  /** 当前会话 id（空串 = 未选会话） */
  @Prop sessionId: string = '';
  /** 宿主报告的可执行命令 */
  @Prop commands: CommandCandidate[] = [];

  onRun: (command: CommandCandidate) => void = () => {
  };
  /** §FR-006：popupSelect 选项点击——用选项值作为命令参数执行 */
  onRunWithArg: (command: CommandCandidate, arg: string) => void = () => {
  };

  /** 当前展开的 popupSelect 命令索引（-1 = 无） */
  @State expandedCommandIdx: number = -1;
  /** 搜索框内容（条目 > 12 时才出搜索框，对照源码 `searchable`） */
  @State query: string = '';

  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  /** 过滤后的命令（源码 `filterByQuery`：名字子序列 ∨ 说明/参数包含，大小写不敏感） */
  private filteredCommands(): CommandCandidate[] {
    const needle: string = this.query.trim().toLowerCase();
    if (needle.length === 0) {
      return this.commands;
    }
    const out: CommandCandidate[] = [];
    for (let i = 0; i < this.commands.length; i++) {
      const c: CommandCandidate = this.commands[i];
      if (commandFuzzyContains(c.name, needle)
        || c.detail.toLowerCase().indexOf(needle) >= 0
        || c.args.toLowerCase().indexOf(needle) >= 0) {
        out.push(c);
      }
    }
    return out;
  }

  build() {
    Column({ space: DsSpacing.XSMALL }) {
      if (this.commands.length === 0) {
        // 两种"没有命令"分开说（见文件头）；样式对照源码 unavailable/empty 分支：
        // caption11 + labelTertiary。
        Text(this.sessionId.length === 0
          ? '命令取决于具体会话：请先在工作区里选中一个会话。'
          : '宿主没有报告该会话可用的命令（或尚未读取）。')
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(CMD_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
          .width('100%')
      } else {
        // 可搜索门槛（源码 `searchable`）：条目多到翻不动时才出搜索框。
        if (this.commands.length > CMD_SEARCHABLE_THRESHOLD) {
          TextInput({ text: this.query, placeholder: '搜索' })
            .fontSize(DsType.STD_14.size)
            .fontFamily(CMD_FONT_SANS)
            .fontColor(this.palette().labelPrimary)
            .placeholderColor(this.palette().labelTertiary)
            .placeholderFont({ size: DsType.STD_14.size })
            .height(DsSpacing.TOUCH_TARGET)
            .width('100%')
            .onChange((v: string) => {
              this.query = v;
            })
        }
        if (this.filteredCommands().length === 0) {
          Text('没有匹配的命令。')
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontWeight(DsType.CAPTION_11.weight)
            .fontFamily(CMD_FONT_SANS)
            .fontColor(this.palette().labelTertiary)
            .width('100%')
        }
        ForEach(this.filteredCommands(), (c: CommandCandidate) => {
          Column({ space: DsSpacing.TINY }) {
            this.commandRow(c)
            // §FR-006：popupSelect 选项列表（源码无此形态——它是官方 web 客户端的
            // CommandDecoration；保留 v1 行为，样式随行语言）。
            if (c.kind === 'popupSelect' && c.options.length > 0
              && this.expandedCommandIdx === this.commands.indexOf(c)) {
              Column({ space: DsSpacing.TINY }) {
                ForEach(c.options, (opt: CommandOption) => {
                  Row() {
                    Text(opt.label)
                      .fontSize(DsType.STD_14.size)
                      .lineHeight(DsType.STD_14.lineHeight)
                      .fontWeight(DsType.STD_14.weight)
                      .fontFamily(CMD_FONT_SANS)
                      .fontColor(this.palette().accent)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({
                    left: DsSpacing.MEDIUM,
                    right: DsSpacing.MEDIUM,
                    top: DsSpacing.XSMALL,
                    bottom: DsSpacing.XSMALL
                  })
                  .borderRadius(DsShape.ROW)
                  .backgroundColor(this.palette().accentTertiary)
                  .onClick(() => {
                    this.onRunWithArg(c, opt.value);
                    this.expandedCommandIdx = -1;
                  })
                  .accessibilityText(`${c.name}：${opt.label}`)
                }, (opt: CommandOption) => opt.value)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
        }, (c: CommandCandidate) => `${c.name}:${c.args}:${c.detail}`)
      }
    }
    .width('100%')
  }

  /**
   * 一条命令行（对照 `SheetRow`：fillMaxWidth + clip(DsShapes.row) + 垂直内距 small，
   * 标题 std14Strong maxLines 1 / 副题 caption11 maxLines 2 / 尾注 caption11 等宽
   * labelCaption maxLines 1 + widthIn(max = 120.dp)）。
   */
  @Builder
  commandRow(c: CommandCandidate) {
    Row({ space: DsSpacing.SMALL }) {
      Column({ space: DsSpacing.TINY }) {
        Text(c.name)
          .fontSize(DsType.STD_14_STRONG.size)
          .lineHeight(DsType.STD_14_STRONG.lineHeight)
          .fontWeight(DsType.STD_14_STRONG.weight)
          .fontFamily(CMD_FONT_SANS)
          .fontColor(this.palette().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (c.detail.length > 0) {
          Text(c.detail)
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontWeight(DsType.CAPTION_11.weight)
            .fontFamily(CMD_FONT_SANS)
            .fontColor(this.palette().labelTertiary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (c.args.length > 0) {
        // 参数提示（源码 trailing = input.hint）：它决定这条命令能不能直接执行（P9-4），
        // 所以单独露出；等宽 + 最宽 120（长提示给名字让路，源码注释照录）。
        Text(c.args)
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(CMD_FONT_MONO)
          .fontColor(this.palette().labelCaption)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: CMD_TRAILING_MAX_WIDTH })
      }
    }
    .width('100%')
    .padding({ top: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
    .borderRadius(DsShape.ROW)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      // §FR-006：popupSelect 命令展开选项列表，其他命令直接执行
      const idx: number = this.commands.indexOf(c);
      if (c.kind === 'popupSelect' && c.options.length > 0) {
        this.expandedCommandIdx = this.expandedCommandIdx === idx ? -1 : idx;
      } else {
        this.onRun(c);
      }
    })
    .accessibilityText(c.detail.length > 0 ? `${c.name}，${c.detail}` : c.name)
  }
}
