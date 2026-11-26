import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:clashmi/app/utils/platform_utils.dart';
import 'package:clashmi_vpn_service/vpn_service.dart';

class DeviceUtils {
  static Future<bool> disableOrientation() async {
    if (Platform.isWindows) {
      return false;
    }
    if (!PlatformUtils.isMobile()) {
      return true;
    }

    if (Platform.isAndroid) {
      final platformDispatcher = WidgetsBinding.instance.platformDispatcher;
      if (platformDispatcher.views.isEmpty ||
          platformDispatcher.displays.isEmpty) {
        return false;
      }
      var screenWidthInPixels =
          platformDispatcher.views.first.physicalSize.width;
      var devicePixelRatio = platformDispatcher.displays.first.devicePixelRatio;
      double screenWidthInDp = screenWidthInPixels / devicePixelRatio;
      if (screenWidthInDp >= 600) {
        //Android 16  https://developer.android.com/about/versions/16/behavior-changes-16?hl=zh-cn#ignore-orientation
        String version = await FlutterVpnService.getSystemVersion();
        int? v = int.tryParse(version);
        if (v != null && v >= 36) {
          return true;
        }
      }
    }
    return false;
  }
}
