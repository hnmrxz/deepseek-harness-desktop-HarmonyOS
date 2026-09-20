/**
 * 添加 Host / 授权 / 配对页（T024：对照 `dshmobile/ui/screens/connect/ConnectScreen.kt`
 * 的版式复刻；失败呈现的语义对照 `ConnectDiagnosis.kt`）。
 *
 * ## 对照结构（ConnectScreen.kt）
 *
 * 源码是一条滚动长页：`ConnectHeader`（40dp WhaleMark + large20 名称 + small13 副题）
 * 之后按 `SectionHeader` 分节——手动连接（输入框 + **满宽 Info 按钮**）/ 发现的 Host
 * （节头右侧「扫描」动作 + 扫描进行行 + 结果卡）/ 记住的 Host（StateDot 卡）——
 * 版式只有一条铁律（源注释照录）："**可操作物之前至多一段说明文字**"。
 * v1 的 ①②③ 编号卡片收编为这三节；本组件保留 v1 的全部数据面与回调。
 *
 * ## 失败呈现（ConnectDiagnosis.kt 的语义，v1 的通道）
 *
 * 源码把失败归因为 14 种"人能执行动作"的 `ConnectFailure`，渲染成 **warnTertiary 面 +
 * Error 状态点 + 一句原因 + 一句动作**。本仓的归因通道是宿主给的
 * `resultText / resultOk / resultAdvice`（宿主侧已含 ConnectDiagnosis 同款的"建议动作"
 * 语义：401 → 重贴启动链接等）；本组件按源码的**视觉语言**渲染它（成功 = hoverSolid 面 +
 * Done 点；失败 = warnTertiary 面 + Error 点 + 建议行 + 「打开连接诊断」Ghost 按钮）。
 *
 * ## 保留 v1 的安全红线（一句话的排版改动，内容一字不删）
 *
 * 「不绑定 0.0.0.0、不伪造 Host 头、跨设备走加密隧道 + L0/L1 接入级别」是本项目红线
 * （D1 §6.4）。源码没有对应小节，但它的"通知面"（warnTertiary Surface）是这套设计语言里
 * "警告性事实"的容器——本侧把红线内容整体收进一个 warnTertiary 面，作为页面收尾。
 *
 * ## 刻意不搬的（源码有、本仓数据面没有——不造死控件）
 *
 *  · LAN/Relay 模式分段（`DsSegmented`）：本仓只有 LAN 直连 + 手动 URL，Relay 客户端
 *    不存在，画一个选不动的分段是死控件；
 *  · 扫描进度分数与「取消扫描」：`scanning` 只是布尔，没有进度回调；
 *  · 自动连接三个 ToggleRow：设置存储里没有对应键；
 *  · 连接阶段名（Validating/Reaching/…）：`busy` 只是布尔——用 RUNNING 状态点 + 文案
 *    表达"正在连接"，不虚构阶段。
 *
 * ## 桌面形态（T012，保留）
 *
 * 桌面档位（`dshLayoutMode`）下表单列收口居中（上限取 `Breakpoint.MD`，与档位判定同源），
 * 手机形态左对齐铺满。
 */

import {
  Breakpoint,
  DsPalette,
  DsShape,
  DsSpacing,
  DsThemePreference,
  DsType,
  HarmonyBorder,
  HostRecord,
  HostReadyState,
  RemoteHost,
  dsPaletteOf,
  hostReadyStateLabel,
} from 'appstate';
import {
  DsButton,
  DsButtonSize,
  DsButtonVariant,
  DsIconButton,
  DsPill,
  DsSectionHeader,
  DsStateDot,
  DsStateDotState,
  installDsSystemDarkWatch,
} from './NativePrimitives';

/* ───────── 组件级度量（ConnectScreen.kt 的 dp 字面量，逐条标注出处） ───────── */

/** ConnectScreen.kt `ConnectHeader`：WhaleMark 40dp */
const CONNECT_MARK_SIZE: number = 40;
/** ConnectScreen.kt `DiscoveredHarnessCard`：globe 图标宽 14dp（本仓用 wifi 符号——SDK 无 globe） */
const CONNECT_GLOBE_ICON_WIDTH: number = 14;
/** ConnectScreen.kt `ScanProgressRow`：无进度分数时的静态轨道高 4dp（`Box(height(4.dp))`） */
const CONNECT_TRACK_HEIGHT: number = 4;
/** 等宽/系统字体栈（Type.kt system UI stack） */
const CONNECT_FONT_SANS: string = 'sans-serif';

@Component
export struct ConnectPane {
  @Prop hosts: HostRecord[] = [];
  @Prop address: string = '';
  @Prop token: string = '';
  @Prop busy: boolean = false;
  /** 最近一次操作的结论（成功或失败都要说明"可以做什么"） */
  @Prop resultText: string = '';
  @Prop resultOk: boolean = false;
  @Prop resultAdvice: string = '';
  /** 自动发现是否可用（Host 侧需运行搭桥服务，D1 §6.5） */
  @Prop discoveryAvailable: boolean = false;
  /** §FR-059：LAN 发现扫描到的远程主机列表 */
  @Prop discoveredHosts: RemoteHost[] = [];
  /** §FR-059：是否正在扫描 */
  @Prop scanning: boolean = false;
  /**
   * T012（US2）：当前档位（`Index` 发布到 AppStorage）。桌面形态（非 single）下
   * 表单列收口居中。与 `Composer` / `MessageRow` 用同一个来源，不另立形态判定。
   */
  @StorageProp('dshLayoutMode') layoutMode: string = 'single';
  @StorageProp('dsSystemDark') systemDark: boolean = false;

  /** 桌面形态判定（档位字符串只在此处解释一次） */
  private isDesktopLike(): boolean {
    return this.layoutMode !== 'single';
  }

  /**
   * 表单列宽度上限。取 `Breakpoint.MD`（600vp，桌面形态的下限阈值）：
   * 表单收在"桌面起点宽度"内，窗口再宽只居中不加宽（600 与档位判定同源）。
   */
  private contentMaxWidthVp(): number {
    return Breakpoint.MD;
  }

  onAddressChange: (v: string) => void = () => {
  };
  onTokenChange: (v: string) => void = () => {
  };
  /** 认证并保存 */
  onSubmit: () => void = () => {
  };
  /*
   * E130/E144：`onSelectHost` / `onRemoveHost` 已删除（本应用只记一个 Host，
   * "使用/移除某一个"没有对应动作；详见 git 历史）。
   */
  onStartDiscovery: () => void = () => {
  };
  /** §FR-059：点击已发现的远程主机进行连接 */
  onConnectRemote: (host: RemoteHost) => void = () => {
  };
  onOpenDiagnostics: () => void = () => {
  };
  onBack: () => void = () => {
  };

  aboutToAppear(): void {
    installDsSystemDarkWatch();
  }

  private palette(): DsPalette {
    return dsPaletteOf(DsThemePreference.SYSTEM, this.systemDark);
  }

  build() {
    Column() {
      // 顶行（v1 契约：返回；对照源码顶行的 DsIconButton 形态）
      Row() {
        DsIconButton({
          icon: $r('sys.symbol.chevron_left'),
          a11y: '返回',
          tint: this.palette().labelPrimary,
          onTap: () => {
            this.onBack();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: DsSpacing.COMFORTABLE }) {
          this.connectHeader()
          this.manualSection()
          if (this.resultText.length > 0) {
            this.resultBlock()
          }
          this.discoveredSection()
          this.recentSection()
          this.securityNotice()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        // T012：桌面形态下表单收口（阈值与档位判定同源）
        .constraintSize({ maxWidth: this.contentMaxWidthVp() })
      }
      .layoutWeight(1)
      .width('100%')
      // 桌面形态水平居中（表单窄于视口时）；手机形态维持既有左上对齐
      .align(this.isDesktopLike() ? Alignment.Top : Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }

  // ───────────── 页头（对照 ConnectHeader：WhaleMark 40dp + large20 + small13） ─────────────

  @Builder
  connectHeader() {
    Row({ space: DsSpacing.MEDIUM }) {
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.foreground'))
          .width(CONNECT_MARK_SIZE)
          .height(CONNECT_MARK_SIZE)
          .objectFit(ImageFit.Contain)
      }
      .width(CONNECT_MARK_SIZE)
      .height(CONNECT_MARK_SIZE)
      .borderRadius(DsShape.PILL_FULL)
      .backgroundColor(this.palette().accentTertiary)
      .clip(true)
      Column({ space: DsSpacing.TINY }) {
        Text('远程 Host（可选）')
          .fontSize(DsType.LARGE_20.size)
          .lineHeight(DsType.LARGE_20.lineHeight)
          .fontWeight(DsType.LARGE_20.weight)
          .fontFamily(CONNECT_FONT_SANS)
          .fontColor(this.palette().labelPrimary)
        Text('选择一种方式连接到你的 Harness')
          .fontSize(DsType.SMALL_13.size)
          .lineHeight(DsType.SMALL_13.lineHeight)
          .fontWeight(DsType.SMALL_13.weight)
          .fontFamily(CONNECT_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ───────────── 手动连接（对照源码 Manual 节：一段说明 + 输入框 + 满宽 Info 按钮） ─────────────

  @Builder
  manualSection() {
    Column({ space: DsSpacing.SMALL }) {
      DsSectionHeader({ title: '手动连接' })
      // 一段说明（源码铁律：可操作物之前至多一段 prose）。v1 ①② 的两段说明合并：
      // URL 粘贴与手输 token 是同一条提交通道，分两节各配一段话违反该铁律。
      Text('在 Host 上运行 dsh web 后，它会打印一行形如 http://127.0.0.1:3111/?token=xxxx 的地址。整段粘贴即同时完成地址与授权；token 需要单独粘贴时再填第二格（每个进程只生成一次，重启后需重新获取）。')
        .fontSize(DsType.SMALL_13.size)
        .lineHeight(DsType.SMALL_13.lineHeight)
        .fontWeight(DsType.SMALL_13.weight)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().labelTertiary)
        .width('100%')
      TextInput({ text: this.address, placeholder: 'http://127.0.0.1:3111/?token=xxxx' })
        .fontSize(DsType.STD_14.size)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().labelPrimary)
        .placeholderColor(this.palette().labelTertiary)
        .placeholderFont({ size: DsType.STD_14.size })
        .height(DsSpacing.TOUCH_TARGET)
        .width('100%')
        .onChange((v: string) => {
          this.onAddressChange(v);
        })
        .accessibilityText('Host 启动 URL')
      TextInput({ text: this.token, placeholder: 'token（可选）' })
        .fontSize(DsType.STD_14.size)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().labelPrimary)
        .placeholderColor(this.palette().labelTertiary)
        .placeholderFont({ size: DsType.STD_14.size })
        .height(DsSpacing.TOUCH_TARGET)
        .width('100%')
        .onChange((v: string) => {
          this.onTokenChange(v);
        })
        .accessibilityText('访问 token')
      // 正在连接 = RUNNING 点 + 文案（对照 ConnectProgressRow；busy 只是布尔，不虚构阶段）
      if (this.busy) {
        Row({ space: DsSpacing.XSMALL }) {
          DsStateDot({ state: DsStateDotState.RUNNING })
          Text('正在连接…')
            .fontSize(DsType.STD_14.size)
            .lineHeight(DsType.STD_14.lineHeight)
            .fontWeight(DsType.STD_14.weight)
            .fontFamily(CONNECT_FONT_SANS)
            .fontColor(this.palette().labelTertiary)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        // 无进度分数的静态轨道（源码 ScanProgressRow 的 Box(4dp) 同款）
        Column()
          .width('100%')
          .height(CONNECT_TRACK_HEIGHT)
          .borderRadius(DsShape.PILL_FULL)
          .backgroundColor(this.palette().hoverSolid)
      }
      DsButton({
        text: this.busy ? '正在连接…' : '连接并授权',
        variant: DsButtonVariant.INFO,
        disabled: this.busy || this.address.trim().length === 0,
        onTap: () => {
          this.onSubmit();
        }
      })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ───────────── 结论面（对照 ConnectFailureBlock 的视觉语言；文本走 v1 通道） ─────────────

  @Builder
  resultBlock() {
    Column({ space: DsSpacing.XSMALL }) {
      Row({ space: DsSpacing.XSMALL }) {
        DsStateDot({ state: this.resultOk ? DsStateDotState.DONE : DsStateDotState.ERROR })
        Text(this.resultText)
          .fontSize(DsType.STD_14.size)
          .lineHeight(DsType.STD_14.lineHeight)
          .fontWeight(DsType.STD_14.weight)
          .fontFamily(CONNECT_FONT_SANS)
          .fontColor(this.resultOk ? this.palette().labelSecondary : this.palette().warnLabel)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.resultAdvice.length > 0) {
        Text(this.resultAdvice)
          .fontSize(DsType.SMALL_13.size)
          .lineHeight(DsType.SMALL_13.lineHeight)
          .fontWeight(DsType.SMALL_13.weight)
          .fontFamily(CONNECT_FONT_SANS)
          .fontColor(this.resultOk ? this.palette().labelTertiary : this.palette().warnLabel)
          .width('100%')
      }

      if (!this.resultOk) {
        DsButton({
          text: '打开连接诊断',
          variant: DsButtonVariant.GHOST,
          buttonSize: DsButtonSize.SMALL,
          onTap: () => {
            this.onOpenDiagnostics();
          }
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(DsSpacing.MEDIUM)
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.resultOk ? this.palette().hoverSolid : this.palette().warnTertiary)
  }

  // ───────────── 发现的 Host（对照源码 Discovered 节：节头动作「扫描」 + 扫描行 + 结果卡） ─────────────

  @Builder
  discoveredSection() {
    Column({ space: DsSpacing.SMALL }) {
      DsSectionHeader({
        title: '发现的 Host',
        action: this.scanning ? '扫描中…' : '扫描',
        onAction: () => {
          if (this.discoveryAvailable && !this.busy && !this.scanning) {
            this.onStartDiscovery();
          }
        }
      })
      if (!this.discoveryAvailable) {
        Text('需要 Host 侧运行搭桥服务（hostkit）才会广播可配对的 Host。当前未检测到可用发现源。')
          .fontSize(DsType.SMALL_13.size)
          .lineHeight(DsType.SMALL_13.lineHeight)
          .fontWeight(DsType.SMALL_13.weight)
          .fontFamily(CONNECT_FONT_SANS)
          .fontColor(this.palette().labelTertiary)
          .width('100%')
      }
      // 扫描进行行（对照 ScanProgressRow：标签 + 静态轨道；无进度分数/取消回调，不造死控件）
      if (this.scanning) {
        Column({ space: DsSpacing.XSMALL }) {
          Text('正在扫描局域网…')
            .fontSize(DsType.STD_14.size)
            .lineHeight(DsType.STD_14.lineHeight)
            .fontWeight(DsType.STD_14.weight)
            .fontFamily(CONNECT_FONT_SANS)
            .fontColor(this.palette().labelTertiary)
            .width('100%')
          Column()
            .width('100%')
            .height(CONNECT_TRACK_HEIGHT)
            .borderRadius(DsShape.PILL_FULL)
            .backgroundColor(this.palette().hoverSolid)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      ForEach(this.discoveredHosts, (host: RemoteHost) => {
        this.discoveredCard(host)
      }, (host: RemoteHost) => `${host.hostAddress}:${host.readyState}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 一张发现卡（对照 DiscoveredHarnessCard：globe 图标 + authority + 小号 Info 连接/警示 pill） */
  @Builder
  discoveredCard(host: RemoteHost) {
    Column({ space: DsSpacing.XSMALL }) {
      Row({ space: DsSpacing.COMPACT }) {
        SymbolGlyph($r('sys.symbol.wifi'))
          .fontSize(CONNECT_GLOBE_ICON_WIDTH)
          .fontColor([host.readyState === HostReadyState.READY
            ? this.palette().accent : this.palette().warn])
        Text(host.label.length > 0 ? host.label : host.hostAddress)
          .fontSize(DsType.STD_14_STRONG.size)
          .lineHeight(DsType.STD_14_STRONG.lineHeight)
          .fontWeight(DsType.STD_14_STRONG.weight)
          .fontFamily(CONNECT_FONT_SANS)
          .fontColor(this.palette().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (host.readyState === HostReadyState.READY) {
          DsButton({
            text: '连接',
            variant: DsButtonVariant.INFO,
            buttonSize: DsButtonSize.SMALL,
            onTap: () => {
              this.onConnectRemote(host);
            }
          })
        } else {
          DsPill({ text: '未就绪', warn: true })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(host.label.length > 0 ? host.hostAddress : '')
        .fontSize(DsType.CAPTION_11.size)
        .lineHeight(DsType.CAPTION_11.lineHeight)
        .fontWeight(DsType.CAPTION_11.weight)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().labelTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(`状态：${hostReadyStateLabel(host.readyState)}`)
        .fontSize(DsType.CAPTION_11.size)
        .lineHeight(DsType.CAPTION_11.lineHeight)
        .fontWeight(DsType.CAPTION_11.weight)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().labelTertiary)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: DsSpacing.MEDIUM, right: DsSpacing.MEDIUM, top: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().bgLayer1)
    .borderWidth(HarmonyBorder.HAIRLINE)
    .borderColor(this.palette().borderL2)
  }

  // ───────────── 记住的 Host（对照源码 Recent 节：StateDot 卡 + 幽灵动作） ─────────────

  @Builder
  recentSection() {
    Column({ space: DsSpacing.SMALL }) {
      DsSectionHeader({ title: `记住的 Host（${this.hosts.length}）` })
      if (this.hosts.length === 0) {
        Text('还没有配置任何 Host。用上面的任一方式添加后即可开始使用。')
          .fontSize(DsType.STD_14.size)
          .lineHeight(DsType.STD_14.lineHeight)
          .fontWeight(DsType.STD_14.weight)
          .fontFamily(CONNECT_FONT_SANS)
          .fontColor(this.palette().labelCaption)
          .width('100%')
      }
      ForEach(this.hosts, (h: HostRecord) => {
        this.recentCard(h)
      }, (h: HostRecord) => h.id)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 一张记住卡（对照 RecentHarnessCard：StateDot + 名字 + 地址行 + 幽灵小按钮） */
  @Builder
  recentCard(h: HostRecord) {
    Column({ space: DsSpacing.XSMALL }) {
      Row({ space: DsSpacing.COMPACT }) {
        DsStateDot({ state: h.authorized ? DsStateDotState.DONE : DsStateDotState.WARNING })
        Text(h.name)
          .fontSize(DsType.STD_14_STRONG.size)
          .lineHeight(DsType.STD_14_STRONG.lineHeight)
          .fontWeight(DsType.STD_14_STRONG.weight)
          .fontFamily(CONNECT_FONT_SANS)
          .fontColor(this.palette().labelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        DsButton({
          text: '重新接入',
          variant: DsButtonVariant.GHOST,
          buttonSize: DsButtonSize.SMALL,
          onTap: () => {
            // E130：只记一个 Host，"使用/移除某一个"没有对应动作；
            // 保留的是真能做的事——用当前地址重新接入（同一条 onSubmit 通道）。
            this.onSubmit();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(`${h.authority} · ${h.level}`)
        .fontSize(DsType.CAPTION_11.size)
        .lineHeight(DsType.CAPTION_11.lineHeight)
        .fontWeight(DsType.CAPTION_11.weight)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().labelTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: DsSpacing.MEDIUM, right: DsSpacing.MEDIUM, top: DsSpacing.SMALL, bottom: DsSpacing.SMALL })
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().bgLayer1)
    .borderWidth(HarmonyBorder.HAIRLINE)
    .borderColor(this.palette().borderL2)
  }

  // ───────────── 安全红线（v1 内容一字不删；容器换成设计语言的 warnTertiary 通知面） ─────────────

  @Builder
  securityNotice() {
    Column({ space: DsSpacing.XSMALL }) {
      Text('关于跨设备访问')
        .fontSize(DsType.STD_14_STRONG.size)
        .lineHeight(DsType.STD_14_STRONG.lineHeight)
        .fontWeight(DsType.STD_14_STRONG.weight)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().warnLabel)
        .width('100%')
      Text('dsh 默认只监听 loopback，并且会拒绝非 loopback 的 Host 头（返回 403）。本客户端不会通过「绑定 0.0.0.0」或「伪造 Host 头」来绕过这一限制。')
        .fontSize(DsType.SMALL_13.size)
        .lineHeight(DsType.SMALL_13.lineHeight)
        .fontWeight(DsType.SMALL_13.weight)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().warnLabel)
        .width('100%')
      Text('因此手机连 PC 时应使用加密隧道：隧道出口在 Host 的 loopback 上，安全语义与在本机使用一致。')
        .fontSize(DsType.SMALL_13.size)
        .lineHeight(DsType.SMALL_13.lineHeight)
        .fontWeight(DsType.SMALL_13.weight)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().warnLabel)
        .width('100%')
      Text('L0 · 直连 loopback：Host 与客户端同机，无新增暴露面\nL1 · 加密隧道：局域网内配对后经隧道访问，未配对设备一律拒绝')
        .fontSize(DsType.CAPTION_11.size)
        .lineHeight(DsType.CAPTION_11.lineHeight)
        .fontWeight(DsType.CAPTION_11.weight)
        .fontFamily(CONNECT_FONT_SANS)
        .fontColor(this.palette().warnLabel)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(DsSpacing.MEDIUM)
    .borderRadius(DsShape.BLOCK)
    .backgroundColor(this.palette().warnTertiary)
  }
}
