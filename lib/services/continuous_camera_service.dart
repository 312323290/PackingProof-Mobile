import 'dart:async';

import 'package:flutter/services.dart';

class ContinuousCameraInitialization {
  const ContinuousCameraInitialization({
    required this.textureId,
    required this.previewWidth,
    required this.previewHeight,
    required this.sensorOrientation,
    required this.fps,
    required this.videoMime,
    required this.flashAvailable,
    required this.lensDirection,
    required this.canSwitchCamera,
  });

  final int textureId;
  final int previewWidth;
  final int previewHeight;
  final int sensorOrientation;
  final int fps;
  final String videoMime;
  final bool flashAvailable;
  final String lensDirection;
  final bool canSwitchCamera;

  bool get isFrontCamera => lensDirection == 'front';

  Size get portraitPreviewSize {
    final bool swapsDimensions =
        sensorOrientation == 90 || sensorOrientation == 270;
    return swapsDimensions
        ? Size(previewHeight.toDouble(), previewWidth.toDouble())
        : Size(previewWidth.toDouble(), previewHeight.toDouble());
  }

  factory ContinuousCameraInitialization.fromMap(Map<Object?, Object?> map) {
    return ContinuousCameraInitialization(
      textureId: (map['textureId']! as num).toInt(),
      previewWidth: (map['previewWidth']! as num).toInt(),
      previewHeight: (map['previewHeight']! as num).toInt(),
      sensorOrientation: (map['sensorOrientation']! as num).toInt(),
      fps: (map['fps']! as num).toInt(),
      videoMime: map['videoMime']! as String,
      flashAvailable: map['flashAvailable'] == true,
      lensDirection: '${map['lensDirection'] ?? 'back'}',
      canSwitchCamera: map['canSwitchCamera'] == true,
    );
  }
}

class NativeRecordingStart {
  const NativeRecordingStart({required this.path, required this.startedAt});

  final String path;
  final DateTime startedAt;

  factory NativeRecordingStart.fromMap(Map<Object?, Object?> map) {
    return NativeRecordingStart(
      path: map['path']! as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['startedAtMs']! as num).toInt(),
      ),
    );
  }
}

class NativeRecordingSplit {
  const NativeRecordingSplit({
    required this.completedPath,
    required this.nextPath,
    required this.completedStartedAt,
    required this.boundaryAt,
  });

  final String completedPath;
  final String nextPath;
  final DateTime completedStartedAt;
  final DateTime boundaryAt;

  factory NativeRecordingSplit.fromMap(Map<Object?, Object?> map) {
    return NativeRecordingSplit(
      completedPath: map['completedPath']! as String,
      nextPath: map['nextPath']! as String,
      completedStartedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['completedStartedAtMs']! as num).toInt(),
      ),
      boundaryAt: DateTime.fromMillisecondsSinceEpoch(
        (map['boundaryAtMs']! as num).toInt(),
      ),
    );
  }
}

class NativeRecordingStop {
  const NativeRecordingStop({
    required this.path,
    required this.startedAt,
    required this.endedAt,
  });

  final String path;
  final DateTime startedAt;
  final DateTime endedAt;

  factory NativeRecordingStop.fromMap(Map<Object?, Object?> map) {
    return NativeRecordingStop(
      path: map['path']! as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['startedAtMs']! as num).toInt(),
      ),
      endedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['endedAtMs']! as num).toInt(),
      ),
    );
  }
}

class NativeBarcodeCandidate {
  const NativeBarcodeCandidate({required this.value, required this.area});

  final String value;
  final int area;
}

class ContinuousCameraService {
  static const MethodChannel _channel = MethodChannel(
    'app.packingproof.mobile/continuous_camera',
  );

  ContinuousCameraService() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  void Function(List<NativeBarcodeCandidate> candidates)? onBarcodeFrame;
  void Function(String message)? onError;
  void Function()? onStorageCritical;

  Future<ContinuousCameraInitialization> initialize() async {
    final Map<Object?, Object?> values = (await _channel
        .invokeMethod<Map<Object?, Object?>>('initialize'))!;
    return ContinuousCameraInitialization.fromMap(values);
  }

  Future<NativeRecordingStart> startWork(
    String path, {
    required bool recordAudio,
  }) async {
    final Map<Object?, Object?> values = (await _channel
        .invokeMethod<Map<Object?, Object?>>('startWork', <String, Object>{
          'path': path,
          'recordAudio': recordAudio,
        }))!;
    return NativeRecordingStart.fromMap(values);
  }

  Future<NativeRecordingSplit> split(String nextPath) async {
    final Map<Object?, Object?> values = (await _channel
        .invokeMethod<Map<Object?, Object?>>('split', <String, Object>{
          'path': nextPath,
        }))!;
    return NativeRecordingSplit.fromMap(values);
  }

  Future<NativeRecordingStop> stopWork() async {
    final Map<Object?, Object?> values = (await _channel
        .invokeMethod<Map<Object?, Object?>>('stopWork'))!;
    return NativeRecordingStop.fromMap(values);
  }

  Future<void> setPairingScanEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setPairingScanEnabled', <String, Object>{
      'enabled': enabled,
    });
  }

  Future<void> setWorkScanEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setWorkScanEnabled', <String, Object>{
      'enabled': enabled,
    });
  }

  Future<void> setPreviewActive(bool active) async {
    await _channel.invokeMethod<void>('setPreviewActive', <String, Object>{
      'active': active,
    });
  }

  Future<bool> setTorchEnabled(bool enabled) async {
    return (await _channel.invokeMethod<bool>(
          'setTorchEnabled',
          <String, Object>{'enabled': enabled},
        )) ??
        false;
  }

  Future<ContinuousCameraInitialization> switchCamera() async {
    final Map<Object?, Object?> values = (await _channel
        .invokeMethod<Map<Object?, Object?>>('switchCamera'))!;
    return ContinuousCameraInitialization.fromMap(values);
  }

  Future<void> dispose() async {
    onBarcodeFrame = null;
    onError = null;
    onStorageCritical = null;
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod<void>('dispose');
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'barcodeFrame':
        final List<Object?> values = List<Object?>.from(
          call.arguments! as List,
        );
        onBarcodeFrame?.call(
          values
              .map((Object? value) {
                final Map<Object?, Object?> map = Map<Object?, Object?>.from(
                  value! as Map,
                );
                return NativeBarcodeCandidate(
                  value: map['value']! as String,
                  area: (map['area']! as num).toInt(),
                );
              })
              .toList(growable: false),
        );
      case 'nativeError':
        onError?.call(call.arguments?.toString() ?? '原生录像发生未知错误');
      case 'storageCritical':
        onStorageCritical?.call();
    }
  }
}
