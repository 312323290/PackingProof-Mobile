import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/app/app_build_config.dart';

void main() {
  test('单机版拒绝在线 Edge TTS', () {
    const AppBuildConfig config = AppBuildConfig(
      edition: AppEdition.standalone,
      onlineEdgeTtsEnabled: true,
      networkPolicy: NetworkPolicy.localOnly,
    );
    expect(config.validate, throwsStateError);
  });

  test('单机版必须限制为局域网', () {
    const AppBuildConfig config = AppBuildConfig(
      edition: AppEdition.standalone,
      onlineEdgeTtsEnabled: false,
      networkPolicy: NetworkPolicy.publicAllowed,
    );
    expect(config.validate, throwsStateError);
  });

  test('两种正式配置均有效', () {
    const AppBuildConfig(
      edition: AppEdition.standard,
      onlineEdgeTtsEnabled: true,
      networkPolicy: NetworkPolicy.publicAllowed,
    ).validate();
    const AppBuildConfig(
      edition: AppEdition.standalone,
      onlineEdgeTtsEnabled: false,
      networkPolicy: NetworkPolicy.localOnly,
    ).validate();
  });
}
