import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:tracelet/tracelet.dart' as tl;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_service.dart';
import 'profile_screen.dart';
import '../services/share_service.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// ═══════════════════════════════════════════════════════════════
//  MOTION SAMPLE — for motion window logging only
// ═══════════════════════════════════════════════════════════════
class _MotionSample {
  final double lat;
  final double lng;
  final DateTime time;
  const _MotionSample({required this.lat, required this.lng, required this.time});
}

// ═══════════════════════════════════════════════════════════════
//  SIMPLE LAT/LNG PAIR — for smoothing buffer
// ═══════════════════════════════════════════════════════════════
class _LatLng {
  final double lat;
  final double lng;
  const _LatLng(this.lat, this.lng);
}

// ═══════════════════════════════════════════════════════════════
//  TIME-AWARE MAP STYLE
//
//  Mapbox Standard ships with 4 lighting presets (dawn, day, dusk,
//  night). Switching is instant via setStyleImportConfigProperty —
//  no style reload, no flicker, no need to redraw zones/route/dot.
//
//  We sync to local time of day and re-check every minute.
// ═══════════════════════════════════════════════════════════════
enum _StyleMode { auto, satellite }

class _StylePresets {
  /// Returns the Mapbox Standard lightPreset for the given local time.
  /// Cutoffs chosen as common-sense civil twilight / golden hour bands.
  static String forTime(DateTime t) {
    final h = t.hour + t.minute / 60.0;
    if (h >= 5.5  && h < 7.0)  return 'dawn';
    if (h >= 7.0  && h < 17.0) return 'day';
    if (h >= 17.0 && h < 19.5) return 'dusk';
    return 'night';
  }
}

// ═══════════════════════════════════════════════════════════════
//  RDP ALGORITHM — Ramer-Douglas-Peucker polyline simplification
//  Used post-run to clean up the recorded route (Strava approach)
// ═══════════════════════════════════════════════════════════════
class _RDP {
  /// Perpendicular distance from point P to line segment AB (in meters).
  static double _perpendicularDist(
      _LatLng p, _LatLng a, _LatLng b,
      ) {
    // Convert to approximate flat-earth meters
    const degToM = 111320.0;
    final px = (p.lng - a.lng) * degToM * math.cos(a.lat * math.pi / 180);
    final py = (p.lat - a.lat) * degToM;
    final ax = 0.0;
    final ay = 0.0;
    final bx = (b.lng - a.lng) * degToM * math.cos(a.lat * math.pi / 180);
    final by = (b.lat - a.lat) * degToM;

    final len2 = bx * bx + by * by;
    if (len2 == 0) {
      return math.sqrt(px * px + py * py);
    }
    final t = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / len2;
    final tc = t.clamp(0.0, 1.0);
    final projX = ax + tc * (bx - ax);
    final projY = ay + tc * (by - ay);
    final dx = px - projX;
    final dy = py - projY;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Recursively simplify points between indices [start] and [end].
  static void _rdpRecursive(
      List<_LatLng> points,
      int start,
      int end,
      double epsilon,
      List<bool> keep,
      ) {
    if (end <= start + 1) return;
    double maxDist = 0;
    int maxIdx = start;
    for (int i = start + 1; i < end; i++) {
      final d = _perpendicularDist(points[i], points[start], points[end]);
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }
    if (maxDist > epsilon) {
      keep[maxIdx] = true;
      _rdpRecursive(points, start, maxIdx, epsilon, keep);
      _rdpRecursive(points, maxIdx, end, epsilon, keep);
    }
  }

  /// Simplify a list of _LatLng points using RDP with [epsilon] in meters.
  /// Returns a new simplified list.
  static List<_LatLng> simplify(List<_LatLng> points, double epsilon) {
    if (points.length < 3) return List.from(points);
    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;
    _rdpRecursive(points, 0, points.length - 1, epsilon, keep);
    final result = <_LatLng>[];
    for (int i = 0; i < points.length; i++) {
      if (keep[i]) result.add(points[i]);
    }
    return result;
  }
}




// ═══════════════════════════════════════════════════════════════
//  MAP SCREEN
// ═══════════════════════════════════════════════════════════════
class MapScreen extends StatefulWidget {
  final String username;
  final String trailColor;
  final String activity;

  const MapScreen({
    super.key,
    required this.username,
    required this.trailColor,
    this.activity = 'RUN',
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  // ── Map ───────────────────────────────────────────────────────
  mapbox.MapboxMap?               _mapboxMap;
  mapbox.PointAnnotationManager?  _annotMgr;
  mapbox.PointAnnotation?         _locationDot;
  bool                            _routeSourceAdded = false;
  bool                            _dotCreating      = false;

  // ── GPS (Tracelet) ─────────────────────────────────────────
  tl.Location? _lastLocation;
  bool         _isMoving = false;
  bool         _hasMovedThisRun = false;
  // ── GPS tuning ─────────────────────────────────────────────
  static const double _kDistanceFilter  = 1.2;
  static const int    _kMaxAccuracy     = 30;
  static const        _kMaxImpliedSpeed = 60;
  static const double _kMinDotMove      = 3.0;

  // ── Live route smoothing ────────────────────────────────────
  static const int    _kSmoothWindow   = 7;
  static const double _kRouteGateM     = 10.0;
  static const double _kRouteMaxAcc    = 20.0;   // worse fixes are not drawn
  static const double _kSpikeTurnDeg   = 110.0;  // sharp U-turn over a short hop = GPS jitter
  static const double _kSpikeMaxLenM   = 25.0;
  final List<_LatLng> _smoothBuffer    = [];

  // ── RDP post-run simplification ────────────────────────────
  static const double _kRdpEpsilon     = 4.0;
  final List<_LatLng> _rawRoutePoints  = [];

  // ── GPS Batching ────────────────────────────────────────────
  final List<GpsBatchPoint> _gpsBatch         = [];
  static const int          _batchIntervalSecs = 30;
  Timer?                    _batchTimer;

  // ── Motion window (logging only) ───────────────────────────
  final List<_MotionSample> _motionWindow = [];
  static const int _kMotionWindowSecs = 20;

  // ── Activity state ──────────────────────────────────────────
  bool   _isRunning       = false;
  bool   _isPaused        = false;
  int    _zonesPainted    = 0;
  double _distanceMeters  = 0;
  int    _seconds         = 0;
  int    _activeSeconds   = 0;
  double _currentSpeedKmh = 0;
  double _currentAccuracy = 0;
  bool   _showZoneCapture = false;
  int    _zoneCaptureId   = 0;
  late   String _activity;

  // ── Map style state ─────────────────────────────────────────
  _StyleMode _styleMode     = _StyleMode.auto;
  String     _currentPreset = 'day';
  Timer?     _styleTimer;

  // ── Step counter ────────────────────────────────────────────
  StreamSubscription<StepCount>? _stepStream;
  int _stepCount     = 0;
  int _stepCountBase = -1;
  bool _sensorSteps  = false;   // false = no step sensor/permission: estimate from distance

  // ── Speed / calorie tracking ────────────────────────────────
  double _totalSpeedSum = 0;
  int    _speedReadings = 0;
  double get _avgSpeedKmh =>
      _speedReadings == 0 ? 0.0 : _totalSpeedSum / _speedReadings;

  // ── Dot cache ───────────────────────────────────────────────
  Uint8List? _cachedDotImage;

  // ── Splits ──────────────────────────────────────────────────
  final List<double> _splits   = [];
  double             _splitDist = 0;
  int                _splitSecs = 0;

  // ── Zones ───────────────────────────────────────────────────
  List<dynamic> _zones      = [];
  int           _totalZones = 0;
  int           _myZones    = 0;

  // ── Route (smoothed coords sent to Mapbox) ──────────────────
  final List<List<double>> _routeCoords = [];
  double? _lastRouteLat, _lastRouteLng;

  // ── Position ────────────────────────────────────────────────
  double? _lat, _lng, _displayLat, _displayLng;

  // ── Timers ──────────────────────────────────────────────────
  Timer? _clockTimer;
  Timer? _zoneTimer;

  // ── Animations ──────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _captureCtrl;
  late Animation<double>   _captureAnim;

  // ── Colors ──────────────────────────────────────────────────
  static const Map<String, String> _colorMap = {
    'PINK':   '#FF2D78',
    'BLUE':   '#2D8BFF',
    'GREEN':  '#2DFF78',
    'ORANGE': '#FF8C2D',
    'PURPLE': '#8C2DFF',
    'RED':    '#FF4D4D',
    'CYAN':   '#00E5FF',
    'YELLOW': '#FFEA00',
  };
  static const String _unknownZoneColor = '#4A6080';

  Color get _accent => _hex(_colorMap[widget.trailColor] ?? '#FF2D78');

  static const double _defLat = 22.7196;
  static const double _defLng = 75.8577;

  // ════════════════════════════════════════════════════════════
  //  LIFECYCLE
  // ════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activity = widget.activity;
    _currentPreset = _StylePresets.forTime(DateTime.now());
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _captureCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _captureAnim = CurvedAnimation(
        parent: _captureCtrl, curve: Curves.elasticOut);
    _initTracelet();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _styleTimer?.cancel();
    _stepStream?.cancel();
    _clockTimer?.cancel();
    _zoneTimer?.cancel();
    _batchTimer?.cancel();
    _pulseCtrl.dispose();
    _captureCtrl.dispose();
    tl.Tracelet.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed
        && _styleMode == _StyleMode.auto) {
      _applyAutoPreset();
    }
  }

  // ════════════════════════════════════════════════════════════
  //  TRACELET INIT
  // ════════════════════════════════════════════════════════════
  Future<void> _initTracelet() async {
    tl.Tracelet.onLocation(_onTraceletLocation);

    tl.Tracelet.onMotionChange((tl.Location location) {
      if (!mounted) return;
      final moving = location.isMoving;
      setState(() {
        _isMoving = moving;
        if (moving && _isRunning) _hasMovedThisRun = true;
      });
    });
    await tl.Tracelet.ready(tl.Config(
      geo: tl.GeoConfig(
        desiredAccuracy: tl.DesiredAccuracy.high,
        distanceFilter: _kDistanceFilter,
        filter: tl.LocationFilter(
          useKalmanFilter: true,
          trackingAccuracyThreshold: _kMaxAccuracy,
          maxImpliedSpeed: _kMaxImpliedSpeed,
        ),
      ),
      motion: tl.MotionConfig(
        stopTimeout: 2,
      ),
      app: tl.AppConfig(
        stopOnTerminate: false,
        startOnBoot: false,
        foregroundService: tl.ForegroundServiceConfig(
          enabled: true,
          notificationTitle: 'Strideun',
          notificationText: 'Ready to track your run…',
        ),
      ),
      logger: tl.LoggerConfig(
        logLevel: tl.LogLevel.warning,
      ),
    ));

    final status = await tl.Tracelet.requestLocationAuthorization();
    FirebaseCrashlytics.instance.log('Tracelet permission status: $status');

    await _getOnceLocation();
  }

  // ════════════════════════════════════════════════════════════
  //  ONE-SHOT LOCATION
  // ════════════════════════════════════════════════════════════
  Future<void> _getOnceLocation() async {
    try {
      final loc = await tl.Tracelet.getCurrentPosition(
        desiredAccuracy: tl.DesiredAccuracy.high,
        timeout: 15,
        persist: false,
      );
      if (!mounted) return;
      final lat = loc.coords.latitude;
      final lng = loc.coords.longitude;
      setState(() { _lat = lat; _lng = lng; });
      await _updateDot(lat, lng);
      await _flyTo(lat, lng, zoom: 16, pitch: 50);
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════
  //  CLOCK TIMER
  // ════════════════════════════════════════════════════════════
  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _seconds++;
        if (_isMoving && !_isPaused) {
          _activeSeconds++;
          _totalSpeedSum += _currentSpeedKmh;
          _speedReadings++;
          _splitSecs++;
          _splitDist += (_currentSpeedKmh * 1000 / 3600);
          if (_splitSecs >= 60) {
            _splits.add(_splitDist);
            _splitDist = 0;
            _splitSecs = 0;
          }
        }
      });
      if (_isRunning && !_isPaused && _seconds % 5 == 0) {
        _updateNotification(
          title: 'Strideun — $_activity $_activityEmoji',
          body: '${(_distanceMeters / 1000).toStringAsFixed(2)}km'
              ' · ${_fmt(_activeSeconds)} · $_pace/km'
              ' · 🎯$_zonesPainted · 👟$_stepCount',
        );
      }
    });
  }

  // ════════════════════════════════════════════════════════════
  //  CORE GPS HANDLER
  // ════════════════════════════════════════════════════════════
  void _onTraceletLocation(tl.Location loc) {
    if (!_isRunning || _isPaused) return;

    final double lat      = loc.coords.latitude;
    final double lng      = loc.coords.longitude;
    final double speedMs  = loc.coords.speed;
    final double rawKmh   = speedMs * 3.6;
    final double speedKmh = (_isMoving && rawKmh >= 1.5) ? rawKmh : 0.0;
    final double accuracy = loc.coords.accuracy;
    final DateTime now    = (loc.timestamp is DateTime)
        ? loc.timestamp as DateTime
        : DateTime.now();

    FirebaseCrashlytics.instance.log(
      'GPS: acc=${accuracy.toStringAsFixed(1)}m '
          'spd=${speedKmh.toStringAsFixed(1)}km/h moving=$_isMoving',
    );

    setState(() {
      _lat             = lat;
      _lng             = lng;
      _currentSpeedKmh = speedKmh;
      _currentAccuracy = accuracy;
    });

    if (_lastLocation != null && _isMoving) {
      final d = _haversine(
        _lastLocation!.coords.latitude,
        _lastLocation!.coords.longitude,
        lat, lng,
      );
      setState(() {
        _distanceMeters += d;
        if (!_sensorSteps) _stepCount = _estimatedSteps();
      });
    }

    _motionWindow.add(_MotionSample(lat: lat, lng: lng, time: now));
    _motionWindow.removeWhere(
            (s) => now.difference(s.time).inSeconds > _kMotionWindowSecs);
    if (_motionWindow.length >= 2) {
      final oldest = _motionWindow.first;
      final newest = _motionWindow.last;
      final netDisp = _haversine(
          oldest.lat, oldest.lng, newest.lat, newest.lng);
      FirebaseCrashlytics.instance.log(
        'Motion window: netDisp=${netDisp.toStringAsFixed(1)}m '
            'pts=${_motionWindow.length} moving=$_isMoving',
      );
    }

    _rawRoutePoints.add(_LatLng(lat, lng));

    if (_isMoving && accuracy <= _kRouteMaxAcc) {
      _smoothBuffer.add(_LatLng(lat, lng));
      if (_smoothBuffer.length > _kSmoothWindow) {
        _smoothBuffer.removeAt(0);
      }
      final sLat = _smoothBuffer.map((p) => p.lat).reduce((a, b) => a + b)
          / _smoothBuffer.length;
      final sLng = _smoothBuffer.map((p) => p.lng).reduce((a, b) => a + b)
          / _smoothBuffer.length;

      final bool addPoint;
      if (_lastRouteLat == null) {
        addPoint = true;
      } else {
        final d = _haversine(_lastRouteLat!, _lastRouteLng!, sLat, sLng);
        addPoint = d >= _kRouteGateM && !_isSpike(sLat, sLng, d);
      }

      if (addPoint) {
        _routeCoords.add([sLng, sLat]);
        _lastRouteLat = sLat;
        _lastRouteLng = sLng;
        _updateRouteLine();
      }
    }

    _gpsBatch.add(GpsBatchPoint(
        lat: lat, lng: lng, speedKmh: speedKmh, time: now));

    final bool moveDot;
    if (_displayLat == null || _displayLng == null) {
      moveDot = true;
    } else {
      moveDot = _haversine(
          _displayLat!, _displayLng!, lat, lng) >= _kMinDotMove;
    }
    if (moveDot) {
      _displayLat = lat;
      _displayLng = lng;
      _updateDot(lat, lng);
      if (_isMoving) {
        _flyTo(lat, lng,
            zoom: 17, pitch: 62, bearing: _calcBearing(), ms: 400);
      }
    }

    _lastLocation = loc;
  }

  // Average stride length per activity (m); cycling has no steps.
  int _estimatedSteps() {
    const stride = {'RUN': 1.0, 'WALK': 0.75, 'HIKE': 0.7};
    final s = stride[_activity];
    return s == null ? 0 : (_distanceMeters / s).round();
  }

  // ════════════════════════════════════════════════════════════
  //  NOTIFICATION
  // ════════════════════════════════════════════════════════════
  Future<void> _updateNotification({
    required String title,
    required String body,
  }) async {
    try {
      debugPrint('Notification: $title — $body');
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════
  //  ACTIVITY CONTROL
  // ════════════════════════════════════════════════════════════
  Future<void> _startRun() async {
    HapticFeedback.heavyImpact();
    try {
      await ApiService.startRun();
    } catch (e) {
      FirebaseCrashlytics.instance.log('startRun failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to start session — check connection'),
          backgroundColor: Color(0xFFCC1144),
        ));
      }
      setState(() => _isRunning = false);
      return;
    }


    setState(() {
      _isRunning       = true;
      _isPaused        = false;
      _zonesPainted    = 0;
      _distanceMeters  = 0;
      _seconds         = 0;
      _activeSeconds   = 0;
      _currentSpeedKmh = 0;
      _isMoving        = false;
      _hasMovedThisRun = false;
      _splits.clear();
      _splitDist       = 0;
      _splitSecs       = 0;
      _routeCoords.clear();
      _routeSourceAdded = false;
      _totalSpeedSum   = 0;
      _speedReadings   = 0;
      _stepCount       = 0;
      _stepCountBase   = -1;
    });

    _gpsBatch.clear();
    _rawRoutePoints.clear();
    _smoothBuffer.clear();
    _lastLocation      = null;
    _displayLat = _displayLng = null;
    _lastRouteLat = null;
    _lastRouteLng = null;
    _motionWindow.clear();

    _locationDot    = null;
    _dotCreating    = false;
    _cachedDotImage = null;
    try { await _annotMgr?.deleteAll(); } catch (_) {}

    _flyTo(_lat ?? _defLat, _lng ?? _defLng, zoom: 17, pitch: 62, ms: 800);

    await tl.Tracelet.start();

    _startClock();

    _zoneTimer = Timer.periodic(
        const Duration(seconds: 45), (_) => _loadZones());

    _batchTimer = Timer.periodic(
        const Duration(seconds: _batchIntervalSecs),
            (_) => _flushGpsBatch());

    _stepStream?.cancel();
    _sensorSteps = false;
    if (await Permission.activityRecognition.request().isGranted) {
      _stepStream = Pedometer.stepCountStream.listen((event) {
        if (!mounted) return;
        if (_stepCountBase < 0) _stepCountBase = event.steps;
        final s = event.steps - _stepCountBase;
        if (s > 0) _sensorSteps = true;
        if (_sensorSteps) setState(() => _stepCount = s);
      }, onError: (_) {});
    }

    _loadZones();
    _updateNotification(
      title: 'Strideun — $_activity in progress $_activityEmoji',
      body: 'Starting…',
    );
  }

  // ════════════════════════════════════════════════════════════
  //  FLUSH GPS BATCH
  // ════════════════════════════════════════════════════════════
  Future<void> _flushGpsBatch() async {
    if (!_isRunning || _gpsBatch.isEmpty) return;

    final toSend = List<GpsBatchPoint>.from(_gpsBatch);
    _gpsBatch.clear();

    FirebaseCrashlytics.instance.log(
      'Batch flush: ${toSend.length} pts, '
          'dist=${_distanceMeters.toStringAsFixed(0)}m, '
          'zones=$_zonesPainted, moving=$_isMoving',
    );

    try {
      final res = await ApiService.sendGpsBatch(toSend);
      FirebaseCrashlytics.instance.log('Batch response: ${jsonEncode(res)}');


      if (res['sessionExpired'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Session expired — please login again'),
            backgroundColor: Color(0xFFCC1144),
          ));
        }
        return;
      }

      final serverZones = (res['totalZonesPaintedThisRun'] as num?)?.toInt();
      if (serverZones != null && serverZones > _zonesPainted) {
        _onZoneCaptured(serverZones);
      } else if (res['zonePainted'] == true && serverZones == null) {
        _onZoneCaptured(_zonesPainted + 1);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
          e, stack, reason: 'Batch flush failed', fatal: false);
      _gpsBatch.insertAll(0, toSend);
    }
  }

  Future<void> _onZoneCaptured(int newTotal) async {
    final captureId = ++_zoneCaptureId;
    setState(() {
      _zonesPainted    = newTotal;
      _showZoneCapture = true;
    });
    _updateNotification(
      title: 'Strideun — Zone Captured! 🎯',
      body: '${(_distanceMeters / 1000).toStringAsFixed(2)}km'
          ' · ${_fmt(_activeSeconds)} · 🎯$_zonesPainted',
    );
    _captureCtrl.forward(from: 0);
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(seconds: 3));
    if (mounted && _zoneCaptureId == captureId) {
      setState(() => _showZoneCapture = false);
    }
  }

  // ════════════════════════════════════════════════════════════
  //  PAUSE / RESUME
  // ════════════════════════════════════════════════════════════
  Future<void> _togglePause() async {
    HapticFeedback.mediumImpact();
    setState(() => _isPaused = !_isPaused);
    if (_isPaused) {
      _clockTimer?.cancel();
      _batchTimer?.cancel();
      _motionWindow.clear();
      await _flushGpsBatch();
      _updateNotification(
        title: 'Strideun — Paused ⏸',
        body: '${(_distanceMeters / 1000).toStringAsFixed(2)}km'
            ' · ${_fmt(_activeSeconds)} · 🎯$_zonesPainted',
      );
    } else {
      _lastLocation = null;
      _displayLat = _displayLng = null;
      _lastRouteLat = null;
      _lastRouteLng = null;
      _smoothBuffer.clear();
      _motionWindow.clear();
      _gpsBatch.clear();
      _startClock();
      _batchTimer = Timer.periodic(
          const Duration(seconds: _batchIntervalSecs),
              (_) => _flushGpsBatch());
      _updateNotification(
        title: 'Strideun — $_activity resumed $_activityEmoji',
        body: '${(_distanceMeters / 1000).toStringAsFixed(2)}km'
            ' · ${_fmt(_activeSeconds)}',
      );
    }
  }

  // ════════════════════════════════════════════════════════════
  //  STOP RUN
  // ════════════════════════════════════════════════════════════
  Future<void> _stopRun() async {
    HapticFeedback.heavyImpact();
    _clockTimer?.cancel();
    _zoneTimer?.cancel();
    _batchTimer?.cancel();
    _stepStream?.cancel();

    await tl.Tracelet.stop();
    await _flushGpsBatch();
    _motionWindow.clear();
    _gpsBatch.clear();

    // simplify the smoothed line (not the raw GPS fixes, which zigzag)
    if (_routeCoords.length >= 3) {
      final smoothed = _routeCoords.map((c) => _LatLng(c[1], c[0])).toList();
      final simplified = _RDP.simplify(smoothed, _kRdpEpsilon);
      FirebaseCrashlytics.instance.log(
        'RDP: ${_rawRoutePoints.length} pts → ${simplified.length} pts '
            '(${(100 - simplified.length / _rawRoutePoints.length * 100).toStringAsFixed(0)}% reduction)',
      );
      _routeCoords
        ..clear()
        ..addAll(simplified.map((p) => [p.lng, p.lat]));
      _updateRouteLine();
    }

    double finalDist = _distanceMeters;
    try {
      final res = await ApiService.stopRun();
      final bd  = (res['distanceMeters'] ?? 0).toDouble();
      if (bd > finalDist) finalDist = bd;
    } catch (_) {}

    FirebaseCrashlytics.instance.log(
      'Run stopped: dist=${finalDist.toStringAsFixed(0)}m '
          'zones=$_zonesPainted secs=$_activeSeconds cal=$_calories',
    );

    setState(() {
      _isRunning      = false;
      _isPaused       = false;
      _distanceMeters = finalDist;
    });

    if (_routeCoords.length > 1) {
      await _flyTo(_lat ?? _defLat, _lng ?? _defLng,
          zoom: 14, pitch: 30, ms: 1200);
    }
    _showSummary();
  }

  // ════════════════════════════════════════════════════════════
  //  MAP HELPERS
  // ════════════════════════════════════════════════════════════
  Future<void> _flyTo(double lat, double lng, {
    double zoom = 16,
    double pitch = 50,
    double bearing = 0,
    int ms = 900,
  }) async {
    await _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center:  mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        zoom: zoom, pitch: pitch, bearing: bearing,
      ),
      mapbox.MapAnimationOptions(duration: ms),
    );
  }

  double _calcBearing() {
    if (_routeCoords.length < 2) return 0;
    final n = math.min(_routeCoords.length, 5);
    final a = _routeCoords[_routeCoords.length - n];
    final b = _routeCoords[_routeCoords.length - 1];
    return math.atan2(b[0] - a[0], b[1] - a[1]) * 180 / math.pi;
  }

  // ════════════════════════════════════════════════════════════
  //  LOCATION DOT
  // ════════════════════════════════════════════════════════════
  Future<void> _updateDot(double lat, double lng) async {
    if (_mapboxMap == null || _annotMgr == null || _dotCreating) return;
    _dotCreating = true;
    try {
      _cachedDotImage ??= await _buildDotImage();
      final opts = mapbox.PointAnnotationOptions(
        geometry:   mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        image:      _cachedDotImage!,
        iconSize:   1.0,
        iconAnchor: mapbox.IconAnchor.CENTER,
      );
      if (_locationDot == null) {
        try { await _annotMgr!.deleteAll(); } catch (_) {}
        _locationDot = await _annotMgr!.create(opts);
      } else {
        _locationDot!.geometry =
            mapbox.Point(coordinates: mapbox.Position(lng, lat));
        try {
          await _annotMgr!.update(_locationDot!);
        } catch (_) {
          _locationDot = null;
          try { await _annotMgr!.deleteAll(); } catch (_) {}
        }
      }
    } catch (_) {
      _locationDot = null;
    } finally {
      _dotCreating = false;
    }
  }

  Future<Uint8List> _buildDotImage() async {
    const sz = 64;
    final rec = ui.PictureRecorder();
    final c   = ui.Canvas(rec);
    final col = _accent;
    c.drawCircle(const ui.Offset(32, 32), 30,
        ui.Paint()..color = col.withValues(alpha: 0.15));
    c.drawCircle(const ui.Offset(32, 32), 21,
        ui.Paint()..color = col.withValues(alpha: 0.30));
    c.drawCircle(const ui.Offset(32, 32), 14,
        ui.Paint()..color = Colors.white);
    c.drawCircle(const ui.Offset(32, 32), 10,
        ui.Paint()..color = col);
    final pic   = rec.endRecording();
    final img   = await pic.toImage(sz, sz);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  // ════════════════════════════════════════════════════════════
  //  TIME-AWARE STYLE — APPLY METHODS
  // ════════════════════════════════════════════════════════════

  /// Cheap update — just changes the lightPreset config property.
  /// No style reload. Zones, route, and dot stay intact.
  Future<void> _applyAutoPreset() async {
    if (_mapboxMap == null) return;
    final preset = _StylePresets.forTime(DateTime.now());
    if (preset == _currentPreset && _styleMode == _StyleMode.auto) return;
    try {
      await _mapboxMap!.style.setStyleImportConfigProperty(
        'basemap',
        'lightPreset',
        preset,
      );
      if (mounted) setState(() => _currentPreset = preset);
      FirebaseCrashlytics.instance.log('Map preset → $preset');
    } catch (e) {
      FirebaseCrashlytics.instance.log('lightPreset failed: $e');
    }
  }

  /// Heavy switch — full style reload. Dots, zones, route get redrawn.
  Future<void> _applySatellite() async {
    if (_mapboxMap == null) return;
    HapticFeedback.lightImpact();
    final oldMgr = _annotMgr;
    setState(() {
      _styleMode        = _StyleMode.satellite;
      _routeSourceAdded = false;
      _locationDot      = null;
      _cachedDotImage   = null;
      _annotMgr         = null;
    });
    try { await oldMgr?.deleteAll(); } catch (_) {}
    await _mapboxMap!.loadStyleURI(mapbox.MapboxStyles.SATELLITE_STREETS);
    await Future.delayed(const Duration(milliseconds: 600));
    _annotMgr    = await _mapboxMap!.annotations.createPointAnnotationManager();
    _dotCreating = false;
    try { await _annotMgr!.deleteAll(); } catch (_) {}
    if (_zones.isNotEmpty)       _drawZones();
    if (_routeCoords.length > 1) _updateRouteLine();
    if (_lat != null && _lng != null) await _updateDot(_lat!, _lng!);
  }

  /// Switch back from satellite to time-aware mode.
  Future<void> _applyAutoMode() async {
    if (_mapboxMap == null) return;
    HapticFeedback.lightImpact();
    final oldMgr = _annotMgr;
    setState(() {
      _styleMode        = _StyleMode.auto;
      _routeSourceAdded = false;
      _locationDot      = null;
      _cachedDotImage   = null;
      _annotMgr         = null;
    });
    try { await oldMgr?.deleteAll(); } catch (_) {}
    await _mapboxMap!.loadStyleURI(mapbox.MapboxStyles.STANDARD);
    await Future.delayed(const Duration(milliseconds: 600));
    _annotMgr    = await _mapboxMap!.annotations.createPointAnnotationManager();
    _dotCreating = false;
    try { await _annotMgr!.deleteAll(); } catch (_) {}
    await _applyAutoPreset();
    try {
      await _mapboxMap!.style.addLayer(mapbox.FillExtrusionLayer(
        id: 'buildings-3d', sourceId: 'composite', sourceLayer: 'building',
        fillExtrusionOpacity: 0.55, fillExtrusionColor: 0xFF1a2035,
        fillExtrusionHeightExpression: ['get', 'height'],
        fillExtrusionBaseExpression:   ['get', 'min_height'],
      ));
    } catch (_) {}
    if (_zones.isNotEmpty)       _drawZones();
    if (_routeCoords.length > 1) _updateRouteLine();
    if (_lat != null && _lng != null) await _updateDot(_lat!, _lng!);
  }

  /// Icon shown on the AUTO chip — morphs with current preset.
  IconData _presetIcon(String preset) {
    switch (preset) {
      case 'dawn':  return Icons.wb_twilight_rounded;
      case 'day':   return Icons.wb_sunny_rounded;
      case 'dusk':  return Icons.brightness_4_rounded;
      case 'night': return Icons.nightlight_round;
      default:      return Icons.brightness_auto_rounded;
    }
  }

  // A new point that turns back sharply after a short hop is jitter, not a real turn.
  bool _isSpike(double lat, double lng, double hopM) {
    if (_routeCoords.length < 2 || hopM > _kSpikeMaxLenM) return false;
    final a = _routeCoords[_routeCoords.length - 2];
    final b = _routeCoords.last;
    final b1 = math.atan2(b[0] - a[0], b[1] - a[1]);
    final b2 = math.atan2(lng - b[0], lat - b[1]);
    var turn = ((b2 - b1) * 180 / math.pi).abs() % 360;
    if (turn > 180) turn = 360 - turn;
    return turn > _kSpikeTurnDeg;
  }

  // Chaikin corner cutting: rounds corners without overshooting (no loops).
  List<List<double>> _chaikin(List<List<double>> pts, {int rounds = 2}) {
    var cur = pts;
    for (int k = 0; k < rounds && cur.length >= 3; k++) {
      final out = <List<double>>[cur.first];
      for (int i = 0; i < cur.length - 1; i++) {
        final p = cur[i], q = cur[i + 1];
        out.add([0.75 * p[0] + 0.25 * q[0], 0.75 * p[1] + 0.25 * q[1]]);
        out.add([0.25 * p[0] + 0.75 * q[0], 0.25 * p[1] + 0.75 * q[1]]);
      }
      out.add(cur.last);
      cur = out;
    }
    return cur;
  }

  // ════════════════════════════════════════════════════════════
  //  ROUTE LINE
  // ════════════════════════════════════════════════════════════
  Future<void> _updateRouteLine() async {
    if (_mapboxMap == null || _routeCoords.length < 2) return;
    final curved = _routeCoords.length >= 3
        ? _chaikin(_routeCoords)
        : _routeCoords;
    final geojson = jsonEncode({
      'type': 'Feature',
      'geometry': {'type': 'LineString', 'coordinates': curved},
      'properties': {},
    });
    try {
      if (!_routeSourceAdded) {
        await _mapboxMap!.style.addSource(
            mapbox.GeoJsonSource(id: 'route-src', data: geojson));
        await _mapboxMap!.style.addLayer(mapbox.LineLayer(
          id: 'route-glow', sourceId: 'route-src',
          lineColor: _accent.value, lineWidth: 14.0, lineOpacity: 0.22,
          lineCap: mapbox.LineCap.ROUND, lineJoin: mapbox.LineJoin.ROUND,
        ));
        await _mapboxMap!.style.addLayer(mapbox.LineLayer(
          id: 'route-line', sourceId: 'route-src',
          lineColor: _accent.value, lineWidth: 5.5, lineOpacity: 0.95,
          lineCap: mapbox.LineCap.ROUND, lineJoin: mapbox.LineJoin.ROUND,
        ));
        _routeSourceAdded = true;
      } else {
        await _mapboxMap!.style
            .setStyleSourceProperty('route-src', 'data', geojson);
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════
  //  ZONES
  // ════════════════════════════════════════════════════════════
  Future<void> _loadZones() async {
    try {
      final lat   = _lat ?? _defLat;
      final lng   = _lng ?? _defLng;
      final zones = (await ApiService.getViewport(
          lat - 0.015, lat + 0.015, lng - 0.015, lng + 0.015))
          .where((z) => '${z['gridReference'] ?? ''}'.startsWith('h'))
          .toList();
      final my = zones
          .where((z) => z['ownerUsername'] == widget.username)
          .length;
      setState(() {
        _zones      = zones;
        _totalZones = zones.length;
        _myZones    = my;
      });
      _drawZones();
    } catch (_) {}
  }

  Future<void> _drawZones() async {
    if (_mapboxMap == null || _zones.isEmpty) return;
    try {
      for (final id in ['zones-fill', 'zones-outline']) {
        try { await _mapboxMap!.style.removeStyleLayer(id); } catch (_) {}
      }
      try { await _mapboxMap!.style.removeStyleSource('zones-src'); } catch (_) {}

      final features = _zones.map((z) {
        final isOwn  = z['ownerUsername'] == widget.username;
        final color  = isOwn
            ? (_colorMap[widget.trailColor] ?? '#FF2D78')
            : (_colorMap[z['factionColor']] ?? _unknownZoneColor);
        final raw    = (z['coordinates'] as List<dynamic>?) ?? [];
        if (raw.isEmpty) return null;
        final ring   = raw.map((pt) {
          final p = pt as List<dynamic>;
          return [p[0] as double, p[1] as double];
        }).toList();
        return {
          'type': 'Feature',
          'properties': {
            'color':   color,
            'fill_op': isOwn ? 0.45 : 0.15,
            'line_op': isOwn ? 0.95 : 0.55,
            'line_w':  isOwn ? 2.5  : 1.0,
          },
          'geometry': {'type': 'Polygon', 'coordinates': [ring]},
        };
      }).whereType<Map>().toList();

      await _mapboxMap!.style.addSource(mapbox.GeoJsonSource(
        id:   'zones-src',
        data: jsonEncode({'type': 'FeatureCollection', 'features': features}),
      ));
      await _mapboxMap!.style.addLayer(mapbox.FillLayer(
        id: 'zones-fill', sourceId: 'zones-src',
        fillColorExpression:   ['get', 'color'],
        fillOpacityExpression: ['get', 'fill_op'],
      ));
      await _mapboxMap!.style.addLayer(mapbox.LineLayer(
        id: 'zones-outline', sourceId: 'zones-src',
        lineColorExpression:   ['get', 'color'],
        lineOpacityExpression: ['get', 'line_op'],
        lineWidthExpression:   ['get', 'line_w'],
        lineCap: mapbox.LineCap.ROUND, lineJoin: mapbox.LineJoin.ROUND,
      ));
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════
  //  STAT HELPERS
  // ════════════════════════════════════════════════════════════
  Color _hex(String h) {
    try {
      final val = int.parse(h.replaceAll('#', ''), radix: 16);
      return Color.fromARGB(
          0xFF, (val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF);
    } catch (_) { return const Color(0xFFFF2D78); }
  }

  String _fmt(int s) {
    if (s >= 3600) {
      return '${(s ~/ 3600).toString().padLeft(2, '0')}'
          ':${((s % 3600) ~/ 60).toString().padLeft(2, '0')}'
          ':${(s % 60).toString().padLeft(2, '0')}';
    }
    return '${(s ~/ 60).toString().padLeft(2, '0')}'
        ':${(s % 60).toString().padLeft(2, '0')}';
  }

  String get _pace {
    if (_distanceMeters < 10 || _activeSeconds < 1) return '--:--';
    final p = _activeSeconds / (_distanceMeters / 1000);
    return '${(p ~/ 60).toString().padLeft(2, '0')}'
        ':${(p % 60).round().toString().padLeft(2, '0')}';
  }

  int get _calories {
    if (_activeSeconds < 1) return 0;
    final speed = _avgSpeedKmh;
    double met;
    switch (widget.activity) {
      case 'WALK':
        met = speed < 3.2 ? 2.5 : speed < 4.8 ? 3.5 : speed < 6.4 ? 4.3 : 5.0;
        break;
      case 'RUN':
        met = speed < 8.0 ? 8.3 : speed < 10.0 ? 9.8 : speed < 12.0 ? 11.0
            : speed < 14.0 ? 12.3 : 14.5;
        break;
      case 'CYCLE':
        met = speed < 16.0 ? 6.0 : speed < 20.0 ? 8.0
            : speed < 25.0 ? 10.0 : 12.0;
        break;
      case 'HIKE':
        met = speed < 4.0 ? 5.3 : 6.0;
        break;
      default:
        met = 7.0;
    }
    return (met * 70.0 * (_activeSeconds / 3600.0)).round();
  }

  double get _avgPaceMinPerKm {
    if (_distanceMeters < 10 || _activeSeconds < 1) return 0;
    return (_activeSeconds / 60) / (_distanceMeters / 1000);
  }

  int get _xpEarned =>
      (_zonesPainted * 50) + (_distanceMeters / 100).round();

  String get _activityEmoji {
    switch (_activity) {
      case 'WALK':  return '🚶';
      case 'CYCLE': return '🚴';
      case 'HIKE':  return '🥾';
      default:      return '🏃';
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2)
        + math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180)
            * math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String get _gpsLabel {
    if (_currentAccuracy <= 5)  return 'GPS ●●●';
    if (_currentAccuracy <= 15) return 'GPS ●●○';
    return 'GPS ●○○';
  }

  Color get _gpsColor {
    if (_currentAccuracy <= 5)  return const Color(0xFF2DFF78);
    if (_currentAccuracy <= 15) return const Color(0xFFFFEA00);
    return const Color(0xFFFF4D4D);
  }

  double get _territoryPct =>
      _totalZones == 0 ? 0 : (_myZones / _totalZones).clamp(0.0, 1.0);
  bool get _isAutoPaused =>
      _isRunning && !_isPaused && !_isMoving && _hasMovedThisRun && _activeSeconds > 5;

  // ── Activity picker ────────────────────────────────────────
  void _showActivityPicker() {
    const activities = [
      {'name': 'RUN',   'emoji': '🏃', 'desc': 'Up to 30 km/h'},
      {'name': 'WALK',  'emoji': '🚶', 'desc': 'Up to 10 km/h'},
      {'name': 'CYCLE', 'emoji': '🚴', 'desc': 'Up to 50 km/h'},
      {'name': 'HIKE',  'emoji': '🥾', 'desc': 'Up to 8 km/h'},
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0d1120),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('SWITCH ACTIVITY',
              style: TextStyle(color: Colors.white54, fontSize: 11,
                  letterSpacing: 3, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ...activities.map((a) {
            final selected = a['name'] == _activity;
            return GestureDetector(
              onTap: () {
                setState(() => _activity = a['name']!);
                _updateNotification(
                  title: 'Strideun — ${a['name']} in progress',
                  body: '${(_distanceMeters / 1000).toStringAsFixed(2)}km'
                      ' · ${_fmt(_activeSeconds)}',
                );
                Navigator.pop(context);
                HapticFeedback.lightImpact();
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? _accent.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: selected
                          ? _accent.withValues(alpha: 0.4)
                          : Colors.white10),
                ),
                child: Row(children: [
                  Text(a['emoji']!, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a['name']!,
                          style: TextStyle(
                              color: selected ? _accent : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14, letterSpacing: 2)),
                      Text(a['desc']!,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10)),
                    ],
                  )),
                  if (selected)
                    Icon(Icons.check_circle_rounded,
                        color: _accent, size: 20),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

  // ── Manual preset picker (long-press AUTO chip) ─────────────
  void _showPresetPicker() {
    if (_styleMode != _StyleMode.auto) return;
    HapticFeedback.mediumImpact();
    const presets = [
      {'key': 'dawn',  'label': 'DAWN',  'desc': 'Sunrise'},
      {'key': 'day',   'label': 'DAY',   'desc': 'Morning · Afternoon'},
      {'key': 'dusk',  'label': 'DUSK',  'desc': 'Sunset · Evening'},
      {'key': 'night', 'label': 'NIGHT', 'desc': 'After dark'},
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0d1120),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('OVERRIDE LIGHTING',
              style: TextStyle(color: Colors.white54, fontSize: 11,
                  letterSpacing: 3, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Will revert to auto on next minute',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 16),
          ...presets.map((p) {
            final selected = p['key'] == _currentPreset;
            return GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                HapticFeedback.lightImpact();
                if (_mapboxMap == null) return;
                try {
                  await _mapboxMap!.style.setStyleImportConfigProperty(
                    'basemap', 'lightPreset', p['key']!,
                  );
                  if (mounted) setState(() => _currentPreset = p['key']!);
                } catch (_) {}
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? _accent.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: selected
                          ? _accent.withValues(alpha: 0.4)
                          : Colors.white10),
                ),
                child: Row(children: [
                  Icon(_presetIcon(p['key']!),
                      color: selected ? _accent : Colors.white60, size: 20),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['label']!,
                          style: TextStyle(
                              color: selected ? _accent : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14, letterSpacing: 2)),
                      Text(p['desc']!,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10)),
                    ],
                  )),
                  if (selected)
                    Icon(Icons.check_circle_rounded,
                        color: _accent, size: 20),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  RUN SUMMARY
  // ════════════════════════════════════════════════════════════
  void _showSummary() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0d1120),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).padding.bottom + 28),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('$_activityEmoji  $_activity COMPLETE',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900,
                    color: _accent, letterSpacing: 3)),
            const SizedBox(height: 4),
            Text(widget.username.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white38, letterSpacing: 3, fontSize: 11)),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(children: [
                Row(children: [
                  _sBox('ZONES', '$_zonesPainted', '🎯'),
                  _sDiv(),
                  _sBox('DISTANCE',
                      '${(_distanceMeters / 1000).toStringAsFixed(2)} km',
                      '📍'),
                ]),
                Divider(height: 1, color: Colors.white10),
                Row(children: [
                  _sBox('TIME', _fmt(_activeSeconds), '⏱'),
                  _sDiv(),
                  _sBox('PACE', '$_pace /km', '💨'),
                ]),
                Divider(height: 1, color: Colors.white10),
                Row(children: [
                  _sBox('AVG SPEED',
                      '${_avgSpeedKmh.toStringAsFixed(1)} km/h', '⚡'),
                  _sDiv(),
                  _sBox('CALORIES', '$_calories kcal', '🔥'),
                ]),
                Divider(height: 1, color: Colors.white10),
                Row(children: [
                  _sBox('STEPS', '$_stepCount', '👟'),
                  _sDiv(),
                  _sBox('TOTAL TIME', _fmt(_seconds), '🕐'),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEA00).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFFFEA00).withValues(alpha: 0.25)),
              ),
              child: Column(children: [
                Text('+$_xpEarned XP',
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFEA00))),
                const Text('EXPERIENCE EARNED',
                    style: TextStyle(color: Color(0xFFFFEA00),
                        fontSize: 10, letterSpacing: 3,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 12),
            if (_splits.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('PACE SPLITS',
                    style: TextStyle(
                        color: _accent.withValues(alpha: 0.8),
                        fontSize: 10, letterSpacing: 2,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              _PaceSplitGraph(splits: _splits, color: _accent),
              const SizedBox(height: 12),
            ],
            if (_totalZones > 0) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TERRITORY CONTROL',
                        style: TextStyle(color: Colors.white38,
                            fontSize: 10, letterSpacing: 2)),
                    Text('$_myZones / $_totalZones zones',
                        style: TextStyle(color: _accent, fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _territoryPct, minHeight: 8,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(_accent),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => ShareService.showShareSheet(
                  context: context,
                  data: RunShareData(
                    username:        widget.username,
                    activityType:    _activity,
                    distanceKm:      _distanceMeters / 1000,
                    durationSeconds: _activeSeconds,
                    zonesCaptured:   _zonesPainted,
                    avgPaceMinPerKm: _avgPaceMinPerKm,
                    calories:        _calories,
                    xpEarned:        _xpEarned,
                    trailColor:      _accent,
                  ),
                ),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('SHARE RUN',
                    style: TextStyle(fontSize: 14,
                        fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A2030),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                      side: BorderSide(
                          color: _accent.withValues(alpha: 0.35))),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32)),
                  elevation: 0,
                ),
                child: const Text('AWESOME! 🔥',
                    style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white, letterSpacing: 2)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sBox(String label, String val, String emoji) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 5),
        Text(val,
            style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w900, color: Colors.white),
            textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
            color: Colors.white38, letterSpacing: 1.5, fontSize: 9)),
      ]),
    ),
  );

  Widget _sDiv() => Container(width: 1, height: 70, color: Colors.white10);

  // ════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFF080c14),
      body: Stack(children: [

        // ── Mapbox ──────────────────────────────────────────────
        mapbox.MapWidget(
          key: const ValueKey('map'),
          styleUri: mapbox.MapboxStyles.STANDARD,
          onMapCreated: (map) async {
            _mapboxMap = map;
            await map.loadStyleURI(mapbox.MapboxStyles.STANDARD);

            // Apply correct preset BEFORE first paint — no lag.
            final preset = _StylePresets.forTime(DateTime.now());
            try {
              await map.style.setStyleImportConfigProperty(
                'basemap', 'lightPreset', preset,
              );
              if (mounted) setState(() => _currentPreset = preset);
            } catch (e) {
              FirebaseCrashlytics.instance.log('initial lightPreset: $e');
            }

            // Re-check every minute. Auto-update if mode is auto.
            _styleTimer?.cancel();
            _styleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
              if (_styleMode == _StyleMode.auto) _applyAutoPreset();
            });

            await map.setCamera(mapbox.CameraOptions(
              center: mapbox.Point(
                  coordinates: mapbox.Position(_defLng, _defLat)),
              zoom: 16, pitch: 50, bearing: 0,
            ));
            await map.scaleBar.updateSettings(
                mapbox.ScaleBarSettings(enabled: false));
            await map.compass.updateSettings(
                mapbox.CompassSettings(enabled: false));
            await map.logo.updateSettings(
                mapbox.LogoSettings(marginBottom: -100));
            await map.attribution.updateSettings(
                mapbox.AttributionSettings(marginBottom: -100));
            await map.location.updateSettings(
                mapbox.LocationComponentSettings(enabled: false));
            try {
              await map.style.addLayer(mapbox.FillExtrusionLayer(
                id: 'buildings-3d',
                sourceId: 'composite',
                sourceLayer: 'building',
                fillExtrusionOpacity: 0.55,
                fillExtrusionColor: 0xFF1a2035,
                fillExtrusionHeightExpression: ['get', 'height'],
                fillExtrusionBaseExpression:   ['get', 'min_height'],
              ));
            } catch (_) {}

            _locationDot = null;
            _dotCreating = false;
            _annotMgr =
            await map.annotations.createPointAnnotationManager();
            try { await _annotMgr!.deleteAll(); } catch (_) {}

            await _loadZones();
            await _getOnceLocation();
          },
        ),

        // ── Top bar ─────────────────────────────────────────────
        Positioned(
          top: top + 8, left: 16, right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF080c14).withValues(alpha: 0.93),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: _accent.withValues(alpha: 0.22)),
            ),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white54, size: 18),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isRunning ? _showActivityPicker : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$_activityEmoji $_activity',
                        style: TextStyle(color: _accent, fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5)),
                    if (_isRunning) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.swap_horiz_rounded,
                          color: _accent.withValues(alpha: 0.6),
                          size: 14),
                    ],
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              if (_currentAccuracy > 0)
                Text(_gpsLabel,
                    style: TextStyle(color: _gpsColor, fontSize: 9,
                        fontWeight: FontWeight.w700, letterSpacing: 1)),
              const Spacer(),
              if (_isAutoPaused) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEA00).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFFFEA00)
                            .withValues(alpha: 0.4)),
                  ),
                  child: const Text('AUTO PAUSED',
                      style: TextStyle(color: Color(0xFFFFEA00),
                          fontSize: 8, letterSpacing: 1,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
              ],
              if (_isRunning) ...[
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, child) => Opacity(
                    opacity: _isAutoPaused
                        ? 0.3
                        : (0.4 + _pulseCtrl.value * 0.6),
                    child: child,
                  ),
                  child: Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                        color: _isAutoPaused
                            ? const Color(0xFFFFEA00) : _accent,
                        shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 5),
                Text(_fmt(_activeSeconds),
                    style: TextStyle(
                        color: _isAutoPaused
                            ? const Color(0xFFFFEA00) : _accent,
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 10),
              ],
              Text('🎯 $_zonesPainted',
                  style: TextStyle(color: _accent,
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      username:   widget.username,
                      trailColor: widget.trailColor,
                    ),
                  ),
                ),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.5)),
                  ),
                  child: Center(child: Text(
                    widget.username[0].toUpperCase(),
                    style: TextStyle(color: _accent,
                        fontWeight: FontWeight.bold, fontSize: 13),
                  )),
                ),
              ),
            ]),
          ),
        ),

        // ── Stats bar ────────────────────────────────────────────
        if (_isRunning)
          Positioned(
            top: top + 72, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF0d1320).withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _isAutoPaused
                        ? const Color(0xFFFFEA00).withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('DIST',
                      '${(_distanceMeters / 1000).toStringAsFixed(2)}km',
                      Icons.straighten_rounded),
                  _vl(),
                  _stat('PACE', _pace, Icons.speed_rounded),
                  _vl(),
                  _stat('TIME', _fmt(_activeSeconds), Icons.timer_rounded),
                  _vl(),
                  _stat('KM/H',
                      _isMoving
                          ? _currentSpeedKmh.toStringAsFixed(1)
                          : '0.0',
                      Icons.bolt_rounded),
                  _stat('STEPS', '$_stepCount',
                      Icons.directions_walk_rounded),
                ],
              ),
            ),
          ),

        // ── Zone capture toast ────────────────────────────────────
        if (_showZoneCapture)
          Positioned(
            top: top + (_isRunning ? 138 : 74),
            left: 0, right: 0,
            child: Center(
              child: ScaleTransition(
                scale: _captureAnim,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.6),
                        width: 1.5),
                    boxShadow: [BoxShadow(
                        color: _accent.withValues(alpha: 0.3),
                        blurRadius: 16)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('🎯', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Text('ZONE CAPTURED! +1',
                        style: TextStyle(color: _accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13, letterSpacing: 1.5)),
                  ]),
                ),
              ),
            ),
          ),

        // ── Right rail (locate, zoom +/-) — style btn moved to bottom
        Positioned(
          right: 16, bottom: 220,
          child: Column(children: [
            _mapBtn(Icons.my_location_rounded, _getOnceLocation),
            const SizedBox(height: 8),
            _mapBtn(Icons.add_rounded, () async {
              final c = await _mapboxMap?.getCameraState();
              if (c != null) _mapboxMap?.flyTo(
                mapbox.CameraOptions(zoom: c.zoom + 1),
                mapbox.MapAnimationOptions(duration: 300),
              );
            }),
            const SizedBox(height: 8),
            _mapBtn(Icons.remove_rounded, () async {
              final c = await _mapboxMap?.getCameraState();
              if (c != null) _mapboxMap?.flyTo(
                mapbox.CameraOptions(zoom: c.zoom - 1),
                mapbox.MapAnimationOptions(duration: 300),
              );
            }),
          ]),
        ),

        // ── Territory bar ────────────────────────────────────────
        if (!_isRunning && _totalZones > 0)
          Positioned(
            bottom: 190, left: 24, right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('YOUR TERRITORY',
                        style: TextStyle(color: Colors.white54,
                            fontSize: 9, letterSpacing: 2)),
                    Text('$_myZones / $_totalZones',
                        style: TextStyle(color: _accent, fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _territoryPct, minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(_accent),
                  ),
                ),
              ],
            ),
          ),

        // ── BOTTOM MAP STYLE PICKER ──────────────────────────────
        // Two chips: AUTO (with current preset) and SAT.
        // Tap AUTO chip when in auto mode → opens manual override sheet.
        // Tap SAT chip when in auto mode → swaps to satellite.
        // Tap AUTO chip when in satellite mode → swaps back to auto.
        Positioned(
          bottom: 120, left: 24, right: 24,
          child: Row(children: [
            _stylePickerChip(
              label:    'AUTO',
              subtitle: _styleMode == _StyleMode.auto
                  ? _currentPreset.toUpperCase()
                  : 'TIME-AWARE',
              icon:     _presetIcon(_currentPreset),
              selected: _styleMode == _StyleMode.auto,
              onTap: () {
                if (_styleMode == _StyleMode.satellite) {
                  _applyAutoMode();
                } else {
                  _showPresetPicker();
                }
              },
              onLongPress: _styleMode == _StyleMode.auto
                  ? _showPresetPicker
                  : null,
            ),
            const SizedBox(width: 10),
            _stylePickerChip(
              label:    'SAT',
              subtitle: 'SATELLITE',
              icon:     Icons.satellite_alt_rounded,
              selected: _styleMode == _StyleMode.satellite,
              onTap: () {
                if (_styleMode == _StyleMode.auto) _applySatellite();
              },
            ),
          ]),
        ),

        // ── Bottom controls ──────────────────────────────────────
        Positioned(
          bottom: 44, left: 24, right: 24,
          child: Row(children: [
            if (_isRunning) ...[
              GestureDetector(
                onTap: _togglePause,
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0d1320),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.45),
                        width: 1.5),
                  ),
                  child: Icon(
                    _isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: _accent, size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: ElevatedButton(
                onPressed: _isRunning ? _stopRun : _startRun,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  _isRunning ? const Color(0xFFCC1144) : _accent,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRunning
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white, size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isRunning
                          ? (_isPaused ? 'STOP' : 'STOP $_activity')
                          : 'START $_activity',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold,
                          letterSpacing: 2, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ]),
        ),

      ]),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  UI HELPERS
  // ════════════════════════════════════════════════════════════
  Widget _stat(String label, String val, IconData icon) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white38, size: 12),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.bold, fontSize: 12)),
        Text(label, style: const TextStyle(
            color: Colors.white38, fontSize: 8, letterSpacing: 1.5)),
      ]);

  Widget _vl() =>
      Container(width: 1, height: 30, color: Colors.white10);

  Widget _mapBtn(IconData icon, VoidCallback onTap, {String? label}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF0d1320),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8)],
          ),
          child: label != null
              ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white54, size: 14),
                Text(label, style: const TextStyle(
                    color: Colors.white38, fontSize: 7,
                    letterSpacing: 0.5)),
              ])
              : Icon(icon, color: Colors.white54, size: 20),
        ),
      );

  /// Bottom map style chip. Selected = pink fill + pink border.
  /// Unselected = dark fill + thin gray border.
  Widget _stylePickerChip({
    required String       label,
    required String       subtitle,
    required IconData     icon,
    required bool         selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? _accent.withValues(alpha: 0.10)
                : const Color(0xFF0d1320).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _accent.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(
                color: _accent.withValues(alpha: 0.25),
                blurRadius: 12)]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? _accent
                    : Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? _accent : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  PACE SPLIT GRAPH
// ═══════════════════════════════════════════════════════════════
class _PaceSplitGraph extends StatelessWidget {
  final List<double> splits;
  final Color        color;
  const _PaceSplitGraph({required this.splits, required this.color});

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) return const SizedBox.shrink();
    final max = splits.reduce(math.max);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: splits.asMap().entries.map((e) {
          final pct = max > 0 ? (e.value / max) : 0.0;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 18,
                height: (pct * 44).clamp(4.0, 44.0),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 3),
              Text("${e.key + 1}'",
                  style: const TextStyle(
                      color: Colors.white30, fontSize: 8)),
            ],
          );
        }).toList(),
      ),
    );
  }
}