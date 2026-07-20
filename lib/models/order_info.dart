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

  String get refundStatusDisplay {
    final List<String> statuses = refundStatus
        .split(RegExp(r'[,，;；|]'))
        .map((String value) => value.trim().toUpperCase())
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (statuses.isEmpty) return '存在打印后退款，请人工核对';
    final List<String> descriptions = statuses
        .where((String value) => value != 'NO_REFUND')
        .map(
          (String value) => switch (value) {
            'WAIT_SELLER_AGREE' => '等待卖家同意退款',
            'WAIT_BUYER_RETURN_GOODS' => '等待买家退货',
            'WAIT_SELLER_CONFIRM_GOODS' => '等待卖家确认收货',
            'SUCCESS' => '退款完成',
            'CLOSED' => '退款关闭',
            _ =>
              value.contains(RegExp(r'[\u4e00-\u9fff]'))
                  ? value
                  : '退款状态未知（$value），请人工核对',
          },
        )
        .toSet()
        .toList(growable: false);
    return descriptions.isEmpty ? '无退款' : descriptions.join('，');
  }

  String get summary {
    if (hasRefundWarning) {
      return '退款：$refundStatusDisplay';
    }
    if (buyerMessage.trim().isNotEmpty) return '买家留言：${buyerMessage.trim()}';
    if (sellerMemo.trim().isNotEmpty) return '卖家备注：${sellerMemo.trim()}';
    if (productInfo.trim().isNotEmpty) return '商品：${productInfo.trim()}';
    return orderId.trim().isEmpty ? '已匹配订单信息' : '订单：${orderId.trim()}';
  }

  List<({String label, String value})> get details =>
      <({String label, String value})>[
        if (trackingNumber.isNotEmpty) (label: '面单号', value: trackingNumber),
        if (orderId.trim().isNotEmpty) (label: '订单号', value: orderId.trim()),
        if (buyerMessage.trim().isNotEmpty)
          (label: '买家留言', value: buyerMessage.trim()),
        if (sellerMemo.trim().isNotEmpty)
          (label: '卖家备注', value: sellerMemo.trim()),
        if (productInfo.trim().isNotEmpty)
          (label: '商品信息', value: productInfo.trim()),
        if (hasRefundWarning) (label: '退款状态', value: refundStatusDisplay),
        if (refundProductInfo.trim().isNotEmpty)
          (label: '退款商品', value: refundProductInfo.trim()),
      ];

  List<({String text, bool warning})> get speechMessages => [
    if (hasRefundWarning) (text: '退款提醒，$refundStatusDisplay', warning: true),
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
