import 'package:flutter_test/flutter_test.dart';
import 'package:securevault/services/crypto_service.dart';

void main() {
  final c = CryptoService.instance;

  test('derive key, encrypt/decrypt round-trip', () async {
    final salt = c.randomBytes(16);
    final sw = Stopwatch()..start();
    final key = await c.deriveKey(password: 'correct horse battery', salt: salt);
    sw.stop();
    // ignore: avoid_print
    print('Argon2id derive took ${sw.elapsedMilliseconds} ms');

    final sealed = await c.encryptString(key, 'hello secret world');
    final back = await c.decryptString(key, sealed);
    expect(back, 'hello secret world');
  });

  test('verifier accepts right password, rejects wrong', () async {
    final salt = c.randomBytes(16);
    final key = await c.deriveKey(password: 'master-pass-1', salt: salt);
    final verifier = await c.createVerifier(key);
    expect(await c.checkVerifier(key, verifier), isTrue);

    final wrong = await c.deriveKey(password: 'master-pass-2', salt: salt);
    expect(await c.checkVerifier(wrong, verifier), isFalse);
  });

  test('json round-trip', () async {
    final salt = c.randomBytes(16);
    final key = await c.deriveKey(password: 'pw', salt: salt);
    final sealed = await c.encryptJson(key, {'a': 1, 'b': 'x', 'c': null});
    final m = await c.decryptJson(key, sealed);
    expect(m['a'], 1);
    expect(m['b'], 'x');
    expect(m['c'], isNull);
  });
}
