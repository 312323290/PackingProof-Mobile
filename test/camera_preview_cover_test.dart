import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/screens/packing_home_screen.dart';

void main() {
  testWidgets('录像前后都按竖屏宽高比等比裁切', (WidgetTester tester) async {
    final ValueNotifier<CameraValue> cameraValue = ValueNotifier<CameraValue>(
      _cameraValue(previewSize: const Size(1920, 1080)),
    );
    addTearDown(cameraValue.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 390,
            height: 560,
            child: CameraPreviewCoverLayout(
              cameraValue: cameraValue,
              preview: const ColoredBox(color: Colors.green),
            ),
          ),
        ),
      ),
    );

    final FittedBox beforeRecording = tester.widget<FittedBox>(
      find.byType(FittedBox),
    );
    final Size initialNaturalSize = tester.getSize(
      find.byKey(const Key('camera-preview-natural-size')),
    );
    expect(beforeRecording.fit, BoxFit.cover);
    expect(initialNaturalSize.aspectRatio, closeTo(9 / 16, 0.001));
    expect(find.byType(RotatedBox), findsNothing);

    cameraValue.value = _cameraValue(
      previewSize: const Size(1440, 1080),
      isRecordingVideo: true,
    );
    await tester.pump();

    final Size recordingNaturalSize = tester.getSize(
      find.byKey(const Key('camera-preview-natural-size')),
    );
    expect(recordingNaturalSize.aspectRatio, closeTo(3 / 4, 0.001));
    expect(recordingNaturalSize.width, lessThan(recordingNaturalSize.height));
    expect(find.byType(RotatedBox), findsNothing);
  });

  testWidgets('已是竖屏尺寸时不会再次旋转宽高比', (WidgetTester tester) async {
    final ValueNotifier<CameraValue> cameraValue = ValueNotifier<CameraValue>(
      _cameraValue(previewSize: const Size(1080, 1920)),
    );
    addTearDown(cameraValue.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 390,
          height: 560,
          child: CameraPreviewCoverLayout(
            cameraValue: cameraValue,
            preview: const ColoredBox(color: Colors.green),
          ),
        ),
      ),
    );

    final Size naturalSize = tester.getSize(
      find.byKey(const Key('camera-preview-natural-size')),
    );
    expect(naturalSize.aspectRatio, closeTo(9 / 16, 0.001));
  });
}

CameraValue _cameraValue({
  required Size previewSize,
  bool isRecordingVideo = false,
}) {
  const CameraDescription description = CameraDescription(
    name: 'test-camera',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );
  return CameraValue(
    isInitialized: true,
    previewSize: previewSize,
    isRecordingVideo: isRecordingVideo,
    isTakingPicture: false,
    isStreamingImages: isRecordingVideo,
    isRecordingPaused: false,
    flashMode: FlashMode.off,
    exposureMode: ExposureMode.auto,
    focusMode: FocusMode.auto,
    exposurePointSupported: true,
    focusPointSupported: true,
    deviceOrientation: DeviceOrientation.portraitUp,
    lockedCaptureOrientation: DeviceOrientation.portraitUp,
    recordingOrientation: isRecordingVideo
        ? DeviceOrientation.portraitUp
        : null,
    description: description,
  );
}
