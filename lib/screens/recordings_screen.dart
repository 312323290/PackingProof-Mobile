import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/backup_retention_policy.dart';
import '../models/barcode_marker.dart';
import '../models/lan_backup.dart';
import '../models/recording_operation_mode.dart';
import '../models/recording_session.dart';
import '../services/order_info_receiver_service.dart';
import '../models/work_mode.dart';
import '../widgets/about_settings.dart';
import '../widgets/two_button_confirm_dialog.dart';
import '../services/recording_thumbnail_service.dart';
import '../services/recording_database.dart';
import 'video_playback_screen.dart';

enum RecordingsScreenMode { history, settings }

enum RecordingSourceFilter { all, local, backedUp, computer }

@visibleForTesting
String recordingsHistoryTitle(String deviceName, String ipAddress) {
  final String name = deviceName.trim().isEmpty ? '设备' : deviceName.trim();
  final String ip = ipAddress.trim();
  return ip.isEmpty ? name : '$name · $ip';
}

class _RecordingsHistoryTitle extends StatelessWidget {
  const _RecordingsHistoryTitle({
    required this.deviceName,
    required this.ipAddress,
  });

  final String deviceName;
  final String ipAddress;

  @override
  Widget build(BuildContext context) {
    final String name = deviceName.trim().isEmpty ? '设备' : deviceName.trim();
    final String ip = ipAddress.trim();
    return Semantics(
      label: recordingsHistoryTitle(name, ip),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (ip.isNotEmpty)
            Text(
              ' · $ip',
              key: const Key('recordings-history-ip'),
              maxLines: 1,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }
}

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({
    required this.sessions,
    required this.workMode,
    required this.speechEnabled,
    this.orderSpeechEnabled = true,
    this.orderReceiverSnapshot = const OrderInfoReceiverSnapshot(),
    required this.maxVolumeEnabled,
    required this.onWorkModeChanged,
    required this.onSpeechEnabledChanged,
    this.onOrderSpeechEnabledChanged,
    this.onRetryOrderReceiver,
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
    this.onRetryConnection,
    this.onRetryBackup,
    this.onRefreshHistory,
    this.unbackedRetention = UnbackedRetentionPolicy.days30,
    this.backedRetention = BackedRetentionPolicy.days7,
    this.onBackupRetentionChanged,
    this.onLoadRemoteRecordings,
    this.onLoadLocalRecordings,
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
    this.focusBackupRevision = 0,
    super.key,
  });

  final List<RecordingSession> sessions;
  final WorkMode workMode;
  final bool speechEnabled;
  final bool orderSpeechEnabled;
  final OrderInfoReceiverSnapshot orderReceiverSnapshot;
  final bool maxVolumeEnabled;
  final Future<void> Function(WorkMode mode) onWorkModeChanged;
  final Future<void> Function(bool enabled) onSpeechEnabledChanged;
  final Future<void> Function(bool enabled)? onOrderSpeechEnabledChanged;
  final Future<void> Function()? onRetryOrderReceiver;
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
  final Future<void> Function()? onRetryConnection;
  final Future<void> Function(String jobId)? onRetryBackup;
  final Future<void> Function()? onRefreshHistory;
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
  final Future<LocalRecordingPage> Function({
    required int page,
    required int pageSize,
    String keyword,
  })?
  onLoadLocalRecordings;
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
  final int focusBackupRevision;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  static const int _historyPageSize = 5;
  static const RecordingThumbnailService _thumbnailService =
      RecordingThumbnailService();

  late WorkMode _workMode;
  late bool _speechEnabled;
  late bool _orderSpeechEnabled;
  late bool _maxVolumeEnabled;
  late List<RecordingSession> _sessions;
  late int _localRecordingBytes;
  late Set<String> _localRecordingPaths;
  late LanBackupSnapshot _backupSnapshot;
  late UnbackedRetentionPolicy _unbackedRetention;
  late BackedRetentionPolicy _backedRetention;
  final List<RemoteRecording> _remoteRecordings = <RemoteRecording>[];
  final Map<int, List<RemoteRecording>> _remotePages =
      <int, List<RemoteRecording>>{};
  final Map<int, List<RecordingSession>> _localPages =
      <int, List<RecordingSession>>{};
  final Map<int, ({RemoteRecordingStatus status, bool exists, String reason})>
  _remoteStatuses = {};
  late Set<int> _hiddenRemoteIds;
  Timer? _remoteSearchTimer;
  bool _loadingRemote = false;
  bool _remoteCacheDirty = false;
  bool _manualRefreshing = false;
  DateTime? _lastManualRefreshAt;
  int _remoteTotal = 0;
  int _remoteDeviceTotal = 0;
  int _localTotal = 0;
  bool _loadingLocal = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedIds = <String>{};
  final Map<String, Future<String?>> _localThumbnailFutures =
      <String, Future<String?>>{};
  String _query = '';
  bool _managing = false;
  int _historyPage = 0;
  int _remoteRequestGeneration = 0;
  int _localRequestGeneration = 0;
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
              '${_two(value.hour)}:${_two(value.minute)} '
              '${session.orderInfo?.orderId ?? ''} '
              '${session.orderInfo?.buyerMessage ?? ''} '
              '${session.orderInfo?.sellerMemo ?? ''} '
              '${session.orderInfo?.productInfo ?? ''}';
          return searchable.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _workMode = widget.workMode;
    _speechEnabled = widget.speechEnabled;
    _orderSpeechEnabled = widget.orderSpeechEnabled;
    _maxVolumeEnabled = widget.maxVolumeEnabled;
    _sessions = List<RecordingSession>.of(widget.sessions);
    _refreshLocalRecordingStats();
    _backupSnapshot = widget.backupSnapshot;
    _unbackedRetention = widget.unbackedRetention;
    _backedRetention = widget.backedRetention;
    _hiddenRemoteIds = Set<int>.of(widget.hiddenRemoteRecordingIds);
    _applyExternalSearch(widget.externalSearchQuery);
    widget.backupListenable?.addListener(_refreshBackupSnapshot);
    if (widget.mode == RecordingsScreenMode.history && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadLocal(reset: true, pageNumber: 1, prefetchNext: true));
        unawaited(_loadRemote(reset: true, pageNumber: 1, prefetchNext: true));
      });
    }
  }

  @override
  void didUpdateWidget(covariant RecordingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool sessionsChanged = !_sameSessionSnapshot(
      oldWidget.sessions,
      widget.sessions,
    );
    if (sessionsChanged && widget.onLoadLocalRecordings == null) {
      _sessions = List<RecordingSession>.of(widget.sessions);
      _refreshLocalRecordingStats();
    } else if (sessionsChanged && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(
          _loadLocal(reset: true, pageNumber: 1, prefetchNext: true),
        ),
      );
    }
    _workMode = widget.workMode;
    _speechEnabled = widget.speechEnabled;
    _orderSpeechEnabled = widget.orderSpeechEnabled;
    _maxVolumeEnabled = widget.maxVolumeEnabled;
    _unbackedRetention = widget.unbackedRetention;
    _backedRetention = widget.backedRetention;
    _hiddenRemoteIds.addAll(widget.hiddenRemoteRecordingIds);
    if (oldWidget.focusBackupRevision != widget.focusBackupRevision &&
        widget.focusBackupRevision > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
    if (!oldWidget.active &&
        widget.active &&
        (_remoteRecordings.isEmpty || _remoteCacheDirty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadLocal(reset: true, pageNumber: 1, prefetchNext: true));
        _reloadRemoteAfterBackup(force: _remoteRecordings.isEmpty);
      });
    }
    if (oldWidget.externalSearchQuery != widget.externalSearchQuery &&
        widget.externalSearchQuery.isNotEmpty) {
      _applyExternalSearch(widget.externalSearchQuery);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadLocal(reset: true, pageNumber: 1, prefetchNext: true));
        unawaited(_loadRemote(reset: true, pageNumber: 1, prefetchNext: true));
      });
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
    _scrollController.dispose();
    super.dispose();
  }

  void _refreshBackupSnapshot() {
    if (!mounted) {
      return;
    }
    final LanBackupSnapshot next =
        widget.backupSnapshotProvider?.call() ?? widget.backupSnapshot;
    final Set<String> previousCompleted = _completedBackupSignatures(
      _backupSnapshot,
    );
    final Set<String> nextCompleted = _completedBackupSignatures(next);
    final bool completedChanged = nextCompleted
        .difference(previousCompleted)
        .isNotEmpty;
    final Set<String> previousDeleted = _deletedLocalPaths(_backupSnapshot);
    final Set<String> nextDeleted = _deletedLocalPaths(next);
    final bool localCleanupChanged = nextDeleted
        .difference(previousDeleted)
        .isNotEmpty;
    final bool reconnected =
        _backupSnapshot.connectionStatus != LanConnectionStatus.connected &&
        next.connectionStatus == LanConnectionStatus.connected;
    if (localCleanupChanged) {
      _refreshLocalRecordingStats();
    }
    setState(() {
      _backupSnapshot = next;
      if (completedChanged) _remoteCacheDirty = true;
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
    if (reconnected) {
      unawaited(_loadRemote(reset: true, pageNumber: 1, prefetchNext: true));
    } else if (completedChanged) {
      _reloadRemoteAfterBackup();
    } else if (widget.active &&
        _backupSnapshot.connectionStatus == LanConnectionStatus.connected &&
        _remoteRecordings.isEmpty) {
      unawaited(_loadRemote(reset: true, pageNumber: 1, prefetchNext: true));
    }
  }

  Set<String> _completedBackupSignatures(LanBackupSnapshot snapshot) => snapshot
      .jobs
      .where(
        (LanBackupJob job) =>
            job.state == LanBackupJobState.completed &&
            job.remoteRecordIds.isNotEmpty,
      )
      .map(
        (LanBackupJob job) =>
            '${job.id}:${job.destinationComputerId}:${job.remoteRecordIds.join(',')}',
      )
      .toSet();

  Set<String> _deletedLocalPaths(LanBackupSnapshot snapshot) => snapshot.jobs
      .where((LanBackupJob job) => job.localDeletedAt != null)
      .map((LanBackupJob job) => lanBackupFileIdentity(job.filePath))
      .toSet();

  void _reloadRemoteAfterBackup({bool force = false}) {
    if ((!_remoteCacheDirty && !force) ||
        !mounted ||
        !widget.active ||
        _loadingRemote ||
        _backupSnapshot.connectionStatus != LanConnectionStatus.connected) {
      return;
    }
    _remoteCacheDirty = false;
    unawaited(_loadRemote(reset: true, pageNumber: 1, prefetchNext: true));
  }

  Future<void> _manualRefresh() async {
    final DateTime now = DateTime.now();
    if (_manualRefreshing ||
        (_lastManualRefreshAt != null &&
            now.difference(_lastManualRefreshAt!) <
                const Duration(milliseconds: 800))) {
      return;
    }
    _lastManualRefreshAt = now;
    setState(() => _manualRefreshing = true);
    try {
      await widget.onRefreshHistory?.call();
      if (!mounted) return;
      _localRequestGeneration++;
      _loadingLocal = false;
      await _loadLocal(reset: true, pageNumber: 1, prefetchNext: true);
      if (!mounted) return;
      _remoteRequestGeneration++;
      _loadingRemote = false;
      _remoteCacheDirty = false;
      if (_backupSnapshot.connectionStatus == LanConnectionStatus.connected) {
        await _loadRemote(reset: true, pageNumber: 1, prefetchNext: true);
      }
    } finally {
      if (mounted) setState(() => _manualRefreshing = false);
    }
  }

  Future<void> _loadLocal({
    bool reset = false,
    required int pageNumber,
    bool prefetchNext = false,
  }) async {
    final callback = widget.onLoadLocalRecordings;
    if (callback == null || _loadingLocal || !widget.active) return;
    final int generation = ++_localRequestGeneration;
    setState(() {
      _loadingLocal = true;
      if (reset) {
        _localPages.clear();
        _sessions.clear();
        _localTotal = 0;
        _historyPage = 0;
      }
    });
    try {
      final LocalRecordingPage result = await callback(
        page: pageNumber,
        pageSize: _historyPageSize,
        keyword: _query,
      );
      if (!mounted || generation != _localRequestGeneration) return;
      setState(() {
        _localPages[result.page] = result.data;
        _localTotal = result.total;
        _rebuildLocalRecordings();
        _refreshLocalRecordingStats();
      });
      if (prefetchNext && result.page < result.pageCount) {
        await _loadLocalPageWithoutBusy(result.page + 1, generation);
      }
    } on Object {
      // Keep already loaded rows visible if the local database is unavailable.
    } finally {
      if (mounted && generation == _localRequestGeneration) {
        setState(() => _loadingLocal = false);
      }
    }
  }

  Future<void> _loadLocalPageWithoutBusy(int pageNumber, int generation) async {
    final callback = widget.onLoadLocalRecordings;
    if (callback == null || _localPages.containsKey(pageNumber)) return;
    final LocalRecordingPage page = await callback(
      page: pageNumber,
      pageSize: _historyPageSize,
      keyword: _query,
    );
    if (!mounted || generation != _localRequestGeneration) return;
    setState(() {
      _localPages[page.page] = page.data;
      _localTotal = page.total;
      _rebuildLocalRecordings();
      _refreshLocalRecordingStats();
    });
  }

  void _rebuildLocalRecordings() {
    final entries = _localPages.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    _sessions
      ..clear()
      ..addAll(entries.expand((entry) => entry.value));
  }

  List<_RecordingListItem> get _visibleItems {
    final Map<String, RemoteRecording> remoteBySession =
        <String, RemoteRecording>{
          for (final RemoteRecording remote in _remoteRecordings)
            if (remote.sourceSessionId.isNotEmpty &&
                _isRemoteFromThisDevice(remote))
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
              (item.remote != null &&
                  _isRemoteFromThisDevice(item.remote!) &&
                  item.remote!.status == RemoteRecordingStatus.available &&
                  item.remote!.exists) ||
              (item.local != null &&
                  _backupSnapshot.jobs.any(
                    (job) =>
                        isSameLanBackupFile(
                          job.filePath,
                          item.local!.filePath,
                        ) &&
                        _isJobConfirmedAvailable(job),
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
        _reloadRemoteAfterBackup();
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
    _remoteSearchTimer = Timer(const Duration(milliseconds: 300), () {
      _localRequestGeneration++;
      _loadingLocal = false;
      unawaited(_loadLocal(reset: true, pageNumber: 1, prefetchNext: true));
      unawaited(_loadRemote(reset: true, pageNumber: 1, prefetchNext: true));
    });
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

  Future<void> _setOrderSpeechEnabled(bool enabled) async {
    if (_orderSpeechEnabled == enabled) return;
    setState(() => _orderSpeechEnabled = enabled);
    await widget.onOrderSpeechEnabledChanged?.call(enabled);
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
        _refreshLocalRecordingStats();
      }
    });
  }

  void _toggleManaging() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _managing = !_managing;
      _selectedIds.clear();
      _historyPage = 0;
      if (_managing) {
        _sourceFilter = RecordingSourceFilter.local;
      }
    });
  }

  Future<String?> _localThumbnail(String filePath) => _localThumbnailFutures
      .putIfAbsent(filePath, () => _thumbnailService.generate(filePath));

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
      _refreshLocalRecordingStats();
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
                            ? Theme.of(context).colorScheme.primary
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
    if (!_localPages.containsKey(remotePage)) {
      await _loadLocal(pageNumber: remotePage);
    }
    if (!mounted) return;
    setState(() => _historyPage = nextHistoryPage);
    final int prefetchPage = remotePage + 1;
    if (prefetchPage <= (_remoteTotal / _historyPageSize).ceil() &&
        !_remotePages.containsKey(prefetchPage) &&
        _backupSnapshot.connectionStatus == LanConnectionStatus.connected) {
      unawaited(_loadRemote(pageNumber: prefetchPage));
    }
    if (prefetchPage <= (_localTotal / _historyPageSize).ceil() &&
        !_localPages.containsKey(prefetchPage)) {
      unawaited(_loadLocal(pageNumber: prefetchPage));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<_RecordingListItem> visibleItems = _managing
        ? _visibleItems
              .where(
                (item) =>
                    item.local != null &&
                    File(item.local!.filePath).existsSync(),
              )
              .toList(growable: false)
        : _visibleItems;
    final List<RecordingSession> visibleSessions = visibleItems
        .map((item) => item.local)
        .whereType<RecordingSession>()
        .toList(growable: false);
    final int localCount = _filteredSessions
        .where((session) => File(session.filePath).existsSync())
        .length;
    final int localLogicalCount = widget.onLoadLocalRecordings == null
        ? _filteredSessions.length
        : _localTotal;
    final int estimatedCount = _managing
        ? visibleItems.length
        : switch (_sourceFilter) {
            RecordingSourceFilter.local =>
              widget.onLoadLocalRecordings == null ? localCount : _localTotal,
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
        title: _managing
            ? Text('已选 ${_selectedIds.length} 项')
            : historyMode
            ? _RecordingsHistoryTitle(
                deviceName: _backupSnapshot.deviceName,
                ipAddress: widget.orderReceiverSnapshot.ipAddress,
              )
            : const Text('设置'),
        actions: <Widget>[
          if (historyMode && _sessions.isNotEmpty)
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
          if (!historyMode) ...<Widget>[
            _WorkModeSettings(workMode: _workMode, onChanged: _setWorkMode),
            const SizedBox(height: 12),
            _RetentionSettings(
              unbackedRetention: _unbackedRetention,
              backedRetention: _backedRetention,
              onUnbackedRetentionChanged: _setUnbackedRetention,
              onBackedRetentionChanged: _setBackedRetention,
            ),
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
            _OrderSpeechSettings(
              enabled: _orderSpeechEnabled,
              masterEnabled: _speechEnabled,
              onChanged: _setOrderSpeechEnabled,
            ),
            const SizedBox(height: 12),
            _OrderReceiverSettings(
              snapshot: widget.orderReceiverSnapshot,
              onRetry: widget.onRetryOrderReceiver,
            ),
            const SizedBox(height: 12),
            const AboutSettings(),
          ] else ...<Widget>[
            _HistorySummary(
              total: _existingLocalSessions.length,
              today: _existingLocalSessions
                  .where((item) => _isToday(item.startedAt))
                  .length,
              totalBytes: _localRecordingBytes,
            ),
            const SizedBox(height: 12),
            _ComputerBackupSettings(
              snapshot: _backupSnapshot,
              allBackedUp: _allLocalFilesBackedUp,
              remainingBackupCount: _remainingBackupCount,
              onConnect:
                  widget.onConnectComputer ??
                  () => Navigator.of(context).pop(true),
              onAutoChanged: widget.onAutoBackupChanged,
              onBackupNow: widget.onBackupNow,
              onDisconnect: _confirmDeleteComputer,
              onRetryConnection: widget.onRetryConnection,
              onRetry: widget.onRetryBackup,
              unbackedRetention: _unbackedRetention,
              backedRetention: _backedRetention,
              onUnbackedRetentionChanged: _setUnbackedRetention,
              onBackedRetentionChanged: _setBackedRetention,
              showRetention: false,
            ),
            const SizedBox(height: 12),
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
                  IconButton(
                    key: const Key('refresh-recordings-button'),
                    tooltip: '刷新录像记录',
                    onPressed: _manualRefreshing ? null : _manualRefresh,
                    icon: _manualRefreshing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
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
                final List<LanBackupJob> matchingBackupJobs = item.local == null
                    ? const <LanBackupJob>[]
                    : _backupSnapshot.jobs
                          .where(
                            (LanBackupJob job) => isSameLanBackupFile(
                              job.filePath,
                              item.local!.filePath,
                            ),
                          )
                          .toList(growable: false);
                final bool remoteAvailable =
                    item.remote != null &&
                    item.remote!.status == RemoteRecordingStatus.available &&
                    item.remote!.exists;
                final LanBackupJob? completedBackupJob = matchingBackupJobs
                    .where(_isJobKnownAvailable)
                    .firstOrNull;
                final LanBackupJob? backupJob =
                    completedBackupJob ?? matchingBackupJobs.firstOrNull;
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
                    sourceLabel: _recordingSourceLabel(item),
                    sourceIdentity: _recordingSourceIdentity(item),
                    localRecording: item.local != null && localAvailable,
                    backedUp:
                        (remoteAvailable &&
                            _isRemoteFromThisDevice(item.remote!)) ||
                        completedBackupJob != null,
                    localThumbnail: localAvailable
                        ? _localThumbnail(session.filePath)
                        : null,
                    remoteThumbnail: item.remote?.thumbnailUri,
                    remoteHeaders: widget.remotePlaybackHeaders,
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
                                    remoteVideoId: localAvailable
                                        ? null
                                        : remoteAvailable
                                        ? item.remote?.id
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
                          _refreshLocalRecordingStats();
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
                loading: _loadingRemote || _loadingLocal,
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
    final Set<String> completedPaths = _backupSnapshot.jobs
        .where(_isJobConfirmedAvailable)
        .map((LanBackupJob job) => lanBackupFileIdentity(job.filePath))
        .toSet();
    return _localRecordingPaths
        .map(lanBackupFileIdentity)
        .every(completedPaths.contains);
  }

  int get _remainingBackupCount {
    final Set<String> completedPaths = _backupSnapshot.jobs
        .where(_isJobConfirmedAvailable)
        .map((LanBackupJob job) => lanBackupFileIdentity(job.filePath))
        .toSet();
    return _localRecordingPaths
        .map(lanBackupFileIdentity)
        .where((String path) => !completedPaths.contains(path))
        .length;
  }

  void _refreshLocalRecordingStats() {
    final ({int bytes, Set<String> paths}) summary =
        _measureLocalRecordingStats(_sessions);
    _localRecordingBytes = summary.bytes;
    _localRecordingPaths = summary.paths;
  }

  List<RecordingSession> get _existingLocalSessions => _sessions
      .where(
        (RecordingSession session) =>
            session.filePath.isNotEmpty &&
            _localRecordingPaths.contains(session.filePath),
      )
      .toList(growable: false);

  static ({int bytes, Set<String> paths}) _measureLocalRecordingStats(
    Iterable<RecordingSession> sessions,
  ) {
    int total = 0;
    final Set<String> candidates = sessions
        .map((RecordingSession session) => session.filePath)
        .where((String path) => path.isNotEmpty)
        .toSet();
    final Set<String> existingPaths = <String>{};
    for (final String path in candidates) {
      try {
        final File file = File(path);
        if (file.existsSync()) {
          existingPaths.add(path);
          total += file.lengthSync();
        }
      } on FileSystemException {
        // A file may be removed by the retention worker while this page opens.
      }
    }
    return (bytes: total, paths: existingPaths);
  }

  bool _isJobConfirmedAvailable(LanBackupJob job) {
    final String currentComputerId = _backupSnapshot.endpoint?.computerId ?? '';
    if (currentComputerId.isEmpty ||
        job.destinationComputerId != currentComputerId) {
      return false;
    }
    return _isJobKnownAvailable(job);
  }

  bool _isRemoteFromThisDevice(RemoteRecording recording) {
    final String deviceId = _backupSnapshot.deviceId.trim();
    return deviceId.isNotEmpty && recording.sourceDeviceId == deviceId;
  }

  String _recordingSourceLabel(_RecordingListItem item) {
    final RemoteRecording? remote = item.remote;
    if (remote != null) {
      if (remote.sourceType.toLowerCase() != 'external') return '电脑';
      final String remoteName = remote.sourceDeviceName.trim();
      if (remoteName.isNotEmpty) return remoteName;
    }
    final String currentDeviceName = _backupSnapshot.deviceName.trim();
    if (item.local != null ||
        (remote != null && _isRemoteFromThisDevice(remote))) {
      return currentDeviceName.isEmpty ? '手机' : currentDeviceName;
    }
    return '手机';
  }

  String _recordingSourceIdentity(_RecordingListItem item) {
    final RemoteRecording? remote = item.remote;
    if (remote != null) {
      if (remote.sourceType.toLowerCase() != 'external') return 'computer';
      final String remoteDeviceId = remote.sourceDeviceId.trim();
      if (remoteDeviceId.isNotEmpty) return remoteDeviceId;
      final String remoteDeviceName = remote.sourceDeviceName.trim();
      if (remoteDeviceName.isNotEmpty) return remoteDeviceName;
    }
    final String currentDeviceId = _backupSnapshot.deviceId.trim();
    if (currentDeviceId.isNotEmpty) return currentDeviceId;
    final String currentDeviceName = _backupSnapshot.deviceName.trim();
    return currentDeviceName.isEmpty ? 'mobile' : currentDeviceName;
  }

  bool _isJobKnownAvailable(LanBackupJob job) {
    if (job.state != LanBackupJobState.completed ||
        job.remoteRecordIds.isEmpty) {
      return false;
    }
    return job.remoteRecordIds.every((int id) {
      final status = _remoteStatuses[id];
      return status == null ||
          (status.status == RemoteRecordingStatus.available && status.exists);
    });
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
      orderInfo: value.orderInfo,
      operationMode: value.operationMode,
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({
    required this.total,
    required this.today,
    required this.totalBytes,
  });

  final int total;
  final int today;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final ({String value, String unit}) totalSize = _formatStorageSize(
      totalBytes,
    );
    return Row(
      children: <Widget>[
        _SummaryMetric(label: '本机今日', value: '$today'),
        const SizedBox(width: 10),
        _SummaryMetric(label: '本机全部', value: '$total'),
        const SizedBox(width: 10),
        _SummaryMetric(
          label: '总占用',
          value: totalSize.value,
          unit: totalSize.unit,
        ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: <Widget>[
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: value,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
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

  static const String _retentionDescription =
      '保留时间仅在空间充足时生效。剩余不足 2GB 时会提前清理已完成电脑校验的录像，'
      '不会自动删除未备份录像。建议保持电脑备份连接或缩短保留时间';

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                '录像清理',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                key: const Key('retention-info-button'),
                tooltip: '录像清理说明',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.info_outline_rounded),
                onPressed: () => _showRetentionInfo(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
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

  Future<void> _showRetentionInfo(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('录像清理说明'),
        content: const Text(_retentionDescription),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
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
    final ColorScheme colors = Theme.of(context).colorScheme;
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
          Text(
            '超过保留时间且仍未完成电脑备份的录像将从本机永久删除',
            style: TextStyle(color: colors.error, fontSize: 11, height: 1.4),
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
    required this.remainingBackupCount,
    required this.onConnect,
    this.onAutoChanged,
    this.onBackupNow,
    this.onDisconnect,
    this.onRetryConnection,
    this.onRetry,
    required this.unbackedRetention,
    required this.backedRetention,
    required this.onUnbackedRetentionChanged,
    required this.onBackedRetentionChanged,
    this.showRetention = true,
  });

  final LanBackupSnapshot snapshot;
  final bool allBackedUp;
  final int remainingBackupCount;
  final VoidCallback onConnect;
  final Future<void> Function(bool enabled)? onAutoChanged;
  final Future<void> Function()? onBackupNow;
  final Future<void> Function()? onDisconnect;
  final Future<void> Function()? onRetryConnection;
  final Future<void> Function(String jobId)? onRetry;
  final UnbackedRetentionPolicy unbackedRetention;
  final BackedRetentionPolicy backedRetention;
  final ValueChanged<UnbackedRetentionPolicy> onUnbackedRetentionChanged;
  final ValueChanged<BackedRetentionPolicy> onBackedRetentionChanged;
  final bool showRetention;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
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
    final LanBackupJob? credentialFailure = snapshot.jobs
        .cast<LanBackupJob?>()
        .firstWhere(
          (LanBackupJob? job) =>
              (job?.state == LanBackupJobState.failed ||
                  job?.state == LanBackupJobState.paused) &&
              job?.failureKind == LanBackupFailureKind.credentialInvalid,
          orElse: () => null,
        );
    final LanBackupJob? classifiedFailure = failed?.failureKind != null
        ? failed
        : paused?.failureKind != null
        ? paused
        : null;
    final LanBackupFailureKind? failureKind =
        snapshot.connectionStatus == LanConnectionStatus.rePair ||
            credentialFailure != null
        ? LanBackupFailureKind.credentialInvalid
        : classifiedFailure?.failureKind;
    final int pending = snapshot.jobs
        .where((LanBackupJob job) => job.state == LanBackupJobState.pending)
        .length;
    final int progress = ((active?.progress ?? 0) * 100).round();
    final bool paired = snapshot.endpoint != null;
    final String remainingLabel = remainingBackupCount == 0
        ? '全部完成'
        : '$remainingBackupCount 个未备份';
    final bool online =
        snapshot.connectionStatus == LanConnectionStatus.connected;
    final bool needsRepair =
        snapshot.connectionStatus == LanConnectionStatus.rePair ||
        failureKind == LanBackupFailureKind.credentialInvalid;
    final bool connecting =
        snapshot.connectionStatus == LanConnectionStatus.connecting;
    final String stateLabel = connecting
        ? '连接中'
        : online
        ? '在线'
        : needsRepair
        ? '需扫码'
        : '离线';
    final Color stateForeground = online
        ? colors.primary
        : needsRepair
        ? const Color(0xFFA35A16)
        : colors.onSurfaceVariant;
    final Color stateBackground = online
        ? colors.secondaryContainer
        : needsRepair
        ? const Color(0xFFFFE8CF)
        : colors.surfaceContainerHighest;
    final String? status = !snapshot.connected
        ? '扫描电脑二维码后自动备份'
        : needsRepair
        ? '电脑连接密钥已失效，请重新扫码'
        : connecting
        ? '正在重新连接电脑'
        : snapshot.connectionStatus == LanConnectionStatus.offline
        ? (snapshot.message?.isNotEmpty == true
              ? snapshot.message!
              : '电脑离线，备份已暂停')
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
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!paired) ...<Widget>[
            const Text(
              '电脑备份',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Row(
              children: <Widget>[
                Text(
                  remainingLabel,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '连接电脑后自动备份录像',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                key: const Key('connect-computer-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onConnect,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: const Text('连接电脑'),
              ),
            ),
          ] else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        '电脑备份',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        remainingLabel,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: stateBackground,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    stateLabel,
                    style: TextStyle(
                      color: stateForeground,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  key: const Key('delete-computer-button'),
                  tooltip: '删除电脑',
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFC43D32),
                    side: const BorderSide(color: Color(0xFFC43D32)),
                  ),
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
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
          if (status != null && paired)
            Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          if (active != null && !needsRepair) ...<Widget>[
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
          if (paired && failureKind != null) ...<Widget>[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('backup-failure-action-button'),
                onPressed: switch (failureKind.recoveryAction) {
                  LanBackupRecoveryAction.rescan => onConnect,
                  LanBackupRecoveryAction.retryConnection => onRetryConnection,
                  LanBackupRecoveryAction.updateComputer => null,
                  LanBackupRecoveryAction.retryBackup =>
                    online && onRetry != null
                        ? () => onRetry!(classifiedFailure!.id)
                        : null,
                },
                icon: Icon(
                  failureKind == LanBackupFailureKind.credentialInvalid
                      ? Icons.qr_code_scanner_rounded
                      : failureKind == LanBackupFailureKind.incompatibleVersion
                      ? Icons.system_update_rounded
                      : failureKind == LanBackupFailureKind.offlineOrTimeout
                      ? Icons.wifi_find_rounded
                      : Icons.refresh_rounded,
                ),
                label: Text(failureKind.recoveryLabel),
              ),
            ),
          ] else if (paired) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('backup-now-button'),
                    onPressed: connecting
                        ? null
                        : !online
                        ? onRetryConnection
                        : !allBackedUp
                        ? onBackupNow
                        : null,
                    icon: Icon(
                      connecting
                          ? Icons.sync_rounded
                          : !online
                          ? Icons.refresh_rounded
                          : allBackedUp && online
                          ? Icons.check_circle_rounded
                          : Icons.backup_rounded,
                    ),
                    label: Text(
                      connecting
                          ? '连接中'
                          : !online
                          ? '重试连接'
                          : allBackedUp
                          ? '备份完成'
                          : '立即备份',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('auto-backup-button'),
                    onPressed: onAutoChanged == null
                        ? null
                        : () => onAutoChanged!(!snapshot.autoEnabled),
                    icon: Icon(
                      snapshot.autoEnabled
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(snapshot.autoEnabled ? '暂停备份' : '继续备份'),
                  ),
                ),
              ],
            ),
            if (failed != null) ...<Widget>[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('work-mode-settings'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
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
            style: TextStyle(
              color: colors.onSurfaceVariant,
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('speech-prompt-settings'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '语音提示',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 5),
                Text(
                  '离线自动使用系统语音',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
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

class _OrderSpeechSettings extends StatelessWidget {
  const _OrderSpeechSettings({
    required this.enabled,
    required this.masterEnabled,
    required this.onChanged,
  });

  final bool enabled;
  final bool masterEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('order-speech-settings'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '订单播报',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  masterEnabled ? '播报留言、备注和退款提醒' : '请先开启语音提示',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: const Key('order-speech-enabled-switch'),
            value: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _OrderReceiverSettings extends StatelessWidget {
  const _OrderReceiverSettings({required this.snapshot, this.onRetry});

  final OrderInfoReceiverSnapshot snapshot;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final bool ready = snapshot.running && snapshot.url.isNotEmpty;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('order-receiver-settings'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '订单接收',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: ready
                      ? colors.secondaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  ready ? '接收中' : '未启动',
                  style: TextStyle(
                    color: ready ? colors.primary : colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ready
                ? snapshot.url
                : snapshot.errorMessage.isEmpty
                ? '请连接局域网 Wi-Fi 后重试'
                : snapshot.errorMessage,
            key: const Key('order-receiver-address'),
            style: TextStyle(
              color: ready ? colors.primary : colors.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '在油猴脚本中将监控地址设为以上地址',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ready
                      ? () async {
                          await Clipboard.setData(
                            ClipboardData(text: snapshot.url),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('接收地址已复制')),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制地址'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
              ),
            ],
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('max-volume-settings'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
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
                    color: colors.onSurfaceVariant,
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.video_library_outlined,
                size: 34,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '还没有录像',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              '返回首页点“开始工作”，录像会自动保存在这里',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.search_off_rounded,
            size: 42,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          const Text(
            '没有找到匹配的录像',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _RecordingThumbnail extends StatelessWidget {
  const _RecordingThumbnail({
    this.localPath,
    this.remoteUri,
    required this.remoteHeaders,
    required this.unavailable,
  });

  final Future<String?>? localPath;
  final Uri? remoteUri;
  final Map<String, String> remoteHeaders;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
      key: const Key('recording-thumbnail'),
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        unavailable ? Icons.videocam_off_rounded : Icons.play_arrow_rounded,
        color: unavailable ? colors.onSurfaceVariant : colors.primary,
      ),
    );

    Widget image(String path, {bool network = false}) => ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        key: const Key('recording-thumbnail'),
        width: 56,
        height: 56,
        child: network
            ? Image.network(
                path,
                headers: remoteHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder(),
              )
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder(),
              ),
      ),
    );

    if (unavailable) return placeholder();
    if (localPath != null) {
      return FutureBuilder<String?>(
        future: localPath,
        builder: (_, snapshot) => snapshot.data?.isNotEmpty == true
            ? image(snapshot.data!)
            : placeholder(),
      );
    }
    if (remoteUri != null) return image(remoteUri.toString(), network: true);
    return placeholder();
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({
    required this.session,
    required this.managing,
    required this.selected,
    required this.onTap,
    required this.sourceLabel,
    required this.sourceIdentity,
    required this.localRecording,
    required this.backedUp,
    required this.remoteHeaders,
    this.unavailable = false,
    this.backupJob,
    this.localThumbnail,
    this.remoteThumbnail,
  });

  final RecordingSession session;
  final bool managing;
  final bool selected;
  final VoidCallback onTap;
  final LanBackupJob? backupJob;
  final String sourceLabel;
  final String sourceIdentity;
  final bool localRecording;
  final bool unavailable;
  final bool backedUp;
  final Future<String?>? localThumbnail;
  final Uri? remoteThumbnail;
  final Map<String, String> remoteHeaders;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: unavailable ? 0.52 : 1,
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    if (managing) ...<Widget>[
                      Checkbox(value: selected, onChanged: (_) => onTap()),
                      const SizedBox(width: 4),
                    ],
                    _RecordingThumbnail(
                      localPath: localThumbnail,
                      remoteUri: remoteThumbnail,
                      remoteHeaders: remoteHeaders,
                      unavailable: unavailable,
                    ),
                    const SizedBox(width: 12),
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
                              _StatusChip(
                                key: const Key('recording-source-chip'),
                                label: sourceLabel,
                                tone: sourceLabel == '电脑'
                                    ? _StatusChipTone.computer
                                    : _StatusChipTone.recordingDevice,
                                identity: sourceIdentity,
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  key: const Key('recording-date-duration'),
                                  '${_dateTime(session.startedAt)}  ·  ${_duration(session.duration)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (backedUp) ...<Widget>[
                                const SizedBox(width: 8),
                                const _StatusChip(
                                  key: Key('recording-backed-up-chip'),
                                  label: '已备份',
                                  tone: _StatusChipTone.backupCompleted,
                                ),
                              ] else if (backupJob != null &&
                                  backupJob!.state !=
                                      LanBackupJobState.completed) ...[
                                const SizedBox(width: 8),
                                _StatusChip(
                                  label: _backupLabel(backupJob!),
                                  tone: _backupTone(backupJob!),
                                ),
                              ] else if (localRecording) ...<Widget>[
                                const SizedBox(width: 8),
                                const _StatusChip(
                                  label: '未备份',
                                  tone: _StatusChipTone.backupPending,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!managing)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
              Positioned(
                key: const Key('recording-operation-mode-strip'),
                left: 0,
                top: 12,
                bottom: 12,
                width: 4,
                child: Semantics(
                  label: '${session.operationMode.label}录像',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          session.operationMode ==
                              RecordingOperationMode.returnGoods
                          ? const Color(0xFFFF9800)
                          : colors.primary,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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

enum _StatusChipTone {
  neutral,
  recordingDevice,
  computer,
  backupCompleted,
  backupPending,
  backupPaused,
  backupUploading,
  error,
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    this.tone = _StatusChipTone.neutral,
    this.identity = '',
    super.key,
  });

  final String label;
  final _StatusChipTone tone;
  final String identity;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (tone) {
      _StatusChipTone.recordingDevice => _recordingDeviceChipColors(
        identity,
        colors.brightness,
      ),
      _StatusChipTone.computer => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      _StatusChipTone.backupCompleted => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      _StatusChipTone.backupPending => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
      _StatusChipTone.backupPaused =>
        colors.brightness == Brightness.dark
            ? (const Color(0xFF4A2D0A), const Color(0xFFFFB86C))
            : (const Color(0xFFFFE8CF), const Color(0xFFA35A16)),
      _StatusChipTone.backupUploading => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      _StatusChipTone.error => (colors.errorContainer, colors.onErrorContainer),
      _StatusChipTone.neutral => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
    };
    return DecoratedBox(
      key: ValueKey<String>('recording-source-chip-color-$identity'),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

(Color, Color) _recordingDeviceChipColors(
  String identity,
  Brightness brightness,
) {
  int hash = 0x811C9DC5;
  for (final int unit in identity.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  hash ^= hash >> 16;
  final double hue = (hash % 360).toDouble();
  if (brightness == Brightness.dark) {
    return (
      HSLColor.fromAHSL(1, hue, 0.48, 0.24).toColor(),
      HSLColor.fromAHSL(1, hue, 0.72, 0.78).toColor(),
    );
  }
  return (
    HSLColor.fromAHSL(1, hue, 0.58, 0.91).toColor(),
    HSLColor.fromAHSL(1, hue, 0.68, 0.30).toColor(),
  );
}

String _backupLabel(LanBackupJob job) => switch (job.state) {
  LanBackupJobState.pending => '未备份',
  LanBackupJobState.uploading => '备份中 ${(job.progress * 100).round()}%',
  LanBackupJobState.paused => '等待续传',
  LanBackupJobState.completed => '已备份',
  LanBackupJobState.failed => '备份失败',
};

_StatusChipTone _backupTone(LanBackupJob job) => switch (job.state) {
  LanBackupJobState.pending => _StatusChipTone.backupPending,
  LanBackupJobState.uploading => _StatusChipTone.backupUploading,
  LanBackupJobState.paused => _StatusChipTone.backupPaused,
  LanBackupJobState.completed => _StatusChipTone.backupCompleted,
  LanBackupJobState.failed => _StatusChipTone.error,
};

String _dateTime(DateTime value) {
  return '${value.month}月${value.day}日 ${_two(value.hour)}:${_two(value.minute)}';
}

bool _sameSessionSnapshot(
  List<RecordingSession> first,
  List<RecordingSession> second,
) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    final RecordingSession left = first[index];
    final RecordingSession right = second[index];
    if (left.id != right.id ||
        left.filePath != right.filePath ||
        left.startedAt != right.startedAt ||
        left.endedAt != right.endedAt ||
        left.mediaStart != right.mediaStart ||
        left.mediaEnd != right.mediaEnd) {
      return false;
    }
  }
  return true;
}

String _duration(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.inMinutes)}:${two(value.inSeconds.remainder(60))}';
}

({String value, String unit}) _formatStorageSize(int bytes) {
  const int mebibyte = 1024 * 1024;
  const int gibibyte = 1024 * mebibyte;
  if (bytes <= 0) return (value: '0', unit: 'MB');
  if (bytes < mebibyte) return (value: '<1', unit: 'MB');
  if (bytes < gibibyte) {
    final double value = bytes / mebibyte;
    return (value: value.toStringAsFixed(value < 10 ? 1 : 0), unit: 'MB');
  }
  final double value = bytes / gibibyte;
  return (value: value.toStringAsFixed(value < 10 ? 1 : 0), unit: 'GB');
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
  RecordingSourceFilter.local => '本地',
  RecordingSourceFilter.backedUp => '已备份',
  RecordingSourceFilter.computer => '电脑录像',
};
