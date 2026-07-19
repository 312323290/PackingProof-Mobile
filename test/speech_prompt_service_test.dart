import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/speech_prompt.dart';
import 'package:packing_proof_mobile/services/speech_prompt_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('packing-proof-speech-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('缓存键包含文本、音色和格式版本', () {
    expect(
      SpeechPromptCache.cacheKey(SpeechPrompt.recordingStarted),
      SpeechPromptCache.cacheKey(SpeechPrompt.recordingStarted),
    );
    expect(
      SpeechPromptCache.cacheKey(SpeechPrompt.recordingStarted),
      isNot(SpeechPromptCache.cacheKey(SpeechPrompt.recordingStopped)),
    );
  });

  test('损坏缓存会被移除', () async {
    final SpeechPromptCache cache = SpeechPromptCache.inDirectory(root);
    final File corrupt = File(
      '${root.path}/${SpeechPromptCache.cacheKey(SpeechPrompt.recordingStarted)}.mp3',
    );
    await corrupt.writeAsBytes(<int>[1, 2, 3]);

    expect(await cache.find(SpeechPrompt.recordingStarted), isNull);
    expect(await corrupt.exists(), isFalse);
  });

  test('缓存超过上限时清理最旧文件', () async {
    final SpeechPromptCache cache = SpeechPromptCache.inDirectory(
      root,
      maxBytes: 300,
    );
    final File first = await cache.store(
      SpeechPrompt.recordingStarted,
      _mp3Bytes(200),
    );
    await first.setLastModified(DateTime(2020));
    final File second = await cache.store(
      SpeechPrompt.recordingStopped,
      _mp3Bytes(200),
    );

    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);
  });

  test('没有内置资源时生成 Edge 缓存并复用', () async {
    final _FakeSpeechOutput firstOutput = _FakeSpeechOutput();
    final _FakeEdgeGenerator generator = _FakeEdgeGenerator(_mp3Bytes(200));
    final SpeechPromptCache cache = SpeechPromptCache.inDirectory(root);
    final SpeechPromptService firstService = SpeechPromptService(
      output: firstOutput,
      edgeGenerator: generator,
      cache: cache,
      assetBundle: _MissingAssetBundle(),
    );

    firstService.enqueue(SpeechPrompt.recordingStarted);
    await firstService.waitUntilIdle();
    expect(generator.calls, 1);
    expect(firstOutput.files, hasLength(1));
    await firstService.dispose();

    final _FakeSpeechOutput secondOutput = _FakeSpeechOutput();
    final _FakeEdgeGenerator unavailable = _FakeEdgeGenerator(null);
    final SpeechPromptService secondService = SpeechPromptService(
      output: secondOutput,
      edgeGenerator: unavailable,
      cache: cache,
      assetBundle: _MissingAssetBundle(),
    );
    secondService.enqueue(SpeechPrompt.recordingStarted);
    await secondService.waitUntilIdle();
    expect(unavailable.calls, 0);
    expect(secondOutput.files, hasLength(1));
    await secondService.dispose();
  });

  test('Edge 不可用时回退系统语音', () async {
    final _FakeSpeechOutput output = _FakeSpeechOutput();
    final SpeechPromptService service = SpeechPromptService(
      output: output,
      edgeGenerator: _FakeEdgeGenerator(null),
      cache: SpeechPromptCache.inDirectory(root),
      assetBundle: _MissingAssetBundle(),
    );

    service.enqueue(SpeechPrompt.recordingFailed);
    await service.waitUntilIdle();
    expect(output.systemTexts, <String>['录制失败']);
    await service.dispose();
  });

  test('单机模式不调用 Edge 在线生成', () async {
    final _FakeSpeechOutput output = _FakeSpeechOutput();
    final _FakeEdgeGenerator generator = _FakeEdgeGenerator(_mp3Bytes(200));
    final SpeechPromptService service = SpeechPromptService(
      output: output,
      edgeGenerator: generator,
      cache: SpeechPromptCache.inDirectory(root),
      assetBundle: _MissingAssetBundle(),
      onlineEdgeTtsEnabled: false,
      offlineSystemTtsOnly: true,
    );

    service.enqueue(SpeechPrompt.recordingFailed);
    await service.waitUntilIdle();
    expect(generator.calls, 0);
    expect(output.systemTexts, <String>['录制失败']);
    expect(output.offlineOnlyRequests, <bool>[true]);
    await service.dispose();
  });

  test('同一故障恢复前只播报一次', () async {
    final _FakeSpeechOutput output = _FakeSpeechOutput();
    final SpeechPromptService service = SpeechPromptService(
      output: output,
      edgeGenerator: _FakeEdgeGenerator(null),
      cache: SpeechPromptCache.inDirectory(root),
      assetBundle: _PresentAssetBundle(),
    );

    service.enqueue(SpeechPrompt.cameraDisconnected, incidentKey: 'camera');
    service.enqueue(SpeechPrompt.cameraDisconnected, incidentKey: 'camera');
    await service.waitUntilIdle();
    expect(output.assets, hasLength(1));

    service.resetIncidents();
    service.enqueue(SpeechPrompt.cameraDisconnected, incidentKey: 'camera');
    await service.waitUntilIdle();
    expect(output.assets, hasLength(2));
    await service.dispose();
  });
}

Uint8List _mp3Bytes(int payloadLength) => Uint8List.fromList(<int>[
  0x49,
  0x44,
  0x33,
  ...List<int>.filled(payloadLength, 0),
]);

class _FakeSpeechOutput implements SpeechOutput {
  final List<String> assets = <String>[];
  final List<String> files = <String>[];
  final List<String> systemTexts = <String>[];
  final List<bool> offlineOnlyRequests = <bool>[];

  @override
  Future<void> playAsset(String assetPath) async => assets.add(assetPath);

  @override
  Future<void> playFile(String filePath) async => files.add(filePath);

  @override
  Future<void> speakSystem(String text, {bool offlineOnly = false}) async {
    systemTexts.add(text);
    offlineOnlyRequests.add(offlineOnly);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeEdgeGenerator implements EdgeSpeechGenerator {
  _FakeEdgeGenerator(this.bytes);

  final Uint8List? bytes;
  int calls = 0;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
  }) async {
    calls++;
    if (bytes == null) {
      throw StateError('offline');
    }
    return bytes!;
  }
}

class _MissingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future<ByteData>.error('missing');
}

class _PresentAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(200);
}
