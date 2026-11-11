import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_templates.dart';
import '../../models/vault_entry.dart';
import '../../services/autofill_bridge.dart';
import '../../state/vault_state.dart';
import '../widgets/type_tile.dart';

/// Shown instead of the home screen when SecureVault was opened by Android
/// autofill: lists matching logins first, tap one to fill the other app.
class AutofillPickerScreen extends StatefulWidget {
  final AutofillRequest request;
  const AutofillPickerScreen({super.key, required this.request});

  @override
  State<AutofillPickerScreen> createState() => _AutofillPickerScreenState();
}

class _AutofillPickerScreenState extends State<AutofillPickerScreen> {
  String _q = '';

  // Higher = better match for the requesting site/app.
  int _score(VaultEntry e) {
    final host = TypeTile.hostOf(e.url);
    final domain = widget.request.domain?.toLowerCase();
    final pkg = widget.request.package?.toLowerCase() ?? '';
    if (host == null) {
      final t = e.title.toLowerCase();
      return t.length > 2 && pkg.contains(t.replaceAll(' ', '')) ? 1 : 0;
    }
    if (domain != null && domain.isNotEmpty) {
      if (host == domain || domain.endsWith('.$host') || host.endsWith('.$domain')) {
        return 3;
      }
      return 0;
    }
    final parts = host.split('.');
    final label = parts.length >= 2 ? parts[parts.length - 2] : host;
    return label.length > 2 && pkg.contains(label) ? 2 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final logins =
        state.activeEntries.where((e) => e.type == EntryType.login).toList();
    final q = _q.trim().toLowerCase();
    final suggested = logins.where((e) => _score(e) > 0).toList()
      ..sort((a, b) => _score(b).compareTo(_score(a)));
    final others = logins
        .where((e) => _score(e) == 0)
        .where((e) =>
            q.isEmpty ||
            e.title.toLowerCase().contains(q) ||
            e.username.toLowerCase().contains(q) ||
            e.url.toLowerCase().contains(q))
        .toList();

    Widget tile(VaultEntry e) => ListTile(
          leading: TypeTile(
              icon: ItemTemplates.of(e.type).icon,
              color: ItemTemplates.of(e.type).color,
              url: e.url),
          title: Text(e.title.isEmpty ? '(untitled)' : e.title),
          subtitle: Text(e.username),
          onTap: () => AutofillBridge.fill(e.username, e.password),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Autofill'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: AutofillBridge.cancel,
        ),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              widget.request.domain ?? widget.request.package ?? '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (suggested.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('SUGGESTED',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            ...suggested.map(tile),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: 'Search all logins',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          ...others.map(tile),
          if (suggested.isEmpty && others.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No logins found')),
            ),
        ],
      ),
    );
  }
}