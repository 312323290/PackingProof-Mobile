import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/services/lan_backup_discovery_service.dart';

void main() {
  test('只接受具备录像备份能力的主机', () {
    final Uri uri = Uri.parse('http://192.168.1.20:5280');
    final LanBackupDiscoveredHost? host = parseLanBackupDiscoveredHost(
      uri,
      '{"protocol":"packingproof","protocolVersion":1,'
      '"nodeId":"host-1","nodeName":"仓库电脑","httpPort":5280,'
      '"capabilities":["host","mobile-backup"]}',
    );
    expect(host?.nodeId, 'host-1');
    expect(host?.address, '192.168.1.20:5280');
    expect(
      parseLanBackupDiscoveredHost(
        uri,
        '{"protocol":"packingproof","protocolVersion":1,'
        '"nodeId":"client-1","capabilities":["recording"]}',
      ),
      isNull,
    );
  });

  test('搜索进度来自真实候选地址完成数并合并同一主机', () async {
    final LanBackupHostDiscoveryService service = LanBackupHostDiscoveryService(
      candidateProvider: () async => <Uri>[
        Uri.parse('http://192.168.1.10:5280'),
        Uri.parse('http://192.168.1.11:5280'),
        Uri.parse('http://192.168.1.12:5280'),
      ],
      probe: (Uri uri) async => uri.host == '192.168.1.10'
          ? const LanBackupDiscoveredHost(
              nodeId: 'host-1',
              name: '保存主机',
              address: '192.168.1.10:5280',
            )
          : null,
    );
    addTearDown(service.dispose);
    final List<LanBackupDiscoverySnapshot> snapshots =
        <LanBackupDiscoverySnapshot>[];
    service.addListener(() => snapshots.add(service.snapshot));

    await service.search();

    expect(service.snapshot.searching, isFalse);
    expect(service.snapshot.completed, 3);
    expect(service.snapshot.total, 3);
    expect(service.snapshot.progress, 1);
    expect(service.snapshot.hosts.single.nodeId, 'host-1');
    expect(snapshots.any((item) => item.searching), isTrue);
  });
}
