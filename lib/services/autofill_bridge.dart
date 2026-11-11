import 'dart:io';

import 'package:flutter/services.dart';

/// A pending Android autofill request (set only when the app was opened by the
/// system autofill framework from another app or website).
class AutofillRequest {
  final String? domain;
  final String? package;
  // Set when Android asks to save credentials the user just typed.
  final bool isSave;
  final String saveUsername;
  final String savePassword;
  // Set for Credential Manager passkey requests: 'create' or 'get'.
  final String? passkeyMode;
  final String? rpId;
  final String? rpName;
  final String? userName;
  final String? displayName;
  const AutofillRequest(this.domain, this.package,
      {this.isSave = false,
      this.saveUsername = '',
      this.savePassword = '',
      this.passkeyMode,
      this.rpId,
      this.rpName,
      this.userName,
      this.displayName});
}

class AutofillBridge {
  static const _ch = MethodChannel('securevault/autofill');

  static Future<AutofillRequest?> getRequest() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _ch.invokeMethod<Map>('getRequest');
      if (m == null) return null;
      return AutofillRequest(m['domain'] as String?, m['package'] as String?,
          isSave: (m['save'] ?? false) as bool,
          saveUsername: (m['saveUser'] ?? '') as String,
          savePassword: (m['savePass'] ?? '') as String,
          passkeyMode: m['passkeyMode'] as String?,
          rpId: m['rpId'] as String?,
          rpName: m['rpName'] as String?,
          userName: m['userName'] as String?,
          displayName: m['displayName'] as String?);
    } catch (_) {
      return null;
    }
  }

  static Future<void> fill(String username, String password) =>
      _ch.invokeMethod('fill', {'username': username, 'password': password});

  static Future<Map<String, String>> passkeyCreate() async {
    final m = await _ch.invokeMethod<Map>('passkeyCreate');
    return {for (final e in (m ?? {}).entries) e.key as String: e.value as String};
  }

  static Future<void> passkeyComplete() => _ch.invokeMethod('passkeyComplete');

  static Future<void> passkeyAssert(
          {required String privateKey,
          required String credentialId,
          required String userHandle}) =>
      _ch.invokeMethod('passkeyAssert', {
        'privateKey': privateKey,
        'credentialId': credentialId,
        'userHandle': userHandle,
      });

  static Future<void> cancel() => _ch.invokeMethod('cancel');
}