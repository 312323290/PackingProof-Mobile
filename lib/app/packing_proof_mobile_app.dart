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
        fontFamily: 'NotoSansSC',
        fontFamilyFallback: const <String>[
          'Noto Sans CJK SC',
          'Microsoft YaHei',
          'PingFang SC',
        ],
        textTheme: ThemeData.light().textTheme.apply(
          fontFamily: 'NotoSansSC',
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
              fontFamily: 'NotoSansSC',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontFamily: 'NotoSansSC'),
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
          return _StandaloneStartupGate(
            buildConfig: widget.buildConfig,
            repository: _repository,
            settings: snapshot.data!,
          );
        },
      ),
    );
  }
}

class _StandaloneStartupGate extends StatefulWidget {
  const _StandaloneStartupGate({
    required this.buildConfig,
    required this.repository,
    required this.settings,
  });

  final AppBuildConfig buildConfig;
  final SessionRepository repository;
  final AppSettings settings;

  @override
  State<_StandaloneStartupGate> createState() =>
      _StandaloneStartupGateState();
}

class _StandaloneStartupGateState extends State<_StandaloneStartupGate> {
  bool _continueToCamera = false;
  bool _doNotShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final bool needsNotice = widget.buildConfig.isStandalone &&
        !widget.settings.standaloneNoticeDismissed &&
        !_continueToCamera;
    if (!needsNotice) {
      return PackingHomeScreen(
        repository: widget.repository,
        buildConfig: widget.buildConfig,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Icon(
                Icons.phonelink_lock_rounded,
                size: 58,
                color: PackingProofMobileApp.forest,
              ),
              const SizedBox(height: 24),
              const Text(
                '单机版说明',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              const Text(
                '本版本仅在本机运行，不会将录像、面单号或其他数据上传到互联网。只有在你主动连接电脑后，才会通过局域网备份录像。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.65),
              ),
              const SizedBox(height: 20),
              CheckboxListTile(
                key: const Key('standalone-notice-dismiss-checkbox'),
                contentPadding: EdgeInsets.zero,
                title: const Text('下次不再提示'),
                value: _doNotShowAgain,
                onChanged: (bool? value) {
                  setState(() => _doNotShowAgain = value ?? false);
                },
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('standalone-notice-confirm'),
                onPressed: () async {
                  if (_doNotShowAgain) {
                    await widget.repository.saveStandaloneNoticeDismissed(true);
                  }
                  if (mounted) {
                    setState(() => _continueToCamera = true);
                  }
                },
                child: const Text('我知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
