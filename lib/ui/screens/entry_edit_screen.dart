import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vault_entry.dart';
import '../../services/totp_service.dart';
import '../../state/vault_state.dart';
import '../widgets/generator_sheet.dart';
import 'totp_scan_screen.dart';

/// Create or edit a login entry. Pass [entryId] to edit, or null to create.
class EntryEditScreen extends StatefulWidget {
  final String? entryId;
  const EntryEditScreen({super.key, this.entryId});

  @override
  State<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends State<EntryEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late VaultEntry _entry;
  late bool _isNew;
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _url;
  late final TextEditingController _notes;
  late final TextEditingController _totp;
  String? _folderId;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final state = context.read<VaultState>();
    if (widget.entryId != null) {
      _entry = state.entries.firstWhere((e) => e.id == widget.entryId);
      _isNew = false;
    } else {
      _entry = state.newEntryDraft();
      _isNew = true;
    }
    _title = TextEditingController(text: _entry.title);
    _username = TextEditingController(text: _entry.username);
    _password = TextEditingController(text: _entry.password);
    _url = TextEditingController(text: _entry.url);
    _notes = TextEditingController(text: _entry.notes);
    _totp = TextEditingController(text: _entry.totp ?? '');
    _folderId = _entry.folderId;
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _url.dispose();
    _notes.dispose();
    _totp.dispose();
    super.dispose();
  }

  // QR scanning needs a camera — only offered on Android/iOS.
  bool get _canScan => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _scanTotp() async {
    final config = await Navigator.of(context).push<TotpConfig>(
      MaterialPageRoute(builder: (_) => const TotpScanScreen()),
    );
    if (config == null || !mounted) return;
    setState(() => _totp.text = config.secret);
    final who = config.issuer ?? config.account;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(who == null ? 'TOTP secret added' : 'TOTP added for $who'),
    ));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<VaultState>();
    _entry.title = _title.text.trim();
    _entry.username = _username.text;
    _entry.password = _password.text;
    _entry.url = _url.text.trim();
    _entry.notes = _notes.text;
    _entry.totp = _totp.text.trim().isEmpty ? null : _totp.text.trim();
    _entry.folderId = _folderId;
    await state.saveEntry(_entry, isNew: _isNew);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add login' : 'Edit login'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title *',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration: InputDecoration(
                labelText: 'Username / email',
                prefixIcon: const Icon(Icons.person_outline),
                suffixIcon: IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy),
                  onPressed: () =>
                      state.copyToClipboard(_username.text),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _obscure ? 'Show' : 'Hide',
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    IconButton(
                      tooltip: 'Generate',
                      icon: const Icon(Icons.casino_outlined),
                      onPressed: () => showGeneratorSheet(
                        context,
                        onUse: (pw) => setState(() => _password.text = pw),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL / website',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _folderId,
              decoration: const InputDecoration(
                labelText: 'Folder',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('No folder')),
                ...state.folders.map((f) =>
                    DropdownMenuItem<String?>(value: f.id, child: Text(f.name))),
              ],
              onChanged: (v) => setState(() => _folderId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _totp,
              decoration: InputDecoration(
                labelText: 'TOTP secret (optional)',
                prefixIcon: const Icon(Icons.timer_outlined),
                helperText: _canScan
                    ? 'Stored encrypted. Base32 secret, or scan a QR code.'
                    : 'Stored encrypted. Base32 secret, optional.',
                suffixIcon: _canScan
                    ? IconButton(
                        tooltip: 'Scan QR code',
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _scanTotp,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save login'),
            ),
          ],
        ),
      ),
    );
  }
}
