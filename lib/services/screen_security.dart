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

  /// Shares autofill options with the native autofill service.
  static Future<void> applyAutofill(bool inline, bool save) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('setAutofillPrefs', {'inline': inline, 'save': save});
    } catch (_) {}
  }
}
