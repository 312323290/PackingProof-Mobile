import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/lan_backup.dart';
import '../models/recording_session.dart';
import '../models/backup_retention_policy.dart';

class LanBackupUnsupportedException implements Exception {
  const LanBackupUnsupportedException();

  @override
  String toString() => '电脑端版本暂不支持录像备份';
}

abstract interface class LanBackupSink implements Listenable {
  LanBackupSnapshot get snapshot;

  Future<void> initialize({
    required bool autoEnabled,
    required UnbackedRetentionPolicy unbackedRetention,
    required BackedRetentionPolicy backedRetention,
  });
  Future<void> pair(String qrValue);
  Future<void> disconnect();
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
  Future<void> refresh();
  Future<List<RemoteRecording>> fetchRemoteRecordings({
    required int page,
    required int pageSize,
    String keyword,
  });
  Map<String, String> get playbackHeaders;
  Future<void> dispose();
}

class LanBackupService extends ChangeNotifier implements LanBackupSink {
  LanBackupService({MethodChannel? channel, HttpClient? httpClient})
    : _channel = channel ?? _defaultChannel,
      _httpClient = httpClient ?? HttpClient();

  static const MethodChannel _defaultChannel = MethodChannel(
    'app.packingproof.mobile/lan_backup',
  );

  final MethodChannel _channel;
  final HttpClient _httpClient;
  Timer? _pollTimer;
  String _accessKey = '';
  LanBackupSnapshot _snapshot = const LanBackupSnapshot();

  @override
  LanBackupSnapshot get snapshot => _snapshot;

  @override
  Future<void> initialize({
    required bool autoEnabled,
    required UnbackedRetentionPolicy unbackedRetention,
    required BackedRetentionPolicy backedRetention,
  }) async {
    _snapshot = _snapshot.copyWith(autoEnabled: autoEnabled);
    if (!Platform.isAndroid) {
      notifyListeners();
      return;
    }
    final Map<Object?, Object?> values =
        (await _channel.invokeMapMethod<Object?, Object?>('initialize', <String, Object?>{
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
    final String key = uri.queryParameters['key']?.trim() ?? '';
    if (key.length < 16) {
      throw const FormatException('电脑连接密钥无效，请重新生成二维码');
    }
    return LanBackupEndpoint(
      baseUri: Uri(scheme: 'http', host: uri.host, port: uri.port),
      accessKey: key,
      computerId: '',
      computerName: '',
    );
  }

  @override
  Future<void> pair(String qrValue) async {
    final LanBackupEndpoint candidate = parsePairingQr(qrValue);
    _snapshot = _snapshot.copyWith(connectionStatus: LanConnectionStatus.connecting);
    notifyListeners();
    try {
      final Uri capabilityUri = candidate.baseUri.replace(
        path: '/api/mobile-backup/capabilities',
      );
      final HttpClientRequest request = await _httpClient
          .getUrl(capabilityUri)
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.set('X-EPM-Access-Key', candidate.accessKey);
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final String body = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.notFound) {
        throw const LanBackupUnsupportedException();
      }
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const FormatException('电脑连接密钥已失效，请重新扫码');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('电脑连接失败（${response.statusCode}）');
      }
      final Map<String, Object?> capabilities = Map<String, Object?>.from(
        jsonDecode(body) as Map<Object?, Object?>,
      );
      if (capabilities['protocol'] != 'mobile-backup-v1' ||
          (capabilities['version'] as num?)?.toInt() != 1) {
        throw const LanBackupUnsupportedException();
      }
      await _channel.invokeMethod<void>('saveConnection', <String, Object?>{
        'baseUrl': candidate.baseUri.toString(),
        'accessKey': candidate.accessKey,
        'computerId': '${capabilities['computerId'] ?? ''}',
        'computerName': '${capabilities['computerName'] ?? '已连接电脑'}',
      });
      _accessKey = candidate.accessKey;
      await refresh();
      _snapshot = _snapshot.copyWith(
        connectionStatus: LanConnectionStatus.connected,
        message: '电脑连接成功',
      );
      notifyListeners();
    } on FormatException {
      _snapshot = _snapshot.copyWith(connectionStatus: LanConnectionStatus.rePair);
      notifyListeners();
      rethrow;
    } on Object {
      _snapshot = _snapshot.copyWith(connectionStatus: LanConnectionStatus.offline);
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _channel.invokeMethod<void>('disconnect');
    _snapshot = _snapshot.copyWith(
      clearEndpoint: true,
      connectionStatus: LanConnectionStatus.disconnected,
    );
    _accessKey = '';
    notifyListeners();
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
  }) async {
    if (!File(filePath).existsSync()) {
      return;
    }
    await _channel.invokeMethod<void>('enqueue', <String, Object?>{
      'filePath': filePath,
      'sessions': sessions
          .map(recordingSessionBackupMap)
          .toList(growable: false),
      'startUpload': startUpload,
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
      await _enqueue(entry.key, entry.value, startUpload: true);
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
  Future<void> refresh() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final Map<Object?, Object?> values =
          (await _channel.invokeMapMethod<Object?, Object?>('snapshot')) ??
          <Object?, Object?>{};
      _applyNativeSnapshot(values);
    } on PlatformException {
      // A worker can briefly hold the state file while replacing it.
    }
  }

  @override
  Future<List<RemoteRecording>> fetchRemoteRecordings({
    required int page,
    required int pageSize,
    String keyword = '',
  }) async {
    final LanBackupEndpoint? endpoint = _snapshot.endpoint;
    if (endpoint == null || _accessKey.isEmpty) return const <RemoteRecording>[];
    final Uri uri = endpoint.baseUri.replace(
      path: '/api/videos',
      queryParameters: <String, String>{
        'page': '$page',
        'size': '$pageSize',
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
    try {
      final HttpClientRequest request = await _httpClient.getUrl(uri).timeout(
        const Duration(seconds: 5),
      );
      request.headers.set('X-EPM-Access-Key', _accessKey);
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final String body = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        _snapshot = _snapshot.copyWith(connectionStatus: LanConnectionStatus.rePair);
        notifyListeners();
        return const <RemoteRecording>[];
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
      _snapshot = _snapshot.copyWith(connectionStatus: LanConnectionStatus.connected);
      notifyListeners();
      return recordings;
    } on Object {
      _snapshot = _snapshot.copyWith(connectionStatus: LanConnectionStatus.offline);
      notifyListeners();
      return const <RemoteRecording>[];
    }
  }

  @override
  Map<String, String> get playbackHeaders => _accessKey.isEmpty
      ? const <String, String>{}
      : <String, String>{'X-EPM-Access-Key': _accessKey};

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
    _snapshot = LanBackupSnapshot(
      endpoint: endpoint,
      jobs: jobs,
      autoEnabled: _snapshot.autoEnabled,
      connectionStatus: endpoint == null
          ? LanConnectionStatus.disconnected
          : _snapshot.connectionStatus == LanConnectionStatus.disconnected
          ? LanConnectionStatus.connected
          : _snapshot.connectionStatus,
    );
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _pollTimer?.cancel();
    _httpClient.close(force: true);
    super.dispose();
  }
}
