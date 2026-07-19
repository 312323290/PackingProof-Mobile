import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/backup_retention_policy.dart';
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
    expect(settings.maxVolumeEnabled, isTrue);
    expect(settings.startupNoticeVersion, 0);
    expect(settings.lanBackupAutoEnabled, isTrue);
    expect(settings.unbackedRetention, UnbackedRetentionPolicy.days30);
    expect(settings.backedRetention, BackedRetentionPolicy.days7);

    await repository.saveSpeechEnabled(false);
    final Map<String, Object?> persisted = Map<String, Object?>.from(
      jsonDecode(await File('${root.path}/settings.json').readAsString())
          as Map<Object?, Object?>,
    );
    expect(persisted['workMode'], 'sameCodeStop');
    expect(persisted['speechEnabled'], isFalse);
    expect(persisted['maxVolumeEnabled'], isTrue);
    expect(persisted['futureOption'], <String, Object>{'enabled': true});
  });

  test('双重保留策略相互独立并保留未知字段', () async {
    final SessionRepository repository = SessionRepository(rootDirectory: root);
    await repository.saveBackupRetention(
      unbacked: UnbackedRetentionPolicy.days90,
      backed: BackedRetentionPolicy.immediately,
    );
    await repository.saveSpeechEnabled(false);

    final settings = await repository.loadSettings();
    expect(settings.unbackedRetention, UnbackedRetentionPolicy.days90);
    expect(settings.backedRetention, BackedRetentionPolicy.immediately);
    expect(settings.speechEnabled, isFalse);
  });

  test('首次说明版本在两个编译版本间共享且保留其他设置', () async {
    final SessionRepository repository = SessionRepository(rootDirectory: root);
    await repository.saveSpeechEnabled(false);
    await repository.saveStartupNoticeVersion(1);

    final settings = await repository.loadSettings();
    expect(settings.startupNoticeVersion, 1);
    expect(settings.speechEnabled, isFalse);
  });

  test('音量设置默认开启并保留其他字段', () async {
    final SessionRepository repository = SessionRepository(rootDirectory: root);

    expect((await repository.loadSettings()).maxVolumeEnabled, isTrue);
    await repository.saveMaxVolumeEnabled(false);
    await repository.saveSpeechEnabled(false);

    final settings = await repository.loadSettings();
    expect(settings.maxVolumeEnabled, isFalse);
    expect(settings.speechEnabled, isFalse);
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
