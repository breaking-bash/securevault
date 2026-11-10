import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/secure_note.dart';
import '../../state/vault_state.dart';

/// Create or edit a secure note. Pass [noteId] to edit, null to create.
class NoteEditScreen extends StatefulWidget {
  final String? noteId;
  const NoteEditScreen({super.key, this.noteId});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late SecureNote _note;
  late bool _isNew;
  late final TextEditingController _title;
  late final TextEditingController _body;
  String? _folderId;

  @override
  void initState() {
    super.initState();
    final state = context.read<VaultState>();
    if (widget.noteId != null) {
      _note = state.notes.firstWhere((n) => n.id == widget.noteId);
      _isNew = false;
    } else {
      _note = state.newNoteDraft();
      _isNew = true;
    }
    _title = TextEditingController(text: _note.title);
    _body = TextEditingController(text: _note.body);
    _folderId = _note.folderId;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<VaultState>();
    _note.title = _title.text.trim();
    _note.body = _body.text;
    _note.folderId = _folderId;
    await state.saveNote(_note, isNew: _isNew);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add secure note' : 'Edit secure note'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete note?'),
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
                if (ok == true) {
                  await state.deleteNote(_note);
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
            ),
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
              controller: _body,
              maxLines: 14,
              minLines: 8,
              decoration: const InputDecoration(
                labelText: 'Note (encrypted)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
