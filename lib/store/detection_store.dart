import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class Detection {
  Detection({
    required this.id,
    required this.model,
    required this.sci,
    required this.common,
    required this.confidence,
    required this.at,
    this.hasClip = false,
  });

  final int id;
  final String model;
  final String sci;
  final String common;
  double confidence;
  final DateTime at;
  bool hasClip;

  Map<String, dynamic> toJson() => {
        'id': id,
        'model': model,
        'sci': sci,
        'common': common,
        'confidence': confidence,
        'at': at.toIso8601String(),
        'clip': hasClip,
      };

  static Detection fromJson(Map<String, dynamic> j) => Detection(
        id: j['id'] as int,
        model: j['model'] as String,
        sci: j['sci'] as String,
        common: j['common'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        at: DateTime.parse(j['at'] as String),
        hasClip: (j['clip'] as bool?) ?? false,
      );
}

/// One stretch of listening, from Start to Stop, and where it happened.
/// A detection belongs to the session whose time span holds it.
class Session {
  Session({required this.id, required this.start, this.end, this.lat, this.lon});

  final int id;
  final DateTime start;

  /// Null while still listening.
  DateTime? end;

  double? lat;
  double? lon;

  bool get live => end == null;
  bool get hasPlace => lat != null && lon != null;

  bool contains(DateTime t) => !t.isBefore(start) && (end == null || !t.isAfter(end!));

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'lat': lat,
        'lon': lon,
      };

  static Session fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as int,
        start: DateTime.parse(j['start'] as String),
        end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
      );
}

/// Detections heard before sessions existed are grouped into sessions
/// wherever the gap between two calls exceeds this.
const legacySessionGap = Duration(minutes: 30);

/// Split detections (oldest first) into time spans at gaps longer than [gap].
List<(DateTime, DateTime)> groupIntoSpans(List<DateTime> times, Duration gap) {
  final spans = <(DateTime, DateTime)>[];
  DateTime? from, to;
  for (final t in times) {
    if (to != null && t.difference(to) > gap) {
      spans.add((from!, to));
      from = null;
    }
    from ??= t;
    to = t;
  }
  if (from != null) spans.add((from, to!));
  return spans;
}

/// Detections heard on this device, kept in memory and appended to a JSON
/// lines file, with the listening sessions beside them. Plenty for a test
/// build; a release would use SQLite.
class DetectionStore extends ChangeNotifier {
  DetectionStore._(this.dir);

  final Directory dir;
  final List<Detection> all = [];
  int _nextId = 1;

  /// Oldest first.
  final List<Session> sessions = [];
  int _nextSessionId = 1;
  int? _selectedId;

  File get _log => File('${dir.path}/detections.jsonl');
  File get _sessionLog => File('${dir.path}/sessions.jsonl');
  Directory get clips => Directory('${dir.path}/clips');

  static Future<DetectionStore> open(Directory dir) async {
    final s = DetectionStore._(dir);
    await s.clips.create(recursive: true);
    if (await s._log.exists()) {
      final byId = <int, Detection>{};
      for (final line in await s._log.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final d = Detection.fromJson(jsonDecode(line) as Map<String, dynamic>);
          byId[d.id] = d; // a later line for the same id is an update
        } catch (_) {}
      }
      s.all.addAll(byId.values.toList()..sort((a, b) => a.at.compareTo(b.at)));
      if (s.all.isNotEmpty) {
        s._nextId = s.all.map((d) => d.id).reduce((a, b) => a > b ? a : b) + 1;
      }
    }
    await s._loadSessions();
    return s;
  }

  Future<void> _loadSessions() async {
    final byId = <int, Session?>{};
    if (await _sessionLog.exists()) {
      for (final line in await _sessionLog.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          final id = j['id'] as int;
          byId[id] = j['deleted'] == true ? null : Session.fromJson(j);
          if (id >= _nextSessionId) _nextSessionId = id + 1;
        } catch (_) {}
      }
    }
    sessions.addAll(byId.values.whereType<Session>().toList()
      ..sort((a, b) => a.start.compareTo(b.start)));

    // A session left open by a crash or a force-quit ends at its last call.
    for (final ses in sessions.where((x) => x.live).toList()) {
      final inside = all.where((d) => ses.contains(d.at));
      ses.end = inside.isEmpty ? ses.start : inside.last.at;
      await _appendSession(ses);
    }

    // Detections from before sessions existed: one session per stretch.
    final loose = [for (final d in all) if (!sessions.any((x) => x.contains(d.at))) d.at];
    for (final (from, to) in groupIntoSpans(loose, legacySessionGap)) {
      final ses = Session(id: _nextSessionId++, start: from, end: to);
      sessions.add(ses);
      await _appendSession(ses);
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));
  }

  Future<void> _appendSession(Session x) => _sessionLog
      .writeAsString('${jsonEncode(x.toJson())}\n', mode: FileMode.append, flush: true);

  // ---- sessions -------------------------------------------------------------

  /// The session the plate shows: the one picked with the arrows, else the
  /// latest.
  Session? get selected {
    if (sessions.isEmpty) return null;
    for (final x in sessions) {
      if (x.id == _selectedId) return x;
    }
    return sessions.last;
  }

  int get selectedIndex {
    final sel = selected;
    return sel == null ? -1 : sessions.indexOf(sel);
  }

  Session? get liveSession => sessions.isNotEmpty && sessions.last.live ? sessions.last : null;

  /// Move the plate [delta] sessions back (-1) or on (+1).
  void step(int delta) {
    final i = selectedIndex;
    if (i < 0) return;
    final j = (i + delta).clamp(0, sessions.length - 1).toInt();
    if (j == i) return;
    _selectedId = sessions[j].id;
    notifyListeners();
  }

  Future<Session> startSession({DateTime? at, double? lat, double? lon}) async {
    final x = Session(id: _nextSessionId++, start: at ?? DateTime.now(), lat: lat, lon: lon);
    sessions.add(x);
    _selectedId = x.id;
    await _appendSession(x);
    notifyListeners();
    return x;
  }

  /// Close a session. One that heard nothing and lasted under a minute is
  /// dropped, so a mistaken tap on the microphone leaves no trace.
  Future<void> endSession(Session x, {DateTime? at}) async {
    x.end = at ?? DateTime.now();
    final heard = all.any((d) => x.contains(d.at));
    if (!heard && x.end!.difference(x.start) < const Duration(minutes: 1)) {
      sessions.remove(x);
      if (_selectedId == x.id) _selectedId = null;
      await _sessionLog.writeAsString('${jsonEncode({'id': x.id, 'deleted': true})}\n',
          mode: FileMode.append, flush: true);
    } else {
      await _appendSession(x);
    }
    notifyListeners();
  }

  Future<void> saveSession(Session x) async {
    await _appendSession(x);
    notifyListeners();
  }

  List<Detection> inSession(Session x) => all.where((d) => x.contains(d.at)).toList();

  // ---- detections -----------------------------------------------------------

  Future<Detection> add({
    required String model,
    required String sci,
    required String common,
    required double confidence,
    required DateTime at,
  }) async {
    final d = Detection(
        id: _nextId++, model: model, sci: sci, common: common, confidence: confidence, at: at);
    all.add(d);
    await _append(d);
    notifyListeners();
    return d;
  }

  /// Record a change to a detection already stored (a clip saved, a higher
  /// confidence on a repeated call).
  Future<void> save(Detection d) async {
    await _append(d);
    notifyListeners();
  }

  Future<void> _append(Detection d) =>
      _log.writeAsString('${jsonEncode(d.toJson())}\n', mode: FileMode.append, flush: true);

  File clipFile(int id) => File('${clips.path}/$id.wav');
  File spectrogramFile(int id) => File('${clips.path}/$id.bmp');

  Detection? byId(int id) {
    for (var i = all.length - 1; i >= 0; i--) {
      if (all[i].id == id) return all[i];
    }
    return null;
  }

  /// What the plate draws: one model's detections, or every model's, from
  /// one session when given.
  List<Detection> forPlate(String plateModel, {Session? session}) => all
      .where((d) =>
          (plateModel == 'all' || d.model == plateModel) &&
          (session == null || session.contains(d.at)))
      .toList();

  Future<void> clear() async {
    all.clear();
    sessions.removeWhere((x) => !x.live);
    _selectedId = null;
    if (await _log.exists()) await _log.delete();
    if (await _sessionLog.exists()) await _sessionLog.delete();
    for (final x in sessions) {
      await _appendSession(x);
    }
    if (await clips.exists()) await clips.delete(recursive: true);
    await clips.create(recursive: true);
    notifyListeners();
  }
}
