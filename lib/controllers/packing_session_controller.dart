import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/barcode_marker.dart';
import '../models/recording_session.dart';
import '../models/work_mode.dart';
import '../services/barcode_candidate_policy.dart';
import '../services/barcode_stability_tracker.dart';
import '../services/barcode_work_mode_policy.dart';
import '../services/continuous_camera_service.dart';
import '../services/nv21_center_crop.dart';
import '../services/recording_timeline.dart';
import '../services/session_repository.dart';

enum PackingSessionPhase {
  initializing,
  ready,
  starting,
  recording,
  saving,
  error,
}

class PackingSessionController extends ChangeNotifier {
  PackingSessionController({SessionRepository? repository})
    : _repository = repository ?? SessionRepository(),
      _barcodeScanner = BarcodeScanner(
        formats: const <BarcodeFormat>[BarcodeFormat.all],
      );

  static const Duration analysisInterval = Duration(milliseconds: 200);
  static const Duration transitionSettleDelay = Duration(milliseconds: 120);
  static const int recordingFps = 30;

  final SessionRepository _repository;
  final BarcodeScanner _barcodeScanner;
  final BarcodeStabilityTracker _stabilityTracker = BarcodeStabilityTracker();
  final RecordingTimeline _timeline = RecordingTimeline();

  CameraController? _cameraController;
  ContinuousCameraService? _nativeCamera;
  ContinuousCameraInitialization? _nativeInitialization;
  PackingSessionPhase _phase = PackingSessionPhase.initializing;
  List<RecordingSession> _sessions = <RecordingSession>[];
  DateTime _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _elapsedTimer;
  Timer? _feedbackTimer;
  Duration _elapsed = Duration.zero;
  BarcodeMarker? _lastMarker;
  String _candidateCode = '';
  WorkMode _workMode = WorkMode.continuousScan;
  String? _errorMessage;
  bool _processingFrame = false;
  bool _handlingBarcode = false;
  bool _disposed = false;
  String? _recordingId;
  String? _activeSegmentId;
  int _segmentIndex = 1;

  CameraController? get cameraController => _cameraController;
  int? get nativeTextureId => _nativeInitialization?.textureId;
  double? get nativePreviewAspectRatio =>
      _nativeInitialization?.portraitAspectRatio;
  PackingSessionPhase get phase => _phase;
  List<RecordingSession> get sessions =>
      List<RecordingSession>.unmodifiable(_sessions);
  Duration get elapsed => _elapsed;
  BarcodeMarker? get lastMarker => _lastMarker;
  String get candidateCode => _candidateCode;
  String get currentCode => _timeline.currentCode;
  WorkMode get workMode => _workMode;
  String? get errorMessage => _errorMessage;
  bool get isRecording => _phase == PackingSessionPhase.recording;
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
      _sessions = await _repository.loadSessions();
      _workMode = await _repository.loadWorkMode();
      if (Platform.isAndroid) {
        final ContinuousCameraService nativeCamera = ContinuousCameraService();
        nativeCamera.onBarcodeFrame = _processNativeBarcodeFrame;
        nativeCamera.onError = (String message) {
          _errorMessage = message;
          if (!_disposed) {
            notifyListeners();
          }
        };
        _nativeCamera = nativeCamera;
        _nativeInitialization = await nativeCamera.initialize();
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

  Future<void> startWork() async {
    final CameraController? camera = _cameraController;
    final bool cameraUnavailable = Platform.isAndroid
        ? _nativeInitialization == null
        : camera == null || !camera.value.isInitialized;
    if (cameraUnavailable || isBusy || isRecording) {
      return;
    }

    _errorMessage = null;
    _lastMarker = null;
    _candidateCode = '';
    _timeline.reset();
    _stabilityTracker.reset();

    try {
      await WakelockPlus.enable();
      await _startRecording();
    } on CameraException catch (error) {
      _timeline.reset();
      await WakelockPlus.disable();
      _setCameraError(error);
    } on Object catch (error) {
      _timeline.reset();
      await WakelockPlus.disable();
      _errorMessage = '无法开始录像，请重新检查摄像头\n$error';
      _setPhase(PackingSessionPhase.error);
    }
  }

  Future<RecordingSession?> stopWork() async {
    final CameraController? camera = _cameraController;
    final DateTime? startedAt = _timeline.recordingStartedAt;
    final bool recordingUnavailable = Platform.isAndroid
        ? _nativeCamera == null
        : camera == null || !camera.value.isRecordingVideo;
    if (recordingUnavailable || startedAt == null) {
      return null;
    }

    _setPhase(PackingSessionPhase.saving);
    await WidgetsBinding.instance.endOfFrame;

    try {
      final List<RecordingSession> savedSessions = Platform.isAndroid
          ? await _finishNativeRecording()
          : await _finishRecording();
      _candidateCode = '';
      _stabilityTracker.reset();
      await WakelockPlus.disable();
      await Future<void>.delayed(transitionSettleDelay);
      _setPhase(PackingSessionPhase.ready);
      return savedSessions.isEmpty ? null : savedSessions.last;
    } on Object catch (error) {
      _timeline.reset();
      await WakelockPlus.disable();
      _errorMessage = '录像保存失败，请保留应用并重试\n$error';
      _setPhase(PackingSessionPhase.error);
      return null;
    }
  }

  Future<void> setWorkMode(WorkMode mode) async {
    if (_workMode == mode || isRecording || isBusy) {
      return;
    }
    _workMode = mode;
    notifyListeners();
    await _repository.saveWorkMode(mode);
  }

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
    final String savedPath = await _repository.persistVideo(
      captured.path,
      sessionId,
    );
    final List<RecordingSession> sessions = _timeline.buildSessions(
      endedAt: endedAt,
      filePath: savedPath,
      recordingId: sessionId,
    );
    _sessions = await _repository.addSessions(sessions);
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
    final RecordingSession session = _standaloneSession(
      id: segmentId,
      path: stopped.path,
      draft: draft,
    );
    _sessions = await _repository.addSession(session);
    _elapsed = stopped.endedAt.difference(_timeline.recordingStartedAt!);
    _timeline.reset();
    _recordingId = null;
    _activeSegmentId = null;
    return <RecordingSession>[session];
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final DateTime? startedAt = _timeline.recordingStartedAt;
      if (startedAt == null || _disposed) {
        return;
      }
      _elapsed = DateTime.now().difference(startedAt);
      notifyListeners();
    });
  }

  Future<void> handleInactive() async {
    if (isRecording) {
      await stopWork();
    }
    if (_phase != PackingSessionPhase.saving) {
      await _disposeCamera();
    }
  }

  Future<void> handleResumed() async {
    final bool needsInitialization = Platform.isAndroid
        ? _nativeInitialization == null
        : _cameraController?.value.isInitialized != true;
    if (needsInitialization && _phase != PackingSessionPhase.saving) {
      await initialize();
    }
  }

  Future<void> refreshSessions() async {
    _sessions = await _repository.loadSessions();
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

  void _processNativeBarcodeFrame(List<NativeBarcodeCandidate> candidates) {
    if (!isRecording || !_timeline.isActive) {
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
    if (_processingFrame || !isRecording || !_timeline.isActive) {
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
    if (_handlingBarcode || !isRecording || !_timeline.isActive) {
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
          await stopWork();
        } finally {
          _handlingBarcode = false;
        }
        return;
      case BarcodeWorkAction.startNextVideo:
        _handlingBarcode = true;
        try {
          final BarcodeMarker? marker = Platform.isAndroid
              ? await _splitNativeRecording(code)
              : _timeline.startNext(code, now)?.marker;
          if (marker != null) {
            _showMarkerFeedback(marker);
          }
        } finally {
          _handlingBarcode = false;
        }
        return;
    }
  }

  Future<BarcodeMarker?> _splitNativeRecording(String code) async {
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
    final RecordingSession completed = _standaloneSession(
      id: completedId,
      path: split.completedPath,
      draft: transition.completed,
    );
    _sessions = await _repository.addSession(completed);
    _activeSegmentId = nextId;
    _segmentIndex = nextIndex;
    return transition.marker;
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

  void _bindCurrentCode(String code, DateTime now) {
    final BarcodeMarker? marker = _timeline.bindCode(code, now);
    if (marker == null) {
      return;
    }
    _showMarkerFeedback(marker);
  }

  void _showMarkerFeedback(BarcodeMarker marker) {
    _lastMarker = marker;
    _candidateCode = '';
    _feedbackTimer?.cancel();
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
  }

  void _setPhase(PackingSessionPhase value) {
    _phase = value;
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _disposeCamera() async {
    if (Platform.isAndroid) {
      final ContinuousCameraService? nativeCamera = _nativeCamera;
      _nativeCamera = null;
      _nativeInitialization = null;
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
    super.dispose();
  }
}
