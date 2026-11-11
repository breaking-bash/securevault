import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_templates.dart';
import '../../models/secure_note.dart';
import '../../models/vault_entry.dart';
import '../../state/vault_state.dart';
import '../widgets/type_tile.dart';
import 'entry_detail_screen.dart';
import 'note_edit_screen.dart';

enum GroupFilter { type, notes, folder, tag }

/// A filtered list of vault items (a category, folder or tag), shown as simple
/// divider-separated rows - the drill-down from the grouped vault overview.
class GroupListScreen extends StatelessWidget {
  final String title;
  final GroupFilter filter;
  final String? folderId;
  final EntryType? entryType;
  final String? tag;

  const GroupListScreen({
    super.key,
    required this.title,
    required this.filter,
    this.folderId,
    this.entryType,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();

    List<VaultEntry> entries;
    List<SecureNote> notes;
    switch (filter) {
      case GroupFilter.type:
        entries = state.entries.where((e) => e.type == entryType).toList();
        notes = const [];
        break;
      case GroupFilter.notes:
        entries = const [];
        notes = state.notes;
        break;
      case GroupFilter.folder:
        entries = state.entries.where((e) => e.folderId == folderId).toList();
        notes = state.notes.where((n) => n.folderId == folderId).toList();
        break;
      case GroupFilter.tag:
        entries = state.entries.where((e) => e.tags.contains(tag)).toList();
        notes = const [];
        break;
    }

    final empty = entries.isEmpty && notes.isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: empty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 56, color: Theme.of(context).disabledColor),
                  const SizedBox(height: 12),
                  Text('Nothing here yet',
                      style:
                          TextStyle(color: Theme.of(context).disabledColor)),
                ],
              ),
            )
          : ListView(
              children: [
                for (final e in entries)
                  _Row(
                    icon: ItemTemplates.of(e.type).icon,
                    color: ItemTemplates.of(e.type).color,
                    title: e.title.isEmpty ? '(untitled)' : e.title,
                    subtitle: e.subtitle,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => EntryDetailScreen(entryId: e.id))),
                  ),
                for (final n in notes)
                  _Row(
                    icon: Icons.sticky_note_2_outlined,
                    color: ItemTemplates.noteColor,
                    title: n.title.isEmpty ? '(untitled)' : n.title,
                    subtitle: n.body.replaceAll('\n', ' '),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => NoteEditScreen(noteId: n.id))),
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: TypeTile(icon: icon, color: color),
          title: Text(title),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        const Divider(height: 0, indent: 72, endIndent: 16),
      ],
    );
  }
}
