import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class MaxVolumeSink {
  Future<void> beginSession();

  Future<void> endSession();

  Future<void> disable();

  Future<void> boost();

  Future<void> dispose();
}

class MaxVolumeService implements MaxVolumeSink {
  static const MethodChannel _channel = MethodChannel(
    'app.packingproof.mobile/system_volume',
  );

  @override
  Future<void> beginSession() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('beginSession');
    }
  }

  @override
  Future<void> endSession() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('endSession');
    }
  }

  @override
  Future<void> disable() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('disable');
    }
  }

  @override
  Future<void> boost() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('boost');
    }
  }

  @override
  Future<void> dispose() => endSession();
}
