import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/secure_note.dart';
import '../../models/vault_entry.dart';
import '../../state/vault_state.dart';
import '../widgets/generator_sheet.dart';
import 'entry_edit_screen.dart';
import 'entry_detail_screen.dart';
import 'note_edit_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _folderFilter; // null = all

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<VaultEntry> _filteredEntries(VaultState s) {
    final q = _query.toLowerCase();
    return s.entries.where((e) {
      if (_folderFilter != null && e.folderId != _folderFilter) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.username.toLowerCase().contains(q) ||
          e.url.toLowerCase().contains(q) ||
          e.notes.toLowerCase().contains(q);
    }).toList();
  }

  List<SecureNote> _filteredNotes(VaultState s) {
    final q = _query.toLowerCase();
    return s.notes.where((n) {
      if (_folderFilter != null && n.folderId != _folderFilter) return false;
      if (q.isEmpty) return true;
      return n.title.toLowerCase().contains(q) ||
          n.body.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(state.account?.name ?? 'SecureVault'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search titles, usernames, URLs…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                  ),
                ),
              ),
              TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Logins', icon: Icon(Icons.key)),
                  Tab(text: 'Secure notes', icon: Icon(Icons.sticky_note_2_outlined)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Password generator',
            icon: const Icon(Icons.casino_outlined),
            onPressed: () => showGeneratorSheet(context),
          ),
          IconButton(
            tooltip: 'Lock now',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => state.lock(),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'settings') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SettingsScreen()));
              } else if (v == 'signout') {
                state.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'signout', child: Text('Switch account')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _FolderChips(
            selected: _folderFilter,
            onSelect: (id) => setState(() => _folderFilter = id),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _EntryList(entries: _filteredEntries(state)),
                _NoteList(notes: _filteredNotes(state)),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabs.index == 0) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const EntryEditScreen()));
          } else {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NoteEditScreen()));
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabs.index == 0 ? 'Add login' : 'Add note'),
      ),
    );
  }
}

class _FolderChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _FolderChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            ),
          ),
          ...state.folders.map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.name),
                  selected: selected == f.id,
                  onSelected: (_) => onSelect(f.id),
                ),
              )),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Manage'),
              onPressed: () => _manageFolders(context),
            ),
          ),
        ],
      ),
    );
  }

  void _manageFolders(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _FolderManager(),
    );
  }
}

class _FolderManager extends StatefulWidget {
  const _FolderManager();
  @override
  State<_FolderManager> createState() => _FolderManagerState();
}

class _FolderManagerState extends State<_FolderManager> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Folders', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(hintText: 'New folder name'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  if (_ctrl.text.trim().isEmpty) return;
                  await state.createFolder(_ctrl.text);
                  _ctrl.clear();
                },
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.folders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No folders yet.'),
            ),
          ...state.folders.map((f) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final name = await _promptRename(context, f.name);
                        if (name != null && name.trim().isNotEmpty) {
                          await state.renameFolder(f, name);
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => state.deleteFolder(f),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Future<String?> _promptRename(BuildContext context, String current) {
    final ctrl = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  final List<VaultEntry> entries;
  const _EntryList({required this.entries});

  @override
  Widget build(BuildContext context) {
    final state = context.read<VaultState>();
    if (entries.isEmpty) {
      return const _EmptyState(
          icon: Icons.key_off_outlined, text: 'No logins yet');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final e = entries[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(e.title.isEmpty ? '?' : e.title[0].toUpperCase()),
            ),
            title: Text(e.title.isEmpty ? '(untitled)' : e.title),
            subtitle: Text(
              [
                if (e.username.isNotEmpty) e.username,
                if (e.folderId != null) state.folderName(e.folderId),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Copy password',
              icon: const Icon(Icons.copy),
              onPressed: e.password.isEmpty
                  ? null
                  : () {
                      state.copyToClipboard(e.password, sensitive: true);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(state.clipboardClearSeconds > 0
                            ? 'Password copied — clears in ${state.clipboardClearSeconds}s'
                            : 'Password copied'),
                      ));
                    },
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EntryDetailScreen(entryId: e.id))),
          ),
        );
      },
    );
  }
}

class _NoteList extends StatelessWidget {
  final List<SecureNote> notes;
  const _NoteList({required this.notes});

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return const _EmptyState(
          icon: Icons.note_outlined, text: 'No secure notes yet');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final n = notes[i];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
            title: Text(n.title.isEmpty ? '(untitled)' : n.title),
            subtitle: Text(
              n.body.replaceAll('\n', ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => NoteEditScreen(noteId: n.id))),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Theme.of(context).disabledColor)),
          const SizedBox(height: 4),
          const Text('Tap + to add one',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
