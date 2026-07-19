import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/packing_proof_mobile_app.dart';
import '../models/backup_retention_policy.dart';
import '../models/barcode_marker.dart';
import '../models/lan_backup.dart';
import '../models/recording_session.dart';
import '../models/work_mode.dart';
import '../widgets/about_settings.dart';
import '../widgets/two_button_confirm_dialog.dart';
import 'video_playback_screen.dart';

enum RecordingsScreenMode { history, settings }

enum RecordingSourceFilter { all, local, backedUp, computer }

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
    this.onLoadRemoteRecordingStatuses,
    this.hiddenRemoteRecordingIds = const <int>{},
    this.onHideRemoteRecordings,
    this.remotePlaybackHeaders = const <String, String>{},
    this.mode = RecordingsScreenMode.history,
    this.embedded = false,
    this.onConnectComputer,
    this.onScanSearch,
    this.externalSearchQuery = '',
    this.active = true,
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
  final Future<RemoteRecordingPage> Function({
    required int page,
    required int pageSize,
    String keyword,
  })?
  onLoadRemoteRecordings;
  final Future<
    Map<int, ({RemoteRecordingStatus status, bool exists, String reason})>
  >
  Function(Iterable<int> ids)?
  onLoadRemoteRecordingStatuses;
  final Set<int> hiddenRemoteRecordingIds;
  final Future<void> Function(Set<int> ids)? onHideRemoteRecordings;
  final Map<String, String> remotePlaybackHeaders;
  final RecordingsScreenMode mode;
  final bool embedded;
  final VoidCallback? onConnectComputer;
  final VoidCallback? onScanSearch;
  final String externalSearchQuery;
  final bool active;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  static const int _historyPageSize = 10;

  late WorkMode _workMode;
  late bool _speechEnabled;
  late bool _maxVolumeEnabled;
  late List<RecordingSession> _sessions;
  late LanBackupSnapshot _backupSnapshot;
  late UnbackedRetentionPolicy _unbackedRetention;
  late BackedRetentionPolicy _backedRetention;
  final List<RemoteRecording> _remoteRecordings = <RemoteRecording>[];
  final Map<int, List<RemoteRecording>> _remotePages =
      <int, List<RemoteRecording>>{};
  final Map<int, ({RemoteRecordingStatus status, bool exists, String reason})>
  _remoteStatuses = {};
  late Set<int> _hiddenRemoteIds;
  Timer? _remoteSearchTimer;
  bool _loadingRemote = false;
  int _remoteTotal = 0;
  int _remoteDeviceTotal = 0;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  String _query = '';
  bool _managing = false;
  int _historyPage = 0;
  int _remoteRequestGeneration = 0;
  RecordingSourceFilter _sourceFilter = RecordingSourceFilter.all;

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
    _hiddenRemoteIds = Set<int>.of(widget.hiddenRemoteRecordingIds);
    _applyExternalSearch(widget.externalSearchQuery);
    widget.backupListenable?.addListener(_refreshBackupSnapshot);
    if (widget.mode == RecordingsScreenMode.history && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadRemote(reset: true, pageNumber: 1, prefetchNext: true),
      );
    }
  }

  @override
  void didUpdateWidget(covariant RecordingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessions, widget.sessions)) {
      _sessions = List<RecordingSession>.of(widget.sessions);
    }
    _workMode = widget.workMode;
    _speechEnabled = widget.speechEnabled;
    _maxVolumeEnabled = widget.maxVolumeEnabled;
    _unbackedRetention = widget.unbackedRetention;
    _backedRetention = widget.backedRetention;
    _hiddenRemoteIds.addAll(widget.hiddenRemoteRecordingIds);
    if (!oldWidget.active && widget.active && _remoteRecordings.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(
          _loadRemote(reset: true, pageNumber: 1, prefetchNext: true),
        ),
      );
    }
    if (oldWidget.externalSearchQuery != widget.externalSearchQuery &&
        widget.externalSearchQuery.isNotEmpty) {
      _applyExternalSearch(widget.externalSearchQuery);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(
          _loadRemote(reset: true, pageNumber: 1, prefetchNext: true),
        ),
      );
    }
  }

  void _applyExternalSearch(String value) {
    if (value.isEmpty) return;
    _query = value;
    _searchController.text = value;
    _searchController.selection = TextSelection.collapsed(offset: value.length);
  }

  @override
  void dispose() {
    widget.backupListenable?.removeListener(_refreshBackupSnapshot);
    _remoteSearchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _refreshBackupSnapshot() {
    if (!mounted) {
      return;
    }
    final LanBackupSnapshot next =
        widget.backupSnapshotProvider?.call() ?? widget.backupSnapshot;
    setState(() {
      _backupSnapshot = next;
      if (next.connectionStatus != LanConnectionStatus.connected) {
        _remoteRequestGeneration++;
        _loadingRemote = false;
      }
      if (next.endpoint == null) {
        _remoteRecordings.clear();
        _remotePages.clear();
        _remoteTotal = 0;
        _remoteDeviceTotal = 0;
        _historyPage = 0;
      }
    });
    if (widget.active &&
        _backupSnapshot.connectionStatus == LanConnectionStatus.connected &&
        _remoteRecordings.isEmpty) {
      unawaited(_loadRemote(reset: true, pageNumber: 1, prefetchNext: true));
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
    final Set<int> includedRemoteIds = values
        .map((item) => item.remote?.id)
        .whereType<int>()
        .toSet();
    for (final RemoteRecording remote in _remoteRecordings) {
      if (!_hiddenRemoteIds.contains(remote.id) &&
          includedRemoteIds.add(remote.id)) {
        values.add(_RecordingListItem(remote: remote));
      }
    }
    values.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return values
        .where((item) {
          final bool hasLocalFile =
              item.local != null && File(item.local!.filePath).existsSync();
          final bool backedUp =
              item.remote != null ||
              (item.local != null &&
                  _backupSnapshot.jobs.any(
                    (job) =>
                        job.filePath == item.local!.filePath &&
                        job.state == LanBackupJobState.completed &&
                        job.destinationComputerId ==
                            _backupSnapshot.endpoint?.computerId,
                  ));
          return switch (_sourceFilter) {
            RecordingSourceFilter.all => true,
            RecordingSourceFilter.local => hasLocalFile,
            RecordingSourceFilter.backedUp => backedUp,
            RecordingSourceFilter.computer =>
              !hasLocalFile && item.remote != null,
          };
        })
        .toList(growable: false);
  }

  Future<void> _loadRemote({
    bool reset = false,
    required int pageNumber,
    bool prefetchNext = false,
  }) async {
    if (_loadingRemote ||
        !widget.active ||
        widget.onLoadRemoteRecordings == null ||
        _backupSnapshot.connectionStatus != LanConnectionStatus.connected) {
      return;
    }
    final int requestGeneration = ++_remoteRequestGeneration;
    setState(() {
      _loadingRemote = true;
      if (reset) {
        _remotePages.clear();
        _remoteRecordings.clear();
        _remoteTotal = 0;
        _remoteDeviceTotal = 0;
        _historyPage = 0;
      }
    });
    try {
      final RemoteRecordingPage result = await widget.onLoadRemoteRecordings!(
        page: pageNumber,
        pageSize: _historyPageSize,
        keyword: _query,
      );
      if (!mounted || requestGeneration != _remoteRequestGeneration) return;
      setState(() {
        _remotePages[result.page] = result.data;
        _remoteTotal = result.total;
        _remoteDeviceTotal = result.deviceTotal;
        _rebuildRemoteRecordings();
      });
      await _refreshRemoteStatuses(result.data);
      if (prefetchNext && result.hasMore && mounted) {
        await _loadRemotePageWithoutBusy(result.page + 1, requestGeneration);
      }
    } on Object {
      // Connection state is updated by the backup service; cached rows stay visible.
    } finally {
      if (mounted && requestGeneration == _remoteRequestGeneration) {
        setState(() => _loadingRemote = false);
      }
    }
  }

  Future<void> _loadRemotePageWithoutBusy(
    int pageNumber,
    int requestGeneration,
  ) async {
    if (_remotePages.containsKey(pageNumber) ||
        widget.onLoadRemoteRecordings == null ||
        _backupSnapshot.connectionStatus != LanConnectionStatus.connected) {
      return;
    }
    final RemoteRecordingPage page = await widget.onLoadRemoteRecordings!(
      page: pageNumber,
      pageSize: _historyPageSize,
      keyword: _query,
    );
    if (!mounted || requestGeneration != _remoteRequestGeneration) return;
    setState(() {
      _remotePages[page.page] = page.data;
      _remoteTotal = page.total;
      _remoteDeviceTotal = page.deviceTotal;
      _rebuildRemoteRecordings();
    });
    await _refreshRemoteStatuses(page.data);
  }

  void _rebuildRemoteRecordings() {
    final entries = _remotePages.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    _remoteRecordings
      ..clear()
      ..addAll(entries.expand((entry) => entry.value));
  }

  Future<void> _refreshRemoteStatuses(List<RemoteRecording> page) async {
    final callback = widget.onLoadRemoteRecordingStatuses;
    if (callback == null) return;
    final Set<int> ids = page.map((item) => item.id).toSet()
      ..addAll(
        _backupSnapshot.jobs
            .where(
              (job) =>
                  job.destinationComputerId ==
                  _backupSnapshot.endpoint?.computerId,
            )
            .expand((job) => job.remoteRecordIds),
      );
    if (ids.isEmpty) return;
    try {
      final statuses = await callback(ids);
      if (!mounted || statuses.isEmpty) return;
      setState(() {
        _remoteStatuses.addAll(statuses);
        for (final int pageNumber in _remotePages.keys.toList()) {
          _remotePages[pageNumber] = _remotePages[pageNumber]!
              .map((RemoteRecording item) {
                final status = statuses[item.id];
                return status == null
                    ? item
                    : item.withStatus(
                        status: status.status,
                        exists: status.exists,
                        reason: status.reason,
                      );
              })
              .toList(growable: false);
        }
        _rebuildRemoteRecordings();
      });
    } on Object {
      // The page remains usable with the availability returned by /api/videos.
    }
  }

  Future<void> _confirmDeleteComputer() async {
    final LanBackupEndpoint? endpoint = _backupSnapshot.endpoint;
    if (endpoint == null || widget.onDisconnectBackup == null) return;
    final bool? continueDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => const TwoButtonConfirmDialog(
        title: '删除这台电脑？',
        message: '将删除电脑地址和连接密钥，并停止当前备份。手机中的录像不会被删除。',
        confirmLabel: '继续',
      ),
    );
    if (continueDelete != true || !mounted) return;
    final String identity = endpoint.computerName.isEmpty
        ? endpoint.displayAddress
        : '${endpoint.computerName}\n${endpoint.displayAddress}';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => TwoButtonConfirmDialog(
        title: '再次确认删除',
        message: '确定删除以下电脑？\n\n$identity',
        confirmLabel: '确认删除',
        dangerous: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.onDisconnectBackup!();
    if (!mounted) return;
    setState(() {
      _remoteRequestGeneration++;
      _loadingRemote = false;
      _remoteRecordings.clear();
      _remotePages.clear();
      _remoteTotal = 0;
      _remoteDeviceTotal = 0;
      _historyPage = 0;
    });
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _historyPage = 0;
    });
    _remoteSearchTimer?.cancel();
    _remoteSearchTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(
        _loadRemote(reset: true, pageNumber: 1, prefetchNext: true),
      ),
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
        builder: (BuildContext context) => const TwoButtonConfirmDialog(
          title: '备份后立即清除？',
          message: '录像成功备份到电脑后，将自动删除手机中的本机文件。电脑离线时仍可查看录像记录，但无法播放远程视频。',
          confirmLabel: '确认',
          dangerous: true,
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
      builder: (BuildContext context) => TwoButtonConfirmDialog(
        title: '删除 ${_selectedIds.length} 段录像？',
        message: '删除后无法恢复；共用同一母视频的其他片段不会受影响',
        confirmLabel: '删除',
        dangerous: true,
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

  Future<void> _pasteSearch() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String value = data?.text?.trim() ?? '';
    if (!mounted || value.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('剪贴板里没有可用文本')));
      }
      return;
    }
    _searchController.text = value;
    _searchController.selection = TextSelection.collapsed(offset: value.length);
    _onSearchChanged(value);
  }

  Future<void> _showSourceFilter() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    final RecordingSourceFilter? value =
        await showModalBottomSheet<RecordingSourceFilter>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: RecordingSourceFilter.values
                  .map(
                    (filter) => ListTile(
                      leading: Icon(
                        filter == _sourceFilter
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: filter == _sourceFilter
                            ? PackingProofMobileApp.forest
                            : null,
                      ),
                      title: Text(_sourceFilterLabel(filter)),
                      onTap: () => Navigator.of(context).pop(filter),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
    if (value != null && mounted) {
      setState(() {
        _sourceFilter = value;
        _historyPage = 0;
      });
    }
  }

  Future<void> _showNextHistoryPage(int pageCount) async {
    if (_historyPage + 1 >= pageCount) return;
    final int nextHistoryPage = _historyPage + 1;
    final int remotePage = nextHistoryPage + 1;
    if (!_remotePages.containsKey(remotePage) &&
        _backupSnapshot.connectionStatus == LanConnectionStatus.connected) {
      await _loadRemote(pageNumber: remotePage);
    }
    if (!mounted) return;
    setState(() => _historyPage = nextHistoryPage);
    final int prefetchPage = remotePage + 1;
    if (prefetchPage <= (_remoteTotal / _historyPageSize).ceil() &&
        !_remotePages.containsKey(prefetchPage) &&
        _backupSnapshot.connectionStatus == LanConnectionStatus.connected) {
      unawaited(_loadRemote(pageNumber: prefetchPage));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<RecordingSession> visibleSessions = _filteredSessions;
    final List<_RecordingListItem> visibleItems = _visibleItems;
    final int localCount = _filteredSessions
        .where((session) => File(session.filePath).existsSync())
        .length;
    final int localLogicalCount = _filteredSessions.length;
    final int estimatedCount = switch (_sourceFilter) {
      RecordingSourceFilter.local => localCount,
      RecordingSourceFilter.backedUp => _remoteDeviceTotal,
      RecordingSourceFilter.computer => _remoteTotal,
      RecordingSourceFilter.all =>
        localLogicalCount +
            _remoteTotal -
            _remoteDeviceTotal.clamp(0, localLogicalCount),
    };
    final int historyPageCount = estimatedCount <= 0
        ? (visibleItems.isEmpty ? 0 : 1)
        : (estimatedCount / _historyPageSize).ceil();
    final int historyPage = historyPageCount == 0
        ? 0
        : _historyPage >= historyPageCount
        ? historyPageCount - 1
        : _historyPage;
    final List<_RecordingListItem> pageItems = visibleItems
        .skip(historyPage * _historyPageSize)
        .take(_historyPageSize)
        .toList(growable: false);
    final bool historyMode = widget.mode == RecordingsScreenMode.history;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(
          _managing
              ? '已选 ${_selectedIds.length} 项'
              : historyMode
              ? '订单历史'
              : '设置',
        ),
        actions: <Widget>[
          if (historyMode && _sessions.isNotEmpty)
            TextButton(
              onPressed: _toggleManaging,
              child: Text(_managing ? '完成' : '管理'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: <Widget>[
          if (!historyMode) ...<Widget>[
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
            _RetentionSettings(
              unbackedRetention: _unbackedRetention,
              backedRetention: _backedRetention,
              onUnbackedRetentionChanged: _setUnbackedRetention,
              onBackedRetentionChanged: _setBackedRetention,
            ),
            const SizedBox(height: 12),
            const AboutSettings(),
          ] else ...<Widget>[
            _HistorySummary(
              total: _sessions.length,
              today: _sessions.where((item) => _isToday(item.startedAt)).length,
              backedUp: _backupSnapshot.completedCount,
            ),
            const SizedBox(height: 12),
            _ComputerBackupSettings(
              snapshot: _backupSnapshot,
              allBackedUp: _allLocalFilesBackedUp,
              onConnect:
                  widget.onConnectComputer ??
                  () => Navigator.of(context).pop(true),
              onAutoChanged: widget.onAutoBackupChanged,
              onBackupNow: widget.onBackupNow,
              onDisconnect: _confirmDeleteComputer,
              onRetry: widget.onRetryBackup,
              unbackedRetention: _unbackedRetention,
              backedRetention: _backedRetention,
              onUnbackedRetentionChanged: _setUnbackedRetention,
              onBackedRetentionChanged: _setBackedRetention,
              showRetention: false,
            ),
            const SizedBox(height: 16),
            SearchBar(
              key: const Key('recording-search'),
              controller: _searchController,
              hintText: '搜索面单号或日期',
              leading: const Icon(Icons.search_rounded),
              trailing: <Widget>[
                IconButton(
                  key: const Key('scan-search-button'),
                  tooltip: '扫描条码搜索',
                  onPressed: widget.onScanSearch,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
                IconButton(
                  key: const Key('paste-search-button'),
                  tooltip: '粘贴搜索内容',
                  onPressed: _pasteSearch,
                  icon: const Icon(Icons.content_paste_rounded),
                ),
                if (_query.isNotEmpty)
                  IconButton(
                    tooltip: '清除搜索',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _query = '';
                        _historyPage = 0;
                      });
                      unawaited(
                        _loadRemote(
                          reset: true,
                          pageNumber: 1,
                          prefetchNext: true,
                        ),
                      );
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
              onChanged: _onSearchChanged,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 18, 2, 12),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '录像记录',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
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
                  const SizedBox(width: 8),
                  FilterChip(
                    key: const Key('recording-source-filter'),
                    avatar: const Icon(Icons.filter_alt_rounded, size: 18),
                    label: Text(_sourceFilterLabel(_sourceFilter)),
                    selected: _sourceFilter != RecordingSourceFilter.all,
                    showCheckmark: false,
                    onSelected: (_) => _showSourceFilter(),
                  ),
                ],
              ),
            ),
            if (_sessions.isEmpty && _remoteRecordings.isEmpty)
              const SizedBox(height: 280, child: _EmptyRecordings())
            else if (visibleItems.isEmpty)
              const SizedBox(height: 220, child: _NoSearchResults())
            else
              ...List<Widget>.generate(pageItems.length, (int index) {
                final _RecordingListItem item = pageItems[index];
                final RecordingSession session = item.session;
                final bool localAvailable =
                    item.local != null &&
                    File(item.local!.filePath).existsSync();
                final LanBackupJob? backupJob = item.local == null
                    ? null
                    : _backupSnapshot.jobs
                          .where(
                            (LanBackupJob job) =>
                                job.filePath == item.local!.filePath,
                          )
                          .firstOrNull;
                final bool remoteAvailable =
                    item.remote != null &&
                    item.remote!.status == RemoteRecordingStatus.available &&
                    item.remote!.exists;
                final bool computerCleared =
                    (item.remote != null && !remoteAvailable) ||
                    (backupJob?.remoteRecordIds.any(
                          (id) =>
                              _remoteStatuses[id]?.status != null &&
                              _remoteStatuses[id]!.status !=
                                  RemoteRecordingStatus.available,
                        ) ??
                        false);
                final bool unavailable = !localAvailable && !remoteAvailable;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == pageItems.length - 1 ? 0 : 10,
                  ),
                  child: _RecordingTile(
                    session: session,
                    backupJob: backupJob,
                    managing: _managing && item.local != null,
                    unavailable: unavailable,
                    sourceLabel: localAvailable
                        ? (computerCleared
                              ? '本机 · 电脑已清理'
                              : remoteAvailable ||
                                    backupJob?.state ==
                                        LanBackupJobState.completed
                              ? '本机 · 已备份'
                              : '本机')
                        : (item.remote == null
                              ? '已备份 · 电脑离线'
                              : remoteAvailable
                              ? '电脑录像'
                              : '电脑录像 · 已清理'),
                    selected: _selectedIds.contains(session.id),
                    onTap: () async {
                      if (_managing) {
                        if (item.local != null) _toggleSelection(session.id);
                        return;
                      }
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (unavailable) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('录像已清理或文件不存在，无法播放')),
                        );
                        return;
                      }
                      final bool? deleted = await Navigator.of(context)
                          .push<bool>(
                            MaterialPageRoute<bool>(
                              builder: (BuildContext context) =>
                                  VideoPlaybackScreen(
                                    session: session,
                                    onSessionUpdated: _updateSession,
                                    onDelete: item.local == null
                                        ? null
                                        : () => widget.onDeleteSessions(
                                            <String>{item.local!.id},
                                          ),
                                    remoteUri: localAvailable
                                        ? null
                                        : remoteAvailable
                                        ? item.remote?.playUri
                                        : null,
                                    remoteHeaders: widget.remotePlaybackHeaders,
                                  ),
                            ),
                          );
                      if (deleted == true && mounted && item.local != null) {
                        final Set<int> hiddenIds = <int>{
                          if (item.remote != null) item.remote!.id,
                          if (backupJob != null) ...backupJob.remoteRecordIds,
                        };
                        setState(() {
                          _hiddenRemoteIds.addAll(hiddenIds);
                          _sessions.removeWhere(
                            (RecordingSession value) =>
                                value.id == item.local!.id,
                          );
                        });
                        await widget.onHideRemoteRecordings?.call(hiddenIds);
                      }
                    },
                  ),
                );
              }),
            if (historyPageCount > 1)
              _HistoryPagination(
                currentPage: historyPage,
                pageCount: historyPageCount,
                loading: _loadingRemote,
                offline:
                    _backupSnapshot.connected &&
                    _backupSnapshot.connectionStatus !=
                        LanConnectionStatus.connected,
                canLoadMore: historyPage + 1 < historyPageCount,
                onPrevious: historyPage == 0
                    ? null
                    : () => setState(() => _historyPage = historyPage - 1),
                onNext: historyPage + 1 < historyPageCount
                    ? () => _showNextHistoryPage(historyPageCount)
                    : null,
              ),
          ],
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

  bool get _allLocalFilesBackedUp {
    final Set<String> localPaths = _sessions
        .map((RecordingSession session) => session.filePath)
        .where((String path) => path.isNotEmpty)
        .toSet();
    final String currentComputerId = _backupSnapshot.endpoint?.computerId ?? '';
    final Set<String> completedPaths = _backupSnapshot.jobs
        .where(
          (LanBackupJob job) =>
              job.state == LanBackupJobState.completed &&
              job.destinationComputerId == currentComputerId,
        )
        .map((LanBackupJob job) => job.filePath)
        .toSet();
    return localPaths.every(completedPaths.contains);
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

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({
    required this.total,
    required this.today,
    required this.backedUp,
  });

  final int total;
  final int today;
  final int backedUp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _SummaryMetric(label: '本机全部', value: total),
        const SizedBox(width: 10),
        _SummaryMetric(label: '本机今日', value: today),
        const SizedBox(width: 10),
        _SummaryMetric(label: '已备份', value: backedUp),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F6F4),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: <Widget>[
            Text(
              '$value',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Color(0xFF69716E))),
          ],
        ),
      ),
    );
  }
}

class _RetentionSettings extends StatelessWidget {
  const _RetentionSettings({
    required this.unbackedRetention,
    required this.backedRetention,
    required this.onUnbackedRetentionChanged,
    required this.onBackedRetentionChanged,
  });

  final UnbackedRetentionPolicy unbackedRetention;
  final BackedRetentionPolicy backedRetention;
  final ValueChanged<UnbackedRetentionPolicy> onUnbackedRetentionChanged;
  final ValueChanged<BackedRetentionPolicy> onBackedRetentionChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '录像保留',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          _RetentionDropdowns(
            unbackedRetention: unbackedRetention,
            backedRetention: backedRetention,
            onUnbackedRetentionChanged: onUnbackedRetentionChanged,
            onBackedRetentionChanged: onBackedRetentionChanged,
          ),
        ],
      ),
    );
  }
}

class _RetentionDropdowns extends StatelessWidget {
  const _RetentionDropdowns({
    required this.unbackedRetention,
    required this.backedRetention,
    required this.onUnbackedRetentionChanged,
    required this.onBackedRetentionChanged,
  });

  final UnbackedRetentionPolicy unbackedRetention;
  final BackedRetentionPolicy backedRetention;
  final ValueChanged<UnbackedRetentionPolicy> onUnbackedRetentionChanged;
  final ValueChanged<BackedRetentionPolicy> onBackedRetentionChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
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
      ],
    );
  }
}

class _ComputerBackupSettings extends StatelessWidget {
  const _ComputerBackupSettings({
    required this.snapshot,
    required this.allBackedUp,
    required this.onConnect,
    this.onAutoChanged,
    this.onBackupNow,
    this.onDisconnect,
    this.onRetry,
    required this.unbackedRetention,
    required this.backedRetention,
    required this.onUnbackedRetentionChanged,
    required this.onBackedRetentionChanged,
    this.showRetention = true,
  });

  final LanBackupSnapshot snapshot;
  final bool allBackedUp;
  final VoidCallback onConnect;
  final Future<void> Function(bool enabled)? onAutoChanged;
  final Future<void> Function()? onBackupNow;
  final Future<void> Function()? onDisconnect;
  final Future<void> Function(String jobId)? onRetry;
  final UnbackedRetentionPolicy unbackedRetention;
  final BackedRetentionPolicy backedRetention;
  final ValueChanged<UnbackedRetentionPolicy> onUnbackedRetentionChanged;
  final ValueChanged<BackedRetentionPolicy> onBackedRetentionChanged;
  final bool showRetention;

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
    final LanBackupJob? paused = snapshot.jobs.cast<LanBackupJob?>().firstWhere(
      (LanBackupJob? job) => job?.state == LanBackupJobState.paused,
      orElse: () => null,
    );
    final int pending = snapshot.jobs
        .where((LanBackupJob job) => job.state == LanBackupJobState.pending)
        .length;
    final int progress = ((active?.progress ?? 0) * 100).round();
    final bool paired = snapshot.endpoint != null;
    final bool online =
        snapshot.connectionStatus == LanConnectionStatus.connected;
    final bool needsRepair =
        snapshot.connectionStatus == LanConnectionStatus.rePair;
    final String stateLabel = online
        ? '电脑在线'
        : needsRepair
        ? '需重新连接'
        : '电脑离线';
    final Color stateForeground = online
        ? PackingProofMobileApp.forest
        : needsRepair
        ? const Color(0xFFA35A16)
        : const Color(0xFF69716E);
    final Color stateBackground = online
        ? const Color(0xFFDDEDE7)
        : needsRepair
        ? const Color(0xFFFFE8CF)
        : const Color(0xFFE1E5E3);
    final String? status = !snapshot.connected
        ? '扫描电脑二维码后自动备份'
        : snapshot.connectionStatus == LanConnectionStatus.rePair
        ? '需要重新配对'
        : snapshot.connectionStatus == LanConnectionStatus.offline
        ? '电脑离线，备份已暂停'
        : active != null
        ? '正在备份 · $progress%'
        : failed != null
        ? (failed.errorMessage ?? '备份失败')
        : paused != null
        ? (paused.errorMessage ?? '等待自动续传')
        : pending > 0
        ? '还有 $pending 个录像等待备份'
        : null;

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
              if (paired) ...<Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: stateBackground,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    stateLabel,
                    style: TextStyle(
                      color: stateForeground,
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
          if (snapshot.endpoint != null) ...<Widget>[
            Row(
              key: const Key('connected-computer-address'),
              children: <Widget>[
                Icon(Icons.computer_rounded, size: 16, color: stateForeground),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    snapshot.endpoint!.computerName.isEmpty
                        ? snapshot.endpoint!.displayAddress
                        : '${snapshot.endpoint!.computerName} · ${snapshot.endpoint!.displayAddress}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: stateForeground,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
          ],
          if (status != null)
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
          if (active != null) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: active.progress),
          ],
          if (showRetention) ...<Widget>[
            const SizedBox(height: 14),
            _RetentionDropdowns(
              unbackedRetention: unbackedRetention,
              backedRetention: backedRetention,
              onUnbackedRetentionChanged: onUnbackedRetentionChanged,
              onBackedRetentionChanged: onBackedRetentionChanged,
            ),
          ],
          const SizedBox(height: 10),
          if (!paired)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: const Key('connect-computer-button'),
                onPressed: onConnect,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('连接电脑'),
              ),
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton.icon(
                    key: const Key('backup-now-button'),
                    onPressed: needsRepair
                        ? onConnect
                        : online && !allBackedUp
                        ? onBackupNow
                        : null,
                    icon: Icon(
                      needsRepair
                          ? Icons.qr_code_scanner_rounded
                          : allBackedUp && online
                          ? Icons.check_circle_rounded
                          : Icons.backup_rounded,
                    ),
                    label: Text(
                      needsRepair
                          ? '重新连接'
                          : !online
                          ? '电脑离线'
                          : allBackedUp
                          ? '备份完成'
                          : '立即备份',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    key: const Key('delete-computer-button'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC43D32),
                    ),
                    onPressed: onDisconnect,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('删除电脑'),
                  ),
                ),
              ],
            ),
            if (failed != null) ...<Widget>[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: online && onRetry != null
                      ? () => onRetry!(failed.id)
                      : null,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试失败任务'),
                ),
              ),
            ],
          ],
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
    this.unavailable = false,
    this.backupJob,
  });

  final RecordingSession session;
  final bool managing;
  final bool selected;
  final VoidCallback onTap;
  final LanBackupJob? backupJob;
  final String sourceLabel;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: unavailable ? 0.52 : 1,
      child: Material(
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
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              session.displayCode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(label: sourceLabel),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${_dateTime(session.startedAt)}  ·  ${_duration(session.duration)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF69716E),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (backupJob != null &&
                              backupJob!.state !=
                                  LanBackupJobState.completed) ...[
                            const SizedBox(width: 8),
                            _StatusChip(
                              label: _backupLabel(backupJob!),
                              error:
                                  backupJob!.state == LanBackupJobState.failed,
                            ),
                          ],
                        ],
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
      ),
    );
  }
}

class _HistoryPagination extends StatelessWidget {
  const _HistoryPagination({
    required this.currentPage,
    required this.pageCount,
    required this.loading,
    required this.offline,
    required this.canLoadMore,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int pageCount;
  final bool loading;
  final bool offline;
  final bool canLoadMore;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final int shownPageCount = pageCount == 0 ? 1 : pageCount;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton.outlined(
            key: const Key('recording-page-previous'),
            tooltip: '上一页',
            onPressed: loading ? null : onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          SizedBox(
            width: 104,
            child: Text(
              offline ? '电脑离线' : '${currentPage + 1} / $shownPageCount 页',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton.outlined(
            key: const Key('recording-page-next'),
            tooltip: offline
                ? '电脑离线'
                : canLoadMore && currentPage + 1 >= pageCount
                ? '加载下一页'
                : '下一页',
            onPressed: loading ? null : onNext,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
          ),
        ],
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

bool _isToday(DateTime value) {
  final DateTime now = DateTime.now();
  return value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
}

String _sourceFilterLabel(RecordingSourceFilter value) => switch (value) {
  RecordingSourceFilter.all => '全部来源',
  RecordingSourceFilter.local => '仅本机',
  RecordingSourceFilter.backedUp => '已备份',
  RecordingSourceFilter.computer => '电脑录像',
};
