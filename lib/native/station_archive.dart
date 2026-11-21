import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../settings.dart' show Station;
import '../store/detection_store.dart';
import 'station_feed.dart';

/// What the calendar knows of one of a station's days.
class StationDay {
  const StationDay({required this.species, required this.calls, this.saved = false, this.complete = false});

  final int species;
  final int calls;

  /// Every call is kept in the day's folder.
  final bool saved;

  /// The day was over when it was asked for, so it won't change.
  final bool complete;

  Map<String, dynamic> toJson() => {
        'species': species,
        'calls': calls,
        if (saved) 'saved': true,
        if (complete) 'complete': true,
      };

  static StationDay fromJson(Map<String, dynamic> j) => StationDay(
        species: (j['species'] as num?)?.toInt() ?? 0,
        calls: (j['calls'] as num?)?.toInt() ?? 0,
        saved: j['saved'] == true,
        complete: j['complete'] == true,
      );
}

/// A remote station's days kept on the device, each as a session folder
/// like Listen's own (session.json and detections.jsonl, the same names and
/// fields), so they can be worked with later as the app's sessions are:
///
///     stations/<station>/station.json      the station, as saved
///     stations/<station>/days.json         each day's species and calls
///     stations/<station>/2026-11-21/       one day: session.json,
///                                          detections.jsonl
///
/// Recordings stay on the station: each call keeps a link to its own.
/// A day shown is kept first (today again as it fills, at most every ten
/// minutes); then, while the station is on show, the back days are filled
/// in one at a time, newest first, back to when its records begin.
class StationArchive extends ChangeNotifier {
  StationArchive(Directory root, this.feed)
      : dir = Directory('${root.path}/stations/${safeName(feed.station.id)}') {
    _ready = _open();
  }

  final StationFeed feed;
  final Directory dir;

  /// What is known of each day, by its date ("2026-11-21").
  final Map<String, StationDay> days = {};

  late final Future<void> _ready;
  bool _closed = false;
  bool _working = false;
  final List<DateTime> _wanted = [];
  final Map<String, DateTime> _keptAt = {};
  int _failures = 0;

  /// After a run of failures, no more asking until then.
  DateTime? _restUntil;

  /// The station can't list one day's calls (an older BirdNET-Go): only the
  /// calendar's counts are kept.
  bool unsupported = false;

  /// A station's id as a folder name.
  static String safeName(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  StationDay? dayOf(DateTime d) => days[ymd(d)];

  Future<void> _open() async {
    try {
      await dir.create(recursive: true);
      final f = File('${dir.path}/days.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          for (final e in j.entries) {
            if (e.value is Map) days['${e.key}'] = StationDay.fromJson(Map<String, dynamic>.from(e.value as Map));
          }
        }
      }
      await _write(File('${dir.path}/station.json'), const JsonEncoder.withIndent('  ').convert({
        ...feed.station.toJson(),
        'kind': feed.station.kind,
      }));
    } catch (e) {
      debugPrint('station archive: $e');
    }
    if (!_closed) notifyListeners();
  }

  void close() {
    _closed = true;
    dispose();
  }

  /// Write by way of a spare file, so a file is never left half written.
  static Future<void> _write(File f, String text) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
  }

  Future<void> _saveIndex() => _write(File('${dir.path}/days.json'),
      jsonEncode({for (final e in (days.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) e.key: e.value}));

  /// The calendar's month: how many species and calls each day not yet
  /// known, from the station's daily lists.
  Future<void> markMonth(DateTime month) async {
    await _ready;
    final today = _day(DateTime.now());
    final from = DateTime(month.year, month.month, 1);
    var to = DateTime(month.year, month.month + 1, 0);
    if (to.isAfter(today)) to = today;
    if (from.isAfter(to)) return;
    final missing = [
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
        if (days[ymd(d)] == null || (d == today && !(days[ymd(d)]!.saved))) d
    ];
    if (missing.isEmpty) return;
    try {
      final sums = await feed.daySums(missing.first, missing.last);
      if (_closed) return;
      for (final e in sums.entries) {
        final had = days[e.key];
        if (had != null && had.saved) continue;
        days[e.key] = StationDay(species: e.value.$1, calls: e.value.$2, complete: e.key != ymd(today));
      }
      await _saveIndex();
      if (!_closed) notifyListeners();
    } catch (e) {
      debugPrint('station archive, month: $e');
    }
  }

  /// Keep [d] soon, ahead of the back days.
  void want(DateTime d) {
    final day = _day(d);
    final at = _keptAt[ymd(day)];
    if (at != null && DateTime.now().difference(at) < const Duration(minutes: 10)) return;
    if (!_wanted.contains(day)) _wanted.add(day);
    fill();
  }

  /// Keep the days wanted, then the back days, one at a time.
  Future<void> fill() async {
    if (_working || _closed || unsupported) return;
    final rest = _restUntil;
    if (rest != null && DateTime.now().isBefore(rest)) return;
    _working = true;
    try {
      await _ready;
      while (!_closed) {
        final d = _wanted.isNotEmpty ? _wanted.removeAt(0) : _nextBackDay();
        if (d == null) break;
        try {
          await _keep(d);
          _failures = 0;
        } catch (e) {
          debugPrint('station archive, ${ymd(d)}: $e');
          if ('$e'.contains("can't list")) {
            unsupported = true;
            break;
          }
          // try again in a while; after a run of failures, rest ten minutes
          if (++_failures >= 3) {
            _failures = 0;
            _restUntil = DateTime.now().add(const Duration(minutes: 10));
            break;
          }
          await Future<void>.delayed(const Duration(seconds: 20));
        }
        // a pause between days, to go easy on the station
        await Future<void>.delayed(Duration(milliseconds: feed.station.isBirdWeather ? 3000 : 1200));
      }
    } finally {
      _working = false;
    }
  }

  /// The newest past day not yet kept, back to when the station's records
  /// begin (as far as it has said); days known to be empty are kept without
  /// asking.
  DateTime? _nextBackDay() {
    final today = _day(DateTime.now());
    final since = feed.since == null ? today.subtract(const Duration(days: 365)) : _day(feed.since!);
    for (var d = today.subtract(const Duration(days: 1)); !d.isBefore(since); d = d.subtract(const Duration(days: 1))) {
      final k = days[ymd(d)];
      if (k == null || !k.saved || !k.complete) return d;
    }
    return null;
  }

  /// Ask for [d]'s every call and keep them as a session folder.
  Future<void> _keep(DateTime d) async {
    final today = _day(DateTime.now());
    final key = ymd(d);
    final known = days[key];
    if (known != null && known.saved && known.complete) return;
    final complete = d.isBefore(today);
    // a day known to be empty: nothing to ask for
    if (known != null && known.complete && known.calls == 0) {
      days[key] = const StationDay(species: 0, calls: 0, saved: true, complete: true);
      await _saveIndex();
      return;
    }
    final calls = await feed.callsOn(d);
    if (_closed) return;
    final weather = await feed.weatherOn(d);
    final folder = Directory('${dir.path}/$key');
    await folder.create(recursive: true);
    final old = File('${folder.path}/session.json');
    String? uuid;
    if (await old.exists()) {
      try {
        uuid = (jsonDecode(await old.readAsString()) as Map)['uuid'] as String?;
      } catch (_) {}
    }
    final session = stationSessionJson(feed.station, feed.place, d, calls, uuid: uuid ?? newUuid(), complete: complete, weather: weather);
    await _write(File('${folder.path}/detections.jsonl'),
        calls.map((c) => jsonEncode(stationCallJson(feed.station, c))).join('\n') + (calls.isEmpty ? '' : '\n'));
    await _write(old, const JsonEncoder.withIndent('  ').convert(session));
    days[key] = StationDay(
        species: {for (final c in calls) c.sci}.length, calls: calls.length, saved: true, complete: complete);
    _keptAt[key] = DateTime.now();
    await _saveIndex();
    if (!_closed) notifyListeners();
  }
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
String _utc(DateTime t) => t.toUtc().toIso8601String();

/// A station's day as a session.json: Listen's fields (session.toJson in
/// detection_store.dart), with the station it came from and the day.
Map<String, dynamic> stationSessionJson(Station st, (double, double)? p, DateTime d, List<StationCall> calls,
    {required String uuid, required bool complete, Map<String, dynamic>? weather}) {
  final start = calls.isEmpty ? d : calls.first.at;
  final end = calls.isEmpty ? d.add(const Duration(days: 1)) : calls.last.at;
  return {
    'schemaVersion': sessionSchemaVersion,
    'app': {'name': 'Birdsong', 'platform': Platform.operatingSystem},
    'id': d.year * 10000 + d.month * 100 + d.day,
    'uuid': uuid,
    'startTime': _utc(start),
    'endTime': _utc(end),
    'utcOffsetMinutes': d.timeZoneOffset.inMinutes,
    if (p != null) 'latitude': p.$1,
    if (p != null) 'longitude': p.$2,
    if (p != null) 'locationSource': 'station',
    'station': {
      'id': st.id,
      'name': st.name,
      'kind': st.kind,
      if (st.isBirdWeather) 'birdweather': st.birdweather else 'birdnetUrl': st.birdnetUrl,
    },
    'day': ymd(d),
    'complete': complete,
    if (weather != null) 'weather': weather,
    'summary': {
      'detections': calls.length,
      'species': {for (final c in calls) c.sci}.length,
    },
  };
}

/// One call as a line of detections.jsonl: Listen's fields (Detection.toJson),
/// with the station's own number and links to its recording.
Map<String, dynamic> stationCallJson(Station st, StationCall c) => {
      ...Detection(
        id: c.id,
        model: st.isBirdWeather ? 'BirdWeather' : 'BirdNET-Go',
        sci: c.sci,
        common: c.common,
        confidence: c.confidence,
        at: c.at,
        reviewStatus: switch (c.verified) {
          'correct' => 'correct',
          'false_positive' => 'wrong',
          _ => 'unreviewed',
        },
      ).toJson(),
      'stationDetectionId': c.id,
      if (c.audioUrl != null) 'audioUrl': c.audioUrl,
      if (c.spectrogramUrl != null) 'spectrogramUrl': c.spectrogramUrl,
      if (c.clip != null) 'clipStart': c.clip!.$1,
      if (c.clip != null) 'clipEnd': c.clip!.$2,
    };
