import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/services/barcode_stability_tracker.dart';

void main() {
  test('有效条码需要连续两次一致才确认', () {
    final BarcodeStabilityTracker tracker = BarcodeStabilityTracker();
    final DateTime now = DateTime(2026, 7, 16, 10);

    final BarcodeObservation first = tracker.observe('JT1234567890', now);
    expect(first.candidateCode, 'JT1234567890');
    expect(first.confirmedCode, isEmpty);

    final BarcodeObservation second = tracker.observe(
      'JT1234567890',
      now.add(const Duration(milliseconds: 100)),
    );
    expect(second.confirmedCode, 'JT1234567890');
  });

  test('中途变化的条码会重新计数', () {
    final BarcodeStabilityTracker tracker = BarcodeStabilityTracker();
    final DateTime now = DateTime(2026, 7, 16, 10);

    tracker.observe('JT1234567890', now);
    final BarcodeObservation changed = tracker.observe(
      'SF1234567890',
      now.add(const Duration(milliseconds: 100)),
    );
    expect(changed.candidateCode, 'SF1234567890');
    expect(changed.confirmedCode, isEmpty);
    expect(
      tracker
          .observe('SF1234567890', now.add(const Duration(milliseconds: 200)))
          .confirmedCode,
      'SF1234567890',
    );
  });

  test('持续停留在画面中的同一条码不会重复确认', () {
    final BarcodeStabilityTracker tracker = BarcodeStabilityTracker();
    final DateTime now = DateTime(2026, 7, 16, 10);
    tracker.observe('JT1234567890', now);
    tracker.observe('JT1234567890', now.add(const Duration(milliseconds: 100)));

    final BarcodeObservation locked = tracker.observe(
      'JT1234567890',
      now.add(const Duration(seconds: 2)),
    );
    expect(locked.confirmedCode, isEmpty);
  });

  test('条码离开画面后再次进入可重新确认', () {
    final BarcodeStabilityTracker tracker = BarcodeStabilityTracker();
    final DateTime now = DateTime(2026, 7, 16, 10);
    tracker.observe('JT1234567890', now);
    tracker.observe('JT1234567890', now.add(const Duration(milliseconds: 100)));
    tracker.observe(null, now.add(const Duration(seconds: 2)));
    tracker.observe(null, now.add(const Duration(milliseconds: 3600)));
    final BarcodeObservation candidateAgain = tracker.observe(
      'JT1234567890',
      now.add(const Duration(seconds: 4)),
    );
    final BarcodeObservation confirmedAgain = tracker.observe(
      'JT1234567890',
      now.add(const Duration(milliseconds: 4100)),
    );

    expect(candidateAgain.candidateCode, 'JT1234567890');
    expect(confirmedAgain.confirmedCode, 'JT1234567890');
  });
}
