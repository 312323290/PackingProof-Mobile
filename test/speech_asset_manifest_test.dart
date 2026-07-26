import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/models/speech_prompt.dart';

void main() {
  test('每条固定语音都有有效且匹配的预生成资源', () {
    final manifestFile = File('${SpeechPrompt.assetDirectory}/manifest.json');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    final entries = (manifest['prompts']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final entriesById = <String, Map<String, Object?>>{
      for (final entry in entries) entry['id']! as String: entry,
    };

    expect(
      entriesById.keys,
      unorderedEquals(SpeechPrompt.values.map((prompt) => prompt.name)),
    );
    for (final prompt in SpeechPrompt.values) {
      final entry = entriesById[prompt.name]!;
      final file = File('${SpeechPrompt.assetDirectory}/${prompt.assetName}');
      final bytes = file.readAsBytesSync();

      expect(entry['text'], prompt.text);
      expect(entry['priority'], prompt.priority.name);
      expect(entry['voice'], prompt.voice);
      expect(entry['file'], prompt.assetName);
      expect(entry['bytes'], bytes.length);
      expect(entry['sha256'], sha256.convert(bytes).toString());
    }
  });

  test('固定文案不能绕过预生成资源直接调用动态系统语音', () {
    final fixedDynamicSpeech = RegExp(r'''enqueueText\(\s*['"]''');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (fixedDynamicSpeech.hasMatch(entity.readAsStringSync())) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
