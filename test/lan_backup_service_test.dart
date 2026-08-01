import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/barcode_marker.dart';
import 'package:packing_proof_mobile/models/lan_backup.dart';
import 'package:packing_proof_mobile/models/recording_session.dart';
import 'package:packing_proof_mobile/models/recording_operation_mode.dart';
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

  test('二维码只解析局域网主机地址并忽略旧查看密钥', () {
    final LanBackupEndpoint endpoint = LanBackupService.parsePairingQr(
      'http://192.168.1.20:5280/?key=0123456789abcdef',
    );
    expect(endpoint.baseUri.toString(), 'http://192.168.1.20:5280');
    expect(endpoint.accessKey, isEmpty);
  });

  test('拒绝公网和域名并接受不含密钥的局域网二维码', () {
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
      LanBackupService.parsePairingQr('http://192.168.1.20:5280/').baseUri,
      Uri.parse('http://192.168.1.20:5280'),
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

  test('备份失败类型兼容旧任务并可触发重新扫码状态', () {
    final LanBackupJob legacy = LanBackupJob.fromMap(<Object?, Object?>{
      'id': 'legacy',
      'filePath': 'legacy.mp4',
      'state': 'failed',
    });
    final LanBackupJob invalidKey = LanBackupJob.fromMap(<Object?, Object?>{
      'id': 'invalid-key',
      'filePath': 'pending.mp4',
      'state': 'failed',
      'failureKind': 'credential_invalid',
    });
    final LanBackupEndpoint endpoint = LanBackupEndpoint(
      baseUri: Uri.parse('http://192.168.1.20:5280'),
      accessKey: '',
      computerId: 'computer-1',
      computerName: '仓库电脑',
    );

    expect(legacy.failureKind, isNull);
    expect(invalidKey.failureKind, LanBackupFailureKind.credentialInvalid);
    expect(
      nativeBackupConnectionStatus(
        previous: LanConnectionStatus.connected,
        endpoint: endpoint,
        jobs: <LanBackupJob>[invalidKey],
      ),
      LanConnectionStatus.rePair,
    );

    final LanBackupJob wrongRole = LanBackupJob.fromMap(<Object?, Object?>{
      'id': 'wrong-role',
      'filePath': 'pending.mp4',
      'state': 'failed',
      'failureKind': 'not_backup_host',
    });
    expect(wrongRole.failureKind, LanBackupFailureKind.notBackupHost);
    expect(
      nativeBackupConnectionStatus(
        previous: LanConnectionStatus.connected,
        endpoint: endpoint,
        jobs: <LanBackupJob>[wrongRole],
      ),
      LanConnectionStatus.notBackupHost,
    );
  });

  test('每种结构化备份失败只映射一个恢复操作', () {
    final Map<String, LanBackupRecoveryAction> cases =
        <String, LanBackupRecoveryAction>{
          'credential_invalid': LanBackupRecoveryAction.rescan,
          'offline_or_timeout': LanBackupRecoveryAction.retryConnection,
          'temporary_service': LanBackupRecoveryAction.retryBackup,
          'upload_expired': LanBackupRecoveryAction.retryBackup,
          'verification_failed': LanBackupRecoveryAction.retryBackup,
          'storage_unavailable': LanBackupRecoveryAction.retryBackup,
          'not_backup_host': LanBackupRecoveryAction.rescan,
          'incompatible_version': LanBackupRecoveryAction.updateComputer,
          'unknown': LanBackupRecoveryAction.retryBackup,
        };

    for (final MapEntry<String, LanBackupRecoveryAction> entry
        in cases.entries) {
      final LanBackupFailureKind? kind = LanBackupFailureKind.fromWireValue(
        entry.key,
      );
      expect(kind, isNotNull);
      expect(kind!.recoveryAction, entry.value);
      expect(kind.recoveryLabel, isNotEmpty);
    }
  });

  test('手机历史仅请求当前设备可访问的录像', () {
    final Uri uri = buildRemoteRecordingsUri(
      Uri.parse('http://192.168.1.20:5280'),
      page: 2,
      pageSize: 10,
      keyword: 'TRACK-1',
    );

    expect(uri.path, '/api/mobile-backup/videos');
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

  test('连接到非备份用途电脑时要求重新扫码而不是更新电脑端', () async {
    final LanBackupService service = LanBackupService(
      httpClient: _SequenceHttpClient(<_StreamHttpResponse>[
        _StreamHttpResponse(
          HttpStatus.ok,
          '{"protocol":"packingproof","protocolVersion":1,'
          '"nodeId":"computer-1","capabilities":["recording","order-receiver"]}',
        ),
      ]),
      wifiConnected: () async => true,
    );
    addTearDown(service.dispose);

    await expectLater(
      service.pair('http://192.168.1.20:5280/?key=0123456789abcdef'),
      throwsA(isA<LanBackupNotHostException>()),
    );

    expect(
      service.snapshot.connectionStatus,
      LanConnectionStatus.notBackupHost,
    );
    expect(service.snapshot.message, contains('不是录像备份主机'));
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
      operationMode: RecordingOperationMode.returnGoods,
    );

    final Map<String, Object?> value = recordingSessionBackupMap(session);
    expect(value['trackingNumber'], 'SF1234567890');
    expect(value['mediaStartMs'], 2000);
    expect(value['mediaEndMs'], 10000);
    expect(value['markers'], hasLength(1));
    expect(value['mode'], 'return');
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

  test('保存主机允许后才保存设备专属令牌', () async {
    final MethodChannel channel = const MethodChannel(
      'app.packingproof.mobile/lan_backup_v3_enrollment_test',
    );
    Map<Object?, Object?>? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'saveConnection') {
            saved = Map<Object?, Object?>.from(call.arguments! as Map);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final LanBackupService service = LanBackupService(
      channel: channel,
      httpClient: _SequenceHttpClient(<_StreamHttpResponse>[
        _nodeInfo('computer-1', '仓库电脑'),
        _enrollment('computer-1', '仓库电脑', 'a' * 64),
      ]),
      wifiConnected: () async => true,
    );
    addTearDown(service.dispose);

    await service.connectToHost(Uri.parse('http://192.168.1.20:5280'));

    expect(saved?['accessKey'], 'a' * 64);
    expect(saved?['computerId'], 'computer-1');
    expect(service.snapshot.message, '保存主机已允许连接');
  });

  test('保存主机拒绝时不写入连接配置', () async {
    final MethodChannel channel = const MethodChannel(
      'app.packingproof.mobile/lan_backup_v3_denied_test',
    );
    int savedConnections = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'saveConnection') savedConnections++;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final LanBackupService service = LanBackupService(
      channel: channel,
      httpClient: _SequenceHttpClient(<_StreamHttpResponse>[
        _nodeInfo('computer-1', '仓库电脑'),
        _StreamHttpResponse(
          HttpStatus.forbidden,
          '{"errorCode":"enrollment_denied"}',
        ),
      ]),
      wifiConnected: () async => true,
    );
    addTearDown(service.dispose);

    await expectLater(
      service.connectToHost(Uri.parse('http://192.168.1.20:5280')),
      throwsA(isA<LanBackupConnectionException>()),
    );
    expect(savedConnections, 0);
    expect(service.snapshot.endpoint, isNull);
  });

  test('存在待备份录像时更换主机要先确认且确认前不申请令牌', () async {
    final LanBackupService service = LanBackupService(
      httpClient: _SequenceHttpClient(<_StreamHttpResponse>[
        _nodeInfo('computer-2', '新电脑'),
      ]),
      wifiConnected: () async => true,
    );
    addTearDown(service.dispose);
    service.debugSetSnapshotForTesting(
      LanBackupSnapshot(
        jobs: <LanBackupJob>[
          LanBackupJob(
            id: 'pending',
            filePath: 'pending.mp4',
            state: LanBackupJobState.pending,
            uploadedBytes: 0,
            totalBytes: 10,
            destinationComputerId: 'computer-1',
          ),
        ],
      ),
    );

    final LanBackupHostMismatchException mismatch = await _expectHostMismatch(
      service.connectToHost(Uri.parse('http://192.168.1.30:5280')),
    );
    expect(mismatch.candidateEndpoint.computerId, 'computer-2');
  });
}

_StreamHttpResponse _nodeInfo(String id, String name) => _StreamHttpResponse(
  HttpStatus.ok,
  '{"protocol":"packingproof","protocolVersion":1,"nodeId":"$id",'
  '"nodeName":"$name","capabilities":["host","mobile-backup"]}',
);

_StreamHttpResponse _enrollment(String id, String name, String token) =>
    _StreamHttpResponse(
      HttpStatus.ok,
      '{"protocol":"mobile-backup-v2","version":2,"authVersion":3,'
      '"computerId":"$id","computerName":"$name",'
      '"deviceId":"00000000-0000-0000-0000-000000000001",'
      '"deviceToken":"$token"}',
    );

Future<LanBackupHostMismatchException> _expectHostMismatch(
  Future<void> pairing,
) async {
  try {
    await pairing;
  } on LanBackupHostMismatchException catch (error) {
    return error;
  }
  throw TestFailure('预期要求确认更换备份电脑');
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

class _SequenceHttpClient extends Fake implements HttpClient {
  _SequenceHttpClient(this.responses);

  final List<_StreamHttpResponse> responses;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _CompletedHttpClientRequest(responses.removeAt(0));
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return _CompletedHttpClientRequest(responses.removeAt(0));
  }

  @override
  void close({bool force = false}) {}
}

class _CompletedHttpClientRequest extends Fake implements HttpClientRequest {
  _CompletedHttpClientRequest(this.response);

  final _StreamHttpResponse response;
  final HttpHeaders _headers = _IgnoringHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  set followRedirects(bool value) {}

  @override
  set contentLength(int value) {}

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async => response;
}

class _StreamHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _StreamHttpResponse(this.statusCode, String body)
    : _bytes = utf8.encode(body);

  @override
  final int statusCode;
  final List<int> _bytes;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IgnoringHttpHeaders extends Fake implements HttpHeaders {
  @override
  set contentType(ContentType? value) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}
