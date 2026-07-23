import 'backup_retention_policy.dart';
import 'work_mode.dart';
import 'storage_notice.dart';

class AppSettings {
  const AppSettings({
    this.workMode = WorkMode.continuousScan,
    this.speechEnabled = true,
    this.orderSpeechEnabled = true,
    this.maxVolumeEnabled = true,
    this.startupNoticeVersion = 0,
    this.lanBackupAutoEnabled = true,
    this.unbackedRetention = UnbackedRetentionPolicy.days30,
    this.backedRetention = BackedRetentionPolicy.days7,
    this.hiddenRemoteRecordingIds = const <int>{},
    this.storageNoticeState = const StorageNoticeState(),
    this.extraValues = const <String, Object?>{},
  });

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> extraValues = Map<String, Object?>.of(json)
      ..remove('workMode')
      ..remove('speechEnabled')
      ..remove('orderSpeechEnabled')
      ..remove('maxVolumeEnabled')
      ..remove('startupNoticeVersion')
      ..remove('lanBackupAutoEnabled')
      ..remove('unbackedRetention')
      ..remove('backedRetention');
    extraValues.remove('storageNoticeState');
    final Set<int> hiddenRemoteRecordingIds =
        ((json['hiddenRemoteRecordingIds'] as List<Object?>?) ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .where((value) => value > 0)
            .toSet();
    extraValues.remove('hiddenRemoteRecordingIds');
    return AppSettings(
      workMode: workModeFromStorage(json['workMode']),
      speechEnabled: json['speechEnabled'] is bool
          ? json['speechEnabled']! as bool
          : true,
      orderSpeechEnabled: json['orderSpeechEnabled'] is bool
          ? json['orderSpeechEnabled']! as bool
          : true,
      maxVolumeEnabled: json['maxVolumeEnabled'] is bool
          ? json['maxVolumeEnabled']! as bool
          : true,
      startupNoticeVersion: json['startupNoticeVersion'] is num
          ? (json['startupNoticeVersion']! as num).toInt()
          : 0,
      lanBackupAutoEnabled: json['lanBackupAutoEnabled'] is bool
          ? json['lanBackupAutoEnabled']! as bool
          : true,
      unbackedRetention: unbackedRetentionFromStorage(
        json['unbackedRetention'],
      ),
      backedRetention: backedRetentionFromStorage(json['backedRetention']),
      hiddenRemoteRecordingIds: hiddenRemoteRecordingIds,
      storageNoticeState: StorageNoticeState.fromJson(
        json['storageNoticeState'],
      ),
      extraValues: extraValues,
    );
  }

  final WorkMode workMode;
  final bool speechEnabled;
  final bool orderSpeechEnabled;
  final bool maxVolumeEnabled;
  final int startupNoticeVersion;
  final bool lanBackupAutoEnabled;
  final UnbackedRetentionPolicy unbackedRetention;
  final BackedRetentionPolicy backedRetention;
  final Set<int> hiddenRemoteRecordingIds;
  final StorageNoticeState storageNoticeState;
  final Map<String, Object?> extraValues;

  AppSettings copyWith({
    WorkMode? workMode,
    bool? speechEnabled,
    bool? orderSpeechEnabled,
    bool? maxVolumeEnabled,
    int? startupNoticeVersion,
    bool? lanBackupAutoEnabled,
    UnbackedRetentionPolicy? unbackedRetention,
    BackedRetentionPolicy? backedRetention,
    Set<int>? hiddenRemoteRecordingIds,
    StorageNoticeState? storageNoticeState,
  }) {
    return AppSettings(
      workMode: workMode ?? this.workMode,
      speechEnabled: speechEnabled ?? this.speechEnabled,
      orderSpeechEnabled: orderSpeechEnabled ?? this.orderSpeechEnabled,
      maxVolumeEnabled: maxVolumeEnabled ?? this.maxVolumeEnabled,
      startupNoticeVersion: startupNoticeVersion ?? this.startupNoticeVersion,
      lanBackupAutoEnabled: lanBackupAutoEnabled ?? this.lanBackupAutoEnabled,
      unbackedRetention: unbackedRetention ?? this.unbackedRetention,
      backedRetention: backedRetention ?? this.backedRetention,
      hiddenRemoteRecordingIds:
          hiddenRemoteRecordingIds ?? this.hiddenRemoteRecordingIds,
      storageNoticeState: storageNoticeState ?? this.storageNoticeState,
      extraValues: extraValues,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    ...extraValues,
    'workMode': workMode.storageValue,
    'speechEnabled': speechEnabled,
    'orderSpeechEnabled': orderSpeechEnabled,
    'maxVolumeEnabled': maxVolumeEnabled,
    'startupNoticeVersion': startupNoticeVersion,
    'lanBackupAutoEnabled': lanBackupAutoEnabled,
    'unbackedRetention': unbackedRetention.storageValue,
    'backedRetention': backedRetention.storageValue,
    'hiddenRemoteRecordingIds': hiddenRemoteRecordingIds.toList()..sort(),
    'storageNoticeState': storageNoticeState.toJson(),
  };
}
