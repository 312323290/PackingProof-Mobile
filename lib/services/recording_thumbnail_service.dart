import 'package:flutter/services.dart';

class RecordingThumbnailService {
  const RecordingThumbnailService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName =
      'app.packingproof.mobile/recording_thumbnail';
  final MethodChannel _channel;

  Future<String?> generate(String filePath) async {
    if (filePath.isEmpty) return null;
    try {
      return await _channel.invokeMethod<String>('generate', <String, Object>{
        'path': filePath,
      });
    } on PlatformException {
      return null;
    }
  }
}
