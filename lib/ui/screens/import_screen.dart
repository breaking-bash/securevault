import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vault_entry.dart';
import '../../services/import_service.dart';
import '../../state/vault_state.dart';

/// Import logins from another password manager's CSV export.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportResult? _result;
  String? _error;
  bool _busy = false;
  int _done = 0;

  static const _sources = [
    ('1Password', 'Export as CSV from 1Password (File > Export).'),
    ('Bitwarden', 'Tools > Export vault > .csv.'),
    ('LastPass', 'Account options > Advanced > Export.'),
    ('Chrome / Edge / Brave', 'Settings > Passwords > Export passwords.'),
    ('Firefox', 'about:logins > menu > Export passwords.'),
    ('Dashlane', 'File > Export > CSV.'),
    ('KeePass', 'File > Export > KeePass CSV.'),
  ];

  Future<void> _pick() async {
    setState(() => _error = null);
    final res = await FilePicker.pickFiles(
        type: FileType.any, withData: true, allowMultiple: false);
    if (res == null || res.files.isEmpty) return;
    final bytes = res.files.first.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read that file.');
      return;
    }
    final parsed = ImportService.parse(utf8.decode(bytes, allowMalformed: true));
    setState(() {
      _result = parsed;
      if (parsed == null || parsed.items.isEmpty) {
        _error = 'No logins found. Make sure it is a CSV export.';
        _result = null;
      }
    });
  }

  Future<void> _import() async {
    final result = _result!;
    final state = context.read<VaultState>();
    setState(() {
      _busy = true;
      _done = 0;
    });
    final folderIds = <String, String>{
      for (final f in state.folders) f.name.toLowerCase(): f.id,
    };
    for (final it in result.items) {
      String? folderId;
      final fname = it.folder;
      if (fname != null) {
        folderId = folderIds[fname.toLowerCase()];
        if (folderId == null) {
          final f = await state.createFolder(fname);
          folderId = f.id;
          folderIds[fname.toLowerCase()] = f.id;
        }
      }
      final e = state.newEntryDraft(type: EntryType.login)
        ..title = it.title
        ..username = it.username
        ..password = it.password
        ..url = it.url
        ..notes = it.notes
        ..totp = it.totp
        ..folderId = folderId;
      await state.saveEntry(e, isNew: true);
      if (mounted) setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${result.items.length} items')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Import data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              'Move your logins from another password manager. Export a CSV '
              'file from it, then choose the file here. Folders are kept and '
              'one-time passwords are imported when present.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final s in _sources)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(s.$1),
                    subtitle: Text(s.$2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (r == null)
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose CSV file'),
            )
          else ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('${r.items.length} items found'),
                subtitle: Text('Detected: ${r.source}'),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download_done),
              label: Text(_busy
                  ? 'Importing $_done / ${r.items.length}'
                  : 'Import ${r.items.length} items'),
            ),
            TextButton(
                onPressed: _busy ? null : () => setState(() => _result = null),
                child: const Text('Choose a different file')),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child:
                  Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 16),
          Text(
              'Delete the exported CSV afterwards - it contains your passwords '
              'in plain text.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}
