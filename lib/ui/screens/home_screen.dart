import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_templates.dart';
import '../../models/secure_note.dart';
import '../../models/vault_entry.dart';
import '../../services/totp_service.dart';
import '../../state/vault_state.dart';
import '../theme.dart';
import '../widgets/generator_sheet.dart';
import '../widgets/type_tile.dart';
import 'entry_detail_screen.dart';
import 'archive_screen.dart';
import 'group_list_screen.dart';
import 'new_item_screen.dart';
import 'note_edit_screen.dart';
import 'settings_screen.dart';
import 'watchtower_screen.dart';

/// App shell: icon-only bottom navigation (Home · Vault · Search · Watchtower).
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
          _HomeTab(),
          _VaultTab(),
          _SearchTab(),
          WatchtowerScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: _tab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              tooltip: 'Home',
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.description_outlined),
              selectedIcon: Icon(Icons.description),
              tooltip: 'Vault',
              label: 'Vault'),
          NavigationDestination(
              icon: Icon(Icons.search),
              selectedIcon: Icon(Icons.search),
              tooltip: 'Search',
              label: 'Search'),
          NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield),
              tooltip: 'Watchtower',
              label: 'Watchtower'),
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
  final _scroll = ScrollController();
  bool _extended = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final ext = _scroll.offset < 24;
      if (ext != _extended) setState(() => _extended = ext);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<VaultEntry> _matchEntries(VaultState s) {
    final q = _query.toLowerCase();
    return s.activeEntries
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      floatingActionButton: _NewItemFab(extended: _extended),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            titleSpacing: 20,
            title: const Text('Vault',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            actions: [
              Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _profileMenu(context, state)),
            ],
          ),          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none),
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
            trailing: Text(
                '${state.activeEntries.length + state.notes.length} items'),
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
        ],
      ),
    );
  }

  // ---- grouped overview (TYPES / FOLDERS / NO FOLDER) ----
  List<Widget> _grouped(BuildContext context, VaultState state) {
    bool show(String k) => !state.settings.hiddenHomeSections.contains(k);
    final noFolderEntries =
        state.activeEntries.where((e) => e.folderId == null).toList();
    final noFolderNotes = state.notes.where((n) => n.folderId == null).toList();
    final noFolderCount = noFolderEntries.length + noFolderNotes.length;
    final typeCount = ItemTemplates.pickerOrder
            .where((t) => state.activeEntries.any((e) => e.type == t))
            .length +
        (state.notes.isEmpty ? 0 : 1);

    return [
      if (show('tags') && state.allTags.isNotEmpty) ...[
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
      if (show('categories')) _SectionHeader('CATEGORIES', typeCount),
      if (show('categories'))
      SliverToBoxAdapter(child: _Group(children: [
      for (final t in ItemTemplates.pickerOrder)
        if (state.activeEntries.any((e) => e.type == t))
            _VaultRow(
              icon: ItemTemplates.of(t).icon,
              color: ItemTemplates.of(t).color,
              label: ItemTemplates.of(t).label,
              count: state.activeEntries.where((e) => e.type == t).length,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GroupListScreen(
                    title: ItemTemplates.of(t).label,
                    filter: GroupFilter.type,
                    entryType: t),
              )),
            ),
      if (state.notes.isNotEmpty)
          _VaultRow(
            icon: Icons.sticky_note_2_outlined,
            color: ItemTemplates.noteColor,
            label: 'Secure Note',
            count: state.notes.length,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const GroupListScreen(
                  title: 'Secure Note', filter: GroupFilter.notes),
            )),
          ),
      ])),
      if (show('folders')) _SectionHeader('FOLDERS', state.folders.length),
      if (show('folders') && state.folders.isNotEmpty)
      SliverToBoxAdapter(child: _Group(children: state.folders.map((f) {
        final count = state.activeEntries.where((e) => e.folderId == f.id).length +
            state.notes.where((n) => n.folderId == f.id).length;
        return _VaultRow(
            icon: Icons.folder_outlined,
            color: const Color(0xFF6B7A90),
            label: f.name,
            count: count,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupListScreen(
                  title: f.name, filter: GroupFilter.folder, folderId: f.id),
            )),
        );
      }).toList())),
      if (show('noFolder')) _SectionHeader('NO FOLDER', noFolderCount),
      if (show('noFolder') && noFolderCount == 0)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Nothing here yet — tap New Item to add one.'),
          ),
        ),
      if (show('noFolder') && noFolderCount > 0)
      SliverToBoxAdapter(child: _Group(children: [
        ...noFolderEntries.map((e) => _EntryRow(entry: e)),
        ...noFolderNotes.map((n) => _NoteRow(note: n)),
      ])),
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
      if (entries.isNotEmpty)
        SliverToBoxAdapter(
            child: _Group(children: entries.map((e) => _EntryRow(entry: e)).toList())),
      if (notes.isNotEmpty) _SectionHeader('SECURE NOTES', notes.length),
      if (notes.isNotEmpty)
        SliverToBoxAdapter(
            child: _Group(children: notes.map((n) => _NoteRow(note: n)).toList())),
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

/// Rounded inset card that joins rows with hairline dividers (1Password style).
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 0, indent: 68),
            children[i],
          ],
        ]),
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
    return ListTile(
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
    return ListTile(
          leading: TypeTile(
              icon: ItemTemplates.of(entry.type).icon,
              color: ItemTemplates.of(entry.type).color,
              url: entry.type == EntryType.login ? entry.url : null),
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
    );
  }
}

/// A secure-note row (list item).
class _NoteRow extends StatelessWidget {
  final SecureNote note;
  const _NoteRow({required this.note});

  @override
  Widget build(BuildContext context) {
    return ListTile(
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


class _CustomizeHome extends StatelessWidget {
  const _CustomizeHome();

  static const _sections = {
    'pinned': 'Pinned fields',
    'recent': 'Recently used & modified',
    'tags': 'Tags',
    'categories': 'Categories',
    'folders': 'Folders',
    'noFolder': 'Items without a folder',
  };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Customize home',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Choose what appears on your home screen'),
          ),
          for (final e in _sections.entries)
            SwitchListTile(
              title: Text(e.value),
              value: !state.settings.hiddenHomeSections.contains(e.key),
              onChanged: (v) {
                final s = state.settings;
                final hidden = {...s.hiddenHomeSections};
                v ? hidden.remove(e.key) : hidden.add(e.key);
                s.hiddenHomeSections = hidden;
                state.updateSettings(s);
              },
            ),
        ],
      ),
    );
  }
}
Widget _profileMenu(BuildContext context, VaultState state) {
  return PopupMenuButton<String>(
    tooltip: 'Settings',
    offset: const Offset(0, 48),
    child: _Avatar(state.account?.name),
    onSelected: (v) {
      final nav = Navigator.of(context);
      switch (v) {
        case 'generator':
          nav.push(MaterialPageRoute(builder: (_) => const _GeneratorTab()));
        case 'settings':
          nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        case 'customize':
          showModalBottomSheet(
            context: context,
            showDragHandle: true,
            builder: (_) => const _CustomizeHome(),
          );
        case 'archive':
          nav.push(MaterialPageRoute(builder: (_) => const ArchiveScreen()));
        case 'trash':
          nav.push(MaterialPageRoute(
              builder: (_) => const ArchiveScreen(trash: true)));
        case 'folders':
          showModalBottomSheet(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => const FolderManager(),
          );
        case 'switch':
          state.signOut();
        case 'lock':
          state.lock();
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(
          value: 'generator',
          child: ListTile(
              leading: Icon(Icons.autorenew), title: Text('Generator'))),
      PopupMenuItem(
          value: 'settings',
          child: ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Settings'))),
      PopupMenuItem(
          value: 'customize',
          child: ListTile(
              leading: Icon(Icons.tune), title: Text('Customize home'))),
      PopupMenuItem(
          value: 'archive',
          child: ListTile(
              leading: Icon(Icons.archive_outlined), title: Text('Archive'))),
      PopupMenuItem(
          value: 'trash',
          child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Recently Deleted'))),
      PopupMenuItem(
          value: 'folders',
          child: ListTile(
              leading: Icon(Icons.create_new_folder_outlined),
              title: Text('Manage folders'))),
      PopupMenuDivider(),
      PopupMenuItem(
          value: 'switch',
          child: ListTile(
              leading: Icon(Icons.switch_account_outlined),
              title: Text('Switch account'))),
      PopupMenuItem(
          value: 'lock',
          child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Lock vault now'))),
    ],
  );
}


/// Rounded-square profile avatar (top-right of every main screen).
class _Avatar extends StatelessWidget {
  final String? name;
  const _Avatar(this.name);

  @override
  Widget build(BuildContext context) {
    final n = (name ?? '').trim();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7FE3C2), Color(0xFF3FA7E6)],
        ),
      ),
      child: Text(n.isEmpty ? 'V' : n.characters.first.toUpperCase(),
          style: const TextStyle(
              color: Color(0xFF0B2A3A),
              fontSize: 18,
              fontWeight: FontWeight.w800)),
    );
  }
}

// ---------------------------------------------------------------- Home tab
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final scheme = Theme.of(context).colorScheme;
    bool show(String k) => !state.settings.hiddenHomeSections.contains(k);
    final all = state.activeEntries;
    final byId = {for (final e in all) e.id: e};
    final used = [
      for (final id in state.settings.recentIds)
        if (byId[id] != null) byId[id]!
    ].take(4).toList();
    final modified = ([...all]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
        .take(4)
        .toList();
    final pinned = [
      ...all.where((e) => (e.totp ?? '').isNotEmpty),
      ...all.where((e) =>
          (e.totp ?? '').isEmpty &&
          e.type == EntryType.login &&
          e.password.isNotEmpty),
    ].take(6).toList();

    return Scaffold(
      floatingActionButton: const _NewItemFab(extended: true),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
              child: Row(children: [
                const Expanded(
                  child: Text('Home',
                      style:
                          TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                ),
                _profileMenu(context, state),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text(state.account?.name ?? 'Vault',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            if (show('pinned') && pinned.isNotEmpty)
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: pinned.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _PinnedCard(entry: pinned[i]),
                ),
              ),
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text('Your vault is empty.\nTap New Item to add a login.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ),
            if (show('recent') && used.isNotEmpty)
              _CollapsibleCard(
                title: 'Recently Used',
                icon: Icons.history,
                tint: const Color(0xFF7EF0E6),
                entries: used,
              ),
            if (show('recent') && modified.isNotEmpty)
              _CollapsibleCard(
                title: 'Recently Modified',
                icon: Icons.sync,
                tint: const Color(0xFFD9A8F0),
                entries: modified,
              ),
          ],
        ),
      ),
    );
  }
}

/// Blue rounded "+ New Item" button shared by Home and Vault.
class _NewItemFab extends StatelessWidget {
  final bool extended;
  const _NewItemFab({required this.extended});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const NewItemScreen())),
      icon: const Icon(Icons.add),
      isExtended: extended,
      label: const Text('New Item'),
    );
  }
}

class _PinnedCard extends StatefulWidget {
  final VaultEntry entry;
  const _PinnedCard({required this.entry});

  @override
  State<_PinnedCard> createState() => _PinnedCardState();
}

class _PinnedCardState extends State<_PinnedCard> {
  Timer? _timer;
  TotpConfig? _cfg;

  @override
  void initState() {
    super.initState();
    final t = widget.entry.totp ?? '';
    if (t.isNotEmpty) {
      _cfg = TotpService.fromStored(t);
      _timer = Timer.periodic(
          const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _spaced(String c) => c.length == 6
      ? '${c.substring(0, 3)} \u2022 ${c.substring(3)}'
      : c;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final scheme = Theme.of(context).colorScheme;
    final tpl = ItemTemplates.of(e.type);
    final otp = _cfg != null;
    final label = otp ? 'one-time password' : 'password';
    Widget value;
    if (otp) {
      final left = TotpService.secondsRemaining(_cfg!.period);
      value = Row(children: [
        Text(_spaced(TotpService.generate(_cfg!)),
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
          decoration: BoxDecoration(
              color: scheme.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                value: left / _cfg!.period,
                strokeWidth: 3,
                color: left <= 5 ? Colors.red : const Color(0xFF1E8E3E),
                backgroundColor: scheme.outlineVariant,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 16,
              child: Text('$left',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ]),
        ),
      ]);
    } else {
      value = Text('\u2022' * 10,
          style: const TextStyle(fontSize: 18, letterSpacing: 2));
    }
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final state = context.read<VaultState>();
          final secret = otp
              ? TotpService.generate(_cfg!)
              : e.password;
          state.copyToClipboard(secret, sensitive: true);
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${e.title} $label copied')));
        },
        child: Container(
          width: 210,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                TypeTile(
                    icon: tpl.icon,
                    color: tpl.color,
                    size: 22,
                    url: e.type == EntryType.login ? e.url : null),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.title.isEmpty ? '(untitled)' : e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16)),
                ),
              ]),
              const Spacer(),
              Text(label,
                  style: TextStyle(
                      fontSize: 14, color: fieldLabelColor(context))),
              const SizedBox(height: 2),
              value,
            ],
          ),
        ),
      ),
    );
  }
}

/// "Recently Used" / "Recently Modified" collapsible card.
class _CollapsibleCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color tint;
  final List<VaultEntry> entries;
  const _CollapsibleCard(
      {required this.title,
      required this.icon,
      required this.tint,
      required this.entries});

  @override
  State<_CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<_CollapsibleCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: widget.tint,
                  child: Icon(widget.icon, color: const Color(0xFF16323A)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: scheme.primary, size: 28),
              ]),
            ),
          ),
          if (_open)
            for (final e in widget.entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: TypeTile(
                    icon: ItemTemplates.of(e.type).icon,
                    color: ItemTemplates.of(e.type).color,
                    url: e.type == EntryType.login ? e.url : null),
                title: Text(e.title.isEmpty ? '(untitled)' : e.title,
                    style: const TextStyle(fontSize: 17)),
                subtitle: e.subtitle.isEmpty ? null : Text(e.subtitle),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EntryDetailScreen(entryId: e.id))),
              ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------------- Search tab
class _SearchTab extends StatefulWidget {
  const _SearchTab();

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final q = _q.trim().toLowerCase();
    final entries = q.isEmpty
        ? <VaultEntry>[]
        : state.activeEntries
            .where((e) =>
                e.title.toLowerCase().contains(q) ||
                e.username.toLowerCase().contains(q) ||
                e.url.toLowerCase().contains(q) ||
                e.subtitle.toLowerCase().contains(q) ||
                e.tags.any((t) => t.contains(q)))
            .toList();
    final notes = q.isEmpty
        ? <SecureNote>[]
        : state.notes
            .where((n) =>
                n.title.toLowerCase().contains(q) ||
                n.body.toLowerCase().contains(q))
            .toList();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: 'Search in all vaults',
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _profileMenu(context, state),
              ]),
            ),
            if (q.isEmpty)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: Text('Search titles, usernames, sites and tags')),
              )
            else if (entries.isEmpty && notes.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: Text('No matches')))
            else
              _Group(children: [
                ...entries.map((e) => _EntryRow(entry: e)),
                ...notes.map((n) => _NoteRow(note: n)),
              ]),
          ],
        ),
      ),
    );
  }
}