import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../models/vault_entry.dart';
import 'password_generator.dart';

enum WatchtowerIssue { weak, reused, insecureUrl, missing2fa, old }

class WatchtowerFinding {
  final VaultEntry entry;
  final WatchtowerIssue issue;
  final String detail;
  const WatchtowerFinding(this.entry, this.issue, this.detail);
}

/// Offline vault health analysis. Breach checking is separate and opt-in
/// because it contacts the network.
class WatchtowerService {
  WatchtowerService._();
  static final WatchtowerService instance = WatchtowerService._();

  static const oldAfter = Duration(days: 365);

  /// Domains known to support TOTP; used to nudge users to enable 2FA.
  static const _twoFactorHosts = [
    'google.com',
    'github.com',
    'microsoft.com',
    'live.com',
    'amazon.com',
    'facebook.com',
    'twitter.com',
    'x.com',
    'dropbox.com',
    'apple.com',
    'paypal.com',
    'linkedin.com',
    'instagram.com',
    'reddit.com',
    'discord.com',
  ];

  List<WatchtowerFinding> analyze(List<VaultEntry> entries, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final logins = entries.where((e) => e.type == EntryType.login).toList();
    final findings = <WatchtowerFinding>[];

    final byPassword = <String, List<VaultEntry>>{};
    for (final e in logins) {
      if (e.password.isNotEmpty) {
        byPassword.putIfAbsent(e.password, () => []).add(e);
      }
    }

    for (final e in logins) {
      if (e.password.isNotEmpty &&
          PasswordGenerator.instance.strength(e.password) <= 1) {
        findings.add(
            WatchtowerFinding(e, WatchtowerIssue.weak, 'Weak password'));
      }
      final same = byPassword[e.password];
      if (e.password.isNotEmpty && same != null && same.length > 1) {
        findings.add(WatchtowerFinding(e, WatchtowerIssue.reused,
            'Password reused on ${same.length} items'));
      }
      if (e.url.toLowerCase().startsWith('http://')) {
        findings.add(WatchtowerFinding(
            e, WatchtowerIssue.insecureUrl, 'Site uses unencrypted HTTP'));
      }
      if ((e.totp ?? '').isEmpty && _supports2fa(e.url)) {
        findings.add(WatchtowerFinding(e, WatchtowerIssue.missing2fa,
            'Two-factor authentication available'));
      }
      if (e.password.isNotEmpty && clock.difference(e.updatedAt) > oldAfter) {
        findings.add(WatchtowerFinding(
            e, WatchtowerIssue.old, 'Password not changed in over a year'));
      }
    }
    return findings;
  }

  bool _supports2fa(String url) {
    final host = Uri.tryParse(url.contains('://') ? url : 'https://$url')
        ?.host
        .toLowerCase();
    if (host == null || host.isEmpty) return false;
    return _twoFactorHosts.any((d) => host == d || host.endsWith('.$d'));
  }

  /// Checks passwords against Have I Been Pwned using k-anonymity: only the
  /// first 5 hex chars of each SHA-1 are sent. Returns entry id -> breach count.
  Future<Map<String, int>> checkBreaches(List<VaultEntry> entries) async {
    final result = <String, int>{};
    final cache = <String, Map<String, int>>{};
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      for (final e in entries) {
        if (e.type != EntryType.login || e.password.isEmpty) continue;
        final hash = (await Sha1().hash(utf8.encode(e.password)))
            .bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase();
        final prefix = hash.substring(0, 5);
        final suffix = hash.substring(5);
        final range =
            cache[prefix] ??= await _fetchRange(client, prefix);
        final count = range[suffix] ?? 0;
        if (count > 0) result[e.id] = count;
      }
    } finally {
      client.close();
    }
    return result;
  }

  Future<Map<String, int>> _fetchRange(HttpClient client, String prefix) async {
    final req = await client
        .getUrl(Uri.parse('https://api.pwnedpasswords.com/range/$prefix'));
    req.headers.set('Add-Padding', 'true');
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('Breach service returned ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    final map = <String, int>{};
    for (final line in const LineSplitter().convert(body)) {
      final parts = line.trim().split(':');
      if (parts.length == 2) {
        final n = int.tryParse(parts[1]) ?? 0;
        if (n > 0) map[parts[0]] = n;
      }
    }
    return map;
  }
}
