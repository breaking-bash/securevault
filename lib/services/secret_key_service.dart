
import 'package:base32/base32.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto_service.dart';

/// The per-account Secret Key: 128 random bits that are mixed into key
/// derivation together with the master password, so a stolen vault file cannot
/// be brute-forced from the password alone. Displayed as `SV1-XXXXXX-...`.
class SecretKeyService {
  SecretKeyService._();
  static final SecretKeyService instance = SecretKeyService._();

  static const prefix = 'SV1';
  static const _bytes = 16;

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _keyFor(String accountId) => 'secret_key_$accountId';

  /// Generates a new Secret Key in display format.
  String generate() => format(CryptoService.instance.randomBytes(_bytes));

  String format(List<int> bytes) {
    final raw = base32
        .encode(Uint8List.fromList(bytes))
        .replaceAll('=', '');
    final groups = <String>[];
    for (var i = 0; i < raw.length; i += 6) {
      groups.add(raw.substring(i, i + 6 > raw.length ? raw.length : i + 6));
    }
    return '$prefix-${groups.join('-')}';
  }

  /// Parses user-entered text (any case, dashes/spaces optional). Returns null
  /// if it is not a valid Secret Key.
  Uint8List? parse(String input) {
    var s = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (!s.startsWith(prefix)) return null;
    s = s.substring(prefix.length);
    if (s.length != 26) return null;
    try {
      final padded = s.padRight(32, '=');
      final out = base32.decode(padded);
      return out.length == _bytes ? Uint8List.fromList(out) : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> load(String accountId) async {
    try {
      return await _storage.read(key: _keyFor(accountId));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> save(String accountId, String secretKey) async {
    try {
      await _storage.write(key: _keyFor(accountId), value: secretKey);
    } on PlatformException {
      // Not fatal: the user will be asked for the key on next unlock.
    } on MissingPluginException {
      // ignore
    }
  }

  Future<void> delete(String accountId) async {
    try {
      await _storage.delete(key: _keyFor(accountId));
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }
}
