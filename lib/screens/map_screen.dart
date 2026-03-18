import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import 'dart:async';
import 'profile_screen.dart';

class MapScreen extends StatefulWidget {
  final String username;
  final String trailColor;
  final String activity;
  const MapScreen({super.key, required this.username, required this.trailColor, this.activity = 'RUN'});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  List<dynamic> _zones = [];
  List<LatLng> _trail = [];
  bool _isRunning = false;
  int _zonesPainted = 0;
  double _distanceMeters = 0;
  int _seconds = 0;
  Timer? _gpsTimer;
  Timer? _zoneTimer;
  Timer? _clockTimer;
  Position? _currentPosition;
  bool _showZoneCapture = false;

  final LatLng _indore = const LatLng(22.7196, 75.8577);

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _loadZones();
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _zoneTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    await Geolocator.requestPermission();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() { _currentPosition = position; });
      _mapController.move(LatLng(position.latitude, position.longitude), 16);
    } catch (e) {}
  }

  Future<void> _loadZones() async {
    try {
      final center = _currentPosition != null
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : _indore;
      final zones = await ApiService.getViewport(
        center.latitude - 0.05,
        center.latitude + 0.05,
        center.longitude - 0.05,
        center.longitude + 0.05,
      );
      setState(() { _zones = zones; });
    } catch (e) {}
  }

  Future<void> _startRun() async {
    try {
      await ApiService.startRun();
      setState(() {
        _isRunning = true;
        _zonesPainted = 0;
        _seconds = 0;
        _trail.clear();
      });
      _gpsTimer = Timer.periodic(const Duration(seconds: 5), (_) => _sendGpsUpdate());
      _zoneTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadZones());
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() { _seconds++; });
      });
    } catch (e) {}
  }

  Future<void> _sendGpsUpdate() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _trail.add(LatLng(position.latitude, position.longitude));
      });
      _mapController.move(LatLng(position.latitude, position.longitude), 16);
      final result = await ApiService.sendGpsUpdate(
          position.latitude, position.longitude, position.speed * 3.6);
      if (result['zonePainted'] == true) {
        setState(() {
          _zonesPainted++;
          _showZoneCapture = true;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() { _showZoneCapture = false; });
        });
      }
    } catch (e) {}
  }

  Future<void> _stopRun() async {
    _gpsTimer?.cancel();
    _zoneTimer?.cancel();
    _clockTimer?.cancel();
    try {
      final result = await ApiService.stopRun();
      setState(() {
        _isRunning = false;
        _distanceMeters = (result['distanceMeters'] ?? 0).toDouble();
      });
      _showRunSummary();
    } catch (e) {
      setState(() { _isRunning = false; });
    }
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showRunSummary() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13151f),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          const Text('RUN COMPLETE!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                  color: Color(0xFFFF2D78), letterSpacing: 4)),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _summaryBox('ZONES', '$_zonesPainted', '🎯'),
            _summaryBox('DISTANCE',
                '${(_distanceMeters / 1000).toStringAsFixed(2)}km', '📍'),
            _summaryBox('TIME', _formatTime(_seconds), '⏱'),
          ]),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF2D78),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32))),
                child: const Text('AWESOME! 🔥',
                    style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.bold, color: Colors.white)),
              )),
        ]),
      ),
    );
  }

  Widget _summaryBox(String label, String value, String emoji) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 24)),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontSize: 28,
          fontWeight: FontWeight.w900, color: Colors.white)),
      Text(label, style: const TextStyle(color: Colors.white38,
          letterSpacing: 2, fontSize: 10)),
    ]);
  }

  Color _getZoneColor(String? color) {
    switch (color) {
      case 'PINK': return const Color(0xFFFF2D78);
      case 'BLUE': return const Color(0xFF2D8BFF);
      case 'GREEN': return const Color(0xFF2DFF78);
      case 'ORANGE': return const Color(0xFFFF8C2D);
      case 'PURPLE': return const Color(0xFF8C2DFF);
      case 'RED': return const Color(0xFFFF2D2D);
      default: return Colors.white24;
    }
  }

  List<Polygon> _buildPolygons() {
    return _zones.map((zone) {
      final color = _getZoneColor(zone['factionColor']);
      final isOwn = zone['ownerUsername'] == widget.username;
      return Polygon(
        points: [
          LatLng(zone['minLat'], zone['minLng']),
          LatLng(zone['maxLat'], zone['minLng']),
          LatLng(zone['maxLat'], zone['maxLng']),
          LatLng(zone['minLat'], zone['maxLng']),
        ],
        color: color.withValues(alpha: isOwn ? 0.45 : 0.25),
        borderColor: color.withValues(alpha: isOwn ? 1.0 : 0.6),
        borderStrokeWidth: isOwn ? 2.0 : 1.0,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : _indore;

    return Scaffold(
      backgroundColor: const Color(0xFF080c14),
      body: Stack(children: [

        // MAP
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: center, initialZoom: 16),
          children: [
            TileLayer(
              urlTemplate:
              'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
            ),
            PolygonLayer(polygons: _buildPolygons()),
            if (_trail.length > 1)
              PolylineLayer(polylines: [
                Polyline(points: _trail, strokeWidth: 3,
                    color: const Color(0xFFFF2D78)),
              ]),
            if (_currentPosition != null)
              MarkerLayer(markers: [
                Marker(
                  point: center,
                  width: 24, height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2D78),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                  ),
                ),
              ]),
          ],
        ),

        // TOP BAR
        Positioned(
          top: 52, left: 16, right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF080c14).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: const Color(0xFFFF2D78).withValues(alpha: 0.2),
                  width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [

                // LEFT — username only
                Text(widget.username.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        fontSize: 13)),

                // CENTER — live indicator
                if (_isRunning)
                  Row(children: [
                    Container(width: 7, height: 7,
                        decoration: const BoxDecoration(
                            color: Color(0xFFFF2D78),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('LIVE  ${_formatTime(_seconds)}',
                        style: const TextStyle(
                            color: Color(0xFFFF2D78),
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ]),

                // RIGHT — zones + profile button
                Row(children: [
                  const Text('🎯 ', style: TextStyle(fontSize: 14)),
                  Text('$_zonesPainted',
                      style: const TextStyle(
                          color: Color(0xFFFF2D78),
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ProfileScreen(
                          username: widget.username,
                          trailColor: widget.trailColor,
                        ))),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2D78).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.username[0].toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFFFF2D78),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),

              ],
            ),
          ),
        ),

        // STATS BAR (only when running)
        if (_isRunning)
          Positioned(
            top: 124, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0d1320).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statPill('DIST',
                      '${(_distanceMeters / 1000).toStringAsFixed(2)}km'),
                  _divider(),
                  _statPill('ZONES', '$_zonesPainted'),
                  _divider(),
                  _statPill('TIME', _formatTime(_seconds)),
                ],
              ),
            ),
          ),

        // ZONE CAPTURE NOTIFICATION
        if (_showZoneCapture)
          Positioned(
            top: _isRunning ? 190 : 130,
            left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF2D78).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFFF2D78).withValues(alpha: 0.5)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('🎯', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 8),
                  Text('ZONE CAPTURED! +1',
                      style: TextStyle(
                          color: Color(0xFFFF2D78),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1)),
                ]),
              ),
            ),
          ),

        // RECENTER BUTTON
        Positioned(
          bottom: 120, right: 16,
          child: GestureDetector(
            onTap: () {
              if (_currentPosition != null) {
                _mapController.move(
                    LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude), 16);
              }
            },
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0d1320),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12, width: 1),
              ),
              child: const Icon(Icons.my_location,
                  color: Colors.white54, size: 20),
            ),
          ),
        ),

        // START/STOP BUTTON
        Positioned(
          bottom: 44, left: 24, right: 24,
          child: ElevatedButton(
            onPressed: _isRunning ? _stopRun : _startRun,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRunning
                  ? const Color(0xFFCC1144)
                  : const Color(0xFFFF2D78),
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32)),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_isRunning
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                    color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Text(
                  _isRunning ? 'STOP RUN' : 'START RUN',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ),

      ]),
    );
  }

  Widget _statPill(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(
          color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
    ]);
  }

  Widget _divider() {
    return Container(width: 1, height: 28, color: Colors.white12);
  }
}