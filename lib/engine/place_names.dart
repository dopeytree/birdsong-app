import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The nearest town or village to a position, from OpenStreetMap's
/// Nominatim (https://nominatim.org/release-docs/latest/api/Reverse/): free,
/// no key, under its usage policy as long as requests carry an identifying
/// User-Agent, come at most once a second, and results are kept rather than
/// asked for again. Birdsong asks once per session and saves the name with
/// it (Session.placeName). Data © OpenStreetMap contributors (ODbL).
///
/// The position is rounded to 0.001 degrees (about 100 m) before it leaves
/// the phone.
///
/// Returns the name, '' when there is no settlement there (out at sea, say:
/// not asked again), or null when the look-up failed (asked again later).
Future<String?> nearestPlace(double lat, double lon) => _queue = _queue.then((_) => _ask(lat, lon));

// One at a time, a little over a second apart, as the policy asks.
Future<String?> _queue = Future.value();
DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

/// The most local name a place has that reads as a town or village.
String placeFromAddress(Map<String, dynamic> a) {
  for (final k in const ['village', 'town', 'city', 'hamlet', 'suburb', 'municipality', 'county', 'state']) {
    final v = a[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

Future<String?> _ask(double lat, double lon) async {
  final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_last);
  if (!wait.isNegative) await Future<void>.delayed(wait);
  _last = DateTime.now();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': lat.toStringAsFixed(3),
      'lon': lon.toStringAsFixed(3),
      'zoom': '14',
      'addressdetails': '1',
    });
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    req.headers.set(HttpHeaders.userAgentHeader, 'Birdsong/0.1 github.com/dopeytree/birdsong');
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'en');
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) return null;
    final j = jsonDecode(body);
    if (j is! Map) return null;
    if (j['error'] != null) return ''; // nothing there
    final a = j['address'];
    return a is Map ? placeFromAddress(a.cast<String, dynamic>()) : '';
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
