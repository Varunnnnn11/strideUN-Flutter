import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String baseUrl = 'http://localhost:8081';

class ApiService {

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> register(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<List<dynamic>> getViewport(
      double minLat, double maxLat, double minLng, double maxLng) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/map/viewport'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'minLat': minLat, 'maxLat': maxLat,
        'minLng': minLng, 'maxLng': maxLng,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> startRun() async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/track/start'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> sendGpsUpdate(
      double lat, double lng, double speedKmh) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/track/update'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'latitude': lat,
        'longitude': lng,
        'speedKmh': speedKmh,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> stopRun() async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/track/stop'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getUserStats(String username) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/stats/user/$username'),
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(response.body);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  static Future<List<dynamic>> getLeaderboard() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/stats/leaderboard'),
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(response.body);
  }
}