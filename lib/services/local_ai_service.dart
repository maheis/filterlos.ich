import 'package:llm_llamacpp/llm_llamacpp.dart';

import '../models.dart';

class LocalAiService {
  String? _modelPath;
  LlamaCppChatRepository? _chatRepository;

  Future<String> generate({
    required String modelPath,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 240,
  }) async {
    final repository = _repositoryFor(modelPath);
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
    final result = response.toString().trim();
    if (result.isEmpty) {
      throw StateError('Das lokale Modell hat keine Antwort geliefert.');
    }
    return result;
  }

  LlamaCppChatRepository _repositoryFor(String modelPath) {
    if (_modelPath != modelPath || _chatRepository == null) {
      _chatRepository?.dispose();
      _modelPath = modelPath;
      _chatRepository = LlamaCppChatRepository.withModelPath(
        modelPath,
        contextSize: 2048,
        threads: 2,
        nGpuLayers: 0,
      );
    }
    return _chatRepository!;
  }

  void dispose() {
    _chatRepository?.dispose();
    _chatRepository = null;
    _modelPath = null;
  }

  void reset() => dispose();
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
