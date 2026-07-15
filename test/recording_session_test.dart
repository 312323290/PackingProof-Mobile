import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_lens/models/barcode_marker.dart';
import 'package:parcel_lens/models/recording_session.dart';
import 'package:parcel_lens/services/session_repository.dart';

void main() {
  test('录像记录可持久化并读取', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'parcel_lens_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final File source = File(
      '${root.path}${Platform.pathSeparator}capture.mp4',
    );
    await source.writeAsBytes(<int>[0, 1, 2, 3]);
    final SessionRepository repository = SessionRepository(rootDirectory: root);
    final DateTime startedAt = DateTime(2026, 7, 16, 10);
    final String videoPath = await repository.persistVideo(
      source.path,
      'session-1',
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
    );

    await repository.addSession(session);
    final List<RecordingSession> loaded = await repository.loadSessions();

    expect(loaded, hasLength(1));
    expect(loaded.single.displayCode, 'JT1234567890');
    expect(loaded.single.markers.single.offset, const Duration(seconds: 12));
    expect(File(videoPath).existsSync(), isTrue);
  });
}
