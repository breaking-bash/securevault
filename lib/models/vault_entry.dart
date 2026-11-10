/// A login / credential entry stored in the vault.
///
/// Secret-bearing fields (username, password, url, notes, totp) are serialized
/// into a single JSON payload that is encrypted as one blob before it ever
/// touches disk. Only [id], [folderId], [title], [createdAt] and [updatedAt]
/// are stored in plaintext columns so the list can be rendered and searched by
/// title without decrypting every record one-by-one (title search still works
/// because the title lives in a column; deep search decrypts in memory).
class VaultEntry {
  final String id;
  String title;
  String username;
  String password;
  String url;
  String notes;
  String? totp;
  String? folderId;
  final DateTime createdAt;
  DateTime updatedAt;

  VaultEntry({
    required this.id,
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.totp,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// The secret payload that gets encrypted. Title is included too so that a
  /// tampered plaintext title can be detected on decrypt.
  Map<String, dynamic> toSecretJson() => {
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'totp': totp,
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
