import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/app/app_build_config.dart';
import 'package:packing_proof_mobile/app/packing_proof_mobile_app.dart';

void main() {
  testWidgets('普通版首次打开显示统一的开源与本地数据说明', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StartupNoticeScreen(
          buildConfig: const AppBuildConfig(
            edition: AppEdition.standard,
            onlineEdgeTtsEnabled: true,
            networkPolicy: NetworkPolicy.publicAllowed,
          ),
          onConfirm: () async {},
        ),
      ),
    );

    expect(find.byKey(const Key('startup-notice-card')), findsOneWidget);
    final Text title = tester.widget<Text>(
      find.byKey(const Key('startup-notice-title')),
    );
    expect(title.textAlign, TextAlign.center);
    expect(
      find.descendant(
        of: find.byKey(const Key('startup-notice-card')),
        matching: find.text('欢迎使用包裹留证'),
      ),
      findsNothing,
    );
    final Text body = tester.widget<Text>(find.textContaining('开源且免费'));
    expect(body.textAlign, TextAlign.left);
    expect(find.textContaining('开源且免费'), findsOneWidget);
    expect(find.textContaining('才会通过局域网备份录像'), findsOneWidget);
  });

  testWidgets('单机版首次打开显示相同说明', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StartupNoticeScreen(
          buildConfig: const AppBuildConfig(
            edition: AppEdition.standalone,
            onlineEdgeTtsEnabled: false,
            networkPolicy: NetworkPolicy.localOnly,
          ),
          onConfirm: () async {},
        ),
      ),
    );

    expect(find.textContaining('才会通过局域网备份录像'), findsOneWidget);
    expect(find.byKey(const Key('startup-notice-confirm')), findsOneWidget);
  });
}
