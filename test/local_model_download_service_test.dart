hiimport 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filterlos_ich/services/local_model_download_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late StreamSubscription<HttpRequest> serverSubscription;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model_download_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverSubscription = server.listen((request) async {
      request.response
        ..headers.contentLength = 3
        ..add(utf8.encode('abc'));
      await request.response.close();
    });
  });

  tearDown(() async {
    await serverSubscription.cancel();
    await server.close(force: true);
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  LocalModelCatalogEntry testModel({String? checksum}) {
    return LocalModelCatalogEntry(
      id: 'test',
      name: 'Test model',
      repository: 'test/model',
      filename: 'test.gguf',
      sizeBytes: 3,
      sha256:
          checksum ??
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      downloadUrlOverride: 'http://127.0.0.1:${server.port}/model',
    );
  }

  test('keeps the file only after its checksum is verified', () async {
    final service = LocalModelDownloadService();
    final progress = <int>[];

    final downloaded = await service.download(
      testModel(),
      directory: directory,
      onProgress: progress.add,
    );

    expect(await downloaded.readAsString(), 'abc');
    expect(progress, [0, 3]);
    expect(await service.matchesExpectedFile(downloaded, testModel()), isTrue);
  });

  test('deletes partial output when the checksum is invalid', () async {
    final service = LocalModelDownloadService();

    await expectLater(
      service.download(
        testModel(checksum: '0' * 64),
        directory: directory,
        onProgress: (_) {},
      ),
      throwsA(isA<LocalModelDownloadException>()),
    );

    expect(await File('${directory.path}/test.gguf').exists(), isFalse);
    expect(await File('${directory.path}/test.gguf.part').exists(), isFalse);
  });
}
