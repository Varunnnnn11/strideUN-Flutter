import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'register_screen.dart';
import 'main_layout.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  bool _showPass  = false;
  String _error   = '';

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  static const neonPink = Color(0xFFFF2D78);
  static const deepBg   = Color(0xFF080C14);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.10), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Please enter username and password');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() { _isLoading = true; _error = ''; });
    try {
      final result = await ApiService.login(
          _userCtrl.text.trim(), _passCtrl.text);
      if (result['token'] != null) {
        await ApiService.saveToken(result['token']);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => MainLayout(
              username:   result['username']   ?? _userCtrl.text.trim(),
              trailColor: result['trailColor'] ?? 'PINK',
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else {
        setState(() => _error = 'Wrong username or password');
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg.startsWith('Too many')
          ? msg
          : 'Cannot reach server — check your connection');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: deepBg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          const Positioned(top: 0,    left: 0,  child: _CornerBracket()),
          const Positioned(top: 0,    right: 0, child: _CornerBracket(flip: true)),
          const Positioned(bottom: 0, left: 0,  child: _CornerBracket(bottom: true)),
          const Positioned(bottom: 0, right: 0, child: _CornerBracket(flip: true, bottom: true)),

          // Pink glow top center
          Positioned(
            top: -80, left: 0, right: 0,
            child: Center(
              child: Container(
                width: 320, height: 320,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x3AFF2D78), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 64),

                        // ── Big wordmark — no logo image ──────
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              fontSize: 48,
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

                        const SizedBox(height: 8),

                        Text(
                          'CLAIM YOUR WORLD',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 4.0,
                            color: Colors.white.withOpacity(0.28),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Neon accent underline
                        Container(
                          width: 44, height: 2,
                          decoration: BoxDecoration(
                            color: neonPink,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                  color: neonPink.withOpacity(0.7),
                                  blurRadius: 10)
                            ],
                          ),
                        ),

                        const SizedBox(height: 56),

                        _LoginField(
                          controller: _userCtrl,
                          label: 'USERNAME',
                          icon: Icons.person_outline_rounded,
                          onSubmit: (_) => FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 18),

                        _LoginField(
                          controller: _passCtrl,
                          label: 'PASSWORD',
                          icon: Icons.lock_outline_rounded,
                          obscure: !_showPass,
                          onSubmit: (_) => _login(),
                          suffix: GestureDetector(
                            onTap: () =>
                                setState(() => _showPass = !_showPass),
                            child: Icon(
                              _showPass
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.white30, size: 20,
                            ),
                          ),
                        ),
                        // After the password _LoginField widget, add:
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (_, __, ___) => const ForgotPasswordScreen(),
                                transitionsBuilder: (_, anim, __, child) =>
                                    FadeTransition(opacity: anim, child: child),
                              ),
                            ),
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),

                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _error.isEmpty
                              ? const SizedBox(height: 16, key: ValueKey('no'))
                              : Padding(
                            key: const ValueKey('err'),
                            padding: const EdgeInsets.only(top: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: neonPink, size: 14),
                                const SizedBox(width: 6),
                                Text(_error,
                                    style: const TextStyle(
                                        color: neonPink,
                                        fontSize: 12,
                                        letterSpacing: 0.3)),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        Container(
                          width: double.infinity, height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _isLoading ? [] : [
                              BoxShadow(
                                  color: neonPink.withOpacity(0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: neonPink,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                                : const Text('LOGIN',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2.0)),
                          ),
                        ),

                        const SizedBox(height: 40),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Don't have an account?  ",
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.40),
                                    fontSize: 12)),
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (_, __, ___) =>
                                  const RegisterScreen(),
                                  transitionsBuilder: (_, anim, __, child) =>
                                      FadeTransition(
                                          opacity: anim, child: child),
                                ),
                              ),
                              child: const Text('Register',
                                  style: TextStyle(
                                    color: neonPink,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(color: neonPink, blurRadius: 8)
                                    ],
                                  )),
                            ),
                          ],
                        ),

                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final void Function(String)? onSubmit;

  const _LoginField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.onSubmit,
  });

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() { _focus.dispose(); super.dispose(); }

  static const neonPink = Color(0xFFFF2D78);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(widget.label,
              style: TextStyle(
                color: _focused ? neonPink : Colors.white.withOpacity(0.35),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
              )),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: const Color(0xFF111722),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? neonPink : Colors.white.withOpacity(0.08),
              width: 1.5,
            ),
            boxShadow: _focused
                ? [BoxShadow(
                color: neonPink.withOpacity(0.18), blurRadius: 16)]
                : [],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.obscure,
            onSubmitted: widget.onSubmit,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: neonPink,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              prefixIcon: Icon(widget.icon,
                  color: _focused
                      ? neonPink
                      : Colors.white.withOpacity(0.25),
                  size: 20),
              suffixIcon: widget.suffix != null
                  ? Padding(
                padding: const EdgeInsets.only(right: 4),
                child: widget.suffix,
              )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = 1.0;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final dp = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1.2;
    for (double x = step; x < size.width; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawLine(Offset(x - 4, y), Offset(x + 4, y), dp);
        canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), dp);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _CornerBracket extends StatelessWidget {
  final bool flip;
  final bool bottom;
  const _CornerBracket({this.flip = false, this.bottom = false});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flip ? -1 : 1,
      scaleY: bottom ? -1 : 1,
      child: SizedBox(width: 36, height: 36,
          child: CustomPaint(painter: _BracketPainter())),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()..moveTo(0, 22)..lineTo(0, 0)..lineTo(22, 0),
      Paint()
        ..color = const Color(0xFF2D6AFF).withOpacity(0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}