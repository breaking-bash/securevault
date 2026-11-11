import 'package:flutter/material.dart';

import '../../models/item_templates.dart';
import '../../models/vault_entry.dart';
import '../widgets/type_tile.dart';
import 'entry_edit_screen.dart';
import 'note_edit_screen.dart';

class _Choice {
  final String label;
  final IconData icon;
  final Color color;
  final EntryType? type; // null = secure note
  const _Choice(this.label, this.icon, this.color, this.type);
}

/// Full-screen "New Item" picker: featured categories in a grid, then every
/// other category as a vertical list.
class NewItemScreen extends StatefulWidget {
  const NewItemScreen({super.key});

  @override
  State<NewItemScreen> createState() => _NewItemScreenState();
}

class _NewItemScreenState extends State<NewItemScreen> {
  String _q = '';

  static const _featured = <EntryType?>[
    EntryType.login,
    null,
    EntryType.card,
    EntryType.identity,
    EntryType.password,
    EntryType.document,
  ];

  static _Choice _choice(EntryType? t) {
    if (t == null) {
      return const _Choice(
          'Secure Note', Icons.sticky_note_2, ItemTemplates.noteColor, null);
    }
    final tpl = ItemTemplates.of(t);
    return _Choice(tpl.label, tpl.icon, tpl.color, t);
  }

  void _open(_Choice c) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => c.type == null
            ? const NoteEditScreen()
            : EntryEditScreen(newType: c.type!)));
  }

  @override
  Widget build(BuildContext context) {
    final featured = _featured.map(_choice).toList();
    final more = [
      for (final t in ItemTemplates.pickerOrder)
        if (!_featured.contains(t)) _choice(t),
    ]..sort((a, b) => a.label.compareTo(b.label));
    final q = _q.trim().toLowerCase();
    bool match(_Choice c) => q.isEmpty || c.label.toLowerCase().contains(q);
    final f = featured.where(match).toList();
    final m = more.where(match).toList();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('New Item'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              hintText: 'What would you like to add?',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          if (f.isNotEmpty)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 92,
              children: [for (final c in f) _FeaturedCard(c, () => _open(c))],
            ),
          if (f.isNotEmpty && m.isNotEmpty) const SizedBox(height: 20),
          if (m.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < m.length; i++) ...[
                    if (i > 0) const Divider(height: 0, indent: 68),
                    ListTile(
                      leading: TypeTile(
                          icon: m[i].icon, color: m[i].color, size: 36),
                      title: Text(m[i].label),
                      trailing: const Icon(Icons.add),
                      onTap: () => _open(m[i]),
                    ),
                  ],
                ],
              ),
            ),
          if (f.isEmpty && m.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No matching categories')),
            ),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final _Choice c;
  final VoidCallback onTap;
  const _FeaturedCard(this.c, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TypeTile(icon: c.icon, color: c.color, size: 36),
                  const Icon(Icons.add, size: 20),
                ],
              ),
              const Spacer(),
              Text(c.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
