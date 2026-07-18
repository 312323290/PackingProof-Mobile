import 'barcode_marker.dart';

class RecordingSession {
  const RecordingSession({
    required this.id,
    required this.filePath,
    required this.startedAt,
    required this.endedAt,
    required this.markers,
    this.mediaStart = Duration.zero,
    this.mediaEnd,
  });

  final String id;
  final String filePath;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<BarcodeMarker> markers;
  final Duration mediaStart;
  final Duration? mediaEnd;

  Duration get duration => endedAt.difference(startedAt);

  Duration get playbackEnd => mediaEnd ?? mediaStart + duration;

  Duration get playbackDuration => playbackEnd - mediaStart;

  String get displayCode => markers.isEmpty ? '未识别面单' : markers.first.code;

  RecordingSession trimmed({
    required Duration startOffset,
    required Duration endOffset,
  }) {
    if (startOffset.isNegative ||
        endOffset > playbackDuration ||
        endOffset <= startOffset) {
      throw ArgumentError('剪辑区间必须位于当前录像片段内');
    }
    final Duration newDuration = endOffset - startOffset;
    final List<BarcodeMarker> adjustedMarkers = markers
        .map((BarcodeMarker marker) {
          Duration offset = marker.offset - startOffset;
          if (offset.isNegative || offset > newDuration) {
            offset = Duration.zero;
          }
          return BarcodeMarker(
            code: marker.code,
            occurredAt: marker.occurredAt,
            offset: offset,
          );
        })
        .toList(growable: false);
    return RecordingSession(
      id: id,
      filePath: filePath,
      startedAt: startedAt.add(startOffset),
      endedAt: startedAt.add(endOffset),
      markers: adjustedMarkers,
      mediaStart: mediaStart + startOffset,
      mediaEnd: mediaStart + endOffset,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'filePath': filePath,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'markers': markers.map((BarcodeMarker marker) => marker.toJson()).toList(),
    'mediaStartMilliseconds': mediaStart.inMilliseconds,
    'mediaEndMilliseconds': playbackEnd.inMilliseconds,
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
      mediaStart: Duration(
        milliseconds: (json['mediaStartMilliseconds'] as num?)?.toInt() ?? 0,
      ),
      mediaEnd: json['mediaEndMilliseconds'] == null
          ? null
          : Duration(
              milliseconds: (json['mediaEndMilliseconds']! as num).toInt(),
            ),
    );
  }
}
