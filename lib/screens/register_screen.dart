import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'main_layout.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {

  final _userCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController(); // ✅ NEW
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool   _isLoading   = false;
  bool   _showPass    = false;
  bool   _showConfirm = false;
  String _error       = '';
  String _selectedColor = 'PINK';

  static const _colors = [
    {'id': 'PINK',   'hex': Color(0xFFFF2D78), 'label': 'Pink'},
    {'id': 'BLUE',   'hex': Color(0xFF4A72FF), 'label': 'Blue'},
    {'id': 'GREEN',  'hex': Color(0xFF00E676), 'label': 'Green'},
    {'id': 'ORANGE', 'hex': Color(0xFFFF8C2D), 'label': 'Orange'},
    {'id': 'PURPLE', 'hex': Color(0xFF8C2DFF), 'label': 'Purple'},
    {'id': 'CYAN',   'hex': Color(0xFF00E5FF), 'label': 'Cyan'},
  ];

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  Color get _accent => _colors.firstWhere(
        (c) => c['id'] == _selectedColor,
    orElse: () => _colors[0],
  )['hex'] as Color;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _userCtrl.dispose();
    _emailCtrl.dispose(); // ✅ NEW
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = _userCtrl.text.trim();
    final email    = _emailCtrl.text.trim(); // ✅ NEW
    final password = _passCtrl.text;
    final confirm  = _confirmCtrl.text;

    // ── Validation ──────────────────────────────────────────
    if (username.length < 3) {
      setState(() => _error = 'Username must be at least 3 characters');
      return;
    }
    // ✅ NEW — email validation
    if (email.isEmpty) {
      setState(() => _error = 'Email is required');
      return;
    }
    final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() { _isLoading = true; _error = ''; });

    try {
      final result = await ApiService.register(
        username, password,
        email: email,           // ✅ NEW
        trailColor: _selectedColor,
      );
      if (result['token'] != null) {
        await ApiService.saveTokens(
          result['token'],
          result['refreshToken'] ?? '',
        );
        if (!mounted) return;
        final savedColor = result['trailColor'] ?? _selectedColor;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => MainLayout(
              username:   result['username'] ?? username,
              trailColor: savedColor,
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else {
        // ✅ FIXED — show actual server error, not generic message
        setState(() => _error = result['message'] ?? 'Registration failed');
      }
    } catch (e) {
      // ✅ FIXED — show actual exception message for easier debugging
      setState(() => _error = 'Registration failed: ${e.toString().replaceAll('Exception: ', '')}');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          const Positioned(top: 0,    left: 0,  child: _CornerBracket()),
          const Positioned(top: 0,    right: 0, child: _CornerBracket(flip: true)),
          const Positioned(bottom: 0, left: 0,  child: _CornerBracket(bottom: true)),
          const Positioned(bottom: 0, right: 0, child: _CornerBracket(flip: true, bottom: true)),

          // Accent glow top right
          Positioned(
            top: -80, right: -80,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [accent.withValues(alpha: 0.10), Colors.transparent],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),

                      // Back button
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111722),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: accent.withValues(alpha: 0.45), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                  color: accent.withValues(alpha: 0.15),
                                  blurRadius: 10)
                            ],
                          ),
                          child: Icon(Icons.arrow_back_rounded,
                              color: accent, size: 17),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── Wordmark ───────────────────────────
                      Center(
                        child: Column(
                          children: [
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'stride',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  TextSpan(
                                    text: 'UN',
                                    style: TextStyle(
                                      color: accent,
                                      shadows: [
                                        Shadow(color: accent, blurRadius: 16),
                                        Shadow(color: accent, blurRadius: 32),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'CLAIM YOUR WORLD',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 3.5,
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                            ),
                            const SizedBox(height: 8),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              width: 36, height: 2,
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [
                                  BoxShadow(
                                      color: accent.withValues(alpha: 0.7),
                                      blurRadius: 8)
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Section label
                      Text('CREATE ACCOUNT',
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                          )),
                      const SizedBox(height: 4),
                      Text('Join the territory war',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 13,
                          )),

                      const SizedBox(height: 24),

                      // USERNAME
                      _RegField(
                        controller: _userCtrl,
                        label: 'USERNAME',
                        hint: 'choose a unique username',
                        icon: Icons.person_add_alt_rounded,
                        accentColor: accent,
                        keyboardType: TextInputType.text,
                        onSubmit: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: 16),

                      // ✅ NEW — EMAIL FIELD
                      _RegField(
                        controller: _emailCtrl,
                        label: 'EMAIL',
                        hint: 'your@email.com',
                        icon: Icons.email_outlined,
                        accentColor: accent,
                        keyboardType: TextInputType.emailAddress,
                        onSubmit: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: 16),

                      // PASSWORD
                      _RegField(
                        controller: _passCtrl,
                        label: 'PASSWORD',
                        hint: 'min 6 characters',
                        icon: Icons.lock_outline_rounded,
                        accentColor: accent,
                        obscure: !_showPass,
                        onSubmit: (_) => FocusScope.of(context).nextFocus(),
                        suffix: _eyeBtn(_showPass,
                                () => setState(() => _showPass = !_showPass)),
                      ),
                      const SizedBox(height: 16),

                      // CONFIRM PASSWORD
                      _RegField(
                        controller: _confirmCtrl,
                        label: 'CONFIRM PASSWORD',
                        hint: 'repeat your password',
                        icon: Icons.vpn_key_outlined,
                        accentColor: accent,
                        obscure: !_showConfirm,
                        onSubmit: (_) => _register(),
                        suffix: _eyeBtn(_showConfirm,
                                () => setState(() => _showConfirm = !_showConfirm)),
                      ),

                      const SizedBox(height: 28),

                      // Trail color picker
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E1520),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.25), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                                color: accent.withValues(alpha: 0.06),
                                blurRadius: 20,
                                spreadRadius: 2)
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: accent, blurRadius: 6)
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('TRAIL COLOR',
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2.5,
                                  )),
                            ]),
                            const SizedBox(height: 6),
                            Text('Your color paints the map as you run.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  fontSize: 11,
                                )),
                            const SizedBox(height: 18),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 2.4,
                              ),
                              itemCount: _colors.length,
                              itemBuilder: (context, i) {
                                final c     = _colors[i];
                                final id    = c['id']    as String;
                                final color = c['hex']   as Color;
                                final label = c['label'] as String;
                                final sel   = _selectedColor == id;
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    setState(() => _selectedColor = id);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: sel ? 0.18 : 0.07),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: sel ? color : color.withValues(alpha: 0.25),
                                        width: sel ? 1.5 : 1,
                                      ),
                                      boxShadow: sel
                                          ? [BoxShadow(
                                          color: color.withValues(alpha: 0.4),
                                          blurRadius: 10)]
                                          : [],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 7, height: 7,
                                          decoration: BoxDecoration(
                                            color: color,
                                            shape: BoxShape.circle,
                                            boxShadow: sel
                                                ? [BoxShadow(
                                                color: color, blurRadius: 5)]
                                                : [],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        AnimatedDefaultTextStyle(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          style: TextStyle(
                                            color: sel ? color : Colors.white38,
                                            fontSize: 10,
                                            fontWeight: sel
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            letterSpacing: 1,
                                          ),
                                          child: Text(label.toUpperCase()),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Error banner
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _error.isEmpty
                            ? const SizedBox(key: ValueKey('no'))
                            : Container(
                          key: const ValueKey('err'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEE4B2B).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFEE4B2B).withValues(alpha: 0.45)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFEE4B2B), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error,
                                  style: const TextStyle(
                                      color: Color(0xFFEE4B2B),
                                      fontSize: 12,
                                      letterSpacing: 0.4)),
                            ),
                          ]),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Register button
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: double.infinity, height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _isLoading ? [] : [
                            BoxShadow(
                                color: accent.withValues(alpha: 0.45),
                                blurRadius: 20,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                              : const Text('CREATE ACCOUNT',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2.0)),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text('BACK TO LOGIN',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.28),
                                fontSize: 11,
                                letterSpacing: 2.0,
                                fontWeight: FontWeight.w500,
                              )),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eyeBtn(bool visible, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: Colors.white30, size: 18,
      ),
    ),
  );
}

// ── Reusable text field ──────────────────────────────────────────────────────
class _RegField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color accentColor;
  final bool obscure;
  final Widget? suffix;
  final void Function(String)? onSubmit;
  final TextInputType keyboardType; // ✅ NEW

  const _RegField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.accentColor,
    this.obscure = false,
    this.suffix,
    this.onSubmit,
    this.keyboardType = TextInputType.text, // ✅ NEW
  });

  @override
  State<_RegField> createState() => _RegFieldState();
}

class _RegFieldState extends State<_RegField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() { _focus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(widget.label,
              style: TextStyle(
                color: _focused ? accent : Colors.white.withValues(alpha: 0.35),
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
              color: _focused ? accent : Colors.white.withValues(alpha: 0.08),
              width: 1.5,
            ),
            boxShadow: _focused
                ? [BoxShadow(color: accent.withValues(alpha: 0.20), blurRadius: 16)]
                : [],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.obscure,
            onSubmitted: widget.onSubmit,
            keyboardType: widget.keyboardType, // ✅ NEW
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: accent,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.18), fontSize: 12),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              prefixIcon: Icon(widget.icon,
                  color: _focused ? accent : Colors.white.withValues(alpha: 0.25),
                  size: 19),
              suffixIcon: widget.suffix,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Painters (unchanged) ─────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x08FFFFFF)..strokeWidth = 1.0;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final dp = Paint()..color = const Color(0x14FFFFFF)..strokeWidth = 1.2;
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
        ..color = const Color(0xFF2D6AFF).withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}