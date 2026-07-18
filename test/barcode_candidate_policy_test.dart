import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/services/barcode_candidate_policy.dart';

void main() {
  group('BarcodeCandidatePolicy', () {
    test('标准化并接受常见物流条码', () {
      expect(
        BarcodeCandidatePolicy.normalize('  jt 1234567890 '),
        'JT1234567890',
      );
      expect(BarcodeCandidatePolicy.isValid('JT1234567890'), isTrue);
      expect(BarcodeCandidatePolicy.isValid('SF-1234567890'), isTrue);
      expect(BarcodeCandidatePolicy.isValid('12345678'), isTrue);
      expect(
        BarcodeCandidatePolicy.isValid('YT123456789012345678901234567890'),
        isTrue,
      );
    });

    test('过滤短码和操作指令', () {
      expect(BarcodeCandidatePolicy.isValid('12345'), isFalse);
      expect(BarcodeCandidatePolicy.isValid('START1234567890'), isFalse);
      expect(BarcodeCandidatePolicy.isValid('https://example.com'), isFalse);
    });
  });
}
