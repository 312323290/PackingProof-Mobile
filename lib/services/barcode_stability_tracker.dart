import 'barcode_candidate_policy.dart';

class BarcodeObservation {
  const BarcodeObservation({this.candidateCode = '', this.confirmedCode = ''});

  final String candidateCode;
  final String confirmedCode;
}

class BarcodeStabilityTracker {
  static const Duration releaseWindow = Duration(milliseconds: 1500);

  String _lockedCode = '';
  DateTime? _lockedLastSeen;
  DateTime? _emptySince;

  BarcodeObservation observe(String? code, DateTime now) {
    final String normalized = BarcodeCandidatePolicy.normalize(code);

    if (normalized.isEmpty) {
      _emptySince ??= now;
      if (_lockedLastSeen != null &&
          now.difference(_emptySince!) >= releaseWindow) {
        _lockedCode = '';
        _lockedLastSeen = null;
      }
      return const BarcodeObservation();
    }

    _emptySince = null;

    if (_lockedCode == normalized) {
      _lockedLastSeen = now;
      return const BarcodeObservation();
    }

    _lockedCode = normalized;
    _lockedLastSeen = now;
    return BarcodeObservation(confirmedCode: normalized);
  }

  void reset() {
    _lockedCode = '';
    _lockedLastSeen = null;
    _emptySince = null;
  }
}
