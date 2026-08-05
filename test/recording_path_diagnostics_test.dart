import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/services/recording_path_diagnostics.dart';

void main() {
  test('解析失败记录写入诊断文件并可导出', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'path_diagnostics_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final RecordingPathDiagnostics diagnostics = RecordingPathDiagnostics(
      rootProvider: () async => root,
    );

    expect(await diagnostics.exportText(), isNull);

    await diagnostics.recordMissing(
      storedPath: '/data/user/0/pkg/app_flutter/recordings/a.mp4',
      recordingsRoot: '/data/user/0/pkg/app_flutter/recordings',
      attemptedPaths: <String>['/data/user/0/pkg/app_flutter/recordings/a.mp4'],
    );

    final String? text = await diagnostics.exportText();
    expect(text, isNotNull);
    expect(text, contains('/data/user/0/pkg/app_flutter/recordings/a.mp4'));
  });

  test('诊断文件最多保留 200 条', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'path_diagnostics_bounded_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final RecordingPathDiagnostics diagnostics = RecordingPathDiagnostics(
      rootProvider: () async => root,
    );

    for (int index = 0; index < 205; index++) {
      await diagnostics.recordMissing(
        storedPath: '/data/user/0/pkg/a_$index.mp4',
        recordingsRoot: '/data/user/0/pkg/recordings',
        attemptedPaths: const <String>[],
      );
    }

    final String? text = await diagnostics.exportText();
    expect(text, isNotNull);
    expect(text!.split('\n'), hasLength(200));
  });
}
