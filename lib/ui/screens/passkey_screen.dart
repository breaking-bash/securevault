import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vault_entry.dart';
import '../../services/autofill_bridge.dart';
import '../../state/vault_state.dart';
import '../widgets/type_tile.dart';

/// Shown when Android's Credential Manager asks SecureVault to create a
/// passkey or sign in with one.
class PasskeyScreen extends StatefulWidget {
  final AutofillRequest request;
  const PasskeyScreen({super.key, required this.request});

  @override
  State<PasskeyScreen> createState() => _PasskeyScreenState();
}

class _PasskeyScreenState extends State<PasskeyScreen> {
  bool _busy = false;
  String? _error;

  bool get _create => widget.request.passkeyMode == 'create';

  String _host(String v) => TypeTile.hostOf(v) ?? v.trim().toLowerCase();

  Future<void> _save() async {
    final r = widget.request;
    final state = context.read<VaultState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final k = await AutofillBridge.passkeyCreate();
      final e = state.newEntryDraft(type: EntryType.passkey);
      e.title = (r.rpName ?? '').isNotEmpty ? r.rpName! : (r.rpId ?? '');
      e.url = 'https://${r.rpId}';
      e.extra[EntryFields.rpId] = r.rpId ?? '';
      e.extra[EntryFields.passkeyUser] =
          (r.userName ?? '').isNotEmpty ? r.userName! : (r.displayName ?? '');
      e.extra[EntryFields.credentialId] = k['credentialId'] ?? '';
      e.extra[EntryFields.privateKey] = k['privateKey'] ?? '';
      e.extra[EntryFields.publicKey] = k['publicKey'] ?? '';
      e.extra['userHandle'] = k['userHandle'] ?? '';
      await state.saveEntry(e, isNew: true);
      await AutofillBridge.passkeyComplete();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not create the passkey.';
        });
      }
    }
  }

  Future<void> _use(VaultEntry e) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AutofillBridge.passkeyAssert(
        privateKey: e.extra[EntryFields.privateKey] ?? '',
        credentialId: e.extra[EntryFields.credentialId] ?? '',
        userHandle: e.extra['userHandle'] ?? '',
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not sign in with this passkey.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final rp = _host(r.rpId ?? '');
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (_create) {
      final user = (r.userName ?? '').isNotEmpty
          ? r.userName!
          : (r.displayName ?? '');
      body = ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.key_rounded, size: 48),
        const SizedBox(height: 16),
        Text('Create a passkey for $rp?',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (user.isNotEmpty) Text(user),
        const SizedBox(height: 8),
        Text('It will be saved in SecureVault and synced like your other items.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: _busy ? null : _save, child: const Text('Create passkey')),
        TextButton(
            onPressed: AutofillBridge.cancel, child: const Text('Not now')),
      ]);
    } else {
      final matches = context
          .watch<VaultState>()
          .activeEntries
          .where((e) =>
              e.type == EntryType.passkey &&
              (e.extra[EntryFields.privateKey] ?? '').isNotEmpty &&
              _host(e.extra[EntryFields.rpId] ?? '') == rp)
          .toList();
      body = ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('Sign in to $rp with a passkey',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final e in matches)
          ListTile(
            leading: const Icon(Icons.key_rounded),
            title: Text(e.title.isEmpty ? rp : e.title),
            subtitle: Text(e.extra[EntryFields.passkeyUser] ?? ''),
            onTap: _busy ? null : () => _use(e),
          ),
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No passkeys saved for this site')),
          ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passkey'),
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: AutofillBridge.cancel),
      ),
      body: Column(children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
        Expanded(child: body),
      ]),
    );
  }
}
