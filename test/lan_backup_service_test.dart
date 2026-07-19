import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/barcode_marker.dart';
import 'package:packing_proof_mobile/models/lan_backup.dart';
import 'package:packing_proof_mobile/models/recording_session.dart';
import 'package:packing_proof_mobile/services/lan_backup_service.dart';

void main() {
  test('接受带访问密钥的局域网电脑二维码', () {
    final LanBackupEndpoint endpoint = LanBackupService.parsePairingQr(
      'http://192.168.1.20:5280/?key=0123456789abcdef',
    );
    expect(endpoint.baseUri.toString(), 'http://192.168.1.20:5280');
    expect(endpoint.accessKey, '0123456789abcdef');
  });

  test('拒绝公网、域名和无密钥二维码', () {
    expect(
      () => LanBackupService.parsePairingQr(
        'http://8.8.8.8:5280/?key=0123456789abcdef',
      ),
      throwsFormatException,
    );
    expect(
      () => LanBackupService.parsePairingQr(
        'http://computer.local:5280/?key=0123456789abcdef',
      ),
      throwsFormatException,
    );
    expect(
      () => LanBackupService.parsePairingQr('http://192.168.1.20:5280/'),
      throwsFormatException,
    );
  });

  test('录像备份元数据包含逻辑片段和面单标记', () {
    final DateTime startedAt = DateTime.utc(2026, 7, 19, 10);
    final RecordingSession session = RecordingSession(
      id: 'session-1',
      filePath: '${Directory.systemTemp.path}/master.mp4',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 8)),
      markers: <BarcodeMarker>[
        BarcodeMarker(
          code: 'SF1234567890',
          occurredAt: startedAt,
          offset: Duration.zero,
        ),
      ],
      mediaStart: const Duration(seconds: 2),
      mediaEnd: const Duration(seconds: 10),
    );

    final Map<String, Object?> value = recordingSessionBackupMap(session);
    expect(value['trackingNumber'], 'SF1234567890');
    expect(value['mediaStartMs'], 2000);
    expect(value['mediaEndMs'], 10000);
    expect(value['markers'], hasLength(1));
  });
}
