import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../state/vault_state.dart';
import 'create_account_screen.dart';

/// Account picker + master-password unlock screen (shown when ≥1 account exists).
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  LocalAccount? _selected;
  final _pw = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final state = context.read<VaultState>();
    final account = _selected ?? state.accountsList.first;
    if (_pw.text.isEmpty) {
      setState(() => _error = 'Enter your master password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await state.unlock(account: account, masterPassword: _pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Incorrect master password';
    });
    if (ok) _pw.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    _selected ??= state.accountsList.first;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 16),
                Text('Unlock your vault',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),
                if (state.accountsList.length > 1)
                  DropdownButtonFormField<String>(
                    value: _selected?.id,
                    decoration: const InputDecoration(
                      labelText: 'Account',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: state.accountsList
                        .map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ))
                        .toList(),
                    onChanged: (id) => setState(() => _selected =
                        state.accountsList.firstWhere((a) => a.id == id)),
                  )
                else
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(_selected?.name ?? ''),
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pw,
                  obscureText: _obscure,
                  autofocus: true,
                  onFieldSubmitted: (_) => _unlock(),
                  decoration: InputDecoration(
                    labelText: 'Master password',
                    errorText: _error,
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _unlock,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lock_open),
                  label: Text(_busy ? 'Unlocking…' : 'Unlock'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const CreateAccountScreen()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add another account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
