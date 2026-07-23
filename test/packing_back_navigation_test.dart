import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/screens/packing_home_screen.dart';

void main() {
  final DateTime now = DateTime(2026, 7, 23, 12);

  test('返回键优先取消电脑连接和历史扫码', () {
    expect(
      _resolve(now, pairingActive: true, historyScanActive: true),
      PackingBackAction.cancelPairing,
    );
    expect(
      _resolve(now, historyScanActive: true),
      PackingBackAction.cancelHistoryScan,
    );
    expect(
      _resolve(now, pairingMessageVisible: true),
      PackingBackAction.cancelPairing,
    );
  });

  test('工作中拦截返回且其他主标签先回录像首页', () {
    expect(
      _resolve(now, workInProgress: true, selectedTab: 0),
      PackingBackAction.keepWorking,
    );
    expect(_resolve(now, selectedTab: 0), PackingBackAction.showHome);
    expect(_resolve(now, selectedTab: 2), PackingBackAction.showHome);
  });

  test('录像首页两秒内第二次返回才退出', () {
    expect(_resolve(now), PackingBackAction.armExit);
    expect(
      _resolve(now, exitArmedAt: now.subtract(const Duration(seconds: 2))),
      PackingBackAction.exitApp,
    );
    expect(
      _resolve(
        now,
        exitArmedAt: now.subtract(const Duration(seconds: 2, milliseconds: 1)),
      ),
      PackingBackAction.armExit,
    );
  });
}

PackingBackAction _resolve(
  DateTime now, {
  bool pairingActive = false,
  bool pairingMessageVisible = false,
  bool historyScanActive = false,
  bool workInProgress = false,
  int selectedTab = 1,
  DateTime? exitArmedAt,
}) {
  return resolvePackingBackAction(
    pairingActive: pairingActive,
    pairingMessageVisible: pairingMessageVisible,
    historyScanActive: historyScanActive,
    workInProgress: workInProgress,
    selectedTab: selectedTab,
    now: now,
    exitArmedAt: exitArmedAt,
  );
}
