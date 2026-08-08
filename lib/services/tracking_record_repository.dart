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
/// 直接从项目原有 recordings.db 的 recording_sessions 表读取数据，
/// 不新建独立数据库，避免数据不一致。
class TrackingRecordRepository {
  static const int pageSize = 10;

  /// 分页查询有 tracking_number 的录像记录，按识别时间倒序。
  ///
  /// [page] 从 1 开始；[start] / [end] 为可选日期范围（含当天）。
  /// 返回当前页记录与总条数。
  Future<(List<TrackingRecord>, int)> queryPage({
    required int page,
    DateTime? start,
    DateTime? end,
  }) async {
    final String dbPath = p.join(
      (await getApplicationDocumentsDirectory()).path,
      'recordings.db',
    );
    Database db;
    try {
      db = await openDatabase(dbPath);
    } on Object {
      return (const <TrackingRecord>[], 0);
    }
    try {
      final List<String> where = <String>["tracking_number != ''"];

      // 排除标记行。
      where.add("tracking_number != '__IMPORTED_FLAG__'");

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
    } finally {
      await db.close();
    }
  }
}
