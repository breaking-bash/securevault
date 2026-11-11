import 'dart:convert';
import 'dart:typed_data';

import 'item_templates.dart';

/// Kinds of items a [VaultEntry] can represent.
enum EntryType {
  login,
  card,
  ssh,
  passkey,
  identity,
  bank,
  wifi,
  server,
  database,
  api,
  license,
  driver,
  passport,
  email,
  password,
  document,
  crypto,
  medical,
  membership,
  reward,
  ssn,
}

/// Keys used in [VaultEntry.extra] for non-login item types.
class EntryFields {
  static const cardholder = 'cardholder';
  static const cardNumber = 'cardNumber';
  static const expiry = 'expiry';
  static const cvv = 'cvv';
  static const pin = 'pin';
  static const publicKey = 'publicKey';
  static const privateKey = 'privateKey';
  static const fingerprint = 'fingerprint';
  static const passphrase = 'passphrase';
  static const rpId = 'rpId';
  static const passkeyUser = 'passkeyUser';
  static const credentialId = 'credentialId';
}

/// A user-defined extra field on any item (text, URL, email, date, OTP…).
class CustomField {
  String label;
  FieldKind kind;
  String value;
  CustomField({required this.label, required this.kind, this.value = ''});

  Map<String, dynamic> toJson() =>
      {'l': label, 'k': kind.name, 'v': value};

  factory CustomField.fromJson(Map<String, dynamic> j) => CustomField(
        label: (j['l'] ?? '') as String,
        kind: FieldKind.values.firstWhere((k) => k.name == j['k'],
            orElse: () => FieldKind.text),
        value: (j['v'] ?? '') as String,
      );
}

/// A file attached to an item. The bytes live inside the encrypted payload.
class Attachment {
  static const maxBytes = 5 * 1024 * 1024;

  final String id;
  final String name;
  final String data; // base64
  Attachment({required this.id, required this.name, required this.data});

  Uint8List get bytes => base64Decode(data);
  int get size => (data.length * 3 ~/ 4);

  Map<String, dynamic> toJson() => {'id': id, 'n': name, 'd': data};

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: (j['id'] ?? '') as String,
        name: (j['n'] ?? 'file') as String,
        data: (j['d'] ?? '') as String,
      );
}

/// A vault item (login, card, identity, …).
///
/// Secret-bearing fields (username, password, url, notes, totp, [extra],
/// [customFields], [tags], [attachments]) are serialized into a single JSON
/// payload that is encrypted as one blob before it ever touches disk. Only
/// [id], [folderId], [title], [createdAt] and [updatedAt] are stored in
/// plaintext columns so the list can be rendered and searched by title without
/// decrypting every record one-by-one.
class VaultEntry {
  final String id;
  EntryType type;
  Map<String, String> extra;
  List<CustomField> customFields;
  List<String> tags;
  List<Attachment> attachments;
  String title;
  String username;
  String password;
  String url;
  String notes;
  String? totp;
  String? folderId;
  bool archived;
  DateTime? deletedAt;
  final DateTime createdAt;
  DateTime updatedAt;

  bool get isTrashed => deletedAt != null;
  bool get isActive => !archived && deletedAt == null;

  /// Short secondary line shown under the title in lists.
  String get subtitle {
    if (type == EntryType.login) return username;
    final t = ItemTemplates.of(type);
    for (final k in t.subtitleKeys) {
      final v = extra[k] ?? '';
      if (v.isEmpty) continue;
      if (k == EntryFields.cardNumber) {
        final n = v.replaceAll(' ', '');
        return n.length >= 4 ? '•••• ${n.substring(n.length - 4)}' : '';
      }
      return v;
    }
    return '';
  }

  VaultEntry({
    required this.id,
    required this.title,
    this.type = EntryType.login,
    Map<String, String>? extra,
    List<CustomField>? customFields,
    List<String>? tags,
    List<Attachment>? attachments,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.totp,
    this.folderId,
    this.archived = false,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  })  : extra = extra ?? {},
        customFields = customFields ?? [],
        tags = tags ?? [],
        attachments = attachments ?? [];

  /// The secret payload that gets encrypted. Title is included too so that a
  /// tampered plaintext title can be detected on decrypt.
  Map<String, dynamic> toSecretJson() => {
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'totp': totp,
        'type': type.name,
        'extra': extra,
        'fields': customFields.map((f) => f.toJson()).toList(),
        'tags': tags,
        'files': attachments.map((a) => a.toJson()).toList(),
        'archived': archived,
        'deletedAt': deletedAt?.millisecondsSinceEpoch,
      };

  factory VaultEntry.fromSecretJson(
    Map<String, dynamic> json, {
    required String id,
    required String? folderId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return VaultEntry(
      id: id,
      title: (json['title'] ?? '') as String,
      type: EntryType.values.firstWhere((t) => t.name == json['type'],
          orElse: () => EntryType.login),
      extra: ((json['extra'] ?? const {}) as Map)
          .map((k, v) => MapEntry(k as String, (v ?? '') as String)),
      customFields: ((json['fields'] ?? const []) as List)
          .map((e) => CustomField.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      tags: ((json['tags'] ?? const []) as List).cast<String>().toList(),
      attachments: ((json['files'] ?? const []) as List)
          .map((e) => Attachment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      username: (json['username'] ?? '') as String,
      password: (json['password'] ?? '') as String,
      url: (json['url'] ?? '') as String,
      notes: (json['notes'] ?? '') as String,
      totp: json['totp'] as String?,
      folderId: folderId,
      archived: (json['archived'] ?? false) as bool,
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['deletedAt'] as int),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}