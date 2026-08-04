import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/screens/video_playback_screen.dart';

void main() {
  test('本地播放失败文案区分文件缺失、损坏与已备份离线', () {
    expect(
      localPlaybackErrorMessage(fileExists: false, backedUpOffline: false),
      '录像文件不在本机，可能已被清理，无法播放',
    );
    expect(
      localPlaybackErrorMessage(fileExists: true, backedUpOffline: false),
      '录像文件不完整或已损坏，无法播放（可能是异常退出导致）',
    );
    expect(
      localPlaybackErrorMessage(fileExists: false, backedUpOffline: true),
      '录像已备份到电脑，电脑离线时暂时无法播放，请连接电脑后重试',
    );
    expect(
      localPlaybackErrorMessage(fileExists: true, backedUpOffline: true),
      '录像已备份到电脑，电脑离线时暂时无法播放，请连接电脑后重试',
    );
  });
}
