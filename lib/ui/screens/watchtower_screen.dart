import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vault_entry.dart';
import '../../services/password_generator.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Watchtower')),
      body: ListView(
        children: [
          _scoreHeader(context, WatchtowerService.instance.score(active, findings)),
          _strengthCard(context, active),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 210,
              children: [
                _statCard(context, breached.length, 'Compromised Websites',
                    'Data stored by these websites may have been compromised. Change your passwords.',
                    () => _push(context, 'Compromised Websites', null,
                        (s) => breached.map((e) => e.id).toList(), (id) => 'Seen in ${_breaches![id]} breaches')),
                _issueCard(context, findings, WatchtowerIssue.reused,
                    'Reused Passwords',
                    "Don't use the same password on multiple websites."),
                _issueCard(context, findings, WatchtowerIssue.weak,
                    'Weak Passwords',
                    'Weak passwords are easier to guess. Generate strong ones.'),
                _issueCard(context, findings, WatchtowerIssue.insecureUrl,
                    'Unsecured Websites',
                    'Websites that use HTTP URLs are not secure.'),
                _issueCard(context, findings, WatchtowerIssue.missing2fa,
                    'Inactive two-factor authentication',
                    'Sites that have two-factor authentication available but not set up.'),
                _issueCard(context, findings, WatchtowerIssue.old,
                    'Expiring',
                    'These passwords have not changed in over a year.'),
                _statCard(context, passkeys.length, 'Passkeys available',
                    'Passkeys saved in your vault.',
                    () => _push(context, 'Passkeys', null,
                        (s) => passkeys.map((e) => e.id).toList(), (_) => 'Passkey saved')),
              ],
            ),
          ),
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


  Widget _scoreHeader(BuildContext context, int score) {
    final pct = score.clamp(0, 100) / 100;
    final label = score >= 80
        ? 'FANTASTIC'
        : score >= 60
            ? 'GOOD'
            : score >= 40
                ? 'FAIR'
                : 'NEEDS WORK';
    final c = score >= 80
        ? const Color(0xFF1BA300)
        : score >= 60
            ? const Color(0xFF8AD91E)
            : score >= 40
                ? const Color(0xFFFFA900)
                : const Color(0xFFF4512C);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Watchtower',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Your score gives an overall idea of how safe your data is. '
                'Take action on flagged items to level up your security.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 130,
          height: 110,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
                size: const Size(130, 110),
                painter: _GaugePainter(pct, c)),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${score * 10}',
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w800)),
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: c)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }


  Widget _strengthCard(BuildContext context, List<VaultEntry> active) {
    const labels = ['TERRIBLE', 'WEAK', 'VERY GOOD', 'EXCELLENT', 'FANTASTIC'];
    const colors = [
      Color(0xFFF4512C),
      Color(0xFFFFA900),
      Color(0xFF8AD91E),
      Color(0xFF2ACB16),
      Color(0xFF1BA300),
    ];
    final counts = List.filled(5, 0);
    for (final e in active.where((e) => e.type == EntryType.login && e.password.isNotEmpty)) {
      counts[PasswordGenerator.instance.strength(e.password).clamp(0, 4)]++;
    }
    final total = counts.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Overall Password Strength',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 38,
                  child: total == 0
                      ? ColoredBox(color: Colors.grey.withValues(alpha: 0.3))
                      : Row(children: [
                          for (var i = 4; i >= 0; i--)
                            if (counts[i] > 0)
                              Expanded(
                                flex: counts[i],
                                child: Container(
                                    margin: const EdgeInsets.only(right: 1),
                                    color: colors[i]),
                              ),
                        ]),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(spacing: 14, runSpacing: 8, children: [
                for (var i = 4; i >= 0; i--)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                          color: colors[i],
                          borderRadius: BorderRadius.circular(4)),
                      child: Text('${counts[i]}',
                          style: const TextStyle(
                              color: Colors.black, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                    Text(labels[i],
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _issueCard(BuildContext context, List<WatchtowerFinding> findings,
      WatchtowerIssue issue, String title, String desc) {
    final items = findings.where((f) => f.issue == issue).toList();
    return _statCard(
        context,
        items.length,
        title,
        desc,
        () => _push(context, title, issue,
            (s) => [for (final f in _live(s, issue)) f.entry.id], (_) => ''));
  }

  List<WatchtowerFinding> _live(VaultState s, WatchtowerIssue issue) {
    final ign = s.settings.ignoredAlerts;
    return WatchtowerService.instance
        .analyze(s.activeEntries)
        .where((f) => f.issue == issue && !ign.contains(_key(f.entry.id, issue)))
        .toList();
  }

  Widget _statCard(BuildContext context, int count, String title, String desc,
      VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count',
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(desc,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Expanded(
                  child: Text('Show Items',
                      style: TextStyle(
                          color: scheme.primary, fontSize: 13))),
              Icon(Icons.arrow_forward, size: 18, color: scheme.primary),
            ]),
          ),
        ]),
      ),
    );
  }

  void _push(BuildContext context, String title, WatchtowerIssue? issue,
      List<String> Function(VaultState) ids, String Function(String) detail) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Consumer<VaultState>(builder: (ctx, s, _) {
        final list = ids(s);
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: list.isEmpty
              ? const Center(child: Text('Nothing to show. Nice work!'))
              : ListView(children: [
                  for (final id in list)
                    ListTile(
                      title: Text(s.entries
                              .firstWhere((e) => e.id == id)
                              .title
                              .isEmpty
                          ? '(untitled)'
                          : s.entries.firstWhere((e) => e.id == id).title),
                      subtitle: detail(id).isEmpty ? null : Text(detail(id)),
                      onTap: () => _open(ctx, id),
                      trailing: issue == null
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: 'Ignore this alert',
                              icon: const Icon(Icons.visibility_off_outlined),
                              onPressed: () => _setIgnored(s, id, issue, true),
                            ),
                    ),
                ]),
        );
      }),
    ));
  }

  void _open(BuildContext context, String id) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EntryDetailScreen(entryId: id)));
}

class _GaugePainter extends CustomPainter {
  final double pct;
  final Color color;
  _GaugePainter(this.pct, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2 + 6),
        radius: size.width / 2 - 10);
    const start = 0.75 * 3.14159265;
    const sweep = 1.5 * 3.14159265;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.2);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, start, sweep, false, bg);
    canvas.drawArc(rect, start, sweep * pct, false, fg);
  }

  @override
  bool shouldRepaint(_GaugePainter o) => o.pct != pct || o.color != color;
}