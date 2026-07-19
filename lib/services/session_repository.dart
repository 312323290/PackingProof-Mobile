import 'dart:convert';
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
  late File _indexFile;
  late File _settingsFile;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _rootDirectory ??= await getApplicationDocumentsDirectory();
    _recordingsDirectory = Directory(
      p.join(_rootDirectory!.path, 'recordings'),
    );
    await _recordingsDirectory.create(recursive: true);
    _indexFile = File(p.join(_rootDirectory!.path, 'sessions.json'));
    _settingsFile = File(p.join(_rootDirectory!.path, 'settings.json'));
    _initialized = true;
  }

  Future<List<RecordingSession>> loadSessions({
    bool includeMissingFiles = false,
  }) async {
    await initialize();
    if (!await _indexFile.exists()) {
      return <RecordingSession>[];
    }

    try {
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
    } on Object {
      final String backupName =
          'sessions-corrupt-${DateTime.now().millisecondsSinceEpoch}.json';
      await _indexFile.rename(p.join(_rootDirectory!.path, backupName));
      return <RecordingSession>[];
    }
  }

  Future<String> persistVideo(String sourcePath, String sessionId) async {
    await initialize();
    final String destinationPath = p.join(
      _recordingsDirectory.path,
      '$sessionId.mp4',
    );
    final File source = File(sourcePath);
    if (p.normalize(source.path) == p.normalize(destinationPath)) {
      return destinationPath;
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
    return p.join(_recordingsDirectory.path, '$sessionId.mp4');
  }

  Future<List<RecordingSession>> addSession(RecordingSession session) async {
    return addSessions(<RecordingSession>[session]);
  }

  Future<List<RecordingSession>> addSessions(
    List<RecordingSession> newSessions,
  ) async {
    final List<RecordingSession> sessions = await loadSessions(
      includeMissingFiles: true,
    );
    sessions.addAll(newSessions);
    sessions.sort(
      (RecordingSession a, RecordingSession b) =>
          b.startedAt.compareTo(a.startedAt),
    );
    await _writeSessions(sessions);
    return sessions;
  }

  Future<List<RecordingSession>> updateSession(
    RecordingSession updatedSession,
  ) async {
    final List<RecordingSession> sessions = await loadSessions(
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
  }

  Future<List<RecordingSession>> deleteSessions(Set<String> sessionIds) async {
    if (sessionIds.isEmpty) {
      return loadSessions(includeMissingFiles: true);
    }
    final List<RecordingSession> sessions = await loadSessions(
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
  }

  Future<WorkMode> loadWorkMode() async {
    return (await loadSettings()).workMode;
  }

  Future<AppSettings> loadSettings() async {
    await initialize();
    if (!await _settingsFile.exists()) {
      return const AppSettings();
    }
    try {
      final Object? decoded = jsonDecode(await _settingsFile.readAsString());
      final Map<String, Object?> values = Map<String, Object?>.from(
        decoded! as Map<Object?, Object?>,
      );
      return AppSettings.fromJson(values);
    } on Object {
      return const AppSettings();
    }
  }

  Future<void> saveWorkMode(WorkMode mode) async {
    final AppSettings settings = await loadSettings();
    await saveSettings(settings.copyWith(workMode: mode));
  }

  Future<void> saveSpeechEnabled(bool enabled) async {
    final AppSettings settings = await loadSettings();
    await saveSettings(settings.copyWith(speechEnabled: enabled));
  }

  Future<void> saveMaxVolumeEnabled(bool enabled) async {
    final AppSettings settings = await loadSettings();
    await saveSettings(settings.copyWith(maxVolumeEnabled: enabled));
  }

  Future<List<RecordingSession>> pruneMissingSessions({
    Set<String> retainedMissingPaths = const <String>{},
  }) async {
    final List<RecordingSession> sessions =
        (await loadSessions(includeMissingFiles: true))
            .where((RecordingSession session) {
              return File(session.filePath).existsSync() ||
                  retainedMissingPaths.contains(p.normalize(session.filePath));
            })
            .toList(growable: false);
    await _writeSessions(sessions);
    return sessions;
  }

  Future<void> saveStandaloneNoticeDismissed(bool dismissed) async {
    final AppSettings settings = await loadSettings();
    await saveSettings(settings.copyWith(standaloneNoticeDismissed: dismissed));
  }

  Future<void> saveLanBackupAutoEnabled(bool enabled) async {
    final AppSettings settings = await loadSettings();
    await saveSettings(settings.copyWith(lanBackupAutoEnabled: enabled));
  }

  Future<void> saveBackupRetention({
    required UnbackedRetentionPolicy unbacked,
    required BackedRetentionPolicy backed,
  }) async {
    final AppSettings settings = await loadSettings();
    await saveSettings(
      settings.copyWith(unbackedRetention: unbacked, backedRetention: backed),
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    await initialize();
    final String contents = const JsonEncoder.withIndent(
      '  ',
    ).convert(settings.toJson());
    final File tempFile = File('${_settingsFile.path}.tmp');
    await tempFile.writeAsString(contents, flush: true);
    if (await _settingsFile.exists()) {
      await _settingsFile.delete();
    }
    await tempFile.rename(_settingsFile.path);
  }

  Future<void> _writeSessions(List<RecordingSession> sessions) async {
    await initialize();
    final String contents = const JsonEncoder.withIndent(
      '  ',
    ).convert(sessions.map((RecordingSession item) => item.toJson()).toList());
    final File tempFile = File('${_indexFile.path}.tmp');
    await tempFile.writeAsString(contents, flush: true);
    if (await _indexFile.exists()) {
      await _indexFile.delete();
    }
    await tempFile.rename(_indexFile.path);
  }
}
