// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import { injectable, inject } from 'inversify';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { BaseAdapter } from '../common/BaseAdapter';
import common from '@ohos.app.ability.common';
import LogMethod from '../common/LogDecorator';
import { ContextAdapter } from './ContextAdapter';

@injectable()
export class NativeThemeAdapter extends BaseAdapter {
  private themeSource: ConfigurationConstant.ColorMode;
  private ctxAdapter: ContextAdapter;
  private hasInit: boolean = false;

  constructor(@inject(ContextAdapter) ctxAdapter: ContextAdapter) {
    super();
    this.ctxAdapter = ctxAdapter;
    this.themeSource = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  override init() {
    let activeContext = this.ctxAdapter.getActiveContext() as common.UIAbilityContext ||
                        this.ctxAdapter.getActiveContext() as common.UIExtensionContext;
    if (!activeContext) {
      return;
    }
    if (activeContext.config.colorMode !== undefined) {
      this.themeSource = activeContext.config.colorMode;
    }
  }

  @LogMethod
  getSystemNativeTheme(): ConfigurationConstant.ColorMode {
    if (!this.hasInit) {
      this.init();
      this.hasInit = true;
    }
    return this.themeSource;
  }

  @LogMethod
  setApplicationColorMode(themeSource: ConfigurationConstant.ColorMode) {
    this.ctxAdapter.getContext()
      .getApplicationContext()
      .setColorMode(themeSource);
  }

  setSystemNativeTheme(themeSource: ConfigurationConstant.ColorMode) {
    this.themeSource = themeSource;
    this.nativeContext.SetThemeSource(themeSource);
  }
};