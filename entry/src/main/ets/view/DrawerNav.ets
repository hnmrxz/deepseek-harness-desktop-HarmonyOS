/**
 * 左侧抽屉：会话列表（v2 T019：对照 `dshmobile/ui/screens/main/ChatListDrawer.kt` 源码级复刻）。
 *
 * 【对照源文件】`.research/deepseek-harness-mobile/app/src/main/java/com/labteto/dshmobile/
 * ui/screens/main/ChatListDrawer.kt`（`ChatListDrawer` / `WorkspaceHeader` / `SessionRowItem` /
 * `SearchResultRow` / `indexSubagents`）与 `ArchivedSessions.kt`（归档区语义）。
 *
 * ## 结构对照（源码 → 本组件）
 *
 * · 标题行：「会话」LARGE_20 + 搜索钮（搜索开时 tint=accent，关时 labelTertiary）。
 * · `DsButton`「新建会话」（Info 变体、plus 图标、满宽）。
 * · 折叠搜索框：关掉搜索**同时清空查询词**（源码注释：藏起来的输入框还留着词，
 *   列表就被一个看不见的东西过滤着）。
 * · 列表 = 工作区分组（chevron 折叠头 + 会话行）→ 已归档折叠区 → 空态 `DsEmptyHero`。
 * · 会话行：当前会话 accent 竖条（2×24 r1，源码注释：低对比侧栏上竖条比底色更快读出
 *   "你在哪"）+ 子代理 chevron（**独立点目标**：打开会话与看它派生了什么是两个意图，
 *   源码注释照录要义）+ `DsStateDot` + 标题 + cwd 末段 · 相对时间 + 子代理计数 pill。
 * · 子代理**嵌套**在自己的父会话下（`indexSubagents` 的移植：按直接父分组、fork 留在
 *   顶层、父被归档/空白的挂到最近的可见祖先、环族谱不挂）。
 * · 空白会话（`blank`）不列（源码规则：harness 把无轮次会话当草稿位复用，列出来只会
 *   积累空行）；时间用**相对时间**（时钟分不出"一小时前"和"上周二"——源码注释原话）。
 *
 * ## 与源码的刻意偏离（缺通道 / 缺数据，不放假入口 P7-18）
 *
 * · 手势滑出/跟手/关闭动画归 `RemoteShell`（T018 的领地，见其头注释）。
 * · `SortChip`（manual/updated 排序）与设置钮：`WorkspaceBrowserFacade` 没有对应通道，
 *   不放点了没反应的假钮。会话按 facade 给的顺序（Host 自己的行序）。
 * · 工作区长按菜单（重命名/删除）与会话长按菜单（重命名/fork/归档）：无通道，省略；
 *   归档动作在右侧详情面板（`RemoteShell.detailsPanelBody` 的会话卡）有真通道。
 * · `pendingInteraction` 的 Warning 点与「需要处理」pill：`SessionListItem` 没建模该字段。
 * · 「未分组会话」区（源码 sessions-header）：facade 只有 per-workspace 的
 *   `sessionsOf`，没有全局会话清单，推不出"不属于任何工作区的会话"。
 * · 搜索：源码本地匹配即时、内容搜索 250ms 防抖；本组件把查询词原样交给
 *   `f.onSearchSessions`，合并（本地标题命中 + Host 内容命中）在中枢完成。
 */

import {
  DsAnimation,
  DsPalette,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  SessionListItem,
  SessionSearchRow,
  WorkspaceItem,
  baseNameOf,
  dsPaletteOf,
  isSubagentSession,
  relativeTime,
  sessionDisplayTitle,
  sessionEmptyCopy,
} from 'appstate';
import type { WorkspaceBrowserFacade } from './WorkspaceBrowser';
import {
  DsButton,
  DsButtonVariant,
  DsDisclosureRow,
  DsEmptyHero,
  DsPill,
  DsSectionHeader,
  DsStateDot,
  DsStateDotState,
  dsTweenCurve,
  installDsSystemDarkWatch,
} from './NativePrimitives';

/* ───────── 组件级度量（ChatListDrawer.kt 的 dp 字面量，逐条标注出处） ───────── */

/** SessionRowItem `padding(start = (depth * 16).dp)`：子代理嵌套的缩进步长 */
const DRAWER_INDENT_STEP: number = 16;
/** SessionRowItem `Modifier.width(2.dp).height(24.dp).clip(RoundedCornerShape(1.dp))`：当前会话竖条 */
const RAIL_WIDTH: number = 2;
const RAIL_HEIGHT: number = 24;
const RAIL_RADIUS: number = 1;
/** SessionRowItem / WorkspaceHeader 里 chevron 与加号的 `size(16.dp)` */
const ROW_ICON: number = 16;
/** ChatTopBar 同款图标钮字面量（图标 18；触达槽 48 由 DsSpacing.TOUCH_TARGET 保证） */
const HEADER_ICON: number = 18;

/** 源码 `subtree()` 的 (row, depth) 对——ArkTS 没有元组，落成接口 */
interface SessionDepth {
  session: SessionListItem;
  depth: number;
}

/** 列表行的判别结构（List 的单 ForEach 消费；字段按 kind 取用） */
enum DrawerRowKind {
  WORKSPACE = 'workspace',
  SESSION = 'session',
  ARCHIVED_HEADER = 'archived_header',
  EMPTY = 'empty',
  SEARCH_HEADER = 'search_header',
  SEARCH_EMPTY = 'search_empty',
  SEARCH_RESULT = 'search_result',
}

interface DrawerRow {
  kind: DrawerRowKind;
  key: string;
  /** WORKSPACE：组头数据 */
  workspace?: WorkspaceItem;
  /** WORKSPACE：根会话数（不含子代理——计数说的是"这一组有几场会话"） */
  rootCount: number;
  /** WORKSPACE：组是否折叠 */
  collapsed: boolean;
  /** SESSION：会话数据 */
  session?: SessionListItem;
  /** SESSION：缩进深度 */
  depth: number;
  /** SESSION：直接子代理数 */
  childCount: number;
  /** SESSION：子代理组是否展开 */
  childrenExpanded: boolean;
  /** SESSION：是否当前会话 */
  isCurrent: boolean;
  /** SEARCH_RESULT：扁平搜索行 */
  result?: SessionSearchRow;
}

/**
 * 左侧抽屉内容（§FR-056）。
 *
 * 门面契约：`@Prop f: WorkspaceBrowserFacade` + `onSelectSession` / `onNewSession`
 * （打开会话与新建后由宿主关抽屉）；手势与开合归 RemoteShell。
 */
@Component
export struct DrawerNav {
  /** 工作区浏览器门面（工作区树 / 归档集 / 搜索，均由中枢投影） */
  @Prop f: WorkspaceBrowserFacade;
  /** 选择会话（宿主负责 openSession + 关抽屉） */
  onSelectSession: (id: string) => void = () => {
  };
  /** 新建会话（宿主负责 createSessionIn + 关抽屉） */
  onNewSession: () => void = () => {
  };

  /** 搜索框是否展开（折叠式，见文件头说明） */
  @State searchOpen: boolean = false;
  /** 搜索词（唯一真值在本组件；结果由中枢算好回填 `f.sessionSearchRows`） */
  @State query: string = '';
  /** 工作区折叠的显式选择（true=显式折叠；默认=「当前会话所在组不折叠」，源码同规） */
  @State wsCollapsed: string[] = [];
  /** 工作区展开的显式选择（源码 `collapsed` map 存的是三态，这里拆成两张表） */
  @State wsExpanded: string[] = [];
  /** 会话子代理组的显式折叠（默认=只有通往当前会话的链路展开，源码 openPath 同规） */
  @State sesCollapsed: string[] = [];
  /** 会话子代理组的显式展开 */
  @State sesExpanded: string[] = [];
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  /* ═══════════════ 派生数据（每次渲染重算；全部是内存里的字符串/数组操作） ═══════════════ */

  /** 全量会话（含归档与空白；工作区各组的并集 + 归档集），供父链游走建索引用 */
  private allSessions(): SessionListItem[] {
    const out: SessionListItem[] = [];
    const workspaces: WorkspaceItem[] = this.f.workspaces;
    for (let i = 0; i < workspaces.length; i++) {
      const list: SessionListItem[] = this.f.sessionsOf(workspaces[i]);
      for (let j = 0; j < list.length; j++) {
        out.push(list[j]);
      }
    }
    const archived: SessionListItem[] = this.f.archivedSessions();
    for (let i = 0; i < archived.length; i++) {
      out.push(archived[i]);
    }
    return out;
  }

  /** 源码 `listable`：非空白且未归档的会话（归档集以 facade 的 id 集为准） */
  private listableSessions(all: SessionListItem[]): SessionListItem[] {
    const archivedIds: string[] = this.f.archivedSessionIds;
    const out: SessionListItem[] = [];
    for (let i = 0; i < all.length; i++) {
      const s: SessionListItem = all[i];
      if (s.blank || archivedIds.indexOf(s.id) >= 0) {
        continue;
      }
      out.push(s);
    }
    return out;
  }

  /**
   * `indexSubagents` 的移植：子代理按**直接父**分组。
   *
   * 判别用 `origin`（源码注释：普通 fork 也会设 parentSessionId，而 fork 是独立会话、
   * 该留在顶层）；父被归档/空白时挂到最近的可见祖先（避免整行消失），环族谱由
   * visited 集合挡住（否则会把自己嵌进自己里、一行也渲染不出来——源码注释原话）。
   */
  private childrenIndex(listable: SessionListItem[], byId: Map<string, SessionListItem>):
    Map<string, SessionListItem[]> {
    const listableIds: Set<string> = new Set<string>();
    for (let i = 0; i < listable.length; i++) {
      listableIds.add(listable[i].id);
    }
    const out: Map<string, SessionListItem[]> = new Map<string, SessionListItem[]>();
    for (let i = 0; i < listable.length; i++) {
      const child: SessionListItem = listable[i];
      if (child.origin.indexOf('subagent') < 0) {
        continue;
      }
      // 游走到最近的可见祖先；visited 以 child 自己为种子，环走不回自己
      const visited: Set<string> = new Set<string>();
      visited.add(child.id);
      let cursor: string = child.parentSessionId;
      let attach: string = '';
      while (cursor.length > 0 && !visited.has(cursor)) {
        visited.add(cursor);
        if (listableIds.has(cursor)) {
          attach = cursor;
          break;
        }
        const parent: SessionListItem | undefined = byId.get(cursor);
        cursor = parent !== undefined ? parent.parentSessionId : '';
      }
      if (attach.length === 0) {
        // 孤儿（整条祖先链都归档/空白）：留在顶层，行尾给「子代理」pill 交代身份
        continue;
      }
      const bucket: SessionListItem[] | undefined = out.get(attach);
      if (bucket !== undefined) {
        bucket.push(child);
      } else {
        out.set(attach, [child]);
      }
    }
    return out;
  }

  /** 源码 `openPath`：当前会话到根的整条链（抽屉中途打开时，能看到自己在哪里） */
  private openPathOf(byId: Map<string, SessionListItem>): Set<string> {
    const out: Set<string> = new Set<string>();
    let cursor: SessionListItem | undefined = byId.get(this.f.selectedSessionId);
    while (cursor !== undefined && !out.has(cursor.id)) {
      out.add(cursor.id);
      cursor = cursor.parentSessionId.length > 0 ? byId.get(cursor.parentSessionId) : undefined;
    }
    return out;
  }

  /** 会话的子代理组是否展开（显式选择优先；默认=在通往当前会话的链上） */
  private isSessionExpanded(id: string, openPath: Set<string>): boolean {
    if (this.sesCollapsed.indexOf(id) >= 0) {
      return false;
    }
    if (this.sesExpanded.indexOf(id) >= 0) {
      return true;
    }
    return openPath.has(id);
  }

  private toggleSessionChildren(id: string, openPath: Set<string>): void {
    const next: boolean = !this.isSessionExpanded(id, openPath);
    // 三态语义（源码 collapsed map 只存显式选择）：翻到哪边，就在哪边的表里登记、
    // 从对面的表里销掉；其他行的显式选择不动
    if (next) {
      this.sesCollapsed = removeFrom(this.sesCollapsed, id);
      this.sesExpanded = addTo(this.sesExpanded, id);
    } else {
      this.sesExpanded = removeFrom(this.sesExpanded, id);
      this.sesCollapsed = addTo(this.sesCollapsed, id);
    }
  }

  /** 工作区组是否折叠（显式选择优先；默认=「当前会话的子树在这组里」才展开） */
  private isWorkspaceCollapsed(w: WorkspaceItem, openPath: Set<string>, rootIds: string[]): boolean {
    if (this.wsCollapsed.indexOf(w.id) >= 0) {
      return true;
    }
    if (this.wsExpanded.indexOf(w.id) >= 0) {
      return false;
    }
    let holdsCurrent: boolean = false;
    for (let i = 0; i < rootIds.length; i++) {
      if (openPath.has(rootIds[i])) {
        holdsCurrent = true;
        break;
      }
    }
    return !holdsCurrent;
  }

  private toggleWorkspace(w: WorkspaceItem, openPath: Set<string>, rootIds: string[]): void {
    const nextCollapsed: boolean = !this.isWorkspaceCollapsed(w, openPath, rootIds);
    if (nextCollapsed) {
      this.wsExpanded = removeFrom(this.wsExpanded, w.id);
      this.wsCollapsed = addTo(this.wsCollapsed, w.id);
    } else {
      this.wsCollapsed = removeFrom(this.wsCollapsed, w.id);
      this.wsExpanded = addTo(this.wsExpanded, w.id);
    }
  }

  /** 源码 `subtree()`：一棵顶层会话的深度优先展开（逐行遵守各自的折叠选择） */
  private subtreeOf(root: SessionListItem, children: Map<string, SessionListItem[]>,
    openPath: Set<string>): SessionDepth[] {
    const out: SessionDepth[] = [];
    const walk = (row: SessionListItem, depth: number): void => {
      out.push({ session: row, depth: depth });
      const kids: SessionListItem[] | undefined = children.get(row.id);
      if (kids === undefined || kids.length === 0 || !this.isSessionExpanded(row.id, openPath)) {
        return;
      }
      for (let i = 0; i < kids.length; i++) {
        walk(kids[i], depth + 1);
      }
    };
    walk(root, 0);
    return out;
  }

  /**
   * 把整棵树摊平成 List 的一维行集（List 的单一 ForEach 消费）。
   * 搜索期间整棵树换成扁平结果（源码 `return@LazyColumn` 同语义）。
   */
  private buildRows(): DrawerRow[] {
    const out: DrawerRow[] = [];
    if (this.query.trim().length > 0) {
      out.push({
        kind: DrawerRowKind.SEARCH_HEADER, key: 'search-header', rootCount: 0, collapsed: false,
        depth: 0, childCount: 0, childrenExpanded: false, isCurrent: false,
      });
      const rows: SessionSearchRow[] = this.f.sessionSearchRows;
      if (rows.length === 0) {
        out.push({
          kind: DrawerRowKind.SEARCH_EMPTY, key: 'search-empty', rootCount: 0, collapsed: false,
          depth: 0, childCount: 0, childrenExpanded: false, isCurrent: false,
        });
      }
      for (let i = 0; i < rows.length; i++) {
        out.push({
          kind: DrawerRowKind.SEARCH_RESULT, key: `sr-${rows[i].sessionId}`, result: rows[i],
          rootCount: 0, collapsed: false, depth: 0, childCount: 0, childrenExpanded: false,
          isCurrent: false,
        });
      }
      return out;
    }

    const all: SessionListItem[] = this.allSessions();
    const byId: Map<string, SessionListItem> = new Map<string, SessionListItem>();
    for (let i = 0; i < all.length; i++) {
      byId.set(all[i].id, all[i]);
    }
    const listable: SessionListItem[] = this.listableSessions(all);
    const children: Map<string, SessionListItem[]> = this.childrenIndex(listable, byId);
    const nestedIds: Set<string> = new Set<string>();
    children.forEach((kids: SessionListItem[]) => {
      for (let i = 0; i < kids.length; i++) {
        nestedIds.add(kids[i].id);
      }
    });
    const openPath: Set<string> = this.openPathOf(byId);

    let anyShown: boolean = false;
    const workspaces: WorkspaceItem[] = this.f.workspaces;
    for (let w = 0; w < workspaces.length; w++) {
      const ws: WorkspaceItem = workspaces[w];
      const wsSessions: SessionListItem[] = this.f.sessionsOf(ws);
      const roots: SessionListItem[] = [];
      for (let i = 0; i < wsSessions.length; i++) {
        const s: SessionListItem = wsSessions[i];
        // 根 = 可列出、未被嵌套（被嵌套的子代理画在父行下面，不占组头计数）
        if (!s.blank && this.f.archivedSessionIds.indexOf(s.id) < 0 && !nestedIds.has(s.id)) {
          roots.push(s);
        }
      }
      if (roots.length === 0) {
        continue;
      }
      anyShown = true;
      const rootIds: string[] = [];
      for (let i = 0; i < roots.length; i++) {
        rootIds.push(roots[i].id);
      }
      const collapsed: boolean = this.isWorkspaceCollapsed(ws, openPath, rootIds);
      out.push({
        kind: DrawerRowKind.WORKSPACE, key: `ws-${ws.id}`, workspace: ws,
        rootCount: roots.length, collapsed: collapsed, depth: 0, childCount: 0,
        childrenExpanded: false, isCurrent: false,
      });
      if (!collapsed) {
        for (let i = 0; i < roots.length; i++) {
          const flat: SessionDepth[] = this.subtreeOf(roots[i], children, openPath);
          for (let j = 0; j < flat.length; j++) {
            const kids: SessionListItem[] | undefined = children.get(flat[j].session.id);
            out.push({
              kind: DrawerRowKind.SESSION, key: `ses-${flat[j].session.id}`, session: flat[j].session,
              rootCount: 0, collapsed: false, depth: flat[j].depth,
              childCount: kids !== undefined ? kids.length : 0,
              childrenExpanded: this.isSessionExpanded(flat[j].session.id, openPath),
              isCurrent: flat[j].session.id === this.f.selectedSessionId,
            });
          }
        }
      }
    }

    const archived: SessionListItem[] = this.f.archivedSessions();
    if (archived.length > 0) {
      anyShown = true;
      out.push({
        kind: DrawerRowKind.ARCHIVED_HEADER, key: 'archived', rootCount: archived.length,
        collapsed: !this.f.archiveOpen, depth: 0, childCount: 0, childrenExpanded: false,
        isCurrent: false,
      });
      if (this.f.archiveOpen) {
        for (let i = 0; i < archived.length; i++) {
          out.push({
            kind: DrawerRowKind.SESSION, key: `arc-${archived[i].id}`, session: archived[i],
            rootCount: 0, collapsed: false, depth: 0, childCount: 0, childrenExpanded: false,
            isCurrent: false,   // 源码归档行显式传 isCurrent=false
          });
        }
      }
    }

    if (!anyShown) {
      // 空态按核心阶段分档（与 WorkspaceBrowser 同一份文案模型）
      out.push({
        kind: DrawerRowKind.EMPTY, key: 'empty', rootCount: 0, collapsed: false,
        depth: 0, childCount: 0, childrenExpanded: false, isCurrent: false,
      });
    }
    return out;
  }

  /** 显示标题：显式标题 → cwd 末段 → id（源码 `sessionTitle` 的兜底链） */
  private titleOf(s: SessionListItem): string {
    const title: string = sessionDisplayTitle(s);
    if (title.length > 0) {
      return title;
    }
    const folder: string = s.cwd.length > 0 ? baseNameOf(s.cwd) : '';
    return folder.length > 0 ? folder : s.id;
  }

  /** 第二行：cwd 末段 · 相对时间（cwd 拿不到就只画时间——源码同判据） */
  private metaLineOf(s: SessionListItem): string {
    const folder: string = s.cwd.length > 0 ? baseNameOf(s.cwd) : '';
    const time: string = relativeTime(s.updatedAt, Date.now());
    if (folder.length > 0) {
      return `${folder} · ${time}`;
    }
    return time;
  }

  /* ═══════════════ 布局 ═══════════════ */

  build() {
    // 源码：fillMaxSize + background(sidebar) + safeDrawingPadding + padding(horizontal=medium)
    Column() {
      // 标题行（源码：title large20 + Search 钮 + SortChip + Settings 钮；
      // 后两者无 facade 通道，见文件头「刻意偏离」）
      Row() {
        Text('会话')
          .fontSize(DsType.LARGE_20.size)
          .lineHeight(DsType.LARGE_20.lineHeight)
          .fontWeight(DsType.LARGE_20.weight)
          .fontColor(this.palette().labelPrimary)
          .layoutWeight(1)
        this.iconButton($r('sys.symbol.magnifyingglass'), '搜索会话',
          this.searchOpen ? this.palette().accent : this.palette().labelTertiary, () => {
            // 关掉搜索同时清空查询词：藏起来的输入框还留着词，列表就被看不见的东西过滤着
            const next: boolean = !this.searchOpen;
            this.searchOpen = next;
            if (!next && this.query.length > 0) {
              this.query = '';
              this.f.onSearchSessions('');
            }
          })
      }
      .width('100%')
      .padding({ top: DsSpacing.SMALL, bottom: DsSpacing.TINY })
      .alignItems(VerticalAlign.Center)

      DsButton({
        text: '新建会话',
        variant: DsButtonVariant.INFO,
        showIcon: true,
        icon: $r('sys.symbol.plus'),
        a11y: '新建会话',
        onTap: () => {
          this.onNewSession();
        }
      })
        .width('100%')

      // 折叠搜索框：不为常见情形永久占掉一行（手机高的抽屉里那是纯开销——源码注释）
      if (this.searchOpen) {
        Column() {
          TextInput({ text: this.query, placeholder: '搜索会话…' })
            .fontSize(DsType.STD_14.size)
            .fontColor(this.palette().labelPrimary)
            .placeholderColor(this.palette().labelTertiary)
            .caretColor(this.palette().accent)
            .constraintSize({ minHeight: DsSpacing.TOUCH_TARGET - 8 })
            .width('100%')
            .onChange((value: string) => {
              this.query = value;
              this.f.onSearchSessions(value);
            })
          // 能力降级说明（老 Host 没有内容搜索）：只在搜着的时候说一次，悄悄地
          if (this.query.trim().length > 0 && this.f.sessionSearchNote.length > 0) {
            Text(this.f.sessionSearchNote)
              .fontSize(DsType.CAPTION_11.size)
              .lineHeight(DsType.CAPTION_11.lineHeight)
              .fontColor(this.palette().labelCaption)
              .width('100%')
              .padding({ top: DsSpacing.TINY })
          }
        }
        .width('100%')
        .padding({ top: DsSpacing.SMALL })
      }

      List() {
        ForEach(this.buildRows(), (row: DrawerRow) => {
          ListItem() {
            this.rowOf(row)
          }
        }, (row: DrawerRow) => row.key)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ top: DsSpacing.SMALL })

      // 底部「新建工作区」行（源码：clip(row) + clickable + Add 16dp + std14 文案）
      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(ROW_ICON)
          .fontColor([this.palette().labelTertiary])
        Text('新建工作区')
          .fontSize(DsType.STD_14.size)
          .lineHeight(DsType.STD_14.lineHeight)
          .fontWeight(DsType.STD_14.weight)
          .fontColor(this.palette().labelSecondary)
          .margin({ left: DsSpacing.SMALL })
      }
      .width('100%')
      .borderRadius(DsShape.ROW)
      .padding({ top: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.f.openFolderPicker();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().sidebar)
    .padding({ left: DsSpacing.MEDIUM, right: DsSpacing.MEDIUM })
  }

  /** List 行分派 */
  @Builder
  rowOf(row: DrawerRow) {
    if (row.kind === DrawerRowKind.WORKSPACE && row.workspace !== undefined) {
      this.workspaceHeader(row.workspace, row.collapsed, row.rootCount)
    } else if (row.kind === DrawerRowKind.SESSION && row.session !== undefined) {
      this.sessionRow(row.session, row.depth, row.childCount, row.childrenExpanded, row.isCurrent)
    } else if (row.kind === DrawerRowKind.ARCHIVED_HEADER) {
      this.archivedHeader(row.rootCount)
    } else if (row.kind === DrawerRowKind.EMPTY) {
      DsEmptyHero({
        headline: sessionEmptyCopy(this.f.coreView.phase).title,
        subtitle: sessionEmptyCopy(this.f.coreView.phase).hint
      })
    } else if (row.kind === DrawerRowKind.SEARCH_HEADER) {
      DsSectionHeader({ title: '搜索' })
    } else if (row.kind === DrawerRowKind.SEARCH_EMPTY) {
      Text('没有匹配的会话。')
        .fontSize(DsType.STD_14.size)
        .lineHeight(DsType.STD_14.lineHeight)
        .fontColor(this.palette().labelTertiary)
        .padding({ top: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
    } else if (row.kind === DrawerRowKind.SEARCH_RESULT && row.result !== undefined) {
      this.searchResultRow(row.result)
    }
  }

  /**
   * 工作区组头（源码 `WorkspaceHeader`）：chevron + std14Strong 标题 + 会话数。
   * 长按菜单（重命名/删除/组内新建）无 facade 通道，省略——见文件头「刻意偏离」。
   */
  @Builder
  workspaceHeader(w: WorkspaceItem, collapsed: boolean, rootCount: number) {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(ROW_ICON)
        .fontColor([this.palette().labelTertiary])
        .rotate({ angle: collapsed ? 0 : 90 })
        .animation({
          duration: DsAnimation.CHEVRON.durationMs,
          curve: dsTweenCurve(DsAnimation.CHEVRON)
        })
      Text(w.name.length > 0 ? w.name : baseNameOf(w.path))
        .fontSize(DsType.STD_14_STRONG.size)
        .lineHeight(DsType.STD_14_STRONG.lineHeight)
        .fontWeight(DsType.STD_14_STRONG.weight)
        .fontColor(this.palette().labelSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: DsSpacing.TINY })
      Text(`${rootCount}`)
        .fontSize(DsType.CAPTION_11.size)
        .lineHeight(DsType.CAPTION_11.lineHeight)
        .fontColor(this.palette().labelCaption)
    }
    .width('100%')
    .borderRadius(DsShape.ROW)
    .padding({ top: DsSpacing.XSMALL, bottom: DsSpacing.XSMALL })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      const all: SessionListItem[] = this.allSessions();
      const byId: Map<string, SessionListItem> = new Map<string, SessionListItem>();
      for (let i = 0; i < all.length; i++) {
        byId.set(all[i].id, all[i]);
      }
      const openPath: Set<string> = this.openPathOf(byId);
      const wsSessions: SessionListItem[] = this.f.sessionsOf(w);
      const rootIds: string[] = [];
      for (let i = 0; i < wsSessions.length; i++) {
        if (!wsSessions[i].blank) {
          rootIds.push(wsSessions[i].id);
        }
      }
      this.toggleWorkspace(w, openPath, rootIds);
    })
  }

  /**
   * 会话行（源码 `SessionRowItem`）：缩进 → 竖条 → 子代理 chevron → 状态点 →
   * 标题/元信息 → 计数 pill。
   */
  @Builder
  sessionRow(s: SessionListItem, depth: number, childCount: number, childrenExpanded: boolean,
    isCurrent: boolean) {
    // 外层只做缩进：源码 Row 的 padding(start = depth*16) 在背景色**之前**，
    // 高亮块从缩进之后开始（内层 Row 才带背景与点击）
    Row() {
      Row() {
        // 当前会话竖条：低对比侧栏上比底色更快读出"你在哪"（源码注释）
        Column()
          .width(RAIL_WIDTH)
          .height(RAIL_HEIGHT)
          .borderRadius(RAIL_RADIUS)
          .backgroundColor(isCurrent ? this.palette().accent : Color.Transparent)
        if (childCount > 0) {
          // chevron 是独立点目标：打开会话与看它派生了什么是两个意图（源码注释）
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(ROW_ICON)
            .fontColor([this.palette().labelTertiary])
            .rotate({ angle: childrenExpanded ? 90 : 0 })
            .animation({
              duration: DsAnimation.CHEVRON.durationMs,
              curve: dsTweenCurve(DsAnimation.CHEVRON)
            })
            .margin({ left: DsSpacing.SMALL })
            .onClick(() => {
              const all: SessionListItem[] = this.allSessions();
              const byId: Map<string, SessionListItem> = new Map<string, SessionListItem>();
              for (let i = 0; i < all.length; i++) {
                byId.set(all[i].id, all[i]);
              }
              this.toggleSessionChildren(s.id, this.openPathOf(byId));
            })
        } else {
          // 空位对齐：混排的整列标题起点要一致（源码 Spacer(16.dp)）
          Column()
            .width(ROW_ICON)
            .margin({ left: DsSpacing.SMALL })
        }
        DsStateDot({
          state: s.running ? DsStateDotState.RUNNING : DsStateDotState.IDLE
        })
          .margin({ left: DsSpacing.TINY })
        Column() {
          Text(this.titleOf(s))
            .fontSize(DsType.STD_14.size)
            .lineHeight(DsType.STD_14.lineHeight)
            .fontWeight(DsType.STD_14.weight)
            .fontColor(this.palette().labelPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.metaLineOf(s))
            .fontSize(DsType.CAPTION_11.size)
            .lineHeight(DsType.CAPTION_11.lineHeight)
            .fontColor(this.palette().labelCaption)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: DsSpacing.SMALL })
        if (childCount > 0) {
          // 计数替代旧的「子代理」pill：孩子缩进在下时，值得说的是收起时下面有几个
          DsPill({ text: `${childCount}` })
            .margin({ left: DsSpacing.XSMALL })
        } else if (isSubagentSession(s) && depth === 0) {
          // 只有孤儿走到这里（祖先链全归档/空白）——缩进说不出它是什么，用 pill 交代
          DsPill({ text: '子代理' })
            .margin({ left: DsSpacing.XSMALL })
        }
      }
      .layoutWeight(1)
      .borderRadius(DsShape.ROW)
      .backgroundColor(isCurrent ? this.palette().sidebarNavActive : Color.Transparent)
      .padding({ left: DsSpacing.SMALL, right: DsSpacing.SMALL,
        top: DsSpacing.XSMALL, bottom: DsSpacing.XSMALL })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onSelectSession(s.id);
      })
    }
    .width('100%')
    .padding({ left: depth * DRAWER_INDENT_STEP })
  }

  /** 已归档折叠区（源码：DisclosureRow「已归档」+ 数量摘要；开合走 facade 的共享态） */
  @Builder
  archivedHeader(count: number) {
    DsDisclosureRow({
      title: '已归档',
      summary: `${count}`,
      expanded: this.f.archiveOpen,
      onToggle: () => {
        this.f.setArchiveOpen(!this.f.archiveOpen);
      }
    })
  }

  /**
   * 搜索结果行（源码 `SearchResultRow`）：先说会话叫什么，再说它住在哪，
   * 最后才是命中的片段——结果应当叫出你正要打开的那个东西（源码注释）。
   */
  @Builder
  searchResultRow(row: SessionSearchRow) {
    Column() {
      Row() {
        Text(row.title)
          .fontSize(DsType.ROW_TEXT.size)
          .lineHeight(DsType.ROW_TEXT.lineHeight)
          .fontWeight(DsType.ROW_TEXT.weight)
          .fontColor(this.palette().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (row.workspace.length > 0) {
        Text(row.workspace)
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontColor(this.palette().labelCaption)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (row.snippet.length > 0) {
        Text(row.snippet)
          .fontSize(DsType.CAPTION_11.size)
          .lineHeight(DsType.CAPTION_11.lineHeight)
          .fontColor(this.palette().labelSecondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .borderRadius(DsShape.ROW)
    .padding({ left: DsSpacing.TINY, right: DsSpacing.TINY,
      top: DsSpacing.XSMALL, bottom: DsSpacing.XSMALL })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onSelectSession(row.sessionId);
    })
  }

  /** 图标钮（对照 `DsIconButton`：48dp 保证触达、图标居中；ChatTopBar 的 18dp 档） */
  @Builder
  iconButton(symbol: Resource, a11y: string, tint: number, onTap: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(symbol)
        .fontSize(HEADER_ICON)
        .fontColor([tint])
    }
    .width(DsSpacing.TOUCH_TARGET)
    .height(DsSpacing.TOUCH_TARGET)
    .accessibilityText(a11y)
    .onClick(() => {
      onTap();
    })
  }
}

/* ───────── 小工具（string[] 的三态表操作） ───────── */

function addTo(list: string[], id: string): string[] {
  if (list.indexOf(id) >= 0) {
    return list;
  }
  const out: string[] = list.slice(0);
  out.push(id);
  return out;
}

function removeFrom(list: string[], id: string): string[] {
  const at: number = list.indexOf(id);
  if (at < 0) {
    return list;
  }
  return list.slice(0, at).concat(list.slice(at + 1));
}
