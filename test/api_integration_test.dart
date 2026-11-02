// Drives the real ApiService against a running backend.
//
//   (backend + PostGIS running on :8081)
//   flutter test test/api_integration_test.dart --dart-define=API_BASE_URL=http://localhost:8081
//
// Skipped automatically when API_BASE_URL is not provided.
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show defaultFirebaseAppName;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aurarun_app/services/api_service.dart';

const _backend = String.fromEnvironment('API_BASE_URL');

// Firebase core mock that also hands Crashlytics the constant it asserts on.
class _FakeFirebaseCore implements TestFirebaseCoreHostApi {
  static final _options = CoreFirebaseOptions(
      apiKey: '123', projectId: '123', appId: '123', messagingSenderId: '123');
  static const _constants = {
    'plugins.flutter.io/firebase_crashlytics': {
      'isCrashlyticsCollectionEnabled': true,
    },
  };

  @override
  Future<CoreInitializeResponse> initializeApp(
          String appName, CoreFirebaseOptions request) async =>
      CoreInitializeResponse(
          name: appName, options: _options, pluginConstants: _constants);

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => [
        CoreInitializeResponse(
            name: defaultFirebaseAppName,
            options: _options,
            pluginConstants: _constants),
      ];

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async => _options;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding blocks real HTTP by default

  final username = 'flt${DateTime.now().millisecondsSinceEpoch % 10000000}';
  const password = 'secret1';

  setUpAll(() async {
    // ApiService logs to Crashlytics; main() initialises Firebase in the real app.
    TestFirebaseCoreHostApi.setUp(_FakeFirebaseCore());
    await Firebase.initializeApp();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/firebase_crashlytics'),
            (call) async => null);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('full app flow against the backend', () async {
    // ── register ────────────────────────────────────────────
    final reg = await ApiService.register(username, password,
        email: '$username@example.com', trailColor: 'BLUE');
    expect(reg['token'], isNotNull, reason: 'register: $reg');
    expect(reg['refreshToken'], isNotNull);
    expect(await ApiService.getToken(), reg['token']);

    // ── start a run, walk ~35 m north in 3 pings ─────────────
    final run = await ApiService.startRun();
    expect(run['isActive'], true, reason: 'startRun: $run');

    final t0 = DateTime.now().subtract(const Duration(seconds: 40));
    final points = [
      for (var i = 0; i < 4; i++)
        GpsBatchPoint(
          lat: 22.7196 + i * 0.0001,
          lng: 75.8577,
          speedKmh: 4.0,
          time: t0.add(Duration(seconds: i * 10)),
        ),
    ];
    final batch = await ApiService.sendGpsBatch(points);
    expect(batch['accepted'], true, reason: 'batch: $batch');
    expect(batch['zonePainted'], true);
    expect(batch['totalZonesPaintedThisRun'], greaterThanOrEqualTo(1));

    // ── the zone shows up in the viewport with GeoJSON-style coords ──
    final zones =
        await ApiService.getViewport(22.71, 22.73, 75.85, 75.87);
    expect(zones, isNotEmpty);
    final mine = zones.firstWhere((z) => z['ownerUsername'] == username);
    expect(mine['factionColor'], 'BLUE');
    expect((mine['coordinates'] as List).first, hasLength(2)); // [lng, lat]

    // ── stop run + history + stats + leaderboard ────────────
    final stopped = await ApiService.stopRun();
    expect(stopped['isActive'], false, reason: 'stopRun: $stopped');
    expect(stopped['distanceMeters'], greaterThan(0));

    final runs = await ApiService.getRunHistory(username);
    expect(runs, hasLength(1));
    expect(runs.first['zonesPainted'], greaterThanOrEqualTo(1));
    expect(runs.first['durationSeconds'], isA<int>());
    expect(runs.first['startedAt'], isA<String>());

    final stats = await ApiService.getUserStats(username);
    expect(stats['totalRuns'], 1);
    expect(stats['totalZonesPainted'], greaterThanOrEqualTo(1));
    expect(stats['globalRank'], isNotNull);
    expect(stats['memberSince'], isA<String>());

    final board = await ApiService.getLeaderboard();
    expect(board.any((e) => e['username'] == username), true);

    // ── expired/invalid access token -> 401 -> silent refresh -> retry ──
    final goodRefresh = await ApiService.getRefreshToken();
    await ApiService.saveTokens('not.a.valid.token', goodRefresh!);
    await ApiService.refreshUserInfo();
    final info = await ApiService.getSavedUserInfo();
    expect(info['username'], username,
        reason: 'refreshUserInfo should have refreshed the token and retried');
    expect(await ApiService.getToken(), isNot('not.a.valid.token'));

    // ── logout clears tokens ────────────────────────────────
    await ApiService.logout();
    expect(await ApiService.getToken(), isNull);
    expect(await ApiService.getRefreshToken(), isNull);
  }, skip: _backend.isEmpty ? 'set --dart-define=API_BASE_URL' : false);
}
