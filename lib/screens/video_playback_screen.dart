import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/parcel_lens_app.dart';
import '../models/barcode_marker.dart';
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

  @override
  void initState() {
    super.initState();
    _video = VideoPlayerController.file(File(widget.session.filePath));
    _initialized = _video.initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  Future<void> _seek(BarcodeMarker marker) async {
    await _video.seekTo(marker.offset);
    await _video.play();
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
                          onPressed: () {
                            setState(() {
                              _video.value.isPlaying
                                  ? _video.pause()
                                  : _video.play();
                            });
                          },
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
              const SizedBox(height: 20),
              const Text(
                '面单时间标记',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '点任一标记可直接跳到面单经过画面的时刻',
                style: TextStyle(color: Color(0xFF69716E)),
              ),
              const SizedBox(height: 14),
              if (widget.session.markers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5F2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('这段录像中没有识别到面单条码'),
                )
              else
                ...widget.session.markers.map(
                  (BarcodeMarker marker) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: const Color(0xFFE5F2ED),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => _seek(marker),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(
                                Icons.sell_outlined,
                                color: ParcelLensApp.forest,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  marker.code,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                _duration(marker.offset),
                                style: const TextStyle(
                                  color: ParcelLensApp.forest,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

String _duration(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.inMinutes)}:${two(value.inSeconds.remainder(60))}';
}
