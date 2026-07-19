import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/barcode_marker.dart';
import 'package:packing_proof_mobile/models/recording_session.dart';
import 'package:packing_proof_mobile/models/work_mode.dart';
import 'package:packing_proof_mobile/services/session_repository.dart';

void main() {
  test('录像记录可持久化并读取', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing_proof_mobile_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final File source = File(
      '${root.path}${Platform.pathSeparator}capture.mp4',
    );
    await source.writeAsBytes(<int>[0, 1, 2, 3]);
    final SessionRepository repository = SessionRepository(rootDirectory: root);
    final DateTime startedAt = DateTime(2026, 7, 16, 10);
    final String videoPath = await repository.finalizeVideo(
      sourcePath: source.path,
      sessionId: 'session-1',
      startedAt: startedAt,
      trackingNumber: 'JT1234567890',
    );
    final RecordingSession session = RecordingSession(
      id: 'session-1',
      filePath: videoPath,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 2)),
      markers: <BarcodeMarker>[
        BarcodeMarker(
          code: 'JT1234567890',
          occurredAt: startedAt.add(const Duration(seconds: 12)),
          offset: const Duration(seconds: 12),
        ),
      ],
      mediaStart: const Duration(seconds: 10),
      mediaEnd: const Duration(seconds: 130),
    );

    await repository.addSession(session);
    final List<RecordingSession> loaded = await repository.loadSessions();

    expect(loaded, hasLength(1));
    expect(loaded.single.displayCode, 'JT1234567890');
    expect(loaded.single.markers.single.offset, const Duration(seconds: 12));
    expect(loaded.single.mediaStart, const Duration(seconds: 10));
    expect(loaded.single.playbackEnd, const Duration(seconds: 130));
    expect(File(videoPath).existsSync(), isTrue);
    expect(
      videoPath,
      endsWith(
        '${Platform.pathSeparator}recordings${Platform.pathSeparator}2026-07-16'
        '${Platform.pathSeparator}JT1234567890_20260716_100000_发货.mp4',
      ),
    );
  });

  test('旧录像记录缺少片段区间时仍按完整视频播放', () {
    final DateTime startedAt = DateTime(2026, 7, 16, 10);
    final RecordingSession session = RecordingSession.fromJson(
      <String, Object?>{
        'id': 'legacy',
        'filePath': 'legacy.mp4',
        'startedAt': startedAt.toIso8601String(),
        'endedAt': startedAt.add(const Duration(seconds: 30)).toIso8601String(),
        'markers': <Object?>[],
      },
    );

    expect(session.mediaStart, Duration.zero);
    expect(session.playbackEnd, const Duration(seconds: 30));
  });

  test('剪辑录像只调整逻辑播放区间并保留面单号', () {
    final DateTime startedAt = DateTime(2026, 7, 18, 10);
    final RecordingSession session = RecordingSession(
      id: 'clip-1',
      filePath: 'master.mp4',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 20)),
      markers: <BarcodeMarker>[
        BarcodeMarker(
          code: 'JT1234567890',
          occurredAt: startedAt.add(const Duration(seconds: 3)),
          offset: const Duration(seconds: 3),
        ),
      ],
      mediaStart: const Duration(seconds: 10),
      mediaEnd: const Duration(seconds: 30),
    );

    final RecordingSession trimmed = session.trimmed(
      startOffset: const Duration(seconds: 2),
      endOffset: const Duration(seconds: 12),
    );

    expect(trimmed.displayCode, 'JT1234567890');
    expect(trimmed.duration, const Duration(seconds: 10));
    expect(trimmed.mediaStart, const Duration(seconds: 12));
    expect(trimmed.playbackEnd, const Duration(seconds: 22));
    expect(trimmed.markers.single.offset, const Duration(seconds: 1));
  });

  test('再次剪辑可按源视频绝对时间恢复之前裁掉的内容', () {
    final DateTime sourceStartedAt = DateTime(2026, 7, 18, 10);
    final RecordingSession clipped = RecordingSession(
      id: 'clip-restore',
      filePath: 'master.mp4',
      startedAt: sourceStartedAt.add(const Duration(seconds: 10)),
      endedAt: sourceStartedAt.add(const Duration(seconds: 20)),
      markers: <BarcodeMarker>[
        BarcodeMarker(
          code: 'JT1234567890',
          occurredAt: sourceStartedAt.add(const Duration(seconds: 12)),
          offset: const Duration(seconds: 2),
        ),
      ],
      mediaStart: const Duration(seconds: 10),
      mediaEnd: const Duration(seconds: 20),
    );

    final RecordingSession restored = clipped.trimmedToMediaRange(
      mediaStart: const Duration(seconds: 5),
      mediaEnd: const Duration(seconds: 25),
    );

    expect(restored.startedAt, sourceStartedAt.add(const Duration(seconds: 5)));
    expect(restored.endedAt, sourceStartedAt.add(const Duration(seconds: 25)));
    expect(restored.mediaStart, const Duration(seconds: 5));
    expect(restored.playbackEnd, const Duration(seconds: 25));
    expect(restored.markers.single.offset, const Duration(seconds: 7));
  });

  test('删除共享母视频的最后一个片段时才清理文件', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing_proof_mobile_delete_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final File source = File(
      '${root.path}${Platform.pathSeparator}capture.mp4',
    );
    await source.writeAsBytes(<int>[0, 1, 2, 3]);
    final SessionRepository repository = SessionRepository(rootDirectory: root);
    final String videoPath = await repository.finalizeVideo(
      sourcePath: source.path,
      sessionId: 'shared-recording',
      startedAt: DateTime(2026, 7, 18, 10),
      trackingNumber: '',
    );
    final DateTime startedAt = DateTime(2026, 7, 18, 10);
    final RecordingSession first = RecordingSession(
      id: 'clip-1',
      filePath: videoPath,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 10)),
      markers: const <BarcodeMarker>[],
    );
    final RecordingSession second = RecordingSession(
      id: 'clip-2',
      filePath: videoPath,
      startedAt: startedAt.add(const Duration(seconds: 10)),
      endedAt: startedAt.add(const Duration(seconds: 20)),
      markers: const <BarcodeMarker>[],
      mediaStart: const Duration(seconds: 10),
      mediaEnd: const Duration(seconds: 20),
    );
    await repository.addSessions(<RecordingSession>[first, second]);

    await repository.deleteSessions(<String>{first.id});
    expect(File(videoPath).existsSync(), isTrue);
    expect(await repository.loadSessions(), hasLength(1));

    await repository.deleteSessions(<String>{second.id});
    expect(File(videoPath).existsSync(), isFalse);
    expect(await repository.loadSessions(), isEmpty);
  });

  test('未识别面单和非法字符使用安全业务文件名且冲突追加会话后缀', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing_proof_mobile_name_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final SessionRepository repository = SessionRepository(rootDirectory: root);
    final DateTime startedAt = DateTime(2026, 7, 19, 9, 8, 7);
    final File firstSource = File('${root.path}/first.mp4')
      ..writeAsBytesSync(<int>[1]);
    final File secondSource = File('${root.path}/second.mp4')
      ..writeAsBytesSync(<int>[2]);
    final File unknownSource = File('${root.path}/unknown.mp4')
      ..writeAsBytesSync(<int>[3]);

    final String first = await repository.finalizeVideo(
      sourcePath: firstSource.path,
      sessionId: 'session-first',
      startedAt: startedAt,
      trackingNumber: 'SF:12/34',
    );
    final String second = await repository.finalizeVideo(
      sourcePath: secondSource.path,
      sessionId: 'session-second',
      startedAt: startedAt,
      trackingNumber: 'SF:12/34',
    );
    final String unknown = await repository.finalizeVideo(
      sourcePath: unknownSource.path,
      sessionId: 'session-unknown',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      trackingNumber: '',
    );

    expect(first, endsWith('SF_12_34_20260719_090807_发货.mp4'));
    expect(second, endsWith('SF_12_34_20260719_090807_发货_onsecond.mp4'));
    expect(unknown, endsWith('未识别面单_20260719_090808_发货.mp4'));
    expect(await repository.recordingPath('pending'), contains('.pending'));
  });

  test('工作模式可持久化并默认使用连续扫码', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing_proof_mobile_mode_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final SessionRepository repository = SessionRepository(rootDirectory: root);

    expect(await repository.loadWorkMode(), WorkMode.continuousScan);
    await repository.saveWorkMode(WorkMode.sameCodeStop);
    expect(await repository.loadWorkMode(), WorkMode.sameCodeStop);
  });
}
