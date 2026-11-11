import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/account_service.dart';
import '../../services/password_generator.dart';
import '../../state/vault_state.dart';
import '../widgets/emergency_kit.dart';

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
  String? _nameError;

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
    setState(() {
      _busy = true;
      _nameError = null;
    });
    try {
      await context.read<VaultState>().createAccountAndUnlock(
            name: _name.text,
            masterPassword: _pw.text,
          );
    } on AccountExistsException {
      // BUG 1: reject duplicate usernames with a clear inline error.
      if (mounted) {
        setState(() {
          _busy = false;
          _nameError = 'An account with this name already exists.';
        });
      }
      return;
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    if (mounted) await _showSecretKey();
    // BUG 2: on success, clear the form and navigate away (replace) so the
    // signup page — with its entered values — is removed from the back stack.
    if (!mounted) return;
    _name.clear();
    _pw.clear();
    _confirm.clear();
    // The GateScreen at the root reactively shows the unlocked HomeScreen, so
    // popping the pushed signup route reveals it with no stale field values.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _showSecretKey() async {
    final key = context.read<VaultState>().sessionSecretKey;
    if (key == null) return;
    await showEmergencyKitDialog(context,
        accountName: _name.text.trim(), secretKey: key);
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
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Vault / account name',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      errorText: _nameError,
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
