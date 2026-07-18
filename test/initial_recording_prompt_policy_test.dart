import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/speech_prompt.dart';
import 'package:packing_proof_mobile/services/initial_recording_prompt_policy.dart';

void main() {
  test('未识别面单时先准备就绪，首次识别后开始录制', () {
    final InitialRecordingPromptPolicy policy = InitialRecordingPromptPolicy()
      ..beginWork();

    expect(policy.onReadyDelayElapsed(), SpeechPrompt.ready);
    expect(policy.onReadyDelayElapsed(), isNull);
    expect(policy.onFirstLabelRecognized(), SpeechPrompt.recordingStarted);
    expect(policy.onFirstLabelRecognized(), isNull);
  });

  test('点击开始时已有面单只提示开始录制', () {
    final InitialRecordingPromptPolicy policy = InitialRecordingPromptPolicy()
      ..beginWork();

    expect(policy.onFirstLabelRecognized(), SpeechPrompt.recordingStarted);
    expect(policy.onReadyDelayElapsed(), isNull);
  });

  test('工作结束后不再提示准备就绪', () {
    final InitialRecordingPromptPolicy policy = InitialRecordingPromptPolicy()
      ..beginWork()
      ..cancel();

    expect(policy.onReadyDelayElapsed(), isNull);
    expect(policy.onFirstLabelRecognized(), isNull);
  });
}
