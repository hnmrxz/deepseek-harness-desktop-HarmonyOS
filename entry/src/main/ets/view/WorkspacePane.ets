/**
 * 工作区面板（D1 §7.5 / D3 §1）。
 *
 * 三段式（在可用宽度内自适应）：
 *   工作区列表 → 文件树（可展开）→ 文件预览
 * 宽屏（>= 840vp）三列并排；窄屏按栈式下钻（由宿主传入的 compact 控制）。
 *
 * 规格要点：
 *   - 目录浏览走「浏览式选择器」语义（D1 §7.5.2），端侧不自造路径规则；
 *   - 大文件只预览前若干字节并明确提示（D3 §7.5.3 / PREVIEW_LIMIT_BYTES）；
 *   - 交付物打标（D1 §7.5.5）。
 */

import {
  fileSummary,
  FileNode,
  FilePreview,
  formatBytes,
  Fs,
  NodeKind,
  PreviewKind,
  Radius,
  Sp,
  Sz,
  WorkspaceItem
} from 'appstate';

@Component
export struct WorkspacePane {
  @Prop workspaces: WorkspaceItem[] = [];
  @Prop tree: FileNode[] = [];
  @Prop selectedPath: string = '';
  @Prop preview?: FilePreview;
  /** 窄屏：是否处于「已下钻」状态（由宿主控制栈式导航） */
  @Prop compact: boolean = false;
  @Prop drillLevel: number = 0;
  /**
   * 文件树空态的标题与说明。
   *
   * 【为什么由宿主提供而不是写死】「空」有好几种完全不同的原因，
   * 而对用户的处置建议各不相同：
   *   - 还没选工作区 → 让他选；
   *   - 选了但该目录下没有会话 → 文件端点的作用域是会话级，他需要先在该目录建会话；
   *   - 列目录调用失败 → 让他去看诊断。
   * 写死一句「在 Host 侧确认目录可读」会把前两种都误诊成第三种——
   * 用户按错误的方向去查，而真正的动作（选工作区/建会话）就在眼前。
   */
  @Prop treeEmptyTitle: string = '该工作区暂无文件';
  @Prop treeEmptyHint: string = '选择其他工作区，或在 Host 侧确认目录可读';

  onSelectWorkspace: (id: string) => void = () => {
  };
  onToggleDirectory: (path: string) => void = () => {
  };
  onOpenFile: (node: FileNode) => void = () => {
  };
  /** 把文件作为附件投喂（回到会话） */
  onAttachFile: (node: FileNode) => void = () => {
  };
  onBack: () => void = () => {
  };

  build() {
    if (this.compact) {
      this.buildStacked()
    } else {
      this.buildColumns()
    }
  }

  // ───────────── 宽屏：三列 ─────────────

  @Builder
  buildColumns() {
    Row() {
      Column() {
        this.workspaceList()
      }
      .width(240)
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))

      Divider().vertical(true).color($r('sys.color.comp_divider'))

      Column() {
        this.treeView()
      }
      .layoutWeight(1)
      .height('100%')

      Divider().vertical(true).color($r('sys.color.comp_divider'))

      Column() {
        this.previewView()
      }
      .width(360)
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
    }
    .width('100%')
    .height('100%')
  }

  // ───────────── 窄屏：栈式 ─────────────

  @Builder
  buildStacked() {
    Column() {
      if (this.drillLevel === 0) {
        this.workspaceList()
      } else if (this.drillLevel === 1) {
        Row({ space: Sp.S }) {
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(18)
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick(() => {
            this.onBack();
          })
          Text('文件').fontSize(Fs.TITLE_S).fontWeight(FontWeight.Medium).layoutWeight(1)
        }
        .width('100%')
        .height(Sz.TOUCH_MIN)
        .padding({ left: Sp.S })

        this.treeView()
      } else {
        Row({ space: Sp.S }) {
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(18)
          }
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .onClick(() => {
            this.onBack();
          })
          Text(this.preview === undefined ? '预览' : this.preview.name)
            .fontSize(Fs.TITLE_S)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(Sz.TOUCH_MIN)
        .padding({ left: Sp.S })

        this.previewView()
      }
    }
    .width('100%')
    .height('100%')
  }

  // ───────────── 工作区列表 ─────────────

  @Builder
  workspaceList() {
    Column() {
      Row({ space: Sp.S }) {
        Text('工作区')
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text('添加')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
      }
      .width('100%')
      .height(Sz.TOUCH_MIN)
      .padding({ left: Sp.M, right: Sp.M })

      List({ space: Sp.XS }) {
        ForEach(this.workspaces, (w: WorkspaceItem) => {
          ListItem() {
            Column({ space: 2 }) {
              Row({ space: Sp.S }) {
                SymbolGlyph($r('sys.symbol.folder')).fontSize(16)
                  .fontColor([w.primary ? $r('sys.color.brand') : $r('sys.color.font_secondary')])
                Text(w.name)
                  .fontSize(Fs.SECONDARY)
                  .fontWeight(w.primary ? FontWeight.Medium : FontWeight.Normal)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (w.primary) {
                  Text('主')
                    .fontSize(Fs.CAPTION)
                    .fontColor($r('sys.color.brand'))
                    .padding({ left: 5, right: 5 })
                    .borderRadius(5)
                    .backgroundColor($r('sys.color.background_primary'))
                }
              }
              .width('100%')
              Text(`${w.path} · ${w.sessionCount} 会话`)
                .fontSize(Fs.CAPTION)
                .fontColor($r('sys.color.font_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .width('100%')
            .padding(Sp.M)
            .borderRadius(Radius.S)
            .backgroundColor(w.primary ? $r('sys.color.background_primary') : Color.Transparent)
            .onClick(() => {
              this.onSelectWorkspace(w.id);
            })
          }
        }, (w: WorkspaceItem) => w.id)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: Sp.S, right: Sp.S })

      // 空态：说明可以做什么（D3 §4）
      if (this.workspaces.length === 0) {
        Text('还没有工作区。添加后它会成为 agent 的工作目录。')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .padding(Sp.M)
      }
    }
    .width('100%')
    .height('100%')
  }

  // ───────────── 文件树 ─────────────

  @Builder
  treeView() {
    Column() {
      if (this.tree.length === 0) {
        Column({ space: Sp.S }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(32)
            .fontColor([$r('sys.color.font_tertiary')])
          Text(this.treeEmptyTitle)
            .fontSize(Fs.SECONDARY)
            .fontColor($r('sys.color.font_secondary'))
          Text(this.treeEmptyHint)
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
            .textAlign(TextAlign.Center)
            .padding({ left: Sp.L, right: Sp.L })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.tree, (node: FileNode) => {
            ListItem() {
              this.treeRow(node, 0)
            }
            if (node.kind === NodeKind.DIRECTORY && node.loaded) {
              ForEach(node.children, (child: FileNode) => {
                ListItem() {
                  this.treeRow(child, 1)
                }
              }, (child: FileNode) => child.path)
            }
          }, (node: FileNode) => node.path)
        }
        .layoutWeight(1)
        .width('100%')
        .padding(Sp.S)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  treeRow(node: FileNode, depth: number) {
    Row({ space: Sp.S }) {
      Text('　'.repeat(depth))
        .fontSize(Fs.CAPTION)
      SymbolGlyph(node.kind === NodeKind.DIRECTORY
        ? (node.loaded ? $r('sys.symbol.folder') : $r('sys.symbol.folder'))
        : $r('sys.symbol.doc_text'))
        .fontSize(14)
        .fontColor([node.deliverable ? $r('sys.color.brand') : $r('sys.color.font_secondary')])

      Text(node.name)
        .fontSize(Fs.SECONDARY)
        .fontColor(this.selectedPath === node.path
          ? $r('sys.color.brand')
          : $r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (node.deliverable) {
        Text('交付物')
          .fontSize(10)
          .fontColor($r('sys.color.brand'))
          .padding({ left: 5, right: 5 })
          .borderRadius(5)
          .backgroundColor($r('sys.color.background_secondary'))
      }

      Text(fileSummary(node, formatBytes))
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
    }
    .width('100%')
    .height(Sz.TOUCH_MIN - 6)
    .padding({ left: Sp.S, right: Sp.S })
    .borderRadius(Radius.S)
    .backgroundColor(this.selectedPath === node.path
      ? $r('sys.color.background_secondary')
      : Color.Transparent)
    .onClick(() => {
      if (node.kind === NodeKind.DIRECTORY) {
        this.onToggleDirectory(node.path);
      } else {
        this.onOpenFile(node);
      }
    })
  }

  // ───────────── 文件预览 ─────────────

  @Builder
  previewView() {
    Column() {
      if (this.preview === undefined) {
        Column({ space: Sp.S }) {
          SymbolGlyph($r('sys.symbol.doc_text')).fontSize(32)
            .fontColor([$r('sys.color.font_tertiary')])
          Text('选择文件以预览')
            .fontSize(Fs.SECONDARY)
            .fontColor($r('sys.color.font_secondary'))
          Text('支持文本、代码、Markdown 与图片')
            .fontSize(Fs.CAPTION)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        this.previewHeader()
        Divider().color($r('sys.color.comp_divider'))
        this.previewBody()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  previewHeader() {
    Column({ space: Sp.XS }) {
      Row({ space: Sp.S }) {
        Text(this.preview!.name)
          .fontSize(Fs.SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('投喂')
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.brand'))
          .onClick(() => {
            this.onAttachFile(this.previewAsNode());
          })
      }
      .width('100%')
      Text(this.previewMeta())
        .fontSize(Fs.CAPTION)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(2)
        .width('100%')
    }
    .width('100%')
    .padding(Sp.M)
  }

  @Builder
  previewBody() {
    if (this.preview!.kind === PreviewKind.TOO_LARGE) {
      Column({ space: Sp.S }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle')).fontSize(28)
          .fontColor([$r('sys.color.warning')])
        Text('文件过大，未在端侧预览')
          .fontSize(Fs.SECONDARY)
        Text(`大小 ${formatBytes(this.preview!.size)}，超过端侧预览上限。可在 Host 侧用工具读取。`)
          .fontSize(Fs.CAPTION)
          .fontColor($r('sys.color.font_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ left: Sp.L, right: Sp.L })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.preview!.kind === PreviewKind.BINARY) {
      Column({ space: Sp.S }) {
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(28)
          .fontColor([$r('sys.color.font_tertiary')])
        Text('二进制文件，无文本预览')
          .fontSize(Fs.SECONDARY)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column({ space: Sp.S }) {
          if (this.preview!.truncated) {
            Text(`仅显示前 ${formatBytes(this.preview!.text.length)}（原文件 ${formatBytes(this.preview!.size)}）`)
              .fontSize(Fs.CAPTION)
              .fontColor($r('sys.color.warning'))
              .width('100%')
          }
          Text(this.preview!.text)
            .fontSize(this.preview!.kind === PreviewKind.CODE ? Fs.CAPTION : Fs.SECONDARY)
            .fontFamily(this.preview!.kind === PreviewKind.CODE ? 'monospace' : '')
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .padding(Sp.M)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
  }

  private previewMeta(): string {
    const p: FilePreview = this.preview!;
    const kindText: string = p.kind === PreviewKind.CODE
      ? `代码 · ${p.language}`
      : (p.kind === PreviewKind.MARKDOWN ? 'Markdown' : (p.kind === PreviewKind.IMAGE ? '图片' : '文本'));
    const sizeText: string = formatBytes(p.size);
    return sizeText.length > 0 ? `${kindText} · ${sizeText}` : kindText;
  }

  /** 预览对应的节点（用于"投喂"动作） */
  private previewAsNode(): FileNode {
    return {
      name: this.preview!.name,
      path: this.preview!.path,
      kind: NodeKind.FILE,
      size: this.preview!.size,
      modifiedAt: 0,
      loaded: true,
      children: [],
      deliverable: false
    };
  }
}
