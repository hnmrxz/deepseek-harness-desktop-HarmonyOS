/**
 * 真实接线投影测试（工作区 / 文件 / 命令 / `@` 引用 / Host 记录 / 详情分区）。
 *
 * 【这些用例防的是什么】
 *   这六块曾经**整块是桩数据**：文件树、工作区、斜杠命令、`@` 引用、设备页 Host 列表、
 *   详情栏分区。桩数据不会报错，所以「功能没接上」在界面上看起来和「功能正常」一模一样。
 *   本文件钉住的是「每一块都必须由**真实回复**投影出来」，以及几条容易写反的语义：
 *     - `entry.type` 是判别字段（不是 `kind`/`isDirectory`），未知取值**不得**当成文件；
 *     - 文件截断看 `eof`，**不能**拿 `text.length` 与 `bytes` 比大小（多字节字符会误判）；
 *     - 上游不给 mtime，所以 `modifiedAt` 只能是 0（不能拿拉取时刻冒充）；
 *     - loopback 判定必须精确，否则会把远端 Host 标成「直连 loopback」（安全性陈述）；
 *     - `commands/list` 返回的名字**可能不带前导 `/`**，补错会让命令发出去必然失败。
 *
 * 样本来源：`docs/11-请求载荷契约.md` §2.1 / §2.3 / §6.1 / §6.3（逐字取自上游声明文件）。
 */

import { describe, expect, it } from '@ohos/hypium';
import { parseJson } from 'connection';
import {
  authorityOfUrl,
  basenameOf,
  hostOfUrl,
  isLoopbackUrl,
  projectCommands,
  projectDetailSections,
  projectFileReferences,
  projectHosts,
  projectSessionReferences,
  projectWorkspaceListing,
  projectWorkspaceFailure,
  projectWorkspaceText,
  projectWorkspaces,
  TrajectoryKind,
  makeItem,
  NodeKind,
  PreviewKind,
  Speaker
} from 'appstate';
import type {
  DetailSection,
  FileNode,
  FilePreview,
  HostRecord,
  CommandCandidate,
  ReferenceCandidate,
  SessionListItem,
  TrajectoryItem,
  WorkspaceItem,
  WorkspaceListingProjection
} from 'appstate';

/** 造一个最小会话项 */
function session(id: string, cwd: string, updatedAt: number): SessionListItem {
  const raw: Record<string, Object> = {};
  return {
    id: id, title: id, cwd: cwd, updatedAt: updatedAt, createdAt: 0,
    running: false, blank: false, raw: raw as Object
  };
}

/** 造一个最小轨迹项 */
function item(id: string, kind: TrajectoryKind, at: number): TrajectoryItem {
  const out: TrajectoryItem = makeItem(id, kind, at);
  return out;
}

export default function liveWireTest() {
  describe('liveWire', () => {

    // ───────────────── Host 记录 ─────────────────

    it('projectHosts：未配置时返回空数组（不编造条目）', 0, () => {
      const list: HostRecord[] = projectHosts({
        url: '', connected: false, authority: '', authorized: false, version: ''
      });
      expect(list.length).assertEqual(0);
    });

    it('projectHosts：loopback 地址标为 L0 且 authority 从 URL 解析', 0, () => {
      const list: HostRecord[] = projectHosts({
        url: 'http://127.0.0.1:3115/?token=x', connected: true,
        authority: '127.0.0.1:3115', authorized: true, version: ''
      });
      expect(list.length).assertEqual(1);
      expect(list[0].isLoopback).assertTrue();
      expect(list[0].authority).assertEqual('127.0.0.1:3115');
      expect(list[0].level.indexOf('L0') >= 0).assertTrue();
      expect(list[0].authorized).assertTrue();
    });

    it('isLoopbackUrl：拒绝把 127.0.0.1.evil.com 判成 loopback', 0, () => {
      expect(isLoopbackUrl('http://127.0.0.1:3115')).assertTrue();
      expect(isLoopbackUrl('http://localhost:3115')).assertTrue();
      expect(isLoopbackUrl('http://[::1]:3115')).assertTrue();
      expect(isLoopbackUrl('http://127.0.0.1.evil.com:3115')).assertFalse();
      expect(isLoopbackUrl('http://10.0.0.5:3115')).assertFalse();
      // 反向代理形态：userinfo 里出现 127.0.0.1 也不能算
      expect(isLoopbackUrl('http://127.0.0.1@evil.com:3115')).assertFalse();
    });

    it('authorityOfUrl / hostOfUrl：去 userinfo、去端口、保留 IPv6 方括号', 0, () => {
      expect(authorityOfUrl('http://a:b@host:99/x?y=1')).assertEqual('host:99');
      expect(hostOfUrl('https://host:8443')).assertEqual('host');
      expect(hostOfUrl('https://[::1]:8443')).assertEqual('[::1]');
      expect(authorityOfUrl('host:1')).assertEqual('host:1');
    });

    // ───────────────── 工作区 ─────────────────

    it('projectWorkspaces：按 cwd 分组、会话最多者为「主」', 0, () => {
      const list: WorkspaceItem[] = projectWorkspaces([
        session('s1', 'D:\\dev\\a', 10),
        session('s2', 'D:\\dev\\a', 20),
        session('s3', 'D:\\dev\\b', 99),
        session('s4', '', 5)
      ]);
      expect(list.length).assertEqual(2);
      expect(list[0].sessionCount).assertEqual(2);
      expect(list[0].primary).assertTrue();
      expect(list[0].name).assertEqual('a');
      expect(list[1].primary).assertFalse();
    });

    it('projectWorkspaces：没有 cwd 的会话被忽略（无法浏览，不给出入口）', 0, () => {
      const list: WorkspaceItem[] = projectWorkspaces([session('s1', '', 1)]);
      expect(list.length).assertEqual(0);
    });

    it('basenameOf：容忍 / 与 \\ 及尾部斜杠', 0, () => {
      expect(basenameOf('D:\\dev\\proj')).assertEqual('proj');
      expect(basenameOf('/home/u/proj/')).assertEqual('proj');
      expect(basenameOf('')).assertEqual('');
    });

    // ───────────────── 文件列表 ─────────────────

    it('projectWorkspaceListing：拼出工作区相对路径，type 判别，未知类型不当成目录', 0, () => {
      const json = '{"path":"","truncated":false,"entries":['
        + '{"name":"docs","type":"directory"},'
        + '{"name":"README.md","type":"file","size":8192},'
        + '{"name":"sock","type":"other"}]}';
      const value: Object | undefined = parseJson(json);
      const out: WorkspaceListingProjection =
        projectWorkspaceListing(value, '', ['README.md']);
      expect(out.truncated).assertFalse();
      expect(out.nodes.length).assertEqual(3);
      expect(out.nodes[0].path).assertEqual('docs');
      expect(out.nodes[0].kind).assertEqual(NodeKind.DIRECTORY);
      expect(out.nodes[1].kind).assertEqual(NodeKind.FILE);
      expect(out.nodes[1].size).assertEqual(8192);
      expect(out.nodes[1].deliverable).assertTrue();
      // `other` 不是目录（把它当目录会让用户点开一个永远打不开的节点）
      expect(out.nodes[2].kind).assertEqual(NodeKind.FILE);
      // 上游不给 mtime：只能是 0，不能拿拉取时刻冒充
      expect(out.nodes[1].modifiedAt).assertEqual(0);
      expect(out.nodes[0].loaded).assertFalse();
    });

    it('projectWorkspaceListing：子层路径是 parent + "/" + name', 0, () => {
      const json = '{"path":"docs","truncated":true,"entries":[{"name":"a.md","type":"file"}]}';
      const out: WorkspaceListingProjection =
        projectWorkspaceListing(parseJson(json), 'docs', []);
      expect(out.truncated).assertTrue();
      expect(out.nodes[0].path).assertEqual('docs/a.md');
    });

    it('projectWorkspaceListing：无回复时返回空且不报错', 0, () => {
      const out: WorkspaceListingProjection = projectWorkspaceListing(undefined, '', []);
      expect(out.nodes.length).assertEqual(0);
      expect(out.truncated).assertFalse();
    });

    // ───────────────── 文件预览 ─────────────────

    it('projectWorkspaceText：truncated 由 eof 决定，不用长度比大小', 0, () => {
      // 多字节文本：text.length(6) < bytes(12)，若按长度比大小会误报「未截断」
      const json = '{"path":"a.md","bytes":12,"offset":1,"text":"你好世界","lines":1,"eof":false}';
      const p: FilePreview = projectWorkspaceText(parseJson(json), 'a.md', 'a.md', 0);
      expect(p.truncated).assertTrue();
      expect(p.kind).assertEqual(PreviewKind.MARKDOWN);
      expect(p.size).assertEqual(12);
    });

    it('projectWorkspaceText：SVG 走 SVG 的文本事实（IMAGE 降级为 CODE）', 0, () => {
      const json = '{"path":"i.svg","bytes":30,"offset":1,"text":"<svg/>","lines":1,"eof":true}';
      const p: FilePreview = projectWorkspaceText(parseJson(json), 'i.svg', 'i.svg', 0);
      expect(p.kind).assertEqual(PreviewKind.CODE);
      expect(p.truncated).assertFalse();
      expect(p.language.length > 0).assertTrue();
    });

    it('projectWorkspaceFailure：把上游拒绝理由带到界面上（不是空白）', 0, () => {
      const p: FilePreview = projectWorkspaceFailure('bin/out', 'out', '二进制文件');
      expect(p.kind).assertEqual(PreviewKind.BINARY);
      expect(p.note).assertEqual('二进制文件');
      expect(p.text).assertEqual('');
    });

    // ───────────────── 斜杠命令 ─────────────────

    it('projectCommands：补前导 /，读 description 与 input.hint', 0, () => {
      const json = '[{"name":"compact","description":"压缩上下文","input":{"hint":"<说明>"}},'
        + '{"name":"/clear","description":"清空视图"}]';
      const list: CommandCandidate[] = projectCommands(parseJson(json));
      expect(list.length).assertEqual(2);
      expect(list[0].name).assertEqual('/compact');
      expect(list[0].args).assertEqual('<说明>');
      expect(list[0].detail).assertEqual('压缩上下文');
      // 已经带 / 的不得补成 //
      expect(list[1].name).assertEqual('/clear');
      expect(list[1].args).assertEqual('');
    });

    it('projectCommands：无名条目跳过；无回复时为空', 0, () => {
      expect(projectCommands(parseJson('[{"description":"x"}]')).length).assertEqual(0);
      expect(projectCommands(undefined).length).assertEqual(0);
      expect(projectCommands(parseJson('{}')).length).assertEqual(0);
    });

    // ───────────────── @ 引用 ─────────────────

    it('projectFileReferences：目录插入带尾斜杠，文件插入裸路径', 0, () => {
      const json = '[{"path":"docs","kind":"directory"},{"path":"a.ts","kind":"file"}]';
      const list: ReferenceCandidate[] = projectFileReferences(parseJson(json));
      expect(list.length).assertEqual(2);
      expect(list[0].insert).assertEqual('@docs/');
      expect(list[1].insert).assertEqual('@a.ts');
      expect(list[1].kind).assertEqual('file');
    });

    it('projectSessionReferences：必须用上游给的 mention，不自行拼语法', 0, () => {
      const json = '[{"mention":"@session:abc","sessionId":"abc","label":"修网关","cwd":"D:/w"}]';
      const list: ReferenceCandidate[] = projectSessionReferences(parseJson(json));
      expect(list.length).assertEqual(1);
      expect(list[0].insert).assertEqual('@session:abc');
      expect(list[0].label).assertEqual('修网关');
      expect(list[0].kind).assertEqual('session');
    });

    // ───────────────── 详情分区 ─────────────────

    it('projectDetailSections：五个分区恒在，计数是真实条数', 0, () => {
      const t: TrajectoryItem[] = [
        item('t1', TrajectoryKind.TOOL, 1),
        item('t2', TrajectoryKind.TOOL, 2),
        item('t3', TrajectoryKind.DELIVERABLE, 3)
      ];
      const t1: TrajectoryItem = t[0];
      t1.toolName = 'read';
      const sections: DetailSection[] = projectDetailSections(t);
      expect(sections.length).assertEqual(5);
      expect(sections[0].title).assertEqual('工具调用');
      expect(sections[0].count).assertEqual(2);
      expect(sections[1].count).assertEqual(0);
      expect(sections[1].lines.length).assertEqual(0);
      expect(sections[1].emptyHint.length > 0).assertTrue();
      expect(sections[2].count).assertEqual(1);
    });

    it('projectDetailSections：空轨迹时每区都是空态（不显示别人的内容）', 0, () => {
      const sections: DetailSection[] = projectDetailSections([]);
      for (let i = 0; i < sections.length; i++) {
        expect(sections[i].count).assertEqual(0);
        expect(sections[i].lines.length).assertEqual(0);
      }
    });

    it('projectDetailSections：工具行带工具名与状态；不给 0ms 的假耗时', 0, () => {
      const t: TrajectoryItem[] = [item('t1', TrajectoryKind.TOOL, 1)];
      t[0].toolName = 'edit';
      const line: string = projectDetailSections(t)[0].lines[0];
      expect(line.indexOf('edit') === 0).assertTrue();
      expect(line.indexOf('0ms') < 0).assertTrue();
    });

    it('projectDetailSections：子代理行不因缺字段崩掉', 0, () => {
      const t: TrajectoryItem[] = [item('s1', TrajectoryKind.SUBAGENT, 1)];
      t[0].subagentName = '';
      const line: string = projectDetailSections(t)[1].lines[0];
      expect(line.length > 0).assertTrue();
    });

    it('makeItem/Speaker 保持默认（防止详情投影依赖未初始化字段）', 0, () => {
      const t: TrajectoryItem = makeItem('x', TrajectoryKind.GOAL, 1);
      expect(t.speaker).assertEqual(Speaker.ASSISTANT);
      expect(t.percent).assertEqual(-1);
    });

    it('FileNode 结构：目录用 children，交付物标记是布尔', 0, () => {
      const n: FileNode = {
        name: 'd', path: 'd', kind: NodeKind.DIRECTORY, size: 0, modifiedAt: 0,
        loaded: false, children: [], deliverable: false
      };
      expect(n.children.length).assertEqual(0);
      expect(n.deliverable).assertFalse();
    });
  });
}
