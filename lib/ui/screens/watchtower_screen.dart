import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/watchtower_service.dart';
import '../../state/vault_state.dart';
import 'entry_detail_screen.dart';

/// Vault health dashboard (weak, reused, insecure, 2FA, old, breached).
class WatchtowerScreen extends StatefulWidget {
  const WatchtowerScreen({super.key});

  @override
  State<WatchtowerScreen> createState() => _WatchtowerScreenState();
}

class _WatchtowerScreenState extends State<WatchtowerScreen> {
  Map<String, int>? _breaches;
  bool _checking = false;
  String? _error;

  Future<void> _checkBreaches() async {
    final state = context.read<VaultState>();
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final r = await WatchtowerService.instance.checkBreaches(state.entries);
      if (mounted) setState(() => _breaches = r);
    } catch (e) {
      if (mounted) setState(() => _error = 'Breach check failed: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  static const _titles = {
    WatchtowerIssue.weak: ('Weak passwords', Icons.warning_amber_rounded),
    WatchtowerIssue.reused: ('Reused passwords', Icons.copy_all_outlined),
    WatchtowerIssue.insecureUrl: ('Unsecured websites', Icons.https_outlined),
    WatchtowerIssue.missing2fa: ('Two-factor available', Icons.timer_outlined),
    WatchtowerIssue.old: ('Old passwords', Icons.history),
  };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final findings = WatchtowerService.instance.analyze(state.entries);
    final scheme = Theme.of(context).colorScheme;
    final breached = _breaches == null
        ? const []
        : state.entries.where((e) => _breaches!.containsKey(e.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Watchtower')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Compromised passwords',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Checks against known breaches. Only a short hash prefix '
                      'of each password leaves your device.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _checking ? null : _checkBreaches,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.shield_outlined),
                      label: Text(_checking ? 'Checking…' : 'Check now'),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!,
                            style: TextStyle(color: scheme.error)),
                      ),
                    if (_breaches != null && breached.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('No breached passwords found.'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (breached.isNotEmpty) ...[
            _header(context, 'Breached passwords', Icons.gpp_bad_outlined,
                breached.length, scheme.error),
            for (final e in breached)
              _tile(context, e.id, e.title,
                  'Seen in ${_breaches![e.id]} breaches'),
          ],
          for (final issue in WatchtowerIssue.values)
            ..._section(context, issue, findings),
          if (findings.isEmpty && breached.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No issues found. Nice work!')),
            ),
        ],
      ),
    );
  }

  List<Widget> _section(BuildContext context, WatchtowerIssue issue,
      List<WatchtowerFinding> all) {
    final items = all.where((f) => f.issue == issue).toList();
    if (items.isEmpty) return const [];
    final (title, icon) = _titles[issue]!;
    return [
      _header(context, title, icon, items.length,
          Theme.of(context).colorScheme.onSurfaceVariant),
      for (final f in items) _tile(context, f.entry.id, f.entry.title, f.detail),
    ];
  }

  Widget _header(BuildContext context, String title, IconData icon, int count,
      Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
        Text('$count'),
      ]),
    );
  }

  Widget _tile(BuildContext context, String id, String title, String detail) {
    return ListTile(
      title: Text(title.isEmpty ? '(untitled)' : title),
      subtitle: Text(detail),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EntryDetailScreen(entryId: id))),
    );
  }
}
