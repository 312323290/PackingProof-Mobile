import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/services/barcode_stability_tracker.dart';

void main() {
  test('有效条码首次解码后立即确认', () {
    final BarcodeStabilityTracker tracker = BarcodeStabilityTracker();
    final DateTime now = DateTime(2026, 7, 16, 10);

    final BarcodeObservation first = tracker.observe('JT1234567890', now);
    expect(first.confirmedCode, 'JT1234567890');
  });

  test('持续停留在画面中的同一条码不会重复确认', () {
    final BarcodeStabilityTracker tracker = BarcodeStabilityTracker();
    final DateTime now = DateTime(2026, 7, 16, 10);
    tracker.observe('JT1234567890', now);

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
    tracker.observe(null, now.add(const Duration(seconds: 2)));
    tracker.observe(null, now.add(const Duration(milliseconds: 3600)));
    final BarcodeObservation confirmedAgain = tracker.observe(
      'JT1234567890',
      now.add(const Duration(seconds: 4)),
    );

    expect(confirmedAgain.confirmedCode, 'JT1234567890');
  });
}
