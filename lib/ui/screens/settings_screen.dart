import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../state/vault_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final s = state.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: s.themeMode,
              onChanged: (m) {
                if (m == null) return;
                state.updateSettings(AppSettings(
                  themeMode: m,
                  autoLockMinutes: s.autoLockMinutes,
                  clipboardClearSeconds: s.clipboardClearSeconds,
                ));
              },
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
            ),
          ),
          const _SectionHeader('Security'),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Auto-lock after inactivity'),
            subtitle: Text(s.autoLockMinutes == 0
                ? 'Never (not recommended)'
                : '${s.autoLockMinutes} minute(s)'),
            trailing: DropdownButton<int>(
              value: s.autoLockMinutes,
              onChanged: (v) {
                if (v == null) return;
                state.updateSettings(AppSettings(
                  themeMode: s.themeMode,
                  autoLockMinutes: v,
                  clipboardClearSeconds: s.clipboardClearSeconds,
                ));
              },
              items: const [
                DropdownMenuItem(value: 0, child: Text('Never')),
                DropdownMenuItem(value: 1, child: Text('1 min')),
                DropdownMenuItem(value: 3, child: Text('3 min')),
                DropdownMenuItem(value: 5, child: Text('5 min')),
                DropdownMenuItem(value: 15, child: Text('15 min')),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste_off_outlined),
            title: const Text('Clear clipboard after copy'),
            subtitle: Text(s.clipboardClearSeconds == 0
                ? 'Never'
                : '${s.clipboardClearSeconds} seconds'),
            trailing: DropdownButton<int>(
              value: s.clipboardClearSeconds,
              onChanged: (v) {
                if (v == null) return;
                state.updateSettings(AppSettings(
                  themeMode: s.themeMode,
                  autoLockMinutes: s.autoLockMinutes,
                  clipboardClearSeconds: v,
                ));
              },
              items: const [
                DropdownMenuItem(value: 0, child: Text('Never')),
                DropdownMenuItem(value: 15, child: Text('15 s')),
                DropdownMenuItem(value: 30, child: Text('30 s')),
                DropdownMenuItem(value: 60, child: Text('60 s')),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change master password'),
            subtitle: const Text('Re-encrypts the whole vault'),
            onTap: () => _changeMasterPassword(context),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock vault now'),
            onTap: () {
              state.lock();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('SecureVault'),
            subtitle: Text(
                'Zero-knowledge, on-device password manager.\n'
                'Argon2id key derivation · AES-256-GCM encryption.\n'
                'All data is stored locally on this device only.'),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }

  Future<void> _changeMasterPassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          bool busy = false;
          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            setLocal(() => busy = true);
            final ok = await ctx.read<VaultState>().changeMasterPassword(
                  currentPassword: current.text,
                  newPassword: next.text,
                );
            if (!ctx.mounted) return;
            if (ok) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Master password changed & vault re-encrypted')));
            } else {
              setLocal(() {
                busy = false;
                error = 'Current password is incorrect';
              });
            }
          }

          return AlertDialog(
            title: const Text('Change master password'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: current,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: 'Current password', errorText: error),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: next,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New password'),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'At least 8 characters'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: confirm,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Confirm new password'),
                    validator: (v) =>
                        v != next.text ? 'Passwords do not match' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'Working…' : 'Change'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}
