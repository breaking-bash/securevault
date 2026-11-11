import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vault_entry.dart';

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
      final r = await WatchtowerService.instance.checkBreaches(state.activeEntries);
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
    WatchtowerIssue.missing2fa:
        ('2FA available, not set up', Icons.timer_outlined),
    WatchtowerIssue.old: ('Old passwords', Icons.history),
  };

  bool _showIgnored = false;

  static String _key(String id, WatchtowerIssue i) => '$id|${i.name}';

  Future<void> _setIgnored(
      VaultState state, String id, WatchtowerIssue i, bool ignore) async {
    final s = state.settings;
    final set = {...s.ignoredAlerts};
    ignore ? set.add(_key(id, i)) : set.remove(_key(id, i));
    s.ignoredAlerts = set;
    await state.updateSettings(s);
  }

  Color _scoreColor(int s) => s >= 80
      ? Colors.green
      : s >= 50
          ? Colors.orange
          : Colors.red;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final active = state.activeEntries;
    final all = WatchtowerService.instance.analyze(active);
    final ignoredKeys = state.settings.ignoredAlerts;
    bool isIgnored(WatchtowerFinding f) =>
        ignoredKeys.contains(_key(f.entry.id, f.issue));
    final findings = all.where((f) => !isIgnored(f)).toList();
    final ignored = all.where(isIgnored).toList();
    final scheme = Theme.of(context).colorScheme;
    final breached = _breaches == null
        ? const <VaultEntry>[]
        : active.where((e) => _breaches!.containsKey(e.id)).toList();
    final passkeys = active.where((e) => e.type == EntryType.passkey).toList();
    final score = WatchtowerService.instance.score(active, findings);
    final color = _scoreColor(score);

    return Scaffold(
      appBar: AppBar(title: const Text('Watchtower')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: score / 100,
                          strokeWidth: 9,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.18),
                        ),
                      ),
                      Text('$score',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Overall password strength',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          score >= 80
                              ? 'Looking good'
                              : score >= 50
                                  ? 'Could be stronger'
                                  : 'Needs attention',
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
          _summary(context, state, 'Reused passwords', Icons.copy_all_outlined,
              findings.where((f) => f.issue == WatchtowerIssue.reused).toList(),
              WatchtowerIssue.reused),
          _summary(context, state, 'Weak passwords',
              Icons.warning_amber_rounded,
              findings.where((f) => f.issue == WatchtowerIssue.weak).toList(),
              WatchtowerIssue.weak),
          _entriesGroup(context, 'Passkeys available', Icons.key, passkeys,
              (e) => 'Passkey saved'),
          _summary(context, state, '2FA available, not set up',
              Icons.timer_outlined,
              findings
                  .where((f) => f.issue == WatchtowerIssue.missing2fa)
                  .toList(),
              WatchtowerIssue.missing2fa),
          _summary(context, state, 'Unsecured websites', Icons.https_outlined,
              findings
                  .where((f) => f.issue == WatchtowerIssue.insecureUrl)
                  .toList(),
              WatchtowerIssue.insecureUrl),
          _summary(context, state, 'Old passwords', Icons.history,
              findings.where((f) => f.issue == WatchtowerIssue.old).toList(),
              WatchtowerIssue.old),
          if (breached.isNotEmpty)
            _entriesGroup(context, 'Breached passwords',
                Icons.gpp_bad_outlined, breached,
                (e) => 'Seen in ${_breaches![e.id]} breaches',
                color: scheme.error),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
          if (ignored.isNotEmpty)
            SwitchListTile(
              title: const Text('Show ignored alerts'),
              subtitle: Text('${ignored.length} ignored'),
              value: _showIgnored,
              onChanged: (v) => setState(() => _showIgnored = v),
            ),
          if (_showIgnored)
            for (final f in ignored)
              ListTile(
                leading: Icon(_titles[f.issue]!.$2),
                title: Text(f.entry.title.isEmpty ? '(untitled)' : f.entry.title),
                subtitle: Text(_titles[f.issue]!.$1),
                trailing: TextButton(
                  onPressed: () => _setIgnored(state, f.entry.id, f.issue, false),
                  child: const Text('Restore'),
                ),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, VaultState state, String title,
      IconData icon, List<WatchtowerFinding> items, WatchtowerIssue issue) {
    return _group(
      context,
      title,
      icon,
      items.length,
      [
        for (final f in items)
          ListTile(
            title: Text(f.entry.title.isEmpty ? '(untitled)' : f.entry.title),
            subtitle: Text(f.detail),
            onTap: () => _open(context, f.entry.id),
            trailing: IconButton(
              tooltip: 'Ignore this alert',
              icon: const Icon(Icons.visibility_off_outlined),
              onPressed: () => _setIgnored(state, f.entry.id, issue, true),
            ),
          ),
      ],
    );
  }

  Widget _entriesGroup(BuildContext context, String title, IconData icon,
      List<VaultEntry> items, String Function(VaultEntry) detail,
      {Color? color}) {
    return _group(
      context,
      title,
      icon,
      items.length,
      [
        for (final e in items)
          ListTile(
            title: Text(e.title.isEmpty ? '(untitled)' : e.title),
            subtitle: Text(detail(e)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(context, e.id),
          ),
      ],
      color: color,
    );
  }

  Widget _group(BuildContext context, String title, IconData icon, int count,
      List<Widget> children,
      {Color? color}) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return ExpansionTile(
      leading: Icon(icon, color: count == 0 ? Colors.green : c),
      title: Text(title),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$count',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text(count == 0 ? '' : 'Show items',
            style: Theme.of(context).textTheme.labelSmall),
        const Icon(Icons.expand_more),
      ]),
      children: children,
    );
  }

  void _open(BuildContext context, String id) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EntryDetailScreen(entryId: id)));
}