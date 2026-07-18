import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/work_mode.dart';
import 'package:packing_proof_mobile/services/session_repository.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('packing-proof-settings-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('旧设置默认开启语音并保留未知字段', () async {
    await File('${root.path}/settings.json').writeAsString(
      jsonEncode(<String, Object>{
        'workMode': 'sameCodeStop',
        'futureOption': <String, Object>{'enabled': true},
      }),
    );
    final SessionRepository repository = SessionRepository(rootDirectory: root);

    final settings = await repository.loadSettings();
    expect(settings.workMode, WorkMode.sameCodeStop);
    expect(settings.speechEnabled, isTrue);

    await repository.saveSpeechEnabled(false);
    final Map<String, Object?> persisted = Map<String, Object?>.from(
      jsonDecode(await File('${root.path}/settings.json').readAsString())
          as Map<Object?, Object?>,
    );
    expect(persisted['workMode'], 'sameCodeStop');
    expect(persisted['speechEnabled'], isFalse);
    expect(persisted['futureOption'], <String, Object>{'enabled': true});
  });

  test('切换工作模式不会覆盖语音设置', () async {
    final SessionRepository repository = SessionRepository(rootDirectory: root);
    await repository.saveSpeechEnabled(false);
    await repository.saveWorkMode(WorkMode.sameCodeStop);

    final settings = await repository.loadSettings();
    expect(settings.workMode, WorkMode.sameCodeStop);
    expect(settings.speechEnabled, isFalse);
  });
}
