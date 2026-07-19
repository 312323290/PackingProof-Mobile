import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/packing_proof_mobile_app.dart';
import 'app/app_build_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  AppBuildConfig.environment.validate();
  runApp(const PackingProofMobileApp());
}
