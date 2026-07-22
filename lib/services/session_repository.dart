import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/backup_retention_policy.dart';
import '../models/recording_session.dart';
import '../models/work_mode.dart';

class SessionRepository {
  SessionRepository({Directory? rootDirectory}) : this._(rootDirectory);

  SessionRepository._(this._rootDirectory);

  Directory? _rootDirectory;
  late Directory _recordingsDirectory;
  late Directory _pendingRecordingsDirectory;
  late File _indexFile;
  late File _settingsFile;
  bool _initialized = false;
  Future<void> _sessionMutationTail = Future<void>.value();
  Future<void> _settingsMutationTail = Future<void>.value();

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _rootDirectory ??= await getApplicationDocumentsDirectory();
    _recordingsDirectory = Directory(
      p.join(_rootDirectory!.path, 'recordings'),
    );
    await _recordingsDirectory.create(recursive: true);
    _pendingRecordingsDirectory = Directory(
      p.join(_recordingsDirectory.path, '.pending'),
    );
    await _pendingRecordingsDirectory.create(recursive: true);
    _indexFile = File(p.join(_rootDirectory!.path, 'sessions.json'));
    _settingsFile = File(p.join(_rootDirectory!.path, 'settings.json'));
    _initialized = true;
  }

  Future<List<RecordingSession>> loadSessions({
    bool includeMissingFiles = false,
  }) => _serializeSessionMutation(
    () => _loadSessionsUnlocked(includeMissingFiles: includeMissingFiles),
  );

  Future<List<RecordingSession>> _loadSessionsUnlocked({
    required bool includeMissingFiles,
  }) async {
    await initialize();
    final File backupFile = File('${_indexFile.path}.bak');
    if (!await _indexFile.exists() && await backupFile.exists()) {
      await backupFile.rename(_indexFile.path);
    }
    if (!await _indexFile.exists()) {
      return <RecordingSession>[];
    }

    try {
      return await _readSessionsIndex(includeMissingFiles);
    } on Object {
      await _archiveCorruptSessionIndex();
      if (await backupFile.exists()) {
        await backupFile.rename(_indexFile.path);
        try {
          return await _readSessionsIndex(includeMissingFiles);
        } on Object {
          await _archiveCorruptSessionIndex();
        }
      }
      return <RecordingSession>[];
    }
  }

  Future<List<RecordingSession>> _readSessionsIndex(
    bool includeMissingFiles,
  ) async {
    final Object? decoded = jsonDecode(await _indexFile.readAsString());
    final List<Object?> values = decoded! as List<Object?>;
    final List<RecordingSession> sessions = values
        .map(
          (Object? value) => RecordingSession.fromJson(
            Map<String, Object?>.from(value! as Map<Object?, Object?>),
          ),
        )
        .where(
          (RecordingSession session) =>
              includeMissingFiles || File(session.filePath).existsSync(),
        )
        .toList();
    sessions.sort(
      (RecordingSession a, RecordingSession b) =>
          b.startedAt.compareTo(a.startedAt),
    );
    return sessions;
  }

  Future<void> _archiveCorruptSessionIndex() async {
    if (!await _indexFile.exists()) return;
    final String backupName =
        'sessions-corrupt-${DateTime.now().microsecondsSinceEpoch}.json';
    await _indexFile.rename(p.join(_rootDirectory!.path, backupName));
  }

  Future<String> finalizeVideo({
    required String sourcePath,
    required String sessionId,
    required DateTime startedAt,
    required String trackingNumber,
  }) => _serializeSessionMutation(
    () => _finalizeVideo(
      sourcePath: sourcePath,
      sessionId: sessionId,
      startedAt: startedAt,
      trackingNumber: trackingNumber,
    ),
  );

  Future<String> _finalizeVideo({
    required String sourcePath,
    required String sessionId,
    required DateTime startedAt,
    required String trackingNumber,
  }) async {
    await initialize();
    final Directory dateDirectory = Directory(
      p.join(_recordingsDirectory.path, _dateDirectoryName(startedAt)),
    );
    await dateDirectory.create(recursive: true);
    final String baseName = _sanitizeFileName(
      '${trackingNumber.trim().isEmpty ? '未识别面单' : trackingNumber.trim()}_'
      '${_timestamp(startedAt)}_发货',
    );
    String destinationPath = p.join(dateDirectory.path, '$baseName.mp4');
    final File source = File(sourcePath);
    if (p.normalize(source.path) == p.normalize(destinationPath)) {
      return destinationPath;
    }
    if (await File(destinationPath).exists()) {
      final String suffix = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final String shortSuffix = suffix.length <= 8
          ? suffix
          : suffix.substring(suffix.length - 8);
      final String collisionSuffix = shortSuffix.isEmpty
          ? '${startedAt.millisecondsSinceEpoch}'
          : shortSuffix;
      var collisionIndex = 1;
      do {
        final String numberedSuffix = collisionIndex == 1
            ? collisionSuffix
            : '${collisionSuffix}_$collisionIndex';
        destinationPath = p.join(
          dateDirectory.path,
          '${baseName}_$numberedSuffix.mp4',
        );
        collisionIndex++;
      } while (await File(destinationPath).exists());
    }
    try {
      await source.rename(destinationPath);
    } on FileSystemException {
      await source.copy(destinationPath);
      try {
        await source.delete();
      } on FileSystemException {
        // The copied recording is already safe; temp cleanup can be retried by the OS.
      }
    }
    return destinationPath;
  }

  Future<String> recordingPath(String sessionId) async {
    await initialize();
    return p.join(_pendingRecordingsDirectory.path, '$sessionId.mp4');
  }

  static String _dateDirectoryName(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _timestamp(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}_'
      '${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}'
      '${value.second.toString().padLeft(2, '0')}';

  static String _sanitizeFileName(String value) {
    final String sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    return sanitized.isEmpty ? '未识别面单' : sanitized;
  }

  Future<List<RecordingSession>> addSession(RecordingSession session) async {
    return addSessions(<RecordingSession>[session]);
  }

  Future<List<RecordingSession>> addSessions(
    List<RecordingSession> newSessions,
  ) => _serializeSessionMutation(() async {
    final List<RecordingSession> sessions = await _loadSessionsUnlocked(
      includeMissingFiles: true,
    );
    sessions.addAll(newSessions);
    sessions.sort(
      (RecordingSession a, RecordingSession b) =>
          b.startedAt.compareTo(a.startedAt),
    );
    await _writeSessions(sessions);
    return sessions;
  });

  Future<List<RecordingSession>> updateSession(
    RecordingSession updatedSession,
  ) => _serializeSessionMutation(() async {
    final List<RecordingSession> sessions = await _loadSessionsUnlocked(
      includeMissingFiles: true,
    );
    final int index = sessions.indexWhere(
      (RecordingSession item) => item.id == updatedSession.id,
    );
    if (index < 0) {
      throw StateError('找不到要更新的录像片段');
    }
    sessions[index] = updatedSession;
    sessions.sort(
      (RecordingSession a, RecordingSession b) =>
          b.startedAt.compareTo(a.startedAt),
    );
    await _writeSessions(sessions);
    return sessions;
  });

  Future<List<RecordingSession>> deleteSessions(
    Set<String> sessionIds,
  ) => _serializeSessionMutation(() async {
    if (sessionIds.isEmpty) {
      return _loadSessionsUnlocked(includeMissingFiles: true);
    }
    final List<RecordingSession> sessions = await _loadSessionsUnlocked(
      includeMissingFiles: true,
    );
    final List<RecordingSession> removed = sessions
        .where((RecordingSession item) => sessionIds.contains(item.id))
        .toList(growable: false);
    final List<RecordingSession> remaining = sessions
        .where((RecordingSession item) => !sessionIds.contains(item.id))
        .toList(growable: false);
    await _writeSessions(remaining);

    final Set<String> retainedPaths = remaining
        .map((RecordingSession item) => p.normalize(item.filePath))
        .toSet();
    for (final String filePath
        in removed
            .map((RecordingSession item) => p.normalize(item.filePath))
            .toSet()) {
      if (retainedPaths.contains(filePath) ||
          !p.isWithin(_recordingsDirectory.path, filePath)) {
        continue;
      }
      final File file = File(filePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } on FileSystemException {
          // The record is already removed; an orphan file is safer than data loss.
        }
      }
    }
    return remaining;
  });

  Future<void> deleteFileIfUnreferenced(String filePath) =>
      _serializeSessionMutation(() async {
        await initialize();
        final String normalizedPath = p.normalize(filePath);
        final List<RecordingSession> sessions = await _loadSessionsUnlocked(
          includeMissingFiles: true,
        );
        if (sessions.any(
              (RecordingSession session) =>
                  p.normalize(session.filePath) == normalizedPath,
            ) ||
            !p.isWithin(_recordingsDirectory.path, normalizedPath)) {
          return;
        }
        final File file = File(normalizedPath);
        if (!await file.exists()) return;
        try {
          await file.delete();
          developer.log(
            '已清理完成水印替换的旧录像：$normalizedPath',
            name: 'PackingProof.VideoCleanup',
          );
        } on FileSystemException {
          // Keeping an unreferenced source is safer than removing a newer file.
        }
      });

  Future<WorkMode> loadWorkMode() async {
    return (await loadSettings()).workMode;
  }

  Future<AppSettings> loadSettings() =>
      _serializeSettingsMutation(_loadSettingsUnlocked);

  Future<AppSettings> _loadSettingsUnlocked() async {
    await initialize();
    final File backupFile = File('${_settingsFile.path}.bak');
    if (!await _settingsFile.exists() && await backupFile.exists()) {
      await backupFile.rename(_settingsFile.path);
    }
    if (!await _settingsFile.exists()) {
      return const AppSettings();
    }
    try {
      return await _readSettingsFile();
    } on Object {
      await _archiveCorruptSettings();
      if (await backupFile.exists()) {
        await backupFile.rename(_settingsFile.path);
        try {
          return await _readSettingsFile();
        } on Object {
          await _archiveCorruptSettings();
        }
      }
      return const AppSettings(
        unbackedRetention: UnbackedRetentionPolicy.keepForever,
        backedRetention: BackedRetentionPolicy.keepForever,
      );
    }
  }

  Future<AppSettings> _readSettingsFile() async {
    final Object? decoded = jsonDecode(await _settingsFile.readAsString());
    final Map<String, Object?> values = Map<String, Object?>.from(
      decoded! as Map<Object?, Object?>,
    );
    return AppSettings.fromJson(values);
  }

  Future<void> _archiveCorruptSettings() async {
    if (!await _settingsFile.exists()) return;
    final String backupName =
        'settings-corrupt-${DateTime.now().microsecondsSinceEpoch}.json';
    await _settingsFile.rename(p.join(_rootDirectory!.path, backupName));
  }

  Future<void> saveWorkMode(WorkMode mode) =>
      _updateSettings((AppSettings value) => value.copyWith(workMode: mode));

  Future<void> saveSpeechEnabled(bool enabled) => _updateSettings(
    (AppSettings value) => value.copyWith(speechEnabled: enabled),
  );

  Future<void> saveOrderSpeechEnabled(bool enabled) => _updateSettings(
    (AppSettings value) => value.copyWith(orderSpeechEnabled: enabled),
  );

  Future<void> saveMaxVolumeEnabled(bool enabled) => _updateSettings(
    (AppSettings value) => value.copyWith(maxVolumeEnabled: enabled),
  );

  Future<List<RecordingSession>> pruneMissingSessions({
    Set<String> retainedMissingPaths = const <String>{},
  }) => _serializeSessionMutation(() async {
    final List<RecordingSession> sessions =
        (await _loadSessionsUnlocked(includeMissingFiles: true))
            .where((RecordingSession session) {
              return File(session.filePath).existsSync() ||
                  retainedMissingPaths.contains(p.normalize(session.filePath));
            })
            .toList(growable: false);
    await _writeSessions(sessions);
    return sessions;
  });

  Future<void> saveStartupNoticeVersion(int version) => _updateSettings(
    (AppSettings value) => value.copyWith(startupNoticeVersion: version),
  );

  Future<void> saveLanBackupAutoEnabled(bool enabled) => _updateSettings(
    (AppSettings value) => value.copyWith(lanBackupAutoEnabled: enabled),
  );

  Future<void> saveHiddenRemoteRecordingIds(Set<int> ids) => _updateSettings(
    (AppSettings value) => value.copyWith(hiddenRemoteRecordingIds: ids),
  );

  Future<void> saveBackupRetention({
    required UnbackedRetentionPolicy unbacked,
    required BackedRetentionPolicy backed,
  }) => _updateSettings(
    (AppSettings value) =>
        value.copyWith(unbackedRetention: unbacked, backedRetention: backed),
  );

  Future<void> saveSettings(AppSettings settings) =>
      _serializeSettingsMutation(() => _writeSettingsUnlocked(settings));

  Future<void> _updateSettings(
    AppSettings Function(AppSettings value) update,
  ) => _serializeSettingsMutation(() async {
    final AppSettings settings = await _loadSettingsUnlocked();
    await _writeSettingsUnlocked(update(settings));
  });

  Future<void> _writeSettingsUnlocked(AppSettings settings) async {
    await initialize();
    final String contents = const JsonEncoder.withIndent(
      '  ',
    ).convert(settings.toJson());
    final File tempFile = File('${_settingsFile.path}.tmp');
    final File backupFile = File('${_settingsFile.path}.bak');
    await tempFile.writeAsString(contents, flush: true);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    final bool hadSettings = await _settingsFile.exists();
    if (hadSettings) {
      await _settingsFile.rename(backupFile.path);
    }
    try {
      await tempFile.rename(_settingsFile.path);
    } on Object {
      if (hadSettings &&
          !await _settingsFile.exists() &&
          await backupFile.exists()) {
        await backupFile.rename(_settingsFile.path);
      }
      rethrow;
    }
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
  }

  Future<void> _writeSessions(List<RecordingSession> sessions) async {
    await initialize();
    final String contents = const JsonEncoder.withIndent(
      '  ',
    ).convert(sessions.map((RecordingSession item) => item.toJson()).toList());
    final File tempFile = File('${_indexFile.path}.tmp');
    final File backupFile = File('${_indexFile.path}.bak');
    await tempFile.writeAsString(contents, flush: true);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    final bool hadIndex = await _indexFile.exists();
    if (hadIndex) {
      await _indexFile.rename(backupFile.path);
    }
    try {
      await tempFile.rename(_indexFile.path);
    } on Object {
      if (hadIndex && !await _indexFile.exists() && await backupFile.exists()) {
        await backupFile.rename(_indexFile.path);
      }
      rethrow;
    }
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
  }

  Future<T> _serializeSessionMutation<T>(Future<T> Function() action) {
    final Completer<T> result = Completer<T>();
    _sessionMutationTail = _sessionMutationTail.catchError((Object _) {}).then((
      _,
    ) async {
      try {
        result.complete(await action());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<T> _serializeSettingsMutation<T>(Future<T> Function() action) {
    final Completer<T> result = Completer<T>();
    _settingsMutationTail = _settingsMutationTail
        .catchError((Object _) {})
        .then((_) async {
          try {
            result.complete(await action());
          } on Object catch (error, stackTrace) {
            result.completeError(error, stackTrace);
          }
        });
    return result.future;
  }
}
