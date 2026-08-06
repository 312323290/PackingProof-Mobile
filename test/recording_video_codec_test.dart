import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/recording_video_codec.dart';

void main() {
  test('编码枚举存储值与标签', () {
    expect(RecordingVideoCodec.hevc.storageValue, 'hevc');
    expect(RecordingVideoCodec.h264.storageValue, 'h264');
    expect(RecordingVideoCodec.hevc.label, contains('H.265'));
    expect(RecordingVideoCodec.h264.label, contains('H.264'));
    expect(RecordingVideoCodec.hevc.description, isNotEmpty);
    expect(RecordingVideoCodec.h264.description, isNotEmpty);
  });

  test('未知编码回退到默认 H.265', () {
    expect(recordingVideoCodecFromStorage(null), RecordingVideoCodec.hevc);
    expect(recordingVideoCodecFromStorage(''), RecordingVideoCodec.hevc);
    expect(recordingVideoCodecFromStorage('weird'), RecordingVideoCodec.hevc);
    expect(recordingVideoCodecFromStorage('h264'), RecordingVideoCodec.h264);
    expect(recordingVideoCodecFromStorage('avc'), RecordingVideoCodec.h264);
  });
}
