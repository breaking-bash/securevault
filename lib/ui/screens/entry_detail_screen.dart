import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_templates.dart';
import '../../models/vault_entry.dart';
import '../../state/vault_state.dart';
import '../widgets/totp_code_tile.dart';
import 'entry_edit_screen.dart';

const _dot = '\u2022';

class EntryDetailScreen extends StatefulWidget {
  final String entryId;
  const EntryDetailScreen({super.key, required this.entryId});

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  final Set<String> _revealed = {};

  void _toggle(String k) => setState(
      () => _revealed.contains(k) ? _revealed.remove(k) : _revealed.add(k));

  Widget _row(String id, String label, String value, FieldKind kind,
      {bool masked = false, bool mono = false}) {
    if (value.isEmpty) return const SizedBox.shrink();
    final hidden = masked && !_revealed.contains(id);
    final isOtp = kind == FieldKind.otp;
    if (isOtp) {
      return TotpCodeTile(
        stored: value,
        onCopy: (code) => _copy(context, code, 'Code', sensitive: true),
      );
    }
    return _FieldRow(
      label: label,
      value: hidden ? _dot * value.length.clamp(0, 24) : value,
      icon: kind.icon,
      monospace: mono && !hidden,
      trailing: masked
          ? IconButton(
              icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
              onPressed: () => _toggle(id),
            )
          : null,
      onCopy: () => _copy(context, value, label, sensitive: masked),
    );
  }

  Future<void> _download(Attachment a) async {
    try {
      final path = await FilePicker.saveFile(fileName: a.name, bytes: a.bytes);
      if (path != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved ${a.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save file: $e')));
      }
    }
  }

  static String _size(int b) => b < 1024
      ? '$b B'
      : b < 1024 * 1024
          ? '${(b / 1024).toStringAsFixed(1)} KB'
          : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

  Widget _section(List<Widget> rows, {String? header}) {
    final visible = rows.where((w) => w is! SizedBox).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(header.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ...visible,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final match = state.entries.where((e) => e.id == widget.entryId);
    if (match.isEmpty) {
      // Entry was deleted (or vault locked) - pop back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final e = match.first;
    final tpl = ItemTemplates.of(e.type);
    final scheme = Theme.of(context).colorScheme;
    final signIn = e.extra[ItemTemplates.signInKey] ?? '';

    final main = <Widget>[
      if (e.type == EntryType.login) ...[
        _row('_user', 'Username / email', e.username, FieldKind.email),
        _row('_pw', 'Password', e.password, FieldKind.password,
            masked: true, mono: true),
        _row('_url', 'Website', e.url, FieldKind.url),
        _row('_signin', 'Sign in with', signIn, FieldKind.text),
        if ((e.totp ?? '').isNotEmpty)
          _row('_totp', 'One-time password', e.totp!, FieldKind.otp),
      ] else
        for (final f in tpl.fields)
          _row(f.key, f.label, e.extra[f.key] ?? '', f.kind,
              masked: f.masked, mono: f.mono),
    ];

    final custom = [
      for (var i = 0; i < e.customFields.length; i++)
        _row('c$i', e.customFields[i].label.isEmpty
                ? e.customFields[i].kind.label
                : e.customFields[i].label,
            e.customFields[i].value, e.customFields[i].kind,
            masked: e.customFields[i].kind.isSecretByDefault),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EntryEditScreen(entryId: e.id))),
          ),
          IconButton(
            tooltip: e.archived ? 'Unarchive' : 'Archive',
            icon: Icon(e.archived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined),
            onPressed: () async {
              await state.setArchived(e, !e.archived);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          IconButton(
            tooltip: 'Delete',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: tpl.color,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(tpl.icon, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title.isEmpty ? '(untitled)' : e.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(tpl.label,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _section(main),
          _section(custom, header: 'More fields'),
          if (e.notes.isNotEmpty)
            _section([
              _FieldRow(label: 'Notes', value: e.notes, icon: Icons.notes),
            ]),
          if (e.attachments.isNotEmpty)
            _section([
              for (final a in e.attachments)
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(a.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_size(a.size)),
                  trailing: IconButton(
                    tooltip: 'Save to device',
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => _download(a),
                  ),
                ),
            ], header: 'Attachments'),
          if (e.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in e.tags)
                    Chip(
                      avatar: const Icon(Icons.sell_outlined, size: 16),
                      label: Text(t),
                    ),
                ],
              ),
            ),
          _section([
            _FieldRow(
              label: 'Folder',
              value: e.folderId == null ? '' : state.folderName(e.folderId),
              icon: Icons.folder_outlined,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Updated ${_fmt(e.updatedAt)} \u00b7 Created ${_fmt(e.createdAt)}',
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
          ? '$label copied \u2014 clears in ${secs}s'
          : '$label copied'),
    ));
  }

  Future<bool?> _confirmDelete(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Move to Recently Deleted?'),
          content: const Text(
              'You can restore it within 30 days, after which it is deleted permanently.'),
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

/// A single detail row: leading icon, label + value, optional actions.
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
    if (value.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
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
                  value,
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
    );
  }
}
