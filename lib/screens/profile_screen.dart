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
  List<dynamic> _runs = [];
  bool _isLoading = true;
  bool _runsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadRuns();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ApiService.getUserStats(widget.username);
      if (mounted) setState(() { _stats = stats; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRuns() async {
    try {
      final runs = await ApiService.getRunHistory(widget.username);
      if (mounted) setState(() { _runs = runs; _runsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _runsLoading = false);
    }
  }

  Color _getColor(String? c) {
    switch (c?.toUpperCase()) {
      case 'PINK':   return const Color(0xFFFF2D78);
      case 'BLUE':   return const Color(0xFF4A72FF);
      case 'GREEN':  return const Color(0xFF00E676);
      case 'ORANGE': return const Color(0xFFFF8C2D);
      case 'PURPLE': return const Color(0xFF8C2DFF);
      case 'CYAN':   return const Color(0xFF00E5FF);
      default:       return const Color(0xFFFF2D78);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1320),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to logout?',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Logout',
                style: TextStyle(
                    color: _getColor(widget.trailColor),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (r) => false,
    );
  }

  // ── Formatters ──────────────────────────────────────────────
  String _fmtDuration(int secs) {
    if (secs <= 0) return '0:00';
    if (secs >= 3600) {
      final h = secs ~/ 3600;
      final m = (secs % 3600) ~/ 60;
      return '${h}h ${m}m';
    }
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) {
      return iso.substring(0, 10);
    }
  }

  String _fmtDist(dynamic meters) {
    final m = (meters ?? 0).toDouble();
    if (m < 1000) return '${m.toStringAsFixed(0)}m';
    return '${(m / 1000).toStringAsFixed(2)}km';
  }

  String _activityEmoji(String? type) {
    switch ((type ?? 'RUN').toUpperCase()) {
      case 'WALK':  return '🚶';
      case 'CYCLE': return '🚴';
      case 'HIKE':  return '🥾';
      default:      return '🏃';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor(widget.trailColor);

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: color, strokeWidth: 2))
            : RefreshIndicator(
          color: color,
          backgroundColor: const Color(0xFF0D1320),
          onRefresh: () async {
            await Future.wait([_loadStats(), _loadRuns()]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Top bar ──────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 40),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2),
                        children: [
                          const TextSpan(
                              text: 'stride',
                              style: TextStyle(color: Colors.white70)),
                          TextSpan(
                              text: 'UN',
                              style: TextStyle(
                                  color: color,
                                  shadows: [Shadow(color: color, blurRadius: 8)])),
                        ],
                      ),
                    ),
                    _circleBtn(
                        icon: Icons.logout_rounded,
                        color: color,
                        onTap: _logout),
                  ],
                ),

                const SizedBox(height: 32),

                // ── Avatar + name ────────────────────────
                Center(
                  child: Column(children: [
                    RepaintBoundary(
                      child: Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.15),
                          border: Border.all(color: color, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                                color: color.withOpacity(0.45),
                                blurRadius: 18,
                                spreadRadius: 2)
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget.username[0].toUpperCase(),
                            style: TextStyle(
                                color: color,
                                fontSize: 38,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.username.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.4)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: color, blurRadius: 4)])),
                        const SizedBox(width: 6),
                        Text('${widget.trailColor.toUpperCase()} TRAIL',
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1320),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Text(
                        'RANK #${_stats?['globalRank'] ?? '?'}',
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 32),

                // ── Stats grid ───────────────────────────
                _sectionLabel('STATS', color),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _statCard(
                      Icons.flag_rounded, 'ZONES PAINTED',
                      '${_stats?['totalZonesPainted'] ?? 0}', color)),
                  const SizedBox(width: 12),
                  Expanded(child: _statCard(
                      Icons.directions_run_rounded, 'TOTAL RUNS',
                      '${_stats?['totalRuns'] ?? 0}', color)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _statCard(
                      Icons.straighten_rounded, 'DISTANCE',
                      '${((_stats?['totalDistanceMeters'] ?? 0) / 1000).toStringAsFixed(1)}km',
                      color)),
                  const SizedBox(width: 12),
                  Expanded(child: _statCard(
                      Icons.map_rounded, 'ACTIVE ZONES',
                      '${_stats?['activeZonesOwned'] ?? 0}', color)),
                ]),

                const SizedBox(height: 28),

                // ── Run history ──────────────────────────
                _sectionLabel('RUN HISTORY', color),
                const SizedBox(height: 12),

                if (_runsLoading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(
                          color: color, strokeWidth: 2),
                    ),
                  )
                else if (_runs.isEmpty)
                  _emptyRuns(color)
                else
                  ..._runs.map((run) => _runCard(run, color)).toList(),

                const SizedBox(height: 28),

                // ── Trail color ──────────────────────────
                _sectionLabel('TRAIL COLOR', color),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1320),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withOpacity(0.25)),
                    boxShadow: [
                      BoxShadow(
                          color: color.withOpacity(0.06), blurRadius: 16)
                    ],
                  ),
                  child: Row(children: [
                    RepaintBoundary(
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: color.withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 1)
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.trailColor.toUpperCase(),
                          style: TextStyle(
                              color: color,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                      const SizedBox(height: 2),
                      const Text('Your zone color on the map',
                          style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ]),
                    const Spacer(),
                    Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: color, blurRadius: 4)])),
                  ]),
                ),

                const SizedBox(height: 16),

                if (_stats?['memberSince'] != null) ...[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1320),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today_outlined,
                          color: color.withOpacity(0.7), size: 18),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('MEMBER SINCE',
                            style: TextStyle(
                                color: color.withOpacity(0.5),
                                fontSize: 10,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          _fmtDate(_stats!['memberSince'].toString()),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                        ),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Leaderboard button ───────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            LeaderboardScreen(username: widget.username),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color.withOpacity(0.12),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: color.withOpacity(0.35)),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.emoji_events_rounded,
                            color: color, size: 20),
                        const SizedBox(width: 10),
                        Text('LEADERBOARD',
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Run card ─────────────────────────────────────────────────
  Widget _runCard(Map<String, dynamic> run, Color color) {
    final dist     = _fmtDist(run['distanceMeters']);
    final duration = _fmtDuration((run['durationSeconds'] ?? 0) as int);
    final zones    = run['zonesPainted'] ?? 0;
    final date     = _fmtDate(run['startedAt']?.toString());
    final type     = run['activityType'] ?? 'RUN';
    final emoji    = _activityEmoji(type);

    // Pace
    String pace = '--:--';
    final distM = (run['distanceMeters'] ?? 0).toDouble();
    final secs  = (run['durationSeconds'] ?? 0) as int;
    if (distM > 10 && secs > 0) {
      final paceS = (secs / (distM / 1000)).round();
      pace = '${(paceS ~/ 60).toString().padLeft(2, '0')}:${(paceS % 60).toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1320),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(children: [
        // Top row — activity + date
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              type.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5),
            ),
            Text(date,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
          const Spacer(),
          // Distance — big number on right
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(dist,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const Text('DISTANCE',
                style: TextStyle(
                    color: Colors.white38, fontSize: 8, letterSpacing: 1.5)),
          ]),
        ]),

        const SizedBox(height: 12),
        const Divider(height: 1, color: Color(0xFF1A2535)),
        const SizedBox(height: 12),

        // Bottom row — time, pace, zones
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _miniStat(Icons.timer_rounded, duration, 'TIME', color),
            _miniDivider(),
            _miniStat(Icons.speed_rounded, '$pace /km', 'PACE', color),
            _miniDivider(),
            _miniStat(Icons.flag_rounded, '$zones', 'ZONES', color),
          ],
        ),
      ]),
    );
  }

  Widget _miniStat(IconData icon, String val, String label, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color.withOpacity(0.6), size: 14),
        const SizedBox(height: 4),
        Text(val,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 8, letterSpacing: 1.2)),
      ]);

  Widget _miniDivider() =>
      Container(width: 1, height: 32, color: Colors.white10);

  Widget _emptyRuns(Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1320),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(children: [
      Icon(Icons.directions_run_rounded,
          color: color.withOpacity(0.3), size: 32),
      const SizedBox(height: 12),
      const Text('NO RUNS YET',
          style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      const Text('Start your first run to see history here.',
          style: TextStyle(color: Colors.white24, fontSize: 11),
          textAlign: TextAlign.center),
    ]),
  );

  // ── Helpers ──────────────────────────────────────────────────
  Widget _sectionLabel(String label, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              color: color.withOpacity(0.85),
              fontSize: 11,
              letterSpacing: 3,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Container(
        width: 22, height: 2,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)],
        ),
      ),
    ]);
  }

  Widget _statCard(IconData iconData, String label,
      String value, Color color) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1320),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.04), blurRadius: 10),
        ],
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(iconData, color: color, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.1)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 8,
                      letterSpacing: 1.2,
                      height: 1.2),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, color: color.withOpacity(0.9), size: 18),
      ),
    );
  }
}