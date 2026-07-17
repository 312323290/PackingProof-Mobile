import '../models/barcode_marker.dart';
import '../models/recording_session.dart';

class RecordingTimeline {
  final List<_SegmentDraft> _completedSegments = <_SegmentDraft>[];
  final List<BarcodeMarker> _activeMarkers = <BarcodeMarker>[];

  DateTime? _recordingStartedAt;
  DateTime? _segmentStartedAt;
  String _currentCode = '';

  DateTime? get recordingStartedAt => _recordingStartedAt;
  String get currentCode => _currentCode;
  bool get isActive => _recordingStartedAt != null;

  void start(DateTime startedAt) {
    reset();
    _recordingStartedAt = startedAt;
    _segmentStartedAt = startedAt;
  }

  BarcodeMarker? bindCode(String code, DateTime occurredAt) {
    final DateTime? segmentStartedAt = _segmentStartedAt;
    if (segmentStartedAt == null || _currentCode.isNotEmpty) {
      return null;
    }
    final BarcodeMarker marker = BarcodeMarker(
      code: code,
      occurredAt: occurredAt,
      offset: _difference(occurredAt, segmentStartedAt),
    );
    _currentCode = code;
    _activeMarkers.add(marker);
    return marker;
  }

  BarcodeMarker? startNext(String code, DateTime occurredAt) {
    if (_segmentStartedAt == null) {
      return null;
    }
    _completeActiveSegment(occurredAt);
    _segmentStartedAt = occurredAt;
    _currentCode = '';
    _activeMarkers.clear();
    return bindCode(code, occurredAt);
  }

  List<RecordingSession> buildSessions({
    required DateTime endedAt,
    required String filePath,
    required String recordingId,
  }) {
    final DateTime? recordingStartedAt = _recordingStartedAt;
    if (recordingStartedAt == null || _segmentStartedAt == null) {
      return <RecordingSession>[];
    }

    _completeActiveSegment(endedAt);
    return List<RecordingSession>.generate(_completedSegments.length, (
      int index,
    ) {
      final _SegmentDraft draft = _completedSegments[index];
      final String id = _completedSegments.length == 1
          ? recordingId
          : '${recordingId}_${(index + 1).toString().padLeft(3, '0')}';
      return RecordingSession(
        id: id,
        filePath: filePath,
        startedAt: draft.startedAt,
        endedAt: draft.endedAt,
        markers: List<BarcodeMarker>.unmodifiable(draft.markers),
        mediaStart: _difference(draft.startedAt, recordingStartedAt),
        mediaEnd: _difference(draft.endedAt, recordingStartedAt),
      );
    }, growable: false);
  }

  void reset() {
    _completedSegments.clear();
    _activeMarkers.clear();
    _recordingStartedAt = null;
    _segmentStartedAt = null;
    _currentCode = '';
  }

  void _completeActiveSegment(DateTime endedAt) {
    final DateTime? startedAt = _segmentStartedAt;
    if (startedAt == null) {
      return;
    }
    _completedSegments.add(
      _SegmentDraft(
        startedAt: startedAt,
        endedAt: endedAt.isBefore(startedAt) ? startedAt : endedAt,
        markers: List<BarcodeMarker>.of(_activeMarkers),
      ),
    );
    _segmentStartedAt = null;
  }
}

class _SegmentDraft {
  const _SegmentDraft({
    required this.startedAt,
    required this.endedAt,
    required this.markers,
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final List<BarcodeMarker> markers;
}

Duration _difference(DateTime later, DateTime earlier) {
  final Duration value = later.difference(earlier);
  return value.isNegative ? Duration.zero : value;
}
