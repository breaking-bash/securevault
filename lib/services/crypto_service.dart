import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A sealed, self-describing encrypted blob: nonce + ciphertext + MAC, all
/// base64. This is what gets written to disk for every secret field.
class SealedBox {
  final String nonce;
  final String cipher;
  final String mac;

  const SealedBox(this.nonce, this.cipher, this.mac);

  Map<String, String> toJson() => {'n': nonce, 'c': cipher, 'm': mac};

  factory SealedBox.fromJson(Map<String, dynamic> j) =>
      SealedBox(j['n'] as String, j['c'] as String, j['m'] as String);
}

/// Zero-knowledge cryptography for SecureVault.
///
/// Security model:
///  * KDF: Argon2id (memory-hard) turns the master password + a per-account
///    random salt into a 256-bit master key. The password itself is never
///    stored; the key lives only in memory while the vault is unlocked.
///  * Cipher: AES-256-GCM (authenticated encryption) protects every secret
///    field. GCM's MAC means any tampering with the ciphertext is detected on
///    decrypt.
///  * Verifier: a fixed constant encrypted with the master key. On unlock we
///    decrypt it; success proves the entered password is correct WITHOUT having
///    to touch (or risk corrupting) the real vault data.
class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();

  final AesGcm _aes = AesGcm.with256bits();
  final Random _rng = Random.secure();

  // Argon2id parameters. Tuned to be memory-hard yet responsive for the
  // pure-Dart implementation that ships across all three target platforms.
  static const int kdfMemoryKiB = 19456; // 19 MiB
  static const int kdfIterations = 3;
  static const int kdfParallelism = 1; // pure-Dart Argon2id supports lanes == 1
  static const int keyLengthBytes = 32; // AES-256

  // The known-plaintext used to build & check the unlock verifier.
  static final List<int> _verifierPlaintext =
      utf8.encode('securevault.verifier.v1');

  /// Cryptographically-secure random bytes.
  Uint8List randomBytes(int length) {
    final b = Uint8List(length);
    for (var i = 0; i < length; i++) {
      b[i] = _rng.nextInt(256);
    }
    return b;
  }

  String randomBase64(int length) => base64Encode(randomBytes(length));

  /// Derive the 256-bit master key from the password + salt using Argon2id.
  Future<SecretKey> deriveKey({
    required String password,
    required List<int> salt,
    int memoryKiB = kdfMemoryKiB,
    int iterations = kdfIterations,
    int parallelism = kdfParallelism,
    List<int>? secretKey,
  }) async {
    final argon2 = Argon2id(
      memory: memoryKiB,
      parallelism: parallelism,
      iterations: iterations,
      hashLength: keyLengthBytes,
    );
    final base = await argon2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt, // Argon2 "nonce" == the salt
    );
    if (secretKey == null) return base;
    // Two-secret derivation: mix the account Secret Key into the Argon2 output.
    return Hkdf(hmac: Hmac.sha256(), outputLength: keyLengthBytes).deriveKey(
      secretKey: base,
      nonce: secretKey,
      info: utf8.encode('securevault.2skd.v1'),
    );
  }

  /// Encrypt arbitrary bytes with the master key, producing a [SealedBox].
  Future<SealedBox> encryptBytes(SecretKey key, List<int> data) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(data, secretKey: key, nonce: nonce);
    return SealedBox(
      base64Encode(box.nonce),
      base64Encode(box.cipherText),
      base64Encode(box.mac.bytes),
    );
  }

  /// Decrypt a [SealedBox] back into bytes. Throws if the key is wrong or the
  /// ciphertext was tampered with (GCM authentication failure).
  Future<Uint8List> decryptBytes(SecretKey key, SealedBox sealed) async {
    final box = SecretBox(
      base64Decode(sealed.cipher),
      nonce: base64Decode(sealed.nonce),
      mac: Mac(base64Decode(sealed.mac)),
    );
    final clear = await _aes.decrypt(box, secretKey: key);
    return Uint8List.fromList(clear);
  }

  /// Encrypt a UTF-8 string -> SealedBox.
  Future<SealedBox> encryptString(SecretKey key, String text) =>
      encryptBytes(key, utf8.encode(text));

  /// Decrypt a SealedBox -> UTF-8 string.
  Future<String> decryptString(SecretKey key, SealedBox sealed) async =>
      utf8.decode(await decryptBytes(key, sealed));

  /// Encrypt a JSON map -> SealedBox.
  Future<SealedBox> encryptJson(SecretKey key, Map<String, dynamic> map) =>
      encryptString(key, jsonEncode(map));

  /// Decrypt a SealedBox -> JSON map.
  Future<Map<String, dynamic>> decryptJson(
      SecretKey key, SealedBox sealed) async {
    final s = await decryptString(key, sealed);
    return jsonDecode(s) as Map<String, dynamic>;
  }

  /// Build the unlock verifier (encrypt the known constant with the key).
  Future<SealedBox> createVerifier(SecretKey key) =>
      encryptBytes(key, _verifierPlaintext);

  /// Return true iff [sealed] decrypts with [key] to the known constant.
  Future<bool> checkVerifier(SecretKey key, SealedBox sealed) async {
    try {
      final clear = await decryptBytes(key, sealed);
      if (clear.length != _verifierPlaintext.length) return false;
      var diff = 0;
      for (var i = 0; i < clear.length; i++) {
        diff |= clear[i] ^ _verifierPlaintext[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }
}
