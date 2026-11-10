/// A folder / category used to organise entries and notes.
///
/// The folder name is a secret too (it can reveal what the vault contains), so
/// it is encrypted. Only the [id] is stored in plaintext.
class VaultFolder {
  final String id;
  String name;
  final DateTime createdAt;

  VaultFolder({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toSecretJson() => {'name': name};

  factory VaultFolder.fromSecretJson(
    Map<String, dynamic> json, {
    required String id,
    required DateTime createdAt,
  }) {
    return VaultFolder(
      id: id,
      name: (json['name'] ?? '') as String,
      createdAt: createdAt,
    );
  }
}
