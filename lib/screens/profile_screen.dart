import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'leaderboard_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String username;
  final String trailColor;
  const ProfileScreen({
    super.key,
    required this.username,
    required this.trailColor,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ApiService.getUserStats(widget.username);
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _isLoading = false; });
    }
  }

  Color _getTrailColor(String? color) {
    switch (color) {
      case 'PINK': return const Color(0xFFFF2D78);
      case 'BLUE': return const Color(0xFF2D8BFF);
      case 'GREEN': return const Color(0xFF2DFF78);
      case 'ORANGE': return const Color(0xFFFF8C2D);
      case 'PURPLE': return const Color(0xFF8C2DFF);
      default: return const Color(0xFFFF2D78);
    }
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _getTrailColor(widget.trailColor);

    return Scaffold(
      backgroundColor: const Color(0xFF080c14),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(
            color: Color(0xFFFF2D78)))
            : SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Top bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0d1320),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white54, size: 18),
                    ),
                  ),
                  const Text('PROFILE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        fontSize: 13,
                      )),
                  GestureDetector(
                    onTap: _logout,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0d1320),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(Icons.logout,
                          color: Colors.white54, size: 18),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 36),

              // Avatar + name
              Center(
                child: Column(children: [
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2.5),
                    ),
                    child: Center(
                      child: Text(
                        widget.username[0].toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(widget.username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      )),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'RANK #${_stats?['globalRank'] ?? '?'}',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 36),

              // Stats grid
              const Text('STATS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  )),
              const SizedBox(height: 12),

              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _statCard('🎯', 'ZONES PAINTED',
                      '${_stats?['totalZonesPainted'] ?? 0}', color),
                  _statCard('🏃', 'TOTAL RUNS',
                      '${_stats?['totalRuns'] ?? 0}', color),
                  _statCard('📍', 'DISTANCE',
                      '${((_stats?['totalDistanceMeters'] ?? 0) / 1000).toStringAsFixed(1)}km',
                      color),
                  _statCard('🗺️', 'ACTIVE ZONES',
                      '${_stats?['activeZonesOwned'] ?? 0}', color),
                ],
              ),

              const SizedBox(height: 24),

              // Trail color
              const Text('TRAIL COLOR',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  )),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0d1320),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.trailColor,
                          style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          )),
                      const Text('Your zone color',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          )),
                    ],
                  ),
                ]),
              ),

              const SizedBox(height: 24),

              // Member since
              if (_stats?['memberSince'] != null)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0d1320),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined,
                        color: Colors.white38, size: 20),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('MEMBER SINCE',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              letterSpacing: 2,
                            )),
                        const SizedBox(height: 4),
                        Text(
                            _stats!['memberSince'].toString().substring(0, 10),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            )),
                      ],
                    ),
                  ]),
                ),

              const SizedBox(height: 24),

              // Leaderboard button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => LeaderboardScreen(
                        username: widget.username,
                      ))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0d1320),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🏆', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 10),
                      Text('LEADERBOARD',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          )),
                    ],
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String emoji, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0d1320),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  )),
              Text(label,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    letterSpacing: 1.5,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}