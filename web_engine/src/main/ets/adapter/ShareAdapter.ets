// Copyright (c) 2024 Huawei Device Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import { inject, injectable } from 'inversify';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@ohos.base';

import { BaseAdapter } from '../common/BaseAdapter';
import LogMethod from '../common/LogDecorator';
import LogUtil from '../utils/LogUtil';
import { ContextAdapter } from './ContextAdapter';

const TAG: string = 'ShareAdapter';

interface ShareAnchorOffset {
  x: number,
  y: number
}

interface ShareAnchorSize {
  width: number,
  height: number
}

interface ShareAnchorRect {
  windowOffset: ShareAnchorOffset,
  size?: ShareAnchorSize
}

interface ShareRecordOptions {
  utd?: string,
  type?: string,
  content?: string,
  uri?: string,
  path?: string,
  title?: string,
  description?: string
}

interface ShareDataOptions extends ShareRecordOptions {
  records?: ShareRecordOptions[],
  anchor?: string | ShareAnchorRect
}

interface ShareShowOptions {
  anchor: string | ShareAnchorRect
}

@injectable()
export class ShareAdapter extends BaseAdapter {
  private ctxAdapter: ContextAdapter;

  constructor(@inject(ContextAdapter) ctxAdapter: ContextAdapter) {
    super();
    this.ctxAdapter = ctxAdapter;
  }

  @LogMethod
  shareData(optionsJson: string, callback: (success: boolean, error: string) => void): void {
    let options: ShareDataOptions;
    try {
      options = JSON.parse(optionsJson) as ShareDataOptions;
    } catch (err) {
      callback(false, 'Invalid share data JSON: ' + JSON.stringify(err));
      return;
    }

    let records = options.records && options.records.length > 0 ? options.records : [options];
    let firstRecord = this.createSharedRecord(records[0]);
    if (!firstRecord) {
      callback(false, 'Share data must contain content, uri, or path.');
      return;
    }

    let data: systemShare.SharedData = new systemShare.SharedData(firstRecord);
    for (let i = 1; i < records.length; i++) {
      let record = this.createSharedRecord(records[i]);
      if (record) {
        data.addRecord(record);
      }
    }

    let context = this.ctxAdapter.getActiveContext() as common.UIAbilityContext;
    if (!context) {
      callback(false, 'No active UIAbility context for share panel.');
      return;
    }

    try {
      let controller: systemShare.ShareController = new systemShare.ShareController(data);
      controller.on('dismiss', () => {
        LogUtil.info(TAG, 'Share panel closed');
      });
      let result = controller.show(context, this.createShowOptions(options)) as Promise<void> | undefined;
      if (result) {
        result.then(() => {
          callback(true, '');
        }).catch((err: BusinessError) => {
          callback(false, 'Failed to show share panel: ' + JSON.stringify(err));
        });
      } else {
        callback(true, '');
      }
    } catch (err) {
      callback(false, 'Failed to share data: ' + JSON.stringify(err));
    }
  }

  private createSharedRecord(options: ShareRecordOptions): systemShare.SharedRecord | undefined {
    let uri = this.normalizeUri(options.uri, options.path);
    if (!options.content && !uri) {
      return undefined;
    }

    let record: systemShare.SharedRecord = {
      utd: this.resolveUtd(options, uri)
    };
    if (options.content) {
      record.content = options.content;
    }
    if (uri) {
      record.uri = uri;
    }
    if (options.title) {
      record.title = options.title;
    }
    if (options.description) {
      record.description = options.description;
    }
    return record;
  }

  private resolveUtd(options: ShareRecordOptions, uri: string): string {
    if (options.utd) {
      return options.utd;
    }
    if (uri) {
      let extension = this.getFileExtension(uri);
      if (extension.length > 0) {
        return this.resolveUtdByExtension(extension);
      }
    }
    switch (options.type) {
      case 'image':
        return 'general.image';
      case 'video':
        return 'general.video';
      case 'file':
        return 'general.file';
      case 'text':
      default:
        return utd.UniformDataType.PLAIN_TEXT;
    }
  }

  private resolveUtdByExtension(extension: string): string {
    switch (extension.toLowerCase()) {
      case 'txt':
      case 'md':
      case 'json':
        return 'general.text';
      case 'png':
        return 'general.png';
      case 'jpg':
      case 'jpeg':
        return 'general.jpeg';
      case 'gif':
        return 'general.gif';
      case 'mp4':
        return 'general.mpeg-4';
      case 'mov':
        return 'general.quicktime-movie';
      case 'pdf':
        return 'com.adobe.pdf';
      default:
        return 'general.file';
    }
  }

  private normalizeUri(uri?: string, path?: string): string {
    let value = uri && uri.length > 0 ? uri : path;
    if (!value || value.length === 0) {
      return '';
    }
    if (value.startsWith('file://') || value.startsWith('datashare://') || value.startsWith('content://')) {
      return value;
    }
    try {
      return fileUri.getUriFromPath(value);
    } catch (err) {
      LogUtil.warn(TAG, 'Failed to convert path to URI: ' + JSON.stringify(err));
      return value;
    }
  }

  private getFileExtension(uri: string): string {
    let queryIndex = uri.indexOf('?');
    let path = queryIndex >= 0 ? uri.substring(0, queryIndex) : uri;
    let dotIndex = path.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex === path.length - 1) {
      return '';
    }
    return path.substring(dotIndex + 1);
  }

  private createShowOptions(options: ShareDataOptions): ShareShowOptions {
    if (options.anchor) {
      let showOptions: ShareShowOptions = {
        anchor: options.anchor
      };
      return showOptions;
    }
    let windowOffset: ShareAnchorOffset = { x: 100, y: 100 };
    let size: ShareAnchorSize = { width: 0, height: 0 };
    let anchor: ShareAnchorRect = {
      windowOffset: windowOffset,
      size: size
    };
    let showOptions: ShareShowOptions = {
      anchor: anchor
    };
    return showOptions;
  }
}
