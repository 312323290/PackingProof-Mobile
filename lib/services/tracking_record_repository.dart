import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/tracking_record.dart';

/// 扫描记录数据库。
///
/// 独立于项目原有 recordings.db（recording_sessions），专门保存
/// 改造后识别出的快递单号记录，支持分页查询与日期筛选。
class TrackingRecordRepository {
  TrackingRecordRepository({this._database});

  static const String databaseName = 'tracking_records.db';
  static const int pageSize = 10;

  Database? _database;
  bool _initialized = false;

  Future<Database> get _db async {
    if (_database == null || !_initialized) {
      await initialize();
    }
    return _database!;
  }

  /// 打开（或创建）数据库并建表，幂等。
  Future<void> initialize() async {
    if (_initialized && _database != null) {
      return;
    }
    _database ??= await openDatabase(
      p.join(await getDatabasesPath(), databaseName),
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
CREATE TABLE tracking_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tracking_number TEXT NOT NULL,
  recognized_at INTEGER NOT NULL,
  video_file_path TEXT DEFAULT '',
  created_at INTEGER NOT NULL
)
''');
        await db.execute(
          'CREATE INDEX idx_tracking_records_number '
          'ON tracking_records(tracking_number)',
        );
        await db.execute(
          'CREATE INDEX idx_tracking_records_time '
          'ON tracking_records(recognized_at)',
        );
      },
    );
    _initialized = true;
  }

  /// 插入一条识别记录，返回新记录 id。
  Future<int> insert(TrackingRecord record) async {
    final Database db = await _db;
    return db.insert(
      'tracking_records',
      {
        'tracking_number': record.trackingNumber,
        'recognized_at': record.recognizedAt.millisecondsSinceEpoch,
        'video_file_path': record.videoFilePath,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// 分页查询记录，按识别时间倒序。
  ///
  /// [page] 从 1 开始；[start] / [end] 为可选日期范围（含当天）。
  /// 返回当前页记录与总条数。
  Future<(List<TrackingRecord>, int)> queryPage({
    required int page,
    DateTime? start,
    DateTime? end,
  }) async {
    final Database db = await _db;
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];
    if (start != null) {
      where.add('recognized_at >= ?');
      args.add(start.millisecondsSinceEpoch);
    }
    if (end != null) {
      where.add('recognized_at <= ?');
      args.add(
        DateTime(end.year, end.month, end.day, 23, 59, 59, 999)
            .millisecondsSinceEpoch,
      );
    }
    final String whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final List<Map<String, Object?>> rows = await db.query(
      'tracking_records',
      where: where.isEmpty ? null : whereClause,
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'recognized_at DESC, id DESC',
      limit: pageSize,
      offset: (page - 1) * pageSize,
    );
    final int total = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM tracking_records $whereClause',
            args,
          ),
        ) ??
        0;
    return (
      rows.map(TrackingRecord.fromMap).toList(),
      total,
    );
  }

  /// 关闭数据库连接。
  Future<void> dispose() async {
    final Database? database = _database;
    if (database != null) {
      await database.close();
      _database = null;
      _initialized = false;
    }
  }
}