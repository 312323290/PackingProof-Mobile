import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/lan_backup.dart';
import '../models/recording_session.dart';
import '../models/backup_retention_policy.dart';

class LanBackupUnsupportedException implements Exception {
  const LanBackupUnsupportedException();

  @override
  String toString() => '电脑端版本暂不支持录像备份';
}

const int _backupAuthenticationVersion = 3;
const String _backupProtocol = 'mobile-backup-v2';

List<int> _decodeSecret(String value) {
  final String normalized = value.trim();
  if (normalized.length >= 32 && normalized.length.isEven) {
    try {
      return List<int>.generate(
        normalized.length ~/ 2,
        (int index) => int.parse(
          normalized.substring(index * 2, index * 2 + 2),
          radix: 16,
        ),
      );
    } on FormatException {
      // 非十六进制设备令牌按 UTF-8 参与签名。
    }
  }
  return utf8.encode(normalized);
}

class LanBackupNotHostException implements Exception {
  const LanBackupNotHostException();

  @override
  String toString() => '连接的电脑当前不是录像备份主机';
}

class LanBackupConnectionException implements Exception {
  const LanBackupConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LanBackupPairingConfirmation {
  const LanBackupPairingConfirmation({
    required this.computerId,
    required this.baseUri,
  });

  final String computerId;
  final Uri baseUri;

  bool matches(LanBackupEndpoint endpoint) {
    final String expectedId = computerId.trim();
    final String actualId = endpoint.computerId.trim();
    if (expectedId.isNotEmpty && actualId.isNotEmpty) {
      return expectedId == actualId;
    }
    return _normalizedHostUri(baseUri) == _normalizedHostUri(endpoint.baseUri);
  }
}

class LanBackupHostMismatchException implements Exception {
  const LanBackupHostMismatchException({
    required this.currentEndpoint,
    required this.candidateEndpoint,
  });

  final LanBackupEndpoint currentEndpoint;
  final LanBackupEndpoint candidateEndpoint;

  LanBackupPairingConfirmation get confirmation => LanBackupPairingConfirmation(
    computerId: candidateEndpoint.computerId,
    baseUri: candidateEndpoint.baseUri,
  );

  @override
  String toString() => '扫描到另一台备份电脑';
}

abstract interface class LanBackupSink implements Listenable {
  LanBackupSnapshot get snapshot;

  Future<void> initialize({
    required bool autoEnabled,
    required UnbackedRetentionPolicy unbackedRetention,
    required BackedRetentionPolicy backedRetention,
  });
  Future<void> pair(
    String qrValue, {
    LanBackupPairingConfirmation? replacementConfirmation,
  });
  Future<void> connectToHost(
    Uri baseUri, {
    LanBackupPairingConfirmation? replacementConfirmation,
  });
  void cancelPairing();
  Future<void> disconnect();
  Future<bool> retryConnection();
  Future<void> setAutoEnabled(bool enabled);
  Future<void> setRetentionPolicies({
    required UnbackedRetentionPolicy unbacked,
    required BackedRetentionPolicy backed,
  });
  Future<void> enqueueFinalizedFile(
    String filePath,
    List<RecordingSession> sessions,
  );
  Future<void> backupAll(List<RecordingSession> sessions);
  Future<void> retry(String jobId);
  Future<void> cancel(String jobId);
  Future<StorageSpaceResult> checkAndReclaimStorage();
  Future<void> refresh();
  Future<RemoteRecordingPage> fetchRemoteRecordings({
    required int page,
    required int pageSize,
    String keyword = '',
  });
  Future<Map<int, ({RemoteRecordingStatus status, bool exists, String reason})>>
  fetchRemoteRecordingStatuses(Iterable<int> ids);
  Map<String, String> get playbackHeaders;
  Future<void> dispose();
}

class LanBackupService extends ChangeNotifier implements LanBackupSink {
  LanBackupService({
    MethodChannel? channel,
    HttpClient? httpClient,
    Future<bool> Function()? wifiConnected,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _channel = channel ?? _defaultChannel,
       _httpClient = httpClient ?? HttpClient(),
       // Keep the public injection name readable while the stored callback remains private.
       // ignore: prefer_initializing_formals
       _wifiConnected = wifiConnected,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  static const MethodChannel _defaultChannel = MethodChannel(
    'app.packingproof.mobile/lan_backup',
  );

  final MethodChannel _channel;
  final HttpClient _httpClient;
  final Future<bool> Function()? _wifiConnected;
  final Future<PackageInfo> Function() _packageInfoLoader;
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  Future<void>? _refreshFuture;
  bool _refreshAgain = false;
  bool _nativeHandlerAttached = false;
  String _accessKey = '';
  LanBackupSnapshot _snapshot = const LanBackupSnapshot();
  int _pairingRevision = 0;
  HttpClientRequest? _activePairingRequest;
  LanBackupSnapshot? _pairingRestoreSnapshot;
  String _appVersion = '';
  int _appBuildNumber = 0;

  @override
  LanBackupSnapshot get snapshot => _snapshot;

  @visibleForTesting
  void debugSetSnapshotForTesting(LanBackupSnapshot snapshot) {
    _snapshot = snapshot;
  }

  @override
  Future<void> initialize({
    required bool autoEnabled,
    required UnbackedRetentionPolicy unbackedRetention,
    required BackedRetentionPolicy backedRetention,
  }) async {
    _attachNativeHandler();
    _snapshot = _snapshot.copyWith(autoEnabled: autoEnabled);
    try {
      final PackageInfo packageInfo = await _packageInfoLoader();
      _appVersion = packageInfo.version;
      _appBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
    } on Object {
      // Version checks are optional and must never block recording or backup.
    }
    if (!Platform.isAndroid) {
      notifyListeners();
      return;
    }
    final Map<Object?, Object?> values =
        (await _channel
            .invokeMapMethod<Object?, Object?>('initialize', <String, Object?>{
              'unbackedRetentionDays': unbackedRetention.days,
              'backedRetentionDays': backedRetention.days,
            })) ??
        <Object?, Object?>{};
    _accessKey = (await _channel.invokeMethod<String>('loadAccessKey')) ?? '';
    _applyNativeSnapshot(values);
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(refresh()),
    );
    _heartbeatTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_sendConnectionHeartbeat()),
    );
    unawaited(_sendConnectionHeartbeat());
  }

  static LanBackupEndpoint parsePairingQr(String value) {
    final Uri uri = Uri.parse(value.trim());
    if (uri.scheme != 'http' || uri.host.isEmpty || !uri.hasPort) {
      throw const FormatException('这不是有效的电脑备份二维码');
    }
    final InternetAddress address;
    try {
      address = InternetAddress(uri.host);
    } on ArgumentError {
      throw const FormatException('二维码必须使用局域网 IP 地址');
    }
    if (!isPrivateLanAddress(address)) {
      throw const FormatException('只允许连接局域网电脑');
    }
    return LanBackupEndpoint(
      baseUri: Uri(scheme: 'http', host: uri.host, port: uri.port),
      accessKey: '',
      computerId: '',
      computerName: '',
    );
  }

  @override
  Future<void> pair(
    String qrValue, {
    LanBackupPairingConfirmation? replacementConfirmation,
  }) async {
    final LanBackupEndpoint candidate = parsePairingQr(qrValue);
    await connectToHost(
      candidate.baseUri,
      replacementConfirmation: replacementConfirmation,
    );
  }

  @override
  Future<void> connectToHost(
    Uri baseUri, {
    LanBackupPairingConfirmation? replacementConfirmation,
  }) async {
    await _ensureWifiConnected();
    final LanBackupEndpoint candidateEndpoint;
    try {
      candidateEndpoint = await _readBackupHostIdentity(baseUri);
    } on LanBackupNotHostException {
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.notBackupHost,
        message: '这台电脑当前不是录像备份主机，请切换电脑用途或选择另一台主机',
      );
      notifyListeners();
      rethrow;
    }
    final Set<String> pendingHostIds = _snapshot.jobs
        .where((LanBackupJob job) => job.state != LanBackupJobState.completed)
        .map((LanBackupJob job) => job.destinationComputerId.trim())
        .where((String id) => id.isNotEmpty)
        .toSet();
    final LanBackupEndpoint? currentEndpoint = _snapshot.endpoint;
    final bool changesCurrentHost =
        currentEndpoint != null &&
        !_isSameBackupHost(currentEndpoint, candidateEndpoint);
    final bool changesPendingHost =
        pendingHostIds.isNotEmpty &&
        !pendingHostIds.contains(candidateEndpoint.computerId);
    if ((changesCurrentHost || changesPendingHost) &&
        replacementConfirmation?.matches(candidateEndpoint) != true) {
      throw LanBackupHostMismatchException(
        currentEndpoint:
            currentEndpoint ??
            LanBackupEndpoint(
              baseUri: baseUri,
              accessKey: '',
              computerId: pendingHostIds.first,
              computerName: '原保存主机',
            ),
        candidateEndpoint: candidateEndpoint,
      );
    }
    final int revision = ++_pairingRevision;
    final LanBackupSnapshot restoreSnapshot = _snapshot;
    _pairingRestoreSnapshot = restoreSnapshot;
    _snapshot = _snapshot.copyWith(
      connectionStatus: LanConnectionStatus.connecting,
    );
    notifyListeners();
    try {
      final Uri enrollmentUri = baseUri.replace(
        path: '/api/mobile-backup/enroll',
      );
      final List<int> enrollmentBody = utf8.encode(
        jsonEncode(<String, Object?>{
          'deviceId': _signingDeviceId,
          'deviceName': _snapshot.deviceName,
          'deviceKind': 'mobile',
        }),
      );
      final HttpClientRequest request = await _httpClient
          .postUrl(enrollmentUri)
          .timeout(const Duration(seconds: 5));
      if (revision != _pairingRevision) {
        request.abort();
        return;
      }
      _activePairingRequest = request;
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.contentLength = enrollmentBody.length;
      request.add(enrollmentBody);
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      final String body = await utf8.decoder.bind(response).join();
      if (revision != _pairingRevision) return;
      if (response.statusCode == HttpStatus.notFound) {
        throw const LanBackupUnsupportedException();
      }
      if (response.statusCode == HttpStatus.forbidden) {
        throw const LanBackupConnectionException('保存主机未允许连接，请重新申请');
      }
      if (response.statusCode == HttpStatus.conflict) {
        throw const LanBackupNotHostException();
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw const LanBackupConnectionException('连接申请过于频繁，请稍后重试');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('电脑连接失败（${response.statusCode}）');
      }
      final Map<String, Object?> enrollment = Map<String, Object?>.from(
        jsonDecode(body) as Map<Object?, Object?>,
      );
      final String deviceToken = '${enrollment['deviceToken'] ?? ''}'.trim();
      if (enrollment['protocol'] != _backupProtocol ||
          (enrollment['version'] as num?)?.toInt() != 2 ||
          (enrollment['authVersion'] as num?)?.toInt() !=
              _backupAuthenticationVersion ||
          '${enrollment['deviceId'] ?? ''}'.trim().toLowerCase() !=
              _signingDeviceId.toLowerCase() ||
          deviceToken.length < 32) {
        throw const LanBackupUnsupportedException();
      }
      final LanBackupEndpoint connectedEndpoint = LanBackupEndpoint(
        baseUri: baseUri,
        accessKey: '',
        computerId: '${enrollment['computerId'] ?? ''}',
        computerName: '${enrollment['computerName'] ?? '已连接电脑'}',
        lastConnectedAt: DateTime.now(),
      );
      final String assignedDeviceName =
          '${enrollment['deviceName'] ?? _snapshot.deviceName}'.trim();
      if (revision != _pairingRevision) return;
      final LanBackupEndpoint? currentEndpoint = restoreSnapshot.endpoint;
      if (currentEndpoint != null &&
          !_isSameBackupHost(currentEndpoint, connectedEndpoint) &&
          replacementConfirmation?.matches(connectedEndpoint) != true) {
        throw LanBackupHostMismatchException(
          currentEndpoint: currentEndpoint,
          candidateEndpoint: connectedEndpoint,
        );
      }
      await _channel.invokeMethod<void>('saveConnection', <String, Object?>{
        'baseUrl': baseUri.toString(),
        'accessKey': deviceToken,
        'computerId': connectedEndpoint.computerId,
        'computerName': connectedEndpoint.computerName,
        'deviceName': assignedDeviceName,
      });
      if (revision != _pairingRevision) {
        await _restorePersistedConnection(restoreSnapshot);
        return;
      }
      _accessKey = deviceToken;
      _snapshot = _snapshot.copyWith(
        deviceName: assignedDeviceName,
        endpoint: connectedEndpoint,
        connectionStatus: LanConnectionStatus.connected,
        message: '保存主机已允许连接',
      );
      notifyListeners();
      unawaited(_sendConnectionHeartbeat());
      unawaited(refresh());
    } on LanBackupHostMismatchException {
      if (revision != _pairingRevision) return;
      _snapshot = restoreSnapshot;
      notifyListeners();
      rethrow;
    } on LanBackupNotHostException {
      if (revision != _pairingRevision) return;
      _snapshot = restoreSnapshot.endpoint != null
          ? restoreSnapshot
          : _snapshot.copyWith(
              connectionStatus: LanConnectionStatus.notBackupHost,
              message: '这台电脑当前不是录像备份主机，请切换电脑用途或选择另一台主机',
            );
      notifyListeners();
      rethrow;
    } on FormatException {
      if (revision != _pairingRevision) return;
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.rePair,
      );
      notifyListeners();
      rethrow;
    } on SocketException {
      if (revision != _pairingRevision) return;
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.offline,
      );
      notifyListeners();
      throw const LanBackupConnectionException(
        '无法通过局域网连接电脑，请确认手机和电脑连接了同一个 Wi-Fi',
      );
    } on TimeoutException {
      if (revision != _pairingRevision) return;
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.offline,
      );
      notifyListeners();
      throw const LanBackupConnectionException('等待保存主机允许连接超时，请重新申请');
    } on Object {
      if (revision != _pairingRevision) return;
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.offline,
      );
      notifyListeners();
      rethrow;
    } finally {
      if (revision == _pairingRevision) {
        _activePairingRequest = null;
        _pairingRestoreSnapshot = null;
      }
    }
  }

  Future<LanBackupEndpoint> _readBackupHostIdentity(Uri baseUri) async {
    final HttpClientRequest request = await _httpClient
        .getUrl(baseUri.replace(path: '/api/node-info'))
        .timeout(const Duration(seconds: 5));
    request.followRedirects = false;
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 8),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw const LanBackupConnectionException('无法读取保存主机信息');
    }
    final Map<String, Object?> node = Map<String, Object?>.from(
      jsonDecode(body) as Map<Object?, Object?>,
    );
    final Set<String> capabilities =
        ((node['capabilities'] as List<Object?>?) ?? const <Object?>[])
            .map((Object? value) => '$value'.toLowerCase())
            .toSet();
    if (!capabilities.contains('host') ||
        !capabilities.contains('mobile-backup')) {
      throw const LanBackupNotHostException();
    }
    final String nodeId = '${node['nodeId'] ?? ''}'.trim();
    if (nodeId.isEmpty) throw const LanBackupUnsupportedException();
    return LanBackupEndpoint(
      baseUri: baseUri,
      accessKey: '',
      computerId: nodeId,
      computerName: '${node['nodeName'] ?? '录像文件备份主机'}'.trim(),
    );
  }

  @override
  void cancelPairing() {
    final LanBackupSnapshot? restoreSnapshot = _pairingRestoreSnapshot;
    if (restoreSnapshot == null) return;
    _pairingRevision++;
    _activePairingRequest?.abort();
    _activePairingRequest = null;
    _pairingRestoreSnapshot = null;
    _snapshot = restoreSnapshot;
    notifyListeners();
  }

  Future<void> _restorePersistedConnection(
    LanBackupSnapshot restoreSnapshot,
  ) async {
    final LanBackupEndpoint? endpoint = restoreSnapshot.endpoint;
    if (endpoint == null || _accessKey.isEmpty) {
      await _channel.invokeMethod<void>('disconnect');
      return;
    }
    await _channel.invokeMethod<void>('saveConnection', <String, Object?>{
      'baseUrl': endpoint.baseUri.toString(),
      'accessKey': _accessKey,
      'computerId': endpoint.computerId,
      'computerName': endpoint.computerName,
      'deviceName': restoreSnapshot.deviceName,
    });
  }

  @override
  Future<void> disconnect() async {
    await _sendConnectionHeartbeat(connected: false);
    await _channel.invokeMethod<void>('disconnect');
    _snapshot = _snapshot.copyWith(
      clearEndpoint: true,
      connectionStatus: LanConnectionStatus.disconnected,
    );
    _accessKey = '';
    notifyListeners();
  }

  @override
  Future<bool> retryConnection() async {
    final LanBackupEndpoint? endpoint = _snapshot.endpoint;
    if (endpoint == null || _accessKey.isEmpty) return false;
    if (_snapshot.connectionStatus == LanConnectionStatus.notBackupHost) {
      _snapshot = _snapshot.copyWith(message: '电脑用途改变后需要重新搜索，或扫码选择另一台录像备份主机');
      notifyListeners();
      return false;
    }
    if (!await _hasWifiConnection()) {
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.offline,
        message: '请先连接与电脑相同的 Wi-Fi 后重试',
      );
      notifyListeners();
      return false;
    }
    _snapshot = _snapshot.copyWith(
      connectionStatus: LanConnectionStatus.connecting,
      message: '正在重新连接电脑',
    );
    notifyListeners();
    try {
      final HttpClientRequest request = await _httpClient
          .getUrl(
            endpoint.baseUri.replace(path: '/api/mobile-backup/capabilities'),
          )
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      _setSignedBackupHeaders(
        request,
        _accessKey,
        const <int>[],
        method: 'GET',
        path: endpoint.baseUri
            .replace(path: '/api/mobile-backup/capabilities')
            .path,
      );
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        _snapshot = _snapshot.copyWith(
          connectionStatus: LanConnectionStatus.rePair,
          message: '设备连接已失效，请重新申请并在电脑上允许连接',
        );
        notifyListeners();
        return false;
      }
      if (response.statusCode == HttpStatus.notFound &&
          await _probeBackupHost(endpoint.baseUri) ==
              _BackupHostProbe.notBackupHost) {
        _snapshot = _snapshot.copyWith(
          connectionStatus: LanConnectionStatus.notBackupHost,
          message: '连接的电脑当前不是录像备份主机，请切换电脑用途或重新搜索',
        );
        notifyListeners();
        return false;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('电脑连接失败（${response.statusCode}）');
      }
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.connected,
        message: '电脑已重新连接',
      );
      notifyListeners();
      unawaited(_sendConnectionHeartbeat());
      return true;
    } on Object {
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.offline,
        message: '仍无法连接，请确认电脑端已打开且处于同一局域网',
      );
      notifyListeners();
      return false;
    }
  }

  @override
  Future<void> setAutoEnabled(bool enabled) async {
    _snapshot = _snapshot.copyWith(autoEnabled: enabled);
    notifyListeners();
  }

  @override
  Future<void> setRetentionPolicies({
    required UnbackedRetentionPolicy unbacked,
    required BackedRetentionPolicy backed,
  }) async {
    await _channel.invokeMethod<void>('setRetentionPolicies', <String, Object?>{
      'unbackedRetentionDays': unbacked.days,
      'backedRetentionDays': backed.days,
    });
    await refresh();
  }

  @override
  Future<void> enqueueFinalizedFile(
    String filePath,
    List<RecordingSession> sessions,
  ) => _enqueue(filePath, sessions, startUpload: _snapshot.autoEnabled);

  Future<void> _enqueue(
    String filePath,
    List<RecordingSession> sessions, {
    required bool startUpload,
    bool forceRestart = false,
  }) async {
    final File source = File(filePath);
    try {
      if (!source.existsSync() || source.lengthSync() <= 0) return;
    } on FileSystemException {
      return;
    }
    await _channel.invokeMethod<void>('enqueue', <String, Object?>{
      'filePath': filePath,
      'sessions': sessions
          .map(recordingSessionBackupMap)
          .toList(growable: false),
      'startUpload': startUpload,
      'forceRestart': forceRestart,
    });
    await refresh();
  }

  @override
  Future<void> backupAll(List<RecordingSession> sessions) async {
    final Map<String, List<RecordingSession>> grouped =
        <String, List<RecordingSession>>{};
    for (final RecordingSession session in sessions) {
      grouped
          .putIfAbsent(session.filePath, () => <RecordingSession>[])
          .add(session);
    }
    for (final MapEntry<String, List<RecordingSession>> entry
        in grouped.entries) {
      await _enqueue(
        entry.key,
        entry.value,
        startUpload: true,
        forceRestart: true,
      );
    }
  }

  @override
  Future<void> retry(String jobId) async {
    await _channel.invokeMethod<void>('retry', <String, Object>{'id': jobId});
    await refresh();
  }

  @override
  Future<void> cancel(String jobId) async {
    await _channel.invokeMethod<void>('cancel', <String, Object>{'id': jobId});
    await refresh();
  }

  @override
  Future<StorageSpaceResult> checkAndReclaimStorage() async {
    if (!Platform.isAndroid) {
      return const StorageSpaceResult(
        availableBytes: 1 << 62,
        availableBytesBefore: 1 << 62,
        freedBytes: 0,
        deletedCount: 0,
        warning: false,
        insufficient: false,
      );
    }
    final Map<Object?, Object?> values =
        (await _channel.invokeMapMethod<Object?, Object?>(
          'checkAndReclaimStorage',
        )) ??
        <Object?, Object?>{};
    await refresh();
    return StorageSpaceResult.fromMap(values);
  }

  @override
  Future<void> refresh() {
    if (!Platform.isAndroid) {
      return Future<void>.value();
    }
    final Future<void>? active = _refreshFuture;
    if (active != null) {
      _refreshAgain = true;
      return active;
    }
    final Future<void> refresh = _refreshLoop();
    _refreshFuture = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshFuture, refresh)) _refreshFuture = null;
    });
  }

  Future<void> _refreshLoop() async {
    do {
      _refreshAgain = false;
      await _refreshOnce();
    } while (_refreshAgain);
  }

  Future<void> _refreshOnce() async {
    try {
      final Map<Object?, Object?> values =
          (await _channel.invokeMapMethod<Object?, Object?>('snapshot')) ??
          <Object?, Object?>{};
      _applyNativeSnapshot(values);
    } on PlatformException {
      // A worker can briefly hold the state file while replacing it.
    }
  }

  void _attachNativeHandler() {
    if (_nativeHandlerAttached || !Platform.isAndroid) return;
    _nativeHandlerAttached = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'snapshotChanged' || call.arguments is! Map) return;
      _applyNativeSnapshot(Map<Object?, Object?>.from(call.arguments! as Map));
    });
  }

  @override
  Future<RemoteRecordingPage> fetchRemoteRecordings({
    required int page,
    required int pageSize,
    String keyword = '',
  }) async {
    final LanBackupEndpoint? endpoint = _snapshot.endpoint;
    if (endpoint == null || _accessKey.isEmpty) {
      return const RemoteRecordingPage.empty();
    }
    final Uri uri = buildRemoteRecordingsUri(
      endpoint.baseUri,
      page: page,
      pageSize: pageSize,
      keyword: keyword,
    );
    try {
      final HttpClientRequest request = await _httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      _setSignedBackupHeaders(
        request,
        _accessKey,
        const <int>[],
        method: 'GET',
        path: uri.path,
      );
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final String body = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        _snapshot = _snapshot.copyWith(
          connectionStatus: LanConnectionStatus.rePair,
        );
        notifyListeners();
        return const RemoteRecordingPage.empty();
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('电脑录像读取失败（${response.statusCode}）');
      }
      final Map<String, Object?> payload = Map<String, Object?>.from(
        jsonDecode(body) as Map<Object?, Object?>,
      );
      final List<RemoteRecording> recordings =
          ((payload['data'] as List<Object?>?) ?? const <Object?>[])
              .map(
                (Object? value) => RemoteRecording.fromJson(
                  Map<String, Object?>.from(value! as Map),
                  endpoint.baseUri,
                ),
              )
              .toList(growable: false);
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.connected,
      );
      notifyListeners();
      return RemoteRecordingPage(
        data: recordings,
        page: (payload['page'] as num?)?.toInt() ?? page,
        pageSize: (payload['pageSize'] as num?)?.toInt() ?? pageSize,
        total: (payload['total'] as num?)?.toInt() ?? recordings.length,
        deviceTotal: (payload['deviceTotal'] as num?)?.toInt() ?? 0,
      );
    } on Object {
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.offline,
      );
      notifyListeners();
      return const RemoteRecordingPage.empty();
    }
  }

  @override
  Future<Map<int, ({RemoteRecordingStatus status, bool exists, String reason})>>
  fetchRemoteRecordingStatuses(Iterable<int> ids) async {
    final LanBackupEndpoint? endpoint = _snapshot.endpoint;
    final List<int> values = ids
        .where((int id) => id > 0)
        .toSet()
        .take(100)
        .toList();
    if (endpoint == null || _accessKey.isEmpty || values.isEmpty) {
      return const <
        int,
        ({RemoteRecordingStatus status, bool exists, String reason})
      >{};
    }
    final Uri uri = endpoint.baseUri.replace(
      path: '/api/mobile-backup/videos/status',
      queryParameters: <String, String>{'ids': values.join(',')},
    );
    final HttpClientRequest request = await _httpClient
        .getUrl(uri)
        .timeout(const Duration(seconds: 5));
    _setSignedBackupHeaders(
      request,
      _accessKey,
      const <int>[],
      method: 'GET',
      path: uri.path,
    );
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 10),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('电脑录像状态读取失败（${response.statusCode}）');
    }
    final Map<String, Object?> payload = Map<String, Object?>.from(
      jsonDecode(body) as Map<Object?, Object?>,
    );
    return <int, ({RemoteRecordingStatus status, bool exists, String reason})>{
      for (final Object? value
          in (payload['data'] as List<Object?>?) ?? const <Object?>[])
        if (value is Map)
          (value['id'] as num).toInt(): (
            status: RemoteRecordingStatus.values.firstWhere(
              (RemoteRecordingStatus status) => status.name == value['status'],
              orElse: () => RemoteRecordingStatus.missing,
            ),
            exists: value['exists'] == true,
            reason: '${value['reason'] ?? ''}',
          ),
    };
  }

  @override
  Map<String, String> get playbackHeaders => const <String, String>{};

  Future<void> _ensureWifiConnected() async {
    if (!await _hasWifiConnection()) {
      throw const FormatException('请先连接与电脑相同的 Wi-Fi 后重试');
    }
  }

  Future<bool> _hasWifiConnection() async {
    final Future<bool> Function()? override = _wifiConnected;
    if (override != null) return override();
    if (!Platform.isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>('isWifiConnected')) == true;
    } on PlatformException {
      return false;
    }
  }

  void _setSignedBackupHeaders(
    HttpClientRequest request,
    String deviceCredential,
    List<int> content, {
    required String method,
    required String path,
  }) {
    final String deviceId = _signingDeviceId;
    if (deviceId.isEmpty) {
      throw const FormatException('手机设备身份尚未准备好，请稍后重试');
    }
    final int timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final Random random = Random.secure();
    final String nonce = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((int value) => value.toRadixString(16).padLeft(2, '0')).join();
    final String contentHash = sha256.convert(content).toString();
    final String canonical = <String>[
      method.toUpperCase(),
      path,
      '$timestamp',
      nonce,
      contentHash,
      deviceId.toLowerCase(),
    ].join('\n');
    final String signature = Hmac(
      sha256,
      _decodeSecret(deviceCredential),
    ).convert(utf8.encode(canonical)).toString();
    request.headers.set('X-EPM-Auth-Version', '$_backupAuthenticationVersion');
    request.headers.set('X-EPM-Timestamp', '$timestamp');
    request.headers.set('X-EPM-Nonce', nonce);
    request.headers.set('X-EPM-Content-SHA256', contentHash);
    request.headers.set('X-EPM-Signature', signature);
    request.headers.set('X-EPM-Device-Id', deviceId);
    request.headers.set('X-EPM-Device-Kind', 'mobile');
    if (_snapshot.deviceName.isNotEmpty) {
      request.headers.set(
        'X-EPM-Device-Name',
        Uri.encodeComponent(_snapshot.deviceName),
      );
    }
  }

  String get _signingDeviceId {
    final String deviceId = _snapshot.deviceId.trim();
    if (deviceId.isNotEmpty) return deviceId;
    if (!Platform.isAndroid) {
      return '00000000-0000-0000-0000-000000000001';
    }
    throw const FormatException('手机设备身份尚未准备好，请稍后重试');
  }

  Future<void> _sendConnectionHeartbeat({bool connected = true}) async {
    final LanBackupEndpoint? endpoint = _snapshot.endpoint;
    if (endpoint == null ||
        _accessKey.isEmpty ||
        _snapshot.deviceId.isEmpty ||
        _snapshot.deviceName.isEmpty) {
      return;
    }
    try {
      final HttpClientRequest request = await _httpClient
          .postUrl(endpoint.baseUri.replace(path: '/api/connections/heartbeat'))
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, Object?>{
          'clientId': _snapshot.deviceId,
          'clientType': 'mobile-app',
          'displayName': _snapshot.deviceName,
          'connected': connected,
          'nodeId': _snapshot.deviceId,
          'deviceType': 'mobile',
          'orderReceiverPort': 5280,
          'capabilities': const <String>['recording', 'order-receiver'],
          'appVersion': _appVersion,
          'appBuildNumber': _appBuildNumber,
        }),
      );
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final String responseBody = await utf8.decoder.bind(response).join();
      if (connected) {
        LanConnectionStatus nextStatus = heartbeatConnectionStatus(
          response.statusCode,
        );
        final _BackupHostProbe hostProbe = await _probeBackupHost(
          endpoint.baseUri,
        );
        if (hostProbe == _BackupHostProbe.notBackupHost ||
            _snapshot.connectionStatus == LanConnectionStatus.notBackupHost) {
          nextStatus = LanConnectionStatus.notBackupHost;
        }
        _applyHeartbeatConnectionStatus(nextStatus);
        if (nextStatus == LanConnectionStatus.connected &&
            responseBody.isNotEmpty) {
          _applyMobileAppUpdateResponse(responseBody);
        }
      }
    } on Object {
      if (connected &&
          _snapshot.connectionStatus != LanConnectionStatus.notBackupHost) {
        _applyHeartbeatConnectionStatus(LanConnectionStatus.offline);
      }
    }
  }

  void _applyHeartbeatConnectionStatus(LanConnectionStatus status) {
    if (_snapshot.connectionStatus == status) return;
    _snapshot = _snapshot.copyWith(
      connectionStatus: status,
      message: switch (status) {
        LanConnectionStatus.connected => '电脑已重新连接',
        LanConnectionStatus.rePair => '设备连接已失效，请重新申请并在电脑上允许连接',
        LanConnectionStatus.notBackupHost => '连接的电脑当前不是录像备份主机，请切换电脑用途或重新搜索',
        _ => '电脑已离线，正在自动重新连接',
      },
    );
    notifyListeners();
  }

  Future<_BackupHostProbe> _probeBackupHost(Uri baseUri) async {
    try {
      final HttpClientRequest request = await _httpClient
          .getUrl(baseUri.replace(path: '/api/node-info'))
          .timeout(const Duration(seconds: 3));
      request.followRedirects = false;
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final String body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        return _BackupHostProbe.unknown;
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map || decoded['protocol'] != 'packingproof') {
        return _BackupHostProbe.unknown;
      }
      final List<Object?> capabilities = decoded['capabilities'] is List
          ? List<Object?>.from(decoded['capabilities']! as List)
          : const <Object?>[];
      return capabilities.any(
            (Object? value) => '$value'.toLowerCase() == 'mobile-backup',
          )
          ? _BackupHostProbe.backupHost
          : _BackupHostProbe.notBackupHost;
    } on Object {
      return _BackupHostProbe.unknown;
    }
  }

  void _applyMobileAppUpdateResponse(String responseBody) {
    try {
      final Object? decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic> ||
          !decoded.containsKey('mobileAppUpdate') ||
          decoded['mobileAppUpdate'] is! Map) {
        return;
      }

      final MobileAppUpdateNotice? notice = evaluateMobileAppUpdatePolicy(
        Map<String, Object?>.from(decoded['mobileAppUpdate']! as Map),
        currentVersion: _appVersion,
        currentBuildNumber: _appBuildNumber,
      );
      final MobileAppUpdateNotice? previous = _snapshot.mobileAppUpdate;
      if (previous?.signature == notice?.signature &&
          previous?.message == notice?.message) {
        return;
      }
      _snapshot = _snapshot.copyWith(
        mobileAppUpdate: notice,
        clearMobileAppUpdate: notice == null,
      );
      notifyListeners();
    } on Object {
      // Invalid or newer policy formats are ignored for forward compatibility.
    }
  }

  void _applyNativeSnapshot(Map<Object?, Object?> values) {
    LanBackupEndpoint? endpoint;
    final Object? connectionValue = values['connection'];
    if (connectionValue is Map<Object?, Object?>) {
      endpoint = LanBackupEndpoint(
        baseUri: Uri.parse(connectionValue['baseUrl']! as String),
        accessKey: '',
        computerId: connectionValue['computerId']! as String,
        computerName: connectionValue['computerName']! as String,
        lastConnectedAt: DateTime.tryParse(
          '${connectionValue['lastConnectedAt'] ?? ''}',
        ),
      );
    }
    final List<LanBackupJob> jobs =
        ((values['jobs'] as List<Object?>?) ?? const <Object?>[])
            .map(
              (Object? item) => LanBackupJob.fromMap(
                Map<Object?, Object?>.from(item! as Map),
              ),
            )
            .toList(growable: false);
    final Object? migrationValue = values['migrationHost'];
    final Map<Object?, Object?> migration = migrationValue is Map
        ? Map<Object?, Object?>.from(migrationValue)
        : const <Object?, Object?>{};
    _snapshot = LanBackupSnapshot(
      deviceId: '${values['deviceId'] ?? _snapshot.deviceId}',
      deviceName: '${values['deviceName'] ?? _snapshot.deviceName}',
      preferredHostId: endpoint == null
          ? '${migration['computerId'] ?? _snapshot.preferredHostId}'
          : '',
      preferredHostName: endpoint == null
          ? '${migration['computerName'] ?? _snapshot.preferredHostName}'
          : '',
      endpoint: endpoint,
      jobs: jobs,
      autoEnabled: _snapshot.autoEnabled,
      connectionStatus: nativeBackupConnectionStatus(
        previous: _snapshot.connectionStatus,
        endpoint: endpoint,
        jobs: jobs,
      ),
      message:
          jobs.any(
            (LanBackupJob job) =>
                job.failureKind == LanBackupFailureKind.credentialInvalid,
          )
          ? '设备连接已失效，请重新申请并在电脑上允许连接'
          : jobs.any(
              (LanBackupJob job) =>
                  job.failureKind == LanBackupFailureKind.notBackupHost,
            )
          ? '连接的电脑当前不是录像备份主机，请切换电脑用途或重新搜索'
          : _snapshot.message,
    );
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _sendConnectionHeartbeat(connected: false);
    if (_nativeHandlerAttached) {
      _channel.setMethodCallHandler(null);
      _nativeHandlerAttached = false;
    }
    _httpClient.close(force: true);
    super.dispose();
  }
}

enum _BackupHostProbe { backupHost, notBackupHost, unknown }

bool _isSameBackupHost(LanBackupEndpoint current, LanBackupEndpoint candidate) {
  final String currentId = current.computerId.trim();
  final String candidateId = candidate.computerId.trim();
  if (currentId.isNotEmpty && candidateId.isNotEmpty) {
    return currentId == candidateId;
  }
  return _normalizedHostUri(current.baseUri) ==
      _normalizedHostUri(candidate.baseUri);
}

String _normalizedHostUri(Uri uri) => Uri(
  scheme: uri.scheme.toLowerCase(),
  host: uri.host.toLowerCase(),
  port: uri.hasPort ? uri.port : null,
).toString();

LanConnectionStatus nativeBackupConnectionStatus({
  required LanConnectionStatus previous,
  required LanBackupEndpoint? endpoint,
  required List<LanBackupJob> jobs,
}) {
  if (endpoint == null) return LanConnectionStatus.disconnected;
  if (jobs.any(
    (LanBackupJob job) =>
        job.failureKind == LanBackupFailureKind.credentialInvalid,
  )) {
    return LanConnectionStatus.rePair;
  }
  if (jobs.any(
    (LanBackupJob job) => job.failureKind == LanBackupFailureKind.notBackupHost,
  )) {
    return LanConnectionStatus.notBackupHost;
  }
  return previous == LanConnectionStatus.disconnected
      ? LanConnectionStatus.connected
      : previous;
}

@visibleForTesting
Uri buildRemoteRecordingsUri(
  Uri baseUri, {
  required int page,
  required int pageSize,
  String keyword = '',
}) {
  return baseUri.replace(
    path: '/api/mobile-backup/videos',
    queryParameters: <String, String>{
      'page': '$page',
      'size': '$pageSize',
      if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
    },
  );
}

@visibleForTesting
LanConnectionStatus heartbeatConnectionStatus(int statusCode) {
  if (statusCode >= 200 && statusCode < 300) {
    return LanConnectionStatus.connected;
  }
  if (statusCode == HttpStatus.unauthorized ||
      statusCode == HttpStatus.forbidden) {
    return LanConnectionStatus.rePair;
  }
  return LanConnectionStatus.offline;
}

@visibleForTesting
MobileAppUpdateNotice? evaluateMobileAppUpdatePolicy(
  Map<String, Object?> value, {
  required String currentVersion,
  required int currentBuildNumber,
}) {
  final int schemaVersion = (value['schemaVersion'] as num?)?.toInt() ?? 0;
  if (schemaVersion != 1 && schemaVersion != 2) return null;
  final String minimumVersion = '${value['minimumVersion'] ?? ''}'.trim();
  final int minimumBuildNumber =
      (value['minimumBuildNumber'] as num?)?.toInt() ?? 0;
  if (minimumVersion.isEmpty || minimumBuildNumber <= 0) return null;

  final bool updateRequired = currentBuildNumber > 0
      ? currentBuildNumber < minimumBuildNumber
      : compareAppVersions(currentVersion, minimumVersion) < 0;
  final String latestVersion = '${value['latestVersion'] ?? ''}'.trim();
  final int latestBuildNumber =
      (value['latestBuildNumber'] as num?)?.toInt() ?? 0;
  final bool updateRecommended = latestBuildNumber > 0
      ? currentBuildNumber <= 0 || currentBuildNumber < latestBuildNumber
      : latestVersion.isNotEmpty &&
            compareAppVersions(currentVersion, latestVersion) < 0;
  if (!updateRequired && !updateRecommended) return null;

  return MobileAppUpdateNotice(
    minimumVersion: minimumVersion,
    minimumBuildNumber: minimumBuildNumber,
    message: updateRequired
        ? '${value['message'] ?? ''}'.trim()
        : '发现新版手机 App，建议更新',
    latestVersion: latestVersion,
    latestBuildNumber: latestBuildNumber,
    updateRequired: updateRequired,
  );
}

@visibleForTesting
int compareAppVersions(String left, String right) {
  final List<int> leftParts = _numericVersionParts(left);
  final List<int> rightParts = _numericVersionParts(right);
  final int length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (int index = 0; index < length; index++) {
    final int leftPart = index < leftParts.length ? leftParts[index] : 0;
    final int rightPart = index < rightParts.length ? rightParts[index] : 0;
    if (leftPart != rightPart) return leftPart.compareTo(rightPart);
  }
  return 0;
}

List<int> _numericVersionParts(String value) => value
    .split(RegExp(r'[^0-9]+'))
    .where((String part) => part.isNotEmpty)
    .map((String part) => int.tryParse(part) ?? 0)
    .toList(growable: false);
