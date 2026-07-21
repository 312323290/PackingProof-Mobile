import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:packing_proof_mobile/models/speech_prompt.dart';

const int _assetVersion = 3;
const String _audioFormat = 'audio-24khz-48kbitrate-mono-mp3';
const int _minimumAudioBytes = 128;

Future<void> main() async {
  final Directory output = Directory(SpeechPrompt.assetDirectory);
  await output.create(recursive: true);
  final File manifestFile = File('${output.path}/manifest.json');
  final Map<String, Object?> existingManifest = await _readManifest(
    manifestFile,
  );
  final Map<String, Map<String, Object?>> existingEntries =
      <String, Map<String, Object?>>{};
  final Object? prompts = existingManifest['prompts'];
  if (prompts is List<Object?>) {
    for (final Object? value in prompts) {
      if (value is Map<String, Object?> && value['id'] is String) {
        existingEntries[value['id']! as String] = value;
      }
    }
  }

  final List<Map<String, Object>> manifestEntries = <Map<String, Object>>[];
  final Set<String> expectedFiles = <String>{};
  int reused = 0;
  int generated = 0;

  for (final SpeechPrompt prompt in SpeechPrompt.values) {
    expectedFiles.add(prompt.assetName);
    final File destination = File('${output.path}/${prompt.assetName}');
    final String cacheKey = _cacheKey(prompt.text, prompt.voice);
    final Map<String, Object?>? existing = existingEntries[prompt.name];
    if (await _isReusable(
      prompt: prompt,
      destination: destination,
      existing: existing,
      cacheKey: cacheKey,
    )) {
      reused++;
      stdout.writeln('复用 ${prompt.assetName}');
    } else {
      await _generate(prompt, destination);
      generated++;
      stdout.writeln('生成 ${prompt.assetName}（${prompt.voice}）');
    }

    final int bytes = await destination.length();
    final String fileHash = await _fileSha256(destination);
    manifestEntries.add(<String, Object>{
      'id': prompt.name,
      'text': prompt.text,
      'priority': prompt.priority.name,
      'voice': prompt.voice,
      'file': prompt.assetName,
      'bytes': bytes,
      'sha256': fileHash,
      'cacheKey': cacheKey,
    });
  }

  await for (final FileSystemEntity entity in output.list()) {
    if (entity is File &&
        entity.path.toLowerCase().endsWith('.mp3') &&
        !expectedFiles.contains(_fileName(entity.path))) {
      await entity.delete();
      stdout.writeln('移除过期语音 ${_fileName(entity.path)}');
    }
  }

  final String manifestText =
      '${const JsonEncoder.withIndent('  ').convert(<String, Object>{'version': _assetVersion, 'format': _audioFormat, 'prompts': manifestEntries})}\n';
  if (!await manifestFile.exists() ||
      await manifestFile.readAsString() != manifestText) {
    await manifestFile.writeAsString(manifestText, flush: true);
  }
  stdout.writeln('固定语音：复用 $reused，生成 $generated');
}

Future<Map<String, Object?>> _readManifest(File file) async {
  if (!await file.exists()) return <String, Object?>{};
  try {
    final Object? value = jsonDecode(await file.readAsString());
    return value is Map<String, Object?> ? value : <String, Object?>{};
  } on Object {
    return <String, Object?>{};
  }
}

Future<bool> _isReusable({
  required SpeechPrompt prompt,
  required File destination,
  required Map<String, Object?>? existing,
  required String cacheKey,
}) async {
  if (existing == null || !await destination.exists()) return false;
  final int bytes = await destination.length();
  if (bytes < _minimumAudioBytes ||
      existing['text'] != prompt.text ||
      existing['priority'] != prompt.priority.name ||
      existing['voice'] != prompt.voice ||
      existing['file'] != prompt.assetName ||
      existing['bytes'] != bytes ||
      existing['cacheKey'] != cacheKey) {
    return false;
  }
  return existing['sha256'] == await _fileSha256(destination);
}

Future<void> _generate(SpeechPrompt prompt, File destination) async {
  final File temporary = File('${destination.path}.generating');
  if (await temporary.exists()) await temporary.delete();
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
      final Uint8List bytes = result.audioBytes;
      if (bytes.length < _minimumAudioBytes) {
        throw StateError('语音数据过短');
      }
      await temporary.writeAsBytes(bytes, flush: true);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      return;
    } on Object catch (error) {
      lastError = error;
      stderr.writeln('${prompt.assetName} 第 $attempt 次生成失败：$error');
    } finally {
      await client.close();
    }
  }
  if (await temporary.exists()) await temporary.delete();
  throw StateError('无法生成 ${prompt.text}：$lastError');
}

String _cacheKey(String text, String voice) {
  final String input = '$text|$voice|$_audioFormat|$_assetVersion';
  return sha256.convert(utf8.encode(input)).toString();
}

Future<String> _fileSha256(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;
