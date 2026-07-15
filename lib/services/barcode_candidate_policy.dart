class BarcodeCandidatePolicy {
  const BarcodeCandidatePolicy._();

  static final RegExp _allowed = RegExp(r'^[A-Z0-9-]{8,40}$');
  static const List<String> _blockedWords = <String>[
    'CLEAR',
    'SHIP',
    'FAHUO',
    'BACK',
    'TUIHUO',
    'START',
    'STOP',
    'HTTP',
  ];

  static String normalize(String? value) {
    return (value ?? '').trim().replaceAll(' ', '').toUpperCase();
  }

  static bool isValid(String? value) {
    final String normalized = normalize(value);
    if (!_allowed.hasMatch(normalized)) {
      return false;
    }
    return !_blockedWords.any(normalized.contains);
  }
}
