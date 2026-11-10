import 'package:flutter/material.dart';

import 'create_account_screen.dart';

/// First-run screen shown when the device has no accounts yet.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shield_moon_outlined,
                      size: 64, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 24),
                Text('SecureVault',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Your passwords, secure notes and logins — encrypted and '
                  'stored only on this device. No cloud, no server, zero-knowledge.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                const _Feature(
                    icon: Icons.lock_outline,
                    text: 'Argon2id + AES-256-GCM encryption'),
                const _Feature(
                    icon: Icons.phonelink_lock_outlined,
                    text: 'Everything stays on your device'),
                const _Feature(
                    icon: Icons.key_outlined,
                    text: 'Unlocked only by your master password'),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const CreateAccountScreen()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Create your vault'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Feature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
