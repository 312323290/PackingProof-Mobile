import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/services/lan_backup_discovery_service.dart';

void main() {
  test('只接受具备手机备份能力的 PackingProof 主机', () {
    final Uri address = Uri.parse('http://192.168.1.20:5280');
    final LanBackupDiscoveredHost? host = parseLanBackupDiscoveredHost(
      address,
      '{"protocol":"packingproof","protocolVersion":1,'
      '"nodeId":"host-1","nodeName":"仓库电脑","httpPort":5290,'
      '"capabilities":["host","mobile-backup"]}',
    );
    final LanBackupDiscoveredHost? workstation = parseLanBackupDiscoveredHost(
      address,
      '{"protocol":"packingproof","protocolVersion":1,'
      '"nodeId":"workstation-1","nodeName":"录制电脑",'
      '"capabilities":["recording","order-receiver"]}',
    );

    expect(host?.name, '仓库电脑');
    expect(host?.address, '192.168.1.20:5290');
    expect(workstation, isNull);
  });

  test('自动搜索报告真实进度并去重发现结果', () async {
    final List<Uri> candidates = <Uri>[
      Uri.parse('http://192.168.1.20:5280'),
      Uri.parse('http://192.168.1.21:5280'),
      Uri.parse('http://192.168.1.22:5280'),
    ];
    final List<LanBackupDiscoverySnapshot> snapshots =
        <LanBackupDiscoverySnapshot>[];
    final LanBackupHostDiscoveryService service = LanBackupHostDiscoveryService(
      candidateProvider: () async => candidates,
      probe: (Uri uri) async => uri.host == '192.168.1.21'
          ? const LanBackupDiscoveredHost(
              nodeId: 'host-1',
              name: '电脑1',
              address: '192.168.1.21:5280',
            )
          : null,
    );
    addTearDown(service.dispose);
    service.addListener(() => snapshots.add(service.snapshot));

    await service.search();

    expect(snapshots.any((item) => item.searching && item.total == 3), isTrue);
    expect(service.snapshot.completed, 3);
    expect(service.snapshot.progress, 1);
    expect(service.snapshot.hosts, hasLength(1));
    expect(service.snapshot.message, '找到 1 台录像备份主机');
  });

  test('较早搜索结果不会覆盖后来一次搜索', () async {
    final Completer<LanBackupDiscoveredHost?> first =
        Completer<LanBackupDiscoveredHost?>();
    int round = 0;
    final LanBackupHostDiscoveryService service = LanBackupHostDiscoveryService(
      candidateProvider: () async {
        round++;
        return <Uri>[Uri.parse('http://192.168.1.$round:5280')];
      },
      probe: (Uri uri) {
        if (uri.host.endsWith('.1')) return first.future;
        return Future<LanBackupDiscoveredHost?>.value(
          const LanBackupDiscoveredHost(
            nodeId: 'new-host',
            name: '新主机',
            address: '192.168.1.2:5280',
          ),
        );
      },
    );
    addTearDown(service.dispose);

    final Future<void> staleSearch = service.search();
    await Future<void>.delayed(Duration.zero);
    await service.search();
    first.complete(
      const LanBackupDiscoveredHost(
        nodeId: 'old-host',
        name: '旧主机',
        address: '192.168.1.1:5280',
      ),
    );
    await staleSearch;

    expect(service.snapshot.hosts.single.name, '新主机');
  });
}
