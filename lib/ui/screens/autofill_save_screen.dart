import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vault_entry.dart';
import '../../services/autofill_bridge.dart';
import '../../state/vault_state.dart';
import '../widgets/type_tile.dart';

/// Shown when Android asks to save a login the user just typed in another
/// app. Saves a new login, or updates the password of a matching one.
class AutofillSaveScreen extends StatefulWidget {
  final AutofillRequest request;
  const AutofillSaveScreen({super.key, required this.request});

  @override
  State<AutofillSaveScreen> createState() => _AutofillSaveScreenState();
}

class _AutofillSaveScreenState extends State<AutofillSaveScreen> {
  late final TextEditingController _title;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  bool _show = false;
  VaultEntry? _existing;

  @override
  void initState() {
    super.initState();
    final r = widget.request;
    final host = r.domain ?? '';
    final guess = host.isNotEmpty
        ? host.replaceFirst(RegExp(r'^www\.'), '')
        : (r.package ?? '').split('.').last;
    _title = TextEditingController(text: guess);
    _user = TextEditingController(text: r.saveUsername);
    _pass = TextEditingController(text: r.savePassword);
    final logins = context
        .read<VaultState>()
        .activeEntries
        .where((e) => e.type == EntryType.login);
    for (final e in logins) {
      final h = TypeTile.hostOf(e.url);
      final sameSite = host.isNotEmpty && h != null && (h == host || host.endsWith('.$h'));
      if (sameSite && e.username == r.saveUsername) _existing = e;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<VaultState>();
    final host = widget.request.domain ?? '';
    final e = _existing ?? state.newEntryDraft();
    if (_existing == null) {
      e.title = _title.text.trim();
      if (host.isNotEmpty) e.url = 'https://$host';
    }
    e.username = _user.text.trim();
    e.password = _pass.text;
    e.updatedAt = DateTime.now();
    await state.saveEntry(e, isNew: _existing == null);
    await AutofillBridge.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final update = _existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(update ? 'Update login?' : 'Save login?'),
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: AutofillBridge.cancel),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            update
                ? 'The password for this login changed. Update it in SecureVault?'
                : 'Save this login to SecureVault so you can autofill it next time.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (!update) ...[
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _user,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: !_show,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(_show
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: Text(update ? 'Update' : 'Save'),
          ),
          TextButton(
              onPressed: AutofillBridge.cancel, child: const Text('Not now')),
        ],
      ),
    );
  }
}
