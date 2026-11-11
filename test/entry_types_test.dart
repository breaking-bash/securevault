import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:securevault/models/vault_entry.dart';
import 'package:securevault/services/ssh_key_service.dart';

void main() {
  test('card entry round-trips through secret JSON', () {
    final now = DateTime.now();
    final e = VaultEntry(
      id: '1',
      title: 'Visa',
      type: EntryType.card,
      extra: {EntryFields.cardNumber: '4111 1111 1111 1234'},
      createdAt: now,
      updatedAt: now,
    );
    final back = VaultEntry.fromSecretJson(
      jsonDecode(jsonEncode(e.toSecretJson())) as Map<String, dynamic>,
      id: '1',
      folderId: null,
      createdAt: now,
      updatedAt: now,
    );
    expect(back.type, EntryType.card);
    expect(back.subtitle, '•••• 1234');
  });

  test('legacy payload without type loads as login', () {
    final now = DateTime.now();
    final e = VaultEntry.fromSecretJson({'title': 'x'},
        id: '1', folderId: null, createdAt: now, updatedAt: now);
    expect(e.type, EntryType.login);
    expect(e.extra, isEmpty);
  });

  test('generates OpenSSH ed25519 key', () async {
    final k = await SshKeyService.instance.generateEd25519(comment: 'me');
    expect(k.publicKey, startsWith('ssh-ed25519 '));
    expect(k.privateKey, contains('BEGIN OPENSSH PRIVATE KEY'));
    expect(k.fingerprint, startsWith('SHA256:'));
  });
}
