import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/barcode_marker.dart';
import 'package:packing_proof_mobile/models/lan_backup.dart';
import 'package:packing_proof_mobile/models/recording_session.dart';
import 'package:packing_proof_mobile/services/lan_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android 私有目录别名会识别为同一个备份文件', () {
    expect(
      isSameLanBackupFile(
        '/data/user/0/app.packingproof.mobile/app_flutter/recordings/a.mp4',
        '/data/data/app.packingproof.mobile/app_flutter/recordings/a.mp4',
      ),
      isTrue,
    );
    expect(
      isSameLanBackupFile(
        '/data/user/0/app.packingproof.mobile/app_flutter/recordings/a.mp4',
        '/data/data/app.packingproof.mobile/app_flutter/recordings/b.mp4',
      ),
      isFalse,
    );
  });

  test('接受带访问密钥的局域网电脑二维码', () {
    final LanBackupEndpoint endpoint = LanBackupService.parsePairingQr(
      'http://192.168.1.20:5280/?key=0123456789abcdef',
    );
    expect(endpoint.baseUri.toString(), 'http://192.168.1.20:5280');
    expect(endpoint.accessKey, '0123456789abcdef');
  });

  test('拒绝公网、域名和无密钥二维码', () {
    expect(
      () => LanBackupService.parsePairingQr(
        'http://8.8.8.8:5280/?key=0123456789abcdef',
      ),
      throwsFormatException,
    );
    expect(
      () => LanBackupService.parsePairingQr(
        'http://computer.local:5280/?key=0123456789abcdef',
      ),
      throwsFormatException,
    );
    expect(
      () => LanBackupService.parsePairingQr('http://192.168.1.20:5280/'),
      throwsFormatException,
    );
  });

  test('电脑心跳恢复后自动切回已连接状态', () {
    expect(
      heartbeatConnectionStatus(HttpStatus.ok),
      LanConnectionStatus.connected,
    );
    expect(
      heartbeatConnectionStatus(HttpStatus.serviceUnavailable),
      LanConnectionStatus.offline,
    );
    expect(
      heartbeatConnectionStatus(HttpStatus.unauthorized),
      LanConnectionStatus.rePair,
    );
  });

  test('手机历史默认请求主机全部录像而不限定当前设备', () {
    final Uri uri = buildRemoteRecordingsUri(
      Uri.parse('http://192.168.1.20:5280'),
      page: 2,
      pageSize: 10,
      keyword: 'TRACK-1',
    );

    expect(uri.path, '/api/videos');
    expect(uri.queryParameters['page'], '2');
    expect(uri.queryParameters['size'], '10');
    expect(uri.queryParameters['keyword'], 'TRACK-1');
    expect(uri.queryParameters.containsKey('deviceId'), isFalse);
  });

  test('电脑传来的最低版本仅在当前 App 过旧时生成更新提示', () {
    final Map<String, Object?> policy = <String, Object?>{
      'schemaVersion': 1,
      'minimumVersion': '0.5.6',
      'minimumBuildNumber': 11006,
      'message': '当前 APP 版本过低，需要更新',
    };

    expect(
      evaluateMobileAppUpdatePolicy(
        policy,
        currentVersion: '0.5.6',
        currentBuildNumber: 11006,
      ),
      isNull,
    );

    final MobileAppUpdateNotice? notice = evaluateMobileAppUpdatePolicy(
      policy,
      currentVersion: '0.5.5',
      currentBuildNumber: 11005,
    );
    expect(notice?.minimumVersion, '0.5.6');
    expect(notice?.message, '当前 APP 版本过低，需要更新');
  });

  test('版本比较兼容不同长度的语义版本号', () {
    expect(compareAppVersions('0.5.5', '0.5.6'), lessThan(0));
    expect(compareAppVersions('0.5.6', '0.5.6'), 0);
    expect(compareAppVersions('0.5.10', '0.5.6'), greaterThan(0));
  });

  test('电脑传来的推荐版本高于当前版本时生成普通更新提示', () {
    final MobileAppUpdateNotice? notice = evaluateMobileAppUpdatePolicy(
      <String, Object?>{
        'schemaVersion': 2,
        'minimumVersion': '0.5.6',
        'minimumBuildNumber': 11006,
        'message': '当前 APP 版本过低，需要更新',
        'latestVersion': '0.5.7',
        'latestBuildNumber': 11007,
      },
      currentVersion: '0.5.6',
      currentBuildNumber: 11006,
    );

    expect(notice?.updateRequired, isFalse);
    expect(notice?.latestVersion, '0.5.7');
    expect(notice?.message, '发现新版手机 App，建议更新');
  });

  test('未连接 Wi-Fi 时扫码给出友好提示且不发起网络请求', () async {
    final _UnexpectedHttpClient httpClient = _UnexpectedHttpClient();
    final LanBackupService service = LanBackupService(
      httpClient: httpClient,
      wifiConnected: () async => false,
    );
    addTearDown(service.dispose);

    await expectLater(
      service.pair('http://192.168.1.20:5280/?key=0123456789abcdef'),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          '请先连接与电脑相同的 Wi-Fi 后重试',
        ),
      ),
    );
    expect(httpClient.requested, isFalse);
  });

  test('录像备份元数据包含逻辑片段和面单标记', () {
    final DateTime startedAt = DateTime.utc(2026, 7, 19, 10);
    final RecordingSession session = RecordingSession(
      id: 'session-1',
      filePath: '${Directory.systemTemp.path}/master.mp4',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 8)),
      markers: <BarcodeMarker>[
        BarcodeMarker(
          code: 'SF1234567890',
          occurredAt: startedAt,
          offset: Duration.zero,
        ),
      ],
      mediaStart: const Duration(seconds: 2),
      mediaEnd: const Duration(seconds: 10),
    );

    final Map<String, Object?> value = recordingSessionBackupMap(session);
    expect(value['trackingNumber'], 'SF1234567890');
    expect(value['mediaStartMs'], 2000);
    expect(value['mediaEndMs'], 10000);
    expect(value['markers'], hasLength(1));
  });

  test('立即备份会要求原生任务强制重启', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing-proof-backup-',
    );
    addTearDown(() => root.delete(recursive: true));
    final File video = File('${root.path}/video.mp4');
    await video.writeAsBytes(<int>[1, 2, 3]);
    final MethodChannel channel = MethodChannel(
      'app.packingproof.mobile/lan_backup_test_${root.path.hashCode}',
    );
    MethodCall? enqueueCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'enqueue') enqueueCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final LanBackupService service = LanBackupService(channel: channel);
    addTearDown(service.dispose);
    final DateTime startedAt = DateTime.utc(2026, 7, 19, 10);

    await service.backupAll(<RecordingSession>[
      RecordingSession(
        id: 'session-1',
        filePath: video.path,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 1)),
        markers: const <BarcodeMarker>[],
      ),
    ]);

    expect(enqueueCall?.method, 'enqueue');
    final Map<Object?, Object?> arguments =
        enqueueCall!.arguments! as Map<Object?, Object?>;
    expect(arguments['startUpload'], isTrue);
    expect(arguments['forceRestart'], isTrue);
  });

  test('空录像不会创建无法完成的备份任务', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing-proof-empty-backup-',
    );
    addTearDown(() => root.delete(recursive: true));
    final File video = File('${root.path}/empty.mp4');
    await video.create();
    final MethodChannel channel = MethodChannel(
      'app.packingproof.mobile/lan_backup_empty_test_${root.path.hashCode}',
    );
    int enqueueCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'enqueue') enqueueCount++;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final LanBackupService service = LanBackupService(channel: channel);
    addTearDown(service.dispose);
    final DateTime startedAt = DateTime.utc(2026, 7, 24, 10);

    await service.backupAll(<RecordingSession>[
      RecordingSession(
        id: 'empty-session',
        filePath: video.path,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 1)),
        markers: const <BarcodeMarker>[],
      ),
    ]);

    expect(enqueueCount, 0);
  });

  test('取消连接后延迟完成的请求不会写入连接配置', () async {
    final MethodChannel channel = MethodChannel(
      'app.packingproof.mobile/lan_backup_cancel_test',
    );
    int savedConnections = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'saveConnection') savedConnections++;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final _PendingHttpClient httpClient = _PendingHttpClient();
    final LanBackupService service = LanBackupService(
      channel: channel,
      httpClient: httpClient,
    );
    addTearDown(service.dispose);

    final Future<void> pairing = service.pair(
      'http://192.168.1.20:5280/?key=0123456789abcdef',
    );
    await httpClient.request.closed;
    service.cancelPairing();
    await pairing;

    expect(httpClient.request.aborted, isTrue);
    expect(savedConnections, 0);
    expect(service.snapshot.endpoint, isNull);
    expect(service.snapshot.connectionStatus, LanConnectionStatus.disconnected);
  });
}

class _PendingHttpClient extends Fake implements HttpClient {
  final _PendingHttpClientRequest request = _PendingHttpClientRequest();

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => request;

  @override
  void close({bool force = false}) {}
}

class _UnexpectedHttpClient extends Fake implements HttpClient {
  bool requested = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requested = true;
    throw StateError('未连接 Wi-Fi 时不应发起请求');
  }

  @override
  void close({bool force = false}) {}
}

class _PendingHttpClientRequest extends Fake implements HttpClientRequest {
  final Completer<void> _closed = Completer<void>();
  final Completer<HttpClientResponse> _response =
      Completer<HttpClientResponse>();
  final HttpHeaders _headers = _IgnoringHttpHeaders();
  bool aborted = false;

  Future<void> get closed => _closed.future;

  @override
  HttpHeaders get headers => _headers;

  @override
  set followRedirects(bool value) {}

  @override
  Future<HttpClientResponse> close() {
    if (!_closed.isCompleted) _closed.complete();
    return _response.future;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
    if (!_response.isCompleted) {
      _response.completeError(
        exception ?? const HttpException('pairing cancelled'),
        stackTrace,
      );
    }
  }
}

class _IgnoringHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}
