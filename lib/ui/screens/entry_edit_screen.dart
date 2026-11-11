import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vault_entry.dart';
import '../../services/ssh_key_service.dart';
import '../../services/totp_service.dart';
import '../../state/vault_state.dart';
import '../widgets/generator_sheet.dart';
import 'totp_scan_screen.dart';

/// Create or edit a login entry. Pass [entryId] to edit, or null to create.
class EntryEditScreen extends StatefulWidget {
  final String? entryId;
  final EntryType newType;
  const EntryEditScreen(
      {super.key, this.entryId, this.newType = EntryType.login});

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
  final Map<String, TextEditingController> _extra = {};
  String? _folderId;
  bool _obscure = true;
  bool _obscureSecret = true;

  static const _extraKeys = [
    EntryFields.cardholder,
    EntryFields.cardNumber,
    EntryFields.expiry,
    EntryFields.cvv,
    EntryFields.pin,
    EntryFields.publicKey,
    EntryFields.privateKey,
    EntryFields.fingerprint,
    EntryFields.passphrase,
    EntryFields.rpId,
    EntryFields.passkeyUser,
    EntryFields.credentialId,
  ];

  @override
  void initState() {
    super.initState();
    final state = context.read<VaultState>();
    if (widget.entryId != null) {
      _entry = state.entries.firstWhere((e) => e.id == widget.entryId);
      _isNew = false;
    } else {
      _entry = state.newEntryDraft(type: widget.newType);
      _isNew = true;
    }
    _title = TextEditingController(text: _entry.title);
    _username = TextEditingController(text: _entry.username);
    _password = TextEditingController(text: _entry.password);
    _url = TextEditingController(text: _entry.url);
    _notes = TextEditingController(text: _entry.notes);
    _totp = TextEditingController(text: _entry.totp ?? '');
    for (final k in _extraKeys) {
      _extra[k] = TextEditingController(text: _entry.extra[k] ?? '');
    }
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
    for (final c in _extra.values) {
      c.dispose();
    }
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

  bool _isRelevantKey(String k) {
    switch (_entry.type) {
      case EntryType.card:
        return const [
          EntryFields.cardholder,
          EntryFields.cardNumber,
          EntryFields.expiry,
          EntryFields.cvv,
          EntryFields.pin,
        ].contains(k);
      case EntryType.ssh:
        return const [
          EntryFields.publicKey,
          EntryFields.privateKey,
          EntryFields.fingerprint,
          EntryFields.passphrase,
        ].contains(k);
      case EntryType.passkey:
        return const [
          EntryFields.rpId,
          EntryFields.passkeyUser,
          EntryFields.credentialId,
          EntryFields.privateKey,
        ].contains(k);
      case EntryType.login:
        return false;
    }
  }

  Future<void> _generateSshKey() async {
    final key = await SshKeyService.instance
        .generateEd25519(comment: _title.text.trim());
    if (!mounted) return;
    setState(() {
      _extra[EntryFields.publicKey]!.text = key.publicKey;
      _extra[EntryFields.privateKey]!.text = key.privateKey;
      _extra[EntryFields.fingerprint]!.text = key.fingerprint;
    });
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
    _entry.extra = {
      for (final k in _extraKeys)
        if (_isRelevantKey(k) && _extra[k]!.text.isNotEmpty)
          k: _extra[k]!.text.trim(),
    };
    await state.saveEntry(_entry, isNew: _isNew);
    if (mounted) Navigator.of(context).pop();
  }

  static String _typeLabel(EntryType t) => switch (t) {
        EntryType.login => 'login',
        EntryType.card => 'credit card',
        EntryType.ssh => 'SSH key',
        EntryType.passkey => 'passkey',
      };

  Widget _field(String key, String label, IconData icon,
      {bool secret = false,
      int maxLines = 1,
      TextInputType? keyboard,
      bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _extra[key],
        obscureText: secret && _obscureSecret,
        maxLines: secret && _obscureSecret ? 1 : maxLines,
        keyboardType: keyboard,
        style: mono ? const TextStyle(fontFamily: 'monospace') : null,
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: maxLines > 1,
          prefixIcon: Icon(icon),
          suffixIcon: secret
              ? IconButton(
                  icon: Icon(
                      _obscureSecret ? Icons.visibility : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscureSecret = !_obscureSecret),
                )
              : null,
        ),
      ),
    );
  }

  List<Widget> _typeFields() {
    switch (_entry.type) {
      case EntryType.card:
        return [
          _field(
              EntryFields.cardholder, 'Cardholder name', Icons.person_outline),
          _field(EntryFields.cardNumber, 'Card number', Icons.credit_card,
              keyboard: TextInputType.number),
          _field(EntryFields.expiry, 'Expiry (MM/YY)', Icons.event_outlined,
              keyboard: TextInputType.datetime),
          _field(EntryFields.cvv, 'Security code (CVV)', Icons.password,
              secret: true, keyboard: TextInputType.number),
          _field(EntryFields.pin, 'PIN', Icons.pin_outlined,
              secret: true, keyboard: TextInputType.number),
        ];
      case EntryType.ssh:
        return [
          OutlinedButton.icon(
            onPressed: _generateSshKey,
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('Generate Ed25519 key pair'),
          ),
          const SizedBox(height: 12),
          _field(EntryFields.publicKey, 'Public key', Icons.key,
              maxLines: 3, mono: true),
          _field(EntryFields.privateKey, 'Private key', Icons.lock_outline,
              secret: true, maxLines: 6, mono: true),
          _field(EntryFields.fingerprint, 'Fingerprint', Icons.fingerprint),
          _field(EntryFields.passphrase, 'Key passphrase (optional)',
              Icons.password,
              secret: true),
        ];
      case EntryType.passkey:
        return [
          _field(EntryFields.rpId, 'Website (e.g. example.com)', Icons.language,
              keyboard: TextInputType.url),
          _field(EntryFields.passkeyUser, 'User name', Icons.person_outline),
          _field(EntryFields.credentialId, 'Credential ID', Icons.badge_outlined,
              mono: true),
          _field(EntryFields.privateKey, 'Private key', Icons.lock_outline,
              secret: true, maxLines: 6, mono: true),
        ];
      case EntryType.login:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    return Scaffold(
      appBar: AppBar(
        title: Text('${_isNew ? 'Add' : 'Edit'} ${_typeLabel(_entry.type)}'),
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
            ..._typeFields(),
            if (_entry.type == EntryType.login) ...[
              TextFormField(
                controller: _username,
                decoration: InputDecoration(
                  labelText: 'Username / email',
                  prefixIcon: const Icon(Icons.person_outline),
                  suffixIcon: IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy),
                    onPressed: () => state.copyToClipboard(_username.text),
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
            ],
            DropdownButtonFormField<String?>(
              value: _folderId,
              decoration: const InputDecoration(
                labelText: 'Folder',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('No folder')),
                ...state.folders.map((f) => DropdownMenuItem<String?>(
                    value: f.id, child: Text(f.name))),
              ],
              onChanged: (v) => setState(() => _folderId = v),
            ),
            if (_entry.type == EntryType.login) ...[
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
            ],
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
              label: Text('Save ${_typeLabel(_entry.type)}'),
            ),
          ],
        ),
      ),
    );
  }
}
