import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_lens/services/barcode_stability_tracker.dart';

void main() {
  test('相同条码在窗口内出现两次才确认', () {
    final BarcodeStabilityTracker tracker = BarcodeStabilityTracker();
    final DateTime now = DateTime(2026, 7, 16, 10);

    final BarcodeObservation first = tracker.observe('JT1234567890', now);
    final BarcodeObservation second = tracker.observe(
      'JT1234567890',
      now.add(const Duration(milliseconds: 400)),
    );

    expect(first.candidateCode, 'JT1234567890');
    expect(first.confirmedCode, isEmpty);
    expect(second.confirmedCode, 'JT1234567890');
  });

  test('持续停留在画面中的同一条码不会重复确认', () {
    final BarcodeStabilityTracker tracker = BarcodeStabilityTracker();
    final DateTime now = DateTime(2026, 7, 16, 10);
    tracker.observe('JT1234567890', now);
    tracker.observe('JT1234567890', now.add(const Duration(milliseconds: 300)));

    final BarcodeObservation locked = tracker.observe(
      'JT1234567890',
      now.add(const Duration(seconds: 2)),
    );
    expect(locked.confirmedCode, isEmpty);
  });

  test('同一次录像内条码离开后也不重复标记', () {
    final BarcodeStabilityTracker tracker = BarcodeStabilityTracker();
    final DateTime now = DateTime(2026, 7, 16, 10);
    tracker.observe('JT1234567890', now);
    tracker.observe('JT1234567890', now.add(const Duration(milliseconds: 300)));
    tracker.observe(null, now.add(const Duration(seconds: 2)));
    tracker.observe('JT1234567890', now.add(const Duration(seconds: 3)));
    final BarcodeObservation confirmedAgain = tracker.observe(
      'JT1234567890',
      now.add(const Duration(milliseconds: 3400)),
    );

    expect(confirmedAgain.confirmedCode, isEmpty);
  });
}
