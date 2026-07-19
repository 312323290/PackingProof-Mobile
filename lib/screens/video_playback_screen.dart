import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_session.dart';
import '../services/video_share_service.dart';
import '../services/remote_video_clip_service.dart';
import '../widgets/two_button_confirm_dialog.dart';
import 'video_trim_screen.dart';
import 'remote_video_trim_screen.dart';

class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({
    required this.session,
    required this.onSessionUpdated,
    this.onDelete,
    this.remoteUri,
    this.remoteVideoId,
    this.remoteHeaders = const <String, String>{},
    this.remoteClipService,
    super.key,
  });

  final RecordingSession session;
  final Future<void> Function(RecordingSession session) onSessionUpdated;
  final Future<void> Function()? onDelete;
  final Uri? remoteUri;
  final int? remoteVideoId;
  final Map<String, String> remoteHeaders;
  final RemoteVideoClipSink? remoteClipService;

  @override
  State<VideoPlaybackScreen> createState() => _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState extends State<VideoPlaybackScreen> {
  late final VideoPlayerController _video;
  late final Future<void> _initialized;
  late RecordingSession _session;
  late Duration _playbackStart;
  late Duration _playbackEnd;
  bool _handlingBoundary = false;
  bool _resumeAfterScrub = false;
  double? _scrubMilliseconds;
  final VideoShareService _shareService = VideoShareService();
  bool _sharing = false;
  double _shareProgress = 0;
  String _shareMessage = '';

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _playbackStart = _session.mediaStart;
    _playbackEnd = _session.playbackEnd;
    _video = widget.remoteUri == null
        ? VideoPlayerController.file(File(_session.filePath))
        : VideoPlayerController.networkUrl(
            widget.remoteUri!,
            httpHeaders: widget.remoteHeaders,
          );
    _initialized = _video.initialize().then((_) async {
      await _video.setVolume(1);
      final Duration sourceDuration = _video.value.duration;
      if (_playbackStart > sourceDuration) {
        _playbackStart = Duration.zero;
      }
      if (_playbackEnd > sourceDuration || _playbackEnd <= _playbackStart) {
        _playbackEnd = sourceDuration;
      }
      await _video.seekTo(_playbackStart);
      _video.addListener(_handlePlaybackBoundary);
      await _video.play();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _video.removeListener(_handlePlaybackBoundary);
    _video.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_video.value.isPlaying) {
      await _video.pause();
    } else {
      final Duration position = _video.value.position;
      if (position < _playbackStart || position >= _playbackEnd) {
        await _video.seekTo(_playbackStart);
      }
      await _video.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Duration get _playbackDuration => _playbackEnd - _playbackStart;

  double _relativePositionMilliseconds(VideoPlayerValue value) {
    final double maximum = _playbackDuration.inMilliseconds.toDouble();
    if (maximum <= 0) {
      return 0;
    }
    return (_scrubMilliseconds ??
            (value.position - _playbackStart).inMilliseconds.toDouble())
        .clamp(0, maximum);
  }

  void _startScrubbing(double value) {
    _resumeAfterScrub = _video.value.isPlaying;
    _handlingBoundary = true;
    if (_resumeAfterScrub) {
      unawaited(_video.pause());
    }
    setState(() => _scrubMilliseconds = value);
  }

  void _scrubTo(double value) {
    setState(() => _scrubMilliseconds = value);
    unawaited(
      _video.seekTo(_playbackStart + Duration(milliseconds: value.round())),
    );
  }

  Future<void> _finishScrubbing(double value) async {
    await _video.seekTo(_playbackStart + Duration(milliseconds: value.round()));
    _scrubMilliseconds = null;
    _handlingBoundary = false;
    if (_resumeAfterScrub && value < _playbackDuration.inMilliseconds) {
      await _video.play();
    }
    _resumeAfterScrub = false;
    if (mounted) {
      setState(() {});
    }
  }

  String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds.clamp(0, 359999);
    final int hours = totalSeconds ~/ 3600;
    final int minutes = totalSeconds.remainder(3600) ~/ 60;
    final int seconds = totalSeconds.remainder(60);
    final String minuteText = minutes.toString().padLeft(2, '0');
    final String secondText = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minuteText:$secondText';
    }
    return '$minuteText:$secondText';
  }

  void _handlePlaybackBoundary() {
    if (_handlingBoundary ||
        !_video.value.isInitialized ||
        _video.value.position < _playbackEnd) {
      return;
    }
    _handlingBoundary = true;
    unawaited(_rewindAtBoundary());
  }

  Future<void> _rewindAtBoundary() async {
    await _video.pause();
    await _video.seekTo(_playbackStart);
    _handlingBoundary = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openTrim() async {
    await _video.pause();
    if (!mounted) {
      return;
    }
    if (widget.remoteUri != null && widget.remoteVideoId != null) {
      final Uri remote = widget.remoteUri!;
      final RemoteVideoClipSink service =
          widget.remoteClipService ??
          RemoteVideoClipService(
            baseUri: Uri(
              scheme: remote.scheme,
              host: remote.host,
              port: remote.hasPort ? remote.port : null,
            ),
            accessHeaders: widget.remoteHeaders,
          );
      final File? clip = await Navigator.of(context).push<File>(
        MaterialPageRoute<File>(
          builder: (_) => RemoteVideoTrimScreen(
            videoId: widget.remoteVideoId!,
            playUri: remote,
            duration: _video.value.duration,
            service: service,
          ),
        ),
      );
      if (clip != null && mounted) {
        await SharePlus.instance.share(
          ShareParams(
            title: _session.displayCode,
            files: <XFile>[XFile(clip.path, mimeType: 'video/mp4')],
          ),
        );
      }
      if (mounted) await _video.play();
      return;
    }
    final RecordingSession? updated = await Navigator.of(context)
        .push<RecordingSession>(
          MaterialPageRoute<RecordingSession>(
            builder: (BuildContext context) =>
                VideoTrimScreen(session: _session),
          ),
        );
    if (updated == null || !mounted) {
      await _video.play();
      return;
    }
    try {
      await widget.onSessionUpdated(updated);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('剪辑保存失败，请稍后重试')));
        await _video.play();
      }
      return;
    }
    _handlingBoundary = true;
    _session = updated;
    _playbackStart = updated.mediaStart;
    _playbackEnd = updated.playbackEnd;
    await _video.seekTo(_playbackStart);
    _handlingBoundary = false;
    await _video.play();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _share() async {
    if (_sharing || !_video.value.isInitialized) return;
    await _video.pause();
    setState(() {
      _sharing = true;
      _shareProgress = 0;
      _shareMessage = widget.remoteUri == null ? '正在准备分享' : '正在下载电脑录像';
    });
    try {
      final File file = await _shareService.prepare(
        sourcePath: _session.filePath,
        remoteUri: widget.remoteUri,
        remoteHeaders: widget.remoteHeaders,
        mediaStart: _playbackStart,
        mediaEnd: _playbackEnd,
        sourceDuration: _video.value.duration,
        onProgress: (double progress, String message) {
          if (!mounted) return;
          setState(() {
            _shareProgress = progress;
            _shareMessage = message;
          });
        },
      );
      await SharePlus.instance.share(
        ShareParams(
          title: _session.displayCode,
          files: <XFile>[XFile(file.path, mimeType: 'video/mp4')],
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '分享失败：${error.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
          _shareProgress = 0;
          _shareMessage = '';
        });
      }
    }
  }

  Future<void> _deleteLocalRecording() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => const TwoButtonConfirmDialog(
        title: '删除这段录像？',
        message: '将删除手机中的录像和记录，电脑中的备份不会受到影响',
        confirmLabel: '删除',
        dangerous: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.onDelete?.call();
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_session.displayCode),
        actions: <Widget>[
          if (widget.remoteUri == null && widget.onDelete != null)
            IconButton(
              key: const Key('delete-local-recording'),
              tooltip: '删除本机录像',
              onPressed: _sharing ? null : _deleteLocalRecording,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initialized,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                widget.remoteUri == null
                    ? '录像无法播放，请检查文件是否仍在本机'
                    : '电脑录像暂时无法播放，请检查局域网连接',
              ),
            );
          }
          return ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _video,
            builder:
                (BuildContext context, VideoPlayerValue value, Widget? child) {
                  final double maximum = _playbackDuration.inMilliseconds
                      .toDouble();
                  final double position = _relativePositionMilliseconds(value);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _togglePlayback,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                VideoPlayer(_video),
                                if (!value.isPlaying &&
                                    _scrubMilliseconds == null)
                                  const Center(
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Color(0x66000000),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(14),
                                          child: Icon(
                                            Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 38,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: IgnorePointer(
                                    child: Container(
                                      height: 104,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: <Color>[
                                            Colors.transparent,
                                            Color(0x99000000),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 10,
                                  right: 10,
                                  bottom: 4,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child: Row(
                                          children: <Widget>[
                                            Text(
                                              _formatDuration(
                                                Duration(
                                                  milliseconds: position
                                                      .round(),
                                                ),
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _formatDuration(
                                                _playbackDuration,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: Colors.white,
                                          inactiveTrackColor: const Color(
                                            0x66FFFFFF,
                                          ),
                                          thumbColor: Colors.white,
                                          overlayColor: const Color(0x33FFFFFF),
                                          trackHeight: 3,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 6,
                                              ),
                                        ),
                                        child: Slider(
                                          value: maximum > 0 ? position : 0,
                                          max: maximum > 0 ? maximum : 1,
                                          onChangeStart: maximum > 0
                                              ? _startScrubbing
                                              : null,
                                          onChanged: maximum > 0
                                              ? _scrubTo
                                              : null,
                                          onChangeEnd: maximum > 0
                                              ? _finishScrubbing
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_sharing) ...<Widget>[
                        LinearProgressIndicator(value: _shareProgress),
                        const SizedBox(height: 8),
                        Text(_shareMessage, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: <Widget>[
                          if (widget.remoteUri == null ||
                              widget.remoteVideoId != null) ...<Widget>[
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _sharing ? null : _openTrim,
                                icon: const Icon(Icons.content_cut_rounded),
                                label: const Text('剪辑'),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: FilledButton.tonalIcon(
                              key: const Key('share-recording'),
                              onPressed: _sharing ? null : _share,
                              icon: const Icon(Icons.share_rounded),
                              label: Text(
                                widget.remoteUri == null ? '分享' : '下载并分享',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
          );
        },
      ),
    );
  }
}
