import 'dart:io';

import 'recording_session.dart';

enum LanBackupJobState { pending, uploading, paused, completed, failed }

enum LanConnectionStatus {
  disconnected,
  connecting,
  connected,
  offline,
  rePair,
}

String lanBackupFileIdentity(String path) {
  final String normalized = path.replaceAll('\\', '/');
  return normalized.replaceFirst(
    RegExp(r'^/data/(?:user/0|data)/([^/]+)/'),
    r'/data/app-private/$1/',
  );
}

bool isSameLanBackupFile(String left, String right) =>
    lanBackupFileIdentity(left) == lanBackupFileIdentity(right);

enum RemoteRecordingStatus { available, deleted, missing }

class LanBackupEndpoint {
  const LanBackupEndpoint({
    required this.baseUri,
    required this.accessKey,
    required this.computerId,
    required this.computerName,
    this.lastConnectedAt,
  });

  final Uri baseUri;
  final String accessKey;
  final String computerId;
  final String computerName;
  final DateTime? lastConnectedAt;

  String get displayAddress =>
      baseUri.hasPort ? '${baseUri.host}:${baseUri.port}' : baseUri.host;
}

class LanBackupJob {
  const LanBackupJob({
    required this.id,
    required this.filePath,
    required this.state,
    required this.uploadedBytes,
    required this.totalBytes,
    this.errorMessage,
    this.fileCreatedAt,
    this.backupCompletedAt,
    this.scheduledCleanupAt,
    this.localDeletedAt,
    this.waitingCleanup = false,
    this.remoteRecordIds = const <int>[],
    this.destinationComputerId = '',
  });

  factory LanBackupJob.fromMap(Map<Object?, Object?> map) {
    return LanBackupJob(
      id: map['id']! as String,
      filePath: map['filePath']! as String,
      state: LanBackupJobState.values.firstWhere(
        (LanBackupJobState value) => value.name == map['state'],
        orElse: () => LanBackupJobState.failed,
      ),
      uploadedBytes: (map['uploadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      errorMessage: map['errorMessage'] as String?,
      fileCreatedAt: _dateTime(map['fileCreatedAt']),
      backupCompletedAt: _dateTime(map['backupCompletedAt']),
      scheduledCleanupAt: _dateTime(map['scheduledCleanupAt']),
      localDeletedAt: _dateTime(map['localDeletedAt']),
      waitingCleanup: map['waitingCleanup'] == true,
      remoteRecordIds: ((map['remoteRecordIds'] as List<Object?>?) ?? const [])
          .whereType<num>()
          .map((num value) => value.toInt())
          .toList(growable: false),
      destinationComputerId: '${map['destinationComputerId'] ?? ''}',
    );
  }

  final String id;
  final String filePath;
  final LanBackupJobState state;
  final int uploadedBytes;
  final int totalBytes;
  final String? errorMessage;
  final DateTime? fileCreatedAt;
  final DateTime? backupCompletedAt;
  final DateTime? scheduledCleanupAt;
  final DateTime? localDeletedAt;
  final bool waitingCleanup;
  final List<int> remoteRecordIds;
  final String destinationComputerId;

  double get progress => totalBytes <= 0 ? 0 : uploadedBytes / totalBytes;
}

class LanBackupSnapshot {
  const LanBackupSnapshot({
    this.endpoint,
    this.jobs = const <LanBackupJob>[],
    this.autoEnabled = true,
    this.message,
    this.connectionStatus = LanConnectionStatus.disconnected,
    this.deviceId = '',
  });

  final LanBackupEndpoint? endpoint;
  final List<LanBackupJob> jobs;
  final bool autoEnabled;
  final String? message;
  final LanConnectionStatus connectionStatus;
  final String deviceId;

  bool get connected => endpoint != null;
  int get pendingCount => jobs.where((LanBackupJob job) {
    return job.state != LanBackupJobState.completed;
  }).length;

  int get activeCount => jobs.where((LanBackupJob job) {
    return job.state == LanBackupJobState.pending ||
        job.state == LanBackupJobState.uploading ||
        job.state == LanBackupJobState.paused;
  }).length;

  int get completedCount => jobs
      .where((LanBackupJob job) => job.state == LanBackupJobState.completed)
      .length;

  double get aggregateProgress {
    final List<LanBackupJob> active = jobs
        .where((LanBackupJob job) => job.state != LanBackupJobState.completed)
        .toList(growable: false);
    final int total = active.fold(
      0,
      (int sum, LanBackupJob job) => sum + job.totalBytes,
    );
    if (total <= 0) return 0;
    final int uploaded = active.fold(
      0,
      (int sum, LanBackupJob job) => sum + job.uploadedBytes,
    );
    return (uploaded / total).clamp(0, 1);
  }

  LanBackupSnapshot copyWith({
    LanBackupEndpoint? endpoint,
    bool clearEndpoint = false,
    List<LanBackupJob>? jobs,
    bool? autoEnabled,
    String? message,
    bool clearMessage = false,
    LanConnectionStatus? connectionStatus,
    String? deviceId,
  }) {
    return LanBackupSnapshot(
      endpoint: clearEndpoint ? null : endpoint ?? this.endpoint,
      jobs: jobs ?? this.jobs,
      autoEnabled: autoEnabled ?? this.autoEnabled,
      message: clearMessage ? null : message ?? this.message,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}

class RemoteRecording {
  const RemoteRecording({
    required this.id,
    required this.trackingNumber,
    required this.startedAt,
    required this.duration,
    required this.sourceType,
    required this.sourceDeviceId,
    required this.sourceDeviceName,
    required this.sourceSessionId,
    required this.contentSha256,
    required this.playUri,
    this.thumbnailUri,
    this.exists = true,
    this.status = RemoteRecordingStatus.available,
    this.statusReason = '',
  });

  factory RemoteRecording.fromJson(Map<String, Object?> json, Uri baseUri) {
    final String rawStart = '${json['startTime'] ?? ''}';
    return RemoteRecording(
      id: (json['id'] as num).toInt(),
      trackingNumber: '${json['trackingNumber'] ?? json['orderId'] ?? ''}',
      startedAt:
          DateTime.tryParse(rawStart) ?? DateTime.fromMillisecondsSinceEpoch(0),
      duration: Duration(
        milliseconds: (((json['durationSec'] as num?) ?? 0) * 1000).round(),
      ),
      sourceType: '${json['sourceType'] ?? 'pc'}',
      sourceDeviceId: '${json['sourceDeviceId'] ?? ''}',
      sourceDeviceName: '${json['sourceDeviceName'] ?? ''}',
      sourceSessionId: '${json['sourceSessionId'] ?? ''}',
      contentSha256: '${json['contentSha256'] ?? ''}',
      playUri: baseUri.resolve(
        '${json['playUrl'] ?? '/api/videos/${json['id']}/play?compat=0'}',
      ),
      thumbnailUri: json['thumbnailUrl'] == null
          ? null
          : baseUri.resolve('${json['thumbnailUrl']}'),
      exists: json['exists'] != false,
    );
  }

  final int id;
  final String trackingNumber;
  final DateTime startedAt;
  final Duration duration;
  final String sourceType;
  final String sourceDeviceId;
  final String sourceDeviceName;
  final String sourceSessionId;
  final String contentSha256;
  final Uri playUri;
  final Uri? thumbnailUri;
  final bool exists;
  final RemoteRecordingStatus status;
  final String statusReason;

  RemoteRecording withStatus({
    required RemoteRecordingStatus status,
    required bool exists,
    String reason = '',
  }) => RemoteRecording(
    id: id,
    trackingNumber: trackingNumber,
    startedAt: startedAt,
    duration: duration,
    sourceType: sourceType,
    sourceDeviceId: sourceDeviceId,
    sourceDeviceName: sourceDeviceName,
    sourceSessionId: sourceSessionId,
    contentSha256: contentSha256,
    playUri: playUri,
    thumbnailUri: thumbnailUri,
    exists: exists,
    status: status,
    statusReason: reason,
  );
}

class RemoteRecordingPage {
  const RemoteRecordingPage({
    required this.data,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.deviceTotal,
  });

  const RemoteRecordingPage.empty()
    : data = const <RemoteRecording>[],
      page = 1,
      pageSize = 5,
      total = 0,
      deviceTotal = 0;

  final List<RemoteRecording> data;
  final int page;
  final int pageSize;
  final int total;
  final int deviceTotal;

  int get pageCount => total <= 0 ? 0 : (total + pageSize - 1) ~/ pageSize;
  bool get hasMore => page < pageCount;
}

DateTime? _dateTime(Object? value) => switch (value) {
  String text => DateTime.tryParse(text),
  num milliseconds => DateTime.fromMillisecondsSinceEpoch(
    milliseconds.toInt(),
    isUtc: true,
  ),
  _ => null,
};

Map<String, Object?> recordingSessionBackupMap(RecordingSession session) {
  return <String, Object?>{
    'id': session.id,
    'trackingNumber': session.displayCode,
    'startedAt': session.startedAt.toUtc().toIso8601String(),
    'endedAt': session.endedAt.toUtc().toIso8601String(),
    'mediaStartMs': session.mediaStart.inMilliseconds,
    'mediaEndMs': session.playbackEnd.inMilliseconds,
    'markers': session.markers
        .map(
          (marker) => <String, Object?>{
            'code': marker.code,
            'occurredAt': marker.occurredAt.toUtc().toIso8601String(),
            'offsetMs': marker.offset.inMilliseconds,
          },
        )
        .toList(growable: false),
  };
}

bool isPrivateLanAddress(InternetAddress address) {
  if (address.type == InternetAddressType.IPv4) {
    final List<int> bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        (bytes[0] == 169 && bytes[1] == 254);
  }
  final List<int> bytes = address.rawAddress;
  return (bytes[0] & 0xFE) == 0xFC ||
      (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80);
}
