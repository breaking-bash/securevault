import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/account.dart';
import '../models/folder.dart';
import '../models/secure_note.dart';
import '../models/vault_entry.dart';
import '../services/account_service.dart';
import '../services/biometric_service.dart';
import '../services/crypto_service.dart';
import '../services/database_service.dart';
import '../services/secret_key_service.dart';
import '../services/settings_service.dart';

/// Central app controller. Holds the in-memory master key while unlocked,
/// exposes the decrypted vault contents, and drives auto-lock + clipboard
/// auto-clear. Never persists the key or master password.
class VaultState extends ChangeNotifier {
  final _crypto = CryptoService.instance;
  final _accounts = AccountService.instance;
  final _db = DatabaseService.instance;

  // ---- settings ----
  AppSettings settings = AppSettings();

  // ---- session state ----
  List<LocalAccount> accountsList = [];
  LocalAccount? _account;
  SecretKey? _key; // in-memory only
  bool _unlocked = false;

  // Held in memory ONLY while unlocked so the user can opt into biometric
  // unlock from Settings (we need the plaintext to seal it in the OS keystore).
  // Cleared on lock(); never persisted by VaultState itself.
  String? _sessionMasterPassword;
  String? get sessionMasterPassword => _sessionMasterPassword;

  // Account Secret Key for the current session (null for legacy accounts).
  String? _sessionSecretKey;
  String? get sessionSecretKey => _sessionSecretKey;

  /// True if unlocking [account] needs the user to type its Secret Key (it is
  /// required but not stored on this device).
  Future<bool> needsSecretKey(LocalAccount account) async {
    if (!account.secretKeyRequired) return false;
    return await SecretKeyService.instance.load(account.id) == null;
  }

  LocalAccount? get account => _account;
  bool get unlocked => _unlocked;
  bool get hasAccounts => accountsList.isNotEmpty;

  // ---- decrypted data (only while unlocked) ----
  final List<VaultEntry> entries = [];
  final List<SecureNote> notes = [];
  final List<VaultFolder> folders = [];

  Timer? _lockTimer;
  Timer? _clipboardTimer;

  Future<void> init() async {
    DatabaseService.initPlatform();
    settings = await SettingsService.instance.load();
    accountsList = await _accounts.listAccounts();
    notifyListeners();
  }

  Future<void> reloadAccounts() async {
    accountsList = await _accounts.listAccounts();
    notifyListeners();
  }

  // ---------------------------------------------------------------- accounts
  Future<void> createAccountAndUnlock({
    required String name,
    required String masterPassword,
  }) async {
    final sk = SecretKeyService.instance;
    final secretKey = sk.generate();
    final account = await _accounts.createAccount(
        name: name,
        masterPassword: masterPassword,
        secretKey: sk.parse(secretKey));
    accountsList = await _accounts.listAccounts();
    await unlock(
        account: account,
        masterPassword: masterPassword,
        secretKey: secretKey);
  }

  /// Returns true on success, false if the master password was wrong.
  Future<bool> unlock({
    required LocalAccount account,
    required String masterPassword,
    String? secretKey,
  }) async {
    final sk = SecretKeyService.instance;
    String? secretText;
    if (account.secretKeyRequired) {
      secretText = secretKey ?? await sk.load(account.id);
      if (secretText == null || sk.parse(secretText) == null) return false;
    }
    final salt = base64Decode(account.kdfSalt);
    final key = await _crypto.deriveKey(
      password: masterPassword,
      salt: salt,
      memoryKiB: account.kdfMemory,
      iterations: account.kdfIterations,
      parallelism: account.kdfParallelism,
      secretKey: secretText == null ? null : sk.parse(secretText),
    );
    final verifier = SealedBox(
        account.verifierNonce, account.verifierCipher, account.verifierMac);
    final ok = await _crypto.checkVerifier(key, verifier);
    if (!ok) return false;

    _account = account;
    _key = key;
    _unlocked = true;
    _sessionMasterPassword = masterPassword;
    _sessionSecretKey = secretText;
    if (secretText != null) await sk.save(account.id, secretText);

    await _db.open(await _accounts.vaultPathFor(account.id));
    await _loadAll();
    _restartLockTimer();
    notifyListeners();
    return true;
  }

  Future<void> lock() async {
    _lockTimer?.cancel();
    _clipboardTimer?.cancel();
    _key = null;
    _unlocked = false;
    _sessionMasterPassword = null;
    _sessionSecretKey = null;
    entries.clear();
    notes.clear();
    folders.clear();
    await _db.close();
    notifyListeners();
  }

  /// Full sign-out: lock and forget which account was active.
  Future<void> signOut() async {
    await lock();
    _account = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ load/decrypt
  Future<void> _loadAll() async {
    final key = _key!;
    folders.clear();
    entries.clear();
    notes.clear();

    for (final row in await _db.readFolders()) {
      final sealed = _sealedFrom(row['payload'] as String);
      final json = await _crypto.decryptJson(key, sealed);
      folders.add(VaultFolder.fromSecretJson(
        json,
        id: row['id'] as String,
        createdAt: _dt(row['created_at']),
      ));
    }
    for (final row in await _db.readEntries()) {
      final sealed = _sealedFrom(row['payload'] as String);
      final json = await _crypto.decryptJson(key, sealed);
      entries.add(VaultEntry.fromSecretJson(
        json,
        id: row['id'] as String,
        folderId: row['folder_id'] as String?,
        createdAt: _dt(row['created_at']),
        updatedAt: _dt(row['updated_at']),
      ));
    }
    for (final row in await _db.readNotes()) {
      final sealed = _sealedFrom(row['payload'] as String);
      final json = await _crypto.decryptJson(key, sealed);
      notes.add(SecureNote.fromSecretJson(
        json,
        id: row['id'] as String,
        folderId: row['folder_id'] as String?,
        createdAt: _dt(row['created_at']),
        updatedAt: _dt(row['updated_at']),
      ));
    }
    folders
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  SealedBox _sealedFrom(String payload) =>
      SealedBox.fromJson(jsonDecode(payload) as Map<String, dynamic>);

  DateTime _dt(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch((ms as int?) ?? 0);

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_crypto.randomBase64(4).replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}';

  // ---------------------------------------------------------------- entries
  Future<void> saveEntry(VaultEntry entry, {bool isNew = false}) async {
    _touch();
    final key = _key!;
    entry.updatedAt = DateTime.now();
    final sealed = await _crypto.encryptJson(key, entry.toSecretJson());
    await _db.upsertEntry(
      id: entry.id,
      folderId: entry.folderId,
      createdAt: entry.createdAt.millisecondsSinceEpoch,
      updatedAt: entry.updatedAt.millisecondsSinceEpoch,
      payload: jsonEncode(sealed.toJson()),
    );
    if (isNew) {
      entries.insert(0, entry);
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
  }

  VaultEntry newEntryDraft({EntryType type = EntryType.login}) {
    final now = DateTime.now();
    return VaultEntry(
        id: _newId(), title: '', type: type, createdAt: now, updatedAt: now);
  }

  Future<void> deleteEntry(VaultEntry entry) async {
    _touch();
    await _db.deleteEntry(entry.id);
    entries.removeWhere((e) => e.id == entry.id);
    notifyListeners();
  }

  // ------------------------------------------------------------ device link
  /// Snapshot of the encrypted vault for sending to another device. Contains
  /// only ciphertext plus the non-secret KDF/verifier metadata.
  Future<Map<String, dynamic>> exportForLink() async {
    final acc = _account;
    if (acc == null || !_unlocked) {
      throw StateError('Unlock the vault first.');
    }
    return {
      'account': acc.toJson(),
      'folders': await _db.readFolders(),
      'entries': await _db.readEntries(),
      'notes': await _db.readNotes(),
    };
  }

  /// Imports a vault received from another device. The user then unlocks it
  /// with the original master password.
  Future<LocalAccount> importFromLink(Map<String, dynamic> data) async {
    List<Map<String, Object?>> rows(String k) => ((data[k] ?? const []) as List)
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
    final incoming =
        LocalAccount.fromJson(data['account'] as Map<String, dynamic>);
    final account = await _accounts.importAccount(incoming);
    await _db.importRows(
      path: await _accounts.vaultPathFor(account.id),
      folders: rows('folders'),
      entries: rows('entries'),
      notes: rows('notes'),
    );
    accountsList = await _accounts.listAccounts();
    notifyListeners();
    return account;
  }

  // ---------------------------------------------------------------- notes
  Future<void> saveNote(SecureNote note, {bool isNew = false}) async {
    _touch();
    final key = _key!;
    note.updatedAt = DateTime.now();
    final sealed = await _crypto.encryptJson(key, note.toSecretJson());
    await _db.upsertNote(
      id: note.id,
      folderId: note.folderId,
      createdAt: note.createdAt.millisecondsSinceEpoch,
      updatedAt: note.updatedAt.millisecondsSinceEpoch,
      payload: jsonEncode(sealed.toJson()),
    );
    if (isNew) notes.insert(0, note);
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
  }

  SecureNote newNoteDraft() {
    final now = DateTime.now();
    return SecureNote(id: _newId(), title: '', createdAt: now, updatedAt: now);
  }

  Future<void> deleteNote(SecureNote note) async {
    _touch();
    await _db.deleteNote(note.id);
    notes.removeWhere((n) => n.id == note.id);
    notifyListeners();
  }

  // ---------------------------------------------------------------- folders
  Future<VaultFolder> createFolder(String name) async {
    _touch();
    final key = _key!;
    final folder =
        VaultFolder(id: _newId(), name: name.trim(), createdAt: DateTime.now());
    final sealed = await _crypto.encryptJson(key, folder.toSecretJson());
    await _db.upsertFolder(
      id: folder.id,
      createdAt: folder.createdAt.millisecondsSinceEpoch,
      payload: jsonEncode(sealed.toJson()),
    );
    folders.add(folder);
    folders
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(VaultFolder folder, String name) async {
    _touch();
    final key = _key!;
    folder.name = name.trim();
    final sealed = await _crypto.encryptJson(key, folder.toSecretJson());
    await _db.upsertFolder(
      id: folder.id,
      createdAt: folder.createdAt.millisecondsSinceEpoch,
      payload: jsonEncode(sealed.toJson()),
    );
    folders
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
  }

  Future<void> deleteFolder(VaultFolder folder) async {
    _touch();
    await _db.deleteFolder(folder.id);
    folders.removeWhere((f) => f.id == folder.id);
    for (final e in entries) {
      if (e.folderId == folder.id) e.folderId = null;
    }
    for (final n in notes) {
      if (n.folderId == folder.id) n.folderId = null;
    }
    notifyListeners();
  }

  String folderName(String? id) {
    if (id == null) return 'No folder';
    final f = folders.where((f) => f.id == id);
    return f.isEmpty ? 'No folder' : f.first.name;
  }

  // -------------------------------------------------- master password change
  /// Re-derive a new key from [newPassword] and re-encrypt EVERY record, then
  /// update the account's salt + verifier. Returns false if [currentPassword]
  /// is wrong.
  Future<bool> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
    String? newSecretKey,
  }) async {
    final acc = _account;
    if (acc == null || _key == null) return false;
    final sk = SecretKeyService.instance;
    final curSecret =
        _sessionSecretKey == null ? null : sk.parse(_sessionSecretKey!);
    final nextSecretText = newSecretKey ?? _sessionSecretKey;
    final nextSecret = nextSecretText == null ? null : sk.parse(nextSecretText);

    // Verify current password.
    final curKey = await _crypto.deriveKey(
      password: currentPassword,
      salt: base64Decode(acc.kdfSalt),
      memoryKiB: acc.kdfMemory,
      iterations: acc.kdfIterations,
      parallelism: acc.kdfParallelism,
      secretKey: curSecret,
    );
    final verifier =
        SealedBox(acc.verifierNonce, acc.verifierCipher, acc.verifierMac);
    if (!await _crypto.checkVerifier(curKey, verifier)) return false;

    // New salt + key.
    final newSalt = _crypto.randomBytes(16);
    final newKey = await _crypto.deriveKey(
      password: newPassword,
      salt: newSalt,
      memoryKiB: CryptoService.kdfMemoryKiB,
      iterations: CryptoService.kdfIterations,
      parallelism: CryptoService.kdfParallelism,
      secretKey: nextSecret,
    );

    // Re-encrypt all payloads with the new key.
    final reFolders = <Map<String, Object?>>[];
    for (final f in folders) {
      final sealed = await _crypto.encryptJson(newKey, f.toSecretJson());
      reFolders.add({'id': f.id, 'payload': jsonEncode(sealed.toJson())});
    }
    final reEntries = <Map<String, Object?>>[];
    for (final e in entries) {
      final sealed = await _crypto.encryptJson(newKey, e.toSecretJson());
      reEntries.add({'id': e.id, 'payload': jsonEncode(sealed.toJson())});
    }
    final reNotes = <Map<String, Object?>>[];
    for (final n in notes) {
      final sealed = await _crypto.encryptJson(newKey, n.toSecretJson());
      reNotes.add({'id': n.id, 'payload': jsonEncode(sealed.toJson())});
    }
    await _db.replaceAllPayloads(
        folders: reFolders, entries: reEntries, notes: reNotes);

    // New verifier + persist account metadata.
    final newVerifier = await _crypto.createVerifier(newKey);
    final updated = acc.copyWith(
      kdfSalt: base64Encode(newSalt),
      verifierNonce: newVerifier.nonce,
      verifierCipher: newVerifier.cipher,
      verifierMac: newVerifier.mac,
      secretKeyRequired: nextSecret != null,
    );
    await _accounts.updateAccount(updated);
    _account = updated;
    _key = newKey;
    _sessionMasterPassword = newPassword;
    _sessionSecretKey = nextSecretText;
    if (nextSecretText != null) await sk.save(updated.id, nextSecretText);
    accountsList = await _accounts.listAccounts();

    // Keep the biometric-gated keystore in sync if this account opted in.
    if (await BiometricService.instance.hasStoredSecret(updated.id)) {
      await BiometricService.instance.storeSecret(updated.id, newPassword);
    }

    notifyListeners();
    return true;
  }

  // -------------------------------------------------------------- biometrics
  /// Enable biometric unlock for the current account by sealing the master
  /// password into the biometric-gated OS keystore. Requires an active session
  /// (so we have the plaintext). Returns true on success.
  Future<bool> enableBiometricForCurrentAccount() async {
    final acc = _account;
    final pw = _sessionMasterPassword;
    if (acc == null || pw == null) return false;
    final ok = await BiometricService.instance.authenticate(
        reason: 'Confirm your identity to enable biometric unlock');
    if (!ok) return false;
    await BiometricService.instance.storeSecret(acc.id, pw);
    notifyListeners();
    return true;
  }

  /// Disable biometric unlock for the current account (deletes the stored secret).
  Future<void> disableBiometricForCurrentAccount() async {
    final acc = _account;
    if (acc == null) return;
    await BiometricService.instance.deleteSecret(acc.id);
    notifyListeners();
  }

  /// Attempt a biometric unlock for [account]: prompt for biometrics, retrieve
  /// the stored master password, then unlock normally. Returns true on success.
  Future<bool> unlockWithBiometrics(LocalAccount account) async {
    final pw = await BiometricService.instance.retrieveSecret(
      account.id,
      reason: 'Unlock ${account.name}',
    );
    if (pw == null) return false;
    return unlock(account: account, masterPassword: pw);
  }

  // ---------------------------------------------------------------- settings
  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    await SettingsService.instance.save(s);
    _restartLockTimer();
    notifyListeners();
  }

  // ------------------------------------------------------- clipboard + lock
  /// Copy a value to the clipboard. If [sensitive] and auto-clear is enabled,
  /// schedule a wipe of the clipboard after the configured timeout.
  Future<void> copyToClipboard(String value, {bool sensitive = false}) async {
    _touch();
    await Clipboard.setData(ClipboardData(text: value));
    _clipboardTimer?.cancel();
    if (sensitive && settings.clipboardClearSeconds > 0) {
      _clipboardTimer = Timer(
        Duration(seconds: settings.clipboardClearSeconds),
        () async {
          final current = await Clipboard.getData(Clipboard.kTextPlain);
          // Only clear if our value is still on the clipboard.
          if (current?.text == value) {
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        },
      );
    }
  }

  int get clipboardClearSeconds => settings.clipboardClearSeconds;

  /// Call on any user interaction to reset the idle auto-lock countdown.
  void registerActivity() => _touch();

  void _touch() => _restartLockTimer();

  void _restartLockTimer() {
    _lockTimer?.cancel();
    // "Immediately" locks on background, not on an idle timer, so no timer is
    // armed for it. Otherwise arm the idle-timeout timer when a limit is set.
    if (_unlocked &&
        !settings.autoLockImmediate &&
        settings.autoLockMinutes > 0) {
      _lockTimer = Timer(
        Duration(minutes: settings.autoLockMinutes),
        () => lock(),
      );
    }
  }

  /// Called when the app leaves the foreground. With "Immediately" selected the
  /// vault locks at once (zero idle grace); otherwise the idle-timeout timer
  /// keeps running in the background and locks when it elapses.
  void onAppBackgrounded() {
    if (_unlocked && settings.autoLockImmediate) lock();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _clipboardTimer?.cancel();
    super.dispose();
  }
}
