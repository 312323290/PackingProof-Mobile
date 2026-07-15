import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_lens/app/parcel_lens_app.dart';
import 'package:parcel_lens/controllers/packing_session_controller.dart';
import 'package:parcel_lens/screens/packing_home_screen.dart';

void main() {
  testWidgets('390x844 首页视觉基线', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      final Uint8List textFont = await File(
        'assets/fonts/NotoSansSC-Subset.ttf',
      ).readAsBytes();
      final File executable = File(Platform.resolvedExecutable);
      Directory flutterRoot = executable.parent;
      while (!Directory(
        '${flutterRoot.path}${Platform.pathSeparator}packages'
        '${Platform.pathSeparator}flutter',
      ).existsSync()) {
        if (flutterRoot.parent.path == flutterRoot.path) {
          throw StateError('无法从 Dart 运行时定位 Flutter SDK');
        }
        flutterRoot = flutterRoot.parent;
      }
      final Uint8List iconFont = await File(
        '${flutterRoot.path}${Platform.pathSeparator}bin${Platform.pathSeparator}'
        'cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}'
        'material_fonts${Platform.pathSeparator}MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader('NotoSansSC')
            ..addFont(Future<ByteData>.value(ByteData.sublistView(textFont))))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(Future<ByteData>.value(ByteData.sublistView(iconFont))))
          .load();
    });

    final MemoryImage preview = MemoryImage(
      File('assets/images/packing-preview.png').readAsBytesSync(),
    );
    final ThemeData theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ParcelLensApp.forest,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      fontFamily: 'NotoSansSC',
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'NotoSansSC',
        bodyColor: ParcelLensApp.ink,
        displayColor: ParcelLensApp.ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ParcelLensApp.forest,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontFamily: 'NotoSansSC'),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: PackingHomeView(
          phase: PackingSessionPhase.ready,
          elapsed: Duration.zero,
          previewOverride: Image(image: preview, fit: BoxFit.cover),
          onPrimaryPressed: () {},
          onRetryPressed: () {},
          onRecordingsPressed: () {},
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        preview,
        tester.element(find.byType(PackingHomeView)),
      );
    });
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PackingHomeView),
      matchesGoldenFile('goldens/home_ready.png'),
    );
  });
}
