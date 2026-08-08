import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 扫描记录数据类。
class TrackingRecord {
  final String trackingNumber;
  final DateTime recognizedAt;

  const TrackingRecord({
    required this.trackingNumber,
    required this.recognizedAt,
  });

  factory TrackingRecord.fromMap(Map<String, dynamic> map) => TrackingRecord(
        trackingNumber: map['tracking_number'] as String? ?? '',
        recognizedAt: map['started_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int)
            : DateTime.now(),
      );
}

/// 扫描记录仓库。
///
/// 直接从项目原有 recordings.db 的 recording_sessions 表读取数据。
/// 注意：使用 sqflite.openDatabase（单例），绝不能 close()，
/// 否则会关闭原有 SessionRepository 正在使用的连接。
class TrackingRecordRepository {
  static const int pageSize = 10;

  Database? _cachedDb;

  Future<Database> _getDb() async {
    if (_cachedDb != null) return _cachedDb!;
    final String dbPath = p.join(
      (await getApplicationDocumentsDirectory()).path,
      'recordings.db',
    );
    _cachedDb = await openDatabase(dbPath);
    return _cachedDb!;
  }

  /// 分页查询有 tracking_number 的录像记录，按识别时间倒序。
  ///
  /// [page] 从 1 开始；[start] / [end] 为可选日期范围（含当天）。
  /// 返回当前页记录与总条数。
  Future<(List<TrackingRecord>, int)> queryPage({
    required int page,
    DateTime? start,
    DateTime? end,
  }) async {
    Database db;
    try {
      db = await _getDb();
    } on Object {
      return (const <TrackingRecord>[], 0);
    }
    try {
      final List<String> where = <String>["tracking_number != ''"];
      final List<Object?> args = <Object?>[];
      if (start != null) {
        where.add('started_at >= ?');
        args.add(start.millisecondsSinceEpoch);
      }
      if (end != null) {
        where.add('started_at <= ?');
        args.add(
          DateTime(end.year, end.month, end.day, 23, 59, 59, 999)
              .millisecondsSinceEpoch,
        );
      }
      final String whereClause = 'WHERE ${where.join(' AND ')}';

      final List<Map<String, Object?>> rows = await db.query(
        'recording_sessions',
        columns: const <String>['tracking_number', 'started_at'],
        where: where.isEmpty ? null : whereClause,
        whereArgs: where.isEmpty ? null : args,
        orderBy: 'started_at DESC, id DESC',
        limit: pageSize,
        offset: (page - 1) * pageSize,
      );
      final int total = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM recording_sessions $whereClause',
              args,
            ),
          ) ??
          0;
      return (
        rows.map(TrackingRecord.fromMap).toList(),
        total,
      );
    } on Object {
      return (const <TrackingRecord>[], 0);
    }
  }
}