import 'package:intl/intl.dart';

class EmotionCategory {
  const EmotionCategory({
    required this.id,
    required this.emoji,
    required this.name,
    required this.description,
    required this.colorValue,
  });

  final String id;
  final String emoji;
  final String name;
  final String description;
  final int colorValue;

  static const all = <EmotionCategory>[
    EmotionCategory(
      id: 'vent',
      emoji: '😡',
      name: 'Ausrast',
      description: 'Dampf ablassen, Wut und Frust festhalten.',
      colorValue: 0xFFE57373,
    ),
    EmotionCategory(
      id: 'joy',
      emoji: '😊',
      name: 'Freude',
      description: 'Erfolge, Dankbarkeit und gute Momente sammeln.',
      colorValue: 0xFFAED581,
    ),
    EmotionCategory(
      id: 'sadness',
      emoji: '😢',
      name: 'Trauer',
      description: 'Sorgen, Enttäuschung und Melancholie notieren.',
      colorValue: 0xFF64B5F6,
    ),
    EmotionCategory(
      id: 'thought',
      emoji: '😐',
      name: 'Gedanke',
      description: 'Alltagsnotizen und Beobachtungen festhalten.',
      colorValue: 0xFF8FDCBE,
    ),
    EmotionCategory(
      id: 'spark',
      emoji: '💡',
      name: 'Geistesblitz',
      description: 'Spontane Ideen sichern, bevor sie verschwinden.',
      colorValue: 0xFFFFB74D,
    ),
    EmotionCategory(
      id: 'chaos',
      emoji: '🤯',
      name: 'Chaos',
      description: 'Gedankenstrudel aus dem Kopf aufs Papier bringen.',
      colorValue: 0xFF9575CD,
    ),
  ];

  static EmotionCategory? find(String id) {
    for (final category in all) {
      if (category.id == id) return category;
    }
    return null;
  }
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.categoryId,
    required this.createdAt,
    required this.text,
    this.attachments = const [],
  });

  final String id;
  final String categoryId;
  final DateTime createdAt;
  final String text;
  final List<JournalAttachment> attachments;

  EmotionCategory get category =>
      EmotionCategory.find(categoryId) ?? EmotionCategory.all[3];

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'createdAt': createdAt.toIso8601String(),
    'text': text,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(),
  };

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: (json['id'] ?? '').toString(),
      categoryId: (json['categoryId'] ?? 'thought').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      text: (json['text'] ?? '').toString(),
      attachments: (json['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                JournalAttachment.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

class JournalAttachment {
  const JournalAttachment({
    required this.name,
    required this.mimeType,
    required this.base64Data,
  });

  final String name;
  final String mimeType;
  final String base64Data;

  Map<String, dynamic> toJson() => {
    'name': name,
    'mimeType': mimeType,
    'base64Data': base64Data,
  };

  factory JournalAttachment.fromJson(Map<String, dynamic> json) {
    return JournalAttachment(
      name: (json['name'] ?? '').toString(),
      mimeType: (json['mimeType'] ?? 'application/octet-stream').toString(),
      base64Data: (json['base64Data'] ?? '').toString(),
    );
  }
}

String formatEntryDate(DateTime date) =>
    DateFormat('dd.MM.yyyy · HH:mm', 'de_DE').format(date);

String formatDay(DateTime date) =>
    DateFormat('EEEE, d. MMMM', 'de_DE').format(date);

Map<DateTime, List<JournalEntry>> groupEntriesByDay(
  Iterable<JournalEntry> entries,
) {
  final grouped = <DateTime, List<JournalEntry>>{};
  for (final entry in entries) {
    final created = entry.createdAt;
    final day = DateTime(created.year, created.month, created.day);
    grouped.putIfAbsent(day, () => []).add(entry);
  }
  final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return {for (final day in days) day: List.unmodifiable(grouped[day]!)};
}
