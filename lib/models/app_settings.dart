import 'work_mode.dart';

class AppSettings {
  const AppSettings({
    this.workMode = WorkMode.continuousScan,
    this.speechEnabled = true,
    this.extraValues = const <String, Object?>{},
  });

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> extraValues = Map<String, Object?>.of(json)
      ..remove('workMode')
      ..remove('speechEnabled');
    return AppSettings(
      workMode: workModeFromStorage(json['workMode']),
      speechEnabled: json['speechEnabled'] is bool
          ? json['speechEnabled']! as bool
          : true,
      extraValues: extraValues,
    );
  }

  final WorkMode workMode;
  final bool speechEnabled;
  final Map<String, Object?> extraValues;

  AppSettings copyWith({WorkMode? workMode, bool? speechEnabled}) {
    return AppSettings(
      workMode: workMode ?? this.workMode,
      speechEnabled: speechEnabled ?? this.speechEnabled,
      extraValues: extraValues,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    ...extraValues,
    'workMode': workMode.storageValue,
    'speechEnabled': speechEnabled,
  };
}
