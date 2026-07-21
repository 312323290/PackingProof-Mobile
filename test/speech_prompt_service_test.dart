import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/speech_prompt.dart';
import 'package:packing_proof_mobile/services/speech_prompt_service.dart';

void main() {
  test('固定提示优先播放内置 Edge 语音', () async {
    final _FakeSpeechOutput output = _FakeSpeechOutput();
    final SpeechPromptService service = SpeechPromptService(output: output);

    service.enqueue(SpeechPrompt.recordingFailed);
    await service.waitUntilIdle();

    expect(output.assetPaths, <String>['audio/tts/recording_failed.mp3']);
    expect(output.systemTexts, isEmpty);
    await service.dispose();
  });

  test('固定语音资源损坏时回退离线系统语音', () async {
    final _FakeSpeechOutput output = _FakeSpeechOutput(failAssets: true);
    final SpeechPromptService service = SpeechPromptService(output: output);

    service.enqueue(SpeechPrompt.recordingFailed);
    await service.waitUntilIdle();

    expect(output.systemTexts, <String>['录制失败']);
    expect(output.offlineOnlyRequests, <bool>[true]);
    await service.dispose();
  });

  test('动态订单提示使用离线系统语音', () async {
    final _FakeSpeechOutput output = _FakeSpeechOutput();
    final SpeechPromptService service = SpeechPromptService(output: output);

    service.enqueueText('卖家备注，核对颜色');
    await service.waitUntilIdle();

    expect(output.systemTexts, <String>['卖家备注，核对颜色']);
    expect(output.offlineOnlyRequests, <bool>[true]);
    await service.dispose();
  });

  test('备注播报先播放提示音', () async {
    final _FakeSpeechOutput output = _FakeSpeechOutput();
    final SpeechPromptService service = SpeechPromptService(output: output);

    service.enqueueText('卖家备注，核对颜色', playRemarkTone: true);
    await service.waitUntilIdle();

    expect(output.remarkToneCount, 1);
    expect(output.systemTexts, <String>['卖家备注，核对颜色']);
    await service.dispose();
  });

  test('退款播报先播放一次电脑端同款工业警报音', () async {
    final _FakeSpeechOutput output = _FakeSpeechOutput();
    final SpeechPromptService service = SpeechPromptService(output: output);

    for (int index = 0; index < 2; index++) {
      service.enqueueText(
        '退款提醒，退款完成',
        priority: SpeechPromptPriority.warning,
        incidentKey: 'order-refund:TRACK-1:ORDER-1:SUCCESS',
        playWarningTone: true,
      );
    }
    await service.waitUntilIdle();

    expect(output.warningToneCount, 1);
    expect(output.remarkToneCount, 0);
    expect(output.systemTexts, <String>['退款提醒，退款完成']);
    await service.dispose();
  });

  test('同一故障恢复前只播报一次', () async {
    final _FakeSpeechOutput output = _FakeSpeechOutput();
    final SpeechPromptService service = SpeechPromptService(output: output);

    service.enqueue(SpeechPrompt.cameraDisconnected, incidentKey: 'camera');
    service.enqueue(SpeechPrompt.cameraDisconnected, incidentKey: 'camera');
    await service.waitUntilIdle();
    expect(output.assetPaths, hasLength(1));

    service.resolveIncident('camera');
    service.enqueue(SpeechPrompt.cameraDisconnected, incidentKey: 'camera');
    await service.waitUntilIdle();
    expect(output.assetPaths, hasLength(2));
    await service.dispose();
  });

  test('开始录制会打断仍在播放的准备就绪', () async {
    final _InterruptibleSpeechOutput output = _InterruptibleSpeechOutput();
    final SpeechPromptService service = SpeechPromptService(output: output);

    service.enqueue(SpeechPrompt.ready);
    while (output.assetPaths.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    service.enqueue(SpeechPrompt.recordingStarted);
    await service.waitUntilIdle();

    expect(output.assetPaths, <String>[
      'audio/tts/ready.mp3',
      'audio/tts/recording_started.mp3',
    ]);
    expect(output.stopCount, greaterThanOrEqualTo(1));
    await service.dispose();
  });
}

class _FakeSpeechOutput implements SpeechOutput {
  _FakeSpeechOutput({this.failAssets = false});

  final bool failAssets;
  final List<String> assetPaths = <String>[];
  final List<String> systemTexts = <String>[];
  final List<bool> offlineOnlyRequests = <bool>[];
  int remarkToneCount = 0;
  int warningToneCount = 0;

  @override
  Future<void> playAsset(String assetPath) async {
    assetPaths.add(assetPath);
    if (failAssets) throw StateError('asset unavailable');
  }

  @override
  Future<void> playRemarkTone() async => remarkToneCount++;

  @override
  Future<void> playWarningTone() async => warningToneCount++;

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

class _InterruptibleSpeechOutput extends _FakeSpeechOutput {
  final Completer<void> _readyPlayback = Completer<void>();
  int stopCount = 0;

  @override
  Future<void> playAsset(String assetPath) async {
    await super.playAsset(assetPath);
    if (assetPath == 'audio/tts/ready.mp3') await _readyPlayback.future;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    if (!_readyPlayback.isCompleted) _readyPlayback.complete();
  }
}
