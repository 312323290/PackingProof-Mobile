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

abstract interface class PreparableSpeechPromptSink {
  Future<void> prepare();
}

abstract interface class DynamicSpeechPromptSink {
  void enqueueText(
    String text, {
    SpeechPromptPriority priority = SpeechPromptPriority.normal,
    String? incidentKey,
  });
}

class _QueuedSpeechPrompt {
  _QueuedSpeechPrompt.fixed(SpeechPrompt value)
    : prompt = value,
      text = value.text,
      voice = value.voice,
      priority = value.priority;

  _QueuedSpeechPrompt.dynamic({
    required this.text,
    required this.voice,
    required this.priority,
  }) : prompt = null;

  final SpeechPrompt? prompt;
  final String text;
  final String voice;
  final SpeechPromptPriority priority;
}

abstract interface class SpeechOutput {
  Future<void> playAsset(String assetPath);

  Future<void> playFile(String filePath);

  Future<void> speakSystem(String text, {bool offlineOnly = false});

  Future<void> stop();

  Future<void> dispose();
}

abstract interface class PreparableSpeechOutput {
  Future<void> prepareAssets(Iterable<String> assetPaths);
}

abstract interface class EdgeSpeechGenerator {
  Future<Uint8List> synthesize({required String text, required String voice});
}

class SpeechPromptService
    implements
        SpeechPromptSink,
        PreparableSpeechPromptSink,
        DynamicSpeechPromptSink {
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
  final ListQueue<_QueuedSpeechPrompt> _queue =
      ListQueue<_QueuedSpeechPrompt>();
  final Set<String> _activeIncidents = <String>{};

  bool _enabled = true;
  bool _draining = false;
  bool _disposed = false;
  _QueuedSpeechPrompt? _activePrompt;
  Future<void>? _prepareFuture;

  @override
  Future<void> prepare() {
    return _prepareFuture ??= _prepareOutput();
  }

  Future<void> _prepareOutput() async {
    if (_output case final PreparableSpeechOutput output) {
      await output.prepareAssets(
        SpeechPrompt.values.map(
          (SpeechPrompt prompt) => prompt.audioPlayerAssetPath,
        ),
      );
    }
  }

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
        (_QueuedSpeechPrompt queued) =>
            queued.priority == SpeechPromptPriority.normal,
      );
      unawaited(_output.stop());
    } else if (prompt == SpeechPrompt.recordingStarted) {
      _queue.removeWhere(
        (_QueuedSpeechPrompt queued) => queued.prompt == SpeechPrompt.ready,
      );
      if (_activePrompt?.prompt == SpeechPrompt.ready) {
        unawaited(_output.stop());
      }
    } else if (prompt == SpeechPrompt.recordingStopped) {
      _queue.removeWhere(
        (_QueuedSpeechPrompt queued) =>
            queued.prompt == SpeechPrompt.ready ||
            queued.prompt == SpeechPrompt.recordingStarted,
      );
      if (_activePrompt?.prompt == SpeechPrompt.ready ||
          _activePrompt?.prompt == SpeechPrompt.recordingStarted) {
        unawaited(_output.stop());
      }
    }
    _queue.add(_QueuedSpeechPrompt.fixed(prompt));
    unawaited(_drain());
  }

  @override
  void enqueueText(
    String text, {
    SpeechPromptPriority priority = SpeechPromptPriority.normal,
    String? incidentKey,
  }) {
    final String normalized = text.trim();
    if (_disposed || !_enabled || normalized.isEmpty) return;
    if (priority == SpeechPromptPriority.warning) {
      final String key = incidentKey ?? 'dynamic:$normalized';
      if (!_activeIncidents.add(key)) return;
      _queue.removeWhere(
        (_QueuedSpeechPrompt queued) =>
            queued.priority == SpeechPromptPriority.normal,
      );
      unawaited(_output.stop());
    }
    _queue.add(
      _QueuedSpeechPrompt.dynamic(
        text: normalized,
        voice: priority == SpeechPromptPriority.warning
            ? SpeechPrompt.warningVoice
            : SpeechPrompt.normalVoice,
        priority: priority,
      ),
    );
    unawaited(_drain());
  }

  @override
  Future<void> preview() async {
    if (_disposed || !_enabled) {
      return;
    }
    await _output.stop();
    _queue.addFirst(_QueuedSpeechPrompt.fixed(SpeechPrompt.previewEnabled));
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
        final _QueuedSpeechPrompt prompt = _queue.removeFirst();
        _activePrompt = prompt;
        try {
          await _playWithFallback(prompt);
        } finally {
          if (_activePrompt == prompt) _activePrompt = null;
        }
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty && !_disposed && _enabled) {
        unawaited(_drain());
      }
    }
  }

  Future<void> _playWithFallback(_QueuedSpeechPrompt item) async {
    await prepare();
    final SpeechPrompt? prompt = item.prompt;
    if (prompt != null && await _hasBundledAsset(prompt)) {
      try {
        await _output.playAsset(prompt.audioPlayerAssetPath);
        return;
      } on Object {
        // A damaged package asset can still be repaired through the online cache.
      }
    }

    final File? cached = await _cache.findText(item.text, item.voice);
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
            .synthesize(text: item.text, voice: item.voice)
            .timeout(const Duration(seconds: 10));
        final File generated = await _cache.storeText(
          item.text,
          item.voice,
          bytes,
        );
        await _output.playFile(generated.path);
        return;
      } on Object {
        // Edge is best effort; Android system TTS is the final fallback.
      }
    }

    try {
      await _output.speakSystem(item.text, offlineOnly: offlineSystemTtsOnly);
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

class DeviceSpeechOutput implements SpeechOutput, PreparableSpeechOutput {
  DeviceSpeechOutput({
    AudioPlayer? audioPlayer,
    FlutterTts? systemTts,
    AudioCache? audioCache,
  }) : _audioPlayer = audioPlayer ?? AudioPlayer(),
       _systemTts = systemTts ?? FlutterTts(),
       _audioCache = audioCache ?? AudioCache(prefix: 'assets/') {
    _systemTts.setCompletionHandler(_completePlayback);
    _systemTts.setCancelHandler(_completePlayback);
    _systemTts.setErrorHandler((_) => _completePlayback());
  }

  final AudioPlayer _audioPlayer;
  final FlutterTts _systemTts;
  final AudioCache _audioCache;
  final Map<String, String> _preparedAssets = <String, String>{};
  Completer<void>? _activePlayback;
  bool _audioContextConfigured = false;

  @override
  Future<void> prepareAssets(Iterable<String> assetPaths) async {
    await _configureAudioContext();
    for (final String assetPath in assetPaths) {
      if (_preparedAssets.containsKey(assetPath)) continue;
      try {
        _preparedAssets[assetPath] = await _audioCache.loadPath(assetPath);
      } on Object {
        // AssetSource remains available when the temporary cache cannot be prepared.
      }
    }
  }

  @override
  Future<void> playAsset(String assetPath) async {
    final String? preparedPath = _preparedAssets[assetPath];
    await _play(
      preparedPath == null
          ? AssetSource(assetPath)
          : DeviceFileSource(preparedPath),
    );
  }

  @override
  Future<void> playFile(String filePath) async {
    await _play(DeviceFileSource(filePath));
  }

  Future<void> _play(Source source) async {
    await stop();
    await _configureAudioContext();
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

  Future<void> _configureAudioContext() async {
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
        final bool requiresNetwork =
            networkValue == true || '$networkValue'.toLowerCase() == 'true';
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
    try {
      await _audioCache.clearAll();
    } on Object {
      // Temporary audio cache cleanup is best effort.
    }
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
    return cacheKeyFor(prompt.text, prompt.voice);
  }

  static String cacheKeyFor(String text, String voice) {
    final String input = '$cacheVersion|$text|$voice|24khz-48kbps-mono-mp3';
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
    return findText(prompt.text, prompt.voice);
  }

  Future<File?> findText(String text, String voice) async {
    final Directory directory = await _resolveDirectory();
    final File file = File(
      p.join(directory.path, '${cacheKeyFor(text, voice)}.mp3'),
    );
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
    return storeText(prompt.text, prompt.voice, bytes);
  }

  Future<File> storeText(String text, String voice, Uint8List bytes) async {
    if (!_hasMp3Header(bytes)) {
      throw const FormatException('Edge 返回的语音不是有效 MP3');
    }
    final Directory directory = await _resolveDirectory();
    final File file = File(
      p.join(directory.path, '${cacheKeyFor(text, voice)}.mp3'),
    );
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
