import '../models/speech_prompt.dart';

class InitialRecordingPromptPolicy {
  bool _active = false;
  bool _readyAnnounced = false;
  bool _recordingStartedAnnounced = false;

  void beginWork() {
    _active = true;
    _readyAnnounced = false;
    _recordingStartedAnnounced = false;
  }

  SpeechPrompt? onReadyDelayElapsed() {
    if (!_active || _readyAnnounced || _recordingStartedAnnounced) {
      return null;
    }
    _readyAnnounced = true;
    return SpeechPrompt.ready;
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
