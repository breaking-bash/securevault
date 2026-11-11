import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Toggles Android's FLAG_SECURE (screenshots, recording, recents preview).
class ScreenSecurity {
  static const _ch = MethodChannel('securevault/autofill');

  static Future<void> apply(bool block) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('setSecure', block);
    } catch (_) {}
  }
}
