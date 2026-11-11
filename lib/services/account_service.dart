import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/account.dart';
import 'crypto_service.dart';

/// Thrown by [AccountService.createAccount] when an account with the same
/// (case-insensitive, trimmed) username already exists on this device.
class AccountExistsException implements Exception {
  final String username;
  AccountExistsException(this.username);
  @override
  String toString() => 'An account named "$username" already exists.';
}

/// Manages the set of local accounts on this device.
///
/// Accounts are listed in `<appSupport>/securevault/accounts.json`. That index
/// holds only NON-SECRET bookkeeping (display name, KDF salt + params, and the
/// encrypted unlock verifier). Each account's actual vault lives in its own
/// encrypted SQLite file `<appSupport>/securevault/vault_<id>.db`.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  Directory? _baseDir;

  Future<Directory> _dir() async {
    if (_baseDir != null) return _baseDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'securevault'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _baseDir = dir;
    return dir;
  }

  Future<File> _indexFile() async => File(p.join((await _dir()).path, 'accounts.json'));

  Future<String> vaultPathFor(String accountId) async =>
      p.join((await _dir()).path, 'vault_$accountId.db');

  Future<List<LocalAccount>> listAccounts() async {
    final f = await _indexFile();
    if (!await f.exists()) return [];
    try {
      final raw = jsonDecode(await f.readAsString()) as List<dynamic>;
      return raw
          .map((e) => LocalAccount.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<LocalAccount> accounts) async {
    final f = await _indexFile();
    await f.writeAsString(jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }

  /// Create a brand-new account. Derives the key once to build the verifier,
  /// then returns the created account. The derived key is discarded here; the
  /// caller re-derives on unlock.
  Future<LocalAccount> createAccount({
    required String name,
    required String masterPassword,
    List<int>? secretKey,
  }) async {
    final crypto = CryptoService.instance;

    // Enforce unique usernames per device (case-insensitive, trimmed) so the
    // same username cannot create a second/duplicate vault.
    final desiredName = name.trim().isEmpty ? 'My Vault' : name.trim();
    final existing = await listAccounts();
    final clash = existing.any(
        (a) => a.name.trim().toLowerCase() == desiredName.toLowerCase());
    if (clash) {
      throw AccountExistsException(desiredName);
    }

    final rand = crypto.randomBase64(6).replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final id = '${DateTime.now().microsecondsSinceEpoch}_$rand';
    final salt = crypto.randomBytes(16);
    final key = await crypto.deriveKey(
        password: masterPassword, salt: salt, secretKey: secretKey);
    final verifier = await crypto.createVerifier(key);

    final account = LocalAccount(
      id: id,
      name: desiredName,
      kdfSalt: base64Encode(salt),
      kdfMemory: CryptoService.kdfMemoryKiB,
      kdfIterations: CryptoService.kdfIterations,
      kdfParallelism: CryptoService.kdfParallelism,
      verifierNonce: verifier.nonce,
      verifierCipher: verifier.cipher,
      verifierMac: verifier.mac,
      createdAt: DateTime.now(),
      secretKeyRequired: secretKey != null,
    );

    final all = await listAccounts();
    all.add(account);
    await _writeAll(all);
    return account;
  }

  /// Registers an account received from another device. Throws
  /// [StateError] if this device already has it.
  Future<LocalAccount> importAccount(LocalAccount account) async {
    final all = await listAccounts();
    if (all.any((a) => a.id == account.id)) {
      throw StateError('This vault is already on this device.');
    }
    var name = account.name;
    while (all.any((a) => a.name.trim().toLowerCase() == name.toLowerCase())) {
      name = '$name (linked)';
    }
    final imported = account.copyWith(name: name);
    all.add(imported);
    await _writeAll(all);
    return imported;
  }

  Future<void> renameAccount(String id, String newName) async {
    final all = await listAccounts();
    final idx = all.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    all[idx] = all[idx].copyWith(name: newName.trim());
    await _writeAll(all);
  }

  /// Persist an updated account record (used after a master-password change,
  /// which updates the salt + verifier).
  Future<void> updateAccount(LocalAccount account) async {
    final all = await listAccounts();
    final idx = all.indexWhere((a) => a.id == account.id);
    if (idx == -1) {
      all.add(account);
    } else {
      all[idx] = account;
    }
    await _writeAll(all);
  }

  Future<void> deleteAccount(String id) async {
    final all = await listAccounts();
    all.removeWhere((a) => a.id == id);
    await _writeAll(all);
    final vault = File(await vaultPathFor(id));
    if (await vault.exists()) {
      await vault.delete();
    }
  }
}
