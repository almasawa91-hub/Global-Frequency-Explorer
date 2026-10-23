import 'package:flutter_test/flutter_test.dart';
import 'package:global_frequency_explorer/main.dart';

void main() {
  test('station parser handles a Radio Browser station', () {
    final station = Station.fromJson({
      'stationuuid': 'abc',
      'name': 'Test Radio',
      'country': 'Yemen',
      'url': 'https://example.com/live',
      'url_resolved': 'https://example.com/live',
      'geo_lat': '15.3',
      'geo_long': '44.2',
      'votes': 12,
      'bitrate': 128,
      'codec': 'MP3',
    });
    expect(station.name, 'Test Radio');
    expect(station.country, 'Yemen');
    expect(station.lat, 15.3);
    expect(station.lon, 44.2);
  });
}
