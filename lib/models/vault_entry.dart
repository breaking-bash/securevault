/// Kinds of items a [VaultEntry] can represent.
enum EntryType { login, card, ssh, passkey }

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

/// A login, credit card or SSH key stored in the vault.
///
/// Secret-bearing fields (username, password, url, notes, totp, [extra]) are serialized
/// into a single JSON payload that is encrypted as one blob before it ever
/// touches disk. Only [id], [folderId], [title], [createdAt] and [updatedAt]
/// are stored in plaintext columns so the list can be rendered and searched by
/// title without decrypting every record one-by-one (title search still works
/// because the title lives in a column; deep search decrypts in memory).
class VaultEntry {
  final String id;
  EntryType type;
  Map<String, String> extra;
  String title;
  String username;
  String password;
  String url;
  String notes;
  String? totp;
  String? folderId;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Short secondary line shown under the title in lists.
  String get subtitle {
    switch (type) {
      case EntryType.login:
        return username;
      case EntryType.card:
        final n = (extra[EntryFields.cardNumber] ?? '').replaceAll(' ', '');
        return n.length >= 4 ? '•••• ${n.substring(n.length - 4)}' : '';
      case EntryType.ssh:
        return extra[EntryFields.fingerprint] ?? '';
      case EntryType.passkey:
        return extra[EntryFields.passkeyUser] ?? extra[EntryFields.rpId] ?? '';
    }
  }

  VaultEntry({
    required this.id,
    required this.title,
    this.type = EntryType.login,
    Map<String, String>? extra,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.totp,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
  }) : extra = extra ?? {};

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
      username: (json['username'] ?? '') as String,
      password: (json['password'] ?? '') as String,
      url: (json['url'] ?? '') as String,
      notes: (json['notes'] ?? '') as String,
      totp: json['totp'] as String?,
      folderId: folderId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
