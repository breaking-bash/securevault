import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_templates.dart';
import '../../models/secure_note.dart';
import '../../models/vault_entry.dart';
import '../../state/vault_state.dart';
import '../widgets/generator_sheet.dart';
import '../widgets/type_tile.dart';
import 'entry_detail_screen.dart';
import 'group_list_screen.dart';
import 'new_item_screen.dart';
import 'note_edit_screen.dart';
import 'settings_screen.dart';
import 'watchtower_screen.dart';

/// App shell: a 4-tab bottom navigation (Vault · Generator · Watchtower · Settings).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          _VaultTab(),
          _GeneratorTab(),
          WatchtowerScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.lock_outline),
              selectedIcon: Icon(Icons.lock),
              label: 'Vault'),
          NavigationDestination(
              icon: Icon(Icons.autorenew_outlined),
              selectedIcon: Icon(Icons.autorenew),
              label: 'Generator'),
          NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield),
              label: 'Watchtower'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Vault tab
class _VaultTab extends StatefulWidget {
  const _VaultTab();

  @override
  State<_VaultTab> createState() => _VaultTabState();
}

class _VaultTabState extends State<_VaultTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<VaultEntry> _matchEntries(VaultState s) {
    final q = _query.toLowerCase();
    return s.entries
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.username.toLowerCase().contains(q) ||
            e.url.toLowerCase().contains(q) ||
            e.subtitle.toLowerCase().contains(q) ||
            e.notes.toLowerCase().contains(q) ||
            e.tags.any((t) => t.contains(q)))
        .toList();
  }

  List<SecureNote> _matchNotes(VaultState s) {
    final q = _query.toLowerCase();
    return s.notes
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.body.toLowerCase().contains(q))
        .toList();
  }

  void _add(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NewItemScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('New Item'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(state.account?.name ?? 'Vault'),
            actions: [
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_horiz),
                onPressed: () => _showOverflow(context, state),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search',
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
          ),
          if (!searching) _filterRow(context, state),
          if (searching)
            ..._searchResults(context, state)
          else
            ..._grouped(context, state),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  Widget _filterRow(BuildContext context, VaultState state) {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          ListTile(
            title: const Text('Vault: All'),
            trailing: IconButton(
              icon: const Icon(Icons.more_horiz),
              tooltip: 'More',
              onPressed: () => _showOverflow(context, state),
            ),
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
        ],
      ),
    );
  }

  void _showOverflow(BuildContext context, VaultState state) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Manage folders'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => const FolderManager(),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.switch_account_outlined),
              title: const Text('Switch account'),
              onTap: () {
                Navigator.pop(context);
                state.signOut();
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Lock vault now'),
              onTap: () {
                Navigator.pop(context);
                state.lock();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---- grouped overview (TYPES / FOLDERS / NO FOLDER) ----
  List<Widget> _grouped(BuildContext context, VaultState state) {
    final noFolderEntries =
        state.entries.where((e) => e.folderId == null).toList();
    final noFolderNotes = state.notes.where((n) => n.folderId == null).toList();
    final noFolderCount = noFolderEntries.length + noFolderNotes.length;
    final typeCount = ItemTemplates.pickerOrder
            .where((t) => state.entries.any((e) => e.type == t))
            .length +
        (state.notes.isEmpty ? 0 : 1);

    return [
      if (state.allTags.isNotEmpty) ...[
        _SectionHeader('TAGS', state.allTags.length),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in state.allTags)
                  ActionChip(
                    avatar: const Icon(Icons.sell_outlined, size: 16),
                    label: Text(t),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => GroupListScreen(
                                title: '#$t',
                                filter: GroupFilter.tag,
                                tag: t))),
                  ),
              ],
            ),
          ),
        ),
      ],
      _SectionHeader('CATEGORIES', typeCount),
      for (final t in ItemTemplates.pickerOrder)
        if (state.entries.any((e) => e.type == t))
          SliverToBoxAdapter(
            child: _VaultRow(
              icon: ItemTemplates.of(t).icon,
              color: ItemTemplates.of(t).color,
              label: ItemTemplates.of(t).label,
              count: state.entries.where((e) => e.type == t).length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GroupListScreen(
                    title: ItemTemplates.of(t).label,
                    filter: GroupFilter.type,
                    entryType: t),
              )),
            ),
          ),
      if (state.notes.isNotEmpty)
        SliverToBoxAdapter(
          child: _VaultRow(
            icon: Icons.sticky_note_2_outlined,
            color: ItemTemplates.noteColor,
            label: 'Secure Note',
            count: state.notes.length,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const GroupListScreen(
                  title: 'Secure Note', filter: GroupFilter.notes),
            )),
          ),
        ),
      _SectionHeader('FOLDERS', state.folders.length),
      ...state.folders.map((f) {
        final count = state.entries.where((e) => e.folderId == f.id).length +
            state.notes.where((n) => n.folderId == f.id).length;
        return SliverToBoxAdapter(
          child: _VaultRow(
            icon: Icons.folder_outlined,
            color: const Color(0xFF6B7A90),
            label: f.name,
            count: count,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupListScreen(
                  title: f.name, filter: GroupFilter.folder, folderId: f.id),
            )),
          ),
        );
      }),
      _SectionHeader('NO FOLDER', noFolderCount),
      if (noFolderCount == 0)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Nothing here yet — tap New Item to add one.'),
          ),
        ),
      SliverList.list(children: [
        ...noFolderEntries.map((e) => _EntryRow(entry: e)),
        ...noFolderNotes.map((n) => _NoteRow(note: n)),
      ]),
    ];
  }

  // ---- flat search results ----
  List<Widget> _searchResults(BuildContext context, VaultState state) {
    final entries = _matchEntries(state);
    final notes = _matchNotes(state);
    if (entries.isEmpty && notes.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No matches')),
          ),
        ),
      ];
    }
    return [
      if (entries.isNotEmpty) _SectionHeader('ITEMS', entries.length),
      SliverList.list(
          children: entries.map((e) => _EntryRow(entry: e)).toList()),
      if (notes.isNotEmpty) _SectionHeader('SECURE NOTES', notes.length),
      SliverList.list(children: notes.map((n) => _NoteRow(note: n)).toList()),
    ];
  }
}

// ------------------------------------------------------------- Generator tab
class _GeneratorTab extends StatelessWidget {
  const _GeneratorTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generator')),
      body: const SafeArea(child: GeneratorPanel()),
    );
  }
}

// ----------------------------------------------------------- shared widgets
/// Uppercase grey section header with a count, as a sliver.
class _SectionHeader extends StatelessWidget {
  final String text;
  final int count;
  const _SectionHeader(this.text, this.count);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          '$text ($count)',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// A group/type/folder row: leading outline icon, label, trailing count + chevron.
class _VaultRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final VoidCallback onTap;
  const _VaultRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          leading: TypeTile(icon: icon, color: color, size: 36),
          title: Text(label),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$count', style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
          onTap: onTap,
        ),
        const Divider(height: 0, indent: 16, endIndent: 16),
      ],
    );
  }
}

/// A login entry row (list item) with a quick copy-password action.
class _EntryRow extends StatelessWidget {
  final VaultEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final state = context.read<VaultState>();
    return Column(
      children: [
        ListTile(
          leading: TypeTile(
              icon: ItemTemplates.of(entry.type).icon,
              color: ItemTemplates.of(entry.type).color),
          title: Text(entry.title.isEmpty ? '(untitled)' : entry.title),
          subtitle: entry.subtitle.isEmpty
              ? null
              : Text(entry.subtitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: entry.type != EntryType.login || entry.password.isEmpty
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  tooltip: 'Copy password',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    state.copyToClipboard(entry.password, sensitive: true);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(state.clipboardClearSeconds > 0
                          ? 'Password copied — clears in ${state.clipboardClearSeconds}s'
                          : 'Password copied'),
                    ));
                  },
                ),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EntryDetailScreen(entryId: entry.id))),
        ),
        const Divider(height: 0, indent: 16, endIndent: 16),
      ],
    );
  }
}

/// A secure-note row (list item).
class _NoteRow extends StatelessWidget {
  final SecureNote note;
  const _NoteRow({required this.note});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const TypeTile(
              icon: Icons.sticky_note_2_outlined,
              color: ItemTemplates.noteColor),
          title: Text(note.title.isEmpty ? '(untitled)' : note.title),
          subtitle: note.body.isEmpty
              ? null
              : Text(note.body.replaceAll('\n', ' '),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => NoteEditScreen(noteId: note.id))),
        ),
        const Divider(height: 0, indent: 16, endIndent: 16),
      ],
    );
  }
}

// --------------------------------------------------------- folder management
/// Create / rename / delete folders. Shown as a modal bottom sheet.
class FolderManager extends StatefulWidget {
  const FolderManager({super.key});
  @override
  State<FolderManager> createState() => _FolderManagerState();
}

class _FolderManagerState extends State<FolderManager> {
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
                  decoration:
                      const InputDecoration(hintText: 'New folder name'),
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
