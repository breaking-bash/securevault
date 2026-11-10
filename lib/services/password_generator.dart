import 'dart:math';

class PasswordOptions {
  int length;
  bool upper;
  bool lower;
  bool digits;
  bool symbols;
  bool excludeAmbiguous;

  PasswordOptions({
    this.length = 20,
    this.upper = true,
    this.lower = true,
    this.digits = true,
    this.symbols = true,
    this.excludeAmbiguous = true,
  });
}

/// Cryptographically-secure, configurable password generator.
class PasswordGenerator {
  PasswordGenerator._();
  static final PasswordGenerator instance = PasswordGenerator._();

  final Random _rng = Random.secure();

  static const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const _digits = '0123456789';
  static const _symbols = r'!@#$%^&*()-_=+[]{};:,.?/';
  // Characters that are easy to confuse with each other.
  static const _ambiguous = 'O0oIl1|S5B8Z2';

  String generate(PasswordOptions o) {
    final pools = <String>[];
    if (o.upper) pools.add(_filter(_upper, o.excludeAmbiguous));
    if (o.lower) pools.add(_filter(_lower, o.excludeAmbiguous));
    if (o.digits) pools.add(_filter(_digits, o.excludeAmbiguous));
    if (o.symbols) pools.add(_filter(_symbols, o.excludeAmbiguous));

    // Fall back to lowercase if the user disabled everything.
    if (pools.isEmpty) pools.add(_lower);

    final length = o.length.clamp(4, 128);
    final chars = <String>[];

    // Guarantee at least one character from each selected pool.
    for (final pool in pools) {
      if (pool.isNotEmpty) chars.add(pool[_rng.nextInt(pool.length)]);
    }

    final combined = pools.join();
    while (chars.length < length) {
      chars.add(combined[_rng.nextInt(combined.length)]);
    }

    // Fisher-Yates shuffle so the guaranteed chars aren't all at the front.
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }
    return chars.join();
  }

  String _filter(String pool, bool excludeAmbiguous) {
    if (!excludeAmbiguous) return pool;
    return pool.split('').where((c) => !_ambiguous.contains(c)).join();
  }

  /// Rough strength score 0..4 based on length and character variety.
  int strength(String password) {
    if (password.isEmpty) return 0;
    var variety = 0;
    if (RegExp(r'[A-Z]').hasMatch(password)) variety++;
    if (RegExp(r'[a-z]').hasMatch(password)) variety++;
    if (RegExp(r'[0-9]').hasMatch(password)) variety++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) variety++;

    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.length >= 16) score++;
    if (variety >= 3) score++;
    return score.clamp(0, 4);
  }
}
