/**
 * 会话列表面板。
 *
 * 规格依据 D3 §3.1：标题、副信息（工作区 · 相对时间）、状态徽标、未读圆点、选中态。
 * 数据由宿主注入（桩数据或 SessionHub 的真实投影），组件不认识协议对象。
 */

import {
  formatClock,
  relativeTime,
  Fs,
  PendingItem,
  Radius,
  SessionListItem,
  Sp,
  Sz
} from 'appstate';

@Component
export struct SessionListPane {
  @Prop sessions: SessionListItem[] = [];
  /**
   * 待决事项（用于算出每个会话的「待审核 N」）。
   *
   * 为什么要把待决传进来：`SessionSummary` **没有**「有几个待决」这个字段
   * （只有 sessionId/updatedAt/running/blank/cwd/projections），
   * 所以「待审核」必须由**已收到的待决列表**按 sessionId 计数得出——
   * 这是唯一有证据支撑的来源。
   */
  @Prop pending: PendingItem[] = [];
  @Prop selectedId: string = '';
  onSelect: (id: string) => void = () => {
  };
  /**
   * 新建会话（D1 §7.2 的「新建」入口）。
   *
   * 放在会话列表顶部而不是全局标题栏：新建会话是**列表级**动作，
   * 三种形态下会话区都由本组件承载，因此一处改动即可覆盖单栏/双栏/三栏。
   */
  onCreate: () => void = () => {
  };

  /**
   * 状态徽标文字（D3 §3.1：运行中 / 待审核 / 空闲 / 失败）。
   *
   * 【缺陷修正 · 真机验证时发现】
   *   原实现按**列表下标**硬编码：`index === 1 → '待审核 2'`、`index === 2 → '失败'`。
   *   那是给桩数据配的演示规则，接上真实 Host 后它继续生效——
   *   于是四个 `running:false, blank:true` 的真实会话被显示成
   *   「空闲 / 待审核 2 / 失败 / 空闲」。**界面在凭空捏造会话状态**，
   *   比显示不出来更糟：用户会去点「失败」的会话找原因。
   *
   *   现在只依据有证据的事实：
   *     1. `running` → 运行中
   *     2. 该会话的待决数 > 0 → 待审核 N（由已收到的待决列表计数）
   *     3. `blank` → 新会话（Host 侧已建好但还没有任何轮次）
   *     4. 其余 → 空闲
   *
   *   **「失败」被移除**，因为没有数据来源：`SessionSummary` 无错误字段，
   *   错误只通过 `api-session/error` 事件到达，而该事件的载荷形状尚未实测确认
   *   （见 D2 §8.7.5）。宁可不显示，也不猜。
   */
  private statusLabel(item: SessionListItem): string {
    if (item.running) {
      return '运行中';
    }
    const waiting: number = this.pendingCountFor(item.id);
    if (waiting > 0) {
      return `待审核 ${waiting}`;
    }
    if (item.blank) {
      return '新会话';
    }
    return '空闲';
  }

  private pendingCountFor(sessionId: string): number {
    let n: number = 0;
    for (let i = 0; i < this.pending.length; i++) {
      if (this.pending[i].sessionId === sessionId) {
        n++;
      }
    }
    return n;
  }

  build() {
    Column() {
      Row() {
        Blank()
        Text('＋ 新建会话')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .padding({ left: Sp.S, right: Sp.S, top: Sp.XS, bottom: Sp.XS })
          .onClick(() => {
            this.onCreate();
          })
      }
      .width('100%')
      .padding({ left: Sp.S, right: Sp.S, top: Sp.S })

      if (this.sessions.length === 0) {
        Column({ space: Sp.M }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(40)
            .fontColor([$r('sys.color.font_tertiary')])
          Text('还没有会话')
            .fontSize(Fs.BODY)
            .fontColor($r('sys.color.font_secondary'))
          Text('在 Host 上新建会话后会自动出现在这里')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: Sp.XS }) {
          ForEach(this.sessions, (item: SessionListItem) => {
            ListItem() {
              this.sessionRow(item)
            }
          }, (item: SessionListItem) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: Sp.S, right: Sp.S, top: Sp.S })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sessionRow(item: SessionListItem) {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        Text(item.title.length > 0 ? item.title : '（未命名会话）')
          .fontSize(Fs.BODY)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.statusBadge(this.statusLabel(item), item.running)
      }
      .width('100%')

      Row({ space: Sp.S }) {
        Text(this.subtitleOf(item))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(formatClock(item.updatedAt))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: Sp.M, right: Sp.M, top: Sp.M, bottom: Sp.M })
    .borderRadius(Radius.M)
    .backgroundColor(this.selectedId === item.id
      ? $r('sys.color.background_secondary')
      : Color.Transparent)
    .onClick(() => {
      this.onSelect(item.id);
    })
  }

  private subtitleOf(item: SessionListItem): string {
    const time: string = relativeTime(item.updatedAt, Date.now());
    if (item.cwd.length === 0) {
      return time;
    }
    return time.length === 0 ? item.cwd : `${item.cwd} · ${time}`;
  }

  /** 状态徽标：运行中带脉冲点，失败/待审核用语义色（D3 §3.1、§7 色彩不唯一） */
  @Builder
  statusBadge(label: string, running: boolean) {
    Row({ space: 4 }) {
      if (running) {
        Circle({ width: 6, height: 6 })
          .fill($r('sys.color.confirm'))
      }
      Text(label)
        .fontSize(Fs.CAPTION)
        .fontColor(this.badgeColor(label))
    }
    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    .borderRadius(6)
    .backgroundColor($r('sys.color.background_secondary'))
  }

  private badgeColor(label: string): ResourceColor {
    if (label.startsWith('运行中')) {
      return $r('sys.color.confirm');
    }
    if (label.startsWith('待审核')) {
      return $r('sys.color.warning');
    }
    if (label.startsWith('失败')) {
      return $r('sys.color.alert');
    }
    return $r('sys.color.font_tertiary');
  }
}
