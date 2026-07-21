import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:packing_proof_mobile/widgets/about_settings.dart';
import 'package:packing_proof_mobile/app/app_build_config.dart';

void main() {
  testWidgets('关于页显示版本、源码、Release 和开源项目', (WidgetTester tester) async {
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AboutSettings(
            buildConfig: const AppBuildConfig(
              buildRevision: 'abc1234',
              buildTimestamp: '2026-07-19T14:00:00Z',
            ),
            packageInfoLoader: () async => PackageInfo(
              appName: '包裹留证',
              packageName: 'app.packingproof.mobile',
              version: '0.3.1',
              buildNumber: '9002',
            ),
            uriLauncher: (Uri uri) async {
              opened = uri;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('about-settings-open')));
    await tester.pumpAndSettle();
    expect(find.text('版本 0.3.1+9002'), findsOneWidget);
    expect(find.text('构建修订'), findsOneWidget);
    expect(find.text('abc1234 · 2026-07-19T14:00:00Z'), findsOneWidget);
    expect(find.text('源码仓库'), findsOneWidget);
    expect(find.text('版本发布'), findsOneWidget);
    expect(find.text('Flutter'), findsOneWidget);
    expect(find.text('Microsoft Edge TTS'), findsOneWidget);

    await tester.tap(find.text('版本发布'));
    await tester.pump();
    expect(opened.toString(), packingProofReleasesUrl);
  });

  testWidgets('外部链接打开失败时显示提示', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AboutSettings(
            packageInfoLoader: () async => PackageInfo(
              appName: '包裹留证',
              packageName: 'app.packingproof.mobile',
              version: '0.3.1',
              buildNumber: '9002',
            ),
            uriLauncher: (_) async => false,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('about-settings-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('源码仓库'));
    await tester.pump();
    expect(find.text('无法打开链接，请稍后重试'), findsOneWidget);
  });

  testWidgets('点击版本可重新查看首次说明且只显示关闭按钮', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AboutScreen(
          packageInfoLoader: () async => PackageInfo(
            appName: '包裹留证',
            packageName: 'app.packingproof.mobile',
            version: '0.4.2',
            buildNumber: '10002',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('版本 0.4.2+10002'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('startup-notice-card')), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('开始使用'), findsNothing);
  });
}
