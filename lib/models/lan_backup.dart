import 'dart:io';

import 'recording_session.dart';

enum LanBackupJobState { pending, uploading, paused, completed, failed }

class LanBackupEndpoint {
  const LanBackupEndpoint({
    required this.baseUri,
    required this.accessKey,
    required this.computerId,
    required this.computerName,
  });

  final Uri baseUri;
  final String accessKey;
  final String computerId;
  final String computerName;
}

class LanBackupJob {
  const LanBackupJob({
    required this.id,
    required this.filePath,
    required this.state,
    required this.uploadedBytes,
    required this.totalBytes,
    this.errorMessage,
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
    );
  }

  final String id;
  final String filePath;
  final LanBackupJobState state;
  final int uploadedBytes;
  final int totalBytes;
  final String? errorMessage;

  double get progress => totalBytes <= 0 ? 0 : uploadedBytes / totalBytes;
}

class LanBackupSnapshot {
  const LanBackupSnapshot({
    this.endpoint,
    this.jobs = const <LanBackupJob>[],
    this.autoEnabled = true,
    this.message,
  });

  final LanBackupEndpoint? endpoint;
  final List<LanBackupJob> jobs;
  final bool autoEnabled;
  final String? message;

  bool get connected => endpoint != null;
  int get pendingCount => jobs.where((LanBackupJob job) {
    return job.state != LanBackupJobState.completed;
  }).length;

  LanBackupSnapshot copyWith({
    LanBackupEndpoint? endpoint,
    bool clearEndpoint = false,
    List<LanBackupJob>? jobs,
    bool? autoEnabled,
    String? message,
    bool clearMessage = false,
  }) {
    return LanBackupSnapshot(
      endpoint: clearEndpoint ? null : endpoint ?? this.endpoint,
      jobs: jobs ?? this.jobs,
      autoEnabled: autoEnabled ?? this.autoEnabled,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

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
