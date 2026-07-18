import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:parcel_lens/services/continuous_camera_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('原生录像不停相机即可生成两个独立分片', (WidgetTester tester) async {
    if (!Platform.isAndroid) {
      return;
    }
    final Directory root = await getApplicationDocumentsDirectory();
    final Directory output = Directory(p.join(root.path, 'integration-test'));
    await output.create(recursive: true);
    final File first = File(p.join(output.path, 'segment-1.mp4'));
    final File second = File(p.join(output.path, 'segment-2.mp4'));
    for (final File file in <File>[first, second]) {
      if (await file.exists()) {
        await file.delete();
      }
    }

    final ContinuousCameraService camera = ContinuousCameraService();
    addTearDown(camera.dispose);
    final ContinuousCameraInitialization initialization = await camera
        .initialize();
    expect(initialization.textureId, greaterThanOrEqualTo(0));
    expect(initialization.fps, 30);

    final NativeRecordingStart started = await camera.startWork(first.path);
    expect(started.path, first.path);
    await Future<void>.delayed(const Duration(seconds: 4));

    final NativeRecordingSplit split = await camera.split(second.path);
    expect(split.completedPath, first.path);
    expect(split.nextPath, second.path);
    expect(split.boundaryAt.isAfter(started.startedAt), isTrue);
    await Future<void>.delayed(const Duration(seconds: 4));

    final NativeRecordingStop stopped = await camera.stopWork();
    expect(stopped.path, second.path);
    expect(await first.length(), greaterThan(100000));
    expect(await second.length(), greaterThan(100000));
  });
}
