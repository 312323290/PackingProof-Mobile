enum RecordingVideoCodec { h264, hevc }

extension RecordingVideoCodecDetails on RecordingVideoCodec {
  String get storageValue => switch (this) {
    RecordingVideoCodec.h264 => 'h264',
    RecordingVideoCodec.hevc => 'hevc',
  };

  String get label => switch (this) {
    RecordingVideoCodec.h264 => 'H.264 兼容优先',
    RecordingVideoCodec.hevc => 'H.265 更省空间',
  };

  String get description => switch (this) {
    RecordingVideoCodec.h264 => '兼容性最好，几乎所有手机都能播放；文件体积约增加 30–40%。',
    RecordingVideoCodec.hevc => '默认编码，文件更小；个别设备解码兼容性较差。',
  };
}

RecordingVideoCodec recordingVideoCodecFromStorage(Object? value) {
  final String normalized = '$value'.trim().toLowerCase();
  return switch (normalized) {
    'h264' || 'avc' => RecordingVideoCodec.h264,
    _ => RecordingVideoCodec.hevc,
  };
}
