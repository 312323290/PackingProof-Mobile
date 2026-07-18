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
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
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
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    expect(find.text('CODE-001'), findsOneWidget);
    expect(find.textContaining('00:08'), findsOneWidget);
    expect(find.textContaining('个标记'), findsNothing);
  });

  testWidgets('可按面单号搜索录像', (WidgetTester tester) async {
    final DateTime startedAt = DateTime(2026, 7, 18, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: <RecordingSession>[
            _session('clip-1', 'JT1234567890', startedAt),
            _session('clip-2', 'SF9876543210', startedAt),
          ],
          workMode: WorkMode.continuousScan,
          onWorkModeChanged: (_) async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('recording-search')),
        matching: find.byType(EditableText),
      ),
      'SF9876',
    );
    await tester.pump();

    expect(find.text('SF9876543210'), findsOneWidget);
    expect(find.text('JT1234567890'), findsNothing);
  });

  testWidgets('管理模式可多选并确认删除录像', (WidgetTester tester) async {
    final DateTime startedAt = DateTime(2026, 7, 18, 12);
    Set<String>? deletedIds;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: <RecordingSession>[
            _session('clip-1', 'JT1234567890', startedAt),
          ],
          workMode: WorkMode.continuousScan,
          onWorkModeChanged: (_) async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (Set<String> ids) async {
            deletedIds = ids;
          },
        ),
      ),
    );

    await tester.tap(find.text('管理'));
    await tester.pump();
    await tester.tap(find.text('JT1234567890'));
    await tester.pump();

    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.tap(find.text('删除所选录像'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(deletedIds, <String>{'clip-1'});
    expect(find.text('JT1234567890'), findsNothing);
  });
}

RecordingSession _session(String id, String code, DateTime startedAt) {
  return RecordingSession(
    id: id,
    filePath: 'master.mp4',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(seconds: 8)),
    markers: <BarcodeMarker>[
      BarcodeMarker(code: code, occurredAt: startedAt, offset: Duration.zero),
    ],
  );
}
