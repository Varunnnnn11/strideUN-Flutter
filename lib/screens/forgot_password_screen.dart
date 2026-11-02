import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {

  final _emailCtrl = TextEditingController();
  bool _isLoading  = false;
  bool _sent       = false;
  String _error    = '';

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  static const neonPink = Color(0xFFFF2D78);
  static const deepBg   = Color(0xFF080C14);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() { _isLoading = true; _error = ''; });

    try {
      await ApiService.forgotPassword(email);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        setState(() => _error = msg.startsWith('Too many')
            ? msg
            : 'Cannot reach server — check your connection');
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: deepBg,
      body: Stack(
        children: [
          // Grid background
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),

          // Pink glow
          Positioned(
            top: -80, left: 0, right: 0,
            child: Center(
              child: Container(
                width: 280, height: 280,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x28FF2D78), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Back button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white54,
                        size: 20),
                    padding: const EdgeInsets.all(16),
                  ),
                ),

                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: SlideTransition(
                          position: _slideAnim,
                          child: _sent
                              ? _buildSuccessState()
                              : _buildFormState(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Lock icon
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF1A0A12),
            shape: BoxShape.circle,
            border: Border.all(
                color: neonPink.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: neonPink.withOpacity(0.15),
                  blurRadius: 20)
            ],
          ),
          child: const Icon(
              Icons.lock_reset_rounded,
              color: neonPink,
              size: 32),
        ),

        const SizedBox(height: 24),

        const Text(
          'Forgot Password?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Enter your registered email.\nWe\'ll send you a reset link.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 13,
            height: 1.6,
          ),
        ),

        const SizedBox(height: 40),

        // Email field
        _buildEmailField(),

        // Error
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _error.isEmpty
              ? const SizedBox(height: 16, key: ValueKey('no'))
              : Padding(
            key: const ValueKey('err'),
            padding: const EdgeInsets.only(top: 12),
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

        // Send button
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
            onPressed: _isLoading ? null : _sendReset,
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
                : const Text('SEND RESET LINK',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0)),
          ),
        ),

        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Green check
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF041A0E),
            shape: BoxShape.circle,
            border: Border.all(
                color: const Color(0xFF00FF82).withOpacity(0.3),
                width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF00FF82).withOpacity(0.15),
                  blurRadius: 24)
            ],
          ),
          child: const Icon(
              Icons.mark_email_read_rounded,
              color: Color(0xFF00FF82),
              size: 36),
        ),

        const SizedBox(height: 28),

        const Text(
          'Check Your Email',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),

        const SizedBox(height: 12),

        Text(
          'If ${_emailCtrl.text.trim()} is registered,\nyou\'ll get a reset link shortly.\n\nLink expires in 15 minutes.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 13,
            height: 1.7,
          ),
        ),

        const SizedBox(height: 40),

        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Back to Login',
            style: TextStyle(
              color: neonPink,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: neonPink, blurRadius: 8)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text('EMAIL',
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
              )),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111722),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Colors.white.withOpacity(0.08), width: 1.5),
          ),
          child: TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _sendReset(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: neonPink,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
              const EdgeInsets.symmetric(vertical: 16),
              prefixIcon: Icon(Icons.email_outlined,
                  color: Colors.white.withOpacity(0.25), size: 20),
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}