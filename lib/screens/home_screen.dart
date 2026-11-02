import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  final String trailColor;

  const HomeScreen({
    super.key,
    required this.username,
    required this.trailColor,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _runs = [];
  bool _runsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRuns();
  }

  Future<void> _loadRuns() async {
    try {
      final runs = await ApiService.getRunHistory(widget.username, limit: 5);
      if (mounted) setState(() { _runs = runs; _runsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _runsLoading = false);
    }
  }

  Color get _accent => _getThemeColor(widget.trailColor);

  Color _getThemeColor(String colorStr) {
    switch (colorStr.toUpperCase()) {
      case 'PINK':   return const Color(0xFFFF2D78);
      case 'BLUE':   return const Color(0xFF4A72FF);
      case 'GREEN':  return const Color(0xFF00E676);
      case 'ORANGE': return const Color(0xFFFF8C2D);
      case 'CYAN':   return const Color(0xFF00E5FF);
      case 'PURPLE': return const Color(0xFF8C2DFF);
      default:       return const Color(0xFFFF2D78);
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
        return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (dt.day == yesterday.day && dt.month == yesterday.month) {
        return 'Yesterday';
      }
      return '${dt.day} ${months[dt.month]}';
    } catch (_) {
      return '';
    }
  }

  String _fmtDist(dynamic meters) {
    final m = (meters ?? 0).toDouble();
    if (m < 1000) return '${m.toStringAsFixed(0)}m';
    return '${(m / 1000).toStringAsFixed(2)}km';
  }

  String _fmtDuration(int secs) {
    if (secs <= 0) return '0:00';
    if (secs >= 3600) {
      return '${secs ~/ 3600}h ${((secs % 3600) ~/ 60)}m';
    }
    return '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
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
    final accent = _accent;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1017),
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          backgroundColor: const Color(0xFF0D1320),
          onRefresh: _loadRuns,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Player HUD ─────────────────────────────────
                _buildPlayerHUD(accent),
                const SizedBox(height: 28),

                // ── Missions ───────────────────────────────────
                _SectionHeader(label: 'ACTIVE MISSIONS', accent: accent),
                const SizedBox(height: 14),
                _buildMissionCard(
                  icon: Icons.location_on_rounded,
                  title: 'Indore Explorer',
                  desc: 'Paint 10 new zones today.',
                  reward: '+500 XP',
                  progress: 0.3,
                  themeColor: accent,
                ),
                const SizedBox(height: 12),
                _buildMissionCard(
                  icon: Icons.bolt_rounded,
                  title: 'Speed Demon',
                  desc: 'Maintain a pace under 5:30/km for 3km.',
                  reward: '+300 XP',
                  progress: 0.0,
                  themeColor: const Color(0xFF00E676),
                ),

                const SizedBox(height: 32),

                // ── Turf War Feed ──────────────────────────────
                _SectionHeader(label: 'TURF WAR FEED', accent: accent),
                const SizedBox(height: 14),

                if (_runsLoading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: CircularProgressIndicator(
                          color: accent, strokeWidth: 2),
                    ),
                  )
                else if (_runs.isEmpty)
                  _buildEmptyFeed(accent)
                else ...[
                    ..._runs.map((run) => _buildRunFeedCard(run, accent)).toList(),
                    const SizedBox(height: 8),
                    // "See all" hint
                    Center(
                      child: Text(
                        'Pull down to refresh · See full history in Profile',
                        style: TextStyle(
                            color: accent.withOpacity(0.3),
                            fontSize: 10,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ],

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Run feed card ────────────────────────────────────────────
  Widget _buildRunFeedCard(Map<String, dynamic> run, Color accent) {
    final type     = run['activityType'] ?? 'RUN';
    final emoji    = _activityEmoji(type);
    final dist     = _fmtDist(run['distanceMeters']);
    final duration = _fmtDuration((run['durationSeconds'] ?? 0) as int);
    final zones    = run['zonesPainted'] ?? 0;
    final date     = _fmtDate(run['startedAt']?.toString());

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
        color: const Color(0xFF161A23),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Column(children: [
        // Header row
        Row(children: [
          // Activity icon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          // Username + date
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              widget.username.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1),
            ),
            Row(children: [
              Text(
                type.toUpperCase(),
                style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1),
              ),
              const Text(' · ', style: TextStyle(color: Colors.white24)),
              Text(date,
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ]),
          ]),
          const Spacer(),
          // Distance
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(dist,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const Text('DIST',
                style: TextStyle(
                    color: Colors.white38, fontSize: 8, letterSpacing: 1.5)),
          ]),
        ]),

        const SizedBox(height: 12),

        // Stats row
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _feedStat('⏱', duration, 'TIME'),
              Container(width: 1, height: 24, color: Colors.white10),
              _feedStat('💨', '$pace /km', 'PACE'),
              Container(width: 1, height: 24, color: Colors.white10),
              _feedStat('🎯', '$zones', 'ZONES'),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _feedStat(String emoji, String val, String label) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 3),
        Text(val,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 8, letterSpacing: 1)),
      ]);

  // ── Player HUD ───────────────────────────────────────────────
  Widget _buildPlayerHUD(Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161A23),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.06), blurRadius: 16),
        ],
      ),
      child: Row(children: [
        RepaintBoundary(
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
              boxShadow: [
                BoxShadow(
                    color: accent.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 0)
              ],
            ),
            child: Center(
              child: Text(
                widget.username.isNotEmpty
                    ? widget.username[0].toUpperCase()
                    : 'S',
                style: TextStyle(
                    color: accent,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              widget.username.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: accent, blurRadius: 6)])),
              const SizedBox(width: 6),
              Text('CLAIM YOUR WORLD',
                  style: TextStyle(
                      color: accent.withOpacity(0.8),
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withOpacity(0.2)),
          ),
          child: Icon(Icons.notifications_none_rounded,
              color: accent.withOpacity(0.8), size: 20),
        ),
      ]),
    );
  }

  // ── Mission card ─────────────────────────────────────────────
  Widget _buildMissionCard({
    required IconData icon,
    required String title,
    required String desc,
    required String reward,
    required double progress,
    required Color themeColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161A23),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: themeColor.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(color: themeColor.withOpacity(0.04), blurRadius: 10),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                      color: themeColor,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: themeColor, blurRadius: 6)])),
              const SizedBox(width: 8),
              Text(title.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: themeColor.withOpacity(0.4)),
              ),
              child: Text(reward,
                  style: TextStyle(
                      color: themeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(desc,
            style: const TextStyle(
                color: Colors.white54, fontSize: 12, height: 1.5)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation(themeColor),
            minHeight: 3,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 38,
          child: OutlinedButton(
            onPressed: () => HapticFeedback.lightImpact(),
            style: OutlinedButton.styleFrom(
              backgroundColor: themeColor.withOpacity(0.1),
              side: BorderSide(color: themeColor.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            child: Text('START MISSION',
                style: TextStyle(
                    color: themeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
          ),
        ),
      ]),
    );
  }

  // ── Empty feed ───────────────────────────────────────────────
  Widget _buildEmptyFeed(Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF161A23),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.1)),
      ),
      child: Column(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(color: accent.withOpacity(0.2)),
          ),
          child: Icon(Icons.map_outlined,
              color: accent.withOpacity(0.5), size: 26),
        ),
        const SizedBox(height: 14),
        const Text('NO ACTIVITY YET',
            style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Go for a run to start claiming territory.',
            style: TextStyle(color: Colors.white24, fontSize: 11),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_arrow_rounded, color: accent, size: 16),
            const SizedBox(width: 6),
            Text('START YOUR FIRST RUN',
                style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
          ]),
        ),
      ]),
    );
  }
}

// ── Section header ────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String label;
  final Color accent;
  const _SectionHeader({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              color: accent.withOpacity(0.9),
              fontSize: 11,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Container(
        width: 24, height: 2,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(color: accent.withOpacity(0.6), blurRadius: 6)
          ],
        ),
      ),
    ]);
  }
}