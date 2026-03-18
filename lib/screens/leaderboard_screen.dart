import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LeaderboardScreen extends StatefulWidget {
  final String username;
  const LeaderboardScreen({super.key, required this.username});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<dynamic> _leaderboard = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    try {
      final data = await ApiService.getLeaderboard();
      setState(() {
        _leaderboard = data;
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

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1: return const Color(0xFFFFD700);
      case 2: return const Color(0xFFC0C0C0);
      case 3: return const Color(0xFFCD7F32);
      default: return Colors.white38;
    }
  }

  String _getRankEmoji(int rank) {
    switch (rank) {
      case 1: return '🥇';
      case 2: return '🥈';
      case 3: return '🥉';
      default: return '#$rank';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080c14),
      body: SafeArea(
        child: Column(children: [

          // Top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
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
                const Expanded(
                  child: Center(
                    child: Text('LEADERBOARD',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                          fontSize: 13,
                        )),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() { _isLoading = true; });
                    _loadLeaderboard();
                  },
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0d1320),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Icon(Icons.refresh,
                        color: Colors.white54, size: 18),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Top 3 podium
          if (!_isLoading && _leaderboard.length >= 3)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 2nd place
                  _podiumCard(_leaderboard[1], 2, 80),
                  // 1st place
                  _podiumCard(_leaderboard[0], 1, 110),
                  // 3rd place
                  _podiumCard(_leaderboard[2], 3, 60),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Rest of leaderboard
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(
                color: Color(0xFFFF2D78)))
                : _leaderboard.isEmpty
                ? const Center(
                child: Text('No players yet!',
                    style: TextStyle(color: Colors.white38)))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _leaderboard.length > 3
                  ? _leaderboard.length - 3
                  : 0,
              itemBuilder: (context, index) {
                final entry = _leaderboard[index + 3];
                final rank = index + 4;
                final isMe = entry['username'] == widget.username;
                final color = _getTrailColor(entry['trailColor']);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isMe
                        ? color.withValues(alpha: 0.1)
                        : const Color(0xFF0d1320),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isMe
                          ? color.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(children: [
                    SizedBox(
                      width: 32,
                      child: Text('#$rank',
                          style: TextStyle(
                            color: _getRankColor(rank),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          )),
                    ),
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          entry['username'][0].toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry['username'],
                        style: TextStyle(
                          color: isMe ? color : Colors.white,
                          fontWeight: isMe
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Row(children: [
                      const Text('🎯 ',
                          style: TextStyle(fontSize: 12)),
                      Text('${entry['totalZonesPainted']}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          )),
                    ]),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _podiumCard(dynamic entry, int rank, double height) {
    final color = _getTrailColor(entry['trailColor']);
    final isMe = entry['username'] == widget.username;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Avatar
        Container(
          width: rank == 1 ? 64 : 52,
          height: rank == 1 ? 64 : 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: color,
              width: rank == 1 ? 2.5 : 1.5,
            ),
          ),
          child: Center(
            child: Text(
              entry['username'][0].toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: rank == 1 ? 24 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(entry['username'],
            style: TextStyle(
              color: isMe ? color : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            )),
        const SizedBox(height: 4),
        Text('${entry['totalZonesPainted']} zones',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
            )),
        const SizedBox(height: 8),
        // Podium block
        Container(
          width: rank == 1 ? 90 : 75,
          height: height,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8)),
            border: Border.all(
              color: color.withValues(alpha: 0.4),
            ),
          ),
          child: Center(
            child: Text(
              _getRankEmoji(rank),
              style: TextStyle(
                fontSize: rank == 1 ? 28 : 22,
              ),
            ),
          ),
        ),
      ],
    );
  }
}