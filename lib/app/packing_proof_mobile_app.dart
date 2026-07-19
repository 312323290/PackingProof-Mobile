import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../screens/packing_home_screen.dart';
import '../services/session_repository.dart';
import 'app_build_config.dart';

class PackingProofMobileApp extends StatefulWidget {
  const PackingProofMobileApp({
    this.buildConfig = AppBuildConfig.environment,
    this.repository,
    super.key,
  });

  final AppBuildConfig buildConfig;
  final SessionRepository? repository;

  static const Color forest = Color(0xFF087454);
  static const Color ink = Color(0xFF151918);
  static const Color mineral = Color(0xFFF4F5F2);

  @override
  State<PackingProofMobileApp> createState() => _PackingProofMobileAppState();
}

class _PackingProofMobileAppState extends State<PackingProofMobileApp> {
  late final SessionRepository _repository;
  late final Future<AppSettings> _settings;

  @override
  void initState() {
    super.initState();
    widget.buildConfig.validate();
    _repository = widget.repository ?? SessionRepository();
    _settings = _repository.loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = ColorScheme.fromSeed(
      seedColor: PackingProofMobileApp.forest,
      brightness: Brightness.light,
      surface: Colors.white,
    );

    return MaterialApp(
      title: widget.buildConfig.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: Colors.white,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: PackingProofMobileApp.ink,
          displayColor: PackingProofMobileApp.ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: PackingProofMobileApp.ink,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: PackingProofMobileApp.forest,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(58),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
      home: FutureBuilder<AppSettings>(
        future: _settings,
        builder: (BuildContext context, AsyncSnapshot<AppSettings> snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return _StartupNoticeGate(
            buildConfig: widget.buildConfig,
            repository: _repository,
            settings: snapshot.data!,
          );
        },
      ),
    );
  }
}

class _StartupNoticeGate extends StatefulWidget {
  const _StartupNoticeGate({
    required this.buildConfig,
    required this.repository,
    required this.settings,
  });

  final AppBuildConfig buildConfig;
  final SessionRepository repository;
  final AppSettings settings;

  @override
  State<_StartupNoticeGate> createState() => _StartupNoticeGateState();
}

class _StartupNoticeGateState extends State<_StartupNoticeGate> {
  static const int _noticeVersion = 1;
  bool _continueToCamera = false;

  @override
  Widget build(BuildContext context) {
    final bool needsNotice =
        widget.settings.startupNoticeVersion < _noticeVersion &&
        !_continueToCamera;
    if (!needsNotice) {
      return PackingHomeScreen(
        repository: widget.repository,
        buildConfig: widget.buildConfig,
      );
    }
    return StartupNoticeScreen(
      buildConfig: widget.buildConfig,
      onConfirm: () async {
        await widget.repository.saveStartupNoticeVersion(_noticeVersion);
        if (mounted) setState(() => _continueToCamera = true);
      },
    );
  }
}

class StartupNoticeScreen extends StatelessWidget {
  const StartupNoticeScreen({
    required this.buildConfig,
    required this.onConfirm,
    super.key,
  });

  final AppBuildConfig buildConfig;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Image.asset(
                  'assets/images/app-icon.png',
                  key: const Key('startup-notice-app-icon'),
                  width: 72,
                  height: 72,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '欢迎使用包裹留证',
                key: Key('startup-notice-title'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              Container(
                key: const Key('startup-notice-card'),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6F4),
                  border: Border.all(color: const Color(0xFFD5E0DB)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'PackingProof-Mobile（包裹留证）\n'
                      '是一款开源且免费的包裹录像留证工具\n\n'
                      '录像和面单号仅保存在本机，不会上传到互联网\n\n'
                      '只有你主动连接电脑后，才会通过局域网备份录像',
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontSize: 15, height: 1.65),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('startup-notice-confirm'),
                onPressed: onConfirm,
                child: const Text('开始使用'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
