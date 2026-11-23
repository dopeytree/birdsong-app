import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../settings.dart';
import 'station_archive.dart';

/// A remote station's plate: what it heard over a period, or on one day,
/// asked of BirdNET-Go (its /api/v2) or of a public BirdWeather station
/// (its GraphQL), as the web plate asks them (assets/web/index.html,
/// fetchSpecies, fetchSpeciesBW, loadExtras). Asked again every minute.

/// The four periods of the web plate.
enum Span {
  today('Today', 'Today'),
  week('Seven days', 'Week'),
  month('Thirty days', 'Month'),
  all('Since records began', 'All');

  const Span(this.label, this.short);
  final String label;

  /// The word on a phone, where the four share a corner.
  final String short;
}

/// Which part of the day a station's plate counts: all of it, the hours
/// of daylight (sunrise to sunset), or the night.
enum Light {
  all('Day and night'),
  day('Daytime'),
  night('Night-time');

  const Light(this.label);
  final String label;

  Light get next => Light.values[(index + 1) % Light.values.length];
}

/// Whether hour [h] (0 to 23, the station's own clock) counts for [light],
/// given sunrise and sunset in hours (6.5 is 06:30): an hour is daytime
/// when its middle is between them.
bool inLight(int h, Light light, (double, double) sun) {
  if (light == Light.all) return true;
  final mid = h + .5, isDay = mid >= sun.$1 && mid < sun.$2;
  return light == Light.day ? isDay : !isDay;
}

/// [rows] counted again over the hours [light] keeps, from [hours] (each
/// species' calls by hour); those heard none of those hours drop out, the
/// rest are most heard first. A species with no hours given keeps none.
List<StationSpecies> byLight(
    List<StationSpecies> rows, Map<String, List<int>> hours, Light light, (double, double) sun) {
  if (light == Light.all) return rows;
  final out = <StationSpecies>[];
  for (final r in rows) {
    final h = hours[r.sci] ?? r.hourly;
    if (h == null || h.length != 24) continue;
    var n = 0;
    for (var i = 0; i < 24; i++) {
      if (inLight(i, light, sun)) n += h[i];
    }
    if (n > 0) out.add(r.withCount(n));
  }
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

/// Sunrise and sunset as hours of [day] on a clock [offset] from UTC, at
/// [lat], [lon] (NOAA's sunrise equation); null where the sun stays up or
/// down all day.
(double, double)? sunHours(DateTime day, double lat, double lon, Duration offset) {
  // whole days from noon on 1 Jan 2000 (UTC) to noon on [day]
  final n = DateTime.utc(day.year, day.month, day.day, 12).difference(DateTime.utc(2000, 1, 1, 12)).inDays;
  final jStar = n - lon / 360;
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;
  final m = (357.5291 + .98560028 * jStar) % 360;
  final c = 1.9148 * math.sin(rad(m)) + .02 * math.sin(rad(2 * m)) + .0003 * math.sin(rad(3 * m));
  final l = (m + c + 180 + 102.9372) % 360;
  final transit = jStar + .0053 * math.sin(rad(m)) - .0069 * math.sin(rad(2 * l));
  final dec = math.asin(math.sin(rad(l)) * math.sin(rad(23.44)));
  final cosW = (math.sin(rad(-.833)) - math.sin(rad(lat)) * math.sin(dec)) / (math.cos(rad(lat)) * math.cos(dec));
  if (cosW.abs() > 1) return null;
  final w = deg(math.acos(cosW)) / 360;
  // a time in days from noon on 1 Jan 2000 (UTC), as hours on [day]'s clock
  double clock(double j) => ((j - n) * 24 + 12 + offset.inMinutes / 60) % 24;
  return (clock(transit - w), clock(transit + w));
}

/// BirdNET-Go's sun times for a day ({sunrise, sunset}, in the station's
/// own time) as hours; null without them.
(double, double)? sunFrom(Object? j) {
  if (j is! Map) return null;
  double? at(Object? v) {
    final m = RegExp(r'T(\d\d):(\d\d)').firstMatch('$v');
    return m == null ? null : int.parse(m[1]!) + int.parse(m[2]!) / 60;
  }
  final a = at(j['sunrise']), b = at(j['sunset']);
  return a != null && b != null && b > a ? (a, b) : null;
}

/// Each species' calls by hour from BirdNET-Go: its acoustic succession
/// ([{scientificName, counts}]) or its daily lists ({date: [{scientific_name,
/// hourly_counts}]}, perhaps under data), added up.
void addHours(Map<String, List<int>> into, Object? j) {
  void add(String sci, Object? counts) {
    if (sci.isEmpty || counts is! List || counts.length != 24) return;
    final h = into.putIfAbsent(sci, () => List.filled(24, 0));
    for (var i = 0; i < 24; i++) {
      h[i] += ((counts[i] as num?) ?? 0).toInt();
    }
  }
  void rows(Object? l) {
    if (l is! List) return;
    for (final o in l) {
      if (o is! Map) continue;
      add('${o['scientificName'] ?? o['scientific_name'] ?? ''}', o['counts'] ?? o['hourly_counts']);
    }
  }
  if (j is List) return rows(j);
  if (j is! Map) return;
  final inner = j['data'] ?? j['results'];
  if (inner is List) return rows(inner);
  for (final v in (inner is Map ? inner : j).values) {
    rows(v);
  }
}

/// One species on a station's plate.
class StationSpecies {
  StationSpecies({
    required this.sci,
    required this.common,
    required this.count,
    this.first,
    this.last,
    this.maxConf = 0,
    this.avgConf = 0,
    this.daysKnown = 0,
    this.hourly,
    this.bwId,
  });

  final String sci;
  final String common;
  final int count;
  final DateTime? first;
  final DateTime? last;
  final double maxConf;
  final double avgConf;
  final int daysKnown;

  /// Calls in each hour, when the station gives them with the list.
  final List<int>? hourly;

  /// BirdWeather's own id for the species, for its card.
  final String? bwId;

  /// The same species, heard [n] times (the day or the night alone).
  StationSpecies withCount(int n) => StationSpecies(
      sci: sci,
      common: common,
      count: n,
      first: first,
      last: last,
      maxConf: maxConf,
      avgConf: avgConf,
      daysKnown: daysKnown,
      hourly: hourly,
      bwId: bwId);
}

/// One of a species' latest recordings at a station.
class StationRecording {
  const StationRecording({
    required this.at,
    required this.confidence,
    this.weather,
    this.audioUrl,
    this.clip,
    this.spectrogramUrl,
  });

  final DateTime at;
  final double confidence;
  final String? weather;
  final String? audioUrl;

  /// The call within a longer recording (BirdWeather's soundscapes), in
  /// seconds, a second either side.
  final (double, double)? clip;
  final String? spectrogramUrl;
}

/// One call a station heard, as a day's folder keeps it.
class StationCall {
  const StationCall({
    required this.id,
    required this.at,
    required this.sci,
    required this.common,
    required this.confidence,
    this.verified,
    this.audioUrl,
    this.spectrogramUrl,
    this.clip,
  });

  /// The station's own number for it.
  final int id;
  final DateTime at;
  final String sci;
  final String common;
  final double confidence;

  /// BirdNET-Go's review: correct, false_positive, or none yet.
  final String? verified;
  final String? audioUrl;
  final String? spectrogramUrl;

  /// The call within a longer recording (BirdWeather's soundscapes), in seconds.
  final (double, double)? clip;
}

/// BirdNET-Go's daily lists for several [dates] ({date: [{scientific_name,
/// count}]}, perhaps under data) as species and calls a day.
Map<String, (int, int)> daySumsOf(Object? j, List<String> dates) {
  final out = <String, (int, int)>{};
  final m = j is Map ? ((j['data'] ?? j['results']) is Map ? (j['data'] ?? j['results']) as Map : j) : null;
  if (m == null) return out;
  for (final date in dates) {
    final rows = m[date];
    if (rows is! List) continue;
    var species = 0, calls = 0;
    for (final o in rows) {
      if (o is! Map) continue;
      final n = ((o['count'] ?? o['total'] ?? 0) as num).toInt();
      if (n <= 0) continue;
      species++;
      calls += n;
    }
    out[date] = (species, calls);
  }
  return out;
}

String _two(int n) => n.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// "Sat 21 Nov", with the year when it isn't this one.
String dayWords(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}${d.year == DateTime.now().year ? '' : ' ${d.year}'}';
}

/// BirdNET-Go's hourly weather for a day ({data: [{time, temperature,
/// weather_main, weather_desc}]}, OpenWeather's words) as one reading in
/// a session's shape: the latest for today, else the one nearest midday.
Map<String, dynamic>? dayWeather(Object? j, {required bool today}) {
  final rows = (j is Map ? j['data'] : j);
  if (rows is! List) return null;
  int mins(Map r) {
    final p = '${r['time']}'.split(':');
    return p.length < 2 ? -1 : (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }
  Map? best;
  for (final r in rows) {
    if (r is! Map || r['temperature'] is! num || mins(r) < 0) continue;
    if (best == null ||
        (today ? mins(r) > mins(best) : (mins(r) - 720).abs() < (mins(best) - 720).abs())) {
      best = r;
    }
  }
  if (best == null) return null;
  final main = '${best['weather_main'] ?? ''}'.toLowerCase(), desc = '${best['weather_desc'] ?? ''}'.toLowerCase();
  final light = desc.contains('light') || main == 'drizzle', heavy = desc.contains('heavy');
  final symbol = switch (main) {
    'thunderstorm' => 'rainandthunder',
    'snow' => light ? 'lightsnow' : (heavy ? 'heavysnow' : 'snow'),
    'rain' || 'drizzle' => light ? 'lightrain' : (heavy ? 'heavyrain' : 'rain'),
    'mist' || 'fog' || 'haze' || 'smoke' || 'dust' => 'fog',
    'clouds' => desc.contains('few') || desc.contains('scattered') ? 'partlycloudy_day' : 'cloudy',
    'clear' => 'clearsky_day',
    _ => null,
  };
  return {'temperatureC': best['temperature'], if (symbol != null) 'symbol': symbol};
}

/// A station's time: "2026-11-20 07:42:10", an ISO stamp, or a bare
/// "07:42:10" on [day].
DateTime? stationTime(Object? v, DateTime day) {
  if (v is! String || v.isEmpty) return null;
  final t = RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$');
  if (t.hasMatch(v)) {
    final p = v.split(':').map(int.parse).toList();
    return DateTime(day.year, day.month, day.day, p[0], p[1], p.length > 2 ? p[2] : 0);
  }
  final d = DateTime.tryParse(v.replaceFirst(' ', 'T'));
  // a station's wall-clock time, as the page reads it
  return d?.isUtc == true ? d!.toLocal() : d;
}

/// The page's fetchSpecies rows: BirdNET-Go's names for things vary a little
/// between its versions.
List<StationSpecies> birdnetRows(Object? j, DateTime day) {
  final rows = j is List
      ? j
      : j is Map
          ? (j['species'] ?? j['data'] ?? j['items']) as List? ?? const []
          : const [];
  final out = <StationSpecies>[];
  for (final o in rows) {
    if (o is! Map) continue;
    final sci = (o['scientific_name'] ?? o['scientificName'] ?? '') as String;
    final count = ((o['count'] ?? o['total'] ?? o['count_in_period'] ?? 0) as num).toInt();
    if (sci.isEmpty || count <= 0) continue;
    final hourly = o['hourly_counts'];
    out.add(StationSpecies(
      sci: sci,
      common: (o['common_name'] ?? o['commonName'] ?? sci) as String,
      count: count,
      first: stationTime(o['first_heard'] ?? o['first_seen'] ?? o['first_heard_date'], day),
      last: stationTime(o['last_heard'] ?? o['latest_heard'] ?? o['last_seen'] ?? o['latest_seen'], day),
      hourly: hourly is List && hourly.length == 24 ? [for (final h in hourly) (h as num).toInt()] : null,
      maxConf: ((o['max_confidence'] ?? 0) as num).toDouble(),
      avgConf: ((o['avg_confidence'] ?? 0) as num).toDouble(),
      daysKnown: ((o['days_since_first_seen'] ?? 0) as num).toInt(),
    ));
  }
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

class StationFeed extends ChangeNotifier {
  /// [root] is the app's data folder: each day shown is kept there in the
  /// session format, and the station's back days filled in
  /// (station_archive.dart).
  StationFeed(this.station, {Directory? root, bool Function()? keepPast}) {
    if (root != null) archive = StationArchive(root, this, keepPast: keepPast);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => load(quiet: true));
    load();
  }

  final Station station;

  /// The station's days kept on the device; null in tests.
  StationArchive? archive;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  Timer? _timer;

  /// The period shown, or [day] when one day is.
  /// A station opens on today.
  Span span = Span.today;
  DateTime? day;

  /// What the plate shows: the period's species, by the part of the day
  /// chosen ([light]).
  List<StationSpecies>? species;

  /// Day and night, daytime or night-time (the heading's sun and moon).
  Light light = Light.all;

  /// Why the part of the day can't be told apart, when it can't.
  String? lightNote;

  /// Whether the part of the day can be chosen (BirdNET-Go gives calls by
  /// the hour; BirdWeather's list doesn't).
  bool get canLight => !_bw;

  /// The next part of the day: all, day, night.
  void nextLight() {
    light = light.next;
    load();
  }
  String? error;
  bool loading = false;

  /// When the station's records begin (BirdWeather says; BirdNET-Go is
  /// taken as a year back until it says otherwise), and its time zone.
  DateTime? since;
  String? timezone;

  /// Where the station is, when it says.
  (double, double)? place;

  /// The weather on the one day shown (today, or a day picked), as a
  /// session keeps it ({'temperatureC', 'symbol'} in MET Norway's words),
  /// from BirdNET-Go's own weather log; none over several days.
  Map<String, dynamic>? weather;

  bool get _bw => station.isBirdWeather;
  String get _bwId => station.birdweather.replaceAll(RegExp(r'\D'), '');

  int _run = 0;

  @override
  void dispose() {
    _timer?.cancel();
    archive?.close();
    _client.close(force: true);
    super.dispose();
  }

  void setSpan(Span s) {
    span = s;
    day = null;
    load();
  }

  /// Show [d] alone (the calendar, or the index's ‹ ›).
  void setDay(DateTime d) {
    final today = _dayOf(DateTime.now());
    final x = _dayOf(d);
    day = x.isAfter(today) ? today : x;
    load();
  }

  /// The day shown, or today for the periods, a day on or back.
  void stepDay(int by) => setDay((day ?? _dayOf(DateTime.now())).add(Duration(days: by)));

  bool get canStepBack => since == null || (day ?? _dayOf(DateTime.now())).isAfter(_dayOf(since!));
  bool get canStepOn => day != null && day!.isBefore(_dayOf(DateTime.now()));

  /// The period or day in words, for the heading.
  String get showing {
    final d = day;
    if (d == null) return span.label;
    final today = _dayOf(DateTime.now());
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return dayWords(d);
  }

  /// The dates the plate covers, in words: "Sun 15 Nov – Sat 21 Nov", or
  /// the one day; since records began, from the day they began.
  String get dates {
    final (from, to) = _range;
    if (from == to) return dayWords(from);
    // not yet known when they began: nothing more to say
    if (day == null && span == Span.all && since == null) return showing;
    return '${dayWords(from)} – ${dayWords(to)}';
  }

  /// The dates asked for: from, and to (inclusive for BirdNET-Go).
  (DateTime, DateTime) get _range {
    final today = _dayOf(DateTime.now());
    final d = day;
    if (d != null) return (d, d);
    return switch (span) {
      Span.today => (today, today),
      Span.week => (today.subtract(const Duration(days: 6)), today),
      Span.month => (today.subtract(const Duration(days: 29)), today),
      Span.all => (since ?? DateTime(2015), today),
    };
  }

  Future<void> load({bool quiet = false}) async {
    final run = ++_run;
    if (!quiet) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      var got = _bw ? await _speciesBW() : await _speciesGo();
      if (run != _run) return;
      lightNote = null;
      if (light != Light.all && !_bw) {
        final (from, to) = _range;
        final sun = await _sun(from, to);
        final hours = sun == null ? null : await _hoursGo(got, from, to);
        if (run != _run) return;
        if (sun == null) {
          lightNote = "The station doesn't say when the sun rose there.";
        } else if (hours == null) {
          lightNote = 'This BirdNET-Go gives calls by the hour for up to two months at a time.';
        } else {
          got = byLight(got, hours, light, sun);
        }
      }
      species = got;
      error = null;
      // one day on show: keep it (today's again, as it fills); then the
      // back days, quietly
      final (from, to) = _range;
      if (from == to) archive?.want(from);
      archive?.fill();
    } catch (e) {
      if (run != _run) return;
      error = '$e'.replaceFirst('Exception: ', '');
    } finally {
      if (run == _run) {
        loading = false;
        notifyListeners();
      }
    }
  }

  // ---- BirdNET-Go ------------------------------------------------------------

  String get _base {
    var u = station.birdnetUrl.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Future<Object?> _get(String path) async {
    final req = await _client.getUrl(Uri.parse('$_base$path')).timeout(const Duration(seconds: 12));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('BirdNET-Go asked for a sign-in. Allow this app under its security settings, '
          'or turn off private mode.');
    }
    if (res.statusCode != 200) throw Exception('BirdNET-Go answered with error ${res.statusCode}.');
    return jsonDecode(body);
  }

  Future<List<StationSpecies>> _speciesGo() async {
    final (from, to) = _range;
    final today = _dayOf(DateTime.now());
    // One day is counted from the raw detections: BirdNET-Go's daily summary
    // leaves out bat species the detections list has (its own page shows
    // them). A range keeps the summary, which is small enough to ask for whole.
    final List<StationSpecies> rows;
    if (from == to) {
      rows = await _dayFromDetections(from);
    } else {
      final j = await _get(day == null && span == Span.all
          ? '/api/v2/analytics/species/summary'
          : '/api/v2/analytics/species/summary?start_date=${ymd(from)}&end_date=${ymd(to)}');
      rows = birdnetRows(j, today);
    }
    // how far back the station goes: its longest-known species
    if (since == null && rows.isNotEmpty) {
      final known = rows.map((r) => r.daysKnown).reduce((a, b) => a > b ? a : b);
      if (known > 0) since = today.subtract(Duration(days: known));
    }
    _placeGo();
    // one day: its weather, as BirdNET-Go logged it
    if (from == to) {
      try {
        weather = dayWeather(await _get('/api/v2/weather/hourly/${ymd(from)}'), today: from == today);
      } catch (_) {
        weather = null;
      }
    } else {
      weather = null;
    }
    return rows;
  }

  bool _askedPlace = false;
  void _placeGo() {
    if (_askedPlace) return;
    _askedPlace = true;
    // BirdNET-Go keeps its place in its settings, which it may keep private
    _get('/api/v2/settings/birdnet').then((j) {
      if (j is! Map) return;
      final lat = (j['latitude'] as num?)?.toDouble(), lon = (j['longitude'] as num?)?.toDouble();
      if (lat != null && lon != null && (lat != 0 || lon != 0)) {
        place = (lat, lon);
        notifyListeners();
      }
    }).catchError((Object _) {});
  }

  /// Sunrise and sunset in the middle of the dates shown: BirdNET-Go's own,
  /// else worked out from where the station is, on this phone's clock.
  Future<(double, double)?> _sun(DateTime from, DateTime to) async {
    final mid = from.add(Duration(days: to.difference(from).inDays ~/ 2));
    try {
      final s = sunFrom(await _get('/api/v2/weather/sun/${ymd(mid)}'));
      if (s != null) return s;
    } catch (_) {}
    final p = place;
    return p == null ? null : sunHours(mid, p.$1, p.$2, mid.timeZoneOffset);
  }

  /// Each species' calls by hour over the dates: from the day's list for
  /// one day; else BirdNET-Go's acoustic succession, ten species a time;
  /// else its daily lists, seven days a time, up to two months.
  Future<Map<String, List<int>>?> _hoursGo(List<StationSpecies> rows, DateTime from, DateTime to) async {
    if (from == to && rows.every((r) => r.hourly != null)) return {};
    final out = <String, List<int>>{};
    try {
      for (var i = 0; i < rows.length; i += 10) {
        final q = rows.skip(i).take(10).map((r) => 'species=${Uri.encodeQueryComponent(r.sci)}').join('&');
        addHours(out, await _get('/api/v2/analytics/time/succession?start_date=${ymd(from)}&end_date=${ymd(to)}&limit=10&$q'));
      }
      return out;
    } catch (_) {
      out.clear();
    }
    if (to.difference(from).inDays > 62) return null;
    try {
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 7))) {
        final dates = [
          for (var k = 0; k < 7; k++)
            if (!d.add(Duration(days: k)).isAfter(to)) ymd(d.add(Duration(days: k)))
        ].join(',');
        addHours(out, await _get('/api/v2/analytics/species/daily/batch?dates=$dates'));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  // ---- a day's every call, and the calendar's days ------------------------------

  /// One day's species, counted from the raw detections rather than the
  /// summary. Falls back to the day's summary if the station won't list its
  /// calls.
  Future<List<StationSpecies>> _dayFromDetections(DateTime d) async {
    try {
      return speciesOfCalls(await _callsGo(d));
    } catch (e) {
      debugPrint('station day from detections: $e');
      return birdnetRows(await _get('/api/v2/analytics/species/daily?date=${ymd(d)}'), d);
    }
  }

  /// BirdNET-Go's address, for links to its recordings.
  String get goBase => _base;

  /// Every call the station heard on [d], oldest first: BirdNET-Go's
  /// detections a thousand at a time, BirdWeather's a hundred.
  Future<List<StationCall>> callsOn(DateTime d) => _bw ? _callsBW(d) : _callsGo(d);

  Future<List<StationCall>> _callsGo(DateTime d) async {
    final out = <StationCall>[], date = ymd(d);
    var seen = 0;
    for (var page = 0; page < 40; page++) {
      final j = await _get('/api/v2/detections?start_date=$date&end_date=$date'
          '&numResults=1000&offset=$seen&sortBy=date_asc');
      final rows = j is Map ? (j['data'] as List? ?? const []) : (j is List ? j : const []);
      seen += rows.length;
      for (final r in rows) {
        if (r is! Map) continue;
        // an older BirdNET-Go lists its latest calls whatever the day
        if (r['date'] != null && '${r['date']}' != date) {
          throw Exception("This BirdNET-Go can't list one day's calls.");
        }
        final at = stationTime(r['time'], d);
        final sci = '${r['scientificName'] ?? r['scientific_name'] ?? ''}';
        if (at == null || sci.isEmpty) continue;
        final id = (r['id'] as num?)?.toInt();
        out.add(StationCall(
          id: id ?? seen,
          at: at,
          sci: sci,
          common: '${r['commonName'] ?? r['common_name'] ?? sci}',
          confidence: ((r['confidence'] ?? 0) as num).toDouble(),
          verified: r['verified'] as String?,
          audioUrl: id != null && r['spectrogramOnly'] != true ? '$_base/api/v2/audio/$id' : null,
          spectrogramUrl: id != null ? '$_base/api/v2/spectrogram/$id?size=md' : null,
        ));
      }
      final total = j is Map ? (j['total'] as num?)?.toInt() : null;
      if (rows.isEmpty || total == null || seen >= total) break;
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  Future<List<StationCall>> _callsBW(DateTime d) async {
    final out = <StationCall>[];
    String? after;
    for (var page = 0; page < 100; page++) {
      final j = await _gql(
          r'query($ids:[ID!],$p:InputDuration,$after:String){detections(stationIds:$ids,period:$p,first:100,after:$after)'
          r'{pageInfo{hasNextPage endCursor} nodes{id timestamp confidence species{commonName scientificName}'
          r' soundscape{url startTime endTime}}}}',
          {'ids': [_bwId], 'p': _bwPeriod((d, d)), 'after': after});
      final c = (j['detections'] as Map?) ?? const {};
      for (final n in (c['nodes'] as List?) ?? const []) {
        if (n is! Map) continue;
        final at = stationTime(n['timestamp'], d);
        final sp = (n['species'] as Map?) ?? const {};
        final sci = '${sp['scientificName'] ?? ''}';
        if (at == null || sci.isEmpty) continue;
        final sc = (n['soundscape'] as Map?) ?? const {};
        final a = (sc['startTime'] as num?)?.toDouble(), b = (sc['endTime'] as num?)?.toDouble();
        out.add(StationCall(
          id: int.tryParse('${n['id']}') ?? out.length + 1,
          at: at,
          sci: sci,
          common: '${sp['commonName'] ?? sci}',
          confidence: ((n['confidence'] ?? 0) as num).toDouble(),
          audioUrl: sc['url'] as String?,
          clip: a != null && b != null && b > a ? (a, b) : null,
        ));
      }
      final info = (c['pageInfo'] as Map?) ?? const {};
      after = info['endCursor'] as String?;
      if (info['hasNextPage'] != true || after == null) break;
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// How many species and calls on each day from [from] to [to], for the
  /// calendar: BirdNET-Go's daily lists seven days a time, BirdWeather's
  /// daily counts. Days it says nothing of are left out.
  Future<Map<String, (int, int)>> daySums(DateTime from, DateTime to) async {
    final out = <String, (int, int)>{};
    if (_bw) {
      final j = await _gql(
          r'query($ids:[ID!],$p:InputDuration){dailyDetectionCounts(stationIds:$ids,period:$p){date total counts{count}}}',
          {'ids': [_bwId], 'p': _bwPeriod((from, to))});
      for (final r in (j['dailyDetectionCounts'] as List?) ?? const []) {
        if (r is! Map || r['date'] == null) continue;
        out['${r['date']}'.substring(0, 10)] =
            (((r['counts'] as List?) ?? const []).length, ((r['total'] ?? 0) as num).toInt());
      }
      return out;
    }
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 7))) {
      final dates = [
        for (var k = 0; k < 7; k++)
          if (!d.add(Duration(days: k)).isAfter(to)) ymd(d.add(Duration(days: k)))
      ];
      out.addAll(daySumsOf(await _get('/api/v2/analytics/species/daily/batch?dates=${dates.join(',')}'), dates));
    }
    return out;
  }

  /// BirdNET-Go's weather on [d], as a session keeps it; null without it.
  Future<Map<String, dynamic>?> weatherOn(DateTime d) async {
    if (_bw) return null;
    try {
      return dayWeather(await _get('/api/v2/weather/hourly/${ymd(d)}'), today: d == _dayOf(DateTime.now()));
    } catch (_) {
      return null;
    }
  }

  // ---- BirdWeather -------------------------------------------------------------

  Future<Map<String, dynamic>> _gql(String query, Map<String, dynamic> variables) async {
    final req = await _client
        .postUrl(Uri.parse('https://app.birdweather.com/graphql'))
        .timeout(const Duration(seconds: 12));
    req.headers.contentType = ContentType.json;
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.write(jsonEncode({'query': query, 'variables': variables}));
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw Exception('BirdWeather answered with error ${res.statusCode}.');
    final j = jsonDecode(body) as Map<String, dynamic>;
    final errors = j['errors'];
    if (errors is List && errors.isNotEmpty) {
      throw Exception('BirdWeather station $_bwId could not be read '
          '(${(errors.first as Map)['message'] ?? 'query refused'}). '
          'Check the station number, and that the station is public.');
    }
    return (j['data'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// The page's bwPeriod: "to" is the day after, so the last day is in
  /// whether BirdWeather counts it or not.
  Map<String, String> _bwPeriod([(DateTime, DateTime)? r]) {
    final (from, to) = r ?? _range;
    return {'from': ymd(from), 'to': ymd(to.add(const Duration(days: 1)))};
  }

  bool _checked = false;

  Future<List<StationSpecies>> _speciesBW() async {
    if (!_checked) {
      // once: the station exists and is public, when its records begin,
      // its time zone and where it is
      final d = await _gql(
          r'query($id:ID!){station(id:$id){earliestDetectionAt timezone coords{lat lon}}}', {'id': _bwId});
      final st = d['station'] as Map?;
      if (st == null) throw Exception('BirdWeather has no public station $_bwId.');
      since = DateTime.tryParse('${st['earliestDetectionAt'] ?? ''}');
      timezone = st['timezone'] as String?;
      final c = st['coords'] as Map?;
      if (c != null && c['lat'] is num && c['lon'] is num) {
        place = ((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble());
      }
      _checked = true;
    }
    final d = await _gql(
        r'query($ids:[ID!],$p:InputDuration){topSpecies(stationIds:$ids,period:$p,limit:500)'
        r'{count speciesId species{commonName scientificName}}}',
        {'ids': [_bwId], 'p': _bwPeriod()});
    final out = <StationSpecies>[];
    for (final o in (d['topSpecies'] as List? ?? const [])) {
      if (o is! Map) continue;
      final s = (o['species'] as Map?) ?? const {};
      final sci = (s['scientificName'] ?? '') as String;
      final count = ((o['count'] ?? 0) as num).toInt();
      if (sci.isEmpty || count <= 0) continue;
      out.add(StationSpecies(
          sci: sci, common: (s['commonName'] ?? sci) as String, count: count, bwId: '${o['speciesId']}'));
    }
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  // ---- a bird's card -------------------------------------------------------------

  /// Calls by hour over what is shown (BirdWeather: by the hour only for a
  /// week or less, so longer spans show the last seven days).
  Future<({List<int> hours, String label})?> hourly(StationSpecies s) async {
    if (s.hourly != null) return (hours: s.hourly!, label: _hoursLabel());
    try {
      if (_bw) {
        if (s.bwId == null) return null;
        final short = day != null || span == Span.today || span == Span.week;
        final today = _dayOf(DateTime.now());
        final r = short ? _range : (today.subtract(const Duration(days: 6)), today);
        final d = await _gql(
            r'query($sp:ID,$ids:[ID!],$p:InputDuration){species(id:$sp){detectionCounts(period:$p,group:60,stationIds:$ids)'
            r'{bins{key count}}}}',
            {'sp': s.bwId, 'ids': [_bwId], 'p': _bwPeriod(r)});
        final bins = (((d['species'] as Map?)?['detectionCounts'] as Map?)?['bins'] as List?) ?? const [];
        final h = List<int>.filled(24, 0);
        for (final b in bins) {
          final t = DateTime.tryParse('${(b as Map)['key']}')?.toLocal();
          if (t != null) h[t.hour] += ((b['count'] ?? 0) as num).toInt();
        }
        return (hours: h, label: short ? _hoursLabel() : 'Calls by hour of the day, the last seven days');
      }
      final (from, to) = _range;
      final j = await _get('/api/v2/analytics/time/distribution/hourly?species=${Uri.encodeQueryComponent(s.sci)}'
          '&start_date=${ymd(from)}&end_date=${ymd(to)}');
      final h = List<int>.filled(24, 0);
      for (final r in (j is List ? j : const [])) {
        final hour = ((r as Map)['hour'] as num?)?.toInt();
        if (hour != null && hour >= 0 && hour < 24) h[hour] = ((r['count'] ?? 0) as num).toInt();
      }
      return (hours: h, label: _hoursLabel());
    } catch (_) {
      return null;
    }
  }

  String _hoursLabel() => day != null || span == Span.today
      ? 'Calls by hour, ${day == null ? 'today' : showing}'
      : 'Calls by hour of the day, over this period';

  /// Calls each day for the thirty days to the day shown (or today).
  Future<List<({DateTime day, int count})>?> trend(StationSpecies s) async {
    final end = day ?? _dayOf(DateTime.now());
    final start = end.subtract(const Duration(days: 29));
    try {
      final got = <String, int>{};
      if (_bw) {
        if (s.bwId == null) return null;
        final d = await _gql(
            r'query($ids:[ID!],$sps:[ID!],$p:InputDuration){dailyDetectionCounts(stationIds:$ids,speciesIds:$sps,period:$p)'
            r'{date counts{speciesId count}}}',
            {'ids': [_bwId], 'sps': [s.bwId], 'p': _bwPeriod((start, end))});
        for (final r in (d['dailyDetectionCounts'] as List? ?? const [])) {
          var n = 0;
          for (final c in ((r as Map)['counts'] as List? ?? const [])) {
            if ('${(c as Map)['speciesId']}' == s.bwId) n += ((c['count'] ?? 0) as num).toInt();
          }
          if (n > 0) got['${r['date']}'.substring(0, 10)] = n;
        }
      } else {
        final j = await _get('/api/v2/analytics/time/daily?species=${Uri.encodeQueryComponent(s.sci)}'
            '&start_date=${ymd(start)}&end_date=${ymd(end)}');
        for (final r in ((j is Map ? j['data'] : null) as List? ?? const [])) {
          got['${(r as Map)['date']}'.substring(0, 10)] = ((r['count'] ?? 0) as num).toInt();
        }
      }
      return [
        for (var i = 29; i >= 0; i--)
          (day: end.subtract(Duration(days: i)), count: got[ymd(end.subtract(Duration(days: i)))] ?? 0)
      ];
    } catch (_) {
      return null;
    }
  }

  /// The latest four recordings, newest first.
  Future<List<StationRecording>> recordings(StationSpecies s) async {
    try {
      if (_bw) {
        if (s.bwId == null) return const [];
        final d = await _gql(
            r'query($ids:[ID!],$sp:ID,$p:InputDuration){detections(stationIds:$ids,speciesId:$sp,period:$p,first:4)'
            r'{nodes{timestamp confidence soundscape{url startTime endTime}}}}',
            {'ids': [_bwId], 'sp': s.bwId, 'p': _bwPeriod((since ?? DateTime(2015), _dayOf(DateTime.now())))});
        final out = <StationRecording>[];
        for (final n in (((d['detections'] as Map?)?['nodes'] as List?) ?? const [])) {
          final t = stationTime((n as Map)['timestamp'], DateTime.now());
          if (t == null) continue;
          final sc = (n['soundscape'] as Map?) ?? const {};
          final a = (sc['startTime'] as num?)?.toDouble(), b = (sc['endTime'] as num?)?.toDouble();
          out.add(StationRecording(
            at: t,
            confidence: ((n['confidence'] ?? 0) as num).toDouble(),
            audioUrl: sc['url'] as String?,
            clip: a != null && b != null && b > a ? ((a - 1).clamp(0, double.infinity).toDouble(), b + 1) : null,
          ));
        }
        out.sort((x, y) => y.at.compareTo(x.at));
        return out;
      }
      final j = await _get('/api/v2/detections?species=${Uri.encodeQueryComponent(s.sci)}&numResults=4&includeWeather=true');
      final rows = j is List ? j : ((j is Map ? j['data'] : null) as List? ?? const []);
      final out = <StationRecording>[];
      for (final r in rows.take(4)) {
        if (r is! Map) continue;
        final day = DateTime.tryParse('${r['date']}') ?? DateTime.now();
        final at = stationTime(r['time'], day) ?? day;
        final w = (r['weather'] as Map?) ?? const {};
        final temp = (w['temperature'] as num?)?.round();
        final words = [
          if ((w['description'] ?? w['weatherMain']) != null) '${w['description'] ?? w['weatherMain']}',
          if (temp != null) '$temp°',
        ].join(', ');
        final id = r['id'];
        out.add(StationRecording(
          at: at,
          confidence: ((r['confidence'] ?? 0) as num).toDouble(),
          weather: words.isEmpty ? null : words,
          audioUrl: id != null && r['spectrogramOnly'] != true ? '$_base/api/v2/audio/$id' : null,
          spectrogramUrl: id != null ? '$_base/api/v2/spectrogram/$id?size=md' : null,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Family, order and how usual the bird is (BirdNET-Go only).
  Future<List<(String, String)>> particulars(StationSpecies s) async {
    if (_bw) return const [];
    try {
      final j = await _get('/api/v2/species?scientific_name=${Uri.encodeQueryComponent(s.sci)}');
      if (j is! Map) return const [];
      final t = (j['taxonomy'] as Map?) ?? const {};
      final fam = (t['family_common'] ?? t['familyCommon'] ?? '') as String, famSci = (t['family'] ?? '') as String;
      const rarity = {
        'very_common': 'Very common here at this season',
        'common': 'Common here at this season',
        'uncommon': 'Uncommon here at this season',
        'rare': 'Rare here at this season',
        'very_rare': 'Very rare here at this season',
      };
      final standing = rarity[(j['rarity'] as Map?)?['status']];
      return [
        if (fam.isNotEmpty || famSci.isNotEmpty)
          ('Family', fam.isNotEmpty && famSci.isNotEmpty ? '$fam ($famSci)' : (fam.isNotEmpty ? fam : famSci)),
        if ('${t['order'] ?? ''}'.isNotEmpty) ('Order', '${t['order']}'),
        if (standing != null) ('Standing', standing),
      ];
    } catch (_) {
      return const [];
    }
  }

  @visibleForTesting
  (DateTime, DateTime) get range => _range;
}
