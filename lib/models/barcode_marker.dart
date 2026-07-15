class BarcodeMarker {
  const BarcodeMarker({
    required this.code,
    required this.occurredAt,
    required this.offset,
  });

  final String code;
  final DateTime occurredAt;
  final Duration offset;

  Map<String, Object> toJson() => <String, Object>{
    'code': code,
    'occurredAt': occurredAt.toIso8601String(),
    'offsetMilliseconds': offset.inMilliseconds,
  };

  factory BarcodeMarker.fromJson(Map<String, Object?> json) {
    return BarcodeMarker(
      code: json['code']! as String,
      occurredAt: DateTime.parse(json['occurredAt']! as String),
      offset: Duration(
        milliseconds: (json['offsetMilliseconds']! as num).toInt(),
      ),
    );
  }
}
