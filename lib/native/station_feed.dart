import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../settings.dart';

/// A remote station's plate: what it heard over a period, or on one day,
/// asked of BirdNET-Go (its /api/v2) or of a public BirdWeather station
/// (its GraphQL), as the web plate asks them (assets/web/index.html,
/// fetchSpecies, fetchSpeciesBW, loadExtras). Asked again every minute.

/// The four periods of the web plate.
enum Span {
  today('Today'),
  week('Seven days'),
  month('Thirty days'),
  all('Since records began');

  const Span(this.label);
  final String label;
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

String _two(int n) => n.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

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
  StationFeed(this.station) {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => load(quiet: true));
    load();
  }

  final Station station;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  Timer? _timer;

  /// The period shown, or [day] when one day is.
  Span span = Span.week;
  DateTime? day;

  List<StationSpecies>? species;
  String? error;
  bool loading = false;

  /// When the station's records begin (BirdWeather says; BirdNET-Go is
  /// taken as a year back until it says otherwise), and its time zone.
  DateTime? since;
  String? timezone;

  /// Where the station is, when it says.
  (double, double)? place;

  bool get _bw => station.isBirdWeather;
  String get _bwId => station.birdweather.replaceAll(RegExp(r'\D'), '');

  int _run = 0;

  @override
  void dispose() {
    _timer?.cancel();
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
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}${d.year == today.year ? '' : ' ${d.year}'}';
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
      final got = _bw ? await _speciesBW() : await _speciesGo();
      if (run != _run) return;
      species = got;
      error = null;
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
    final Object? j;
    if (from == to) {
      j = await _get('/api/v2/analytics/species/daily?date=${ymd(from)}');
    } else if (day == null && span == Span.all) {
      j = await _get('/api/v2/analytics/species/summary');
    } else {
      j = await _get('/api/v2/analytics/species/summary?start_date=${ymd(from)}&end_date=${ymd(to)}');
    }
    final rows = birdnetRows(j, from == to ? from : today);
    // how far back the station goes: its longest-known species
    if (since == null && rows.isNotEmpty) {
      final known = rows.map((r) => r.daysKnown).reduce((a, b) => a > b ? a : b);
      if (known > 0) since = today.subtract(Duration(days: known));
    }
    _placeGo();
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
