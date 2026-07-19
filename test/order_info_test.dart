import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/order_info.dart';
import 'package:packing_proof_mobile/models/recording_session.dart';

void main() {
  test('订单摘要优先显示退款并生成默认播报内容', () {
    final OrderInfo info = OrderInfo.fromMap(<Object?, Object?>{
      'trackingNumber': ' track-1 ',
      'buyerMessage': '请放门口',
      'sellerMemo': '核对颜色',
      'productInfo': '商品 A',
      'hasRefund': true,
      'refundStatus': '退款处理中',
    });

    expect(info.trackingNumber, 'TRACK-1');
    expect(info.summary, '退款：退款处理中');
    expect(info.speechMessages.map((value) => value.text), <String>[
      '退款提醒，退款处理中',
      '买家留言，请放门口',
      '卖家备注，核对颜色',
    ]);
    expect(info.speechMessages.first.warning, isTrue);
    expect(info.speechMessages.any((value) => value.text.contains('商品 A')), isFalse);
  });

  test('录像索引持久化订单快照', () {
    final RecordingSession session = RecordingSession(
      id: 'session-1',
      filePath: '/tmp/video.mp4',
      startedAt: DateTime(2026, 7, 20, 10),
      endedAt: DateTime(2026, 7, 20, 10, 0, 5),
      markers: const [],
      orderInfo: const OrderInfo(
        trackingNumber: 'TRACK-1',
        orderId: 'ORDER-1',
        buyerMessage: '留言',
      ),
    );

    final RecordingSession restored = RecordingSession.fromJson(session.toJson());
    expect(restored.orderInfo?.orderId, 'ORDER-1');
    expect(restored.orderInfo?.buyerMessage, '留言');
  });
}
