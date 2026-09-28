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
import 'package:filterlos_ich/ui_settings.dart';

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
    final semantics = tester.ensureSemantics();
    final controller = AppController(_MemoryJournalStore());
    await controller.load();

    await tester.pumpWidget(FilterlosApp(controller: controller));

    expect(find.text('filterlos.ich'), findsOneWidget);
    expect(find.text('Was ist gerade in dir?'), findsOneWidget);
    for (final (category, asset, color) in [
      (EmotionCategory.all[0], 'angry.svg', const Color(0xFFE57373)),
      (EmotionCategory.all[1], 'grin-beam.svg', const Color(0xFFAED581)),
      (EmotionCategory.all[2], 'sad-tear.svg', const Color(0xFF64B5F6)),
      (EmotionCategory.all[3], 'surprise.svg', Colors.white),
      (EmotionCategory.all[4], 'lightbulb-on.svg', const Color(0xFFFFF176)),
      (EmotionCategory.all[5], 'dizzy.svg', const Color(0xFF9575CD)),
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
    expect(find.text('Qwen3 0.6B · Q8_0'), findsOneWidget);
    expect(find.text('Qwen3 1.7B · Q8_0'), findsOneWidget);
    expect(find.text('Qwen3 4B · Q4_K_M'), findsOneWidget);
    expect(find.text('639 MB · Apache 2.0 · Qwen'), findsOneWidget);
    expect(find.text('1.83 GB · Apache 2.0 · Qwen'), findsOneWidget);
    expect(find.text('2.50 GB · Apache 2.0 · Qwen'), findsOneWidget);
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
