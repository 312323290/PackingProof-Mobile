import 'barcode_marker.dart';

class RecordingSession {
  const RecordingSession({
    required this.id,
    required this.filePath,
    required this.startedAt,
    required this.endedAt,
    required this.markers,
  });

  final String id;
  final String filePath;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<BarcodeMarker> markers;

  Duration get duration => endedAt.difference(startedAt);

  String get displayCode => markers.isEmpty ? '未识别面单' : markers.first.code;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'filePath': filePath,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'markers': markers.map((BarcodeMarker marker) => marker.toJson()).toList(),
  };

  factory RecordingSession.fromJson(Map<String, Object?> json) {
    final List<Object?> markerValues = json['markers']! as List<Object?>;
    return RecordingSession(
      id: json['id']! as String,
      filePath: json['filePath']! as String,
      startedAt: DateTime.parse(json['startedAt']! as String),
      endedAt: DateTime.parse(json['endedAt']! as String),
      markers: markerValues
          .map(
            (Object? value) => BarcodeMarker.fromJson(
              Map<String, Object?>.from(value! as Map<Object?, Object?>),
            ),
          )
          .toList(growable: false),
    );
  }
}
