import 'package:flutter_test/flutter_test.dart';
import 'package:securevault/services/totp_service.dart';

void main() {
  group('otpauth:// URI parsing', () {
    test('parses a full otpauth URI with issuer/account/digits/period', () {
      final cfg = TotpService.parseUri(
          'otpauth://totp/GitHub:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30');
      expect(cfg, isNotNull);
      expect(cfg!.secret, 'JBSWY3DPEHPK3PXP');
      expect(cfg.issuer, 'GitHub');
      expect(cfg.account, 'alice@example.com');
      expect(cfg.digits, 6);
      expect(cfg.period, 30);
    });

    test('derives issuer from a "Issuer:Account" label', () {
      final cfg =
          TotpService.parseUri('otpauth://totp/ACME:bob?secret=JBSWY3DPEHPK3PXP');
      expect(cfg, isNotNull);
      expect(cfg!.issuer, 'ACME');
      expect(cfg.account, 'bob');
    });

    test('normalizes secrets with spaces and lower case', () {
      final cfg = TotpService.parseUri(
          'otpauth://totp/Test?secret=jbsw y3dp ehpk 3pxp');
      expect(cfg, isNotNull);
      expect(cfg!.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('defaults digits/period when absent', () {
      final cfg =
          TotpService.parseUri('otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP');
      expect(cfg, isNotNull);
      expect(cfg!.digits, 6);
      expect(cfg.period, 30);
    });

    test('rejects non-otpauth / non-totp / missing-secret URIs', () {
      expect(TotpService.parseUri('https://example.com'), isNull);
      expect(TotpService.parseUri('otpauth://hotp/Test?secret=ABC234'), isNull);
      expect(TotpService.parseUri('otpauth://totp/Test?issuer=X'), isNull);
      expect(TotpService.parseUri('not a uri at all'), isNull);
    });

    test('rejects an invalid base32 secret', () {
      expect(
          TotpService.parseUri('otpauth://totp/Test?secret=0189!@#'), isNull);
    });
  });

  group('fromStored', () {
    test('accepts a bare base32 secret', () {
      final cfg = TotpService.fromStored('JBSWY3DPEHPK3PXP');
      expect(cfg, isNotNull);
      expect(cfg!.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('accepts a full otpauth URI', () {
      final cfg =
          TotpService.fromStored('otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP');
      expect(cfg, isNotNull);
      expect(cfg!.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('returns null for empty / invalid', () {
      expect(TotpService.fromStored(''), isNull);
      expect(TotpService.fromStored('!!!'), isNull);
    });
  });

  group('RFC 6238 TOTP vectors (SHA1, base32 of "12345678901234567890")', () {
    // Official RFC 6238 Appendix B test values for the SHA1 variant.
    const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

    String code8(int unixSeconds) => TotpService.generate(
          const TotpConfig(secret: secret, digits: 8),
          atMillis: unixSeconds * 1000,
        );

    test('8-digit codes match the RFC vectors', () {
      expect(code8(59), '94287082');
      expect(code8(1111111109), '07081804');
      expect(code8(1234567890), '89005924');
      expect(code8(2000000000), '69279037');
    });

    test('6-digit code is the low 6 digits of the 8-digit code', () {
      final c6 = TotpService.generate(const TotpConfig(secret: secret),
          atMillis: 59 * 1000);
      expect(c6, '287082');
    });
  });

  group('secondsRemaining', () {
    test('counts down within the 30s window', () {
      // At unix second 0 the window has just started -> full period remains.
      expect(TotpService.secondsRemaining(30, atMillis: 0), 30);
      expect(TotpService.secondsRemaining(30, atMillis: 1 * 1000), 29);
      expect(TotpService.secondsRemaining(30, atMillis: 29 * 1000), 1);
      expect(TotpService.secondsRemaining(30, atMillis: 30 * 1000), 30);
    });
  });
}
