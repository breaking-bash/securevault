import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vault_entry.dart';
import '../../state/vault_state.dart';
import '../widgets/totp_code_tile.dart';
import 'entry_edit_screen.dart';

class EntryDetailScreen extends StatefulWidget {
  final String entryId;
  const EntryDetailScreen({super.key, required this.entryId});

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  bool _showPassword = false;
  bool _showSecret = false;

  Widget _extraRow(VaultEntry e, String key, String label, IconData icon,
      {bool secret = false, bool mono = false}) {
    final v = e.extra[key] ?? '';
    if (v.isEmpty) return const SizedBox.shrink();
    final hidden = secret && !_showSecret;
    return _FieldRow(
      label: label,
      value: hidden ? '•' * v.length.clamp(0, 24) : v,
      icon: icon,
      monospace: mono && !hidden,
      trailing: secret
          ? IconButton(
              icon: Icon(_showSecret ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showSecret = !_showSecret),
            )
          : null,
      onCopy: () => _copy(context, v, label, sensitive: secret),
    );
  }

  List<Widget> _typeRows(VaultEntry e) {
    switch (e.type) {
      case EntryType.card:
        return [
          _extraRow(
              e, EntryFields.cardholder, 'Cardholder', Icons.person_outline),
          _extraRow(e, EntryFields.cardNumber, 'Card number', Icons.credit_card,
              secret: true),
          _extraRow(e, EntryFields.expiry, 'Expiry', Icons.event_outlined),
          _extraRow(e, EntryFields.cvv, 'Security code', Icons.password,
              secret: true),
          _extraRow(e, EntryFields.pin, 'PIN', Icons.pin_outlined,
              secret: true),
        ];
      case EntryType.ssh:
        return [
          _extraRow(e, EntryFields.publicKey, 'Public key', Icons.key,
              mono: true),
          _extraRow(
              e, EntryFields.fingerprint, 'Fingerprint', Icons.fingerprint),
          _extraRow(
              e, EntryFields.privateKey, 'Private key', Icons.lock_outline,
              secret: true, mono: true),
          _extraRow(e, EntryFields.passphrase, 'Passphrase', Icons.password,
              secret: true),
        ];
      case EntryType.passkey:
        return [
          _extraRow(e, EntryFields.rpId, 'Website', Icons.language),
          _extraRow(e, EntryFields.passkeyUser, 'User', Icons.person_outline),
          _extraRow(e, EntryFields.credentialId, 'Credential ID', Icons.badge_outlined,
              mono: true),
          _extraRow(e, EntryFields.privateKey, 'Private key', Icons.lock_outline,
              secret: true, mono: true),
        ];
      case EntryType.login:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final match = state.entries.where((e) => e.id == widget.entryId);
    if (match.isEmpty) {
      // Entry was deleted (or vault locked) — pop back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final e = match.first;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(e.title.isEmpty ? '(untitled)' : e.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EntryEditScreen(entryId: e.id))),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await _confirmDelete(context);
              if (ok == true) {
                await state.deleteEntry(e);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ..._typeRows(e),
          if (e.type == EntryType.login) ...[
            _FieldRow(
              label: 'Username / email',
              value: e.username,
              icon: Icons.person_outline,
              onCopy: e.username.isEmpty
                  ? null
                  : () => _copy(context, e.username, 'Username'),
            ),
            _FieldRow(
              label: 'Password',
              value: e.password.isEmpty
                  ? ''
                  : (_showPassword
                      ? e.password
                      : '•' * e.password.length.clamp(0, 24)),
              icon: Icons.lock_outline,
              monospace: _showPassword,
              trailing: e.password.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(_showPassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
              onCopy: e.password.isEmpty
                  ? null
                  : () =>
                      _copy(context, e.password, 'Password', sensitive: true),
            ),
            _FieldRow(
              label: 'URL',
              value: e.url,
              icon: Icons.link,
              onCopy: e.url.isEmpty ? null : () => _copy(context, e.url, 'URL'),
            ),
            if ((e.totp ?? '').isNotEmpty) ...[
              const Divider(indent: 16, endIndent: 16),
              TotpCodeTile(
                stored: e.totp!,
                onCopy: (code) => _copy(context, code, 'Code', sensitive: true),
              ),
            ],
          ],
          _FieldRow(
            label: 'Folder',
            value: state.folderName(e.folderId),
            icon: Icons.folder_outlined,
          ),
          if (e.notes.isNotEmpty)
            _FieldRow(
              label: 'Notes',
              value: e.notes,
              icon: Icons.notes,
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Updated ${_fmt(e.updatedAt)} · Created ${_fmt(e.createdAt)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String value, String label,
      {bool sensitive = false}) {
    final state = context.read<VaultState>();
    state.copyToClipboard(value, sensitive: sensitive);
    final secs = state.clipboardClearSeconds;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(sensitive && secs > 0
          ? '$label copied — clears in ${secs}s'
          : '$label copied'),
    ));
  }

  Future<bool?> _confirmDelete(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete item?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete')),
          ],
        ),
      );

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// A single detail row: leading outline icon, label + value, optional actions,
/// separated from neighbours by a thin full-width divider (minimalist style).
class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onCopy;
  final Widget? trailing;
  final bool monospace;

  const _FieldRow({
    required this.label,
    required this.value,
    required this.icon,
    this.onCopy,
    this.trailing,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty && onCopy == null && trailing == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(icon, size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    SelectableText(
                      value.isEmpty ? '—' : value,
                      style: TextStyle(
                        fontFamily: monospace ? 'monospace' : null,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (onCopy != null)
                IconButton(icon: const Icon(Icons.copy), onPressed: onCopy),
            ],
          ),
        ),
        const Divider(indent: 16, endIndent: 16),
      ],
    );
  }
}
