import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/widgets/playback_error_panel.dart';

void main() {
  testWidgets('本地错误面板显示提示、错误码和三个操作', (WidgetTester tester) async {
    int primary = 0;
    int secondary = 0;
    int destructive = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackErrorPanel(
            message: '录像文件不完整或已损坏，无法播放（可能是异常退出导致）',
            errorDetail: 'VideoError：Failed to load video',
            primaryAction: () async {
              primary++;
            },
            primaryActionLabel: '用系统播放器打开',
            secondaryAction: () async {
              secondary++;
            },
            secondaryActionLabel: '分享原文件',
            destructiveAction: () async {
              destructive++;
            },
            destructiveActionLabel: '删除本机录像',
          ),
        ),
      ),
    );

    expect(find.text('录像文件不完整或已损坏，无法播放（可能是异常退出导致）'), findsOneWidget);
    expect(find.text('VideoError：Failed to load video'), findsOneWidget);
    expect(find.text('用系统播放器打开'), findsOneWidget);
    expect(find.text('分享原文件'), findsOneWidget);
    expect(find.text('删除本机录像'), findsOneWidget);

    await tester.tap(find.byKey(const Key('playback-fallback-primary')));
    await tester.tap(find.byKey(const Key('playback-fallback-secondary')));
    await tester.tap(find.byKey(const Key('playback-fallback-destructive')));
    await tester.pump();

    expect(primary, 1);
    expect(secondary, 1);
    expect(destructive, 1);
  });

  testWidgets('远程错误面板显示下载后播放与下载并分享', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackErrorPanel(
            message: '电脑录像暂时无法播放，请检查局域网连接',
            primaryAction: () async {},
            primaryActionLabel: '下载后播放',
            secondaryAction: () async {},
            secondaryActionLabel: '下载并分享原文件',
          ),
        ),
      ),
    );

    expect(find.text('电脑录像暂时无法播放，请检查局域网连接'), findsOneWidget);
    expect(find.text('下载后播放'), findsOneWidget);
    expect(find.text('下载并分享原文件'), findsOneWidget);
    expect(
      find.byKey(const Key('playback-fallback-destructive')),
      findsNothing,
    );
  });

  testWidgets('忙碌时按钮禁用', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackErrorPanel(
            message: '无法播放',
            primaryAction: () async {},
            primaryActionLabel: '用系统播放器打开',
            busy: true,
          ),
        ),
      ),
    );

    final FilledButton button = tester.widget<FilledButton>(
      find.byKey(const Key('playback-fallback-primary')),
    );
    expect(button.onPressed, isNull);
  });
}
