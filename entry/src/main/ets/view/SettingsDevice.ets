/**
 * 设置 · 设备（P4-4：从 `SettingsPane` 拆出的第三个域组件）。
 *
 * ## 这一个域回答什么
 *
 * 本仓特有的设置段（官方没有对应分区，矩阵里以 `hdsh-*` 与"设备事实"登记）：
 * **已记住的 Host 列表**（成对/撤销）与**关于本机**（版本、构建、平台等只读事实）。
 * 它与"通用"分开，是因为前者讲"这个应用怎么工作"，这里讲"这台设备/这条连接是什么"。
 *
 * ## 边界
 *
 * 数据（`about` / `hosts`）由宿主给；**成对与撤销是副作用**（要拿平台能力与中枢），
 * 由回调交回宿主。
 */
import { DATA_PRACTICES, Fs, HostRecord, PERMISSION_DISCLOSURES, Radius, Sp, Sz, privacySummaryLine } from 'appstate';
import type { AboutInfo, PermissionDisclosure, PrivacyPoint } from 'appstate';

@Component
export struct SettingsDevice {

  /** 关于本机（只读事实） */
  @Prop about: AboutInfo;

  /** 隐私与权限说明是否展开（只影响这一页显示 ⇒ 组件内状态） */
  @State privacyOpen: boolean = false;
  /** 已记住的 Host */
  @Prop hosts: HostRecord[] = [];

  /** 与某个 Host 成对（重新认证；不需要参数——宿主自己知道当前待成对的是哪一个） */
  onPairHost: () => void = () => {
  };
  /** 撤销某个 Host 的信任（只传 id：撤销是"删掉这条记录"，不需要整行） */
  onRevokeHost: (id: string) => void = () => {
  };

  // 【ArkUI 约束】组件的 build() 只能有一个根节点 ⇒ 多段内容包进 Column
  build() {
    Column({ space: Sp.L }) {
          Row({ space: Sp.S }) {
            Text('已配置 Host')
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .layoutWeight(1)
            // 措辞刻意写全「远程」：端侧自足运行后，本机核心是默认路径，
            // 连别人的 Host 是**可选能力**，不是"添加 Host 才能用"（D7 §3）
            Text('远程 Host（可选）')
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
                  Text('忘记此 Host')
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

          /*
           * 隐私与权限说明（P7-11）。AppGallery 审核会看"应用里能不能看到隐私说明"；
           * 内容不是宣传语，而是**能核实的做法**（无遥测 / 数据只在沙箱 / 只连回环 Host
           * 或你自填的远端 / 不读设备标识 / 剪贴板只写不读 / 导出剔除敏感项）。
           *
           * 这一页与 `module.json5` 的权限清单由 `tools/check-compliance.mjs` 逐项对账 ——
           * 单边改动（只改包里、或只改这一页）会让门禁红。
           */
          this.privacyRow()
    }
    .width('100%')
  }

  /** 隐私与权限说明（折叠块：默认收起，点开见数据做法与权限逐条） */
  @Builder
  privacyRow() {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        // 图标用本仓已在用的 doc_text：隐私说明本身就是一份说明文档
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(16)   // token-exempt: 行内图标尺寸
          .fontColor([$r('sys.color.font_secondary')])
        Column({ space: 2 }) {
          Text('隐私与权限说明')
            .fontSize(Fs.BODY)
            .width('100%')
          Text(privacySummaryLine())
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .maxLines(2)
        }
        .layoutWeight(1)
        Text(this.privacyOpen ? '收起' : '展开')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
      }
      .width('100%')
      .height(Sz.TOUCH_MIN)   // 44vp 命中区（E214 的教训：只挂 onClick 的文字按不准）
      .onClick(() => {
        this.privacyOpen = !this.privacyOpen;
      })

      if (this.privacyOpen) {
        ForEach(DATA_PRACTICES, (p: PrivacyPoint) => {
          Column({ space: 2 }) {
            Text(p.title)
              .fontSize(Fs.SECONDARY)
              .width('100%')
            Text(p.detail)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          }
          .width('100%')
        }, (p: PrivacyPoint) => p.title)

        Text(`申请的权限（共 ${PERMISSION_DISCLOSURES.length} 项）`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding({ top: Sp.S })
        ForEach(PERMISSION_DISCLOSURES, (d: PermissionDisclosure) => {
          Column({ space: 2 }) {
            Text(d.name)
              .fontSize(Fs.CAPTION)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(d.purpose)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.font_tertiary'))
              .width('100%')
          }
          .width('100%')
        }, (d: PermissionDisclosure) => d.name)

        Text('完整隐私政策以应用市场提交的文本为准；本页是它的摘要，两者一致性由 tools/check-compliance.mjs 对账。')
          .fontSize(Fs.CAPTION_XS)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding({ top: Sp.S })
      }
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
