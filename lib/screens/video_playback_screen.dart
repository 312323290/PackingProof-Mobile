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

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _playbackStart = _session.mediaStart;
    _playbackEnd = _session.playbackEnd;
    _video = VideoPlayerController.file(File(_session.filePath));
    _initialized = _video.initialize().then((_) async {
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
      appBar: AppBar(
        title: Text(_session.displayCode),
        actions: <Widget>[
          IconButton(
            tooltip: '剪辑',
            onPressed: _video.value.isInitialized ? _openTrim : null,
            icon: const Icon(Icons.content_cut_rounded),
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
            return const Center(child: Text('录像无法播放，请检查文件是否仍在本机'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: _video.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      VideoPlayer(_video),
                      Center(
                        child: IconButton.filled(
                          onPressed: _togglePlayback,
                          iconSize: 34,
                          icon: Icon(
                            _video.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
