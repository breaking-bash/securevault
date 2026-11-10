import 'package:otp/otp.dart';

/// Parsed configuration of a TOTP (time-based one-time password) authenticator.
class TotpConfig {
  final String secret; // base32, no spaces, upper-case
  final int digits;
  final int period; // seconds
  final String? issuer;
  final String? account;

  const TotpConfig({
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.issuer,
    this.account,
  });
}

/// Pure-Dart helpers to parse `otpauth://` URIs and generate RFC 6238 TOTP codes.
///
/// Used by the QR scanner (to populate the TOTP secret from a scanned code) and
/// by the entry detail screen (to show a live code + countdown). No platform
/// plugins are required here, so this is fully unit-testable.
class TotpService {
  /// Normalize a raw base32 secret: strip spaces/padding and upper-case it.
  static String normalizeSecret(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').replaceAll('=', '').toUpperCase();

  /// Returns true if [value] looks like a valid (non-empty) base32 secret.
  static bool isValidSecret(String value) {
    final s = normalizeSecret(value);
    if (s.isEmpty) return false;
    return RegExp(r'^[A-Z2-7]+$').hasMatch(s);
  }

  /// Parse an `otpauth://totp/LABEL?secret=...&issuer=...&digits=...&period=...`
  /// URI. Returns null if it is not a valid TOTP otpauth URI.
  static TotpConfig? parseUri(String input) {
    final raw = input.trim();
    Uri uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {
      return null;
    }
    if (uri.scheme.toLowerCase() != 'otpauth') return null;
    if (uri.host.toLowerCase() != 'totp') return null;

    final params = uri.queryParameters;
    final secretRaw = params['secret'];
    if (secretRaw == null) return null;
    final secret = normalizeSecret(secretRaw);
    if (!isValidSecret(secret)) return null;

    // Label is "Issuer:Account" or just "Account" (path after the leading '/').
    String? label = uri.path.isNotEmpty ? uri.path.substring(1) : null;
    if (label != null) label = Uri.decodeComponent(label);
    String? issuer = params['issuer'];
    String? account = label;
    if (label != null && label.contains(':')) {
      final parts = label.split(':');
      issuer ??= parts.first.trim();
      account = parts.sublist(1).join(':').trim();
    }

    final digits = int.tryParse(params['digits'] ?? '') ?? 6;
    final period = int.tryParse(params['period'] ?? '') ?? 30;

    return TotpConfig(
      secret: secret,
      digits: digits <= 0 ? 6 : digits,
      period: period <= 0 ? 30 : period,
      issuer: issuer,
      account: account,
    );
  }

  /// Build a [TotpConfig] from a stored TOTP field value, which may be either a
  /// full `otpauth://` URI or a bare base32 secret.
  static TotpConfig? fromStored(String stored) {
    final value = stored.trim();
    if (value.isEmpty) return null;
    if (value.toLowerCase().startsWith('otpauth://')) {
      return parseUri(value);
    }
    final secret = normalizeSecret(value);
    if (!isValidSecret(secret)) return null;
    return TotpConfig(secret: secret);
  }

  /// Generate the current RFC 6238 TOTP code for [config].
  /// [atMillis] overrides "now" (used for deterministic tests).
  static String generate(TotpConfig config, {int? atMillis}) {
    final time = atMillis ?? DateTime.now().millisecondsSinceEpoch;
    return OTP.generateTOTPCodeString(
      config.secret,
      time,
      length: config.digits,
      interval: config.period,
      algorithm: Algorithm.SHA1, // RFC 6238 / Google Authenticator default
      isGoogle: true,
    );
  }

  /// Seconds remaining in the current time-step window for [period].
  static int secondsRemaining(int period, {int? atMillis}) {
    final nowSec = (atMillis ?? DateTime.now().millisecondsSinceEpoch) ~/ 1000;
    return period - (nowSec % period);
  }
}
