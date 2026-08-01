import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'lan_backup_discovery_service.dart';

class LanBackupHostFileCache implements LanBackupHostCache {
  LanBackupHostFileCache({this.rootDirectory});

  final Directory? rootDirectory;

  @override
  Future<List<LanBackupDiscoveredHost>> load() async {
    final File file = await _cacheFile();
    if (!await file.exists()) return const <LanBackupDiscoveredHost>[];
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return const <LanBackupDiscoveredHost>[];
    return decoded
        .whereType<Map>()
        .map(_parseHost)
        .whereType<LanBackupDiscoveredHost>()
        .take(8)
        .toList(growable: false);
  }

  @override
  Future<void> save(List<LanBackupDiscoveredHost> hosts) async {
    final File file = await _cacheFile();
    await file.parent.create(recursive: true);
    final List<Map<String, Object?>> values = hosts
        .take(8)
        .map((host) {
          return <String, Object?>{
            'nodeId': host.nodeId,
            'name': host.name,
            'address': host.address,
            'compatible': host.compatible,
            if (host.compatibilityMessage != null)
              'compatibilityMessage': host.compatibilityMessage,
          };
        })
        .toList(growable: false);
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(values), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<File> _cacheFile() async {
    final Directory root =
        rootDirectory ?? await getApplicationDocumentsDirectory();
    return File(p.join(root.path, 'lan_backup_hosts.json'));
  }

  static LanBackupDiscoveredHost? _parseHost(Map<Object?, Object?> value) {
    final String nodeId = '${value['nodeId'] ?? ''}'.trim();
    final String name = '${value['name'] ?? ''}'.trim();
    final String address = '${value['address'] ?? ''}'.trim();
    final Uri? uri = Uri.tryParse('http://$address');
    if (nodeId.isEmpty || name.isEmpty || !_isPrivateLanAddress(uri)) {
      return null;
    }
    return LanBackupDiscoveredHost(
      nodeId: nodeId,
      name: name,
      address: address,
      compatible: value['compatible'] == true,
      compatibilityMessage: value['compatibilityMessage'] is String
          ? value['compatibilityMessage'] as String
          : null,
      reachable: false,
    );
  }

  static bool _isPrivateLanAddress(Uri? uri) {
    if (uri == null || uri.host.isEmpty || !uri.hasPort) return false;
    final List<int> parts = uri.host
        .split('.')
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    if (parts.length != 4 || parts.any((part) => part < 0 || part > 255)) {
      return false;
    }
    return parts[0] == 10 ||
        (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
        (parts[0] == 192 && parts[1] == 168);
  }
}
