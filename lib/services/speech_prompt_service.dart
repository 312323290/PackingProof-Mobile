import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/speech_prompt.dart';

abstract interface class SpeechPromptSink {
  bool get enabled;

  Future<void> setEnabled(bool value);

  void enqueue(SpeechPrompt prompt, {String? incidentKey});

  Future<void> preview();

  void resetIncidents();

  void resolveIncident(String incidentKey);

  Future<void> dispose();
}

abstract interface class SpeechOutput {
  Future<void> playAsset(String assetPath);

  Future<void> playFile(String filePath);

  Future<void> speakSystem(String text, {bool offlineOnly = false});

  Future<void> stop();

  Future<void> dispose();
}

abstract interface class EdgeSpeechGenerator {
  Future<Uint8List> synthesize({required String text, required String voice});
}

class SpeechPromptService implements SpeechPromptSink {
  SpeechPromptService({
    SpeechOutput? output,
    EdgeSpeechGenerator? edgeGenerator,
    SpeechPromptCache? cache,
    AssetBundle? assetBundle,
    this.onlineEdgeTtsEnabled = true,
    this.offlineSystemTtsOnly = false,
  }) : _output = output ?? DeviceSpeechOutput(),
       _edgeGenerator = edgeGenerator ?? FlutterEdgeSpeechGenerator(),
       _cache = cache ?? SpeechPromptCache(),
       _assetBundle = assetBundle ?? rootBundle;

  final SpeechOutput _output;
  final EdgeSpeechGenerator _edgeGenerator;
  final SpeechPromptCache _cache;
  final AssetBundle _assetBundle;
  final bool onlineEdgeTtsEnabled;
  final bool offlineSystemTtsOnly;
  final ListQueue<SpeechPrompt> _queue = ListQueue<SpeechPrompt>();
  final Set<String> _activeIncidents = <String>{};

  bool _enabled = true;
  bool _draining = false;
  bool _disposed = false;

  @override
  bool get enabled => _enabled;

  @override
  Future<void> setEnabled(bool value) async {
    if (_disposed || _enabled == value) {
      return;
    }
    _enabled = value;
    if (!value) {
      _queue.clear();
      _activeIncidents.clear();
      await _output.stop();
    }
  }

  @override
  void enqueue(SpeechPrompt prompt, {String? incidentKey}) {
    if (_disposed || !_enabled) {
      return;
    }
    if (prompt.priority == SpeechPromptPriority.warning) {
      final String key = incidentKey ?? prompt.name;
      if (!_activeIncidents.add(key)) {
        return;
      }
      _queue.removeWhere(
        (SpeechPrompt queued) => queued.priority == SpeechPromptPriority.normal,
      );
      unawaited(_output.stop());
    }
    _queue.add(prompt);
    unawaited(_drain());
  }

  @override
  Future<void> preview() async {
    if (_disposed || !_enabled) {
      return;
    }
    await _output.stop();
    _queue.addFirst(SpeechPrompt.previewEnabled);
    unawaited(_drain());
    await waitUntilIdle();
  }

  Future<void> waitUntilIdle() async {
    while (_draining || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  @override
  void resetIncidents() => _activeIncidents.clear();

  @override
  void resolveIncident(String incidentKey) {
    _activeIncidents.remove(incidentKey);
  }

  Future<void> _drain() async {
    if (_draining || _disposed || !_enabled) {
      return;
    }
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_disposed && _enabled) {
        final SpeechPrompt prompt = _queue.removeFirst();
        await _playWithFallback(prompt);
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty && !_disposed && _enabled) {
        unawaited(_drain());
      }
    }
  }

  Future<void> _playWithFallback(SpeechPrompt prompt) async {
    if (await _hasBundledAsset(prompt)) {
      try {
        await _output.playAsset(prompt.audioPlayerAssetPath);
        return;
      } on Object {
        // A damaged package asset can still be repaired through the online cache.
      }
    }

    final File? cached = await _cache.find(prompt);
    if (cached != null) {
      try {
        await _output.playFile(cached.path);
        return;
      } on Object {
        await _cache.remove(cached);
      }
    }

    if (onlineEdgeTtsEnabled) {
      try {
        final Uint8List bytes = await _edgeGenerator
            .synthesize(text: prompt.text, voice: prompt.voice)
            .timeout(const Duration(seconds: 10));
        final File generated = await _cache.store(prompt, bytes);
        await _output.playFile(generated.path);
        return;
      } on Object {
        // Edge is best effort; Android system TTS is the final fallback.
      }
    }

    try {
      await _output.speakSystem(
        prompt.text,
        offlineOnly: offlineSystemTtsOnly,
      );
    } on Object {
      // Speech must never interrupt or fail the recording workflow.
    }
  }

  Future<bool> _hasBundledAsset(SpeechPrompt prompt) async {
    try {
      final ByteData data = await _assetBundle.load(prompt.assetPath);
      return data.lengthInBytes > SpeechPromptCache.minimumAudioBytes;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _queue.clear();
    _activeIncidents.clear();
    await _output.stop();
    await _output.dispose();
    await _edgeGenerator.closeIfSupported();
  }
}

extension on EdgeSpeechGenerator {
  Future<void> closeIfSupported() async {
    if (this case final DisposableEdgeSpeechGenerator disposable) {
      await disposable.close();
    }
  }
}

abstract interface class DisposableEdgeSpeechGenerator
    implements EdgeSpeechGenerator {
  Future<void> close();
}

class FlutterEdgeSpeechGenerator implements DisposableEdgeSpeechGenerator {
  final Set<FlutterEdgeTts> _active = <FlutterEdgeTts>{};

  @override
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
  }) async {
    final FlutterEdgeTts client = FlutterEdgeTts(
      voice: voice,
      outputFormat: EdgeTtsOutputFormat.audio24Khz48KbitrateMonoMp3,
      connectionTimeout: const Duration(seconds: 8),
    );
    _active.add(client);
    try {
      final EdgeTtsSynthesisResult result = await client.synthesize(text);
      return result.audioBytes;
    } finally {
      _active.remove(client);
      await client.close();
    }
  }

  @override
  Future<void> close() async {
    for (final FlutterEdgeTts client in List<FlutterEdgeTts>.of(_active)) {
      await client.close();
    }
    _active.clear();
  }
}

class DeviceSpeechOutput implements SpeechOutput {
  DeviceSpeechOutput({AudioPlayer? audioPlayer, FlutterTts? systemTts})
    : _audioPlayer = audioPlayer ?? AudioPlayer(),
      _systemTts = systemTts ?? FlutterTts() {
    _systemTts.setCompletionHandler(_completePlayback);
    _systemTts.setCancelHandler(_completePlayback);
    _systemTts.setErrorHandler((_) => _completePlayback());
  }

  final AudioPlayer _audioPlayer;
  final FlutterTts _systemTts;
  Completer<void>? _activePlayback;
  bool _audioContextConfigured = false;

  @override
  Future<void> playAsset(String assetPath) async {
    await _play(AssetSource(assetPath));
  }

  @override
  Future<void> playFile(String filePath) async {
    await _play(DeviceFileSource(filePath));
  }

  Future<void> _play(Source source) async {
    await stop();
    if (!_audioContextConfigured) {
      await _audioPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.assistanceNavigationGuidance,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
      _audioContextConfigured = true;
    }
    final Completer<void> completion = Completer<void>();
    _activePlayback = completion;
    final StreamSubscription<void> subscription = _audioPlayer.onPlayerComplete
        .listen((_) => _completePlayback());
    try {
      await _audioPlayer.play(source);
      await completion.future.timeout(const Duration(seconds: 30));
    } finally {
      await subscription.cancel();
      if (identical(_activePlayback, completion)) {
        _activePlayback = null;
      }
    }
  }

  @override
  Future<void> speakSystem(String text, {bool offlineOnly = false}) async {
    await stop();
    final Completer<void> completion = Completer<void>();
    _activePlayback = completion;
    await _systemTts.setLanguage('zh-CN');
    if (offlineOnly) {
      final Object? available = await _systemTts.getVoices;
      final List<Object?> voices = available is List<Object?>
          ? available
          : const <Object?>[];
      Map<Object?, Object?>? selected;
      for (final Object? value in voices) {
        if (value is! Map<Object?, Object?>) {
          continue;
        }
        final String locale = '${value['locale'] ?? ''}'.toLowerCase();
        final Object? networkValue = value['network_required'];
        final bool requiresNetwork = networkValue == true ||
            '$networkValue'.toLowerCase() == 'true';
        if (locale.startsWith('zh') && !requiresNetwork) {
          selected = value;
          break;
        }
      }
      if (selected == null) {
        throw StateError('没有可用的离线系统语音');
      }
      await _systemTts.setVoice(<String, String>{
        'name': '${selected['name']}',
        'locale': '${selected['locale']}',
      });
    }
    await _systemTts.setSpeechRate(0.5);
    await _systemTts.setPitch(1.0);
    await _systemTts.setVolume(1.0);
    await _systemTts.setAudioAttributesForNavigation();
    final Object? result = await _systemTts.speak(text, focus: false);
    if (result != 1) {
      _completePlayback();
    }
    try {
      await completion.future.timeout(const Duration(seconds: 30));
    } finally {
      if (identical(_activePlayback, completion)) {
        _activePlayback = null;
      }
    }
  }

  void _completePlayback() {
    final Completer<void>? completion = _activePlayback;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }

  @override
  Future<void> stop() async {
    _completePlayback();
    await Future.wait<void>(<Future<void>>[
      _audioPlayer.stop(),
      _systemTts.stop().then((_) {}),
    ]);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }
}

class SpeechPromptCache {
  SpeechPromptCache({this.maxBytes = 64 * 1024 * 1024});

  SpeechPromptCache.inDirectory(
    this._directory, {
    this.maxBytes = 64 * 1024 * 1024,
  });

  static const int minimumAudioBytes = 128;
  static const String cacheVersion = 'v1';

  Directory? _directory;
  final int maxBytes;

  static String cacheKey(SpeechPrompt prompt) {
    final String input =
        '$cacheVersion|${prompt.text}|${prompt.voice}|24khz-48kbps-mono-mp3';
    return sha256.convert(input.codeUnits).toString();
  }

  Future<Directory> _resolveDirectory() async {
    _directory ??= Directory(
      p.join((await getTemporaryDirectory()).path, 'speech_prompts'),
    );
    await _directory!.create(recursive: true);
    return _directory!;
  }

  Future<File?> find(SpeechPrompt prompt) async {
    final Directory directory = await _resolveDirectory();
    final File file = File(p.join(directory.path, '${cacheKey(prompt)}.mp3'));
    if (!await _isValid(file)) {
      if (await file.exists()) {
        await file.delete();
      }
      return null;
    }
    await file.setLastModified(DateTime.now());
    return file;
  }

  Future<File> store(SpeechPrompt prompt, Uint8List bytes) async {
    if (!_hasMp3Header(bytes)) {
      throw const FormatException('Edge 返回的语音不是有效 MP3');
    }
    final Directory directory = await _resolveDirectory();
    final File file = File(p.join(directory.path, '${cacheKey(prompt)}.mp3'));
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
    await cleanup();
    return file;
  }

  Future<void> remove(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> cleanup() async {
    final Directory directory = await _resolveDirectory();
    final List<File> files = await directory
        .list()
        .where((FileSystemEntity entity) => entity is File)
        .cast<File>()
        .where((File file) => p.extension(file.path).toLowerCase() == '.mp3')
        .toList();
    final List<({File file, FileStat stat})> entries =
        <({File file, FileStat stat})>[];
    int total = 0;
    for (final File file in files) {
      final FileStat stat = await file.stat();
      total += stat.size;
      entries.add((file: file, stat: stat));
    }
    entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final entry in entries) {
      if (total <= maxBytes) {
        break;
      }
      await entry.file.delete();
      total -= entry.stat.size;
    }
  }

  Future<bool> _isValid(File file) async {
    if (!await file.exists() || await file.length() <= minimumAudioBytes) {
      return false;
    }
    final RandomAccessFile reader = await file.open();
    try {
      return _hasMp3Header(await reader.read(3), requirePayload: false);
    } finally {
      await reader.close();
    }
  }

  static bool _hasMp3Header(List<int> bytes, {bool requirePayload = true}) {
    if (bytes.length < 3 ||
        (requirePayload && bytes.length <= minimumAudioBytes)) {
      return false;
    }
    final bool id3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    final bool frameSync = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
    return id3 || frameSync;
  }
}
