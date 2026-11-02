import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import 'activity_screen.dart';

class MainLayout extends StatefulWidget {
  final String username;
  final String trailColor;

  const MainLayout({
    super.key,
    required this.username,
    required this.trailColor,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout>
    with TickerProviderStateMixin {

  int _currentIndex = 0;

  static const Color _bg        = Color(0xFF0D1017);
  static const Color _barBg     = Color(0xFF10151F);
  static const Color _barBorder = Color(0xFF1A2030);
  static const Color _inactive  = Color(0xFF4A5568);

  Color get _active => _colorFromString(widget.trailColor);

  late final List<AnimationController> _tabCtrls;
  late final List<Animation<double>>   _tabScales;
  late final List<Widget>              _screens;

  @override
  void initState() {
    super.initState();

    _tabCtrls = List.generate(3, (_) =>
    AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 120),
        lowerBound: 0.85,
        upperBound: 1.0)
      ..value = 1.0);

    _tabScales = _tabCtrls
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();

    _screens = [
      HomeScreen(username: widget.username, trailColor: widget.trailColor),
      LeaderboardScreen(username: widget.username),
      ProfileScreen(username: widget.username, trailColor: widget.trailColor),
    ];
  }

  @override
  void dispose() {
    for (final c in _tabCtrls) c.dispose();
    super.dispose();
  }

  // ── Consistent color resolver (matches register + login) ──────
  Color _colorFromString(String c) {
    switch (c.toUpperCase()) {
      case 'PINK':   return const Color(0xFFFF2D78);
      case 'BLUE':   return const Color(0xFF4A72FF);
      case 'GREEN':  return const Color(0xFF00E676);
      case 'ORANGE': return const Color(0xFFFF8C2D);
      case 'CYAN':   return const Color(0xFF00E5FF);
      case 'PURPLE': return const Color(0xFF8C2DFF);
      default:       return const Color(0xFFFF2D78);
    }
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    HapticFeedback.lightImpact();
    _tabCtrls[index].reverse().then((_) => _tabCtrls[index].forward());
    setState(() => _currentIndex = index);
  }

  void _onMapTapped() {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => ActivityScreen(
          username:   widget.username,
          trailColor: widget.trailColor,
        ),
        transitionDuration: const Duration(milliseconds: 380),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildBar(),
    );
  }

  Widget _buildBar() {
    return Container(
      decoration: BoxDecoration(
        color: _barBg,
        border: Border(top: BorderSide(color: _barBorder, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(children: [
            _tab(0, Icons.home_outlined,          'Home'),
            _tab(1, Icons.leaderboard_outlined,   'Ranks'),
            _mapBtn(),
            _tab(2, Icons.person_outline_rounded, 'You'),
          ]),
        ),
      ),
    );
  }

  Widget _tab(int index, IconData icon, String label) {
    final active = _currentIndex == index;
    final color  = active ? _active : _inactive;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabTapped(index),
        behavior: HitTestBehavior.opaque,
        child: ScaleTransition(
          scale: _tabScales[index],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: active
                    ? BoxDecoration(
                  color: _active.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                )
                    : null,
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.3,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ── Center Map button — crisp, no overflow ─────────────────────
  Widget _mapBtn() {
    final color = _active;
    return Expanded(
      child: GestureDetector(
        onTap: _onMapTapped,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Use RepaintBoundary to prevent blur bleeding
            RepaintBoundary(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.35),
                      blurRadius: 10,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.map_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Map',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}