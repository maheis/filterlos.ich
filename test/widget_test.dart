import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:filterlos_ich/app.dart';
import 'package:filterlos_ich/app_controller.dart';
import 'package:filterlos_ich/category_icon.dart';
import 'package:filterlos_ich/models.dart';
import 'package:filterlos_ich/pages/settings_page.dart';
import 'package:filterlos_ich/services/encrypted_journal_store.dart';
import 'package:filterlos_ich/services/daily_text_export_service.dart';
import 'package:filterlos_ich/services/local_ai_service.dart';
import 'package:filterlos_ich/ui_settings.dart';
import 'package:archive/archive.dart';

void main() {
  test('daily text ZIP groups entries and requires the app PIN', () {
    final bytes = DailyTextExportService().createEncryptedZip([
      JournalEntry(
        id: 'later',
        categoryId: 'joy',
        createdAt: DateTime(2026, 10, 8, 18, 30),
        text: 'Abends war es leichter.',
      ),
      JournalEntry(
        id: 'other-day',
        categoryId: 'thought',
        createdAt: DateTime(2026, 10, 9, 7, 15),
        text: 'Neuer Tag.',
      ),
      JournalEntry(
        id: 'earlier',
        categoryId: 'vent',
        createdAt: DateTime(2026, 10, 8, 8, 5),
        text: 'Das war schwierig.',
      ),
    ], '482916');

    final archive = ZipDecoder().decodeBytes(bytes, password: '482916');
    expect(archive.files.map((file) => file.name), [
      '261008.txt',
      '261009.txt',
    ]);
    final firstDay = utf8.decode(archive.findFile('261008.txt')!.readBytes()!);
    expect(firstDay.indexOf('08:05'), lessThan(firstDay.indexOf('18:30')));
    expect(firstDay, contains('Das war schwierig.'));
    expect(firstDay, contains('Abends war es leichter.'));
    expect(
      () => ZipDecoder()
          .decodeBytes(bytes, password: '000000')
          .files
          .first
          .readBytes(),
      throwsA(anything),
    );
  });

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

  test('password backup restores the encrypted journal', () async {
    final sourceDirectory = await Directory.systemTemp.createTemp(
      'filterlos_backup_source_',
    );
    final restoreDirectory = await Directory.systemTemp.createTemp(
      'filterlos_backup_restore_',
    );
    addTearDown(() async {
      await sourceDirectory.delete(recursive: true);
      await restoreDirectory.delete(recursive: true);
    });
    final source = EncryptedJournalStore(
      secrets: _MemorySecretStore(),
      supportDirectory: sourceDirectory,
    );
    await source.initialize();
    await source.saveState({
      'entries': [
        {
          'id': 'backup-entry',
          'categoryId': 'joy',
          'createdAt': '2026-09-29T12:00:00.000',
          'text': 'restore me',
          'attachments': <Map<String, dynamic>>[],
        },
      ],
      'settings': null,
    });
    final backup = await source.createPasswordBackup('correct horse battery');

    final restored = EncryptedJournalStore(
      secrets: _MemorySecretStore(),
      supportDirectory: restoreDirectory,
    );
    await restored.initialize();
    await restored.restorePasswordBackup(backup, 'correct horse battery');
    final state = await restored.loadState();
    expect((state['entries'] as List).single['text'], 'restore me');
    await expectLater(
      restored.restorePasswordBackup(backup, 'wrong password'),
      throwsA(isA<FormatException>()),
    );
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

    final controller = AppController(store);
    await controller.load();
    expect(await controller.verifyTimelinePinForExport('482916'), isTrue);
    expect(controller.timelineUnlocked, isFalse);
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

  test('chat sessions persist with their messages and entry context', () async {
    final store = _MemoryJournalStore();
    final controller = AppController(store);
    await controller.load();
    final entry = JournalEntry(
      id: 'entry-chat-context',
      categoryId: 'thought',
      createdAt: DateTime(2026, 9, 26),
      text: 'context thought',
    );
    await controller.addEntry(entry);

    final chat = await controller.createChat(contextEntry: entry);
    await controller.addChatMessage(
      chat.id,
      ChatMessage(
        text: 'Hallo fi',
        isUser: true,
        createdAt: DateTime(2026, 9, 26, 12),
      ),
    );

    final restored = AppController(store);
    await restored.load();
    expect(restored.chats, hasLength(1));
    expect(restored.chats.single.contextEntryId, entry.id);
    expect(restored.chats.single.messages.single.text, 'Hallo fi');
  });

  test('companion and chat prompts handle third-person self-reference', () {
    final entry = JournalEntry(
      id: 'entry-third-person',
      categoryId: 'thought',
      createdAt: DateTime(2026, 9, 26),
      text: 'Er fühlt sich gerade überfordert.',
    );
    const guidance =
        'Der Nutzer kann über sich selbst in der dritten Person schreiben.';

    expect(buildCompanionPrompt(entry, ''), contains(guidance));
    expect(
      buildCompanionPrompt(entry, ''),
      contains('Trost bei Schmerz oder Überforderung'),
    );
    expect(
      buildCompanionPrompt(entry, ''),
      contains('Rat nur, wenn danach gefragt wird'),
    );
    expect(
      buildChatPrompt(
        'Er fühlt sich gerade überfordert.',
        relevantEntries: const [],
        history: const [],
        memory: '',
      ),
      contains(guidance),
    );
    expect(
      buildChatPrompt(
        'Das war unfair.',
        relevantEntries: const [],
        history: const [],
        memory: '',
      ),
      contains('ohne Menschen zu beleidigen'),
    );
  });

  test(
    'timeline entries group by local calendar day in newest-first order',
    () {
      JournalEntry entry(String id, DateTime createdAt) => JournalEntry(
        id: id,
        categoryId: 'thought',
        createdAt: createdAt,
        text: id,
      );
      final grouped = groupEntriesByDay([
        entry('morning', DateTime(2026, 9, 28, 8)),
        entry('yesterday', DateTime(2026, 9, 27, 23)),
        entry('evening', DateTime(2026, 9, 28, 20)),
      ]);

      expect(grouped.keys.toList(), [
        DateTime(2026, 9, 28),
        DateTime(2026, 9, 27),
      ]);
      expect(grouped[DateTime(2026, 9, 28)]!.map((entry) => entry.id), [
        'morning',
        'evening',
      ]);
    },
  );

  test('snackbars use dark surfaces in light and stealth themes', () {
    final lightTheme = buildFilterlosTheme(
      FilterlosSettings.defaults.copyWith(useLightTheme: true),
      stealth: false,
    );
    final stealthTheme = buildFilterlosTheme(
      FilterlosSettings.defaults,
      stealth: true,
    );

    expect(lightTheme.snackBarTheme.backgroundColor, const Color(0xFF242424));
    expect(stealthTheme.snackBarTheme.backgroundColor, const Color(0xFF101010));
    expect(lightTheme.snackBarTheme.contentTextStyle?.color, Colors.white);
  });

  test('default accent color is red', () {
    expect(FilterlosSettings.defaults.accentColorValue, 0xFFE57373);
  });

  test('stealth theme ignores configured accent and highlight colors', () {
    final settings = FilterlosSettings.defaults.copyWith(
      accentColorValue: 0xFFE57373,
      highlightColorValue: 0xFFFFB74D,
    );
    final scheme = buildFilterlosTheme(settings, stealth: true).colorScheme;

    for (final color in [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.error,
    ]) {
      expect(color.r, color.g);
      expect(color.g, color.b);
    }
    expect(scheme.primary, isNot(Color(settings.accentColorValue)));
    expect(scheme.secondary, isNot(Color(settings.highlightColorValue)));
  });

  testWidgets('category SVGs become neutral in stealth mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryIcon(
            category: EmotionCategory.all.first,
            size: 32,
            stealth: true,
          ),
        ),
      ),
    );

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      picture.colorFilter,
      const ColorFilter.mode(Color(0xFF777777), BlendMode.srcIn),
    );
  });

  testWidgets('app opens directly on the six emotion capture grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final controller = AppController(_MemoryJournalStore());
    await controller.load();

    await tester.pumpWidget(FilterlosApp(controller: controller));

    expect(find.text('filterlos.ich'), findsOneWidget);
    expect(find.text('Was ist gerade in dir?'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    for (final (category, asset, color) in [
      (
        EmotionCategory.all[0],
        'white_transparent_vent.svg',
        const Color(0xFFE57373),
      ),
      (
        EmotionCategory.all[1],
        'white_transparent_joy.svg',
        const Color(0xFFAED581),
      ),
      (
        EmotionCategory.all[2],
        'white_transparent_sadness.svg',
        const Color(0xFF64B5F6),
      ),
      (EmotionCategory.all[3], 'white_transparent_thought.svg', Colors.white),
      (
        EmotionCategory.all[4],
        'white_transparent_spark.svg',
        const Color(0xFFFFF176),
      ),
      (
        EmotionCategory.all[5],
        'white_transparent_chaos.svg',
        const Color(0xFF9575CD),
      ),
    ]) {
      final iconFinder = find.byWidgetPredicate(
        (widget) => widget is CategoryIcon && widget.category == category,
      );
      expect(iconFinder, findsOneWidget);
      final picture = tester.widget<SvgPicture>(
        find.descendant(of: iconFinder, matching: find.byType(SvgPicture)),
      );
      expect(
        (picture.bytesLoader as SvgAssetLoader).assetName,
        'assets/icons/$asset',
      );
      expect(picture.colorFilter, ColorFilter.mode(color, BlendMode.srcIn));
      expect(
        find.ancestor(of: iconFinder, matching: find.byType(Center)),
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
    final category = EmotionCategory.all.first;
    await tester.tap(
      find.bySemanticsLabel('${category.name}: ${category.description}'),
    );
    await tester.pumpAndSettle();
    expect(find.text(category.name), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    expect(find.text('Sprachnotizen'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CategoryIcon && widget.category == category,
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('white thought icon remains visible in light theme', (
    tester,
  ) async {
    final controller = AppController(_MemoryJournalStore());
    await controller.load();
    await controller.updateSettings(
      controller.settings.copyWith(useLightTheme: true, emojiButtons: false),
    );

    await tester.pumpWidget(FilterlosApp(controller: controller));

    final iconFinder = find.byWidgetPredicate(
      (widget) => widget is CategoryIcon && widget.category.id == 'thought',
    );
    final cardFinder = find.ancestor(
      of: iconFinder,
      matching: find.byType(Card),
    );
    expect(tester.widget<Card>(cardFinder).color, const Color(0xFF414650));
  });

  testWidgets('settings list verified downloadable local models', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(_MemoryJournalStore());
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(controller: controller)),
    );
    expect(find.text('Qwen2.5 0.5B · Q4_K_M'), findsOneWidget);
    expect(find.text('Qwen3 1.7B · Q4_K_M'), findsOneWidget);
    expect(find.text('Qwen3 4B · Q4_K_M'), findsOneWidget);
    expect(find.text('Qwen3 8B · Q4_K_M'), findsOneWidget);
    expect(
      find.text(
        'Schnell · läuft auf fast allen Geräten\n491 MB · Apache 2.0 · Qwen',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('1.11 GB · Apache 2.0'), findsOneWidget);
    expect(find.textContaining('2.50 GB · Apache 2.0'), findsOneWidget);
    expect(find.textContaining('5.03 GB · Apache 2.0'), findsOneWidget);
    expect(find.text('Multilingual E5 Small · Q8_0'), findsOneWidget);
    expect(find.textContaining('132 MB · MIT · intfloat'), findsOneWidget);
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

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _MemoryJournalStore implements JournalStore {
  Map<String, dynamic> state = <String, dynamic>{
    'entries': <dynamic>[],
    'chats': <dynamic>[],
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
