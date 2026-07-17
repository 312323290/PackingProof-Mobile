import 'package:flutter/material.dart';

import '../app/parcel_lens_app.dart';
import '../models/recording_session.dart';
import '../models/work_mode.dart';
import 'video_playback_screen.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({
    required this.sessions,
    required this.workMode,
    required this.onWorkModeChanged,
    super.key,
  });

  final List<RecordingSession> sessions;
  final WorkMode workMode;
  final Future<void> Function(WorkMode mode) onWorkModeChanged;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  late WorkMode _workMode;

  @override
  void initState() {
    super.initState();
    _workMode = widget.workMode;
  }

  Future<void> _setWorkMode(WorkMode mode) async {
    if (_workMode == mode) {
      return;
    }
    setState(() => _workMode = mode);
    await widget.onWorkModeChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('录像与设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: <Widget>[
          _WorkModeSettings(workMode: _workMode, onChanged: _setWorkMode),
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 24, 2, 12),
            child: Text(
              '录像记录',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          if (widget.sessions.isEmpty)
            const SizedBox(height: 280, child: _EmptyRecordings())
          else
            ...List<Widget>.generate(widget.sessions.length, (int index) {
              final RecordingSession session = widget.sessions[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == widget.sessions.length - 1 ? 0 : 10,
                ),
                child: _RecordingTile(
                  session: session,
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            VideoPlaybackScreen(session: session),
                      ),
                    );
                  },
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _WorkModeSettings extends StatelessWidget {
  const _WorkModeSettings({required this.workMode, required this.onChanged});

  final WorkMode workMode;
  final ValueChanged<WorkMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('work-mode-settings'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '工作模式',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<WorkMode>(
              showSelectedIcon: false,
              segments: WorkMode.values
                  .map(
                    (WorkMode mode) => ButtonSegment<WorkMode>(
                      value: mode,
                      label: Text(mode.label),
                    ),
                  )
                  .toList(growable: false),
              selected: <WorkMode>{workMode},
              onSelectionChanged: (Set<WorkMode> values) {
                onChanged(values.single);
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            workMode.description,
            style: const TextStyle(
              color: Color(0xFF69716E),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecordings extends StatelessWidget {
  const _EmptyRecordings();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: Color(0xFFE7F2EE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_library_outlined,
                size: 34,
                color: ParcelLensApp.forest,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '还没有录像',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            const Text(
              '返回首页点“开始工作”，录像会自动保存在这里',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF69716E), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({required this.session, required this.onTap});

  final RecordingSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F6F3),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDEDE7),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: ParcelLensApp.forest,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      session.displayCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_dateTime(session.startedAt)}  ·  ${_duration(session.duration)}',
                      style: const TextStyle(
                        color: Color(0xFF69716E),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF7B8380)),
            ],
          ),
        ),
      ),
    );
  }
}

String _dateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.month}月${value.day}日 ${two(value.hour)}:${two(value.minute)}';
}

String _duration(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.inMinutes)}:${two(value.inSeconds.remainder(60))}';
}
