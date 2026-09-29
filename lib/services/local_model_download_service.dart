import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class LocalModelCatalogEntry {
  const LocalModelCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.repository,
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
    this.downloadUrlOverride,
    this.licenseRepository,
  });

  final String id;
  final String name;
  final String description;
  final String repository;
  final String filename;
  final int sizeBytes;
  final String sha256;
  final String? downloadUrlOverride;
  final String? licenseRepository;

  String get sourceUrl => 'https://huggingface.co/$repository';
  String get licenseUrl =>
      'https://huggingface.co/${licenseRepository ?? repository}/blob/main/LICENSE';
  String get downloadUrl =>
      downloadUrlOverride ?? '$sourceUrl/resolve/main/$filename?download=true';

  static const officialModels = <LocalModelCatalogEntry>[
    LocalModelCatalogEntry(
      id: 'qwen2.5-0.5b-q4km',
      name: 'Qwen2.5 0.5B · Q4_K_M',
      description: 'Schnell · läuft auf fast allen Geräten',
      repository: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
      filename: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      sizeBytes: 491400032,
      sha256:
          '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db',
    ),
    LocalModelCatalogEntry(
      id: 'qwen3-1.7b-q4km',
      name: 'Qwen3 1.7B · Q4_K_M',
      description: 'Ausgewogen · bessere Texte, etwas langsamer',
      // Qwen publishes 1.7B only as Q8_0; this is Unsloth's quantization.
      repository: 'unsloth/Qwen3-1.7B-GGUF',
      licenseRepository: 'Qwen/Qwen3-1.7B',
      filename: 'Qwen3-1.7B-Q4_K_M.gguf',
      sizeBytes: 1107409472,
      sha256:
          'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897',
    ),
    LocalModelCatalogEntry(
      id: 'qwen3-4b-q4km',
      name: 'Qwen3 4B · Q4_K_M',
      description: 'Stark · deutlich besser, braucht länger',
      repository: 'Qwen/Qwen3-4B-GGUF',
      filename: 'Qwen3-4B-Q4_K_M.gguf',
      sizeBytes: 2497280256,
      sha256:
          '7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5',
    ),
    LocalModelCatalogEntry(
      id: 'qwen3-8b-q4km',
      name: 'Qwen3 8B · Q4_K_M',
      description: 'Beste Qualität · am langsamsten, ab ca. 12 GB RAM',
      repository: 'Qwen/Qwen3-8B-GGUF',
      filename: 'Qwen3-8B-Q4_K_M.gguf',
      sizeBytes: 5027783488,
      sha256:
          'd98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785',
    ),
  ];
}

class LocalModelDownloadCancelled implements Exception {
  const LocalModelDownloadCancelled();
}

class LocalModelDownloadException implements Exception {
  const LocalModelDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocalModelDownloadService {
  HttpClient? _client;
  bool _cancelRequested = false;

  void cancel() {
    _cancelRequested = true;
    _client?.close(force: true);
  }

  Future<File> download(
    LocalModelCatalogEntry model, {
    required Directory directory,
    required void Function(int receivedBytes) onProgress,
  }) async {
    _cancelRequested = false;
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, model.filename));
    final partial = File('${target.path}.part');
    final existingIsValid = await matchesExpectedFile(target, model);
    if (existingIsValid) return target;
    if (await target.exists()) await target.delete();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    _client = client;
    try {
      final request = await client.getUrl(Uri.parse(model.downloadUrl));
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      final response = await request.close();
      if (_cancelRequested) throw const LocalModelDownloadCancelled();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw LocalModelDownloadException(
          'Der Model-Server antwortete mit HTTP ${response.statusCode}.',
        );
      }
      if (response.contentLength > 0 &&
          response.contentLength != model.sizeBytes) {
        await response.drain<void>();
        throw const LocalModelDownloadException(
          'Die angekündigte Dateigröße stimmt nicht mit dem Modellkatalog überein.',
        );
      }

      final digestSink = _SingleDigestSink();
      final hashInput = sha256.startChunkedConversion(digestSink);
      final output = partial.openWrite();
      var receivedBytes = 0;
      var lastReportedBytes = 0;
      onProgress(0);
      try {
        await for (final chunk in response) {
          if (_cancelRequested) throw const LocalModelDownloadCancelled();
          receivedBytes += chunk.length;
          if (receivedBytes > model.sizeBytes) {
            throw const LocalModelDownloadException(
              'Der Download ist größer als die erwartete Modelldatei.',
            );
          }
          hashInput.add(chunk);
          output.add(chunk);
          if (receivedBytes - lastReportedBytes >= 512 * 1024 ||
              receivedBytes == model.sizeBytes) {
            lastReportedBytes = receivedBytes;
            onProgress(receivedBytes);
          }
        }
        await output.flush();
      } finally {
        await output.close();
      }
      hashInput.close();

      if (receivedBytes != model.sizeBytes ||
          digestSink.digest?.toString() != model.sha256) {
        throw const LocalModelDownloadException(
          'Dateigröße oder SHA-256-Prüfsumme stimmt nicht. Der Download wurde verworfen.',
        );
      }
      if (_cancelRequested) throw const LocalModelDownloadCancelled();
      return await partial.rename(target.path);
    } on LocalModelDownloadCancelled {
      rethrow;
    } on LocalModelDownloadException {
      rethrow;
    } catch (error) {
      if (_cancelRequested) throw const LocalModelDownloadCancelled();
      throw LocalModelDownloadException('Download fehlgeschlagen: $error');
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<bool> matchesExpectedFile(
    File file,
    LocalModelCatalogEntry model,
  ) async {
    if (!await file.exists() || await file.length() != model.sizeBytes) {
      return false;
    }
    final digestSink = _SingleDigestSink();
    final hashInput = sha256.startChunkedConversion(digestSink);
    await for (final chunk in file.openRead()) {
      hashInput.add(chunk);
    }
    hashInput.close();
    return digestSink.digest?.toString() == model.sha256;
  }
}

class _SingleDigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}

String formatModelSize(int bytes) {
  if (bytes >= 1000 * 1000 * 1000) {
    return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(2)} GB';
  }
  return '${(bytes / (1000 * 1000)).round()} MB';
}
