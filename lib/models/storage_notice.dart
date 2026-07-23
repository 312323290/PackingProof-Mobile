enum StorageNoticeSeverity { warning, reclaimed, stopped }

class StorageNotice {
  const StorageNotice({required this.severity, required this.message});

  factory StorageNotice.fromJson(Map<String, Object?> json) {
    return StorageNotice(
      severity: StorageNoticeSeverity.values.firstWhere(
        (StorageNoticeSeverity value) => value.name == json['severity'],
        orElse: () => StorageNoticeSeverity.warning,
      ),
      message: '${json['message'] ?? ''}'.trim(),
    );
  }

  final StorageNoticeSeverity severity;
  final String message;

  int get priority => severity.index;

  Map<String, Object?> toJson() => <String, Object?>{
    'severity': severity.name,
    'message': message,
  };
}

class StorageNoticeState {
  const StorageNoticeState({
    this.pending,
    this.shownDate = '',
    this.shownCount = 0,
  });

  factory StorageNoticeState.fromJson(Object? value) {
    if (value is! Map) return const StorageNoticeState();
    final Map<String, Object?> json = Map<String, Object?>.from(
      value.cast<Object?, Object?>(),
    );
    final Object? pending = json['pending'];
    return StorageNoticeState(
      pending: pending is Map
          ? StorageNotice.fromJson(
              Map<String, Object?>.from(pending.cast<Object?, Object?>()),
            )
          : null,
      shownDate: '${json['shownDate'] ?? ''}',
      shownCount: (json['shownCount'] as num?)?.toInt() ?? 0,
    );
  }

  final StorageNotice? pending;
  final String shownDate;
  final int shownCount;

  StorageNoticeState queue(StorageNotice notice) {
    final StorageNotice? current = pending;
    return StorageNoticeState(
      pending: current == null || notice.priority >= current.priority
          ? notice
          : current,
      shownDate: shownDate,
      shownCount: shownCount,
    );
  }

  ({StorageNotice? notice, StorageNoticeState state}) take(DateTime now) {
    final String today = _dateKey(now);
    final int todayCount = shownDate == today ? shownCount : 0;
    if (pending == null) {
      return (
        notice: null,
        state: StorageNoticeState(shownDate: today, shownCount: todayCount),
      );
    }
    if (todayCount >= 2) {
      return (
        notice: null,
        state: StorageNoticeState(shownDate: today, shownCount: todayCount),
      );
    }
    return (
      notice: pending,
      state: StorageNoticeState(shownDate: today, shownCount: todayCount + 1),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'pending': pending?.toJson(),
    'shownDate': shownDate,
    'shownCount': shownCount,
  };

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
