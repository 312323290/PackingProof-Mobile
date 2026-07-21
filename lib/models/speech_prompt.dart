enum SpeechPromptPriority { normal, warning }

enum SpeechPrompt {
  ready(text: '准备就绪', priority: SpeechPromptPriority.normal),
  recordingStarted(text: '开始录制', priority: SpeechPromptPriority.normal),
  recordingStopped(text: '停止录制', priority: SpeechPromptPriority.normal),
  previewEnabled(text: '语音提示已开启', priority: SpeechPromptPriority.normal),
  cameraNotReady(text: '摄像头未就绪', priority: SpeechPromptPriority.warning),
  cameraNotFound(text: '未检测到摄像头', priority: SpeechPromptPriority.warning),
  permissionRequired(
    text: '需要摄像头和麦克风权限',
    priority: SpeechPromptPriority.warning,
  ),
  recordingFailed(text: '录制失败', priority: SpeechPromptPriority.warning),
  audioRecordingFailed(text: '声音录制异常', priority: SpeechPromptPriority.warning),
  videoFileCreateFailed(
    text: '录像文件创建失败',
    priority: SpeechPromptPriority.warning,
  ),
  segmentSaveFailed(text: '录像分段保存失败', priority: SpeechPromptPriority.warning),
  recordingSaveFailed(text: '录像保存失败', priority: SpeechPromptPriority.warning),
  cameraDisconnected(text: '摄像头连接已断开', priority: SpeechPromptPriority.warning);

  const SpeechPrompt({required this.text, required this.priority});

  final String text;
  final SpeechPromptPriority priority;
}
