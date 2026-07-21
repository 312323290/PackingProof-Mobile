class AppBuildConfig {
  const AppBuildConfig({this.buildRevision = '', this.buildTimestamp = ''});

  static const AppBuildConfig environment = AppBuildConfig(
    buildRevision: String.fromEnvironment('BUILD_REVISION'),
    buildTimestamp: String.fromEnvironment('BUILD_TIMESTAMP'),
  );

  final String buildRevision;
  final String buildTimestamp;

  String get appTitle => '包裹留证';
}
