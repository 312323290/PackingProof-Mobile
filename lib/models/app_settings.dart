import 'backup_retention_policy.dart';
import 'work_mode.dart';

class AppSettings {
  const AppSettings({
    this.workMode = WorkMode.continuousScan,
    this.speechEnabled = true,
    this.maxVolumeEnabled = true,
    this.standaloneNoticeDismissed = false,
    this.lanBackupAutoEnabled = true,
    this.unbackedRetention = UnbackedRetentionPolicy.days30,
    this.backedRetention = BackedRetentionPolicy.days7,
    this.extraValues = const <String, Object?>{},
  });

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> extraValues = Map<String, Object?>.of(json)
      ..remove('workMode')
      ..remove('speechEnabled')
      ..remove('maxVolumeEnabled')
      ..remove('standaloneNoticeDismissed')
      ..remove('lanBackupAutoEnabled')
      ..remove('unbackedRetention')
      ..remove('backedRetention');
    return AppSettings(
      workMode: workModeFromStorage(json['workMode']),
      speechEnabled: json['speechEnabled'] is bool
          ? json['speechEnabled']! as bool
          : true,
      maxVolumeEnabled: json['maxVolumeEnabled'] is bool
          ? json['maxVolumeEnabled']! as bool
          : true,
      standaloneNoticeDismissed:
          json['standaloneNoticeDismissed'] is bool
          ? json['standaloneNoticeDismissed']! as bool
          : false,
      lanBackupAutoEnabled: json['lanBackupAutoEnabled'] is bool
          ? json['lanBackupAutoEnabled']! as bool
          : true,
      unbackedRetention: unbackedRetentionFromStorage(
        json['unbackedRetention'],
      ),
      backedRetention: backedRetentionFromStorage(json['backedRetention']),
      extraValues: extraValues,
    );
  }

  final WorkMode workMode;
  final bool speechEnabled;
  final bool maxVolumeEnabled;
  final bool standaloneNoticeDismissed;
  final bool lanBackupAutoEnabled;
  final UnbackedRetentionPolicy unbackedRetention;
  final BackedRetentionPolicy backedRetention;
  final Map<String, Object?> extraValues;

  AppSettings copyWith({
    WorkMode? workMode,
    bool? speechEnabled,
    bool? maxVolumeEnabled,
    bool? standaloneNoticeDismissed,
    bool? lanBackupAutoEnabled,
    UnbackedRetentionPolicy? unbackedRetention,
    BackedRetentionPolicy? backedRetention,
  }) {
    return AppSettings(
      workMode: workMode ?? this.workMode,
      speechEnabled: speechEnabled ?? this.speechEnabled,
      maxVolumeEnabled: maxVolumeEnabled ?? this.maxVolumeEnabled,
      standaloneNoticeDismissed:
          standaloneNoticeDismissed ?? this.standaloneNoticeDismissed,
      lanBackupAutoEnabled: lanBackupAutoEnabled ?? this.lanBackupAutoEnabled,
      unbackedRetention: unbackedRetention ?? this.unbackedRetention,
      backedRetention: backedRetention ?? this.backedRetention,
      extraValues: extraValues,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    ...extraValues,
    'workMode': workMode.storageValue,
    'speechEnabled': speechEnabled,
    'maxVolumeEnabled': maxVolumeEnabled,
    'standaloneNoticeDismissed': standaloneNoticeDismissed,
    'lanBackupAutoEnabled': lanBackupAutoEnabled,
    'unbackedRetention': unbackedRetention.storageValue,
    'backedRetention': backedRetention.storageValue,
  };
}
