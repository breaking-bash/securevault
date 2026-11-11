import 'dart:io';

import 'package:flutter/services.dart';

/// A pending Android autofill request (set only when the app was opened by the
/// system autofill framework from another app or website).
class AutofillRequest {
  final String? domain;
  final String? package;
  const AutofillRequest(this.domain, this.package);
}

class AutofillBridge {
  static const _ch = MethodChannel('securevault/autofill');

  static Future<AutofillRequest?> getRequest() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _ch.invokeMethod<Map>('getRequest');
      if (m == null) return null;
      return AutofillRequest(m['domain'] as String?, m['package'] as String?);
    } catch (_) {
      return null;
    }
  }

  static Future<void> fill(String username, String password) =>
      _ch.invokeMethod('fill', {'username': username, 'password': password});

  static Future<void> cancel() => _ch.invokeMethod('cancel');
}