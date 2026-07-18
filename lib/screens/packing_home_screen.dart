import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/parcel_lens_app.dart';
import '../controllers/packing_session_controller.dart';
import '../models/barcode_marker.dart';
import '../models/work_mode.dart';
import 'recordings_screen.dart';

class PackingHomeScreen extends StatefulWidget {
  const PackingHomeScreen({super.key});

  @override
  State<PackingHomeScreen> createState() => _PackingHomeScreenState();
}

class _PackingHomeScreenState extends State<PackingHomeScreen>
    with WidgetsBindingObserver {
  late final PackingSessionController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = PackingSessionController();
    unawaited(_controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.handleResumed());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_controller.handleInactive());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleWork() async {
    if (_controller.isRecording) {
      await _controller.stopWork();
      return;
    }
    await _controller.startWork();
  }

  Future<void> _openRecordings() async {
    if (_controller.isRecording || _controller.isBusy) {
      return;
    }
    await _controller.refreshSessions();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RecordingsScreen(
          sessions: _controller.sessions,
          workMode: _controller.workMode,
          onWorkModeChanged: _controller.setWorkMode,
          onSessionUpdated: _controller.updateSession,
          onDeleteSessions: _controller.deleteSessions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? child) {
        return PackingHomeView(
          cameraController: _controller.cameraController,
          nativeTextureId: _controller.nativeTextureId,
          nativePreviewAspectRatio: _controller.nativePreviewAspectRatio,
          phase: _controller.phase,
          elapsed: _controller.elapsed,
          lastMarker: _controller.lastMarker,
          candidateCode: _controller.candidateCode,
          currentCode: _controller.currentCode,
          workMode: _controller.workMode,
          errorMessage: _controller.errorMessage,
          onPrimaryPressed: _toggleWork,
          onRetryPressed: _controller.retryInitialize,
          onRecordingsPressed: _openRecordings,
        );
      },
    );
  }
}

class PackingHomeView extends StatelessWidget {
  const PackingHomeView({
    required this.phase,
    required this.elapsed,
    required this.onPrimaryPressed,
    required this.onRetryPressed,
    required this.onRecordingsPressed,
    this.cameraController,
    this.nativeTextureId,
    this.nativePreviewAspectRatio,
    this.lastMarker,
    this.candidateCode = '',
    this.currentCode = '',
    this.workMode = WorkMode.continuousScan,
    this.errorMessage,
    this.previewOverride,
    super.key,
  });

  final CameraController? cameraController;
  final int? nativeTextureId;
  final double? nativePreviewAspectRatio;
  final PackingSessionPhase phase;
  final Duration elapsed;
  final BarcodeMarker? lastMarker;
  final String candidateCode;
  final String currentCode;
  final WorkMode workMode;
  final String? errorMessage;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onRetryPressed;
  final VoidCallback onRecordingsPressed;
  final Widget? previewOverride;

  bool get _isRecording => phase == PackingSessionPhase.recording;
  bool get _isBusy =>
      phase == PackingSessionPhase.initializing ||
      phase == PackingSessionPhase.starting ||
      phase == PackingSessionPhase.saving;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double panelHeight = (constraints.maxHeight * 0.24).clamp(
              196.0,
              216.0,
            );
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(
                  bottom: panelHeight - 28,
                  child: _CameraArea(this),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _ControlPanel(view: this, height: panelHeight),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CameraArea extends StatelessWidget {
  const _CameraArea(this.view);

  final PackingHomeView view;

  @override
  Widget build(BuildContext context) {
    Widget preview;
    final CameraController? camera = view.cameraController;
    if (view.previewOverride != null) {
      preview = view.previewOverride!;
    } else if (view.nativeTextureId != null &&
        view.nativePreviewAspectRatio != null) {
      preview = NativeCameraPreviewCover(
        textureId: view.nativeTextureId!,
        portraitAspectRatio: view.nativePreviewAspectRatio!,
      );
    } else if (camera?.value.isInitialized == true) {
      preview = CameraPreviewCover(controller: camera!);
    } else {
      preview = Image.asset(
        'assets/images/packing-preview.png',
        fit: BoxFit.cover,
      );
    }

    return ColoredBox(
      key: const Key('camera-preview-backing'),
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(child: preview),
          const Positioned(
            left: 24,
            right: 24,
            top: 64,
            bottom: 72,
            child: SizedBox(
              key: Key('scan-guide'),
              child: CustomPaint(painter: _ScanGuidePainter()),
            ),
          ),
          if (view.lastMarker != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 48,
              child: _RecognitionToast(marker: view.lastMarker!),
            )
          else if (view.candidateCode.isNotEmpty)
            Positioned(
              left: 20,
              right: 20,
              bottom: 48,
              child: Text(
                '正在确认 · ${view.candidateCode}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: <Shadow>[
                    Shadow(color: Color(0x88000000), blurRadius: 8),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NativeCameraPreviewCover extends StatelessWidget {
  const NativeCameraPreviewCover({
    required this.textureId,
    required this.portraitAspectRatio,
    super.key,
  });

  final int textureId;
  final double portraitAspectRatio;

  @override
  Widget build(BuildContext context) {
    const double naturalHeight = 1000;
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            key: const Key('native-camera-preview-natural-size'),
            width: naturalHeight * portraitAspectRatio,
            height: naturalHeight,
            child: Texture(
              textureId: textureId,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanGuidePainter extends CustomPainter {
  const _ScanGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double inset = 1;
    const double cornerLength = 28;
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final Path path = Path()
      ..moveTo(inset, inset + cornerLength)
      ..lineTo(inset, inset)
      ..lineTo(inset + cornerLength, inset)
      ..moveTo(size.width - inset - cornerLength, inset)
      ..lineTo(size.width - inset, inset)
      ..lineTo(size.width - inset, inset + cornerLength)
      ..moveTo(size.width - inset, size.height - inset - cornerLength)
      ..lineTo(size.width - inset, size.height - inset)
      ..lineTo(size.width - inset - cornerLength, size.height - inset)
      ..moveTo(inset + cornerLength, size.height - inset)
      ..lineTo(inset, size.height - inset)
      ..lineTo(inset, size.height - inset - cornerLength);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ScanGuidePainter oldDelegate) => false;
}

class CameraPreviewCover extends StatelessWidget {
  const CameraPreviewCover({required this.controller, super.key});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return CameraPreviewCoverLayout(
      cameraValue: controller,
      preview: controller.buildPreview(),
    );
  }
}

class CameraPreviewCoverLayout extends StatelessWidget {
  const CameraPreviewCoverLayout({
    required this.cameraValue,
    required this.preview,
    super.key,
  });

  final ValueListenable<CameraValue> cameraValue;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: cameraValue,
      builder: (BuildContext context, CameraValue value, Widget? child) {
        if (!value.isInitialized || value.previewSize == null) {
          return const SizedBox.expand();
        }

        final double rawAspectRatio = value.aspectRatio;
        final double portraitAspectRatio = rawAspectRatio > 1
            ? 1 / rawAspectRatio
            : rawAspectRatio;
        const double naturalHeight = 1000;
        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                key: const Key('camera-preview-natural-size'),
                width: naturalHeight * portraitAspectRatio,
                height: naturalHeight,
                child: child,
              ),
            ),
          ),
        );
      },
      child: preview,
    );
  }
}

class _RecognitionToast extends StatelessWidget {
  const _RecognitionToast({required this.marker});

  final BarcodeMarker marker;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xEB087454),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '已识别面单，当前录像已绑定',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  marker.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD8F3E9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.view, required this.height});

  final PackingHomeView view;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bool isError = view.phase == PackingSessionPhase.error;
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 28,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            isError
                ? (view.errorMessage ?? '请重新检查摄像头权限')
                : view._isRecording
                ? _recordingStatus(view)
                : '对准面单条码',
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF767D7A),
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: view._isBusy
                ? null
                : isError
                ? view.onRetryPressed
                : view.onPrimaryPressed,
            icon: view._isBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.4,
                    ),
                  )
                : Icon(
                    isError
                        ? Icons.refresh_rounded
                        : view._isRecording
                        ? Icons.stop_circle_outlined
                        : Icons.videocam_outlined,
                  ),
            label: Text(
              view.phase == PackingSessionPhase.initializing
                  ? '正在准备摄像头'
                  : view.phase == PackingSessionPhase.starting
                  ? '正在启动录像'
                  : view.phase == PackingSessionPhase.saving
                  ? '正在保存录像'
                  : isError
                  ? '重新检查'
                  : view._isRecording
                  ? '结束并保存'
                  : '开始工作',
            ),
          ),
          const SizedBox(height: 1),
          TextButton(
            onPressed: view._isRecording || view._isBusy
                ? null
                : view.onRecordingsPressed,
            style: TextButton.styleFrom(
              foregroundColor: ParcelLensApp.ink,
              textStyle: const TextStyle(
                fontFamily: 'NotoSansSC',
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('录像与设置'),
                SizedBox(width: 5),
                Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

String _recordingStatus(PackingHomeView view) {
  if (view.currentCode.isEmpty) {
    return '录像中  ${_duration(view.elapsed)} · 等待识别面单';
  }
  return switch (view.workMode) {
    WorkMode.continuousScan => '${view.currentCode} · 扫下一单自动分段',
    WorkMode.sameCodeStop => '再次识别 ${view.currentCode} 后停录',
  };
}

String _duration(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  final int hours = value.inHours;
  final int minutes = value.inMinutes.remainder(60);
  final int seconds = value.inSeconds.remainder(60);
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}
