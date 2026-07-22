import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/services/session_repository.dart';

SessionRepository testRepository(Directory root) {
  final SessionRepository repository = SessionRepository(rootDirectory: root);
  addTearDown(repository.dispose);
  return repository;
}
