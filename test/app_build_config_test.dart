import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/app/app_build_config.dart';

void main() {
  test('统一版本使用固定应用标题并保留构建信息', () {
    const AppBuildConfig config = AppBuildConfig(
      buildRevision: 'abc1234',
      buildTimestamp: '2026-07-22T00:00:00Z',
    );

    expect(config.appTitle, '包裹留证');
    expect(config.buildRevision, 'abc1234');
  });
}
