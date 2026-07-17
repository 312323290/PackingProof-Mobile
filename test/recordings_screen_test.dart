import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_lens/models/barcode_marker.dart';
import 'package:parcel_lens/models/recording_session.dart';
import 'package:parcel_lens/models/work_mode.dart';
import 'package:parcel_lens/screens/recordings_screen.dart';

void main() {
  testWidgets('录像页面可切换工作模式', (WidgetTester tester) async {
    WorkMode selected = WorkMode.continuousScan;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: const [],
          workMode: selected,
          onWorkModeChanged: (WorkMode mode) async {
            selected = mode;
          },
        ),
      ),
    );

    expect(find.byKey(const Key('work-mode-settings')), findsOneWidget);
    expect(find.text('连续扫码'), findsOneWidget);
    expect(find.text('同码停录'), findsOneWidget);

    await tester.tap(find.text('同码停录'));
    await tester.pump();

    expect(selected, WorkMode.sameCodeStop);
    expect(find.textContaining('再次识别当前面单'), findsOneWidget);
  });

  testWidgets('录像卡片不重复显示内部识别标记数量', (WidgetTester tester) async {
    final DateTime startedAt = DateTime(2026, 7, 18, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: <RecordingSession>[
            RecordingSession(
              id: 'recording-1',
              filePath: 'master.mp4',
              startedAt: startedAt,
              endedAt: startedAt.add(const Duration(seconds: 8)),
              markers: <BarcodeMarker>[
                BarcodeMarker(
                  code: 'CODE-001',
                  occurredAt: startedAt,
                  offset: Duration.zero,
                ),
              ],
            ),
          ],
          workMode: WorkMode.continuousScan,
          onWorkModeChanged: (_) async {},
        ),
      ),
    );

    expect(find.text('CODE-001'), findsOneWidget);
    expect(find.textContaining('00:08'), findsOneWidget);
    expect(find.textContaining('个标记'), findsNothing);
  });
}
