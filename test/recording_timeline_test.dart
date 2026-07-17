import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_lens/models/recording_session.dart';
import 'package:parcel_lens/services/recording_timeline.dart';

void main() {
  test('连续扫码只生成一个母视频并按识别时间形成独立片段', () {
    final RecordingTimeline timeline = RecordingTimeline();
    final DateTime startedAt = DateTime(2026, 7, 18, 9);
    timeline.start(startedAt);

    timeline.bindCode('CODE-001', startedAt.add(const Duration(seconds: 2)));
    timeline.startNext('CODE-002', startedAt.add(const Duration(seconds: 10)));
    final List<RecordingSession> sessions = timeline.buildSessions(
      endedAt: startedAt.add(const Duration(seconds: 20)),
      filePath: 'master.mp4',
      recordingId: 'recording-1',
    );

    expect(sessions, hasLength(2));
    expect(sessions.map((RecordingSession item) => item.filePath).toSet(), {
      'master.mp4',
    });
    expect(sessions.first.displayCode, 'CODE-001');
    expect(sessions.first.mediaStart, Duration.zero);
    expect(sessions.first.playbackEnd, const Duration(seconds: 10));
    expect(sessions.first.markers.single.offset, const Duration(seconds: 2));
    expect(sessions.last.displayCode, 'CODE-002');
    expect(sessions.last.mediaStart, const Duration(seconds: 10));
    expect(sessions.last.playbackEnd, const Duration(seconds: 20));
    expect(sessions.last.markers.single.offset, Duration.zero);
  });

  test('没有识别到面单时保留完整工作录像', () {
    final RecordingTimeline timeline = RecordingTimeline();
    final DateTime startedAt = DateTime(2026, 7, 18, 9);
    timeline.start(startedAt);

    final List<RecordingSession> sessions = timeline.buildSessions(
      endedAt: startedAt.add(const Duration(seconds: 8)),
      filePath: 'master.mp4',
      recordingId: 'recording-1',
    );

    expect(sessions, hasLength(1));
    expect(sessions.single.displayCode, '未识别面单');
    expect(sessions.single.duration, const Duration(seconds: 8));
    expect(sessions.single.mediaStart, Duration.zero);
    expect(sessions.single.playbackEnd, const Duration(seconds: 8));
  });
}
