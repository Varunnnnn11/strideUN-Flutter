import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// Override per build without touching code:
//   flutter build apk --dart-define=API_BASE_URL=https://your-backend
const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kIsWeb
      ? 'http://localhost:8081'
      : 'https://13-202-27-215.sslip.io', // AWS ap-south-1 (EC2 + RDS), see AuraRun/aws/README.md
);

// ═══════════════════════════════════════════════════════════════
//  GPS BATCH MODEL
// ═══════════════════════════════════════════════════════════════
class GpsBatchPoint {
  final double   lat;
  final double   lng;
  final double   speedKmh;
  final DateTime time;

  GpsBatchPoint({
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
    'latitude':       lat,
    'longitude':      lng,
    'speedKmh':       speedKmh,
    'accuracyMeters': 15.0,
    // UTC with a 'Z': the server checks the claimed time against its own clock,
    // so a zone-less local time (e.g. IST) would look like the future.
    'timestamp':      time.toUtc().toIso8601String(),
  };
}

// ═══════════════════════════════════════════════════════════════
//  API SERVICE
// ═══════════════════════════════════════════════════════════════
class ApiService {

  // ── TOKEN STORAGE ─────────────────────────────────────────────
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refreshToken');
  }

  static Future<void> saveTokens(
      String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', accessToken);
    await prefs.setString('refreshToken', refreshToken);
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static Future<void> logout() async {
    final prefs   = await SharedPreferences.getInstance();
    final refresh = prefs.getString('refreshToken');
    if (refresh != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/api/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refresh}),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    await prefs.remove('token');
    await prefs.remove('refreshToken');
  }

  // ── AUTO REFRESH INTERCEPTOR ──────────────────────────────────
  // Attaches JWT to every request. On 401, auto-refreshes token
  // and retries once. Used by all authenticated endpoints.
  static Future<http.Response> _authRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final token = await getToken();
    final headers = {
      'Content-Type':  'application/json',
      'Authorization': 'Bearer $token',
    };

    http.Response response = await _rawRequest(
      method: method, path: path,
      headers: headers, body: body,
    );

    if (response.statusCode == 401) {
      final refreshed = await tryRefresh();
      if (refreshed) {
        final newToken = await getToken();
        headers['Authorization'] = 'Bearer $newToken';
        response = await _rawRequest(
          method: method, path: path,
          headers: headers, body: body,
        );
      }
    }

    return response;
  }

  static Future<http.Response> _rawRequest({
    required String method,
    required String path,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    final uri     = Uri.parse('$baseUrl$path');
    final bodyStr = body != null ? jsonEncode(body) : null;

    headers['User-Agent']       = 'Strideun/1.0 (Android)';
    headers['X-Requested-With'] = 'com.example.aurarun_app';

    const timeout = Duration(seconds: 12);
    switch (method.toUpperCase()) {
      case 'GET':
        return http.get(uri, headers: headers).timeout(timeout);
      case 'POST':
        return http.post(uri, headers: headers, body: bodyStr).timeout(timeout);
      case 'PUT':
        return http.put(uri, headers: headers, body: bodyStr).timeout(timeout);
      default:
        return http.get(uri, headers: headers).timeout(timeout);
    }
  }

  // ── REFRESH TOKEN ─────────────────────────────────────────────
  // Exchanges refresh token for new access token.
  // Called automatically on 401. Returns true if successful.
  static Future<bool> tryRefresh() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) return false;

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await saveTokens(
          data['token'],
          data['refreshToken'] ?? refreshToken,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── AUTH ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    FirebaseCrashlytics.instance.setUserIdentifier(username);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {
          'Content-Type':    'application/json',
          'User-Agent':      'Strideun/1.0 (Android)',
          'X-Requested-With':'com.example.aurarun_app',
        },
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 429) {
        throw Exception('Too many login attempts. Please wait 10 minutes.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['token'] != null && data['refreshToken'] != null) {
        await saveTokens(data['token'], data['refreshToken']);
        await saveUserInfo(
          data['username']   ?? username,
          data['trailColor'] ?? 'PINK',
        );
      }
      return data;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
          e, stack, reason: 'login failed for user: $username', fatal: false);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> register(
      String username,
      String password, {
        required String email,
        String trailColor = 'PINK',
      }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {
          'Content-Type':    'application/json',
          'User-Agent':      'Strideun/1.0 (Android)',
          'X-Requested-With':'com.example.aurarun_app',
        },
        body: jsonEncode({
          'username':   username,
          'email':      email,
          'password':   password,
          'trailColor': trailColor,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.body.isEmpty) {
        throw Exception(
            'Server returned empty response (status: ${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['token'] != null && data['refreshToken'] != null) {
        await saveTokens(data['token'], data['refreshToken']);
      }
      return data;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
          e, stack, reason: 'register failed for user: $username', fatal: false);
      rethrow;
    }
  }

  // ── MAP ───────────────────────────────────────────────────────
  // Fetches all zones in the current map viewport.
  // Called every 45s during a run and on map load.
  static Future<List<dynamic>> getViewport(
      double minLat, double maxLat,
      double minLng, double maxLng) async {
    try {
      final response = await _authRequest(
        method: 'POST',
        path:   '/api/map/viewport',
        body: {
          'minLat': minLat, 'maxLat': maxLat,
          'minLng': minLng, 'maxLng': maxLng,
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      return jsonDecode(response.body);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
          e, stack, reason: 'viewport load failed', fatal: false);
      return [];
    }
  }

  // ── TRACKING ──────────────────────────────────────────────────
  // Creates a new Trail on the backend.
  // If a run is already active, backend returns the existing one.
  static Future<Map<String, dynamic>> startRun() async {
    try {
      final res = await _authRequest(
        method: 'POST',
        path:   '/api/track/start',
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 && res.statusCode != 201) return {};
      return jsonDecode(res.body);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
          e, stack, reason: 'startRun API failed', fatal: false);
      rethrow;
    }
  }

  // Sends a batch of GPS points every 30 seconds.
  // Backend velocity-filters each point and paints zones.
  // Returns zonePainted + totalZonesPaintedThisRun.
  static Future<Map<String, dynamic>> sendGpsBatch(
      List<GpsBatchPoint> points) async {
    if (points.isEmpty) return {};

    try {
      final res = await _authRequest(
        method: 'POST',
        path:   '/api/track/batch',
        body:   {'points': points.map((p) => p.toJson()).toList()},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => http.Response('{"timeout":true}', 408),
      );

      if (res.statusCode == 401) return {'sessionExpired': true};

      if (res.statusCode == 408) {
        FirebaseCrashlytics.instance.log(
            'GPS batch timeout — ${points.length} points, will retry');
        return {};
      }

      if (res.statusCode != 200) return {};
      return jsonDecode(res.body);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
          e, stack,
          reason: 'GPS batch send failed — ${points.length} points lost',
          fatal: false);
      return {};
    }
  }

  // Marks the Trail as inactive on the backend.
  // Returns final distanceMeters from server for accuracy.
  static Future<Map<String, dynamic>> stopRun() async {
    try {
      final res = await _authRequest(
        method: 'POST',
        path:   '/api/track/stop',
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return {};
      return jsonDecode(res.body);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
          e, stack, reason: 'stopRun API failed', fatal: false);
      rethrow;
    }
  }

  // ── STATS ─────────────────────────────────────────────────────
  // Fetches public stats for any user.
  // Returns empty map on error — ProfileScreen handles gracefully.
  static Future<Map<String, dynamic>> getUserStats(String username) async {
    try {
      final res = await _authRequest(
        method: 'GET',
        path:   '/api/stats/user/$username',
      ).timeout(const Duration(seconds: 10));
      FirebaseCrashlytics.instance.log('Stats[$username]: ${res.statusCode} body=${res.body.length}ch');
      if (res.statusCode != 200) return {};
      return jsonDecode(res.body);
    } catch (_) {
      return {};
    }
  }

  static Future<void> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 429) {
      throw Exception('Too many requests. Please wait a few minutes.');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to send reset email');
    }
  }

  // ── USER INFO ─────────────────────────────────────────────────
  static Future<void> saveUserInfo(
      String username, String trailColor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    await prefs.setString('trailColor', trailColor);
  }

  static Future<Map<String, String?>> getSavedUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'username':   prefs.getString('username'),
      'trailColor': prefs.getString('trailColor'),
    };
  }

  // Fetches fresh user info from /api/auth/me and saves locally.
  // Called after token refresh to keep username/trailColor in sync.
  static Future<void> refreshUserInfo() async {
    try {
      final res = await _authRequest(
        method: 'GET',
        path:   '/api/auth/me',
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await saveUserInfo(
          data['username']   ?? '',
          data['trailColor'] ?? 'PINK',
        );
      }
    } catch (_) {}
  }

  // Fetches past runs for a user. Returns empty list on error.
  static Future<List<dynamic>> getRunHistory(String username,
      {int limit = 20}) async {
    try {
      final res = await _authRequest(
        method: 'GET',
        path: '/api/stats/user/$username/runs?limit=$limit',
      ).timeout(const Duration(seconds: 10));
      FirebaseCrashlytics.instance.log(
          'Runs[$username]: ${res.statusCode} body=${res.body.length}ch');
      if (res.statusCode != 200) return [];
      return jsonDecode(res.body);
    } catch (e) {
      FirebaseCrashlytics.instance.log('Runs[$username]: EXCEPTION $e');
      return [];
    }
  }
  // ── LEADERBOARD ───────────────────────────────────────────────
  // Public endpoint — no auth needed.
  // Returns top 10 players by totalZonesPainted.
  static Future<List<dynamic>> getLeaderboard() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/stats/leaderboard'),
        headers: {
          'Content-Type':    'application/json',
          'User-Agent':      'Strideun/1.0 (Android)',
          'X-Requested-With':'com.example.aurarun_app',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return []; // FIX: was missing
      return jsonDecode(response.body);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
          e, stack, reason: 'leaderboard load failed', fatal: false);
      return [];
    }
  }
}