enum AppEdition { standard, standalone }

enum NetworkPolicy { publicAllowed, localOnly }

class AppBuildConfig {
  const AppBuildConfig({
    required this.edition,
    required this.onlineEdgeTtsEnabled,
    required this.networkPolicy,
  });

  static const AppBuildConfig environment = AppBuildConfig(
    edition: String.fromEnvironment('APP_EDITION') == 'standalone'
        ? AppEdition.standalone
        : AppEdition.standard,
    onlineEdgeTtsEnabled: bool.fromEnvironment(
      'ONLINE_EDGE_TTS_ENABLED',
      defaultValue: true,
    ),
    networkPolicy: String.fromEnvironment('NETWORK_POLICY') == 'localOnly'
        ? NetworkPolicy.localOnly
        : NetworkPolicy.publicAllowed,
  );

  final AppEdition edition;
  final bool onlineEdgeTtsEnabled;
  final NetworkPolicy networkPolicy;

  bool get isStandalone => edition == AppEdition.standalone;
  String get appTitle => isStandalone ? '包裹留证-单机版' : '包裹留证';

  void validate() {
    if (isStandalone && onlineEdgeTtsEnabled) {
      throw StateError('单机版不能启用在线 Edge TTS');
    }
    if (isStandalone && networkPolicy != NetworkPolicy.localOnly) {
      throw StateError('单机版必须使用 localOnly 网络策略');
    }
    if (!isStandalone && networkPolicy != NetworkPolicy.publicAllowed) {
      throw StateError('普通版必须使用 publicAllowed 网络策略');
    }
  }
}
