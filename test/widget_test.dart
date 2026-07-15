import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_lens/app/parcel_lens_app.dart';
import 'package:parcel_lens/controllers/packing_session_controller.dart';
import 'package:parcel_lens/screens/packing_home_screen.dart';

void main() {
  testWidgets('首页只保留一个主要开始动作', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: ParcelLensApp.forest,
            ),
          ),
        ),
        home: PackingHomeView(
          phase: PackingSessionPhase.ready,
          elapsed: Duration.zero,
          previewOverride: const ColoredBox(color: Color(0xFF313A36)),
          onPrimaryPressed: () {},
          onRetryPressed: () {},
          onRecordingsPressed: () {},
        ),
      ),
    );

    expect(find.text('开始工作'), findsOneWidget);
    expect(find.text('查看录像'), findsOneWidget);
    expect(find.text('对准面单条码'), findsOneWidget);
    expect(find.text('摄像头已就绪'), findsNothing);
    expect(find.text('连续录像 · 面单自动标记 · 仅存本机'), findsNothing);
    expect(find.byKey(const Key('scan-guide')), findsOneWidget);
    final ColoredBox backing = tester.widget<ColoredBox>(
      find.byKey(const Key('camera-preview-backing')),
    );
    expect(backing.color, Colors.white);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('启动录像时隐藏摄像头重绑定画面', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PackingHomeView(
          phase: PackingSessionPhase.starting,
          elapsed: Duration.zero,
          previewOverride: const ColoredBox(color: Colors.red),
          onPrimaryPressed: () {},
          onRetryPressed: () {},
          onRecordingsPressed: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('camera-transition-cover')), findsOneWidget);
    expect(find.text('正在启动录像'), findsNWidgets(2));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });

  testWidgets('保存录像时也隐藏摄像头重绑定画面', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PackingHomeView(
          phase: PackingSessionPhase.saving,
          elapsed: const Duration(seconds: 8),
          previewOverride: const ColoredBox(color: Colors.red),
          onPrimaryPressed: () {},
          onRetryPressed: () {},
          onRecordingsPressed: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('camera-transition-cover')), findsOneWidget);
    expect(find.text('正在保存录像'), findsNWidgets(2));
  });
}
