import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/controllers/packing_session_controller.dart';
import 'package:packing_proof_mobile/models/speech_prompt.dart';
import 'package:packing_proof_mobile/services/session_repository.dart';
import 'package:packing_proof_mobile/services/speech_prompt_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('packing-proof-controller-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('摄像头未就绪时保持静音', () async {
    final _FakeSpeechSink speech = _FakeSpeechSink();
    final PackingSessionController controller = PackingSessionController(
      repository: SessionRepository(rootDirectory: root),
      speechService: speech,
    );

    await controller.startWork();

    expect(speech.prompts, isEmpty);
  });

  test('语音开关同步服务并持久化', () async {
    final _FakeSpeechSink speech = _FakeSpeechSink();
    final SessionRepository repository = SessionRepository(rootDirectory: root);
    final PackingSessionController controller = PackingSessionController(
      repository: repository,
      speechService: speech,
    );

    await controller.setSpeechEnabled(false);

    expect(controller.speechEnabled, isFalse);
    expect(speech.enabled, isFalse);
    expect((await repository.loadSettings()).speechEnabled, isFalse);
  });
}

class _FakeSpeechSink implements SpeechPromptSink {
  final List<SpeechPrompt> prompts = <SpeechPrompt>[];

  @override
  bool enabled = true;

  @override
  void enqueue(SpeechPrompt prompt, {String? incidentKey}) {
    if (enabled) {
      prompts.add(prompt);
    }
  }

  @override
  Future<void> setEnabled(bool value) async => enabled = value;

  @override
  Future<void> preview() async {}

  @override
  void resetIncidents() {}

  @override
  void resolveIncident(String incidentKey) {}

  @override
  Future<void> dispose() async {}
}
