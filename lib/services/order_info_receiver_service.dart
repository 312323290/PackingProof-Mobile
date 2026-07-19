import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/order_info.dart';

class OrderInfoReceiverSnapshot {
  const OrderInfoReceiverSnapshot({
    this.running = false,
    this.ipAddress = '',
    this.url = '',
    this.port = 5280,
    this.errorMessage = '',
    this.lastReceivedAt,
  });

  final bool running;
  final String ipAddress;
  final String url;
  final int port;
  final String errorMessage;
  final DateTime? lastReceivedAt;

  OrderInfoReceiverSnapshot copyWith({
    bool? running,
    String? ipAddress,
    String? url,
    int? port,
    String? errorMessage,
    DateTime? lastReceivedAt,
  }) => OrderInfoReceiverSnapshot(
    running: running ?? this.running,
    ipAddress: ipAddress ?? this.ipAddress,
    url: url ?? this.url,
    port: port ?? this.port,
    errorMessage: errorMessage ?? this.errorMessage,
    lastReceivedAt: lastReceivedAt ?? this.lastReceivedAt,
  );
}

abstract interface class OrderInfoReceiverSink implements Listenable {
  OrderInfoReceiverSnapshot get snapshot;

  Stream<OrderInfo> get received;

  Future<void> initialize();

  Future<void> retry();

  Future<OrderInfo?> lookup(String trackingNumber);

  Future<void> setBackgroundKeepAlive(bool enabled);

  Future<void> dispose();
}

class OrderInfoReceiverService extends ChangeNotifier
    implements OrderInfoReceiverSink {
  OrderInfoReceiverService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName =
      'app.packingproof.mobile/order_info_receiver';
  final MethodChannel _channel;
  final StreamController<OrderInfo> _received =
      StreamController<OrderInfo>.broadcast();
  OrderInfoReceiverSnapshot _snapshot = const OrderInfoReceiverSnapshot();
  bool _disposed = false;

  @override
  OrderInfoReceiverSnapshot get snapshot => _snapshot;

  @override
  Stream<OrderInfo> get received => _received.stream;

  @override
  Future<void> initialize() async {
    if (!Platform.isAndroid || _disposed) return;
    _channel.setMethodCallHandler(_handleNativeCall);
    await _applyStatus(
      await _channel.invokeMapMethod<Object?, Object?>('start'),
    );
  }

  @override
  Future<void> retry() async {
    if (!Platform.isAndroid || _disposed) return;
    await _applyStatus(
      await _channel.invokeMapMethod<Object?, Object?>('retry'),
    );
  }

  @override
  Future<OrderInfo?> lookup(String trackingNumber) async {
    if (!Platform.isAndroid || _disposed || trackingNumber.trim().isEmpty) {
      return null;
    }
    final Map<Object?, Object?>? value = await _channel
        .invokeMapMethod<Object?, Object?>('lookup', <String, Object>{
          'trackingNumber': trackingNumber.trim(),
        });
    return value == null ? null : OrderInfo.fromMap(value);
  }

  @override
  Future<void> setBackgroundKeepAlive(bool enabled) async {
    if (!Platform.isAndroid || _disposed) return;
    await _channel.invokeMethod<void>(
      'setBackgroundKeepAlive',
      <String, Object>{'enabled': enabled},
    );
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'orderInfoReceived' || _disposed) return;
    final List<Object?> values = List<Object?>.from(call.arguments as List);
    final List<OrderInfo> items = values
        .whereType<Map>()
        .map(
          (Map value) => OrderInfo.fromMap(Map<Object?, Object?>.from(value)),
        )
        .toList(growable: false);
    _snapshot = _snapshot.copyWith(lastReceivedAt: DateTime.now());
    notifyListeners();
    for (final OrderInfo item in items) {
      _received.add(item);
    }
  }

  Future<void> _applyStatus(Map<Object?, Object?>? value) async {
    if (value == null || _disposed) return;
    _snapshot = OrderInfoReceiverSnapshot(
      running: value['running'] == true,
      ipAddress: '${value['ipAddress'] ?? ''}',
      url: '${value['url'] ?? ''}',
      port: (value['port'] as num?)?.toInt() ?? 5280,
      errorMessage: '${value['errorMessage'] ?? ''}',
      lastReceivedAt: _snapshot.lastReceivedAt,
    );
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _received.close();
    super.dispose();
  }
}
