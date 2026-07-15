import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/recording_session.dart';

class SessionRepository {
  SessionRepository({Directory? rootDirectory}) : this._(rootDirectory);

  SessionRepository._(this._rootDirectory);

  Directory? _rootDirectory;
  late Directory _recordingsDirectory;
  late File _indexFile;
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
    _initialized = true;
  }

  Future<List<RecordingSession>> loadSessions() async {
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
            (RecordingSession session) => File(session.filePath).existsSync(),
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
    await source.copy(destinationPath);
    if (p.normalize(source.path) != p.normalize(destinationPath)) {
      try {
        await source.delete();
      } on FileSystemException {
        // The copied recording is already safe; temp cleanup can be retried by the OS.
      }
    }
    return destinationPath;
  }

  Future<List<RecordingSession>> addSession(RecordingSession session) async {
    final List<RecordingSession> sessions = await loadSessions();
    sessions.insert(0, session);
    await _writeSessions(sessions);
    return sessions;
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
