/// A free-form encrypted secure note.
///
/// The [title] and [body] are both secret and are encrypted together into one
/// blob. Only [id], [createdAt] and [updatedAt] live in plaintext columns.
class SecureNote {
  final String id;
  String title;
  String body;
  String? folderId;
  final DateTime createdAt;
  DateTime updatedAt;

  SecureNote({
    required this.id,
    required this.title,
    this.body = '',
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toSecretJson() => {
        'title': title,
        'body': body,
      };

  factory SecureNote.fromSecretJson(
    Map<String, dynamic> json, {
    required String id,
    required String? folderId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return SecureNote(
      id: id,
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      folderId: folderId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
