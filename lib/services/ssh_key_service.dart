import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class GeneratedSshKey {
  final String publicKey;
  final String privateKey;
  final String fingerprint;
  const GeneratedSshKey(this.publicKey, this.privateKey, this.fingerprint);
}

/// Generates Ed25519 SSH keys in standard OpenSSH formats.
class SshKeyService {
  SshKeyService._();
  static final SshKeyService instance = SshKeyService._();

  Future<GeneratedSshKey> generateEd25519({String comment = ''}) async {
    final algo = Ed25519();
    final pair = await algo.newKeyPair();
    final seed = Uint8List.fromList(await pair.extractPrivateKeyBytes());
    final pub = Uint8List.fromList((await pair.extractPublicKey()).bytes);

    final pubBlob = BytesBuilder()
      ..add(_str(utf8.encode('ssh-ed25519')))
      ..add(_str(pub));
    final blob = pubBlob.toBytes();

    final check = Random.secure().nextInt(1 << 32);
    final priv = BytesBuilder()
      ..add(_u32(check))
      ..add(_u32(check))
      ..add(_str(utf8.encode('ssh-ed25519')))
      ..add(_str(pub))
      ..add(_str([...seed, ...pub]))
      ..add(_str(utf8.encode(comment)));
    var pad = 1;
    while (priv.length % 8 != 0) {
      priv.addByte(pad++);
    }

    final out = BytesBuilder()
      ..add(utf8.encode('openssh-key-v1'))
      ..addByte(0)
      ..add(_str(utf8.encode('none')))
      ..add(_str(utf8.encode('none')))
      ..add(_str(const []))
      ..add(_u32(1))
      ..add(_str(blob))
      ..add(_str(priv.toBytes()));

    final b64 = base64Encode(out.toBytes());
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 70) {
      lines.add(b64.substring(i, min(i + 70, b64.length)));
    }
    final privateKey = '-----BEGIN OPENSSH PRIVATE KEY-----\n'
        '${lines.join('\n')}\n'
        '-----END OPENSSH PRIVATE KEY-----\n';
    final publicKey =
        'ssh-ed25519 ${base64Encode(blob)}${comment.isEmpty ? '' : ' $comment'}';
    return GeneratedSshKey(
        publicKey, privateKey, await fingerprintOf(publicKey));
  }

  /// SHA256 fingerprint of an OpenSSH public key line, or '' if unparsable.
  Future<String> fingerprintOf(String publicKeyLine) async {
    final parts = publicKeyLine.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return '';
    try {
      final hash = await Sha256().hash(base64Decode(parts[1]));
      return 'SHA256:${base64Encode(hash.bytes).replaceAll('=', '')}';
    } catch (_) {
      return '';
    }
  }

  List<int> _u32(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  List<int> _str(List<int> data) => [..._u32(data.length), ...data];
}
