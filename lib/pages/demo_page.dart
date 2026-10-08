import 'package:flutter/material.dart';

import '../category_icon.dart';
import '../models.dart';

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  static final List<JournalEntry> _examples = [
    JournalEntry(
      id: 'demo-1',
      categoryId: 'thought',
      createdAt: DateTime(2026, 10, 8, 8, 15),
      text:
          'Heute sortiere ich erst einmal meine Gedanken, bevor ich antworte.',
    ),
    JournalEntry(
      id: 'demo-2',
      categoryId: 'vent',
      createdAt: DateTime(2026, 10, 8, 12, 40),
      text: 'Das Gespräch war anstrengend. Ich darf darüber sauer sein.',
    ),
    JournalEntry(
      id: 'demo-3',
      categoryId: 'joy',
      createdAt: DateTime(2026, 10, 8, 19, 5),
      text: 'Ein guter Abend mit Freunden hat mir richtig gutgetan.',
    ),
    JournalEntry(
      id: 'demo-4',
      categoryId: 'spark',
      createdAt: DateTime(2026, 10, 7, 16, 20),
      text: 'Idee: morgen mit einem kleinen Schritt anfangen.',
    ),
  ];

  String? _categoryId;

  @override
  Widget build(BuildContext context) {
    final entries =
        _examples
            .where(
              (entry) => _categoryId == null || entry.categoryId == _categoryId,
            )
            .toList()
          ..sort(
            (first, second) => second.createdAt.compareTo(first.createdAt),
          );
    final grouped = <DateTime, List<JournalEntry>>{};
    for (final entry in entries) {
      final date = entry.createdAt;
      final day = DateTime(date.year, date.month, date.day);
      grouped.putIfAbsent(day, () => <JournalEntry>[]).add(entry);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo'),
        actions: [
          IconButton(
            tooltip: 'Filter zurücksetzen',
            onPressed: () => setState(() => _categoryId = null),
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Beispieldaten'),
                subtitle: const Text(
                  'Diese Ansicht enthält keine persönlichen Timeline-Einträge.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Alle'),
                      selected: _categoryId == null,
                      onSelected: (_) => setState(() => _categoryId = null),
                    ),
                  ),
                  for (final category in EmotionCategory.all)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Text(category.emoji),
                        label: Text(category.name),
                        selected: _categoryId == category.id,
                        onSelected: (selected) => setState(
                          () => _categoryId = selected ? category.id : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final day in grouped.keys) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text(
                  '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final entry in grouped[day]!) _buildEntry(entry),
            ],
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('Keine Beispiele in dieser Kategorie.'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(JournalEntry entry) {
    final category = entry.category;
    return Card(
      child: ListTile(
        leading: CategoryIcon(category: category, size: 42, stealth: false),
        title: Text(category.name),
        subtitle: Text(
          entry.text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}',
        ),
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('${category.emoji} ${category.name}'),
            content: SelectableText(entry.text),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Schließen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
