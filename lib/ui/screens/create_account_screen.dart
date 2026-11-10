import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/password_generator.dart';
import '../../state/vault_state.dart';

/// Create a new local account + master password (zero-knowledge).
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'My Vault');
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _ack = false;

  @override
  void dispose() {
    _name.dispose();
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_ack) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please acknowledge that the master password cannot be recovered.'),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<VaultState>().createAccountAndUnlock(
            name: _name.text,
            masterPassword: _pw.text,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = PasswordGenerator.instance.strength(_pw.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Create your vault')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.shield_outlined, size: 56),
                  const SizedBox(height: 16),
                  Text('Set up a new encrypted vault',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Vault / account name',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _pw,
                    obscureText: _obscure,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Master password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 8) {
                        return 'Use at least 8 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  _StrengthBar(strength: strength),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration: const InputDecoration(
                      labelText: 'Confirm master password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) =>
                        v != _pw.text ? 'Passwords do not match' : null,
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _ack,
                    onChanged: (v) => setState(() => _ack = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I understand my data is encrypted with this password '
                      'and it cannot be recovered or reset if I forget it.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(_busy ? 'Creating…' : 'Create vault'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StrengthBar extends StatelessWidget {
  final int strength;
  const _StrengthBar({required this.strength});

  @override
  Widget build(BuildContext context) {
    const labels = ['Very weak', 'Weak', 'Fair', 'Good', 'Strong'];
    const colors = [
      Colors.red,
      Colors.deepOrange,
      Colors.orange,
      Colors.lightGreen,
      Colors.green
    ];
    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: (strength + 1) / 5,
            minHeight: 6,
            backgroundColor: Colors.grey.withValues(alpha: 0.3),
            color: colors[strength],
          ),
        ),
        const SizedBox(width: 10),
        Text(labels[strength], style: TextStyle(color: colors[strength])),
      ],
    );
  }
}
