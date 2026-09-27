import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filterlos_ich/app.dart';
import 'package:filterlos_ich/app_controller.dart';
import 'package:filterlos_ich/models.dart';
import 'package:filterlos_ich/services/encrypted_journal_store.dart';

void main() {
  test('journal payload is encrypted and round-trips', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'filterlos_crypto_test_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final store = EncryptedJournalStore(
      secrets: _MemorySecretStore(),
      supportDirectory: tempDirectory,
    );
    await store.initialize();
    await store.saveState({
      'entries': [
        {
          'id': 'entry-1',
          'categoryId': 'vent',
          'createdAt': '2026-09-26T10:00:00.000',
          'text': 'private thought marker',
          'attachments': <Map<String, dynamic>>[],
        },
      ],
      'settings': null,
    });

    final encryptedFile = File(
      '${tempDirectory.path}/filterlos.ich/journal.enc',
    );
    final encryptedText = await encryptedFile.readAsString();
    expect(encryptedText, isNot(contains('private thought marker')));

    final restored = await store.loadState();
    final restoredEntries = restored['entries'] as List<dynamic>;
    expect(restoredEntries.single['text'], 'private thought marker');
  });

  test('timeline PIN is verified without storing plaintext PIN', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'filterlos_pin_test_',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final secrets = _MemorySecretStore();
    final store = EncryptedJournalStore(
      secrets: secrets,
      supportDirectory: tempDirectory,
    );
    await store.initialize();
    await store.setPin('482916');

    expect(await store.hasPin, isTrue);
    expect(await store.verifyPin('482916'), isTrue);
    expect(await store.verifyPin('482915'), isFalse);
    expect(secrets.values.values, isNot(contains('482916')));
  });

  test('journal entries can be added and deleted from local state', () async {
    final store = _MemoryJournalStore();
    final controller = AppController(store);
    await controller.load();
    final entry = JournalEntry(
      id: 'entry-delete-test',
      categoryId: 'thought',
      createdAt: DateTime(2026, 9, 26),
      text: 'temporary thought',
    );

    await controller.addEntry(entry);
    expect(controller.entries, hasLength(1));

    await controller.deleteEntry(entry.id);
    expect(controller.entries, isEmpty);
    expect((store.state['entries'] as List<dynamic>), isEmpty);
  });

  testWidgets('app opens directly on the six emotion capture grid', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = AppController(_MemoryJournalStore());
    await controller.load();

    await tester.pumpWidget(FilterlosApp(controller: controller));

    expect(find.text('filterlos.ich'), findsOneWidget);
    expect(find.text('Was ist gerade in dir?'), findsOneWidget);
    for (final (symbol, color) in [
      ('♨︎', const Color(0xFFE57373)),
      ('☺︎', const Color(0xFFAED581)),
      ('☂︎', const Color(0xFF64B5F6)),
      ('☁︎', Colors.white),
      ('✦', const Color(0xFFFFF176)),
      ('⚡︎', const Color(0xFF9575CD)),
    ]) {
      final symbolFinder = find.text(symbol);
      expect(symbolFinder, findsOneWidget);
      expect(tester.widget<Text>(symbolFinder).style?.color, color);
      expect(
        find.ancestor(of: symbolFinder, matching: find.byType(Center)),
        findsWidgets,
      );
    }
    for (final category in EmotionCategory.all) {
      expect(find.text(category.name), findsNothing);
      expect(
        find.bySemanticsLabel('${category.name}: ${category.description}'),
        findsOneWidget,
      );
    }
    semantics.dispose();
  });
}

class _MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _MemoryJournalStore implements JournalStore {
  Map<String, dynamic> state = <String, dynamic>{
    'entries': <dynamic>[],
    'settings': null,
  };
  bool _hasPin = false;
  String? _pin;

  @override
  Future<Map<String, dynamic>> loadState() async => state;

  @override
  Future<void> saveState(Map<String, dynamic> value) async {
    state = value;
  }

  @override
  Future<bool> get hasPin async => _hasPin;

  @override
  Future<void> setPin(String pin) async {
    _pin = pin;
    _hasPin = true;
  }

  @override
  Future<bool> verifyPin(String pin) async => pin == _pin;
}
