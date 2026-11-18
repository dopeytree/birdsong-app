// The BirdNET-Go endpoints Birdsong's page reads, answered from detections
// heard on this device. Shapes follow what html/index.html parses and what
// birdsong's tools/bench.py already serves.

import '../store/detection_store.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String hms(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// Local time with its UTC offset, as BirdNET-Go stamps it.
String isoWithOffset(DateTime d) {
  final off = d.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final m = off.inMinutes.abs();
  return '${ymd(d)}T${hms(d)}$sign${_two(m ~/ 60)}:${_two(m % 60)}';
}

DateTime? _date(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return DateTime.parse(s.length == 10 ? '${s}T00:00:00' : s);
  } catch (_) {
    return null;
  }
}

bool _onOrAfter(DateTime t, DateTime? day) =>
    day == null || !t.isBefore(DateTime(day.year, day.month, day.day));

bool _onOrBefore(DateTime t, DateTime? day) =>
    day == null || t.isBefore(DateTime(day.year, day.month, day.day + 1));

Iterable<Detection> _between(List<Detection> all, DateTime? from, DateTime? to) =>
    all.where((d) => _onOrAfter(d.at, from) && _onOrBefore(d.at, to));

class _Agg {
  _Agg(this.sci, this.common);
  final String sci;
  String common;
  int count = 0;
  DateTime? first;
  DateTime? last;
  double max = 0;
  double sum = 0;
  final hours = List<int>.filled(24, 0);

  void add(Detection d) {
    count++;
    if (first == null || d.at.isBefore(first!)) first = d.at;
    if (last == null || d.at.isAfter(last!)) last = d.at;
    if (d.confidence > max) max = d.confidence;
    sum += d.confidence;
    hours[d.at.hour]++;
  }
}

List<_Agg> _aggregate(Iterable<Detection> ds) {
  final by = <String, _Agg>{};
  for (final d in ds) {
    (by[d.sci] ??= _Agg(d.sci, d.common)).add(d);
  }
  return by.values.toList()..sort((a, b) => b.count.compareTo(a.count));
}

/// GET /api/v2/analytics/species/daily?date=YYYY-MM-DD
List<Map<String, dynamic>> speciesDaily(List<Detection> all, String? date) {
  final day = _date(date) ?? DateTime.now();
  return [
    for (final a in _aggregate(_between(all, day, day)))
      {
        'scientific_name': a.sci,
        'common_name': a.common,
        'count': a.count,
        'hourly_counts': a.hours,
        'high_confidence': a.max >= 0.8,
        'max_confidence': a.max,
        // the daily endpoint gives the clock alone, with no date on it
        'first_heard': hms(a.first!),
        'latest_heard': hms(a.last!),
      },
  ];
}

/// GET /api/v2/analytics/species/summary[?start_date=&end_date=]
List<Map<String, dynamic>> speciesSummary(
    List<Detection> all, String? startDate, String? endDate) {
  final firstEver = <String, DateTime>{};
  for (final d in all) {
    final f = firstEver[d.sci];
    if (f == null || d.at.isBefore(f)) firstEver[d.sci] = d.at;
  }
  final now = DateTime.now();
  return [
    for (final a in _aggregate(_between(all, _date(startDate), _date(endDate))))
      {
        'scientific_name': a.sci,
        'common_name': a.common,
        'count': a.count,
        'first_heard': isoWithOffset(a.first!),
        'last_heard': isoWithOffset(a.last!),
        'avg_confidence': a.sum / a.count,
        'max_confidence': a.max,
        'days_since_first_seen': now.difference(firstEver[a.sci]!).inDays,
      },
  ];
}

/// GET /api/v2/analytics/time/distribution/hourly?species=&start_date=&end_date=
List<Map<String, dynamic>> hourly(
    List<Detection> all, String species, String? startDate, String? endDate) {
  final h = List<int>.filled(24, 0);
  for (final d in _between(all, _date(startDate), _date(endDate))) {
    if (d.sci == species) h[d.at.hour]++;
  }
  return [
    for (var i = 0; i < 24; i++) {'hour': i, 'count': h[i]},
  ];
}

/// GET /api/v2/analytics/time/daily?species=&start_date=&end_date=
Map<String, dynamic> daily(
    List<Detection> all, String species, String? startDate, String? endDate) {
  final by = <String, int>{};
  for (final d in _between(all, _date(startDate), _date(endDate))) {
    if (d.sci != species) continue;
    by[ymd(d.at)] = (by[ymd(d.at)] ?? 0) + 1;
  }
  final days = by.keys.toList()..sort();
  return {
    'data': [
      for (final k in days) {'date': k, 'count': by[k]},
    ],
  };
}

/// GET /api/v2/detections?species=&numResults=
List<Map<String, dynamic>> detections(List<Detection> all, String species, int limit) {
  final out = <Map<String, dynamic>>[];
  for (var i = all.length - 1; i >= 0 && out.length < limit; i--) {
    final d = all[i];
    if (d.sci != species) continue;
    out.add({
      'id': d.hasClip ? d.id : null,
      'scientificName': d.sci,
      'commonName': d.common,
      'date': ymd(d.at),
      'time': hms(d.at),
      'confidence': d.confidence,
      'model': d.model,
    });
  }
  return out;
}
