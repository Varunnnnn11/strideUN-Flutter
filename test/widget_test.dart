import 'package:flutter_test/flutter_test.dart';

import 'package:aurarun_app/services/api_service.dart';

void main() {
  test('GpsBatchPoint serialises to the shape the backend expects', () {
    final time = DateTime.utc(2026, 11, 2, 9, 30, 0);
    final json = GpsBatchPoint(
      lat: 22.7196,
      lng: 75.8577,
      speedKmh: 8.5,
      time: time,
    ).toJson();

    expect(json['latitude'], 22.7196);
    expect(json['longitude'], 75.8577);
    expect(json['speedKmh'], 8.5);
    expect(json['timestamp'], time.toIso8601String());
    expect((json['timestamp'] as String).endsWith('Z'), isTrue);

    // a local (non-UTC) time must still go out as UTC
    final local = DateTime(2026, 11, 2, 15, 0, 0);
    final sent = GpsBatchPoint(lat: 0, lng: 0, speedKmh: 0, time: local).toJson();
    expect(DateTime.parse(sent['timestamp'] as String).isAtSameMomentAs(local), isTrue);
    expect((sent['timestamp'] as String).endsWith('Z'), isTrue);
  });
}
