import 'package:flutter/material.dart';

import '../app/parcel_lens_app.dart';
import '../models/recording_session.dart';
import '../models/work_mode.dart';
import 'video_playback_screen.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({
    required this.sessions,
    required this.workMode,
    required this.speechEnabled,
    required this.onWorkModeChanged,
    required this.onSpeechEnabledChanged,
    required this.onSpeechPreview,
    required this.onSessionUpdated,
    required this.onDeleteSessions,
    super.key,
  });

  final List<RecordingSession> sessions;
  final WorkMode workMode;
  final bool speechEnabled;
  final Future<void> Function(WorkMode mode) onWorkModeChanged;
  final Future<void> Function(bool enabled) onSpeechEnabledChanged;
  final Future<void> Function() onSpeechPreview;
  final Future<void> Function(RecordingSession session) onSessionUpdated;
  final Future<void> Function(Set<String> sessionIds) onDeleteSessions;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  late WorkMode _workMode;
  late bool _speechEnabled;
  late List<RecordingSession> _sessions;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  String _query = '';
  bool _managing = false;

  List<RecordingSession> get _filteredSessions {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _sessions;
    }
    return _sessions
        .where((RecordingSession session) {
          final DateTime value = session.startedAt;
          final String searchable =
              '${session.displayCode} '
              '${value.year}-${_two(value.month)}-${_two(value.day)} '
              '${value.month}月${value.day}日 '
              '${_two(value.hour)}:${_two(value.minute)}';
          return searchable.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _workMode = widget.workMode;
    _speechEnabled = widget.speechEnabled;
    _sessions = List<RecordingSession>.of(widget.sessions);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _setWorkMode(WorkMode mode) async {
    if (_workMode == mode) {
      return;
    }
    setState(() => _workMode = mode);
    await widget.onWorkModeChanged(mode);
  }

  Future<void> _setSpeechEnabled(bool enabled) async {
    if (_speechEnabled == enabled) {
      return;
    }
    setState(() => _speechEnabled = enabled);
    await widget.onSpeechEnabledChanged(enabled);
  }

  Future<void> _updateSession(RecordingSession updated) async {
    await widget.onSessionUpdated(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      final int index = _sessions.indexWhere(
        (RecordingSession item) => item.id == updated.id,
      );
      if (index >= 0) {
        _sessions[index] = updated;
        _sessions.sort(
          (RecordingSession a, RecordingSession b) =>
              b.startedAt.compareTo(a.startedAt),
        );
      }
    });
  }

  void _toggleManaging() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _managing = !_managing;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _toggleSelectAll(List<RecordingSession> visibleSessions) {
    final Set<String> visibleIds = visibleSessions
        .map((RecordingSession item) => item.id)
        .toSet();
    setState(() {
      if (_selectedIds.containsAll(visibleIds)) {
        _selectedIds.removeAll(visibleIds);
      } else {
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('删除 ${_selectedIds.length} 段录像？'),
        content: const Text('删除后无法恢复；共用同一母视频的其他片段不会受影响'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final Set<String> ids = Set<String>.of(_selectedIds);
    try {
      await widget.onDeleteSessions(ids);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _sessions.removeWhere((RecordingSession item) => ids.contains(item.id));
      _selectedIds.clear();
      _managing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<RecordingSession> visibleSessions = _filteredSessions;
    return Scaffold(
      appBar: AppBar(
        title: Text(_managing ? '已选 ${_selectedIds.length} 项' : '录像与设置'),
        actions: <Widget>[
          if (_sessions.isNotEmpty)
            TextButton(
              onPressed: _toggleManaging,
              child: Text(_managing ? '完成' : '管理'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: <Widget>[
          _WorkModeSettings(workMode: _workMode, onChanged: _setWorkMode),
          const SizedBox(height: 12),
          _SpeechPromptSettings(
            enabled: _speechEnabled,
            onChanged: _setSpeechEnabled,
            onPreview: widget.onSpeechPreview,
          ),
          const SizedBox(height: 20),
          SearchBar(
            key: const Key('recording-search'),
            controller: _searchController,
            hintText: '搜索面单号或日期',
            leading: const Icon(Icons.search_rounded),
            trailing: <Widget>[
              if (_query.isNotEmpty)
                IconButton(
                  tooltip: '清除搜索',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
            onChanged: (String value) => setState(() => _query = value),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 22, 2, 12),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '录像记录',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                if (_managing && visibleSessions.isNotEmpty)
                  TextButton(
                    onPressed: () => _toggleSelectAll(visibleSessions),
                    child: Text(
                      _selectedIds.containsAll(
                            visibleSessions.map(
                              (RecordingSession item) => item.id,
                            ),
                          )
                          ? '取消全选'
                          : '全选',
                    ),
                  ),
              ],
            ),
          ),
          if (_sessions.isEmpty)
            const SizedBox(height: 280, child: _EmptyRecordings())
          else if (visibleSessions.isEmpty)
            const SizedBox(height: 220, child: _NoSearchResults())
          else
            ...List<Widget>.generate(visibleSessions.length, (int index) {
              final RecordingSession session = visibleSessions[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == visibleSessions.length - 1 ? 0 : 10,
                ),
                child: _RecordingTile(
                  session: session,
                  managing: _managing,
                  selected: _selectedIds.contains(session.id),
                  onTap: () {
                    if (_managing) {
                      _toggleSelection(session.id);
                      return;
                    }
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => VideoPlaybackScreen(
                          session: session,
                          onSessionUpdated: _updateSession,
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
        ],
      ),
      bottomNavigationBar: _managing
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: FilledButton.icon(
                onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(_selectedIds.isEmpty ? '选择要删除的录像' : '删除所选录像'),
              ),
            )
          : null,
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

class _SpeechPromptSettings extends StatelessWidget {
  const _SpeechPromptSettings({
    required this.enabled,
    required this.onChanged,
    required this.onPreview,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final Future<void> Function() onPreview;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('speech-prompt-settings'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '语音提示',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 5),
                Text(
                  'Edge 音色，离线自动使用系统语音',
                  style: TextStyle(
                    color: Color(0xFF69716E),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('speech-preview-button'),
            onPressed: enabled ? onPreview : null,
            child: const Text('试听'),
          ),
          Switch(
            key: const Key('speech-enabled-switch'),
            value: enabled,
            onChanged: onChanged,
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

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search_off_rounded, size: 42, color: Color(0xFF7B8380)),
          SizedBox(height: 12),
          Text(
            '没有找到匹配的录像',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({
    required this.session,
    required this.managing,
    required this.selected,
    required this.onTap,
  });

  final RecordingSession session;
  final bool managing;
  final bool selected;
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
              if (managing)
                Checkbox(value: selected, onChanged: (_) => onTap())
              else
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
              if (!managing)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF7B8380),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dateTime(DateTime value) {
  return '${value.month}月${value.day}日 ${_two(value.hour)}:${_two(value.minute)}';
}

String _duration(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.inMinutes)}:${two(value.inSeconds.remainder(60))}';
}

String _two(int number) => number.toString().padLeft(2, '0');
