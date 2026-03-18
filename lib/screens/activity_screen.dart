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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080c14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              const SizedBox(height: 20),

              // Header
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2D78).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.username[0].toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFFF2D78),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Hey, ${widget.username}!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      )),
                  const Text('Ready to paint the city?',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ]),
              ]),

              const SizedBox(height: 48),

              const Text('SELECT ACTIVITY',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  )),

              const SizedBox(height: 16),

              // Activity cards
              Expanded(
                child: ListView.separated(
                  itemCount: _activities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final activity = _activities[index];
                    final isSelected = _selected == activity['id'];
                    final color = activity['color'] as Color;

                    return GestureDetector(
                      onTap: () => setState(() => _selected = activity['id']),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.12)
                              : const Color(0xFF0d1320),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? color.withValues(alpha: 0.8)
                                : Colors.white.withValues(alpha: 0.06),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [

                          // Emoji circle
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(activity['emoji'],
                                  style: const TextStyle(fontSize: 26)),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Label + desc
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(activity['label'],
                                  style: TextStyle(
                                    color: isSelected ? color : Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  )),
                              const SizedBox(height: 4),
                              Text(activity['desc'],
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 13,
                                  )),
                            ],
                          )),

                          // Selected indicator
                          if (isSelected)
                            Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check,
                                  color: Colors.white, size: 14),
                            )
                          else
                            Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white12, width: 1.5),
                              ),
                            ),

                        ]),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Start button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapScreen(
                          username: widget.username,
                          trailColor: widget.trailColor,
                          activity: _selected,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _activities.firstWhere(
                            (a) => a['id'] == _selected)['color'],
                    padding: const EdgeInsets.symmetric(vertical: 20),
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
                        'START ${_selected}',
                        style: const TextStyle(
                          fontSize: 17,
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