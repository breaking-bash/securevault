import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_templates.dart';
import '../../models/vault_entry.dart';
import '../../state/vault_state.dart';
import 'entry_detail_screen.dart';

/// Lists archived items, or items in Recently Deleted (kept 30 days).
class ArchiveScreen extends StatelessWidget {
  final bool trash;
  const ArchiveScreen({super.key, this.trash = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VaultState>();
    final items = trash ? state.trashedEntries : state.archivedEntries;
    items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: Text(trash ? 'Recently Deleted' : 'Archive'),
        actions: [
          if (trash && items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Empty Recently Deleted?'),
                    content: const Text(
                        'These items will be permanently deleted. This cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete all')),
                    ],
                  ),
                );
                if (ok == true) await state.emptyTrash();
              },
              child: const Text('Empty'),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  trash
                      ? 'No deleted items. Deleted items stay here for 30 days.'
                      : 'No archived items. Archive items you rarely use to keep them out of the way.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 0, indent: 72),
              itemBuilder: (_, i) => _tile(context, state, items[i]),
            ),
    );
  }

  Widget _tile(BuildContext context, VaultState state, VaultEntry e) {
    final t = ItemTemplates.of(e.type);
    String? sub;
    if (trash && e.deletedAt != null) {
      final left = 30 - DateTime.now().difference(e.deletedAt!).inDays;
      sub = 'Deleted forever in ${left < 0 ? 0 : left} days';
    } else {
      sub = e.subtitle.isEmpty ? null : e.subtitle;
    }
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: t.color.withValues(alpha: 0.15),
        child: Icon(t.icon, color: t.color),
      ),
      title: Text(e.title.isEmpty ? '(untitled)' : e.title),
      subtitle: sub == null ? null : Text(sub),
      onTap: trash
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EntryDetailScreen(entryId: e.id))),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'restore') {
            trash ? await state.restoreEntry(e) : await state.setArchived(e, false);
          } else if (v == 'purge') {
            await state.purgeEntry(e);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'restore', child: Text(trash ? 'Restore' : 'Unarchive')),
          if (trash)
            const PopupMenuItem(value: 'purge', child: Text('Delete forever')),
        ],
      ),
    );
  }
}
