import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const AuraRunApp());
}

class AuraRunApp extends StatelessWidget {
  const AuraRunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuraRun',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF2D78),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}