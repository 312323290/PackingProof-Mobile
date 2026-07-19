import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class VideoWatermarkSink {
  Future<String> apply({
    required String inputPath,
    required DateTime startedAt,
    required String trackingNumber,
  });
}

class VideoWatermarkService implements VideoWatermarkSink {
  VideoWatermarkService({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('app.packingproof.mobile/video_watermark');

  final MethodChannel _channel;

  @override
  Future<String> apply({
    required String inputPath,
    required DateTime startedAt,
    required String trackingNumber,
  }) async {
    if (!Platform.isAndroid) return inputPath;
    final int dot = inputPath.lastIndexOf('.');
    final String outputPath = dot > 0
        ? '${inputPath.substring(0, dot)}_watermarked.mp4'
        : '${inputPath}_watermarked.mp4';
    final String? result = await _channel.invokeMethod<String>('apply', {
      'inputPath': inputPath,
      'outputPath': outputPath,
      'startedAtMs': startedAt.millisecondsSinceEpoch,
      'trackingNumber': trackingNumber,
    });
    if (result == null || result.isEmpty || !await File(result).exists()) {
      throw StateError('水印视频生成失败');
    }
    if (result != inputPath) {
      await File(inputPath).delete().catchError((_) => File(inputPath));
    }
    return result;
  }
}
