class OrderInfo {
  const OrderInfo({
    required this.trackingNumber,
    this.orderId = '',
    this.buyerMessage = '',
    this.sellerMemo = '',
    this.productInfo = '',
    this.hasRefund = false,
    this.isPrintedRefund = false,
    this.refundStatus = '',
    this.refundProductInfo = '',
    this.pushTime,
    this.isTest = false,
  });

  factory OrderInfo.fromMap(Map<Object?, Object?> value) => OrderInfo(
    trackingNumber: '${value['trackingNumber'] ?? ''}'.trim().toUpperCase(),
    orderId: '${value['orderId'] ?? ''}',
    buyerMessage: '${value['buyerMessage'] ?? ''}',
    sellerMemo: '${value['sellerMemo'] ?? ''}',
    productInfo: '${value['productInfo'] ?? ''}',
    hasRefund: value['hasRefund'] == true,
    isPrintedRefund: value['isPrintedRefund'] == true,
    refundStatus: '${value['refundStatus'] ?? ''}',
    refundProductInfo: '${value['refundProductInfo'] ?? ''}',
    pushTime: value['pushTimeMilliseconds'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (value['pushTimeMilliseconds']! as num).toInt(),
          )
        : DateTime.tryParse('${value['pushTime'] ?? ''}'),
    isTest: value['isTest'] == true,
  );

  final String trackingNumber;
  final String orderId;
  final String buyerMessage;
  final String sellerMemo;
  final String productInfo;
  final bool hasRefund;
  final bool isPrintedRefund;
  final String refundStatus;
  final String refundProductInfo;
  final DateTime? pushTime;
  final bool isTest;

  bool get hasRefundWarning => hasRefund || isPrintedRefund;

  String get summary {
    if (hasRefundWarning) {
      return refundStatus.trim().isEmpty
          ? '退款订单，请注意核对'
          : '退款：${refundStatus.trim()}';
    }
    if (buyerMessage.trim().isNotEmpty) return '买家留言：${buyerMessage.trim()}';
    if (sellerMemo.trim().isNotEmpty) return '卖家备注：${sellerMemo.trim()}';
    if (productInfo.trim().isNotEmpty) return '商品：${productInfo.trim()}';
    return orderId.trim().isEmpty ? '已匹配订单信息' : '订单：${orderId.trim()}';
  }

  List<({String label, String value})>
  get details => <({String label, String value})>[
    if (trackingNumber.isNotEmpty) (label: '面单号', value: trackingNumber),
    if (orderId.trim().isNotEmpty) (label: '订单号', value: orderId.trim()),
    if (buyerMessage.trim().isNotEmpty)
      (label: '买家留言', value: buyerMessage.trim()),
    if (sellerMemo.trim().isNotEmpty) (label: '卖家备注', value: sellerMemo.trim()),
    if (productInfo.trim().isNotEmpty)
      (label: '商品信息', value: productInfo.trim()),
    if (hasRefundWarning)
      (
        label: '退款状态',
        value: refundStatus.trim().isEmpty ? '存在退款，请注意核对' : refundStatus.trim(),
      ),
    if (refundProductInfo.trim().isNotEmpty)
      (label: '退款商品', value: refundProductInfo.trim()),
  ];

  List<({String text, bool warning})> get speechMessages => [
    if (hasRefundWarning)
      (
        text: refundStatus.trim().isEmpty
            ? '退款订单，请注意核对'
            : '退款提醒，${refundStatus.trim()}',
        warning: true,
      ),
    if (buyerMessage.trim().isNotEmpty)
      (text: '买家留言，${buyerMessage.trim()}', warning: false),
    if (sellerMemo.trim().isNotEmpty)
      (text: '卖家备注，${sellerMemo.trim()}', warning: false),
  ];

  Map<String, Object?> toJson() => <String, Object?>{
    'trackingNumber': trackingNumber,
    'orderId': orderId,
    'buyerMessage': buyerMessage,
    'sellerMemo': sellerMemo,
    'productInfo': productInfo,
    'hasRefund': hasRefund,
    'isPrintedRefund': isPrintedRefund,
    'refundStatus': refundStatus,
    'refundProductInfo': refundProductInfo,
    if (pushTime != null) 'pushTime': pushTime!.toIso8601String(),
  };
}
