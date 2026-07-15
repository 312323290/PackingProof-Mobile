import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/barcode_marker.dart';
import '../models/recording_session.dart';
import '../services/barcode_candidate_policy.dart';
import '../services/barcode_stability_tracker.dart';
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

  static const Duration analysisInterval = Duration(milliseconds: 280);
  static const Duration transitionSettleDelay = Duration(milliseconds: 120);

  final SessionRepository _repository;
  final BarcodeScanner _barcodeScanner;
  final BarcodeStabilityTracker _stabilityTracker = BarcodeStabilityTracker();
  final List<BarcodeMarker> _activeMarkers = <BarcodeMarker>[];

  CameraController? _cameraController;
  PackingSessionPhase _phase = PackingSessionPhase.initializing;
  List<RecordingSession> _sessions = <RecordingSession>[];
  DateTime? _sessionStartedAt;
  DateTime _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _elapsedTimer;
  Timer? _feedbackTimer;
  Duration _elapsed = Duration.zero;
  BarcodeMarker? _lastMarker;
  String _candidateCode = '';
  String? _errorMessage;
  bool _processingFrame = false;
  bool _disposed = false;

  CameraController? get cameraController => _cameraController;
  PackingSessionPhase get phase => _phase;
  List<RecordingSession> get sessions =>
      List<RecordingSession>.unmodifiable(_sessions);
  Duration get elapsed => _elapsed;
  BarcodeMarker? get lastMarker => _lastMarker;
  String get candidateCode => _candidateCode;
  String? get errorMessage => _errorMessage;
  bool get isRecording => _phase == PackingSessionPhase.recording;
  bool get isBusy =>
      _phase == PackingSessionPhase.initializing ||
      _phase == PackingSessionPhase.starting ||
      _phase == PackingSessionPhase.saving;
  bool get isCameraReady =>
      _cameraController?.value.isInitialized == true &&
      _phase != PackingSessionPhase.error;

  Future<void> initialize() async {
    if (_disposed || _cameraController?.value.isInitialized == true) {
      return;
    }
    _setPhase(PackingSessionPhase.initializing);
    _errorMessage = null;

    try {
      await _repository.initialize();
      _sessions = await _repository.loadSessions();
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
        ResolutionPreset.high,
        enableAudio: false,
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
    if (camera == null ||
        !camera.value.isInitialized ||
        isBusy ||
        isRecording) {
      return;
    }

    _errorMessage = null;
    _sessionStartedAt = DateTime.now();
    _elapsed = Duration.zero;
    _activeMarkers.clear();
    _lastMarker = null;
    _candidateCode = '';
    _stabilityTracker.reset();
    _setPhase(PackingSessionPhase.starting);
    await WidgetsBinding.instance.endOfFrame;

    try {
      await WakelockPlus.enable();
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await camera.startVideoRecording(
        onAvailable: _processFrame,
        enablePersistentRecording: true,
      );
      await Future<void>.delayed(transitionSettleDelay);
      _setPhase(PackingSessionPhase.recording);
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final DateTime? startedAt = _sessionStartedAt;
        if (startedAt == null || _disposed) {
          return;
        }
        _elapsed = DateTime.now().difference(startedAt);
        notifyListeners();
      });
    } on CameraException catch (error) {
      _sessionStartedAt = null;
      await WakelockPlus.disable();
      _setCameraError(error);
    } on Object catch (error) {
      _sessionStartedAt = null;
      await WakelockPlus.disable();
      _errorMessage = '无法开始录像，请重新检查摄像头\n$error';
      _setPhase(PackingSessionPhase.error);
    }
  }

  Future<RecordingSession?> stopWork() async {
    final CameraController? camera = _cameraController;
    final DateTime? startedAt = _sessionStartedAt;
    if (camera == null || startedAt == null || !isRecording) {
      return null;
    }

    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _setPhase(PackingSessionPhase.saving);
    await WidgetsBinding.instance.endOfFrame;

    try {
      final XFile captured = await camera.stopVideoRecording();
      final DateTime endedAt = DateTime.now();
      final String sessionId = _sessionId(startedAt);
      final String savedPath = await _repository.persistVideo(
        captured.path,
        sessionId,
      );
      final RecordingSession session = RecordingSession(
        id: sessionId,
        filePath: savedPath,
        startedAt: startedAt,
        endedAt: endedAt,
        markers: List<BarcodeMarker>.unmodifiable(_activeMarkers),
      );
      _sessions = await _repository.addSession(session);
      _sessionStartedAt = null;
      _elapsed = session.duration;
      _candidateCode = '';
      await WakelockPlus.disable();
      await Future<void>.delayed(transitionSettleDelay);
      _setPhase(PackingSessionPhase.ready);
      return session;
    } on Object catch (error) {
      _sessionStartedAt = null;
      await WakelockPlus.disable();
      _errorMessage = '录像保存失败，请保留应用并重试\n$error';
      _setPhase(PackingSessionPhase.error);
      return null;
    }
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
    if (_cameraController?.value.isInitialized != true &&
        _phase != PackingSessionPhase.saving) {
      await initialize();
    }
  }

  Future<void> refreshSessions() async {
    _sessions = await _repository.loadSessions();
    notifyListeners();
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processingFrame || !isRecording || _sessionStartedAt == null) {
      return;
    }
    final DateTime now = DateTime.now();
    if (now.difference(_lastAnalysisAt) < analysisInterval) {
      return;
    }
    _lastAnalysisAt = now;
    _processingFrame = true;

    try {
      final InputImage? inputImage = _toInputImage(image);
      if (inputImage == null) {
        return;
      }
      final List<Barcode> barcodes = await _barcodeScanner.processImage(
        inputImage,
      );
      String? validCode;
      for (final Barcode barcode in barcodes) {
        if (BarcodeCandidatePolicy.isValid(barcode.rawValue)) {
          validCode = BarcodeCandidatePolicy.normalize(barcode.rawValue);
          break;
        }
      }

      final BarcodeObservation observation = _stabilityTracker.observe(
        validCode,
        now,
      );
      if (observation.confirmedCode.isNotEmpty) {
        _confirmBarcode(observation.confirmedCode, now);
      } else if (observation.candidateCode != _candidateCode) {
        _candidateCode = observation.candidateCode;
        notifyListeners();
      }
    } on Object catch (error) {
      debugPrint('面单识别帧已跳过: $error');
    } finally {
      _processingFrame = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final CameraController? controller = _cameraController;
    if (controller == null || image.planes.length != 1) {
      return null;
    }

    final InputImageRotation? rotation = _inputImageRotation(
      controller.description,
      controller.value.deviceOrientation,
    );
    if (rotation == null) {
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

  void _confirmBarcode(String code, DateTime now) {
    final DateTime? startedAt = _sessionStartedAt;
    if (startedAt == null) {
      return;
    }
    final BarcodeMarker marker = BarcodeMarker(
      code: code,
      occurredAt: now,
      offset: now.difference(startedAt),
    );
    _activeMarkers.add(marker);
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
    unawaited(_barcodeScanner.close());
    super.dispose();
  }
}
