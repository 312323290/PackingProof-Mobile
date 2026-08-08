class TrackingRecord {
  final int? id;
  final String trackingNumber;
  final DateTime recognizedAt;
  final String videoFilePath;

  const TrackingRecord({
    this.id,
    required this.trackingNumber,
    required this.recognizedAt,
    this.videoFilePath = '',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'tracking_number': trackingNumber,
        'recognized_at': recognizedAt.millisecondsSinceEpoch,
        'video_file_path': videoFilePath,
      };

  factory TrackingRecord.fromMap(Map<String, dynamic> map) => TrackingRecord(
        id: map['id'] as int?,
        trackingNumber: map['tracking_number'] as String,
        recognizedAt: DateTime.fromMillisecondsSinceEpoch(
          map['recognized_at'] as int,
        ),
        videoFilePath: map['video_file_path'] as String? ?? '',
      );
}