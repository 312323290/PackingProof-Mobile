import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/storage_notice.dart';

void main() {
  test('同一工作期间只保留最高严重级别提醒', () {
    const StorageNoticeState state = StorageNoticeState();
    final StorageNoticeState queued = state
        .queue(
          const StorageNotice(
            severity: StorageNoticeSeverity.warning,
            message: '空间偏低',
          ),
        )
        .queue(
          const StorageNotice(
            severity: StorageNoticeSeverity.stopped,
            message: '录像已停止',
          ),
        )
        .queue(
          const StorageNotice(
            severity: StorageNoticeSeverity.reclaimed,
            message: '已清理',
          ),
        );

    expect(queued.pending?.severity, StorageNoticeSeverity.stopped);
    expect(queued.pending?.message, '录像已停止');
  });

  test('结束工作后同一天最多返回两次弹窗且不补弹', () {
    StorageNoticeState state = const StorageNoticeState().queue(
      const StorageNotice(
        severity: StorageNoticeSeverity.warning,
        message: '第一次',
      ),
    );
    var result = state.take(DateTime(2026, 7, 23, 10));
    expect(result.notice?.message, '第一次');
    state = result.state.queue(
      const StorageNotice(
        severity: StorageNoticeSeverity.reclaimed,
        message: '第二次',
      ),
    );
    result = state.take(DateTime(2026, 7, 23, 12));
    expect(result.notice?.message, '第二次');
    state = result.state.queue(
      const StorageNotice(
        severity: StorageNoticeSeverity.stopped,
        message: '第三次',
      ),
    );
    result = state.take(DateTime(2026, 7, 23, 14));
    expect(result.notice, isNull);
    expect(result.state.pending, isNull);
  });

  test('跨自然日重置弹窗次数', () {
    final StorageNoticeState state =
        const StorageNoticeState(shownDate: '2026-07-23', shownCount: 2).queue(
          const StorageNotice(
            severity: StorageNoticeSeverity.warning,
            message: '次日提醒',
          ),
        );

    final result = state.take(DateTime(2026, 7, 24, 8));

    expect(result.notice?.message, '次日提醒');
    expect(result.state.shownCount, 1);
    expect(result.state.shownDate, '2026-07-24');
  });

  test('待提醒状态可序列化以支持异常退出恢复', () {
    final StorageNoticeState state = const StorageNoticeState().queue(
      const StorageNotice(
        severity: StorageNoticeSeverity.reclaimed,
        message: '已提前清理',
      ),
    );

    final StorageNoticeState restored = StorageNoticeState.fromJson(
      state.toJson(),
    );

    expect(restored.pending?.severity, StorageNoticeSeverity.reclaimed);
    expect(restored.pending?.message, '已提前清理');
  });
}
