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
    expect(find.text('录像与设置'), findsOneWidget);
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

  testWidgets('启动录像时保持摄像头预览可见', (WidgetTester tester) async {
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

    expect(find.byKey(const Key('camera-transition-cover')), findsNothing);
    expect(find.byKey(const Key('scan-guide')), findsOneWidget);
    expect(find.text('正在启动录像'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });

  testWidgets('保存录像时保持摄像头预览可见', (WidgetTester tester) async {
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

    expect(find.byKey(const Key('camera-transition-cover')), findsNothing);
    expect(find.byKey(const Key('scan-guide')), findsOneWidget);
    expect(find.text('正在保存录像'), findsOneWidget);
  });

  testWidgets('录像中显示时长胶囊、加粗单号和红色结束按钮', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: PackingHomeView(
          phase: PackingSessionPhase.recording,
          elapsed: const Duration(seconds: 8),
          currentCode: '770017871213193',
          previewOverride: const ColoredBox(color: Colors.black),
          onPrimaryPressed: () {},
          onRetryPressed: () {},
          onRecordingsPressed: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('recording-duration-pill')), findsOneWidget);
    expect(find.text('00:08'), findsOneWidget);
    expect(find.text('770017871213193'), findsOneWidget);
    expect(find.text('结束工作'), findsOneWidget);

    final Text shippingCode = tester.widget<Text>(
      find.byKey(const Key('current-shipping-code')),
    );
    expect(shippingCode.style?.fontWeight, FontWeight.w800);

    final FilledButton stopButton = tester.widget<FilledButton>(
      find.byKey(const Key('primary-work-button')),
    );
    expect(
      stopButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      const Color(0xFFD92D20),
    );
  });
}
