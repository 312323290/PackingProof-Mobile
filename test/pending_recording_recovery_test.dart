import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/recording_session.dart';
import 'package:packing_proof_mobile/services/session_repository.dart';

import 'test_repository.dart';

void main() {
  List<int> mp4Box(String type, {int extra = 0}) {
    final int size = 8 + extra;
    return <int>[
      (size >> 24) & 0xff,
      (size >> 16) & 0xff,
      (size >> 8) & 0xff,
      size & 0xff,
      ...type.codeUnits,
      ...List<int>.filled(extra, 0),
    ];
  }

  List<int> playableMp4() => <int>[
    ...mp4Box('ftyp', extra: 16),
    ...mp4Box('moov'),
  ];

  List<int> truncatedMp4() => <int>[...mp4Box('ftyp', extra: 16)];

  test('MP4 结构校验只接受包含 ftyp 与 moov 的完整文件', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing_proof_mp4_structure_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final File valid = File('${root.path}/valid.mp4')
      ..writeAsBytesSync(playableMp4());
    final File truncated = File('${root.path}/truncated.mp4')
      ..writeAsBytesSync(truncatedMp4());
    final File moovOnly = File('${root.path}/moov-only.mp4')
      ..writeAsBytesSync(mp4Box('moov'));
    final File garbage = File('${root.path}/garbage.mp4')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final File oversized = File('${root.path}/oversized.mp4')
      ..writeAsBytesSync(<int>[0, 0, 0, 200, ...'ftyp'.codeUnits]);

    expect(await SessionRepository.hasPlayableMp4Structure(valid), isTrue);
    expect(await SessionRepository.hasPlayableMp4Structure(truncated), isFalse);
    expect(await SessionRepository.hasPlayableMp4Structure(moovOnly), isFalse);
    expect(await SessionRepository.hasPlayableMp4Structure(garbage), isFalse);
    expect(await SessionRepository.hasPlayableMp4Structure(oversized), isFalse);
  });

  test('完整异常录像恢复并进入历史', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing_proof_recovery_ok_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final Directory pending = Directory('${root.path}/recordings/.pending');
    await pending.create(recursive: true);
    final File video = File('${pending.path}/20260722_103000_000.mp4');
    await video.writeAsBytes(playableMp4());

    final SessionRepository repository = testRepository(root);
    final List<RecordingSession> sessions = await repository.loadSessions();

    expect(sessions, hasLength(1));
    expect(sessions.single.filePath, contains('异常恢复'));
    expect(File(sessions.single.filePath).existsSync(), isTrue);
    expect(video.existsSync(), isFalse);
  });

  test('残缺异常录像隔离到损坏目录且不进入历史', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing_proof_recovery_broken_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final Directory pending = Directory('${root.path}/recordings/.pending');
    await pending.create(recursive: true);
    final File video = File('${pending.path}/20260722_103000_000.mp4');
    await video.writeAsBytes(truncatedMp4());

    final SessionRepository repository = testRepository(root);
    final List<RecordingSession> sessions = await repository.loadSessions();

    expect(sessions, isEmpty);
    expect(video.existsSync(), isFalse);
    final List<FileSystemEntity> preserved = Directory(
      '${root.path}/recordings/损坏录像',
    ).listSync(recursive: true);
    expect(
      preserved.whereType<File>().where(
        (File file) => file.path.endsWith('.mp4'),
      ),
      hasLength(1),
    );
  });

  test('零字节异常录像同样隔离且不进入历史', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'packing_proof_recovery_empty_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final Directory pending = Directory('${root.path}/recordings/.pending');
    await pending.create(recursive: true);
    final File video = File('${pending.path}/20260722_103000_000.mp4');
    await video.writeAsBytes(<int>[]);

    final SessionRepository repository = testRepository(root);
    final List<RecordingSession> sessions = await repository.loadSessions();

    expect(sessions, isEmpty);
    expect(video.existsSync(), isFalse);
    final List<FileSystemEntity> preserved = Directory(
      '${root.path}/recordings/损坏录像',
    ).listSync(recursive: true);
    expect(
      preserved.whereType<File>().where(
        (File file) => file.path.endsWith('.mp4'),
      ),
      hasLength(1),
    );
  });
}
