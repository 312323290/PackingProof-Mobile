import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/services/continuous_camera_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('原生初始化结果包含镜头方向和切换能力', () {
    final ContinuousCameraInitialization initialization =
        ContinuousCameraInitialization.fromMap(<Object?, Object?>{
          'textureId': 7,
          'previewWidth': 1920,
          'previewHeight': 1080,
          'sensorOrientation': 270,
          'fps': 30,
          'videoMime': 'video/hevc',
          'flashAvailable': false,
          'lensDirection': 'front',
          'canSwitchCamera': true,
        });

    expect(initialization.isFrontCamera, isTrue);
    expect(initialization.canSwitchCamera, isTrue);
    expect(initialization.flashAvailable, isFalse);
    expect(initialization.portraitPreviewSize, const Size(1080, 1920));
  });

  test('工作扫码使用独立的原生开关', () async {
    const MethodChannel channel = MethodChannel(
      'app.packingproof.mobile/continuous_camera',
    );
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return null;
        });
    final ContinuousCameraService service = ContinuousCameraService();

    await service.setWorkScanEnabled(true);

    expect(calls.single.method, 'setWorkScanEnabled');
    expect(calls.single.arguments, <String, Object>{'enabled': true});
    await service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
