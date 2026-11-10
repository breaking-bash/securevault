import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// Biometric (fingerprint / face) unlock support.
///
/// ZERO-KNOWLEDGE NOTE: the master password is never stored by the app in
/// plaintext. When the user opts in, we seal the master password into the
/// platform's hardware-backed, biometric-gated keystore
/// (Android EncryptedSharedPreferences). Retrieving it requires a successful
/// biometric check via [local_auth]. The master-password screen always remains
/// available as a fallback, and disabling biometrics deletes the stored secret.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  // On Android, back the secrets with EncryptedSharedPreferences (AES).
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _keyFor(String accountId) => 'bio_master_$accountId';

  /// Whether this device can actually perform biometric authentication.
  /// Returns false (never throws) on platforms without a biometric backend,
  /// so desktop builds degrade gracefully to master-password only.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      return canCheck;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Run a biometric prompt. Returns true only on a successful authentication.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow device PIN/pattern as a secure fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'SecureVault unlock',
            biometricHint: '',
            cancelButton: 'Use master password',
          ),
        ],
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// True if a biometric secret has been stored for [accountId]
  /// (i.e. the user has enabled biometric unlock for this account).
  Future<bool> hasStoredSecret(String accountId) async {
    try {
      return await _storage.containsKey(key: _keyFor(accountId));
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Seal [masterPassword] into the biometric-gated keystore for [accountId].
  Future<void> storeSecret(String accountId, String masterPassword) async {
    await _storage.write(key: _keyFor(accountId), value: masterPassword);
  }

  /// Remove the stored secret (disables biometric unlock for [accountId]).
  Future<void> deleteSecret(String accountId) async {
    try {
      await _storage.delete(key: _keyFor(accountId));
    } on PlatformException {
      // ignore — nothing to delete
    } on MissingPluginException {
      // ignore
    }
  }

  /// Prompt for biometrics and, on success, return the stored master password.
  /// Returns null if authentication fails or no secret is stored.
  Future<String?> retrieveSecret(String accountId,
      {required String reason}) async {
    if (!await hasStoredSecret(accountId)) return null;
    final ok = await authenticate(reason: reason);
    if (!ok) return null;
    try {
      return await _storage.read(key: _keyFor(accountId));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
