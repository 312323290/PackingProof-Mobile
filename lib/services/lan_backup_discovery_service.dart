import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lan_backup_compatibility.dart';

class LanBackupDiscoveredHost {
  const LanBackupDiscoveredHost({
    required this.nodeId,
    required this.name,
    required this.address,
    this.compatible = true,
    this.compatibilityMessage,
  });

  final String nodeId;
  final String name;
  final String address;
  final bool compatible;
  final String? compatibilityMessage;

  Uri get baseUri => Uri.parse('http://$address');
}

class LanBackupDiscoverySnapshot {
  const LanBackupDiscoverySnapshot({
    this.searching = false,
    this.completed = 0,
    this.total = 0,
    this.hosts = const <LanBackupDiscoveredHost>[],
    this.message,
  });

  final bool searching;
  final int completed;
  final int total;
  final List<LanBackupDiscoveredHost> hosts;
  final String? message;

  double? get progress => total <= 0 ? null : completed / total;
}

abstract interface class LanBackupHostDiscovery implements Listenable {
  LanBackupDiscoverySnapshot get snapshot;
  Future<void> search();
  void cancel();
}

typedef LanBackupCandidateProvider = Future<List<Uri>> Function();
typedef LanBackupHostProbe = Future<LanBackupDiscoveredHost?> Function(Uri uri);

@visibleForTesting
LanBackupDiscoveredHost? parseLanBackupDiscoveredHost(Uri uri, String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map ||
      decoded['protocol'] != 'packingproof' ||
      decoded['protocolVersion'] != 1) {
    return null;
  }
  final Set<String> capabilities = decoded['capabilities'] is List
      ? (decoded['capabilities'] as List)
            .map((Object? value) => '$value'.toLowerCase())
            .toSet()
      : const <String>{};
  if (!capabilities.contains('host') ||
      !capabilities.contains('mobile-backup')) {
    return null;
  }
  final String nodeId = '${decoded['nodeId'] ?? ''}'.trim();
  if (nodeId.isEmpty) return null;
  final int advertisedPort = (decoded['httpPort'] as num?)?.toInt() ?? uri.port;
  final int port = advertisedPort > 0 && advertisedPort <= 65535
      ? advertisedPort
      : uri.port;
  final LanBackupHostCompatibility? compatibility =
      parseLanBackupHostCompatibility(decoded['backupCompatibility']);
  final bool compatible = compatibility?.supportsCurrentMobile == true;
  return LanBackupDiscoveredHost(
    nodeId: nodeId,
    name: '${decoded['nodeName'] ?? ''}'.trim().isEmpty
        ? '录像文件备份主机'
        : '${decoded['nodeName']}'.trim(),
    address: '${uri.host}:$port',
    compatible: compatible,
    compatibilityMessage: compatible ? null : '保存主机版本过低，请在电脑端更新 PackingProof',
  );
}

class LanBackupHostDiscoveryService extends ChangeNotifier
    implements LanBackupHostDiscovery {
  LanBackupHostDiscoveryService({
    LanBackupCandidateProvider? candidateProvider,
    LanBackupHostProbe? probe,
    HttpClient? httpClient,
  }) : _candidateProvider = candidateProvider ?? _defaultCandidates,
       _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null,
       _probeOverride = probe;

  final LanBackupCandidateProvider _candidateProvider;
  final LanBackupHostProbe? _probeOverride;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  int _revision = 0;
  LanBackupDiscoverySnapshot _snapshot = const LanBackupDiscoverySnapshot();

  @override
  LanBackupDiscoverySnapshot get snapshot => _snapshot;

  @override
  Future<void> search() async {
    final int revision = ++_revision;
    _snapshot = const LanBackupDiscoverySnapshot(
      searching: true,
      message: '正在查找同一 Wi-Fi 下的录像文件备份主机',
    );
    notifyListeners();
    final List<Uri> candidates;
    try {
      candidates = await _candidateProvider();
    } on Object {
      if (revision != _revision) return;
      _snapshot = const LanBackupDiscoverySnapshot(
        message: '暂时无法读取局域网地址，可重新搜索或扫码连接',
      );
      notifyListeners();
      return;
    }
    if (revision != _revision) return;
    if (candidates.isEmpty) {
      _snapshot = const LanBackupDiscoverySnapshot(
        message: '未连接 Wi-Fi，请连接后重新搜索或扫码连接',
      );
      notifyListeners();
      return;
    }
    final List<LanBackupDiscoveredHost> hosts = <LanBackupDiscoveredHost>[];
    int cursor = 0;
    int completed = 0;
    _snapshot = LanBackupDiscoverySnapshot(
      searching: true,
      total: candidates.length,
      message: '正在搜索 0 / ${candidates.length}',
    );
    notifyListeners();
    Future<void> worker() async {
      while (revision == _revision) {
        final int index = cursor++;
        if (index >= candidates.length) return;
        final LanBackupDiscoveredHost? host = await _probe(candidates[index]);
        if (revision != _revision) return;
        if (host != null && hosts.every((item) => item.nodeId != host.nodeId)) {
          hosts.add(host);
          hosts.sort((a, b) => a.name.compareTo(b.name));
        }
        completed++;
        if (completed == candidates.length ||
            completed % 4 == 0 ||
            host != null) {
          _snapshot = LanBackupDiscoverySnapshot(
            searching: true,
            completed: completed,
            total: candidates.length,
            hosts: List<LanBackupDiscoveredHost>.unmodifiable(hosts),
            message: '正在搜索 $completed / ${candidates.length}',
          );
          notifyListeners();
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        candidates.length < 24 ? candidates.length : 24,
        (_) => worker(),
      ),
    );
    if (revision != _revision) return;
    _snapshot = LanBackupDiscoverySnapshot(
      completed: completed,
      total: candidates.length,
      hosts: List<LanBackupDiscoveredHost>.unmodifiable(hosts),
      message: hosts.isEmpty
          ? '未找到录像文件备份主机，可重新搜索或扫码连接'
          : hosts.every((LanBackupDiscoveredHost host) => !host.compatible)
          ? '找到保存主机，但电脑端版本过低，请先更新 PackingProof'
          : '找到 ${hosts.length} 台录像文件备份主机，请选择后等待电脑允许连接',
    );
    notifyListeners();
  }

  Future<LanBackupDiscoveredHost?> _probe(Uri uri) async {
    final LanBackupHostProbe? override = _probeOverride;
    if (override != null) return override(uri);
    try {
      final HttpClientRequest request = await _httpClient
          .getUrl(uri.replace(path: '/api/node-info'))
          .timeout(const Duration(milliseconds: 450));
      request.followRedirects = false;
      final HttpClientResponse response = await request.close().timeout(
        const Duration(milliseconds: 650),
      );
      final String body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) return null;
      return parseLanBackupDiscoveredHost(uri, body);
    } on Object {
      return null;
    }
  }

  @override
  void cancel() {
    _revision++;
    if (_snapshot.searching) {
      _snapshot = LanBackupDiscoverySnapshot(
        completed: _snapshot.completed,
        total: _snapshot.total,
        hosts: _snapshot.hosts,
        message: '搜索已停止',
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    cancel();
    if (_ownsHttpClient) _httpClient.close(force: true);
    super.dispose();
  }

  static Future<List<Uri>> _defaultCandidates() async {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final Set<String> localAddresses = interfaces
        .expand((item) => item.addresses)
        .map((item) => item.address)
        .toSet();
    final Set<String> candidates = <String>{};
    for (final String address in localAddresses) {
      final List<int>? octets = _privateIpv4Octets(address);
      if (octets == null) continue;
      final String prefix = '${octets[0]}.${octets[1]}.${octets[2]}';
      for (int host = 1; host < 255; host++) {
        final String candidate = '$prefix.$host';
        if (!localAddresses.contains(candidate)) candidates.add(candidate);
      }
    }
    return candidates.map((host) => Uri.parse('http://$host:5280')).toList();
  }

  static List<int>? _privateIpv4Octets(String value) {
    final List<int> parts = value
        .split('.')
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    if (parts.length != 4 || parts.any((part) => part < 0 || part > 255)) {
      return null;
    }
    final bool isPrivate =
        parts[0] == 10 ||
        (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
        (parts[0] == 192 && parts[1] == 168);
    return isPrivate ? parts : null;
  }
}
