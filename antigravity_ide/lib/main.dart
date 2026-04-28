import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'presentation/editor_screen.dart';

import 'presentation/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const LocodeApp());
}

class LocodeApp extends StatelessWidget {
  const LocodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Locode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        fontFamily: 'sans-serif', // Use local system font to avoid CDN lookups
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFFF),
          surface: Color(0xFF0A0A12),
        ),
        useMaterial3: true,
      ),
      home: const LocodeSplashScreen(),
    );
  }
}
