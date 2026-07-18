import 'package:flutter/material.dart';

import '../screens/packing_home_screen.dart';

class PackingProofMobileApp extends StatelessWidget {
  const PackingProofMobileApp({super.key});

  static const Color forest = Color(0xFF087454);
  static const Color ink = Color(0xFF151918);
  static const Color mineral = Color(0xFFF4F5F2);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = ColorScheme.fromSeed(
      seedColor: forest,
      brightness: Brightness.light,
      surface: Colors.white,
    );

    return MaterialApp(
      title: 'PackingProof-Mobile',
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
          bodyColor: ink,
          displayColor: ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: forest,
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
      home: const PackingHomeScreen(),
    );
  }
}
