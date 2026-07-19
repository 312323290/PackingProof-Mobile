import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/barcode_marker.dart';
import 'package:packing_proof_mobile/models/lan_backup.dart';
import 'package:packing_proof_mobile/models/recording_session.dart';
import 'package:packing_proof_mobile/models/work_mode.dart';
import 'package:packing_proof_mobile/screens/recordings_screen.dart';

void main() {
  testWidgets('录像页面可切换工作模式', (WidgetTester tester) async {
    WorkMode selected = WorkMode.continuousScan;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          mode: RecordingsScreenMode.settings,
          sessions: const [],
          workMode: selected,
          speechEnabled: true,
          maxVolumeEnabled: true,
          onWorkModeChanged: (WorkMode mode) async {
            selected = mode;
          },
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
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

  testWidgets('语音设置可关闭并在开启时试听', (WidgetTester tester) async {
    bool enabled = true;
    int previewCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          mode: RecordingsScreenMode.settings,
          sessions: const [],
          workMode: WorkMode.continuousScan,
          speechEnabled: enabled,
          maxVolumeEnabled: true,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (bool value) async {
            enabled = value;
          },
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {
            previewCount++;
          },
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    expect(find.byKey(const Key('speech-prompt-settings')), findsOneWidget);
    expect(find.text('Edge 音色，离线自动使用系统语音'), findsOneWidget);
    await tester.tap(find.text('试听'));
    await tester.pump();
    expect(previewCount, 1);

    await tester.tap(find.byKey(const Key('speech-enabled-switch')));
    await tester.pump();
    expect(enabled, isFalse);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('speech-preview-button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('最大音量默认开启且可关闭', (WidgetTester tester) async {
    bool enabled = true;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          mode: RecordingsScreenMode.settings,
          sessions: const [],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: enabled,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (bool value) async {
            enabled = value;
          },
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    expect(find.text('最大音量'), findsOneWidget);
    expect(find.text('工作时自动提高媒体音量'), findsOneWidget);
    await tester.tap(find.byKey(const Key('max-volume-enabled-switch')));
    await tester.pump();
    expect(enabled, isFalse);
  });

  testWidgets('电脑备份未连接时提供扫码入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int scanCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': 'SF1234567890'};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: const [],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          backupSnapshot: const LanBackupSnapshot(),
          onScanSearch: () => scanCount++,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    expect(find.byKey(const Key('computer-backup-settings')), findsOneWidget);
    expect(find.text('电脑备份'), findsOneWidget);
    expect(find.text('连接电脑'), findsOneWidget);
    expect(find.byKey(const Key('scan-search-button')), findsOneWidget);
    expect(find.byKey(const Key('paste-search-button')), findsOneWidget);
    expect(find.byKey(const Key('recording-source-filter')), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan-search-button')));
    expect(scanCount, 1);

    await tester.tap(find.byKey(const Key('paste-search-button')));
    await tester.pump();
    expect(find.text('SF1234567890'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recording-source-filter')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('仅本机'), findsOneWidget);
  });

  testWidgets('连接后持续显示电脑名称和局域网地址', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: const [],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          backupSnapshot: LanBackupSnapshot(
            endpoint: LanBackupEndpoint(
              baseUri: Uri.parse('http://192.168.1.20:5280'),
              accessKey: '',
              computerId: 'computer-1',
              computerName: '仓库电脑',
            ),
            connectionStatus: LanConnectionStatus.connected,
          ),
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    expect(find.byKey(const Key('connected-computer-address')), findsOneWidget);
    expect(find.text('仓库电脑 · 192.168.1.20:5280'), findsOneWidget);
  });

  testWidgets('本机录像全部备份后按钮显示灰色备份完成', (WidgetTester tester) async {
    const String videoPath = 'video.mp4';
    final DateTime startedAt = DateTime(2026, 7, 19, 12);
    int backupCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: <RecordingSession>[
            RecordingSession(
              id: 'local-1',
              filePath: videoPath,
              startedAt: startedAt,
              endedAt: startedAt.add(const Duration(seconds: 5)),
              markers: const <BarcodeMarker>[],
            ),
          ],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          backupSnapshot: LanBackupSnapshot(
            endpoint: LanBackupEndpoint(
              baseUri: Uri.parse('http://192.168.1.20:5280'),
              accessKey: '',
              computerId: 'computer-1',
              computerName: '仓库电脑',
            ),
            jobs: <LanBackupJob>[
              LanBackupJob(
                id: 'job-1',
                filePath: videoPath,
                state: LanBackupJobState.completed,
                uploadedBytes: 1,
                totalBytes: 1,
                destinationComputerId: 'computer-1',
              ),
            ],
            connectionStatus: LanConnectionStatus.connected,
          ),
          onBackupNow: () async => backupCount++,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    expect(find.text('备份完成'), findsOneWidget);
    final TextButton button = tester.widget<TextButton>(
      find.byKey(const Key('backup-now-button')),
    );
    expect(button.onPressed, isNull);
    expect(backupCount, 0);
  });

  testWidgets('电脑离线时使用中性状态且不请求远程历史', (WidgetTester tester) async {
    int loadCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: const [],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          backupSnapshot: LanBackupSnapshot(
            endpoint: LanBackupEndpoint(
              baseUri: Uri.parse('http://192.168.1.20:5280'),
              accessKey: '',
              computerId: 'computer-1',
              computerName: '仓库电脑',
            ),
            connectionStatus: LanConnectionStatus.offline,
          ),
          onLoadRemoteRecordings:
              ({required page, required pageSize, keyword = ''}) async {
                loadCount++;
                return const RemoteRecordingPage.empty();
              },
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onAutoBackupChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('电脑离线'), findsWidgets);
    expect(find.text('电脑离线，备份已暂停'), findsOneWidget);
    expect(loadCount, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final Switch autoBackupSwitch = tester.widget<Switch>(
      find.byKey(const Key('auto-backup-switch')),
    );
    expect(autoBackupSwitch.value, isTrue);
    expect(autoBackupSwitch.onChanged, isNotNull);
    expect(autoBackupSwitch.thumbColor, isNull);
    expect(autoBackupSwitch.trackColor, isNull);
  });

  testWidgets('删除电脑需要两次确认并显示名称与地址', (WidgetTester tester) async {
    int deleteCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: const [],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          backupSnapshot: LanBackupSnapshot(
            endpoint: LanBackupEndpoint(
              baseUri: Uri.parse('http://192.168.1.20:5280'),
              accessKey: '',
              computerId: 'computer-1',
              computerName: '仓库电脑',
            ),
            connectionStatus: LanConnectionStatus.connected,
          ),
          onDisconnectBackup: () async => deleteCount++,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('delete-computer-button')));
    await tester.pumpAndSettle();
    expect(find.text('删除这台电脑？'), findsOneWidget);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('再次确认删除'), findsOneWidget);
    expect(find.textContaining('仓库电脑'), findsWidgets);
    expect(find.textContaining('192.168.1.20:5280'), findsWidgets);
    expect(deleteCount, 0);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(deleteCount, 1);
  });

  testWidgets('等待续传不会误显示为正在备份', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: const [],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          backupSnapshot: LanBackupSnapshot(
            endpoint: LanBackupEndpoint(
              baseUri: Uri.parse('http://192.168.1.20:5280'),
              accessKey: '',
              computerId: 'computer-1',
              computerName: '仓库电脑',
            ),
            jobs: const <LanBackupJob>[
              LanBackupJob(
                id: 'job-1',
                filePath: 'video.mp4',
                state: LanBackupJobState.paused,
                uploadedBytes: 0,
                totalBytes: 1024,
                errorMessage: '网络中断，等待自动续传',
              ),
            ],
            connectionStatus: LanConnectionStatus.connected,
          ),
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    expect(find.text('网络中断，等待自动续传'), findsOneWidget);
    expect(find.textContaining('正在备份'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
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
          speechEnabled: true,
          maxVolumeEnabled: true,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
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
          speechEnabled: true,
          maxVolumeEnabled: true,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('recording-search')),
        matching: find.byType(EditableText),
      ),
      'SF9876',
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();

    expect(find.text('SF9876543210'), findsOneWidget);
    expect(find.text('JT1234567890'), findsNothing);
  });

  testWidgets('录像记录每页显示十条并可翻页', (WidgetTester tester) async {
    final DateTime startedAt = DateTime(2026, 7, 18, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: List<RecordingSession>.generate(
            11,
            (int index) => _session(
              'clip-$index',
              'CODE-${index.toString().padLeft(2, '0')}',
              startedAt.subtract(Duration(minutes: index)),
            ),
          ),
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    expect(find.text('CODE-00'), findsOneWidget);
    expect(find.text('CODE-10'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('CODE-09'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('CODE-09'), findsOneWidget);
    expect(find.text('CODE-10'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('recording-page-next')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1 / 2 页'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recording-page-next')));
    await tester.pump();

    expect(find.text('CODE-00'), findsNothing);
    expect(find.text('CODE-10'), findsOneWidget);
    expect(find.text('2 / 2 页'), findsOneWidget);
  });

  testWidgets('电脑录像首次缓存两页且搜索重置分页', (WidgetTester tester) async {
    final List<int> requestedPages = <int>[];
    final List<String> requestedKeywords = <String>[];
    Future<RemoteRecordingPage> loadRemote({
      required int page,
      required int pageSize,
      String keyword = '',
    }) async {
      requestedPages.add(page);
      requestedKeywords.add(keyword);
      final int start = (page - 1) * pageSize;
      return RemoteRecordingPage(
        data: List<RemoteRecording>.generate(
          keyword.isEmpty ? 10 : 1,
          (int index) => RemoteRecording(
            id: start + index + 1,
            trackingNumber: keyword.isEmpty
                ? 'REMOTE-${start + index}'
                : 'SEARCHED',
            startedAt: DateTime(
              2026,
              7,
              19,
              12,
            ).subtract(Duration(minutes: start + index)),
            duration: const Duration(seconds: 5),
            sourceType: 'pc',
            sourceDeviceId: '',
            sourceDeviceName: '',
            sourceSessionId: '',
            contentSha256: '',
            playUri: Uri.parse('http://192.168.1.20/video'),
          ),
        ),
        page: page,
        pageSize: pageSize,
        total: keyword.isEmpty ? 20 : 1,
        deviceTotal: 0,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: const <RecordingSession>[],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          backupSnapshot: LanBackupSnapshot(
            endpoint: LanBackupEndpoint(
              baseUri: Uri.parse('http://192.168.1.20:5280'),
              accessKey: '',
              computerId: 'computer-1',
              computerName: '电脑',
            ),
            connectionStatus: LanConnectionStatus.connected,
          ),
          onLoadRemoteRecordings: loadRemote,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requestedPages, <int>[1, 2]);

    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(requestedPages, <int>[1, 2]);

    await tester.scrollUntilVisible(
      find.byKey(const Key('recording-page-next')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('recording-page-next')));
    await tester.pumpAndSettle();
    expect(requestedPages, <int>[1, 2]);

    await tester.tap(find.byKey(const Key('recording-page-previous')));
    await tester.pump();
    expect(requestedPages, <int>[1, 2]);

    await tester.drag(find.byType(ListView), const Offset(0, 1800));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('recording-search')),
        matching: find.byType(EditableText),
      ),
      'SEARCH',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(requestedPages.last, 1);
    expect(requestedKeywords.last, 'SEARCH');
    expect(find.text('SEARCHED'), findsOneWidget);
  });

  testWidgets('电脑已清理的录像显示灰色状态且禁止播放', (WidgetTester tester) async {
    final RemoteRecording remote = RemoteRecording(
      id: 7,
      trackingNumber: 'CLEANED-001',
      startedAt: DateTime(2026, 7, 19, 12),
      duration: const Duration(seconds: 5),
      sourceType: 'external',
      sourceDeviceId: 'phone-1',
      sourceDeviceName: '手机',
      sourceSessionId: 'session-1',
      contentSha256: 'sha',
      playUri: Uri.parse('http://192.168.1.20/api/videos/7/play'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: const <RecordingSession>[],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          backupSnapshot: LanBackupSnapshot(
            endpoint: LanBackupEndpoint(
              baseUri: Uri.parse('http://192.168.1.20:5280'),
              accessKey: '',
              computerId: 'computer-1',
              computerName: '电脑',
            ),
            connectionStatus: LanConnectionStatus.connected,
          ),
          onLoadRemoteRecordings:
              ({required page, required pageSize, keyword = ''}) async =>
                  RemoteRecordingPage(
                    data: page == 1 ? <RemoteRecording>[remote] : const [],
                    page: page,
                    pageSize: pageSize,
                    total: 1,
                    deviceTotal: 1,
                  ),
          onLoadRemoteRecordingStatuses: (ids) async => {
            7: (
              status: RemoteRecordingStatus.deleted,
              exists: false,
              reason: '容量清理',
            ),
          },
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('电脑录像 · 已清理'), findsOneWidget);
    await tester.tap(find.text('CLEANED-001'));
    await tester.pump();
    expect(find.text('录像已清理或文件不存在，无法播放'), findsOneWidget);
  });

  testWidgets('录像来源标签显示在快递单号右侧', (WidgetTester tester) async {
    final DateTime startedAt = DateTime(2026, 7, 18, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsScreen(
          sessions: <RecordingSession>[
            _session('clip-1', 'TRACKING-001', startedAt),
          ],
          workMode: WorkMode.continuousScan,
          speechEnabled: true,
          maxVolumeEnabled: true,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (_) async {},
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pump();
    final Offset codeCenter = tester.getCenter(find.text('TRACKING-001'));
    final Offset sourceCenter = tester.getCenter(find.text('已备份 · 电脑离线'));
    expect((codeCenter.dy - sourceCenter.dy).abs(), lessThan(2));
    expect(sourceCenter.dx, greaterThan(codeCenter.dx));
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
          speechEnabled: true,
          maxVolumeEnabled: true,
          onWorkModeChanged: (_) async {},
          onSpeechEnabledChanged: (_) async {},
          onMaxVolumeEnabledChanged: (_) async {},
          onSpeechPreview: () async {},
          onSessionUpdated: (_) async {},
          onDeleteSessions: (Set<String> ids) async {
            deletedIds = ids;
          },
        ),
      ),
    );

    await tester.tap(find.text('管理'));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -420));
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
