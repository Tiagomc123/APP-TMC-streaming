import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_config.dart';

/// Detecta Android TV / TV Box.
///  1) `navigationMode == directional` -> so existe em aparelho sem toque;
///  2) feature `android.software.leanback` (checagem definitiva).
class TvDetector {
  TvDetector._();

  static bool _isTv = false;
  static bool get isTv => _isTv;

  static bool fromContext(BuildContext context) {
    if (MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional) {
      return true;
    }
    return _isTv;
  }

  static Future<void> warmUp() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
      _isTv = info.systemFeatures.contains('android.software.leanback') ||
          !info.systemFeatures.contains('android.hardware.touchscreen');
      if (_isTv) AppConfig.useTvUserAgent();
    } catch (_) {}
  }
}