import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../models.dart';

class DailyTextExportService {
  List<int> createEncryptedZip(List<JournalEntry> entries, String pin) {
    if (pin.length < 6 || !RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('Die App-PIN muss mindestens sechs Ziffern haben.');
    }
    if (entries.isEmpty) {
      throw StateError('Das Tagebuch enthält noch keine Einträge.');
    }

    final entriesByDay = <DateTime, List<JournalEntry>>{};
    for (final entry in entries) {
      final localDate = entry.createdAt.toLocal();
      final day = DateTime(localDate.year, localDate.month, localDate.day);
      entriesByDay.putIfAbsent(day, () => <JournalEntry>[]).add(entry);
    }

    final archive = Archive();
    final sortedDays = entriesByDay.keys.toList()..sort();
    for (final day in sortedDays) {
      final dayEntries = entriesByDay[day]!
        ..sort((first, second) => first.createdAt.compareTo(second.createdAt));
      final text = StringBuffer();
      for (final entry in dayEntries) {
        text
          ..writeln(
            '${DateFormat('HH:mm').format(entry.createdAt.toLocal())} · ${entry.category.name}',
          )
          ..writeln(entry.text)
          ..writeln();
      }
      archive.addFile(
        ArchiveFile.string('${DateFormat('yyMMdd').format(day)}.txt', '$text'),
      );
    }

    return ZipEncoder(password: pin).encode(archive);
  }
}
