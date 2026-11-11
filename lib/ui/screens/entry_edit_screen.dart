import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_templates.dart';
import '../../models/vault_entry.dart';
import '../../services/ssh_key_service.dart';
import '../../services/totp_service.dart';
import '../../state/vault_state.dart';
import '../widgets/generator_sheet.dart';
import 'totp_scan_screen.dart';

class _CustomRow {
  final CustomField field;
  final TextEditingController label;
  final TextEditingController value;
  bool reveal = false;
  _CustomRow(this.field)
      : label = TextEditingController(text: field.label),
        value = TextEditingController(text: field.value);
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

/// Create or edit an item. Pass [entryId] to edit, or null to create.
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
  late final ItemTemplate _tpl;
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _url;
  late final TextEditingController _notes;
  late final TextEditingController _totp;
  final _tagInput = TextEditingController();
  final Map<String, TextEditingController> _extra = {};
  final Set<String> _revealed = {};
  final List<_CustomRow> _custom = [];
  late List<String> _tags;
  late List<Attachment> _files;
  String? _folderId;
  String? _signIn;
  bool _obscure = true;
  bool _showTotp = false;

  bool get _isLogin => _entry.type == EntryType.login;

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
    _tpl = ItemTemplates.of(_entry.type);
    _title = TextEditingController(text: _entry.title);
    _username = TextEditingController(text: _entry.username);
    _password = TextEditingController(text: _entry.password);
    _url = TextEditingController(text: _entry.url);
    _notes = TextEditingController(text: _entry.notes);
    _totp = TextEditingController(text: _entry.totp ?? '');
    for (final f in _tpl.fields) {
      _extra[f.key] = TextEditingController(text: _entry.extra[f.key] ?? '');
    }
    for (final c in _entry.customFields) {
      _custom.add(_CustomRow(
          CustomField(label: c.label, kind: c.kind, value: c.value)));
    }
    _tags = List.of(_entry.tags);
    _files = List.of(_entry.attachments);
    _folderId = _entry.folderId;
    _showTotp = (_entry.totp ?? '').isNotEmpty;
    final s = _entry.extra[ItemTemplates.signInKey];
    _signIn = (s == null || s.isEmpty) ? null : s;
  }

  @override
  void dispose() {
    for (final c in [_title, _username, _password, _url, _notes, _totp]) {
      c.dispose();
    }
    _tagInput.dispose();
    for (final c in _extra.values) {
      c.dispose();
    }
    for (final r in _custom) {
      r.dispose();
    }
    super.dispose();
  }

  // QR scanning needs a camera — only offered on Android/iOS.
  bool get _canScan => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _scanTotp(TextEditingController target) async {
    final config = await Navigator.of(context).push<TotpConfig>(
      MaterialPageRoute(builder: (_) => const TotpScanScreen()),
    );
    if (config == null || !mounted) return;
    setState(() => target.text = config.secret);
    final who = config.issuer ?? config.account;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(who == null ? 'TOTP secret added' : 'TOTP added for $who'),
    ));
  }

  Future<void> _pickDate(TextEditingController c) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(c.text) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (d != null) {
      setState(() => c.text =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _generateSshKey() async {
    final key = await SshKeyService.instance
        .generateEd25519(comment: _title.text.trim());
    if (!mounted) return;
    setState(() {
      _extra[EntryFields.publicKey]?.text = key.publicKey;
      _extra[EntryFields.privateKey]?.text = key.privateKey;
      _extra[EntryFields.fingerprint]?.text = key.fingerprint;
    });
  }

  Future<void> _attach() async {
    final res = await FilePicker.pickFiles(withData: true, allowMultiple: true);
    if (res == null || !mounted) return;
    final skipped = <String>[];
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      if (bytes.length > Attachment.maxBytes) {
        skipped.add(f.name);
        continue;
      }
      _files.add(Attachment(
        id: DateTime.now().microsecondsSinceEpoch.toString() +
            _files.length.toString(),
        name: f.name,
        data: base64Encode(bytes),
      ));
    }
    setState(() {});
    if (skipped.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Too large (max 5 MB): ${skipped.join(', ')}'),
      ));
    }
  }

  void _addTag([String? raw]) {
    final t = (raw ?? _tagInput.text).trim().toLowerCase();
    if (t.isEmpty) return;
    if (!_tags.contains(t)) setState(() => _tags.add(t));
    _tagInput.clear();
  }

  Future<void> _addCustomField() async {
    final kind = await showModalBottomSheet<FieldKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Add more',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final k in FieldKindInfo.customKinds)
              ListTile(
                leading: Icon(k.icon),
                title: Text(k.label),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    // A login's first one-time password is its main TOTP field.
    if (kind == FieldKind.otp && _isLogin && !_showTotp) {
      setState(() => _showTotp = true);
      return;
    }
    setState(() => _custom.add(_CustomRow(CustomField(
        label: kind == FieldKind.text ? 'text' : kind.label.toLowerCase(),
        kind: kind))));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<VaultState>();
    _entry.title = _title.text.trim();
    if (_isLogin) {
      _entry.username = _username.text;
      _entry.password = _password.text;
      _entry.url = _url.text.trim();
      _entry.totp = _totp.text.trim().isEmpty ? null : _totp.text.trim();
    }
    _entry.notes = _notes.text;
    _entry.folderId = _folderId;
    _entry.extra = {
      for (final f in _tpl.fields)
        if (_extra[f.key]!.text.trim().isNotEmpty)
          f.key: _extra[f.key]!.text.trim(),
      if (_isLogin && _signIn != null) ItemTemplates.signInKey: _signIn!,
    };
    _entry.customFields = [
      for (final r in _custom)
        if (r.value.text.isNotEmpty || r.label.text.trim().isNotEmpty)
          CustomField(
              label: r.label.text.trim(),
              kind: r.field.kind,
              value: r.value.text.trim()),
    ];
    _addTag();
    _entry.tags = List.of(_tags);
    _entry.attachments = List.of(_files);
    await state.saveEntry(_entry, isNew: _isNew);
    if (mounted) Navigator.of(context).pop();
  }

  InputDecoration _deco(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
          labelText: label, prefixIcon: Icon(icon), suffixIcon: suffix);

  Widget _kindField({
    required TextEditingController controller,
    required String label,
    required FieldKind kind,
    required bool reveal,
    required VoidCallback onToggle,
    bool masked = false,
    bool mono = false,
    int maxLines = 1,
  }) {
    if (kind == FieldKind.date) {
      return TextFormField(
        controller: controller,
        readOnly: true,
        onTap: () => _pickDate(controller),
        decoration: _deco(label, kind.icon,
            suffix: controller.text.isEmpty
                ? const Icon(Icons.calendar_today, size: 18)
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(controller.clear),
                  )),
      );
    }
    final hide = masked && !reveal;
    final actions = <Widget>[
      if (masked)
        IconButton(
          tooltip: hide ? 'Show' : 'Hide',
          icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggle,
        ),
      if (kind == FieldKind.otp && _canScan)
        IconButton(
          tooltip: 'Scan QR code',
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: () => _scanTotp(controller),
        ),
      if (kind == FieldKind.password)
        IconButton(
          tooltip: 'Generate',
          icon: const Icon(Icons.casino_outlined),
          onPressed: () => showGeneratorSheet(context,
              onUse: (pw) => setState(() => controller.text = pw)),
        ),
    ];
    return TextFormField(
      controller: controller,
      obscureText: hide,
      maxLines: hide ? 1 : maxLines,
      keyboardType: kind.keyboard,
      autocorrect: !masked,
      enableSuggestions: !masked,
      style: mono ? const TextStyle(fontFamily: 'monospace') : null,
      decoration: _deco(label, kind.icon,
          suffix: actions.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: actions)),
    );
  }

  Widget _card(List<Widget> children, {String? header}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (header != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(header.toUpperCase(),
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      );

  List<Widget> _loginFields(VaultState state) => [
        TextFormField(
          controller: _username,
          keyboardType: TextInputType.emailAddress,
          decoration: _deco('Username / email', Icons.person_outline,
              suffix: IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy),
                onPressed: () => state.copyToClipboard(_username.text),
              )),
        ),
        _kindField(
          controller: _password,
          label: 'Password',
          kind: FieldKind.password,
          masked: true,
          reveal: !_obscure,
          onToggle: () => setState(() => _obscure = !_obscure),
        ),
        if (_showTotp)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _kindField(
                  controller: _totp,
                  label: 'One-time password (TOTP secret)',
                  kind: FieldKind.otp,
                  masked: true,
                  reveal: _revealed.contains('_totp'),
                  onToggle: () => setState(() => _revealed.contains('_totp')
                      ? _revealed.remove('_totp')
                      : _revealed.add('_totp')),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() {
                  _totp.clear();
                  _showTotp = false;
                }),
              ),
            ],
          ),
        TextFormField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: _deco('Website (URL)', Icons.link),
        ),
        DropdownButtonFormField<String?>(
          initialValue: _signIn,
          decoration: _deco('Sign in with', Icons.account_circle_outlined),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('None')),
            for (final p in ItemTemplates.signInProviders)
              DropdownMenuItem<String?>(value: p, child: Text(p)),
          ],
          onChanged: (v) => setState(() => _signIn = v),
        ),
      ];

  List<Widget> _templateFields() => [
        if (_entry.type == EntryType.ssh)
          OutlinedButton.icon(
            onPressed: _generateSshKey,
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('Generate Ed25519 key pair'),
          ),
        for (final f in _tpl.fields)
          _kindField(
            controller: _extra[f.key]!,
            label: f.label,
            kind: f.kind,
            masked: f.masked,
            mono: f.mono,
            maxLines: f.maxLines,
            reveal: _revealed.contains(f.key),
            onToggle: () => setState(() => _revealed.contains(f.key)
                ? _revealed.remove(f.key)
                : _revealed.add(f.key)),
          ),
      ];

  Widget _customRow(_CustomRow r) {
    final secret = r.field.kind.isSecretByDefault;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: r.label,
            decoration: InputDecoration(
              labelText: 'Label',
              prefixIcon: Icon(r.field.kind.icon),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: _kindField(
            controller: r.value,
            label: 'Value',
            kind: r.field.kind,
            masked: secret,
            reveal: r.reveal,
            onToggle: () => setState(() => r.reveal = !r.reveal),
          ),
        ),
        IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => setState(() {
            _custom.remove(r);
            r.dispose();
          }),
        ),
      ],
    );
  }

  static String _size(int b) => b < 1024
      ? '$b B'
      : b < 1024 * 1024
          ? '${(b / 1024).toStringAsFixed(1)} KB'
          : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final suggestions =
        state.allTags.where((t) => !_tags.contains(t)).take(8).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('${_isNew ? 'New' : 'Edit'} ${_tpl.label}'),
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
            _card([
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _tpl.color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_tpl.icon, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _title,
                      textCapitalization: TextCapitalization.sentences,
                      style: Theme.of(context).textTheme.titleMedium,
                      decoration: const InputDecoration(labelText: 'Title *'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Title is required'
                          : null,
                    ),
                  ),
                ],
              ),
            ]),
            _card(_isLogin ? _loginFields(state) : _templateFields()),
            _card([
              for (final r in _custom) _customRow(r),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addCustomField,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add more'),
                ),
              ),
            ], header: 'More fields'),
            _card([
              TextFormField(
                controller: _notes,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ]),
            _card([
              if (_tags.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final t in _tags)
                      InputChip(
                        label: Text(t),
                        onDeleted: () => setState(() => _tags.remove(t)),
                      ),
                  ],
                ),
              TextField(
                controller: _tagInput,
                textInputAction: TextInputAction.done,
                onSubmitted: _addTag,
                decoration: _deco('Add tag', Icons.sell_outlined,
                    suffix: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _addTag,
                    )),
              ),
              if (suggestions.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in suggestions)
                      ActionChip(label: Text(t), onPressed: () => _addTag(t)),
                  ],
                ),
            ], header: 'Tags'),
            _card([
              for (final a in _files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file),
                  title: Text(a.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_size(a.size)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _files.remove(a)),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _attach,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach a file'),
                ),
              ),
            ], header: 'Attachments'),
            _card([
              DropdownButtonFormField<String?>(
                initialValue: _folderId,
                decoration: _deco('Folder', Icons.folder_outlined),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('No folder')),
                  ...state.folders.map((f) => DropdownMenuItem<String?>(
                      value: f.id, child: Text(f.name))),
                ],
                onChanged: (v) => setState(() => _folderId = v),
              ),
            ]),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text('Save ${_tpl.label.toLowerCase()}'),
            ),
          ],
        ),
      ),
    );
  }
}
