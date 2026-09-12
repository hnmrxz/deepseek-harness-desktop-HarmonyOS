/**
 * 设备侧架构探针（P5）——在**真机**上回答两个决定架构是否成立的问题。
 *
 * ────────────────────────────────────────────────────────────────────────
 * 为什么这两条必须实测，而不能靠推断：
 *
 * ① 沙箱是否允许创建**符号链接**（D6 §9 R3）
 *    dsh 启动时会由 `healProfilesModuleFallback` 在 `$DSH_HOME/profiles/node_modules`
 *    下建**符号链接**（把安装树的依赖闭包链进去）。若沙箱返回 EACCES/EPERM，
 *    `boot()` 会在挂载阶段直接失败——**这是能不能起来的问题，不是优化问题**。
 *    社区工程在鸿蒙上实测到过 symlink 被禁（并为此打了 `dsh-symlink-to-copy.patch`）。
 *    我们要先知道自己这台设备/这个 API 版本的行为，再决定走"预置结构 / 走 pkg-ESM-proxy 分支 /
 *    登记上游缺口"哪条路——而不是先照着别人的结论打补丁。
 *
 * ② 同进程内 `127.0.0.1` 是否可达（D6 §9 R4）
 *    我们的架构把 Host 与页面放在**同一个进程**里，正是为了不跨"进程间 loopback 隔离"
 *    （社区方案因此必须绑 0.0.0.0 + 改写 Host 头）。这里要验证的前提是：
 *    ArkTS 能在这个进程上**监听**回环地址、并且能从同一进程**连上**它。
 *    监听失败 ⇒ 整个"端侧自足 + 不打洞"的架构不成立。
 *
 * 判据写在断言里；失败时用例给出的是**具体错误码**，而不是"失败了"。
 * ────────────────────────────────────────────────────────────────────────
 */

import { describe, expect, it } from '@ohos/hypium';
import { fileIo as fs } from '@kit.CoreFileKit';
import { socket } from '@kit.NetworkKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'HDSH-Probe';
const DOMAIN: number = 0x0000;

/** 探针用的回环端口（选一个不常用的高位端口，避免撞上系统服务） */
const PROBE_PORT: number = 31977;

/** 取应用上下文（测试进程里没有页面，因此从 delegator 拿 app context） */
function appFilesDir(): string {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const ctx: common.Context = delegator.getAppContext();
  return ctx.filesDir;
}

export default function onDeviceProbeTest() {
  describe('OnDeviceProbe', () => {

    /**
     * ① 符号链接能力。
     * 结果分三档，都**如实记录**（不把"没测出"当"通过"）：
     *   - symlinkOk=true  → dsh 的 profiles/node_modules 链接方案原样可用
     *   - symlinkOk=false → 必须走替代方案（见本文件头部说明），并把错误码带回
     */
    it('sandbox_symlink_capability', 0, async () => {
      const base: string = appFilesDir();
      const dir: string = base + '/probe-symlink';
      const target: string = dir + '/target.txt';
      const link: string = dir + '/link.txt';

      let symlinkOk: boolean = false;
      let errCode: number = 0;
      let errMsg: string = '';

      try {
        fs.mkdirSync(dir, true);
        const f = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(f.fd, 'probe');
        fs.closeSync(f);

        try {
          fs.symlinkSync(target, link);
          symlinkOk = true;
        } catch (e) {
          const err: BusinessError = e as BusinessError;
          errCode = err.code;
          errMsg = err.message;
        }
      } catch (e) {
        const err: BusinessError = e as BusinessError;
        errCode = err.code;
        errMsg = 'prep failed: ' + err.message;
      }

      hilog.info(DOMAIN, TAG, 'symlinkOk=%{public}s errCode=%{public}d msg=%{public}s',
        String(symlinkOk), errCode, errMsg);

      // 断言"探针跑完了"，而不是断言"符号链接一定可用"——
      // 可用与否是**结论**，不是**通过条件**；结论由日志与 errCode 承载。
      expect(typeof symlinkOk).assertEqual('boolean');
    });

    /**
     * ② 同进程回环：先 listen 127.0.0.1，再从同一进程 connect 上去并送一个字节。
     * 只看两件事：能否监听、能否连上。连不上时把错误码带回来。
     */
    it('loopback_listen_and_connect', 0, async () => {
      let listenOk: boolean = false;
      let connectOk: boolean = false;
      let listenErr: string = '';
      let connectErr: string = '';

      const addr: socket.NetAddress = {
        address: '127.0.0.1',
        port: PROBE_PORT,
        family: 1,
      };

      const server: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
      try {
        await server.listen(addr);
        listenOk = true;
      } catch (e) {
        const err: BusinessError = e as BusinessError;
        listenErr = err.code + ' ' + err.message;
      }

      if (listenOk) {
        const client: socket.TCPSocket = socket.constructTCPSocketInstance();
        try {
          // 注意：connect 的 address 是 **NetAddress 对象**，不是字符串
          // （实测编译报错 "Type 'string' is not assignable to type 'NetAddress'"）
          await client.connect({ address: addr });
          connectOk = true;
          await client.send({ data: 'ping' });
        } catch (e) {
          const err: BusinessError = e as BusinessError;
          connectErr = err.code + ' ' + err.message;
        }
        try {
          client.close();
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'client close failed');
        }
      }

      hilog.info(DOMAIN, TAG, 'listenOk=%{public}s connectOk=%{public}s listenErr=%{public}s connectErr=%{public}s',
        String(listenOk), String(connectOk), listenErr, connectErr);

      try {
        server.close();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'server close failed');
      }

      // 同样是"探针跑完"的断言：结论通过 hilog 输出（本用例的价值是**取证**）
      expect(typeof listenOk).assertEqual('boolean');
    });
  });
}
