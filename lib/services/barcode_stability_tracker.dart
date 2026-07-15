import 'barcode_candidate_policy.dart';

class BarcodeObservation {
  const BarcodeObservation({this.candidateCode = '', this.confirmedCode = ''});

  final String candidateCode;
  final String confirmedCode;
}

class BarcodeStabilityTracker {
  static const Duration confirmationWindow = Duration(milliseconds: 1500);

  final Set<String> _lockedCodes = <String>{};
  String _candidateCode = '';
  DateTime? _candidateFirstSeen;
  DateTime? _candidateLastSeen;
  int _candidateHits = 0;

  BarcodeObservation observe(String? code, DateTime now) {
    final String normalized = BarcodeCandidatePolicy.normalize(code);

    if (normalized.isEmpty) {
      _expireCandidate(now);
      return BarcodeObservation(candidateCode: _candidateCode);
    }

    if (_lockedCodes.contains(normalized)) {
      if (_candidateCode == normalized) {
        _clearCandidate();
      }
      return const BarcodeObservation();
    }

    if (_candidateCode != normalized ||
        _candidateFirstSeen == null ||
        now.difference(_candidateFirstSeen!) > confirmationWindow) {
      _candidateCode = normalized;
      _candidateFirstSeen = now;
      _candidateLastSeen = now;
      _candidateHits = 1;
      return BarcodeObservation(candidateCode: normalized);
    }

    _candidateLastSeen = now;
    _candidateHits++;
    if (_candidateHits < 2) {
      return BarcodeObservation(candidateCode: normalized);
    }

    _lockedCodes.add(normalized);
    _clearCandidate();
    return BarcodeObservation(confirmedCode: normalized);
  }

  void reset() {
    _lockedCodes.clear();
    _clearCandidate();
  }

  void _expireCandidate(DateTime now) {
    if (_candidateLastSeen != null &&
        now.difference(_candidateLastSeen!) >= confirmationWindow) {
      _clearCandidate();
    }
  }

  void _clearCandidate() {
    _candidateCode = '';
    _candidateFirstSeen = null;
    _candidateLastSeen = null;
    _candidateHits = 0;
  }
}
