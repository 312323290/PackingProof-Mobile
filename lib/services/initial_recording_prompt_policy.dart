import '../models/recording_operation_mode.dart';
import '../models/speech_prompt.dart';

class InitialRecordingPromptPolicy {
  bool _active = false;
  bool _modeAnnounced = false;
  bool _recordingStartedAnnounced = false;
  RecordingOperationMode _mode = RecordingOperationMode.shipping;

  void beginWork(RecordingOperationMode mode) {
    _active = true;
    _mode = mode;
    _modeAnnounced = false;
    _recordingStartedAnnounced = false;
  }

  SpeechPrompt? onModeAnnouncementElapsed() {
    if (!_active || _modeAnnounced || _recordingStartedAnnounced) {
      return null;
    }
    _modeAnnounced = true;
    return _mode == RecordingOperationMode.returnGoods
        ? SpeechPrompt.returnMode
        : SpeechPrompt.shippingMode;
  }

  SpeechPrompt? onFirstLabelRecognized() {
    if (!_active || _recordingStartedAnnounced) {
      return null;
    }
    _recordingStartedAnnounced = true;
    return SpeechPrompt.recordingStarted;
  }

  void cancel() {
    _active = false;
  }
}
