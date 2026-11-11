/// A local account / profile on this device.
///
/// Each account owns its own encrypted SQLite vault file and its own master
/// password. The account metadata below is NON-SECRET bookkeeping used to show
/// the account picker and to derive + verify the master key. It deliberately
/// contains NO plaintext secrets and NO password — only the KDF salt, the KDF
/// parameters, and an encrypted "verifier" blob used to check the master
/// password without decrypting the whole vault.
class LocalAccount {
  /// Stable identifier (also used as the vault DB file name).
  final String id;

  /// Human-friendly display name shown in the account picker.
  String name;

  /// Base64 random salt fed into Argon2id.
  final String kdfSalt;

  /// Argon2id parameters (recorded so future param upgrades stay compatible).
  final int kdfMemory; // in KiB
  final int kdfIterations;
  final int kdfParallelism;

  /// Base64 nonce + ciphertext of a known constant, used to verify the master
  /// password on unlock. If it decrypts & matches, the password is correct.
  final String verifierNonce;
  final String verifierCipher;
  final String verifierMac;

  final DateTime createdAt;

  /// True when the key is derived from the master password AND a Secret Key.
  final bool secretKeyRequired;

  LocalAccount({
    required this.id,
    required this.name,
    required this.kdfSalt,
    required this.kdfMemory,
    required this.kdfIterations,
    required this.kdfParallelism,
    required this.verifierNonce,
    required this.verifierCipher,
    required this.verifierMac,
    required this.createdAt,
    this.secretKeyRequired = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kdfSalt': kdfSalt,
        'kdfMemory': kdfMemory,
        'kdfIterations': kdfIterations,
        'kdfParallelism': kdfParallelism,
        'verifierNonce': verifierNonce,
        'verifierCipher': verifierCipher,
        'verifierMac': verifierMac,
        'createdAt': createdAt.toIso8601String(),
        'secretKeyRequired': secretKeyRequired,
      };

  factory LocalAccount.fromJson(Map<String, dynamic> json) => LocalAccount(
        id: json['id'] as String,
        name: json['name'] as String,
        kdfSalt: json['kdfSalt'] as String,
        kdfMemory: json['kdfMemory'] as int,
        kdfIterations: json['kdfIterations'] as int,
        kdfParallelism: json['kdfParallelism'] as int,
        verifierNonce: json['verifierNonce'] as String,
        verifierCipher: json['verifierCipher'] as String,
        verifierMac: json['verifierMac'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        secretKeyRequired: (json['secretKeyRequired'] ?? false) as bool,
      );

  LocalAccount copyWith({
    String? name,
    String? kdfSalt,
    String? verifierNonce,
    String? verifierCipher,
    String? verifierMac,
    bool? secretKeyRequired,
  }) =>
      LocalAccount(
        id: id,
        name: name ?? this.name,
        kdfSalt: kdfSalt ?? this.kdfSalt,
        kdfMemory: kdfMemory,
        kdfIterations: kdfIterations,
        kdfParallelism: kdfParallelism,
        verifierNonce: verifierNonce ?? this.verifierNonce,
        verifierCipher: verifierCipher ?? this.verifierCipher,
        verifierMac: verifierMac ?? this.verifierMac,
        createdAt: createdAt,
        secretKeyRequired: secretKeyRequired ?? this.secretKeyRequired,
      );
}
