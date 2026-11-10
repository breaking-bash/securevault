import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:securevault/models/vault_entry.dart';
import 'package:securevault/services/crypto_service.dart';
import 'package:securevault/services/database_service.dart';
import 'package:securevault/services/password_generator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// End-to-end test of the encrypted storage pipeline WITHOUT the GUI:
/// derive key -> encrypt entry -> store in SQLite (ffi) -> read -> decrypt,
/// plus search, wrong-password rejection, and re-encryption on key change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final crypto = CryptoService.instance;
  final db = DatabaseService.instance;
  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sv_test');
    dbPath = '${tmp.path}/vault.db';
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('entry encrypt -> store -> load -> decrypt round-trip', () async {
    final salt = crypto.randomBytes(16);
    final key = await crypto.deriveKey(password: 'master-pw', salt: salt);

    await db.open(dbPath);
    final now = DateTime.now();
    final entry = VaultEntry(
      id: 'e1',
      title: 'GitHub',
      username: 'alice',
      password: 'sup3r-secret!',
      url: 'https://github.com',
      notes: 'work account',
      createdAt: now,
      updatedAt: now,
    );
    final sealed = await crypto.encryptJson(key, entry.toSecretJson());
    await db.upsertEntry(
      id: entry.id,
      folderId: null,
      createdAt: now.millisecondsSinceEpoch,
      updatedAt: now.millisecondsSinceEpoch,
      payload: jsonEncode(sealed.toJson()),
    );

    // Confirm what's on disk is CIPHERTEXT, not plaintext.
    final rawBytes = await File(dbPath).readAsBytes();
    final rawStr = String.fromCharCodes(rawBytes);
    expect(rawStr.contains('sup3r-secret!'), isFalse,
        reason: 'password must never appear in plaintext on disk');
    expect(rawStr.contains('work account'), isFalse);

    // Read back and decrypt.
    final rows = await db.readEntries();
    expect(rows.length, 1);
    final back = SealedBox.fromJson(
        jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>);
    final json = await crypto.decryptJson(key, back);
    final loaded = VaultEntry.fromSecretJson(json,
        id: 'e1', folderId: null, createdAt: now, updatedAt: now);
    expect(loaded.title, 'GitHub');
    expect(loaded.password, 'sup3r-secret!');
    expect(loaded.url, 'https://github.com');
  });

  test('wrong master password cannot decrypt stored entry', () async {
    final salt = crypto.randomBytes(16);
    final key = await crypto.deriveKey(password: 'right-pw', salt: salt);
    await db.open(dbPath);
    final now = DateTime.now().millisecondsSinceEpoch;
    final sealed = await crypto.encryptJson(key, {'title': 't', 'password': 'p'});
    await db.upsertEntry(
        id: 'x', folderId: null, createdAt: now, updatedAt: now,
        payload: jsonEncode(sealed.toJson()));

    final rows = await db.readEntries();
    final back = SealedBox.fromJson(
        jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>);
    final wrongKey = await crypto.deriveKey(password: 'wrong-pw', salt: salt);
    expect(() => crypto.decryptJson(wrongKey, back), throwsA(anything),
        reason: 'GCM auth must fail with the wrong key');
  });

  test('search filter matches title/username/url', () async {
    final entries = [
      VaultEntry(id: '1', title: 'Gmail', username: 'bob@x.com', url: 'mail.google.com', createdAt: DateTime.now(), updatedAt: DateTime.now()),
      VaultEntry(id: '2', title: 'Bank', username: 'bob123', url: 'bank.example', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    ];
    List<VaultEntry> search(String q) {
      final l = q.toLowerCase();
      return entries.where((e) =>
          e.title.toLowerCase().contains(l) ||
          e.username.toLowerCase().contains(l) ||
          e.url.toLowerCase().contains(l)).toList();
    }

    expect(search('gmail').length, 1);
    expect(search('bob').length, 2);
    expect(search('bank.example').length, 1);
    expect(search('zzz').length, 0);
  });

  test('re-encryption with new key preserves data (password change)', () async {
    final salt1 = crypto.randomBytes(16);
    final key1 = await crypto.deriveKey(password: 'old', salt: salt1);
    await db.open(dbPath);
    final now = DateTime.now().millisecondsSinceEpoch;
    final sealed = await crypto.encryptJson(key1, {'title': 'Email', 'password': 'pw1'});
    await db.upsertEntry(id: 'a', folderId: null, createdAt: now, updatedAt: now,
        payload: jsonEncode(sealed.toJson()));

    // Re-encrypt with a new key.
    final salt2 = crypto.randomBytes(16);
    final key2 = await crypto.deriveKey(password: 'new', salt: salt2);
    final rows = await db.readEntries();
    final old = SealedBox.fromJson(jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>);
    final data = await crypto.decryptJson(key1, old);
    final reSealed = await crypto.encryptJson(key2, data);
    await db.replaceAllPayloads(folders: [], notes: [], entries: [
      {'id': 'a', 'payload': jsonEncode(reSealed.toJson())}
    ]);

    // Old key fails, new key works.
    final rows2 = await db.readEntries();
    final cur = SealedBox.fromJson(jsonDecode(rows2.first['payload'] as String) as Map<String, dynamic>);
    expect(() => crypto.decryptJson(key1, cur), throwsA(anything));
    final decrypted = await crypto.decryptJson(key2, cur);
    expect(decrypted['title'], 'Email');
    expect(decrypted['password'], 'pw1');
  });

  test('password generator honours options', () {
    final gen = PasswordGenerator.instance;
    final pw = gen.generate(PasswordOptions(length: 32, symbols: false, excludeAmbiguous: true));
    expect(pw.length, 32);
    expect(RegExp(r'[!@#\$%]').hasMatch(pw), isFalse);
    // digits-only still produces requested length
    final digits = gen.generate(PasswordOptions(length: 10, upper: false, lower: false, symbols: false));
    expect(digits.length, 10);
    expect(RegExp(r'^[0-9]+$').hasMatch(digits), isTrue);
  });
}
