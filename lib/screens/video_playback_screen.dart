import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_session.dart';

class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({required this.session, super.key});

  final RecordingSession session;

  @override
  State<VideoPlaybackScreen> createState() => _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState extends State<VideoPlaybackScreen> {
  late final VideoPlayerController _video;
  late final Future<void> _initialized;
  late Duration _playbackStart;
  late Duration _playbackEnd;
  bool _handlingBoundary = false;

  @override
  void initState() {
    super.initState();
    _playbackStart = widget.session.mediaStart;
    _playbackEnd = widget.session.playbackEnd;
    _video = VideoPlayerController.file(File(widget.session.filePath));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.session.displayCode)),
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
