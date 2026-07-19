import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/barcode_marker.dart';
import '../models/app_settings.dart';
import '../models/backup_retention_policy.dart';
import '../models/lan_backup.dart';
import '../models/recording_session.dart';
import '../models/speech_prompt.dart';
import '../models/work_mode.dart';
import '../services/barcode_candidate_policy.dart';
import '../services/barcode_stability_tracker.dart';
import '../services/barcode_work_mode_policy.dart';
import '../services/continuous_camera_service.dart';
import '../services/initial_recording_prompt_policy.dart';
import '../services/lan_backup_service.dart';
import '../services/max_volume_service.dart';
import '../services/nv21_center_crop.dart';
import '../services/recording_timeline.dart';
import '../services/session_repository.dart';
import '../services/speech_prompt_service.dart';
import '../services/video_watermark_service.dart';

enum PackingSessionPhase {
  initializing,
  ready,
  waitingForBarcode,
  starting,
  recording,
  saving,
  error,
}

class PackingSessionController extends ChangeNotifier {
  PackingSessionController({
    SessionRepository? repository,
    SpeechPromptSink? speechService,
    MaxVolumeSink? maxVolumeService,
    LanBackupSink? lanBackupService,
    VideoWatermarkSink? videoWatermarkService,
  }) : _repository = repository ?? SessionRepository(),
       _speechService = speechService ?? SpeechPromptService(),
       _maxVolumeService = maxVolumeService ?? MaxVolumeService(),
       _lanBackupService = lanBackupService ?? LanBackupService(),
       _videoWatermarkService =
           videoWatermarkService ?? VideoWatermarkService(),
       _barcodeScanner = BarcodeScanner(
         formats: const <BarcodeFormat>[BarcodeFormat.all],
       );

  static const Duration analysisInterval = Duration(milliseconds: 200);
  static const Duration transitionSettleDelay = Duration(milliseconds: 120);
  static const Duration initialReadyPromptDelay = Duration(milliseconds: 250);
  static const int recordingFps = 30;

  final SessionRepository _repository;
  final SpeechPromptSink _speechService;
  final MaxVolumeSink _maxVolumeService;
  final LanBackupSink _lanBackupService;
  final VideoWatermarkSink _videoWatermarkService;
  final BarcodeScanner _barcodeScanner;
  final BarcodeStabilityTracker _stabilityTracker = BarcodeStabilityTracker();
  final RecordingTimeline _timeline = RecordingTimeline();
  final InitialRecordingPromptPolicy _initialPromptPolicy =
      InitialRecordingPromptPolicy();

  CameraController? _cameraController;
  ContinuousCameraService? _nativeCamera;
  ContinuousCameraInitialization? _nativeInitialization;
  PackingSessionPhase _phase = PackingSessionPhase.initializing;
  List<RecordingSession> _sessions = <RecordingSession>[];
  DateTime _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _elapsedTimer;
  Timer? _feedbackTimer;
  Timer? _initialPromptTimer;
  Timer? _pairingFeedbackTimer;
  Duration _elapsed = Duration.zero;
  BarcodeMarker? _lastMarker;
  String _candidateCode = '';
  WorkMode _workMode = WorkMode.continuousScan;
  bool _speechEnabled = true;
  bool _maxVolumeEnabled = true;
  UnbackedRetentionPolicy _unbackedRetention = UnbackedRetentionPolicy.days30;
  BackedRetentionPolicy _backedRetention = BackedRetentionPolicy.days7;
  bool _appIsActive = true;
  String? _errorMessage;
  bool _processingFrame = false;
  bool _handlingBarcode = false;
  bool _disposed = false;
  bool _pairingScanActive = false;
  bool _historyScanActive = false;
  bool _pairingBusy = false;
  bool _backupListenerAttached = false;
  final Set<String> _handledDeletedBackupJobs = <String>{};
  String? _pairingMessage;
  String? _historyScanResult;
  String? _recordingId;
  String? _activeSegmentId;
  int _segmentIndex = 1;
  bool _torchEnabled = false;
  bool _workActive = false;
  int _pairingSuccessRevision = 0;
  Set<int> _hiddenRemoteRecordingIds = <int>{};

  CameraController? get cameraController => _cameraController;
  int? get nativeTextureId => _nativeInitialization?.textureId;
  Size? get nativePreviewSize => _nativeInitialization?.portraitPreviewSize;
  PackingSessionPhase get phase => _phase;
  List<RecordingSession> get sessions =>
      List<RecordingSession>.unmodifiable(_sessions);
  Duration get elapsed => _elapsed;
  BarcodeMarker? get lastMarker => _lastMarker;
  String get candidateCode => _candidateCode;
  String get currentCode => _timeline.currentCode;
  WorkMode get workMode => _workMode;
  bool get speechEnabled => _speechEnabled;
  bool get maxVolumeEnabled => _maxVolumeEnabled;
  UnbackedRetentionPolicy get unbackedRetention => _unbackedRetention;
  BackedRetentionPolicy get backedRetention => _backedRetention;
  LanBackupSnapshot get backupSnapshot => _lanBackupService.snapshot;
  bool get pairingScanActive => _pairingScanActive;
  int get pairingSuccessRevision => _pairingSuccessRevision;
  String? get pairingMessage => _pairingMessage;
  bool get historyScanActive => _historyScanActive;
  bool get flashAvailable => Platform.isAndroid
      ? _nativeInitialization?.flashAvailable == true
      : _cameraController?.value.isInitialized == true;
  bool get torchEnabled => _torchEnabled;
  bool get cameraSwitchAvailable =>
      Platform.isAndroid &&
      _nativeInitialization?.canSwitchCamera == true &&
      !_pairingScanActive &&
      !_historyScanActive;
  bool get frontCameraActive =>
      Platform.isAndroid && _nativeInitialization?.isFrontCamera == true;
  String? get historyScanResult => _historyScanResult;
  String? get errorMessage => _errorMessage;
  bool get isRecording => _phase == PackingSessionPhase.recording;
  bool get isWorking => _workActive;
  Set<int> get hiddenRemoteRecordingIds =>
      Set<int>.unmodifiable(_hiddenRemoteRecordingIds);
  bool get isBusy =>
      _phase == PackingSessionPhase.initializing ||
      _phase == PackingSessionPhase.starting ||
      _phase == PackingSessionPhase.saving;
  bool get isCameraReady =>
      (Platform.isAndroid
          ? _nativeInitialization != null
          : _cameraController?.value.isInitialized == true) &&
      _phase != PackingSessionPhase.error;

  Future<void> initialize() async {
    if (_disposed || isCameraReady) {
      return;
    }
    _setPhase(PackingSessionPhase.initializing);
    _errorMessage = null;

    try {
      await _repository.initialize();
      _sessions = await _repository.loadSessions(includeMissingFiles: true);
      final AppSettings settings = await _repository.loadSettings();
      _workMode = settings.workMode;
      _speechEnabled = settings.speechEnabled;
      _maxVolumeEnabled = settings.maxVolumeEnabled;
      _unbackedRetention = settings.unbackedRetention;
      _backedRetention = settings.backedRetention;
      _hiddenRemoteRecordingIds = Set<int>.of(
        settings.hiddenRemoteRecordingIds,
      );
      if (!_backupListenerAttached) {
        _lanBackupService.addListener(_handleBackupChanged);
        _backupListenerAttached = true;
      }
      await _lanBackupService.initialize(
        autoEnabled: settings.lanBackupAutoEnabled,
        unbackedRetention: settings.unbackedRetention,
        backedRetention: settings.backedRetention,
      );
      await _pruneDeletedBackupSessions(notify: false);
      if (_lanBackupService.snapshot.autoEnabled) {
        unawaited(_lanBackupService.backupAll(_sessions));
      } else {
        unawaited(_registerSessionsForRetention(_sessions));
      }
      await _speechService.setEnabled(_speechEnabled);
      if (_speechService case final PreparableSpeechPromptSink speechService) {
        unawaited(speechService.prepare());
      }
      await _beginMaxVolumeIfNeeded();
      if (Platform.isAndroid) {
        final ContinuousCameraService nativeCamera = ContinuousCameraService();
        nativeCamera.onBarcodeFrame = _processNativeBarcodeFrame;
        nativeCamera.onError = (String message) {
          _errorMessage = message;
          _speakErrorMessage(message);
          if (!_disposed) {
            notifyListeners();
          }
        };
        _nativeCamera = nativeCamera;
        _nativeInitialization = await nativeCamera.initialize();
        _speechService.resetIncidents();
        _setPhase(PackingSessionPhase.ready);
        return;
      }
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', '没有检测到可用摄像头');
      }
      final CameraDescription selected = cameras.firstWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        selected,
        ResolutionPreset.veryHigh,
        enableAudio: true,
        fps: recordingFps,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      _cameraController = controller;
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await controller.setFlashMode(FlashMode.off);
      } on CameraException {
        // Some tablets and emulators expose a camera without a controllable flash.
      }
      _setPhase(PackingSessionPhase.ready);
      _speechService.resetIncidents();
    } on CameraException catch (error) {
      _setCameraError(error);
    } on Object catch (error) {
      _errorMessage = '摄像头初始化失败，请重试\n$error';
      _setPhase(PackingSessionPhase.error);
    }
  }

  Future<void> retryInitialize() async {
    await _disposeCamera();
    await initialize();
  }

  Future<void> toggleTorch() async {
    if (!flashAvailable || isBusy) return;
    final bool enabled = !_torchEnabled;
    try {
      if (Platform.isAndroid) {
        _torchEnabled = await _nativeCamera!.setTorchEnabled(enabled);
      } else {
        await _cameraController!.setFlashMode(
          enabled ? FlashMode.torch : FlashMode.off,
        );
        _torchEnabled = enabled;
      }
      notifyListeners();
    } on Object {
      _torchEnabled = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> switchCamera() async {
    if (!cameraSwitchAvailable || isBusy || isWorking) return;
    try {
      if (_torchEnabled) {
        await _nativeCamera!.setTorchEnabled(false);
        _torchEnabled = false;
      }
      _errorMessage = null;
      _setPhase(PackingSessionPhase.initializing);
      _nativeInitialization = await _nativeCamera!.switchCamera();
      _setPhase(PackingSessionPhase.ready);
    } on Object {
      await _disposeCamera();
      await initialize();
      if (!_disposed) {
        _errorMessage = '摄像头切换失败，已恢复后置摄像头';
        notifyListeners();
      }
    }
  }

  Future<void> startWork() async {
    final CameraController? camera = _cameraController;
    final bool cameraUnavailable = Platform.isAndroid
        ? _nativeInitialization == null
        : camera == null || !camera.value.isInitialized;
    if (cameraUnavailable || isBusy || isWorking) {
      return;
    }

    await _boostMaxVolumeIfNeeded();

    _errorMessage = null;
    _lastMarker = null;
    _candidateCode = '';
    _timeline.reset();
    _stabilityTracker.reset();
    _speechService.resetIncidents();
    _beginInitialPromptFlow();

    try {
      await WakelockPlus.enable();
      await _setNativeWorkScanEnabled(true);
      _workActive = true;
      _elapsed = Duration.zero;
      _setPhase(PackingSessionPhase.waitingForBarcode);
      _scheduleInitialReadyPrompt();
    } on CameraException catch (error) {
      await _setNativeWorkScanEnabled(false);
      _cancelInitialPromptFlow();
      _workActive = false;
      _timeline.reset();
      await WakelockPlus.disable();
      _setCameraError(error);
    } on Object catch (error) {
      await _setNativeWorkScanEnabled(false);
      _cancelInitialPromptFlow();
      _workActive = false;
      _timeline.reset();
      await WakelockPlus.disable();
      _errorMessage = '无法开始录像，请重新检查摄像头\n$error';
      _setPhase(PackingSessionPhase.error);
      _speakErrorMessage(error.toString());
    }
  }

  Future<RecordingSession?> stopWork() async {
    if (!isWorking) {
      return null;
    }
    final CameraController? camera = _cameraController;
    final DateTime? startedAt = _timeline.recordingStartedAt;
    final bool recordingUnavailable = Platform.isAndroid
        ? _nativeCamera == null
        : camera == null || !camera.value.isRecordingVideo;
    if (startedAt == null) {
      _cancelInitialPromptFlow();
      await _setNativeWorkScanEnabled(false);
      _workActive = false;
      _candidateCode = '';
      _stabilityTracker.reset();
      await WakelockPlus.disable();
      _setPhase(PackingSessionPhase.ready);
      return null;
    }
    if (recordingUnavailable) {
      return null;
    }
    _cancelInitialPromptFlow();
    await _setNativeWorkScanEnabled(false);

    _setPhase(PackingSessionPhase.saving);
    await WidgetsBinding.instance.endOfFrame;

    try {
      final List<RecordingSession> savedSessions = Platform.isAndroid
          ? await _finishNativeRecording()
          : await _finishRecording();
      _candidateCode = '';
      _stabilityTracker.reset();
      _workActive = false;
      await WakelockPlus.disable();
      await Future<void>.delayed(transitionSettleDelay);
      _setPhase(PackingSessionPhase.ready);
      _speechService.resetIncidents();
      _speechService.enqueue(SpeechPrompt.recordingStopped);
      return savedSessions.isEmpty ? null : savedSessions.last;
    } on Object catch (error) {
      _timeline.reset();
      _workActive = false;
      await WakelockPlus.disable();
      _errorMessage = '录像保存失败，请保留应用并重试\n$error';
      _setPhase(PackingSessionPhase.error);
      _speakErrorMessage(error.toString());
      return null;
    }
  }

  Future<void> setWorkMode(WorkMode mode) async {
    if (_workMode == mode || isWorking || isBusy) {
      return;
    }
    _workMode = mode;
    notifyListeners();
    await _repository.saveWorkMode(mode);
  }

  Future<void> setSpeechEnabled(bool enabled) async {
    if (_speechEnabled == enabled) {
      return;
    }
    _speechEnabled = enabled;
    notifyListeners();
    await _speechService.setEnabled(enabled);
    await _repository.saveSpeechEnabled(enabled);
  }

  Future<void> setMaxVolumeEnabled(bool enabled) async {
    if (_maxVolumeEnabled == enabled) {
      return;
    }
    _maxVolumeEnabled = enabled;
    notifyListeners();
    if (enabled) {
      await _beginMaxVolumeIfNeeded();
    } else {
      await _disableMaxVolume();
    }
    await _repository.saveMaxVolumeEnabled(enabled);
  }

  Future<void> setLanBackupAutoEnabled(bool enabled) async {
    await _lanBackupService.setAutoEnabled(enabled);
    await _repository.saveLanBackupAutoEnabled(enabled);
    if (enabled) {
      await _lanBackupService.backupAll(_sessions);
    }
  }

  Future<void> setBackupRetention({
    required UnbackedRetentionPolicy unbacked,
    required BackedRetentionPolicy backed,
  }) async {
    _unbackedRetention = unbacked;
    _backedRetention = backed;
    notifyListeners();
    await _lanBackupService.setRetentionPolicies(
      unbacked: unbacked,
      backed: backed,
    );
    await _repository.saveBackupRetention(unbacked: unbacked, backed: backed);
  }

  void beginComputerPairing() {
    if (isWorking || isBusy) {
      return;
    }
    _pairingScanActive = true;
    _pairingMessage = '将电脑上的二维码放入框内';
    _stabilityTracker.reset();
    unawaited(_nativeCamera?.setPairingScanEnabled(true));
    notifyListeners();
  }

  void cancelComputerPairing() {
    _pairingFeedbackTimer?.cancel();
    _pairingScanActive = false;
    _pairingBusy = false;
    _pairingMessage = null;
    unawaited(_nativeCamera?.setPairingScanEnabled(false));
    notifyListeners();
  }

  void beginHistoryBarcodeScan() {
    if (isWorking || isBusy) return;
    _historyScanResult = null;
    _historyScanActive = true;
    _stabilityTracker.reset();
    unawaited(_nativeCamera?.setPairingScanEnabled(true));
    notifyListeners();
  }

  void cancelHistoryBarcodeScan() {
    _historyScanActive = false;
    unawaited(_nativeCamera?.setPairingScanEnabled(false));
    notifyListeners();
  }

  void clearHistoryScanResult() => _historyScanResult = null;

  Future<void> backupAllSessions() => _lanBackupService.backupAll(_sessions);

  Future<void> disconnectBackup() => _lanBackupService.disconnect();

  Future<void> retryBackupConnection() async {
    final bool connected = await _lanBackupService.retryConnection();
    if (connected && _lanBackupService.snapshot.autoEnabled) {
      await _lanBackupService.backupAll(_sessions);
    }
  }

  Future<void> retryBackup(String jobId) => _lanBackupService.retry(jobId);

  Future<RemoteRecordingPage> fetchRemoteRecordings({
    required int page,
    required int pageSize,
    String keyword = '',
  }) => _lanBackupService.fetchRemoteRecordings(
    page: page,
    pageSize: pageSize,
    keyword: keyword,
  );

  Future<Map<int, ({RemoteRecordingStatus status, bool exists, String reason})>>
  fetchRemoteRecordingStatuses(Iterable<int> ids) =>
      _lanBackupService.fetchRemoteRecordingStatuses(ids);

  Map<String, String> get remotePlaybackHeaders =>
      _lanBackupService.playbackHeaders;

  Future<void> previewSpeech() => _speechService.preview();

  Future<void> _startRecording() async {
    if (Platform.isAndroid) {
      await _startNativeRecording();
      return;
    }
    final CameraController? camera = _cameraController;
    if (camera == null || !camera.value.isInitialized) {
      throw CameraException('CameraNotReady', '摄像头尚未准备完成');
    }

    final DateTime startedAt = DateTime.now();
    _timeline.start(startedAt);
    _elapsed = Duration.zero;
    _setPhase(PackingSessionPhase.starting);
    await WidgetsBinding.instance.endOfFrame;
    await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
    await camera.startVideoRecording(
      onAvailable: _processFrame,
      enablePersistentRecording: true,
    );
    try {
      await camera.setFocusMode(FocusMode.auto);
      await camera.setFocusPoint(const Offset(0.5, 0.52));
      await camera.setExposurePoint(const Offset(0.5, 0.52));
    } on CameraException {
      // Some devices keep continuous autofocus without exposing focus points.
    }
    await Future<void>.delayed(transitionSettleDelay);
    _setPhase(PackingSessionPhase.recording);
    _startElapsedTimer();
  }

  Future<void> _startNativeRecording() async {
    final ContinuousCameraService? camera = _nativeCamera;
    if (camera == null || _nativeInitialization == null) {
      throw StateError('摄像头尚未准备完成');
    }
    _setPhase(PackingSessionPhase.starting);
    await WidgetsBinding.instance.endOfFrame;
    final String recordingId = _sessionId(DateTime.now());
    final String path = await _repository.recordingPath(recordingId);
    final NativeRecordingStart started = await camera.startWork(path);
    _recordingId = recordingId;
    _activeSegmentId = recordingId;
    _segmentIndex = 1;
    _timeline.start(started.startedAt);
    _elapsed = Duration.zero;
    _setPhase(PackingSessionPhase.recording);
    _startElapsedTimer();
  }

  Future<List<RecordingSession>> _finishRecording() async {
    final CameraController camera = _cameraController!;
    final DateTime startedAt = _timeline.recordingStartedAt!;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    final XFile captured = await camera.stopVideoRecording();
    final DateTime endedAt = DateTime.now();
    final String sessionId = _sessionId(startedAt);
    final List<RecordingSession> drafts = _timeline.buildSessions(
      endedAt: endedAt,
      filePath: captured.path,
      recordingId: sessionId,
    );
    final String savedPath = await _repository.finalizeVideo(
      sourcePath: captured.path,
      sessionId: sessionId,
      startedAt: startedAt,
      trackingNumber: _firstTrackingNumber(drafts),
    );
    final List<RecordingSession> sessions = drafts
        .map((RecordingSession draft) => _sessionWithPath(draft, savedPath))
        .toList(growable: false);
    _sessions = await _repository.addSessions(sessions);
    await _enqueueBackupIfNeeded(savedPath, sessions);
    _elapsed = endedAt.difference(startedAt);
    _timeline.reset();
    return sessions;
  }

  Future<List<RecordingSession>> _finishNativeRecording() async {
    final ContinuousCameraService camera = _nativeCamera!;
    final String segmentId = _activeSegmentId!;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    final NativeRecordingStop stopped = await camera.stopWork();
    final RecordingSegmentDraft? draft = _timeline.finish(stopped.endedAt);
    if (draft == null) {
      throw StateError('找不到当前录像片段');
    }
    final String watermarkedPath = await _videoWatermarkService.apply(
      inputPath: stopped.path,
      startedAt: draft.startedAt,
      trackingNumber: draft.markers.isEmpty ? '' : draft.markers.first.code,
    );
    final String savedPath = await _repository.finalizeVideo(
      sourcePath: watermarkedPath,
      sessionId: segmentId,
      startedAt: draft.startedAt,
      trackingNumber: draft.markers.isEmpty ? '' : draft.markers.first.code,
    );
    final RecordingSession session = _standaloneSession(
      id: segmentId,
      path: savedPath,
      draft: draft,
    );
    _sessions = await _repository.addSession(session);
    await _enqueueBackupIfNeeded(savedPath, <RecordingSession>[session]);
    _elapsed = stopped.endedAt.difference(_timeline.recordingStartedAt!);
    _timeline.reset();
    _recordingId = null;
    _activeSegmentId = null;
    return <RecordingSession>[session];
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final DateTime? startedAt = _timeline.segmentStartedAt;
      if (startedAt == null || _disposed) {
        return;
      }
      _elapsed = DateTime.now().difference(startedAt);
      notifyListeners();
    });
  }

  Future<void> handleInactive() async {
    _appIsActive = false;
    if (isWorking) {
      await stopWork();
    }
    if (_phase != PackingSessionPhase.saving) {
      await _disposeCamera();
    }
    await _endMaxVolumeSession();
  }

  Future<void> handleResumed() async {
    _appIsActive = true;
    await _beginMaxVolumeIfNeeded();
    final bool needsInitialization = Platform.isAndroid
        ? _nativeInitialization == null
        : _cameraController?.value.isInitialized != true;
    if (needsInitialization && _phase != PackingSessionPhase.saving) {
      await initialize();
    }
  }

  Future<void> _beginMaxVolumeIfNeeded() async {
    if (!_maxVolumeEnabled || !_appIsActive) {
      return;
    }
    try {
      await _maxVolumeService.beginSession();
    } on Object {
      // Volume convenience must never block the camera workflow.
    }
  }

  Future<void> setPreviewActive(bool active) async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeCamera?.setPreviewActive(active);
    } on Object {
      // Preview power tuning must never block navigation or recording.
    }
  }

  Future<void> _setNativeWorkScanEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeCamera?.setWorkScanEnabled(enabled);
    } on Object {
      if (enabled) rethrow;
    }
  }

  Future<void> _endMaxVolumeSession() async {
    try {
      await _maxVolumeService.endSession();
    } on Object {
      // Android may already have released the activity during shutdown.
    }
  }

  Future<void> _disableMaxVolume() async {
    try {
      await _maxVolumeService.disable();
    } on Object {
      // Volume convenience must never block settings persistence.
    }
  }

  Future<void> _boostMaxVolumeIfNeeded() async {
    if (!_maxVolumeEnabled || !_appIsActive) {
      return;
    }
    try {
      await _maxVolumeService.boost();
    } on Object {
      // Volume convenience must never block recording startup.
    }
  }

  Future<void> refreshSessions() async {
    _sessions = await _repository.loadSessions(includeMissingFiles: true);
    notifyListeners();
  }

  Future<void> updateSession(RecordingSession session) async {
    _sessions = await _repository.updateSession(session);
    notifyListeners();
  }

  Future<void> deleteSessions(Set<String> sessionIds) async {
    _sessions = await _repository.deleteSessions(sessionIds);
    notifyListeners();
  }

  Future<void> hideRemoteRecordings(Set<int> ids) async {
    if (ids.isEmpty) return;
    _hiddenRemoteRecordingIds = <int>{..._hiddenRemoteRecordingIds, ...ids};
    await _repository.saveHiddenRemoteRecordingIds(_hiddenRemoteRecordingIds);
    notifyListeners();
  }

  void _processNativeBarcodeFrame(List<NativeBarcodeCandidate> candidates) {
    if (_historyScanActive) {
      NativeBarcodeCandidate? match;
      for (final NativeBarcodeCandidate candidate in candidates) {
        if (BarcodeCandidatePolicy.isValid(candidate.value)) {
          match = candidate;
          break;
        }
      }
      if (match != null) {
        _historyScanResult = BarcodeCandidatePolicy.normalize(match.value);
        _historyScanActive = false;
        unawaited(_nativeCamera?.setPairingScanEnabled(false));
        notifyListeners();
      }
      return;
    }
    if (_pairingScanActive) {
      if (!_pairingBusy) {
        for (final NativeBarcodeCandidate candidate in candidates) {
          unawaited(_tryPairComputer(candidate.value));
          break;
        }
      }
      return;
    }
    if (!isWorking || isBusy || _handlingBarcode) {
      return;
    }
    String? validCode;
    int largestArea = -1;
    for (final NativeBarcodeCandidate candidate in candidates) {
      if (BarcodeCandidatePolicy.isValid(candidate.value) &&
          candidate.area > largestArea) {
        largestArea = candidate.area;
        validCode = BarcodeCandidatePolicy.normalize(candidate.value);
      }
    }
    final DateTime now = DateTime.now();
    final BarcodeObservation observation = _stabilityTracker.observe(
      validCode,
      now,
    );
    if (observation.confirmedCode.isNotEmpty) {
      _candidateCode = '';
      unawaited(_handleConfirmedBarcode(observation.confirmedCode, now));
    } else if (observation.candidateCode != _candidateCode) {
      _candidateCode = observation.candidateCode;
      notifyListeners();
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processingFrame || !isWorking || isBusy || _handlingBarcode) {
      return;
    }
    final DateTime now = DateTime.now();
    if (now.difference(_lastAnalysisAt) < analysisInterval) {
      return;
    }
    _lastAnalysisAt = now;
    _processingFrame = true;

    try {
      final InputImageRotation? rotation = _inputImageRotation(
        _cameraController!.description,
        _cameraController!.value.deviceOrientation,
      );
      if (rotation == null) {
        return;
      }
      final InputImage? inputImage = _toInputImage(image, rotation: rotation);
      if (inputImage == null) {
        return;
      }
      List<Barcode> barcodes = await _barcodeScanner.processImage(inputImage);
      if (barcodes.isEmpty && Platform.isAndroid) {
        final InputImage? croppedInput = _toCroppedInputImage(
          image,
          rotation: rotation,
        );
        if (croppedInput != null) {
          barcodes = await _barcodeScanner.processImage(croppedInput);
        }
      }
      String? validCode;
      double largestArea = -1;
      for (final Barcode barcode in barcodes) {
        if (BarcodeCandidatePolicy.isValid(barcode.rawValue)) {
          final double area =
              barcode.boundingBox.width.abs() *
              barcode.boundingBox.height.abs();
          if (area > largestArea) {
            largestArea = area;
            validCode = BarcodeCandidatePolicy.normalize(barcode.rawValue);
          }
        }
      }

      final BarcodeObservation observation = _stabilityTracker.observe(
        validCode,
        now,
      );
      if (observation.confirmedCode.isNotEmpty) {
        _candidateCode = '';
        unawaited(_handleConfirmedBarcode(observation.confirmedCode, now));
      } else if (observation.candidateCode != _candidateCode) {
        _candidateCode = observation.candidateCode;
        notifyListeners();
      }
    } on Object {
      // A malformed analysis frame should not interrupt recording.
    } finally {
      _processingFrame = false;
    }
  }

  InputImage? _toInputImage(
    CameraImage image, {
    required InputImageRotation rotation,
  }) {
    if (image.planes.length != 1) {
      return null;
    }

    final Plane plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImage? _toCroppedInputImage(
    CameraImage image, {
    required InputImageRotation rotation,
  }) {
    if (image.planes.length != 1) {
      return null;
    }
    final Plane plane = image.planes.first;
    final Nv21CropResult? crop = cropNv21Center(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
    );
    if (crop == null) {
      return null;
    }
    return InputImage.fromBytes(
      bytes: crop.bytes,
      metadata: InputImageMetadata(
        size: Size(crop.width.toDouble(), crop.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: crop.width,
      ),
    );
  }

  InputImageRotation? _inputImageRotation(
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    }

    const Map<DeviceOrientation, int> compensations = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final int? compensation = compensations[orientation];
    if (compensation == null) {
      return null;
    }
    final int rotation = camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + compensation) % 360
        : (camera.sensorOrientation - compensation + 360) % 360;
    return InputImageRotationValue.fromRawValue(rotation);
  }

  Future<void> _handleConfirmedBarcode(String code, DateTime now) async {
    if (_handlingBarcode || !isWorking || isBusy) {
      return;
    }
    if (!isRecording || !_timeline.isActive) {
      _handlingBarcode = true;
      try {
        await _startRecording();
        _bindCurrentCode(code, _timeline.segmentStartedAt ?? now);
      } on Object catch (error) {
        _timeline.reset();
        _errorMessage = '无法开始录像，请重新对准面单\n$error';
        _setPhase(PackingSessionPhase.waitingForBarcode);
        _speechService.enqueue(
          SpeechPrompt.recordingFailed,
          incidentKey: SpeechPrompt.recordingFailed.name,
        );
      } finally {
        _handlingBarcode = false;
      }
      return;
    }
    final BarcodeWorkAction action = BarcodeWorkModePolicy.decide(
      mode: _workMode,
      currentCode: _timeline.currentCode,
      scannedCode: code,
    );
    switch (action) {
      case BarcodeWorkAction.bindCurrentVideo:
        _bindCurrentCode(code, now);
        return;
      case BarcodeWorkAction.ignore:
        _candidateCode = '';
        notifyListeners();
        return;
      case BarcodeWorkAction.stopVideo:
        _handlingBarcode = true;
        try {
          await _saveCurrentVideoAndWait();
        } finally {
          _handlingBarcode = false;
        }
        return;
      case BarcodeWorkAction.startNextVideo:
        _handlingBarcode = true;
        try {
          bool announced = false;
          void announceSegmentStarted(BarcodeMarker marker) {
            announced = true;
            _speechService.resolveIncident(SpeechPrompt.segmentSaveFailed.name);
            _speechService.enqueue(SpeechPrompt.recordingStarted);
            _showMarkerFeedback(marker);
          }

          final BarcodeMarker? marker = Platform.isAndroid
              ? await _splitNativeRecording(
                  code,
                  onSegmentStarted: announceSegmentStarted,
                )
              : _startNextTimelineSegment(code, now);
          if (marker != null && !announced) {
            announceSegmentStarted(marker);
          }
        } on Object catch (error) {
          _errorMessage = '录像分段保存失败\n$error';
          _speechService.enqueue(
            SpeechPrompt.segmentSaveFailed,
            incidentKey: SpeechPrompt.segmentSaveFailed.name,
          );
          if (!_disposed) {
            notifyListeners();
          }
        } finally {
          _handlingBarcode = false;
        }
        return;
    }
  }

  Future<RecordingSession?> _saveCurrentVideoAndWait() async {
    if (!isWorking || !isRecording || !_timeline.isActive) {
      return null;
    }
    _cancelInitialPromptFlow();
    _setPhase(PackingSessionPhase.saving);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final List<RecordingSession> savedSessions = Platform.isAndroid
          ? await _finishNativeRecording()
          : await _finishRecording();
      _candidateCode = '';
      _elapsed = Duration.zero;
      await Future<void>.delayed(transitionSettleDelay);
      _setPhase(PackingSessionPhase.waitingForBarcode);
      _speechService.resetIncidents();
      _speechService.enqueue(SpeechPrompt.recordingStopped);
      return savedSessions.isEmpty ? null : savedSessions.last;
    } on Object catch (error) {
      _timeline.reset();
      _workActive = false;
      await WakelockPlus.disable();
      _errorMessage = '录像保存失败，请保留应用并重试\n$error';
      _setPhase(PackingSessionPhase.error);
      _speakErrorMessage(error.toString());
      return null;
    }
  }

  Future<BarcodeMarker?> _splitNativeRecording(
    String code, {
    required void Function(BarcodeMarker marker) onSegmentStarted,
  }) async {
    final ContinuousCameraService? camera = _nativeCamera;
    final String? recordingId = _recordingId;
    final String? completedId = _activeSegmentId;
    if (camera == null || recordingId == null || completedId == null) {
      return null;
    }
    final int nextIndex = _segmentIndex + 1;
    final String nextId =
        '${recordingId}_${nextIndex.toString().padLeft(3, '0')}';
    final String nextPath = await _repository.recordingPath(nextId);
    final NativeRecordingSplit split = await camera.split(nextPath);
    final RecordingSegmentTransition? transition = _timeline.startNext(
      code,
      split.boundaryAt,
    );
    if (transition == null) {
      throw StateError('录像时间线无法开始下一段');
    }
    _resetSegmentElapsed();
    onSegmentStarted(transition.marker);
    final String watermarkedPath = await _videoWatermarkService.apply(
      inputPath: split.completedPath,
      startedAt: transition.completed.startedAt,
      trackingNumber: transition.completed.markers.isEmpty
          ? ''
          : transition.completed.markers.first.code,
    );
    final String savedPath = await _repository.finalizeVideo(
      sourcePath: watermarkedPath,
      sessionId: completedId,
      startedAt: transition.completed.startedAt,
      trackingNumber: transition.completed.markers.isEmpty
          ? ''
          : transition.completed.markers.first.code,
    );
    final RecordingSession completed = _standaloneSession(
      id: completedId,
      path: savedPath,
      draft: transition.completed,
    );
    _sessions = await _repository.addSession(completed);
    await _enqueueBackupIfNeeded(savedPath, <RecordingSession>[completed]);
    _activeSegmentId = nextId;
    _segmentIndex = nextIndex;
    return transition.marker;
  }

  BarcodeMarker? _startNextTimelineSegment(String code, DateTime boundaryAt) {
    final RecordingSegmentTransition? transition = _timeline.startNext(
      code,
      boundaryAt,
    );
    if (transition != null) {
      _resetSegmentElapsed();
    }
    return transition?.marker;
  }

  void _resetSegmentElapsed() {
    _elapsed = Duration.zero;
    notifyListeners();
  }

  RecordingSession _standaloneSession({
    required String id,
    required String path,
    required RecordingSegmentDraft draft,
  }) {
    return RecordingSession(
      id: id,
      filePath: path,
      startedAt: draft.startedAt,
      endedAt: draft.endedAt,
      markers: List<BarcodeMarker>.unmodifiable(draft.markers),
    );
  }

  static String _firstTrackingNumber(List<RecordingSession> sessions) {
    for (final RecordingSession session in sessions) {
      if (session.markers.isNotEmpty && session.markers.first.code.isNotEmpty) {
        return session.markers.first.code;
      }
    }
    return '';
  }

  static RecordingSession _sessionWithPath(
    RecordingSession session,
    String filePath,
  ) => RecordingSession(
    id: session.id,
    filePath: filePath,
    startedAt: session.startedAt,
    endedAt: session.endedAt,
    markers: session.markers,
    mediaStart: session.mediaStart,
    mediaEnd: session.mediaEnd,
  );

  void _bindCurrentCode(String code, DateTime now) {
    final BarcodeMarker? marker = _timeline.bindCode(code, now);
    if (marker == null) {
      return;
    }
    _announceInitialRecordingStarted();
    _showMarkerFeedback(marker);
  }

  Future<void> _tryPairComputer(String value) async {
    if (_pairingBusy || !_pairingScanActive) {
      return;
    }
    _pairingBusy = true;
    final bool isComputerQr = _looksLikeComputerPairingQr(value);
    if (isComputerQr) {
      _pairingMessage = '已识别电脑二维码，正在连接…';
      notifyListeners();
    }
    try {
      await _lanBackupService.pair(value);
      _pairingScanActive = false;
      _pairingSuccessRevision++;
      await _nativeCamera?.setPairingScanEnabled(false);
      final LanBackupEndpoint? endpoint = _lanBackupService.snapshot.endpoint;
      _pairingMessage = endpoint == null
          ? '电脑连接成功'
          : '电脑连接成功 · ${endpoint.computerName} · ${endpoint.displayAddress}';
      _pairingFeedbackTimer?.cancel();
      _pairingFeedbackTimer = Timer(const Duration(seconds: 3), () {
        if (_disposed) return;
        _pairingMessage = null;
        notifyListeners();
      });
      await _lanBackupService.backupAll(_sessions);
      notifyListeners();
    } on FormatException catch (error) {
      if (isComputerQr) {
        _pairingMessage = error.message;
        notifyListeners();
      }
      // Ordinary waybill barcodes remain silent while waiting for a computer QR.
    } on Object catch (error) {
      _pairingScanActive = false;
      await _nativeCamera?.setPairingScanEnabled(false);
      _pairingMessage = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    } finally {
      _pairingBusy = false;
    }
  }

  Future<void> _enqueueBackupIfNeeded(
    String filePath,
    List<RecordingSession> sessions,
  ) async {
    try {
      await _lanBackupService.enqueueFinalizedFile(filePath, sessions);
    } on Object {
      // A saved local recording must never fail because its backup is offline.
    }
  }

  void _handleBackupChanged() {
    final Set<String> deletedJobs = _lanBackupService.snapshot.jobs
        .where((LanBackupJob job) => job.localDeletedAt != null)
        .map((LanBackupJob job) => job.id)
        .toSet();
    if (deletedJobs.difference(_handledDeletedBackupJobs).isNotEmpty) {
      _handledDeletedBackupJobs.addAll(deletedJobs);
      unawaited(_pruneDeletedBackupSessions());
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _registerSessionsForRetention(
    List<RecordingSession> sessions,
  ) async {
    final Map<String, List<RecordingSession>> grouped =
        <String, List<RecordingSession>>{};
    for (final RecordingSession session in sessions) {
      if (!File(session.filePath).existsSync()) continue;
      grouped
          .putIfAbsent(session.filePath, () => <RecordingSession>[])
          .add(session);
    }
    for (final MapEntry<String, List<RecordingSession>> entry
        in grouped.entries) {
      await _lanBackupService.enqueueFinalizedFile(entry.key, entry.value);
    }
  }

  Future<void> _pruneDeletedBackupSessions({bool notify = true}) async {
    final List<LanBackupJob> deletedBackupJobs = _lanBackupService.snapshot.jobs
        .where(
          (LanBackupJob job) =>
              job.state == LanBackupJobState.completed &&
              job.localDeletedAt != null,
        )
        .toList(growable: false);
    final Set<String> backedPaths = _sessions
        .where(
          (RecordingSession session) => deletedBackupJobs.any(
            (LanBackupJob job) =>
                isSameLanBackupFile(job.filePath, session.filePath),
          ),
        )
        .map((RecordingSession session) => session.filePath)
        .toSet();
    _sessions = await _repository.pruneMissingSessions(
      retainedMissingPaths: backedPaths,
    );
    if (notify && !_disposed) notifyListeners();
  }

  void _beginInitialPromptFlow() {
    _initialPromptTimer?.cancel();
    _initialPromptTimer = null;
    _initialPromptPolicy.beginWork();
  }

  void _scheduleInitialReadyPrompt() {
    _initialPromptTimer?.cancel();
    _initialPromptTimer = Timer(initialReadyPromptDelay, () {
      _initialPromptTimer = null;
      if (_disposed || !isWorking || isRecording) {
        return;
      }
      final SpeechPrompt? prompt = _initialPromptPolicy.onReadyDelayElapsed();
      if (prompt != null) {
        _speechService.enqueue(prompt);
      }
    });
  }

  void _announceInitialRecordingStarted() {
    _initialPromptTimer?.cancel();
    _initialPromptTimer = null;
    final SpeechPrompt? prompt = _initialPromptPolicy.onFirstLabelRecognized();
    _speechService.enqueue(prompt ?? SpeechPrompt.recordingStarted);
  }

  void _cancelInitialPromptFlow() {
    _initialPromptTimer?.cancel();
    _initialPromptTimer = null;
    _initialPromptPolicy.cancel();
  }

  void _showMarkerFeedback(BarcodeMarker marker) {
    _lastMarker = marker;
    _candidateCode = '';
    _feedbackTimer?.cancel();
    _pairingFeedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) {
        return;
      }
      _lastMarker = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void _setCameraError(CameraException error) {
    _errorMessage = switch (error.code) {
      'CameraAccessDenied' ||
      'CameraAccessDeniedWithoutPrompt' => '需要摄像头权限才能识别面单和录像\n请允许权限后重试',
      'CameraAccessRestricted' => '系统限制了摄像头访问，请检查设备设置',
      'AudioAccessDenied' ||
      'AudioAccessDeniedWithoutPrompt' => '需要麦克风权限才能录制声音\n请允许权限后重试',
      'AudioAccessRestricted' => '系统限制了麦克风访问，请检查设备设置',
      'NoCamera' => '没有检测到可用摄像头',
      _ => '摄像头暂时不可用，请重试\n${error.description ?? error.code}',
    };
    _setPhase(PackingSessionPhase.error);
    _speakErrorMessage('${error.code} ${error.description ?? ''}');
  }

  void _speakErrorMessage(String message) {
    final String normalized = message.toLowerCase();
    if (normalized.contains('未准备') ||
        normalized.contains('摄像头初始化') ||
        normalized.contains('摄像头打开') ||
        normalized.contains('camera_not_ready')) {
      return;
    }
    final SpeechPrompt prompt;
    if (normalized.contains('permission') ||
        normalized.contains('权限') ||
        normalized.contains('accessdenied') ||
        normalized.contains('accessrestricted')) {
      prompt = SpeechPrompt.permissionRequired;
    } else if (normalized.contains('没有检测到') ||
        normalized.contains('nocamera')) {
      prompt = SpeechPrompt.cameraNotFound;
    } else if (normalized.contains('断开')) {
      prompt = SpeechPrompt.cameraDisconnected;
    } else if (normalized.contains('声音') || normalized.contains('麦克风')) {
      prompt = SpeechPrompt.audioRecordingFailed;
    } else if (normalized.contains('分段')) {
      prompt = SpeechPrompt.segmentSaveFailed;
    } else if (normalized.contains('文件创建')) {
      prompt = SpeechPrompt.videoFileCreateFailed;
    } else if (normalized.contains('保存')) {
      prompt = SpeechPrompt.recordingSaveFailed;
    } else if (normalized.contains('视频编码器')) {
      prompt = SpeechPrompt.recordingFailed;
    } else {
      prompt = SpeechPrompt.recordingFailed;
    }
    _speechService.enqueue(prompt, incidentKey: prompt.name);
  }

  void _setPhase(PackingSessionPhase value) {
    _phase = value;
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _disposeCamera() async {
    _cancelInitialPromptFlow();
    if (Platform.isAndroid) {
      final ContinuousCameraService? nativeCamera = _nativeCamera;
      _nativeCamera = null;
      _nativeInitialization = null;
      _torchEnabled = false;
      if (nativeCamera != null) {
        await nativeCamera.dispose();
      }
      if (!_disposed && _phase != PackingSessionPhase.error) {
        _phase = PackingSessionPhase.initializing;
        notifyListeners();
      }
      return;
    }
    final CameraController? camera = _cameraController;
    _cameraController = null;
    _torchEnabled = false;
    if (camera != null) {
      await camera.dispose();
    }
    if (!_disposed && _phase != PackingSessionPhase.error) {
      _phase = PackingSessionPhase.initializing;
      notifyListeners();
    }
  }

  String _sessionId(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    String three(int number) => number.toString().padLeft(3, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}_'
        '${three(value.millisecond)}';
  }

  @override
  void dispose() {
    _disposed = true;
    _elapsedTimer?.cancel();
    _feedbackTimer?.cancel();
    unawaited(WakelockPlus.disable());
    final CameraController? camera = _cameraController;
    if (camera != null) {
      unawaited(camera.dispose());
    }
    final ContinuousCameraService? nativeCamera = _nativeCamera;
    if (nativeCamera != null) {
      unawaited(nativeCamera.dispose());
    }
    unawaited(_barcodeScanner.close());
    unawaited(_speechService.dispose());
    unawaited(_maxVolumeService.dispose());
    if (_backupListenerAttached) {
      _lanBackupService.removeListener(_handleBackupChanged);
    }
    unawaited(_lanBackupService.dispose());
    super.dispose();
  }
}

bool _looksLikeComputerPairingQr(String value) {
  final String normalized = value.trim().toLowerCase();
  return normalized.startsWith('http://') || normalized.startsWith('https://');
}
