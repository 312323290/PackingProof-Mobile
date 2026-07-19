import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/lan_backup.dart';

void main() {
  test('电脑录像缺少播放地址时默认请求 H.265 原视频', () {
    final RemoteRecording recording = RemoteRecording.fromJson(
      <String, Object?>{
        'id': 7,
        'startTime': '2026-07-20T09:10:11',
        'durationSec': 8,
      },
      Uri.parse('http://192.168.1.20:5280/'),
    );

    expect(recording.playUri.queryParameters['compat'], '0');
  });
}
