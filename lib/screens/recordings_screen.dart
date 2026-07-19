import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/packing_proof_mobile_app.dart';
import '../models/backup_retention_policy.dart';
import '../models/barcode_marker.dart';
import '../models/lan_backup.dart';
import '../models/recording_session.dart';
import '../models/work_mode.dart';
import 'video_playback_screen.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({
    required this.sessions,
    required this.workMode,
    required this.speechEnabled,
    required this.maxVolumeEnabled,
    required this.onWorkModeChanged,
    required this.onSpeechEnabledChanged,
    required this.onMaxVolumeEnabledChanged,
    required this.onSpeechPreview,
    required this.onSessionUpdated,
    required this.onDeleteSessions,
    this.backupSnapshot = const LanBackupSnapshot(),
    this.backupListenable,
    this.backupSnapshotProvider,
    this.onAutoBackupChanged,
    this.onBackupNow,
    this.onDisconnectBackup,
    this.onRetryBackup,
    this.unbackedRetention = UnbackedRetentionPolicy.days30,
    this.backedRetention = BackedRetentionPolicy.days7,
    this.onBackupRetentionChanged,
    this.onLoadRemoteRecordings,
    this.remotePlaybackHeaders = const <String, String>{},
    super.key,
  });

  final List<RecordingSession> sessions;
  final WorkMode workMode;
  final bool speechEnabled;
  final bool maxVolumeEnabled;
  final Future<void> Function(WorkMode mode) onWorkModeChanged;
  final Future<void> Function(bool enabled) onSpeechEnabledChanged;
  final Future<void> Function(bool enabled) onMaxVolumeEnabledChanged;
  final Future<void> Function() onSpeechPreview;
  final Future<void> Function(RecordingSession session) onSessionUpdated;
  final Future<void> Function(Set<String> sessionIds) onDeleteSessions;
  final LanBackupSnapshot backupSnapshot;
  final Listenable? backupListenable;
  final LanBackupSnapshot Function()? backupSnapshotProvider;
  final Future<void> Function(bool enabled)? onAutoBackupChanged;
  final Future<void> Function()? onBackupNow;
  final Future<void> Function()? onDisconnectBackup;
  final Future<void> Function(String jobId)? onRetryBackup;
  final UnbackedRetentionPolicy unbackedRetention;
  final BackedRetentionPolicy backedRetention;
  final Future<void> Function({
    required UnbackedRetentionPolicy unbacked,
    required BackedRetentionPolicy backed,
  })?
  onBackupRetentionChanged;
  final Future<List<RemoteRecording>> Function({
    required int page,
    required int pageSize,
    String keyword,
  })?
  onLoadRemoteRecordings;
  final Map<String, String> remotePlaybackHeaders;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  late WorkMode _workMode;
  late bool _speechEnabled;
  late bool _maxVolumeEnabled;
  late List<RecordingSession> _sessions;
  late LanBackupSnapshot _backupSnapshot;
  late UnbackedRetentionPolicy _unbackedRetention;
  late BackedRetentionPolicy _backedRetention;
  final List<RemoteRecording> _remoteRecordings = <RemoteRecording>[];
  final ScrollController _scrollController = ScrollController();
  Timer? _remoteSearchTimer;
  bool _loadingRemote = false;
  bool _remoteHasMore = true;
  int _remotePage = 0;
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
    _maxVolumeEnabled = widget.maxVolumeEnabled;
    _sessions = List<RecordingSession>.of(widget.sessions);
    _backupSnapshot = widget.backupSnapshot;
    _unbackedRetention = widget.unbackedRetention;
    _backedRetention = widget.backedRetention;
    widget.backupListenable?.addListener(_refreshBackupSnapshot);
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadRemote(reset: true),
    );
  }

  @override
  void dispose() {
    widget.backupListenable?.removeListener(_refreshBackupSnapshot);
    _remoteSearchTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refreshBackupSnapshot() {
    if (!mounted) {
      return;
    }
    setState(() {
      _backupSnapshot =
          widget.backupSnapshotProvider?.call() ?? widget.backupSnapshot;
    });
    if (_backupSnapshot.connected && _remoteRecordings.isEmpty) {
      unawaited(_loadRemote(reset: true));
    }
  }

  List<_RecordingListItem> get _visibleItems {
    final Map<String, RemoteRecording> remoteBySession =
        <String, RemoteRecording>{
          for (final RemoteRecording remote in _remoteRecordings)
            if (remote.sourceSessionId.isNotEmpty)
              remote.sourceSessionId: remote,
        };
    final List<_RecordingListItem> values = _filteredSessions
        .map(
          (RecordingSession local) => _RecordingListItem(
            local: local,
            remote: remoteBySession.remove(local.id),
          ),
        )
        .toList();
    values.addAll(
      _remoteRecordings
          .where(
            (RemoteRecording remote) =>
                remote.sourceSessionId.isEmpty ||
                remoteBySession[remote.sourceSessionId]?.id == remote.id,
          )
          .where(
            (RemoteRecording remote) =>
                !values.any((item) => item.remote?.id == remote.id),
          )
          .map((RemoteRecording remote) => _RecordingListItem(remote: remote)),
    );
    values.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return values;
  }

  void _handleScroll() {
    if (_scrollController.position.extentAfter < 320) {
      unawaited(_loadRemote());
    }
  }

  Future<void> _loadRemote({bool reset = false}) async {
    if (_loadingRemote ||
        widget.onLoadRemoteRecordings == null ||
        !_backupSnapshot.connected ||
        (!reset && !_remoteHasMore)) {
      return;
    }
    _loadingRemote = true;
    if (reset) {
      _remotePage = 0;
      _remoteHasMore = true;
    }
    final int nextPage = _remotePage + 1;
    final List<RemoteRecording> values = await widget.onLoadRemoteRecordings!(
      page: nextPage,
      pageSize: 50,
      keyword: _query,
    );
    if (!mounted) return;
    setState(() {
      if (reset) _remoteRecordings.clear();
      _remoteRecordings.addAll(values);
      _remotePage = nextPage;
      _remoteHasMore = values.length == 50;
      _loadingRemote = false;
    });
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _remoteSearchTimer?.cancel();
    _remoteSearchTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_loadRemote(reset: true)),
    );
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

  Future<void> _setMaxVolumeEnabled(bool enabled) async {
    if (_maxVolumeEnabled == enabled) {
      return;
    }
    setState(() => _maxVolumeEnabled = enabled);
    await widget.onMaxVolumeEnabledChanged(enabled);
  }

  Future<void> _setUnbackedRetention(UnbackedRetentionPolicy value) async {
    setState(() => _unbackedRetention = value);
    await widget.onBackupRetentionChanged?.call(
      unbacked: value,
      backed: _backedRetention,
    );
  }

  Future<void> _setBackedRetention(BackedRetentionPolicy value) async {
    if (value == BackedRetentionPolicy.immediately) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('备份后立即清除？'),
          content: const Text(
            '录像成功备份到电脑后，将自动删除手机中的本机文件。电脑离线时仍可查看录像记录，但无法播放远程视频。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _backedRetention = value);
    await widget.onBackupRetentionChanged?.call(
      unbacked: _unbackedRetention,
      backed: value,
    );
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
    final List<_RecordingListItem> visibleItems = _visibleItems;
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
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: <Widget>[
          _WorkModeSettings(workMode: _workMode, onChanged: _setWorkMode),
          const SizedBox(height: 12),
          _SpeechPromptSettings(
            enabled: _speechEnabled,
            onChanged: _setSpeechEnabled,
            onPreview: widget.onSpeechPreview,
          ),
          const SizedBox(height: 12),
          _MaxVolumeSettings(
            enabled: _maxVolumeEnabled,
            onChanged: _setMaxVolumeEnabled,
          ),
          const SizedBox(height: 12),
          _ComputerBackupSettings(
            snapshot: _backupSnapshot,
            onConnect: () => Navigator.of(context).pop(true),
            onAutoChanged: widget.onAutoBackupChanged,
            onBackupNow: widget.onBackupNow,
            onDisconnect: widget.onDisconnectBackup,
            onRetry: widget.onRetryBackup,
            unbackedRetention: _unbackedRetention,
            backedRetention: _backedRetention,
            onUnbackedRetentionChanged: _setUnbackedRetention,
            onBackedRetentionChanged: _setBackedRetention,
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
                    unawaited(_loadRemote(reset: true));
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
            onChanged: _onSearchChanged,
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
          if (_sessions.isEmpty && _remoteRecordings.isEmpty)
            const SizedBox(height: 280, child: _EmptyRecordings())
          else if (visibleItems.isEmpty)
            const SizedBox(height: 220, child: _NoSearchResults())
          else
            ...List<Widget>.generate(visibleItems.length, (int index) {
              final _RecordingListItem item = visibleItems[index];
              final RecordingSession session = item.session;
              final bool localAvailable =
                  item.local != null && File(item.local!.filePath).existsSync();
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == visibleItems.length - 1 ? 0 : 10,
                ),
                child: _RecordingTile(
                  session: session,
                  backupJob: _backupSnapshot.jobs
                      .where(
                        (LanBackupJob job) => job.filePath == session.filePath,
                      )
                      .firstOrNull,
                  managing: _managing && item.local != null,
                  sourceLabel: localAvailable
                      ? (item.remote == null ? '本机' : '本机 · 已备份')
                      : (item.remote == null ? '已备份 · 电脑离线' : '电脑录像'),
                  selected: _selectedIds.contains(session.id),
                  onTap: () {
                    if (_managing) {
                      if (item.local != null) _toggleSelection(session.id);
                      return;
                    }
                    FocusManager.instance.primaryFocus?.unfocus();
                    if (!localAvailable && item.remote == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('电脑当前不可用，暂时无法播放这段录像')),
                      );
                      return;
                    }
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => VideoPlaybackScreen(
                          session: session,
                          onSessionUpdated: _updateSession,
                          remoteUri: localAvailable
                              ? null
                              : item.remote?.playUri,
                          remoteHeaders: widget.remotePlaybackHeaders,
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
          if (_loadingRemote)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
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

class _RecordingListItem {
  const _RecordingListItem({this.local, this.remote})
    : assert(local != null || remote != null);

  final RecordingSession? local;
  final RemoteRecording? remote;

  DateTime get startedAt => local?.startedAt ?? remote!.startedAt;

  RecordingSession get session {
    if (local != null) return local!;
    final RemoteRecording value = remote!;
    return RecordingSession(
      id: 'remote-${value.id}',
      filePath: '',
      startedAt: value.startedAt,
      endedAt: value.startedAt.add(value.duration),
      markers: value.trackingNumber.isEmpty
          ? const <BarcodeMarker>[]
          : <BarcodeMarker>[
              BarcodeMarker(
                code: value.trackingNumber,
                occurredAt: value.startedAt,
                offset: Duration.zero,
              ),
            ],
    );
  }
}

class _ComputerBackupSettings extends StatelessWidget {
  const _ComputerBackupSettings({
    required this.snapshot,
    required this.onConnect,
    this.onAutoChanged,
    this.onBackupNow,
    this.onDisconnect,
    this.onRetry,
    required this.unbackedRetention,
    required this.backedRetention,
    required this.onUnbackedRetentionChanged,
    required this.onBackedRetentionChanged,
  });

  final LanBackupSnapshot snapshot;
  final VoidCallback onConnect;
  final Future<void> Function(bool enabled)? onAutoChanged;
  final Future<void> Function()? onBackupNow;
  final Future<void> Function()? onDisconnect;
  final Future<void> Function(String jobId)? onRetry;
  final UnbackedRetentionPolicy unbackedRetention;
  final BackedRetentionPolicy backedRetention;
  final ValueChanged<UnbackedRetentionPolicy> onUnbackedRetentionChanged;
  final ValueChanged<BackedRetentionPolicy> onBackedRetentionChanged;

  @override
  Widget build(BuildContext context) {
    final LanBackupJob? active = snapshot.jobs.cast<LanBackupJob?>().firstWhere(
      (LanBackupJob? job) => job?.state == LanBackupJobState.uploading,
      orElse: () => null,
    );
    final LanBackupJob? failed = snapshot.jobs.cast<LanBackupJob?>().firstWhere(
      (LanBackupJob? job) => job?.state == LanBackupJobState.failed,
      orElse: () => null,
    );
    final int progress = (snapshot.aggregateProgress * 100).round();
    final String status = !snapshot.connected
        ? '扫描电脑二维码后自动备份'
        : snapshot.connectionStatus == LanConnectionStatus.rePair
        ? '需要重新配对'
        : snapshot.connectionStatus == LanConnectionStatus.offline
        ? '电脑离线，恢复网络后自动续传'
        : active != null || snapshot.activeCount > 0
        ? '正在备份 ${snapshot.activeCount}/${snapshot.jobs.length} · $progress%'
        : failed != null
        ? (failed.errorMessage ?? '备份失败')
        : snapshot.pendingCount > 0
        ? '还有 ${snapshot.pendingCount} 个录像待备份'
        : '已连接 ${snapshot.endpoint!.computerName} · ${snapshot.endpoint!.displayAddress}';

    return Container(
      key: const Key('computer-backup-settings'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '电脑备份',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              if (snapshot.connected) ...<Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDEDE7),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    '已连接',
                    style: TextStyle(
                      color: PackingProofMobileApp.forest,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Switch(
                  key: const Key('auto-backup-switch'),
                  value: snapshot.autoEnabled,
                  onChanged: onAutoChanged,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF69716E),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (active != null || snapshot.activeCount > 0) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: snapshot.aggregateProgress),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<UnbackedRetentionPolicy>(
                  key: const Key('unbacked-retention-dropdown'),
                  initialValue: unbackedRetention,
                  decoration: const InputDecoration(
                    labelText: '未备份保留',
                    isDense: true,
                  ),
                  items: UnbackedRetentionPolicy.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) onUnbackedRetentionChanged(value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<BackedRetentionPolicy>(
                  key: const Key('backed-retention-dropdown'),
                  initialValue: backedRetention,
                  decoration: const InputDecoration(
                    labelText: '备份后保留',
                    isDense: true,
                  ),
                  items: BackedRetentionPolicy.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) onBackedRetentionChanged(value);
                  },
                ),
              ),
            ],
          ),
          if (unbackedRetention !=
              UnbackedRetentionPolicy.keepForever) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              '超过保留时间且仍未完成电脑备份的录像将从本机永久删除',
              style: TextStyle(
                color: Color(0xFFD15B2A),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              if (!snapshot.connected)
                FilledButton.tonalIcon(
                  key: const Key('connect-computer-button'),
                  onPressed: onConnect,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('连接电脑'),
                )
              else ...<Widget>[
                TextButton(onPressed: onBackupNow, child: const Text('立即备份')),
                if (failed != null)
                  TextButton(
                    onPressed: onRetry == null
                        ? null
                        : () => onRetry!(failed.id),
                    child: const Text('重试'),
                  ),
                TextButton(onPressed: onDisconnect, child: const Text('断开')),
              ],
            ],
          ),
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

class _MaxVolumeSettings extends StatelessWidget {
  const _MaxVolumeSettings({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('max-volume-settings'),
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
                  '最大音量',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 5),
                Text(
                  '工作时自动提高媒体音量',
                  style: TextStyle(
                    color: Color(0xFF69716E),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: const Key('max-volume-enabled-switch'),
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
                color: PackingProofMobileApp.forest,
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
    required this.sourceLabel,
    this.backupJob,
  });

  final RecordingSession session;
  final bool managing;
  final bool selected;
  final VoidCallback onTap;
  final LanBackupJob? backupJob;
  final String sourceLabel;

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
                    color: PackingProofMobileApp.forest,
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
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        _StatusChip(label: sourceLabel),
                        if (backupJob != null)
                          _StatusChip(
                            label: _backupLabel(backupJob!),
                            error: backupJob!.state == LanBackupJobState.failed,
                          ),
                      ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.error = false});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFE5E2) : const Color(0xFFDDEDE7),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: error
                ? const Color(0xFFD92D20)
                : PackingProofMobileApp.forest,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String _backupLabel(LanBackupJob job) => switch (job.state) {
  LanBackupJobState.pending => '待备份',
  LanBackupJobState.uploading => '备份中 ${(job.progress * 100).round()}%',
  LanBackupJobState.paused => '等待续传',
  LanBackupJobState.completed => '已备份',
  LanBackupJobState.failed => '备份失败',
};

String _dateTime(DateTime value) {
  return '${value.month}月${value.day}日 ${_two(value.hour)}:${_two(value.minute)}';
}

String _duration(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.inMinutes)}:${two(value.inSeconds.remainder(60))}';
}

String _two(int number) => number.toString().padLeft(2, '0');
