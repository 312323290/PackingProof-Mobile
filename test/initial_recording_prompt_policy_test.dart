import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/recording_operation_mode.dart';
import 'package:packing_proof_mobile/models/speech_prompt.dart';
import 'package:packing_proof_mobile/services/initial_recording_prompt_policy.dart';

void main() {
  test('未识别面单时先按发货模式播报，首次识别后开始录制', () {
    final InitialRecordingPromptPolicy policy = InitialRecordingPromptPolicy()
      ..beginWork(RecordingOperationMode.shipping);

    expect(policy.onModeAnnouncementElapsed(), SpeechPrompt.shippingMode);
    expect(policy.onModeAnnouncementElapsed(), isNull);
    expect(policy.onFirstLabelRecognized(), SpeechPrompt.recordingStarted);
    expect(policy.onFirstLabelRecognized(), isNull);
  });

  test('退货模式下播报退货模式', () {
    final InitialRecordingPromptPolicy policy = InitialRecordingPromptPolicy()
      ..beginWork(RecordingOperationMode.returnGoods);

    expect(policy.onModeAnnouncementElapsed(), SpeechPrompt.returnMode);
    expect(policy.onModeAnnouncementElapsed(), isNull);
  });

  test('点击开始时已有面单只提示开始录制', () {
    final InitialRecordingPromptPolicy policy = InitialRecordingPromptPolicy()
      ..beginWork(RecordingOperationMode.shipping);

    expect(policy.onFirstLabelRecognized(), SpeechPrompt.recordingStarted);
    expect(policy.onModeAnnouncementElapsed(), isNull);
  });

  test('工作结束后不再提示模式', () {
    final InitialRecordingPromptPolicy policy = InitialRecordingPromptPolicy()
      ..beginWork(RecordingOperationMode.shipping)
      ..cancel();

    expect(policy.onModeAnnouncementElapsed(), isNull);
    expect(policy.onFirstLabelRecognized(), isNull);
  });
}
