import 'package:flutter/services.dart';

/// 系统播放器兜底与视频轨道信息查询。
class SystemVideoPlayerService {
  static const MethodChannel _channel = MethodChannel(
    'app.packingproof.mobile/system_player',
  );

  /// 读取文件第一条视频轨的 mime（如 video/hevc、video/avc）；失败返回 null。
  Future<String?> getVideoTrackMime(String path) async {
    try {
      return await _channel.invokeMethod<String>(
        'getVideoTrackMime',
        <String, Object>{'path': path},
      );
    } on Object {
      return null;
    }
  }

  /// 用系统播放器打开本地录像文件。
  Future<void> openWithSystemPlayer(String path) async {
    await _channel.invokeMethod<void>('openWithSystemPlayer', <String, Object>{
      'path': path,
    });
  }
}
