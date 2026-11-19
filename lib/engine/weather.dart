import 'dart:convert';
import 'dart:io';

/// The weather where a session began, from MET Norway's Locationforecast
/// (https://api.met.no/weatherapi/locationforecast/2.0/documentation): free,
/// worldwide, no key, and usable in a paid app under CC BY 4.0 as long as
/// the data is credited and requests carry an identifying User-Agent.
///
/// The position is rounded to 0.1 degrees (about 10 km) before it leaves
/// the phone. Field names follow BirdNET Live's weather snapshot, with a
/// few extras MET gives (humidity, pressure, its symbol).
///
/// Returns null on any failure: weather never holds up a session.
Future<Map<String, dynamic>?> fetchWeather(double lat, double lon, {DateTime? at}) async {
  final when = (at ?? DateTime.now()).toUtc();
  final rLat = (lat * 10).round() / 10, rLon = (lon * 10).round() / 10;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final uri = Uri.https('api.met.no', '/weatherapi/locationforecast/2.0/compact',
        {'lat': '$rLat', 'lon': '$rLon'});
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    // MET requires an app name and a way to reach its maker.
    req.headers.set(HttpHeaders.userAgentHeader,
        'Birdsong/0.1 github.com/dopeytree/birdsong');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final series = ((jsonDecode(body) as Map)['properties'] as Map)['timeseries'] as List;
    if (series.isEmpty) return null;

    // The step closest to when the session began.
    Map best = series.first as Map;
    var bestGap = const Duration(days: 999);
    for (final s in series) {
      final t = DateTime.parse((s as Map)['time'] as String);
      final gap = t.difference(when).abs();
      if (gap < bestGap) {
        best = s;
        bestGap = gap;
      }
    }
    final data = best['data'] as Map;
    final now = (data['instant'] as Map)['details'] as Map;
    final next = data['next_1_hours'] as Map?;
    double? num_(Object? v) => (v as num?)?.toDouble();
    return {
      'source': 'MET Norway Locationforecast 2.0 (CC BY 4.0)',
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'observedAt': DateTime.parse(best['time'] as String).toUtc().toIso8601String(),
      'latitude': rLat,
      'longitude': rLon,
      if (now['air_temperature'] != null) 'temperatureC': num_(now['air_temperature']),
      if (next?['details']?['precipitation_amount'] != null)
        'precipitationMm': num_(next!['details']['precipitation_amount']),
      if (now['wind_speed'] != null) 'windSpeedMs': num_(now['wind_speed']),
      if (now['wind_from_direction'] != null)
        'windDirectionDeg': num_(now['wind_from_direction']),
      if (now['cloud_area_fraction'] != null)
        'cloudCoverPercent': num_(now['cloud_area_fraction'])!.round(),
      if (now['relative_humidity'] != null) 'humidityPercent': num_(now['relative_humidity']),
      if (now['air_pressure_at_sea_level'] != null)
        'pressureHpa': num_(now['air_pressure_at_sea_level']),
      if (next?['summary']?['symbol_code'] != null) 'symbol': next!['summary']['symbol_code'],
    };
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
