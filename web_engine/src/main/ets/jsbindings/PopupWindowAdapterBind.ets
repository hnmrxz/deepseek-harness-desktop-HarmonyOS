// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import JsBindingUtils from '../utils/JsBindingUtils';
import Inject from "../common/InjectModule";
import lazy { PopupWindowAdapter } from '../adapter/PopupWindowAdapter';
import type { NewWindowParam, WindowBound } from '../interface/CommonInterface';

function implPopupWindowAdapter(): PopupWindowAdapter {
  return Inject.getOrCreate(PopupWindowAdapter);
}

function createWindow(param: NewWindowParam) {
  implPopupWindowAdapter().createWindow(param);
}

function closeWindow(id: number) {
  implPopupWindowAdapter().closeWindow(id);
}

function showWindow(id: number) {
  implPopupWindowAdapter().showWindow(id);
}

function hideWindow(id: number) {
  implPopupWindowAdapter().hideWindow(id);
}

function activateWindow(id: number) {
  implPopupWindowAdapter().activateWindow(id);
}

function setBounds(id: number,
                   bounds: WindowBound) {
  implPopupWindowAdapter().setBounds(id, bounds);
}

function setWindowLimits(minWidth: number, minHeight: number, maxWidth: number, maxHeight: number, id: number) {
  implPopupWindowAdapter().setWindowLimits(minWidth, minHeight, maxWidth, maxHeight, id);
}

function setEnabled(enable: boolean, id: number): boolean {
  return implPopupWindowAdapter().setEnabled(enable, id);
}

function setBackgroundColor(id: number, argbColor: number) {
  implPopupWindowAdapter().setBackgroundColor(id, argbColor);
}

function setOpacity(id: number, opacity: number) {
  implPopupWindowAdapter().setOpacity(id, opacity);
}

function setContentProtection(id: number, enable: boolean) {
  implPopupWindowAdapter().setContentProtection(id, enable);
}

function startWindowMoving(id: number) {
  implPopupWindowAdapter().startWindowMoving(id);
}

function getOriginWindowId(id: number): number {
  return implPopupWindowAdapter().getOriginWindowId(id);
}

function setWindowShadow(id: number, hasShadow: boolean) {
  implPopupWindowAdapter().setWindowShadow(id, hasShadow);
}

export class PopupWindowAdapterBind {
  static bind() {
    JsBindingUtils.bindFunction("PopupWindow.CreateWindow", createWindow);
    JsBindingUtils.bindFunction("PopupWindow.CloseWindow", closeWindow);
    JsBindingUtils.bindFunction("PopupWindow.ShowWindow", showWindow);
    JsBindingUtils.bindFunction("PopupWindow.HideWindow", hideWindow);
    JsBindingUtils.bindFunction("PopupWindow.ActivateWindow", activateWindow);
    JsBindingUtils.bindFunction("PopupWindow.SetBounds", setBounds);
    JsBindingUtils.bindFunction("PopupWindow.SetWindowLimits", setWindowLimits);
    JsBindingUtils.bindFunction("PopupWindow.SetEnabled", setEnabled);
    JsBindingUtils.bindFunction("PopupWindow.SetBackgroundColor", setBackgroundColor);
    JsBindingUtils.bindFunction("PopupWindow.SetOpacity", setOpacity);
    JsBindingUtils.bindFunction("PopupWindow.SetContentProtection", setContentProtection);
    JsBindingUtils.bindFunction("PopupWindow.StartWindowMoving", startWindowMoving);
    JsBindingUtils.bindFunction("PopupWindow.GetOriginWindowId", getOriginWindowId);
    JsBindingUtils.bindFunction("PopupWindow.SetWindowShadow", setWindowShadow);
  }
}