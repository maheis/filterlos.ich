import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:llm_llamacpp/llm_llamacpp.dart';

import '../models.dart';
import 'local_model_download_service.dart';

class LocalAiService {
  String? _modelPath;
  LlamaCppChatRepository? _chatRepository;
  LlamaCppRepository? _modelRepository;
  LlamaCppModel? _loadedModel;

  Future<String> generate({
    required String modelPath,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 240,
  }) async {
    try {
      final repository = await _repositoryFor(modelPath);
      // Qwen3 otherwise spends most tokens on hidden reasoning.
      if (modelPath.toLowerCase().contains('qwen3')) {
        userPrompt = '$userPrompt /no_think';
      }
      final response = StringBuffer();
      final stream = repository.streamChatWithGenerationOptions(
        modelPath,
        messages: [
          LLMMessage(role: LLMRole.system, content: systemPrompt),
          LLMMessage(role: LLMRole.user, content: userPrompt),
        ],
        generationOptions: GenerationOptions(
          temperature: 0.65,
          topP: 0.9,
          maxTokens: maxTokens,
        ),
      );
      await for (final chunk in stream) {
        response.write(chunk.message?.content ?? '');
      }
      final result = response
          .toString()
          .replaceAll(RegExp(r'<think>[\s\S]*?(</think>|$)'), '')
          .trim();
      if (result.isEmpty) {
        throw StateError('Das lokale Modell hat keine Antwort geliefert.');
      }
      return result;
    } on ModelLoadException {
      throw StateError(await _explainModelLoadFailure(modelPath));
    }
  }

  Future<LlamaCppChatRepository> _repositoryFor(String modelPath) async {
    if (_modelPath != modelPath || _chatRepository == null) {
      _chatRepository?.dispose();
      _modelRepository?.dispose();
      _modelPath = modelPath;
      _modelRepository = LlamaCppRepository();
      _loadedModel = await _modelRepository!.loadModel(modelPath);
      _chatRepository = LlamaCppChatRepository.withModel(
        _loadedModel!,
        _modelRepository!.bindings,
        contextSize: 2048,
        threads: 4,
        nGpuLayers: 0,
      );
    }
    return _chatRepository!;
  }

  void dispose() {
    _chatRepository?.dispose();
    _modelRepository?.dispose();
    _chatRepository = null;
    _modelRepository = null;
    _loadedModel = null;
    _modelPath = null;
  }

  void reset() => dispose();

  Future<String> _explainModelLoadFailure(String modelPath) async {
    final file = File(modelPath);
    if (!await file.exists()) {
      return 'Die lokale Modell-Datei wurde nicht gefunden. Wähle sie in den Einstellungen erneut aus.';
    }
    final model = LocalModelCatalogEntry.officialModels
        .where((entry) => entry.filename == p.basename(modelPath))
        .firstOrNull;
    if (model == null) {
      return 'llama.cpp konnte diese GGUF-Datei nicht laden. Prüfe, ob sie vollständig ist, und versuche ein kleineres GGUF-Modell.';
    }
    if (await file.length() != model.sizeBytes) {
      return 'Die Modelldatei ist unvollständig. Entferne sie in den Einstellungen und lade sie erneut herunter.';
    }
    final isVerified = await LocalModelDownloadService().matchesExpectedFile(
      file,
      model,
    );
    if (!isVerified) {
      return 'Die SHA-256-Prüfung der Modelldatei stimmt nicht. Entferne sie in den Einstellungen und lade sie erneut herunter.';
    }
    if (model.id == 'qwen3-4b-q4km') {
      return 'Die Qwen3-4B-Datei ist vollständig und geprüft, konnte aber von llama.cpp auf diesem Gerät nicht geladen werden. Häufig reichen Arbeitsspeicher oder CPU-Backend nicht aus. Entferne das Modell in den Einstellungen und versuche Qwen3 0.6B.';
    }
    if (model.id == 'qwen2.5-0.5b-q4km') {
      return 'Qwen2.5 0.5B ist vollständig und SHA-256-geprüft, wird aber vom nativen llama.cpp-Lader unter Android abgelehnt. Die verwendete Android-Laufzeit liefert leider keinen genaueren nativen Fehler; dafür ist ein Update des Android-Backends nötig.';
    }
    return 'Die Modelldatei ist vollständig und geprüft, konnte aber von llama.cpp auf diesem Gerät nicht geladen werden. Versuche Qwen3 0.6B oder prüfe die Gerätekompatibilität.';
  }
}

String buildCompanionPrompt(JournalEntry entry, String memory) {
  final category = entry.category;
  final memoryContext = memory.trim().isEmpty
      ? 'Es liegt kein gespeichertes Nutzerprofil vor.'
      : 'Vom Nutzer gepflegte Hinweise zur bevorzugten Unterstützung:\n$memory';
  return '''Du bist fi, ein warmherziger, nicht-belehrender Begleiter für private Gedanken.
Bestätige Gefühle ohne Diagnosen zu stellen. Gib keine medizinischen oder therapeutischen Diagnosen.
Antworte kurz, respektvoll und passend zur Kategorie ${category.name} (${category.emoji}).
$memoryContext

Eintrag:
${entry.text}''';
}

String buildDailyRecapPrompt(List<JournalEntry> entries, String memory) {
  final context = entries
      .map((entry) => '[${entry.category.name}] ${entry.text}')
      .join('\n');
  return '''Fasse diese heutigen privaten Notizen knapp und wertschätzend zusammen.
Erfinde keine Fakten, bewerte nicht und formuliere keine Diagnose. Hebe wiederkehrende Themen und positive Momente behutsam hervor.
Nutzerhinweise: ${memory.trim().isEmpty ? 'keine' : memory}

Notizen:
$context''';
}

String buildDiaryQuestionPrompt(
  String question,
  List<JournalEntry> relevantEntries,
  String memory,
) {
  final context = relevantEntries
      .map(
        (entry) =>
            '[${formatEntryDate(entry.createdAt)} · ${entry.category.name}] ${entry.text}',
      )
      .join('\n');
  return '''Beantworte die Frage ausschließlich anhand der ausgewählten Tagebucheinträge. Wenn die Einträge keine Antwort enthalten, sage das offen. Zitiere keine langen privaten Passagen und stelle keine Diagnosen.
Nutzerhinweise: ${memory.trim().isEmpty ? 'keine' : memory}

Frage: $question

Ausgewählte Einträge:
$context''';
}

String buildMemoryUpdatePrompt(
  List<JournalEntry> entries,
  String currentMemory,
) {
  final context = entries
      .map((entry) => '[${entry.category.name}] ${entry.text}')
      .join('\n');
  return '''Erstelle aus diesen Tagebucheinträgen eine kurze Notiz zu ausdrücklich erkennbaren Unterstützungspräferenzen des Nutzers. Keine Diagnosen, keine Vermutungen über Identität oder sensible Eigenschaften. Maximal fünf Stichpunkte. Wenn nichts Belastbares erkennbar ist, sage das.
Bisheriges, vom Nutzer kontrolliertes Profil:
${currentMemory.trim().isEmpty ? 'Noch leer.' : currentMemory}

Einträge:
$context''';
}

List<JournalEntry> findRelevantEntries(
  String question,
  List<JournalEntry> entries,
) {
  final terms = question
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9äöüß]+'))
      .where((term) => term.length >= 3)
      .toSet();
  if (terms.isEmpty) return entries.take(5).toList();

  final ranked =
      entries
          .map((entry) {
            final haystack = '${entry.text} ${entry.category.name}'
                .toLowerCase();
            final score = terms.where(haystack.contains).length;
            return (entry: entry, score: score);
          })
          .where((item) => item.score > 0)
          .toList()
        ..sort((a, b) {
          final scoreOrder = b.score.compareTo(a.score);
          if (scoreOrder != 0) return scoreOrder;
          return b.entry.createdAt.compareTo(a.entry.createdAt);
        });

  if (ranked.isEmpty) return entries.take(5).toList();
  return ranked.take(6).map((item) => item.entry).toList();
}
