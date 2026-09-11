/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 应用唯一的 UIAbility：既承载主窗，也承载每一个会话窗（D1 §7.7.5 / §7.7.5b）。
 *
 * 实例模型（与 platform/window/WindowRegistry.ets 的文件头注释配套阅读）：
 *   module.json5 里 launchType = specified，配合 AppAbilityStage.onAcceptWant 的 key 方案，
 *   得到「一个会话一个实例、其余一切复用同一个主实例」。**所有实例同进程**，所以
 *   appstate 的模块级单例（连接池 / 会话状态机 / 待发队列）天然被所有窗口共享——
 *   这是 §7.7.5b 验收点「开 3 个窗口仍只有 1 条 mux 连接、1 条 $events」的实现基础。
 *   本文件因此**不做任何连接或会话状态**：窗口只是视图，这不是自律，而是分层的硬边界。
 *
 * 本文件负责四件事：
 *   1. 启动参数 → AppStorage（能力层与页面之间的约定交接通道，见 applyLaunchParams）；
 *   2. 窗口台账登记/注销（RuntimeSingleton 是「一个共享运行时而共享单例」的证据面，
 *      登记必须准确，宁可日志报警也不要漏登记）；
 *   3. 窗口记忆（仅主窗）：几何恢复与节流落盘；
 *   4. 窗口生命周期里**只清理本实例自己的东西**——关任一窗口不得影响其他窗口。
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import {
  EVENT_HOST_CONNECTED,
  EVENT_KEY_HOST_TOKEN,
  EVENT_KEY_HOST_URL,
  HostStore,
  parseWindowParams,
  readDeviceFacts,
  registerWindow,
  relabelWindow,
  SecretLoadState,
  unregisterWindow,
  WindowKind,
  WindowMemory,
  WindowParams
} from 'platform';
import type { RememberedHost, RememberedToken } from 'platform';

const DOMAIN = 0x0000;
/** 本文件新增日志的 tag；既有日志沿用 'testTag' 不动，避免无意义的 diff 噪音 */
const TAG: string = 'entry/ability';

/** 窗口几何落盘的最小间隔（ms）。拖动窗口会以帧级频率触发几何变化，直写会打爆 preferences。 */
const GEOMETRY_SAVE_INTERVAL_MS: number = 500;

/**
 * 启动参数经 AppStorage 交给页面的键。
 *
 * 这是**跨 workstream 的契约**：键名一旦定下，能力层与页面两侧都不得各改各的。
 */
const KEY_LAUNCH_KIND: string = 'dshLaunchKind';
const KEY_LAUNCH_SESSION_ID: string = 'dshLaunchSessionId';
const KEY_LAUNCH_TITLE: string = 'dshLaunchTitle';
const KEY_LAUNCH_ROUTE_JSON: string = 'dshLaunchRouteJson';
/**
 * 「上次连上的 Host」经 AppStorage 交给页面的键。
 *
 * 为什么走这条通道而不是让页面自己去读存储：`HostStore` 需要
 * `UIAbilityContext` 才能打开偏好库，而页面拿不到 context；
 * 能力层本来就持有 context，顺手读完再交给页面是唯一不需要页面持有 context 的做法。
 *
 * 三个键对应三种**不同的**处置，不能合成一个字符串：
 *   - `HOST_URL` 非空 → 可以自动重连；
 *   - `HOST_TOKEN_STATE` = `'absent'` → 首次使用，提示粘贴 token；
 *   - `HOST_TOKEN_STATE` = `'unavailable'` → **有记录但读不到**（锁屏策略/系统故障），
 *     此时提示「重新粘贴 token」是错的——token 还在，只是这次读不出来。
 *     D3 §4 要求文案指出「发生了什么 + 可以做什么」，这两种情况的可做之事不同。
 */
const KEY_HOST_URL: string = 'dshLastHostUrl';
const KEY_HOST_TOKEN: string = 'dshLastHostToken';
const KEY_HOST_TOKEN_STATE: string = 'dshLastHostTokenState';
const KEY_HOST_AUTOCONNECT: string = 'dshHostAutoConnect';
/**
 * 页面 → 能力层：报告「刚刚连上了哪个 Host」的进程内事件。
 *
 * 【为什么用 emitter 而不是 AppStorage 订阅】`AppStorage` 没有变更订阅接口
 * （只有 `link`/`prop` 这类声明式双向绑定，能力层用不上）。而这条通路的语义本就是
 * 「一次通知」，不是「一份需要被订阅的状态」——事件总线才是对的工具。
 *
 * 【为什么不让页面直接调 `HostStore`】
 *   1. 页面拿不到 `UIAbilityContext`，而 `HostStore` 需要它才能打开偏好库；
 *   2. **零 UI 依赖**是本工程的架构纪律（`appstate` / `platform` 都不认识 UI），
 *      让页面直接碰平台存储会把存储细节漏进视图层。
 *   页面只报告「连上了哪个 Host」这个**事实**，由能力层决定怎么记。
 *
 * 事件 id 与载荷键来自 `platform`（唯一的契约定义处，见那里为何不能各写一份）。
 */

export default class EntryAbility extends UIAbility {
  /**
   * 本实例的启动参数（onCreate/onNewWant 时刷新）。
   *
   * 初值取「无参数」的解析结果而不是留 undefined：窗口形态在 onCreate 之前就需要被引用
   * （标签、是否恢复几何），给一个安全默认值可以省掉每一个使用点的判空。
   */
  private launchParams: WindowParams = parseWindowParams(undefined);
  /** 本实例窗口的系统 id（字符串化）。空串 = 尚未取到（此时不登记台账）。 */
  private windowId: string = '';
  /** 本实例的主窗口对象；几何读写与监听释放都要用它 */
  private mainWindow: window.Window | undefined = undefined;
  /** 窗口记忆（preferences 句柄），onWindowStageCreate 时 attach */
  private memory: WindowMemory = new WindowMemory();
  /** Host 连接记忆（地址走 preferences、token 走加密存储），onWindowStageCreate 时 attach */
  private hostStore: HostStore = new HostStore();
  /** 窗口记忆就绪信号。几何恢复必须等它，否则会在 store 尚未打开时静默跳过。 */
  private memoryReady: Promise<void> = Promise.resolve();
  /** 节流定时器 id；-1 表示当前无待执行的落盘任务 */
  private geometryTimer: number = -1;
  /** 上一次几何落盘的时间戳 */
  private lastGeometrySaveAt: number = 0;
  /**
   * 几何变化回调。
   * 存成字段（而不是每次现写一个 lambda）是因为 `off()` 必须拿到**同一个函数引用**，
   * 否则解绑会静默失败、留下悬空回调。
   */
  private onGeometryChanged: () => void = () => {
    this.scheduleGeometrySave();
  };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 先于 onWindowStageCreate 发布：窗口标签与「是否主窗」的判断都依赖它
    this.applyLaunchParams(want);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  /**
   * specified 模式**复用**已有实例时的入口——「第二次打开同一会话只聚焦、不新开」的落点。
   *
   * 复用实例时页面不会重建，只有 AppStorage 这条通道能把新路由/新标题送进已有窗口，
   * 所以这里必须重新发布一次启动参数。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant（复用已有实例）');
    this.applyLaunchParams(want);
    if (this.windowId.length > 0) {
      // 会话被改名后再从通知点进来，任务栏/诊断页里的标签要跟上
      relabelWindow(this.windowId, this.ledgerLabel());
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 不把生命周期方法改成 async：系统按「回调返回」判断阶段完成，async 会让它就绪判定
    // 与实际就绪错位；且 ArkTS 会对浮动 Promise 报警。改为记下 Promise，需要时再续接。
    this.memoryReady = this.memory.attach(this.context);
    this.memoryReady.then(() => {
      hilog.info(DOMAIN, TAG, '窗口记忆已就绪（preferences）');
    }).catch((_error: Object) => {
      // attach 内部已兜底（失败时 store = undefined），这里只防御意外；不影响任何功能
      hilog.warn(DOMAIN, TAG, '窗口记忆 attach 异常，几何记忆降级');
    });

    // Host 连接记忆：只在**主窗**上做自动重连的读取与发布。
    // 会话窗（specified 启动、key = session:<id>）是「打开某个会话」，不是「启动应用」，
    // 让它也去自动重连会造成多窗口同时发起认证竞争——而连接池本来就该是单例，
    // 主窗做完之后其它窗口直接复用即可。
    if (this.launchParams.kind === WindowKind.MAIN) {
      this.publishRememberedHost();
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
      } else {
        hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      }
      // 内容加载完成后再登记台账：台账是「窗口已可用」的证据面，登记过早会给出假阳性。
      // 加载失败也照常登记——台账要反映的是**窗口**，不是页面加载成功与否。
      this.afterWindowStageReady(windowStage);
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');

    // 只清理**本实例**的东西。这里刻意不触碰任何共享资源，也不遍历其他窗口——
    // 「关任一窗口不影响其他窗口与其连接」这条验收，正是靠这里的克制成立的。
    if (this.geometryTimer !== -1) {
      clearTimeout(this.geometryTimer);
      this.geometryTimer = -1;
    }
    this.unbindGeometry(this.mainWindow);
    this.mainWindow = undefined;
    if (this.windowId.length > 0) {
      unregisterWindow(this.windowId);
      hilog.info(DOMAIN, TAG, '窗口已注销 id=%{public}s', this.windowId);
      this.windowId = '';
    }
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  /**
   * 窗口就绪后的收尾：登记台账 →（仅主窗）恢复几何 → 监听几何变化。
   *
   * 顺序有讲究：几何恢复依赖 preferences，故挂在 memoryReady 之后而不是直接调用，
   * 否则会因为 store 尚未打开而被 restoreMainGeometry 静默跳过（表现为「记忆失效」）。
   */
  private afterWindowStageReady(windowStage: window.WindowStage): void {
    const win: window.Window | undefined = this.mainWindowOf(windowStage);
    if (win === undefined) {
      return;
    }
    this.mainWindow = win;

    let windowId: string = '';
    try {
      // 直接用手上的 windowStage 取窗口 id，而不是 platform 的 currentWindowId()：
      // 后者要再走一次 getLastWindow，既多一次系统调用，也可能在极端时序下拿到别的窗口。
      windowId = String(win.getWindowProperties().id);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, '读取窗口 id 失败，本次不登记台账：%{public}s', e.message);
    }
    if (windowId.length > 0) {
      this.windowId = windowId;
      registerWindow(windowId, this.ledgerLabel(), readDeviceFacts().form);
      hilog.info(DOMAIN, TAG, '窗口已登记 id=%{public}s label=%{public}s', windowId, this.ledgerLabel());
    }

    // 只有主窗参与几何记忆：saveMainGeometry 固定写 'main.rect'，若让会话窗也监听，
    // 会话窗一挪动就会把主窗的几何覆盖掉（用户会看到主窗位置被「偷走」）。
    if (this.launchParams.kind !== WindowKind.MAIN) {
      return;
    }
    this.memoryReady.then((): Promise<boolean> => {
      return this.memory.restoreMainGeometry(win);
    }).then((restored: boolean) => {
      if (restored) {
        hilog.info(DOMAIN, TAG, '已恢复主窗几何');
      }
    }).catch((_error: Object) => {
      // restoreMainGeometry 内部已吞掉全部异常，这里是纯防御
      hilog.debug(DOMAIN, TAG, '主窗几何恢复异常（已忽略）');
    });
    this.bindGeometry(win);
  }

  /** 取本阶段的窗口；失败返回 undefined（窗口尚未创建/已被销毁都是正常时序）。 */
  private mainWindowOf(windowStage: window.WindowStage): window.Window | undefined {
    try {
      return windowStage.getMainWindowSync();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, '获取窗口失败：%{public}s', e.message);
      return undefined;
    }
  }

  /**
   * 把启动参数发布到 AppStorage——能力层与页面之间的**约定交接通道**。
   *
   * 为什么是 AppStorage：页面由 `loadContent` 内部实例化，能力层拿不到它的入口，无法直接
   * 传构造参数；而 AppStorage 是能力层与页面天然共享的键值仓，页面用
   * `@StorageProp('dshLaunchKind')` 之类即可声明式订阅，参数变化自动刷新。
   *
   * 为什么值一律是**字符串**：跨这条边界传对象字面量或枚举会同时撞上 ArkTS 的类型检查与
   * 取值后的窄化两重麻烦（枚举存进去取出来只剩 string，再 `as` 强转属于自欺）。
   * 统一降级为字符串后，边界上没有任何隐式转换，页面用 platform 侧的常量/枚举自行比对，
   * 路由 JSON 也由页面自己按需解析。
   *
   * 为什么 onCreate 与 onNewWant 都要发布：复用实例时页面**不会重建**，
   * 这条通道是唯一能把新路由送进已有窗口的路径。
   *
   * 已知代价（写下来，免得后来者以为它是免费的）：AppStorage 是**进程级**的，四个键名不带
   * 窗口标识，因此它承载的语义是「最近一次发布的启动参数」。正常情况下每个窗口在自己的
   * onCreate/onNewWant 里发布、紧接着自己的页面初始化时读取，时序自洽；但若两个窗口几乎
   * 同时启动（例如连续 startAbility 两个会话），后发布者会覆盖前者的值，理论上会出现
   * 「新窗口读到上一个窗口的会话」。真正无歧义的做法是**每窗一份**：把参数存进该窗口自己的
   * LocalStorage 并通过 `windowStage.loadContent(path, storage)` 注入，或把窗口 id 拼进键名。
   * 本层按约定只落这四个全局键（页面侧据此读取），故先把风险记在这里：一旦出现
   * 「新窗口显示的是上一个窗口的会话」这类反馈，就按上面的方向改成每窗一份，而不是加锁。
   */
  private applyLaunchParams(want: Want): void {
    const parsed: WindowParams = parseWindowParams(want.parameters);
    this.launchParams = parsed;
    AppStorage.setOrCreate<string>(KEY_LAUNCH_KIND, kindText(parsed.kind));
    AppStorage.setOrCreate<string>(KEY_LAUNCH_SESSION_ID, parsed.sessionId);
    AppStorage.setOrCreate<string>(KEY_LAUNCH_TITLE, parsed.title);
    AppStorage.setOrCreate<string>(KEY_LAUNCH_ROUTE_JSON, parsed.routeJson);
  }

  /**
   * 读取「上次连上的 Host」并发布给页面，供自动重连使用。
   *
   * 【为什么必须先发布 `autoConnect = false`】页面可能比这次异步读取更早就绪。
   * 若只发布最终结果，页面在「还没读到」的那一刻会看到空 URL，从而显示
   * 「请添加 Host」——用户明明上次连过，却被告知没有记录。
   * 因此先立一个明确的「尚未就绪」标志，页面据此**等待**而不是**下结论**。
   *
   * 【为什么 token 读不到时不自动重连】读不到只有两种可能：本次使用（没记录）
   * 或存储系统暂时不可用。后者的正确处置是**让用户看到真实原因**，
   * 而不是拿空 token 去认证——那会得到 401，而 401 的文案会把用户引向
   * 「token 无效」，与真实原因（读不出来）不符。
   */
  private publishRememberedHost(): void {
    AppStorage.setOrCreate<string>(KEY_HOST_URL, '');
    AppStorage.setOrCreate<string>(KEY_HOST_TOKEN, '');
    AppStorage.setOrCreate<string>(KEY_HOST_TOKEN_STATE, 'pending');
    AppStorage.setOrCreate<boolean>(KEY_HOST_AUTOCONNECT, false);

    // 页面连上之后会发事件报告「刚连上的 Host」，这里订阅并落盘
    // （地址走 preferences，token 走加密存储）。
    emitter.on({ eventId: EVENT_HOST_CONNECTED }, (data: emitter.EventData) => {
      const payload: Record<string, Object> = (data.data ?? {}) as Record<string, Object>;
      const url: string = typeof payload[EVENT_KEY_HOST_URL] === 'string'
        ? payload[EVENT_KEY_HOST_URL] as string : '';
      const token: string = typeof payload[EVENT_KEY_HOST_TOKEN] === 'string'
        ? payload[EVENT_KEY_HOST_TOKEN] as string : '';
      this.persistConnectedHost(url, token);
    });

    const ready: Promise<void> = this.hostStore.attach(this.context);
    ready.then(async () => {
      const host: RememberedHost | undefined = await this.hostStore.loadHost();
      if (host === undefined) {
        AppStorage.setOrCreate<string>(KEY_HOST_TOKEN_STATE, 'absent');
        return;
      }
      // 【修复早期版本留下的明文凭据】早期版本把用户粘贴的整串启动 URL
      // （含 `?token=…`）当成 baseUrl 存进了明文 preferences。这里在读取时
      // 剥掉 query 并回写，避免那份明文一直留在设备上。
      // 剥掉之后 token 需要重新建立（旧记录的 token 没进加密存储），
      // 因此这次会走到「没有可用的访问令牌」分支，请用户重贴一次——
      // 这是**有意的**：宁可让用户重贴一次，也不留一份明文凭据在设备上。
      const cut: number = host.baseUrl.search(/[?#]/);
      if (cut >= 0) {
        const sanitized: string = host.baseUrl.substring(0, cut);
        hilog.warn(DOMAIN, TAG, '检测到旧版明文 URL 记录，已剥离凭据并回写');
        await this.hostStore.saveHost(sanitized, host.lastSessionId);
        AppStorage.setOrCreate<string>(KEY_HOST_URL, sanitized);
        AppStorage.setOrCreate<string>(KEY_HOST_TOKEN_STATE, 'absent');
        return;
      }
      const token: RememberedToken = await this.hostStore.loadToken(host.baseUrl);
      AppStorage.setOrCreate<string>(KEY_HOST_URL, host.baseUrl);
      AppStorage.setOrCreate<string>(KEY_HOST_TOKEN_STATE, token.state as string);
      if (token.state === SecretLoadState.FOUND) {
        AppStorage.setOrCreate<string>(KEY_HOST_TOKEN, token.value);
        AppStorage.setOrCreate<boolean>(KEY_HOST_AUTOCONNECT, true);
      }
      hilog.info(DOMAIN, TAG, '记住的 Host=%{public}s token 状态=%{public}s',
        host.baseUrl, token.state as string);
    }).catch((_error: Object) => {
      // attach 内部已兜底；这里只把状态标成「读不到」，页面会给出对应文案
      AppStorage.setOrCreate<string>(KEY_HOST_TOKEN_STATE, 'unavailable');
      hilog.warn(DOMAIN, TAG, 'Host 连接记忆读取异常，本次不自动重连');
    });
  }

  /** 把页面报告的「刚连上的 Host」落盘（地址明文、token 加密） */
  private persistConnectedHost(url: string, token: string): void {
    if (url.length === 0) {
      return;
    }
    this.hostStore.saveHost(url, '').then(() => {
      if (token.length > 0) {
        return this.hostStore.saveToken(url, token);
      }
      return false;
    }).then((saved: boolean) => {
      // token 保存失败**不是**连接失败：只影响「下次能否自动重连」。
      // 如实记日志，不弹错误——用户这次已经连上了，报错只会制造困惑。
      hilog.info(DOMAIN, TAG, 'Host 已记住 url=%{public}s tokenLen=%{public}d tokenSaved=%{public}s',
        url, token.length, saved ? 'true' : 'false');
    }).catch((_error: Object) => {
      hilog.warn(DOMAIN, TAG, 'Host 落盘异常（不影响本次连接）');
    });
  }

  /** 台账标签：主窗固定；会话窗带标题，方便在诊断页与任务栏之间对号入座。 */
  private ledgerLabel(): string {
    const p: WindowParams = this.launchParams;
    if (p.kind === WindowKind.SESSION) {
      const shown: string = p.title.length > 0 ? p.title : p.sessionId;
      return shown.length > 0 ? `会话窗：${shown}` : '会话窗';
    }
    return '主窗';
  }

  /** 注册几何监听（仅主窗调用）。监听失败只降级为「不记忆几何」，不阻断窗口创建。 */
  private bindGeometry(win: window.Window): void {
    try {
      win.on('windowSizeChange', this.onGeometryChanged);
      win.on('windowRectChange', this.onGeometryChanged);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, '注册窗口几何监听失败，几何记忆降级：%{public}s', e.message);
    }
  }

  /** 解绑几何监听；必须传同一个函数引用，否则会留下悬空回调。 */
  private unbindGeometry(win: window.Window | undefined): void {
    if (win === undefined) {
      return;
    }
    try {
      win.off('windowSizeChange', this.onGeometryChanged);
      win.off('windowRectChange', this.onGeometryChanged);
    } catch (err) {
      const e = err as BusinessError;
      hilog.debug(DOMAIN, TAG, '解绑窗口几何监听失败：%{public}s', e.message);
    }
  }

  /**
   * 几何变化节流：首次变化立即落盘，其后 500 ms 内的连续变化合并为一次**尾部**写入。
   *
   * 取舍：为什么保留尾部写入而不是只做「每 500 ms 采样一次」——用户拖动结束的那一次位置
   * 才是他真正想要的；若在拖动途中写下一个中间值就收工，进程随后被杀就会丢掉终点位置。
   * 立即写 + 合并尾部，两者都拿到了，代价只是一个最多 500 ms 的定时器。
   */
  private scheduleGeometrySave(): void {
    const now: number = Date.now();
    const elapsed: number = now - this.lastGeometrySaveAt;
    if (elapsed >= GEOMETRY_SAVE_INTERVAL_MS) {
      this.lastGeometrySaveAt = now;
      this.saveGeometryNow();
      return;
    }
    if (this.geometryTimer !== -1) {
      return;
    }
    this.geometryTimer = setTimeout(() => {
      this.geometryTimer = -1;
      this.lastGeometrySaveAt = Date.now();
      this.saveGeometryNow();
    }, GEOMETRY_SAVE_INTERVAL_MS - elapsed);
  }

  private saveGeometryNow(): void {
    const win: window.Window | undefined = this.mainWindow;
    if (win === undefined) {
      return;
    }
    this.memory.saveMainGeometry(win).then(() => {
      // 落盘成功无需处理：几何记忆不是关键路径，成功与否都不影响用户可见行为
    }).catch((_error: Object) => {
      hilog.debug(DOMAIN, TAG, '主窗几何落盘失败（已忽略）');
    });
  }
}

/**
 * 枚举 → 字符串。
 *
 * 单独抽出来的理由：`WindowKind` 是字符串枚举，但把它直接赋给 `string` 在 ArkTS 里
 * 依赖枚举的隐式兼容；显式转换让「AppStorage 里到底存的什么字面量」一目了然，
 * 也避免将来枚举值改动时静默改变跨层契约。
 */
function kindText(kind: WindowKind): string {
  return kind === WindowKind.SESSION ? 'session' : 'main';
}
