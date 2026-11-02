import 'package:flutter/material.dart';
import 'map_screen.dart';

class ActivityScreen extends StatefulWidget {
  final String username;
  final String trailColor;
  const ActivityScreen({
    super.key,
    required this.username,
    required this.trailColor,
  });

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _selected = 'RUN';

  final List<Map<String, dynamic>> _activities = [
    {
      'id': 'RUN',
      'label': 'Run',
      'emoji': '🏃',
      'desc': 'Up to 30 km/h',
      'color': const Color(0xFFFF2D78),
    },
    {
      'id': 'WALK',
      'label': 'Walk',
      'emoji': '🚶',
      'desc': 'Up to 10 km/h',
      'color': const Color(0xFF2D8BFF),
    },
    {
      'id': 'CYCLE',
      'label': 'Cycle',
      'emoji': '🚴',
      'desc': 'Up to 50 km/h',
      'color': const Color(0xFF2DFF78),
    },
    {
      'id': 'HIKE',
      'label': 'Hike',
      'emoji': '🧗',
      'desc': 'Up to 8 km/h',
      'color': const Color(0xFFFF8C2D),
    },
  ];

  Color get _selectedColor => _activities
      .firstWhere((a) => a['id'] == _selected)['color'] as Color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080c14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Top bar with back button ─────────────────────
              Row(
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
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hey, ${widget.username}!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          )),
                      const Text('Ready to paint the city?',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 36),

              const Text('SELECT ACTIVITY',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  )),

              const SizedBox(height: 14),

              // ── Activity cards ───────────────────────────────
              Expanded(
                child: ListView.separated(
                  itemCount: _activities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final a        = _activities[index];
                    final isSel    = _selected == a['id'];
                    final color    = a['color'] as Color;

                    return GestureDetector(
                      onTap: () => setState(() => _selected = a['id']),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isSel
                              ? color.withOpacity(0.10)
                              : const Color(0xFF0d1320),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSel
                                ? color.withOpacity(0.8)
                                : Colors.white.withOpacity(0.06),
                            width: isSel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(a['emoji'],
                                  style:
                                  const TextStyle(fontSize: 24)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(a['label'],
                                    style: TextStyle(
                                      color: isSel
                                          ? color
                                          : Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    )),
                                const SizedBox(height: 3),
                                Text(a['desc'],
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    )),
                              ],
                            ),
                          ),
                          Container(
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSel ? color : Colors.transparent,
                              border: Border.all(
                                color: isSel
                                    ? color
                                    : Colors.white12,
                                width: 1.5,
                              ),
                            ),
                            child: isSel
                                ? const Icon(Icons.check,
                                color: Colors.white, size: 13)
                                : null,
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // ── Start button ─────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapScreen(
                          username:   widget.username,
                          trailColor: widget.trailColor,
                          activity:   _selected,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedColor,
                    padding:
                    const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32)),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _activities.firstWhere(
                                (a) => a['id'] == _selected)['emoji'],
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'START $_selected',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
                      ),
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
}