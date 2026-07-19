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
    expect(find.textContaining('开源且免费'), findsOneWidget);
    expect(find.textContaining('备份仅在局域网内进行'), findsOneWidget);
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

    expect(find.textContaining('备份仅在局域网内进行'), findsOneWidget);
    expect(find.byKey(const Key('startup-notice-confirm')), findsOneWidget);
  });
}
