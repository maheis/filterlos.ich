import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../models.dart';

class DailyTextExportService {
  List<int> createEncryptedZip(
    List<JournalEntry> entries,
    String pin, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (pin.length < 6 || !RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('Die App-PIN muss mindestens sechs Ziffern haben.');
    }
    if (entries.isEmpty) {
      throw StateError('Das Tagebuch enthält noch keine Einträge.');
    }

    final startDay = startDate == null ? null : _localDay(startDate);
    final endDay = endDate == null ? null : _localDay(endDate);
    if (startDay != null && endDay != null && startDay.isAfter(endDay)) {
      throw ArgumentError('Der Beginn liegt nach dem Ende des Zeitraums.');
    }

    final entriesByDay = <DateTime, List<JournalEntry>>{};
    for (final entry in entries) {
      final localDate = entry.createdAt.toLocal();
      final day = DateTime(localDate.year, localDate.month, localDate.day);
      if ((startDay != null && day.isBefore(startDay)) ||
          (endDay != null && day.isAfter(endDay))) {
        continue;
      }
      entriesByDay.putIfAbsent(day, () => <JournalEntry>[]).add(entry);
    }
    if (entriesByDay.isEmpty) {
      throw StateError('Im gewählten Zeitraum gibt es keine Einträge.');
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

  DateTime _localDay(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
