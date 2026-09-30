import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'models.dart';
import 'services/encrypted_journal_store.dart';
import 'services/local_ai_service.dart';
import 'services/local_embedding_service.dart';
import 'ui_settings.dart';

class AppController extends ChangeNotifier {
  AppController(this._store);

  final JournalStore _store;
  final LocalAuthentication _localAuthentication = LocalAuthentication();
  final LocalAiService _localAi = LocalAiService();
  final LocalEmbeddingService _embeddings = LocalEmbeddingService();

  List<JournalEntry> entries = const [];
  FilterlosSettings settings = FilterlosSettings.defaults;
  bool isLoaded = false;
  bool timelineUnlocked = false;
  int _failedPinAttempts = 0;
  DateTime? _pinLockedUntil;

  bool get hasTimelinePin => _hasTimelinePin;
  bool _hasTimelinePin = false;

  ValueListenable<AiProgress?> get aiProgress => _localAi.progress;

  Future<void> load() async {
    final state = await _store.loadState();
    final storedEntries = state['entries'];
    entries = storedEntries is List
        ? storedEntries
              .whereType<Map>()
              .map(
                (item) =>
                    JournalEntry.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <JournalEntry>[];
    settings = FilterlosSettings.fromJson(
      state['settings'] is Map
          ? Map<String, dynamic>.from(state['settings'] as Map)
          : null,
    );
    _hasTimelinePin = await _store.hasPin;
    _sortEntries();
    isLoaded = true;
    notifyListeners();
  }

  List<JournalEntry> entriesFor({String? categoryId}) {
    final result = categoryId == null
        ? entries
        : entries.where((entry) => entry.categoryId == categoryId).toList();
    return [...result]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> addEntry(JournalEntry entry) async {
    entries = [entry, ...entries];
    await _persist();
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    entries = entries.where((entry) => entry.id != id).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> updateSettings(FilterlosSettings value) async {
    if (value.localModelPath != settings.localModelPath) {
      _localAi.reset();
    }
    if (value.embeddingModelPath != settings.embeddingModelPath) {
      _embeddings.dispose();
    }
    settings = value;
    await _persist();
    notifyListeners();
  }

  Future<String> createPasswordBackup(String password) {
    final store = _store;
    if (store is! EncryptedJournalStore) {
      throw StateError(
        'Passwort-Backups sind für diesen Store nicht verfügbar.',
      );
    }
    return store.createPasswordBackup(password);
  }

  Future<void> restorePasswordBackup(String backup, String password) async {
    final store = _store;
    if (store is! EncryptedJournalStore) {
      throw StateError(
        'Passwort-Backups sind für diesen Store nicht verfügbar.',
      );
    }
    await store.restorePasswordBackup(backup, password);
    await load();
  }

  Future<String> companionReply(JournalEntry entry) {
    return _localAi.generate(
      modelPath: _requireLocalModel(),
      systemPrompt:
          'Du bist fi, ein empathischer, nicht-belehrender lokaler Begleiter. '
          'Validiere Gefühle, stelle keine Diagnosen und antworte kurz.',
      userPrompt: buildCompanionPrompt(entry, settings.userMemorySummary),
      maxTokens: 240,
    );
  }

  Future<String> dailyRecap({DateTime? date}) {
    final day = date ?? DateTime.now();
    final dayEntries = entries.where((entry) {
      final created = entry.createdAt;
      return created.year == day.year &&
          created.month == day.month &&
          created.day == day.day;
    }).toList();
    if (dayEntries.isEmpty) {
      throw StateError('Für diesen Tag gibt es keine Einträge.');
    }
    return _localAi.generate(
      modelPath: _requireLocalModel(),
      systemPrompt: 'Du bist fi. Fasse private Notizen respektvoll zusammen, ohne Fakten zu erfinden oder Diagnosen zu stellen.',
      userPrompt: buildDailyRecapPrompt(dayEntries, settings.userMemorySummary),
      maxTokens: 420,
    );
  }

  Future<String> askDiary(String question) async {
    final relevant = await findRelevantEntriesFor(question);
    if (relevant.isEmpty) {
      throw StateError('Das Tagebuch enthält noch keine Einträge.');
    }
    return _localAi.generate(
      modelPath: _requireLocalModel(),
      systemPrompt: 'Du bist fi. Antworte nur auf Grundlage der lokalen Tagebuchauszüge. Wenn daraus keine Antwort hervorgeht, sage das offen.',
      userPrompt: buildDiaryQuestionPrompt(
        question,
        relevant,
        settings.userMemorySummary,
      ),
      maxTokens: 360,
    );
  }

  Future<void> refreshLocalMemory() async {
    if (entries.isEmpty) {
      throw StateError('Das Tagebuch enthält noch keine Einträge.');
    }
    final summary = await _localAi.generate(
      modelPath: _requireLocalModel(),
      systemPrompt: 'Du aktualisierst ein kurzes, nutzerkontrolliertes Präferenzprofil. Erzeuge keine Diagnosen oder Vermutungen über Identität.',
      userPrompt: buildMemoryUpdatePrompt(
        entries.take(30).toList(),
        settings.userMemorySummary,
      ),
      maxTokens: 180,
    );
    await updateSettings(settings.copyWith(userMemorySummary: summary));
  }

  /// Ranks entries by meaning when an embedding model is available and falls
  /// back to the keyword search otherwise.
  Future<List<JournalEntry>> findRelevantEntriesFor(String question) async {
    final modelPath = settings.embeddingModelPath.trim();
    if (modelPath.isEmpty || entries.isEmpty) {
      return findRelevantEntries(question, entries);
    }
    try {
      await _ensureEmbeddings(modelPath);
      final questionVector = (await _embeddings.embed(modelPath, [
        question,
      ], isQuery: true)).first;
      final ranked =
          entries
              .where((entry) => entry.embedding != null)
              .map(
                (entry) => (
                  entry: entry,
                  score: cosineSimilarity(questionVector, entry.embedding!),
                ),
              )
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      if (ranked.isEmpty) return findRelevantEntries(question, entries);
      return ranked.take(6).map((item) => item.entry).toList();
    } catch (_) {
      return findRelevantEntries(question, entries);
    }
  }

  Future<void> _ensureEmbeddings(String modelPath) async {
    final missing = entries
        .where(
          (entry) => entry.embedding == null && entry.text.trim().isNotEmpty,
        )
        .toList();
    if (missing.isEmpty) return;
    final vectors = await _embeddings.embed(
      modelPath,
      missing.map((entry) => entry.text).toList(),
    );
    if (vectors.length != missing.length) return;
    final updated = {
      for (var i = 0; i < missing.length; i++)
        missing[i].id: missing[i].withEmbedding(vectors[i]),
    };
    entries = entries.map((entry) => updated[entry.id] ?? entry).toList();
    await _persist();
  }

  String _requireLocalModel() {
    final path = settings.localModelPath.trim();
    if (path.isEmpty) {
      throw StateError('Wähle zuerst ein lokales GGUF-Modell aus.');
    }
    return path;
  }

  Future<void> configurePin(String pin) async {
    await _store.setPin(pin);
    _hasTimelinePin = true;
    _failedPinAttempts = 0;
    _pinLockedUntil = null;
    notifyListeners();
  }

  Future<bool> changePin(String currentPin, String newPin) async {
    if (!await _store.verifyPin(currentPin)) return false;
    await _store.setPin(newPin);
    _hasTimelinePin = true;
    notifyListeners();
    return true;
  }

  Future<bool> unlockWithPin(String pin) async {
    final lockedUntil = _pinLockedUntil;
    if (lockedUntil != null && DateTime.now().isBefore(lockedUntil)) {
      return false;
    }
    if (!_hasTimelinePin) return false;

    final valid = await _store.verifyPin(pin);
    if (valid) {
      _failedPinAttempts = 0;
      _pinLockedUntil = null;
      timelineUnlocked = true;
      notifyListeners();
      return true;
    }

    _failedPinAttempts++;
    if (_failedPinAttempts >= 5) {
      _failedPinAttempts = 0;
      _pinLockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return false;
  }

  Future<bool> unlockWithBiometrics() async {
    if (!Platform.isAndroid || !settings.biometricTimeline) return false;
    try {
      final supported = await _localAuthentication.isDeviceSupported();
      if (!supported) return false;
      final authenticated = await _localAuthentication.authenticate(
        localizedReason: 'Timeline von filterlos.ich öffnen',
        biometricOnly: true,
      );
      if (!authenticated) return false;
      timelineUnlocked = true;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void lockTimeline() {
    timelineUnlocked = false;
    notifyListeners();
  }

  Future<void> _persist() {
    return _store.saveState({
      'entries': entries.map((entry) => entry.toJson()).toList(),
      'settings': settings.toJson(),
    });
  }

  void _sortEntries() {
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  void dispose() {
    _localAi.dispose();
    _embeddings.dispose();
    super.dispose();
  }
}
