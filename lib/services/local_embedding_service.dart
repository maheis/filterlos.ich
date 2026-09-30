import 'dart:math' as math;

import 'package:llm_llamacpp/llm_llamacpp.dart';

/// Computes sentence embeddings locally so the diary search can find entries
/// that match by meaning instead of by keyword.
class LocalEmbeddingService {
  String? _modelPath;
  LlamaCppChatRepository? _repository;
  LlamaCppRepository? _modelRepository;

  Future<List<List<double>>> embed(
    String modelPath,
    List<String> texts, {
    bool isQuery = false,
  }) async {
    if (texts.isEmpty) return const [];
    final repository = await _repositoryFor(modelPath);
    // E5 models expect these prefixes and degrade noticeably without them.
    final prefix = isQuery ? 'query: ' : 'passage: ';
    final result = await repository.embed(
      model: modelPath,
      messages: texts.map((text) => '$prefix$text').toList(),
    );
    return result.map((item) => item.embedding).toList();
  }

  Future<LlamaCppChatRepository> _repositoryFor(String modelPath) async {
    if (_modelPath != modelPath || _repository == null) {
      dispose();
      _modelPath = modelPath;
      _modelRepository = LlamaCppRepository();
      final model = await _modelRepository!.loadModel(modelPath);
      _repository = LlamaCppChatRepository.withModel(
        model,
        _modelRepository!.bindings,
        contextSize: 512,
        batchSize: 512,
        threads: 4,
        nGpuLayers: 0,
      );
    }
    return _repository!;
  }

  void dispose() {
    _repository?.dispose();
    _modelRepository?.dispose();
    _repository = null;
    _modelRepository = null;
    _modelPath = null;
  }
}

double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return 0;
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}
