import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_session.dart';
import 'video_trim_screen.dart';

class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({
    required this.session,
    required this.onSessionUpdated,
    super.key,
  });

  final RecordingSession session;
  final Future<void> Function(RecordingSession session) onSessionUpdated;

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

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _playbackStart = _session.mediaStart;
    _playbackEnd = _session.playbackEnd;
    _video = VideoPlayerController.file(File(_session.filePath));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_session.displayCode)),
      body: FutureBuilder<void>(
        future: _initialized,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('录像无法播放，请检查文件是否仍在本机'));
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
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              VideoPlayer(_video),
                              Center(
                                child: IconButton.filled(
                                  onPressed: _togglePlayback,
                                  iconSize: 34,
                                  icon: Icon(
                                    value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Slider(
                        value: maximum > 0 ? position : 0,
                        max: maximum > 0 ? maximum : 1,
                        onChangeStart: maximum > 0 ? _startScrubbing : null,
                        onChanged: maximum > 0 ? _scrubTo : null,
                        onChangeEnd: maximum > 0 ? _finishScrubbing : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: <Widget>[
                            Text(
                              _formatDuration(
                                Duration(milliseconds: position.round()),
                              ),
                            ),
                            const Spacer(),
                            Text(_formatDuration(_playbackDuration)),
                            const SizedBox(width: 14),
                            OutlinedButton.icon(
                              onPressed: _openTrim,
                              icon: const Icon(Icons.content_cut_rounded),
                              label: const Text('剪辑'),
                            ),
                          ],
                        ),
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
