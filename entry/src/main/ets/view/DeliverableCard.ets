/**
 * 交付物卡片（P3-4：从 `ConversationPane` 抽出的**共用**呈现）。
 *
 * ## 为什么抽出来
 *
 * 交付物有两个"家"：会话过程流里的一张卡（官方在过程里也显示），以及**右栏的「交付物」面板**
 * （官方右栏的候选之一）。两处要的是同一张卡（图标 / 文件名 / 大小 / 动作行），抄一份必然走样。
 *
 * ## 边界
 *
 * 卡片**不认识中枢**：它只是一张卡。动作行里：
 *   · **「分享」现在是真动作**（P9-7）：分享目标由宿主按纯模型规则算好传进来
 *     （`deliverableShareTarget`：沙箱内 ⇒ 分享**文件本体**；沙箱外 ⇒ 降级为分享**路径文本**；
 *     连绝对路径都定位不到 ⇒ 禁用并写明原因）；
 *   · **「保存」仍然禁用**，原因是真缺口：本仓的平台层**没有"另存为"能力**
 *     （只有系统选择器与分享）——理由写在无障碍文案里，读屏用户点不到也知道为什么。
 */

import {
  Fs, Radius, SHARE_TARGET_NONE, SHARE_TARGET_TEXT, ShareTarget, shareActionLabel,
  Sp, TrajectoryItem, formatBytes
} from 'appstate';
import { NativeActionBar } from './NativePrimitives';
import type { NativeAction } from './NativePrimitives';

@Component
export struct DeliverableCard {
  /** 要显示的交付物条目 */
  @Prop item: TrajectoryItem;
  /**
   * 这条交付物的分享目标（由宿主算好，见 `model/ProducedFiles.deliverableShareTarget`）。
   *
   * 默认值是"不能分享"，于是**不知道就不给按钮**——比给一个点了没反应的按钮诚实。
   */
  @Prop shareTarget: ShareTarget = { kind: SHARE_TARGET_NONE, absPath: '', text: '', reason: '' };
  /** 点「分享」：宿主负责拉起系统分享面板（失败要给回执） */
  onShare: () => void = () => {
  };
  /** §FR-015：点击文件名跳转预览 */
  onOpenFile: () => void = () => {
  };

  build() {
    // 【ArkUI 约束】组件的 `build()` 只能有一个根节点（`@Builder` 可以多个）⇒ 两行包进 Column
    Column({ space: Sp.XS }) {
      Row({ space: Sp.M }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(20)   // token-exempt: 卡片图标尺寸（搬迁不改视觉；与 Fs.TITLE_L 同值但语义不同）
        .fontColor([$r('sys.color.brand')])
      Column({ space: 2 }) {
        Text(this.item.fileName)
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.onOpenFile();
          })
        Text(formatBytes(this.item.fileSize))
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(Sp.M)
    .borderRadius(Radius.M)
    .backgroundColor($r('sys.color.background_secondary'))
    .accessibilityText(`交付物 ${this.item.fileName}`)
      // 动作行统一交给原语：间距/换行/语气只实现一次（此前是两个手写 Text）
      Row() {
        NativeActionBar({
          actions: this.fileActions(this.item),
          // 动作条把 id 回传（`NativeAction` 里没有 onTap）：只有「分享」是真动作
          onAction: (id: string) => {
            if (id === 'share') {
              this.onShare();
            }
          }
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  private fileActions(item: TrajectoryItem): NativeAction[] {
    const out: NativeAction[] = [];
    /*
     * ── 「保存」：仍然禁用，因为**能力真的没有** ──
     *
     * 本仓平台层只有系统选择器（`pickFolder/pickDocument`，那是**选择**不是**保存**）与分享，
     * **没有"另存为"**。动作留在原位（用户能看见这条卡具备这个能力），
     * 但禁用并把原因写在无障碍文案里（读屏用户点不到也知道为什么）——假入口是本仓禁止的形态。
     */
    out.push({
      id: 'save',
      label: '保存',
      disabled: true,
      a11y: '保存到本地：HarmonyOS 沙箱限制，当前平台未提供文件保存能力'
    });
    /*
     * ── 「分享」：P9-7 起是真动作 ──
     *
     * 三档各说各话（判据在 `model/ProducedFiles.deliverableShareTarget`）：
     *   · 沙箱内的文件 ⇒ **分享文件本体**（平台转 `fileUri` 后交给系统分享面板）；
     *   · 沙箱外（用户挑的工作区）⇒ 降级为**分享路径文本**，并在无障碍里说明为什么降级；
     *   · 连绝对路径都定位不到 ⇒ **禁用**，并把原因说出来。
     * 文案随档位变（`shareActionLabel`）：写「分享文件」却只发路径，就是在骗人。
     */
    const target: ShareTarget = this.shareTarget;
    if (target.kind === SHARE_TARGET_NONE) {
      out.push({
        id: 'share',
        label: '分享',
        disabled: true,
        a11y: target.reason.length > 0 ? `分享：${target.reason}` : '分享：这条交付物暂时无法分享'
      });
      return out;
    }
    const label: string = shareActionLabel(target);
    const why: string = target.kind === SHARE_TARGET_TEXT && target.reason.length > 0
      ? `（${target.reason}）` : '';
    out.push({
      id: 'share',
      label: label,
      a11y: `${label}：${item.fileName}${why}`
    });
    return out;
  }
}
