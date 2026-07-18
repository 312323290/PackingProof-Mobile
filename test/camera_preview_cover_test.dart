import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/screens/packing_home_screen.dart';
import 'package:packing_proof_mobile/services/preview_cover_transform.dart';

void main() {
  testWidgets('录像前后都完整显示竖屏画面', (WidgetTester tester) async {
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

    final Size initialNaturalSize = tester.getSize(
      find.byKey(const Key('camera-preview-natural-size')),
    );
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

  testWidgets('原生纹理完整显示真实竖屏画面且保留过滤', (WidgetTester tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 390,
          height: 560,
          child: NativeCameraPreviewCover(
            textureId: 7,
            sourceSize: Size(1080, 1920),
          ),
        ),
      ),
    );

    final Size naturalSize = tester.getSize(
      find.byKey(const Key('native-camera-preview-natural-size')),
    );
    expect(naturalSize.aspectRatio, closeTo(9 / 16, 0.001));
    expect(
      tester.widget<Texture>(find.byType(Texture)).filterQuality,
      FilterQuality.low,
    );
  });

  test('完整显示模式保留全部源画面', () {
    final PreviewCoverTransform transform = PreviewCoverTransform.contain(
      sourceSize: const Size(1080, 1440),
      canvasSize: const Size(390, 560),
    );

    expect(transform.visibleSourceRect, Offset.zero & const Size(1080, 1440));
    expect(transform.sourceDestinationRect, transform.destinationRect);
    expect(transform.destinationRect.left, greaterThanOrEqualTo(0));
    expect(transform.destinationRect.top, greaterThanOrEqualTo(0));
    expect(transform.destinationRect.right, lessThanOrEqualTo(390));
    expect(transform.destinationRect.bottom, lessThanOrEqualTo(560));
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
