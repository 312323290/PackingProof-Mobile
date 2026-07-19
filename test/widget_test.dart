import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/app/packing_proof_mobile_app.dart';
import 'package:packing_proof_mobile/controllers/packing_session_controller.dart';
import 'package:packing_proof_mobile/screens/packing_home_screen.dart';

void main() {
  test('下拉通知栏不会暂停打包录像', () {
    expect(shouldSuspendPackingSession(AppLifecycleState.inactive), isFalse);
    expect(shouldSuspendPackingSession(AppLifecycleState.resumed), isFalse);
    expect(shouldSuspendPackingSession(AppLifecycleState.hidden), isTrue);
    expect(shouldSuspendPackingSession(AppLifecycleState.paused), isTrue);
    expect(shouldSuspendPackingSession(AppLifecycleState.detached), isTrue);
  });

  testWidgets('首页只保留一个主要开始动作', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: PackingProofMobileApp.forest,
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
    expect(find.byKey(const Key('recording-button-shimmer')), findsNothing);
  });

  testWidgets('电脑配对成功后显示带地址的绿色提示', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PackingHomeView(
          phase: PackingSessionPhase.ready,
          elapsed: Duration.zero,
          previewOverride: const ColoredBox(color: Colors.black),
          pairingMessage: '电脑连接成功 · 仓库电脑 · 192.168.1.20:5280',
          onPrimaryPressed: () {},
          onRetryPressed: () {},
          onRecordingsPressed: () {},
        ),
      ),
    );

    expect(find.text('电脑连接成功 · 仓库电脑 · 192.168.1.20:5280'), findsOneWidget);
    final Material banner = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('电脑连接成功 · 仓库电脑 · 192.168.1.20:5280'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(banner.color, const Color(0xF0087454));
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
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: PackingHomeView(
          phase: PackingSessionPhase.recording,
          elapsed: const Duration(seconds: 8),
          currentCode: '770017871213193',
          nativePreviewSize: const Size(1080, 1920),
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
    expect(find.byKey(const Key('recording-button-shimmer')), findsOneWidget);

    final Rect previewViewport = tester.getRect(
      find.byKey(const Key('camera-preview-viewport')),
    );
    final Rect durationPill = tester.getRect(
      find.byKey(const Key('recording-duration-pill')),
    );
    expect(previewViewport.size.aspectRatio, closeTo(9 / 16, 0.001));
    expect(durationPill.center.dx, closeTo(previewViewport.center.dx, 1));
    expect(
      durationPill.center.dy,
      greaterThan(previewViewport.top + previewViewport.height * 0.65),
    );

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
