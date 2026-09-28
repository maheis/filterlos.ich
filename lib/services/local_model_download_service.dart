import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class LocalModelCatalogEntry {
  const LocalModelCatalogEntry({
    required this.id,
    required this.name,
    required this.repository,
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
    this.downloadUrlOverride,
  });

  final String id;
  final String name;
  final String repository;
  final String filename;
  final int sizeBytes;
  final String sha256;
  final String? downloadUrlOverride;

  String get sourceUrl => 'https://huggingface.co/$repository';
  String get licenseUrl => '$sourceUrl/blob/main/LICENSE';
  String get downloadUrl =>
      downloadUrlOverride ?? '$sourceUrl/resolve/main/$filename?download=true';

  static const officialModels = <LocalModelCatalogEntry>[
    LocalModelCatalogEntry(
      id: 'qwen3-0.6b-q8',
      name: 'Qwen3 0.6B · Q8_0',
      repository: 'Qwen/Qwen3-0.6B-GGUF',
      filename: 'Qwen3-0.6B-Q8_0.gguf',
      sizeBytes: 639446688,
      sha256:
          '9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031',
    ),
    LocalModelCatalogEntry(
      id: 'qwen3-1.7b-q8',
      name: 'Qwen3 1.7B · Q8_0',
      repository: 'Qwen/Qwen3-1.7B-GGUF',
      filename: 'Qwen3-1.7B-Q8_0.gguf',
      sizeBytes: 1834426016,
      sha256:
          '061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a',
    ),
    LocalModelCatalogEntry(
      id: 'qwen3-4b-q4km',
      name: 'Qwen3 4B · Q4_K_M',
      repository: 'Qwen/Qwen3-4B-GGUF',
      filename: 'Qwen3-4B-Q4_K_M.gguf',
      sizeBytes: 2497280256,
      sha256:
          '7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5',
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
    final existingIsValid = await _matchesExpectedFile(target, model);
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

  Future<bool> _matchesExpectedFile(
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
