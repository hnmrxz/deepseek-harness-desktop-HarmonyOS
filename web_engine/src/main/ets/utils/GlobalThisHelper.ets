// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import LogUtil from '../utils/LogUtil';
import { GlobalContext } from '../utils/GlobalContext';
import Inject from '../common/InjectModule';
import { DependencyProvider } from '../interface/Dependency';
import { StringStack } from '../utils/StringStackUtil';

const TAG = 'GlobalThisHelper';
const INIT_ABILITY: string = 'init_ability';
const ACTIVE_BROWSER_IDS: string = 'active_browser_ids';

export class GlobalThisHelper {
  private static global: GlobalContext = GlobalContext.getInstance();

  public static createValue<T extends Object>(key: string,
                                              value: T,
                                              forceChange: boolean = false) {
    if ((GlobalThisHelper.global.getObject(key) === undefined) || forceChange) {
      GlobalThisHelper.global.setObject(key, value);
      LogUtil.info(TAG, `GlobalThisHelper Create key of ${key}`);
    }
  }

  public static getValue<T extends Object>(key: string): T | undefined {
    if (GlobalThisHelper.global.getObject(key) === undefined) {
      LogUtil.error(TAG, `The storageKey is not exist, key = ${key}`);
      return undefined;
    }
    return ((GlobalThisHelper.global.getObject(key)) as T);
  }

  public static appInit(provider: DependencyProvider): void {
    Inject.inject(provider);
    GlobalThisHelper.global.setObject(INIT_ABILITY, true);
    LogUtil.info(TAG, `app init done`);
  }

  public static appUnInit(): void {
    Inject.destroy();
    LogUtil.info(TAG, `app UnInit done`);
  }

  public static isLaunched(): boolean {
    if (GlobalThisHelper.global.getObject(INIT_ABILITY) === undefined) {
      return false;
    }
    return GlobalThisHelper.global.getObject(INIT_ABILITY) as boolean;
  }

  public static pushActiveBrowserId(xcomponentId: string): void {
    if (GlobalThisHelper.global.getObject(ACTIVE_BROWSER_IDS) === undefined) {
      GlobalThisHelper.global.setObject(ACTIVE_BROWSER_IDS, new StringStack());
    }
    let records =
      GlobalThisHelper.global.getObject(ACTIVE_BROWSER_IDS) as StringStack;
    records.remove(xcomponentId);
    records.push(xcomponentId);
  }

  public static delActiveBrowserId(xcomponentId: string): void {
    if (GlobalThisHelper.global.getObject(ACTIVE_BROWSER_IDS) === undefined) {
      return;
    }
    let records =
      GlobalThisHelper.global.getObject(ACTIVE_BROWSER_IDS) as StringStack;
    records.remove(xcomponentId);
  }

  public static getLastActiveBrowserId(): string | undefined {
    if (GlobalThisHelper.global.getObject(ACTIVE_BROWSER_IDS) === undefined) {
      return undefined;
    }
    let records =
      GlobalThisHelper.global.getObject(ACTIVE_BROWSER_IDS) as StringStack;
    if (records.isEmpty()) {
      return undefined;
    }
    return records.peek();
  }
}
