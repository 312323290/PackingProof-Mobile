import 'dart:convert';
import 'dart:io';

import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:parcel_lens/models/speech_prompt.dart';

Future<void> main() async {
  final Directory output = Directory('assets/audio/tts');
  await output.create(recursive: true);
  final List<Map<String, Object>> manifestEntries = <Map<String, Object>>[];

  for (final SpeechPrompt prompt in SpeechPrompt.values) {
    final File destination = File('${output.path}/${prompt.assetName}');
    stdout.writeln('生成 ${prompt.text}（${prompt.voice}）');
    Object? lastError;
    for (int attempt = 1; attempt <= 2; attempt++) {
      final FlutterEdgeTts client = FlutterEdgeTts(
        voice: prompt.voice,
        outputFormat: EdgeTtsOutputFormat.audio24Khz48KbitrateMonoMp3,
        connectionTimeout: const Duration(seconds: 20),
      );
      try {
        final EdgeTtsSynthesisResult result = await client
            .synthesize(prompt.text)
            .timeout(const Duration(seconds: 30));
        if (result.audioBytes.length <= 128) {
          throw StateError('语音数据过短');
        }
        await destination.writeAsBytes(result.audioBytes, flush: true);
        lastError = null;
        break;
      } on Object catch (error) {
        lastError = error;
        stderr.writeln('第 $attempt 次生成失败：$error');
      } finally {
        await client.close();
      }
    }
    if (lastError != null) {
      stderr.writeln('无法生成 ${prompt.text}：$lastError');
      exitCode = 1;
      return;
    }
    manifestEntries.add(<String, Object>{
      'id': prompt.name,
      'text': prompt.text,
      'priority': prompt.priority.name,
      'voice': prompt.voice,
      'file': prompt.assetName,
      'bytes': await destination.length(),
    });
  }

  final File manifest = File('${output.path}/manifest.json');
  await manifest.writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object>{
      'version': 1,
      'format': 'audio-24khz-48kbitrate-mono-mp3',
      'prompts': manifestEntries,
    }),
    flush: true,
  );
  stdout.writeln('已生成 ${manifestEntries.length} 条默认语音');
}
