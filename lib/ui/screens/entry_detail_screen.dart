import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/vault_state.dart';
import 'entry_edit_screen.dart';

class EntryDetailScreen extends StatefulWidget {
  final String entryId;
  const EntryDetailScreen({super.key, required this.entryId});

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  bool _showPassword = false;

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
        padding: const EdgeInsets.all(16),
        children: [
          _FieldCard(
            label: 'Username / email',
            value: e.username,
            icon: Icons.person_outline,
            onCopy: e.username.isEmpty
                ? null
                : () => _copy(context, e.username, 'Username'),
          ),
          _FieldCard(
            label: 'Password',
            value: e.password.isEmpty
                ? ''
                : (_showPassword ? e.password : '•' * e.password.length.clamp(0, 24)),
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
                : () => _copy(context, e.password, 'Password', sensitive: true),
          ),
          _FieldCard(
            label: 'URL',
            value: e.url,
            icon: Icons.link,
            onCopy: e.url.isEmpty ? null : () => _copy(context, e.url, 'URL'),
          ),
          if ((e.totp ?? '').isNotEmpty)
            _FieldCard(
              label: 'TOTP secret',
              value: _showPassword ? e.totp! : '••••••••',
              icon: Icons.timer_outlined,
              onCopy: () => _copy(context, e.totp!, 'TOTP secret', sensitive: true),
            ),
          _FieldCard(
            label: 'Folder',
            value: state.folderName(e.folderId),
            icon: Icons.folder_outlined,
          ),
          if (e.notes.isNotEmpty)
            _FieldCard(
              label: 'Notes',
              value: e.notes,
              icon: Icons.notes,
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Updated ${_fmt(e.updatedAt)} · Created ${_fmt(e.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
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
          title: const Text('Delete login?'),
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

class _FieldCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onCopy;
  final Widget? trailing;
  final bool monospace;

  const _FieldCard({
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
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
    );
  }
}
