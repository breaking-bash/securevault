import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// Thrown for any failure while linking devices.
class LinkException implements Exception {
  final String message;
  LinkException(this.message);
  @override
  String toString() => message;
}

/// An active receiver waiting for another device to send a vault.
class LinkReceiver {
  /// Text to render as a QR code.
  final String qrPayload;

  /// Completes with the decrypted payload (or an error if timed out/cancelled).
  final Future<Map<String, dynamic>> result;
  final Future<void> Function() cancel;
  LinkReceiver(this.qrPayload, this.result, this.cancel);
}

/// Serverless device linking over the local network.
///
/// The receiving device opens a one-shot HTTP listener and shows a QR code
/// containing its LAN addresses, an ephemeral X25519 public key and a random
/// token. The sending device scans it, derives a shared key (X25519 + HKDF
/// bound to the token) and POSTs its already-encrypted vault records wrapped in
/// AES-256-GCM. The master password never leaves either device.
class DeviceLinkService {
  DeviceLinkService._();
  static final DeviceLinkService instance = DeviceLinkService._();

  static const scheme = 'securevault-link:';
  static const _info = 'securevault-link-v1';
  static const _maxAttempts = 5;
  static const timeout = Duration(minutes: 3);

  final _x25519 = X25519();
  final _aes = AesGcm.with256bits();

  Future<SecretKey> _deriveKey(SecretKey shared, List<int> token) {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32)
        .deriveKey(secretKey: shared, nonce: token, info: utf8.encode(_info));
  }

  Future<List<String>> _localAddresses() async {
    final result = <String>[];
    for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false)) {
      for (final a in i.addresses) {
        result.add(a.address);
      }
    }
    return result;
  }

  Future<LinkReceiver> startReceiver() async {
    final addresses = await _localAddresses();
    if (addresses.isEmpty) {
      throw LinkException('No local network connection found.');
    }
    final keyPair = await _x25519.newKeyPair();
    final pub = (await keyPair.extractPublicKey()).bytes;
    final token = SecretKeyData.random(length: 16).bytes;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);

    final completer = Completer<Map<String, dynamic>>();
    var attempts = 0;
    Timer? timer;

    Future<void> shutdown() async {
      timer?.cancel();
      await server.close(force: true);
    }

    timer = Timer(timeout, () async {
      if (!completer.isCompleted) {
        completer.completeError(LinkException('Linking timed out.'));
      }
      await shutdown();
    });

    server.listen((req) async {
      try {
        if (req.method != 'POST' || req.uri.path != '/link') {
          req.response.statusCode = 404;
          return;
        }
        if (completer.isCompleted || attempts >= _maxAttempts) {
          req.response.statusCode = 410;
          return;
        }
        attempts++;
        final body = await utf8
            .decodeStream(req)
            .timeout(const Duration(seconds: 30));
        final j = jsonDecode(body) as Map<String, dynamic>;
        final shared = await _x25519.sharedSecretKey(
          keyPair: keyPair,
          remotePublicKey: SimplePublicKey(base64Decode(j['k'] as String),
              type: KeyPairType.x25519),
        );
        final key = await _deriveKey(shared, token);
        final plain = await _aes.decrypt(
          SecretBox(base64Decode(j['c'] as String),
              nonce: base64Decode(j['n'] as String),
              mac: Mac(base64Decode(j['m'] as String))),
          secretKey: key,
        );
        final data = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
        req.response.statusCode = 200;
        req.response.write('{"ok":true}');
        if (!completer.isCompleted) completer.complete(data);
      } catch (_) {
        req.response.statusCode = 403;
      } finally {
        await req.response.close();
        if (completer.isCompleted) await shutdown();
      }
    });

    final qr = jsonEncode({
      'h': addresses,
      'p': server.port,
      'k': base64Encode(pub),
      't': base64Encode(token),
    });
    return LinkReceiver('$scheme$qr', completer.future, () async {
      if (!completer.isCompleted) {
        completer.completeError(LinkException('Linking cancelled.'));
      }
      await shutdown();
    });
  }

  /// Sends [data] to the receiver described by a scanned [qrPayload].
  Future<void> send(String qrPayload, Map<String, dynamic> data) async {
    if (!qrPayload.startsWith(scheme)) {
      throw LinkException('Not a SecureVault link code.');
    }
    final Map<String, dynamic> info;
    try {
      info = jsonDecode(qrPayload.substring(scheme.length))
          as Map<String, dynamic>;
    } catch (_) {
      throw LinkException('Invalid link code.');
    }
    final hosts = (info['h'] as List).cast<String>();
    final port = info['p'] as int;
    final token = base64Decode(info['t'] as String);

    final mine = await _x25519.newKeyPair();
    final shared = await _x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(base64Decode(info['k'] as String),
          type: KeyPairType.x25519),
    );
    final key = await _deriveKey(shared, token);
    final box = await _aes.encrypt(utf8.encode(jsonEncode(data)),
        secretKey: key);
    final body = jsonEncode({
      'k': base64Encode((await mine.extractPublicKey()).bytes),
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });

    Object? lastError;
    for (final host in hosts) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      try {
        final req = await client.postUrl(Uri.parse('http://$host:$port/link'));
        req.headers.contentType = ContentType.json;
        req.write(body);
        final res = await req.close();
        await res.drain<void>();
        if (res.statusCode == 200) return;
        lastError = 'Receiver rejected the transfer (${res.statusCode}).';
      } catch (e) {
        lastError = e;
      } finally {
        client.close(force: true);
      }
    }
    throw LinkException(
        'Could not reach the other device. Make sure both are on the same '
        'network. ($lastError)');
  }
}
