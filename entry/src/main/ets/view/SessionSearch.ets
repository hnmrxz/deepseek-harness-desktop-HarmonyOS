/**
 * 会话搜索（T023 新建：对照 `dshmobile/ui/screens/main/SessionSearch.kt` 的结果形态复刻）。
 *
 * ## 对照结构（SessionSearch.kt）
 *
 * 源文件的 `deriveSearchResults` 是**模型**（本仓对应 `appstate` 的 `mergeSessionSearch` +
 * `SessionSearchRow` + `SESSION_SEARCH_LIMIT`，已在 appstate 落地）；`SearchHit` 的**呈现**
 * 在源码的抽屉里：一行 = 会话标题 + 工作区名 + 内容片段（host 给的原文），外加
 * `SearchResultSet.hasMore`——"查询太宽、一屏放不下"要**说出来**，而不是静默截断
 * （源注释："past a screenful the list stops being an answer and starts being the thing
 * you were trying to search"）。本组件就是这一呈现层的独立组件。
 *
 * ## 为什么现在才成组件
 *
 * 此前搜索结果内联渲染在 `ConversationPane` 与 `WorkspaceBrowser` 两处（v1 遗留），
 * 同一份行结构写了两遍。本组件把行结构、上限提示、退化说明收口到一处；
 * 两个宿主的接线（替换内联块）属后续任务，本组件按既有数据面
 * （`SessionSearchRow` / `SESSION_SEARCH_LIMIT`）设计契约，接上即可用。
 *
 * ## 边界（与 `MessageFeedback` 同一条纪律）
 *
 * 查询文本与命中列表都归**宿主**持有（宿主调 `mergeSessionSearch` 合并本地标题命中与
 * Host 内容命中）；本组件只报"用户输入了什么 / 点了哪条"（`onQuery` / `onOpenHit`），
 * 不认识 `SessionHub`，也不决定"点击后去哪"。
 */

import {
  DsPalette,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  SESSION_SEARCH_LIMIT,
  SessionSearchRow,
  dsPaletteOf,
} from 'appstate';
import { DsIconButton, installDsSystemDarkWatch } from './NativePrimitives';

/* ───────── 组件级度量（SessionSearch.kt / 抽屉行渲染的字面量，逐条标注出处） ───────── */

/** 等宽/系统字体栈（Type.kt system UI stack） */
const SEARCH_FONT_SANS: string = 'sans-serif';

@Component
export struct SessionSearch {
  /** 搜索框当前文本（宿主持有真值；本组件受控显示） */
  @Prop query: string = '';
  /** 合并后的命中列表（宿主调 `mergeSessionSearch` 的产物） */
  @Prop rows: SessionSearchRow[] = [];
  /**
   * 退化说明（宿主给出，如实透出：如"Host 不支持内容搜索，仅按标题/工作区匹配"）。
   * 空串 = 不显示。
   */
  @Prop note: string = '';
  /** 是否给关闭按钮（宿主的搜索栏可关时才给；接上 `onClose` 才有意义） */
  @Prop closable: boolean = false;
  /** 搜索框占位文案（默认按会话搜索；工作区宿主可换成自己的语境） */
  @Prop placeholder: string = '搜索会话…';

  /** 用户输入（宿主负责合并命中；空查询 = 清空结果） */
  onQuery: (q: string) => void = () => {
  };
  /** 点一条命中（宿主负责跳转：切会话 + 收起搜索栏） */
  onOpenHit: (sessionId: string) => void = () => {
  };
  /** 关闭搜索栏（宿主收起；`closable` 为 true 时显示按钮） */
  onClose: () => void = () => {
  };

  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  /** 命中数达到上游上限（对照 `SearchResultSet.hasMore`：说明"还有，列表没装下"） */
  private hitLimit(): boolean {
    return this.rows.length >= SESSION_SEARCH_LIMIT;
  }

  build() {
    Column({ space: DsSpacing.TINY }) {
      // 搜索框（对照源码抽屉的搜索 TextField：单行 + common_search 占位）
      Row({ space: DsSpacing.SMALL }) {
        TextInput({ text: this.query, placeholder: this.placeholder })
          .fontSize(DsType.STD_14.size)
          .fontFamily(SEARCH_FONT_SANS)
          .fontColor(this.palette().labelPrimary)
          .placeholderColor(this.palette().labelTertiary)
          .placeholderFont({ size: DsType.STD_14.size })
          .height(DsSpacing.TOUCH_TARGET)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.onQuery(v);
          })
        if (this.closable) {
          DsIconButton({
            icon: $r('sys.symbol.xmark'),
            a11y: '关闭搜索',
            onTap: () => {
              this.onClose();
            }
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.rows.length > 0) {
        ForEach(this.rows, (row: SessionSearchRow) => {
          this.hitRow(row)
        }, (row: SessionSearchRow) => row.sessionId)
        // 上限提示（对照源码 hasMore 的读法：不是"就这些"，是"列表装不下了"）
        if (this.hitLimit()) {
          Text(`结果已达上限（${SESSION_SEARCH_LIMIT} 条），试试更具体的查询。`)
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontWeight(DsType.CAPTION_11.weight)
            .fontFamily(SEARCH_FONT_SANS)
            .fontColor(this.palette().labelTertiary)
            .width('100%')
        }
      } else if (this.note.length > 0) {
        // 退化/失败说明如实透出（读不到 ≠ 没有结果）
        Text(this.note)
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontWeight(DsType.CAPTION_11.weight)
          .fontFamily(SEARCH_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 一条命中（对照源码 `SearchHit` 的三段：标题 + 工作区名 + 内容片段）。
   * 标题/工作区是本地匹配，片段是 Host 给的原文（空串不画那一行）。
   */
  @Builder
  hitRow(row: SessionSearchRow) {
    Row({ space: DsSpacing.SMALL }) {
      Column({ space: DsSpacing.TINY }) {
        Row({ space: DsSpacing.SMALL }) {
          Text(row.title)
            .fontSize(DsType.SMALL_13_STRONG.size)
            .lineHeight(DsType.SMALL_13_STRONG.lineHeight)
            .fontWeight(DsType.SMALL_13_STRONG.weight)
            .fontFamily(SEARCH_FONT_SANS)
            .fontColor(this.palette().labelPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (row.workspace.length > 0) {
            Text(row.workspace)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontWeight(DsType.CAPTION_11.weight)
              .fontFamily(SEARCH_FONT_SANS)
              .fontColor(this.palette().labelTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (row.snippet.length > 0) {
          Text(row.snippet)
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontWeight(DsType.CAPTION_11.weight)
            .fontFamily(SEARCH_FONT_SANS)
            .fontColor(this.palette().labelSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(DsSpacing.SMALL)
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().bgModulePlatform)
    .onClick(() => {
      this.onOpenHit(row.sessionId);
    })
    .accessibilityText(row.snippet.length > 0
      ? `${row.title}，命中片段：${row.snippet}` : row.title)
  }
}
