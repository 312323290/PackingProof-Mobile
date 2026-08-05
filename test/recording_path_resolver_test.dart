import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:packing_proof_mobile/services/recording_path_resolver.dart';

void main() {
  group('等价前缀候选', () {
    test('user/0 与 data 双向互换', () {
      expect(
        alternateAppPrivateCandidates(
          '/data/user/0/app.packingproof.mobile/app_flutter/recordings/a.mp4',
        ),
        <String>[
          '/data/data/app.packingproof.mobile/app_flutter/recordings/a.mp4',
        ],
      );
      expect(
        alternateAppPrivateCandidates(
          '/data/data/app.packingproof.mobile/app_flutter/recordings/a.mp4',
        ),
        <String>[
          '/data/user/0/app.packingproof.mobile/app_flutter/recordings/a.mp4',
        ],
      );
    });

    test('非应用私有目录路径不生成候选', () {
      expect(
        alternateAppPrivateCandidates('/storage/emulated/0/a.mp4'),
        isEmpty,
      );
    });
  });

  test('提取 recordings 之后的相对路径', () {
    expect(
      relativeRecordingTail(
        '/data/user/0/pkg/app_flutter/recordings/2026-08-06/a.mp4',
      ),
      '2026-08-06/a.mp4',
    );
    expect(relativeRecordingTail('/data/x/a.mp4'), isNull);
  });

  group('RecordingPathResolver', () {
    late Directory root;
    late String recordingsRoot;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('path_resolver_test');
      recordingsRoot = p.join(root.path, 'recordings');
    });

    tearDown(() => root.delete(recursive: true));

    test('数据库路径失效但文件按相对路径可找到时自动修复', () async {
      final File file = File(p.join(recordingsRoot, '2026-08-06', 'abc.mp4'));
      await file.create(recursive: true);
      final RecordingPathResolution resolution = await RecordingPathResolver(
        recordingsRoot,
      ).resolve('/data/data/pkg/app_flutter/recordings/2026-08-06/abc.mp4');

      expect(resolution.resolvedPath, file.path);
      expect(resolution.repaired, isTrue);
    });

    test('原始路径仍有效时不修复', () async {
      final File file = File(p.join(recordingsRoot, '2026-08-06', 'abc.mp4'));
      await file.create(recursive: true);
      final RecordingPathResolution resolution = await RecordingPathResolver(
        recordingsRoot,
      ).resolve(file.path);

      expect(resolution.resolvedPath, file.path);
      expect(resolution.repaired, isFalse);
    });

    test('文件被移动到其他日期目录后可按文件名找回', () async {
      final File moved = File(p.join(recordingsRoot, '2026-08-06', 'abc.mp4'));
      await moved.create(recursive: true);
      final RecordingPathResolution resolution = await RecordingPathResolver(
        recordingsRoot,
      ).resolve('/data/user/0/old/app_flutter/recordings/2026-07-01/abc.mp4');

      expect(resolution.resolvedPath, moved.path);
    });

    test('待处理目录中的同名文件不会被当作正式录像', () async {
      final File pending = File(p.join(recordingsRoot, '.pending', 'abc.mp4'));
      final File finalFile = File(
        p.join(recordingsRoot, '2026-08-06', 'abc.mp4'),
      );
      await pending.create(recursive: true);
      await finalFile.create(recursive: true);
      final RecordingPathResolution resolution = await RecordingPathResolver(
        recordingsRoot,
      ).resolve('/data/user/0/pkg/app_flutter/recordings/2026-07-01/abc.mp4');

      expect(resolution.resolvedPath, finalFile.path);
    });

    test('真实缺失返回 null 并记录尝试过的候选', () async {
      final RecordingPathResolution resolution = await RecordingPathResolver(
        recordingsRoot,
      ).resolve('/data/user/0/pkg/app_flutter/recordings/2026-08-06/gone.mp4');

      expect(resolution.resolvedPath, isNull);
      expect(resolution.attemptedPaths, isNotEmpty);
    });
  });
}
