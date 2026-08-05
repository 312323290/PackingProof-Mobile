import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../models/recording_session.dart';

class LocalRecordingPage {
  const LocalRecordingPage({
    required this.data,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<RecordingSession> data;
  final int page;
  final int pageSize;
  final int total;

  int get pageCount => total <= 0 ? 0 : (total + pageSize - 1) ~/ pageSize;
}

class RecordingDeleteLog {
  const RecordingDeleteLog({
    required this.filePath,
    required this.sessionId,
    required this.trackingNumber,
    required this.fileSizeBytes,
    required this.deletedAt,
    required this.reason,
  });

  final String filePath;
  final String sessionId;
  final String trackingNumber;
  final int fileSizeBytes;
  final DateTime deletedAt;
  final String reason;
}

class RecordingDatabase {
  RecordingDatabase({required this.path});

  final String path;
  Database? _database;

  Future<Database> get _db async => _database ??= await openDatabase(
    path,
    version: 1,
    onConfigure: (Database db) async {
      // Android treats journal_mode as a result-returning PRAGMA and rejects
      // execute(); sqflite's helper falls back to rawQuery on that platform.
      await db.setJournalMode('WAL');
      await db.execute('PRAGMA synchronous=NORMAL');
      await db.execute('PRAGMA foreign_keys=ON');
    },
    onCreate: (Database db, int version) async {
      await db.execute('''
        CREATE TABLE recording_sessions (
          id TEXT PRIMARY KEY,
          file_path TEXT NOT NULL,
          started_at INTEGER NOT NULL,
          ended_at INTEGER NOT NULL,
          tracking_number TEXT NOT NULL DEFAULT '',
          order_id TEXT NOT NULL DEFAULT '',
          search_text TEXT NOT NULL DEFAULT '',
          payload_json TEXT NOT NULL,
          file_size_bytes INTEGER NOT NULL DEFAULT 0,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          deleted_at INTEGER,
          delete_reason TEXT NOT NULL DEFAULT '',
          missing_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE recording_delete_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_path TEXT NOT NULL,
          session_id TEXT NOT NULL DEFAULT '',
          tracking_number TEXT NOT NULL DEFAULT '',
          file_size_bytes INTEGER NOT NULL DEFAULT 0,
          deleted_at INTEGER NOT NULL,
          reason TEXT NOT NULL DEFAULT ''
        )
      ''');
      await db.execute('''
        CREATE TABLE recording_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_recording_active_time '
        'ON recording_sessions(is_deleted, started_at DESC, id DESC)',
      );
      await db.execute(
        'CREATE INDEX idx_recording_file_path '
        'ON recording_sessions(file_path)',
      );
      await db.execute(
        'CREATE INDEX idx_recording_tracking '
        'ON recording_sessions(tracking_number)',
      );
      await db.execute(
        'CREATE INDEX idx_recording_order '
        'ON recording_sessions(order_id)',
      );
    },
  );

  Future<void> initialize() async {
    await _db;
  }

  Future<void> close() async {
    final Database? database = _database;
    _database = null;
    await database?.close();
  }

  Future<void> migrateLegacyIndex(File indexFile) async {
    final Database db = await _db;
    final List<Map<String, Object?>> migrated = await db.query(
      'recording_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>['legacy_sessions_migrated'],
      limit: 1,
    );
    if (migrated.isNotEmpty) return;

    final File backupFile = File('${indexFile.path}.bak');
    File? source;
    List<RecordingSession> sessions = <RecordingSession>[];
    for (final File candidate in <File>[indexFile, backupFile]) {
      if (!await candidate.exists()) continue;
      try {
        sessions = _decodeLegacySessions(await candidate.readAsString());
        source = candidate;
        break;
      } on Object {
        await _archiveCorruptLegacyIndex(candidate, indexFile);
      }
    }

    await db.transaction((Transaction txn) async {
      for (final RecordingSession session in sessions) {
        await txn.insert(
          'recording_sessions',
          await _sessionRow(session),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await txn.insert('recording_metadata', <String, Object?>{
        'key': 'legacy_sessions_migrated',
        'value': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    if (source != null && await source.exists()) {
      final String migratedPath = '${indexFile.path}.migrated';
      final File migratedFile = File(migratedPath);
      if (!await migratedFile.exists()) {
        await source.copy(migratedPath);
      }
    }
  }

  static List<RecordingSession> _decodeLegacySessions(String contents) {
    final List<Object?> values = jsonDecode(contents) as List<Object?>;
    return values
        .map(
          (Object? value) => RecordingSession.fromJson(
            Map<String, Object?>.from(value! as Map<Object?, Object?>),
          ),
        )
        .toList(growable: false);
  }

  static Future<void> _archiveCorruptLegacyIndex(
    File source,
    File indexFile,
  ) async {
    final String sourceLabel = source.path == indexFile.path ? '' : '-backup';
    final String archivePath =
        '${indexFile.parent.path}${Platform.pathSeparator}'
        'sessions$sourceLabel-corrupt-'
        '${DateTime.now().microsecondsSinceEpoch}.json';
    await source.copy(archivePath);
  }

  Future<List<RecordingSession>> loadActiveSessions() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'recording_sessions',
      columns: <String>['payload_json'],
      where: 'is_deleted = 0',
      orderBy: 'started_at DESC, id DESC',
    );
    return rows.map(_sessionFromRow).toList(growable: false);
  }

  Future<LocalRecordingPage> queryActiveSessions({
    required int page,
    required int pageSize,
    String keyword = '',
  }) async {
    final Database db = await _db;
    final int normalizedPage = page < 1 ? 1 : page;
    final int normalizedSize = pageSize.clamp(1, 100);
    final String query = keyword.trim().toLowerCase();
    final String where = query.isEmpty
        ? 'is_deleted = 0'
        : 'is_deleted = 0 AND search_text LIKE ?';
    final List<Object?> args = query.isEmpty
        ? <Object?>[]
        : <Object?>['%$query%'];
    final List<Map<String, Object?>> countRows = await db.rawQuery(
      'SELECT COUNT(1) AS total FROM recording_sessions WHERE $where',
      args,
    );
    final int total = Sqflite.firstIntValue(countRows) ?? 0;
    final List<Map<String, Object?>> rows = await db.query(
      'recording_sessions',
      columns: <String>['payload_json'],
      where: where,
      whereArgs: args,
      orderBy: 'started_at DESC, id DESC',
      limit: normalizedSize,
      offset: (normalizedPage - 1) * normalizedSize,
    );
    return LocalRecordingPage(
      data: rows.map(_sessionFromRow).toList(growable: false),
      page: normalizedPage,
      pageSize: normalizedSize,
      total: total,
    );
  }

  Future<bool> hasRecentTrackingNumber(
    String trackingNumber, {
    Duration lookback = const Duration(days: 30),
  }) async {
    final String normalized = trackingNumber.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    final Database db = await _db;
    final int since = DateTime.now().subtract(lookback).millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(1) FROM recording_sessions '
      'WHERE is_deleted = 0 AND tracking_number = ? AND started_at >= ?',
      <Object?>[normalized, since],
    );
    return (Sqflite.firstIntValue(rows) ?? 0) > 0;
  }

  Future<List<RecordingSession>> queryBackupBatch({
    required int page,
    required int pageSize,
  }) async {
    final Database db = await _db;
    final int normalizedPage = page < 1 ? 1 : page;
    final int normalizedSize = pageSize.clamp(1, 100);
    final List<Map<String, Object?>> pathRows = await db.rawQuery(
      'SELECT DISTINCT file_path FROM recording_sessions '
      'WHERE is_deleted = 0 ORDER BY file_path '
      'LIMIT ? OFFSET ?',
      <Object?>[normalizedSize, (normalizedPage - 1) * normalizedSize],
    );
    final List<String> paths = pathRows
        .map((Map<String, Object?> row) => row['file_path']! as String)
        .toList(growable: false);
    if (paths.isEmpty) return <RecordingSession>[];
    final String placeholders = List<String>.filled(
      paths.length,
      '?',
    ).join(',');
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT payload_json FROM recording_sessions '
      'WHERE is_deleted = 0 AND file_path IN ($placeholders) '
      'ORDER BY file_path, started_at, id',
      paths,
    );
    return rows.map(_sessionFromRow).toList(growable: false);
  }

  Future<void> upsertSessions(List<RecordingSession> sessions) async {
    if (sessions.isEmpty) return;
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      for (final RecordingSession session in sessions) {
        final Map<String, Object?> row = await _sessionRow(session);
        final List<Map<String, Object?>> existing = await txn.query(
          'recording_sessions',
          columns: <String>['created_at'],
          where: 'id = ?',
          whereArgs: <Object?>[session.id],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          row['created_at'] = existing.single['created_at'];
        }
        await txn.insert(
          'recording_sessions',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<RecordingSession>> findActiveByIds(Set<String> ids) async {
    if (ids.isEmpty) return <RecordingSession>[];
    final Database db = await _db;
    final String placeholders = List<String>.filled(ids.length, '?').join(',');
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT payload_json FROM recording_sessions '
      'WHERE is_deleted = 0 AND id IN ($placeholders)',
      ids.toList(growable: false),
    );
    return rows.map(_sessionFromRow).toList(growable: false);
  }

  Future<void> markDeleted(
    List<RecordingSession> sessions, {
    required String reason,
  }) async {
    if (sessions.isEmpty) return;
    final Database db = await _db;
    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((Transaction txn) async {
      for (final RecordingSession session in sessions) {
        final File file = File(session.filePath);
        final int fileSize = await file.exists() ? await file.length() : 0;
        await txn.update(
          'recording_sessions',
          <String, Object?>{
            'is_deleted': 1,
            'deleted_at': now,
            'delete_reason': reason,
            'updated_at': now,
          },
          where: 'id = ? AND is_deleted = 0',
          whereArgs: <Object?>[session.id],
        );
        await txn.insert('recording_delete_logs', <String, Object?>{
          'file_path': session.filePath,
          'session_id': session.id,
          'tracking_number': session.displayCode,
          'file_size_bytes': fileSize,
          'deleted_at': now,
          'reason': reason,
        });
      }
    });
  }

  Future<void> recordAutomaticCleanup({
    required String eventId,
    required String filePath,
    required int fileSizeBytes,
    required DateTime deletedAt,
    required String reason,
  }) async {
    final String normalizedEventId = eventId.trim();
    if (normalizedEventId.isEmpty || filePath.trim().isEmpty) return;
    final Database db = await _db;
    final String metadataKey = 'cleanup_audit:$normalizedEventId';
    await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> audited = await txn.query(
        'recording_metadata',
        columns: <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>[metadataKey],
        limit: 1,
      );
      if (audited.isNotEmpty) return;
      final List<Map<String, Object?>> rows = await txn.query(
        'recording_sessions',
        columns: <String>['id', 'tracking_number'],
        where: 'is_deleted = 0 AND file_path = ?',
        whereArgs: <Object?>[filePath],
      );
      final int deletedAtMillis = deletedAt.millisecondsSinceEpoch;
      for (final Map<String, Object?> row in rows) {
        await txn.insert('recording_delete_logs', <String, Object?>{
          'file_path': filePath,
          'session_id': row['id']! as String,
          'tracking_number': row['tracking_number']! as String,
          'file_size_bytes': fileSizeBytes < 0 ? 0 : fileSizeBytes,
          'deleted_at': deletedAtMillis,
          'reason': reason,
        });
      }
      await txn.update(
        'recording_sessions',
        <String, Object?>{
          'missing_at': deletedAtMillis,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'is_deleted = 0 AND file_path = ?',
        whereArgs: <Object?>[filePath],
      );
      await txn.insert('recording_metadata', <String, Object?>{
        'key': metadataKey,
        'value': deletedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<int> activeReferenceCount(String filePath) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(1) FROM recording_sessions '
      'WHERE is_deleted = 0 AND file_path = ?',
      <Object?>[filePath],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<void> refreshMissingState({
    Set<String> retainedMissingPaths = const <String>{},
    Map<String, String> resolvedPaths = const <String, String>{},
  }) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'recording_sessions',
      columns: <String>['id', 'file_path', 'missing_at'],
      where: 'is_deleted = 0',
    );
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Batch batch = db.batch();
    for (final Map<String, Object?> row in rows) {
      final String filePath = row['file_path']! as String;
      final String workingPath = resolvedPaths[row['id']] ?? filePath;
      final bool missing = !File(workingPath).existsSync();
      final bool retained =
          retainedMissingPaths.contains(workingPath) ||
          retainedMissingPaths.contains(filePath);
      final Object? current = row['missing_at'];
      final bool pathChanged = workingPath != filePath;
      if (missing && current == null) {
        batch.update(
          'recording_sessions',
          <String, Object?>{
            if (pathChanged) 'file_path': workingPath,
            'missing_at': now,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: <Object?>[row['id']],
        );
      } else if (!missing && current != null) {
        batch.update(
          'recording_sessions',
          <String, Object?>{
            if (pathChanged) 'file_path': workingPath,
            'missing_at': null,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: <Object?>[row['id']],
        );
      } else if (pathChanged) {
        batch.update(
          'recording_sessions',
          <String, Object?>{'file_path': workingPath, 'updated_at': now},
          where: 'id = ?',
          whereArgs: <Object?>[row['id']],
        );
      } else if (missing && retained) {
        // Retained remote history remains active; missing_at records why local
        // playback is unavailable without discarding the audit trail.
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> repairFilePaths(Map<String, String> resolvedPaths) async {
    if (resolvedPaths.isEmpty) return;
    final Database db = await _db;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Batch batch = db.batch();
    resolvedPaths.forEach((String id, String path) {
      batch.update(
        'recording_sessions',
        <String, Object?>{
          'file_path': path,
          'missing_at': null,
          'updated_at': now,
        },
        where: 'id = ? AND file_path != ?',
        whereArgs: <Object?>[id, path],
      );
    });
    await batch.commit(noResult: true);
  }

  Future<List<RecordingDeleteLog>> loadDeleteLogs({int limit = 100}) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'recording_delete_logs',
      orderBy: 'deleted_at DESC, id DESC',
      limit: limit.clamp(1, 1000),
    );
    return rows
        .map(
          (Map<String, Object?> row) => RecordingDeleteLog(
            filePath: row['file_path']! as String,
            sessionId: row['session_id']! as String,
            trackingNumber: row['tracking_number']! as String,
            fileSizeBytes: row['file_size_bytes']! as int,
            deletedAt: DateTime.fromMillisecondsSinceEpoch(
              row['deleted_at']! as int,
            ),
            reason: row['reason']! as String,
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, Object?>> _sessionRow(RecordingSession session) async {
    final File file = File(session.filePath);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final String orderId = session.orderInfo?.orderId ?? '';
    final String searchText = <String>[
      session.displayCode,
      orderId,
      session.orderInfo?.buyerMessage ?? '',
      session.orderInfo?.sellerMemo ?? '',
      session.orderInfo?.productInfo ?? '',
      session.startedAt.toIso8601String(),
    ].join(' ').toLowerCase();
    return <String, Object?>{
      'id': session.id,
      'file_path': session.filePath,
      'started_at': session.startedAt.millisecondsSinceEpoch,
      'ended_at': session.endedAt.millisecondsSinceEpoch,
      'tracking_number': session.displayCode,
      'order_id': orderId,
      'search_text': searchText,
      'payload_json': jsonEncode(session.toJson()),
      'file_size_bytes': await file.exists() ? await file.length() : 0,
      'is_deleted': 0,
      'deleted_at': null,
      'delete_reason': '',
      'missing_at': await file.exists() ? null : now,
      'created_at': now,
      'updated_at': now,
    };
  }

  static RecordingSession _sessionFromRow(Map<String, Object?> row) =>
      RecordingSession.fromJson(
        Map<String, Object?>.from(
          jsonDecode(row['payload_json']! as String) as Map<Object?, Object?>,
        ),
      );
}
