import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'main_layout.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const deepBg   = Color(0xFF080C14);
  static const neonPink = Color(0xFFFF2D78);

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 600)); // splash feel

    final token        = await ApiService.getToken();
    final refreshToken = await ApiService.getRefreshToken();

    if (token == null && refreshToken == null) {
      _goLogin();
      return;
    }

    // Try to refresh — if refresh token is still valid, we get a new access token
    if (token == null && refreshToken != null) {
      final refreshed = await ApiService.tryRefresh();
      if (!refreshed) { _goLogin(); return; }
    }

    // We have a token — fetch user info to validate + get username/color
    try {
      await ApiService.refreshUserInfo(); // ✅ sync from server
      final prefs    = await ApiService.getSavedUserInfo();
      final username = prefs['username'];
      final color    = prefs['trailColor'] ?? 'PINK';

      if (username == null) { _goLogin(); return; }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => MainLayout(
            username:   username,
            trailColor: color,
          ),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (_) {
      _goLogin();
    }
  }

  void _goLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: deepBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
                children: [
                  TextSpan(
                    text: 'stride',
                    style: TextStyle(color: Colors.white),
                  ),
                  TextSpan(
                    text: 'UN',
                    style: TextStyle(
                      color: neonPink,
                      shadows: [
                        Shadow(color: neonPink, blurRadius: 20),
                        Shadow(color: neonPink, blurRadius: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                color: neonPink, strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}