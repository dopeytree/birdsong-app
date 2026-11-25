import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// The version of the session folder format written here. Bump it, and add
/// a step to [DetectionStore._upgrade], when a file's meaning changes.
const sessionSchemaVersion = 1;

/// A fresh random UUID (version 4).
String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) =>
      b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

String _utc(DateTime t) => t.toUtc().toIso8601String();
DateTime _local(String s) => DateTime.parse(s).toLocal();

/// One runner-up a model gave for the same window.
typedef RankedScore = ({String sci, double confidence});

class Detection {
  Detection({
    required this.id,
    required this.model,
    required this.sci,
    required this.common,
    required this.confidence,
    required this.at,
    String? uuid,
    this.windowSeconds,
    this.scores = const [],
    this.hasClip = false,
    this.clipExt = 'wav',
    this.reviewStatus = 'unreviewed',
    this.lat,
    this.lon,
  }) : uuid = uuid ?? newUuid();

  /// Short local id, used in the plate's URLs (`/api/v2/audio/<id>`).
  final int id;
  final String uuid;
  final String model;
  final String sci;
  final String common;
  double confidence;
  /// When it was heard: the end of the window the model listened to.
  final DateTime at;

  /// How long that window was, so it began [windowSeconds] before [at].
  double? windowSeconds;

  /// The model's best scores for that window, highest first (top 5).
  List<RankedScore> scores;
  bool hasClip;

  /// Audio clip file extension ('m4a' or 'wav').
  String clipExt;

  /// unreviewed, correct, wrong or unsure.
  String reviewStatus;

  /// Where it was heard: the phone's latest position fix at the time, for
  /// the map. Null when location was off or no fix had come in yet.
  double? lat;
  double? lon;
  bool get hasPlace => lat != null && lon != null;

  String get clipPath => 'audio/$id.$clipExt';
  String get spectrogramPath => 'spectrograms/$id.bmp';

  /// One line of detections.jsonl. Field names follow BirdNET Live's export.
  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'timestamp': _utc(at),
        if (windowSeconds != null) 'windowSeconds': windowSeconds,
        'scientificName': sci,
        'commonName': common,
        'confidence': double.parse(confidence.toStringAsFixed(4)),
        'model': model,
        if (scores.isNotEmpty)
          'scores': [
            for (final s in scores)
              {'scientificName': s.sci, 'confidence': double.parse(s.confidence.toStringAsFixed(4))}
          ],
        'reviewStatus': reviewStatus,
        if (lat != null) 'latitude': lat,
        if (lon != null) 'longitude': lon,
        if (hasClip) 'clip': clipPath,
        if (hasClip) 'spectrogram': spectrogramPath,
      };

  static Detection fromJson(Map<String, dynamic> j) => Detection(
        id: j['id'] as int,
        uuid: j['uuid'] as String?,
        model: j['model'] as String,
        sci: j['scientificName'] as String,
        common: j['commonName'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        at: _local(j['timestamp'] as String),
        windowSeconds: (j['windowSeconds'] as num?)?.toDouble(),
        scores: [
          for (final s in (j['scores'] as List? ?? const []))
            (
              sci: (s as Map)['scientificName'] as String,
              confidence: (s['confidence'] as num).toDouble()
            )
        ],
        hasClip: j['clip'] != null,
        clipExt: (j['clip'] as String?)?.endsWith('.m4a') == true ? 'm4a' : 'wav',
        reviewStatus: (j['reviewStatus'] as String?) ?? 'unreviewed',
        lat: (j['latitude'] as num?)?.toDouble(),
        lon: (j['longitude'] as num?)?.toDouble(),
      );

  /// A line from the old detections.jsonl (before session folders).
  static Detection fromLegacyJson(Map<String, dynamic> j) => Detection(
        id: j['id'] as int,
        model: j['model'] as String,
        sci: j['sci'] as String,
        common: j['common'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        at: DateTime.parse(j['at'] as String),
        hasClip: (j['clip'] as bool?) ?? false,
      );
}

/// One position fix on the way, for the map's trail. A line of track.jsonl.
class TrackPoint {
  const TrackPoint({required this.at, required this.lat, required this.lon, this.accuracy});

  final DateTime at;
  final double lat;
  final double lon;

  /// Horizontal accuracy in metres, as the phone reported it.
  final double? accuracy;

  Map<String, dynamic> toJson() => {
        'timestamp': _utc(at),
        'latitude': double.parse(lat.toStringAsFixed(6)),
        'longitude': double.parse(lon.toStringAsFixed(6)),
        if (accuracy != null) 'accuracy': double.parse(accuracy!.toStringAsFixed(1)),
      };

  static TrackPoint fromJson(Map<String, dynamic> j) => TrackPoint(
        at: _local(j['timestamp'] as String),
        lat: (j['latitude'] as num).toDouble(),
        lon: (j['longitude'] as num).toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
      );
}

/// One stretch of listening, from Start to Stop, and where it happened.
/// A detection belongs to the session whose time span holds it. On disk a
/// session is a folder: session.json, detections.jsonl, audio/,
/// spectrograms/.
class Session {
  Session({
    required this.id,
    required this.start,
    this.end,
    this.lat,
    this.lon,
    String? uuid,
    int? utcOffsetMinutes,
    this.stopReason,
    this.settings = const {},
    this.models = const [],
    this.weather,
    this.folder,
    this.locationSource,
    this.placeName,
    this.placeArea,
  })  : uuid = uuid ?? newUuid(),
        utcOffsetMinutes = utcOffsetMinutes ?? start.timeZoneOffset.inMinutes;

  /// Short local id, for the plate's arrows.
  final int id;
  final String uuid;
  final DateTime start;

  /// Null while still listening.
  DateTime? end;

  /// The clock's offset from UTC where and when the session began.
  final int utcOffsetMinutes;

  double? lat;
  double? lon;

  /// Where [lat] and [lon] came from: gps, or settings (typed in by hand).
  String? locationSource;

  /// manual, speciesLimit, interrupted or legacy.
  String? stopReason;

  /// The listening settings in force (threshold, hop, repeat, filters).
  Map<String, dynamic> settings;

  /// The models listening: id, name, licence, sample rate, window.
  List<Map<String, dynamic>> models;

  /// Conditions when the session began; see engine/weather.dart.
  Map<String, dynamic>? weather;

  /// The nearest town or village (engine/place_names.dart), '' when there
  /// is none; null until looked up.
  String? placeName;

  /// Where the walk went, after [placeName] in the calendar: the reserve,
  /// wood or heath it was most in (native/walk_names.dart), '' when none;
  /// null until looked up, once the session has ended.
  String? placeArea;

  /// Folder name under sessions/, set when first written.
  String? folder;

  /// Where the phone went while listening, oldest first (track.jsonl).
  /// Recorded about every 30 seconds while moving, and at each detection.
  final List<TrackPoint> track = [];

  bool get live => end == null;
  bool get hasPlace => lat != null && lon != null;

  /// An open session runs to now (with a minute's grace), so a walk dated in
  /// the future (a test or promo copy) never leaks into the live one.
  bool contains(DateTime t) =>
      !t.isBefore(start) &&
      !t.isAfter(end ?? DateTime.now().add(const Duration(minutes: 1)));

  /// "2026-11-18T2219Z_a91e4c": the start in UTC and the start of the UUID,
  /// so folders sort by time and never collide.
  String get folderName {
    final u = start.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z'
        '_${uuid.substring(0, 6)}';
  }

  Map<String, dynamic> toJson(List<Detection> inside) => {
        'schemaVersion': sessionSchemaVersion,
        'app': {
          'name': 'Birdsong',
          'platform': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
        },
        'id': id,
        'uuid': uuid,
        'startTime': _utc(start),
        'endTime': end == null ? null : _utc(end!),
        'utcOffsetMinutes': utcOffsetMinutes,
        if (lat != null) 'latitude': lat,
        if (lon != null) 'longitude': lon,
        if (locationSource != null) 'locationSource': locationSource,
        if (stopReason != null) 'stopReason': stopReason,
        // When the microphone was on. One span for now; pauses would add more.
        'listening': [
          {'startTime': _utc(start), 'endTime': end == null ? null : _utc(end!)}
        ],
        if (settings.isNotEmpty) 'settings': settings,
        if (models.isNotEmpty) 'models': models,
        if (weather != null) 'weather': weather,
        if (placeName != null) 'placeName': placeName,
        if (placeArea != null) 'placeArea': placeArea,
        if (placeArea != null) 'placeAreaRule': placeAreaRule,
        'summary': {
          'detections': inside.length,
          'species': {for (final d in inside) d.sci}.length,
          if (track.isNotEmpty) 'trackPoints': track.length,
        },
      };

  static Session fromJson(Map<String, dynamic> j, String folder) => Session(
        id: j['id'] as int,
        uuid: j['uuid'] as String?,
        start: _local(j['startTime'] as String),
        end: j['endTime'] == null ? null : _local(j['endTime'] as String),
        utcOffsetMinutes: j['utcOffsetMinutes'] as int?,
        lat: (j['latitude'] as num?)?.toDouble(),
        lon: (j['longitude'] as num?)?.toDouble(),
        locationSource: j['locationSource'] as String?,
        stopReason: j['stopReason'] as String?,
        settings: Map<String, dynamic>.from(j['settings'] as Map? ?? const {}),
        models: [
          for (final m in (j['models'] as List? ?? const []))
            Map<String, dynamic>.from(m as Map)
        ],
        weather: j['weather'] == null ? null : Map<String, dynamic>.from(j['weather'] as Map),
        folder: folder,
        placeName: j['placeName'] as String?,
        // named under an older rule: asked again
        placeArea: j['placeAreaRule'] == placeAreaRule ? j['placeArea'] as String? : null,
      );

  /// Bumped when the way walks are named changes, so saved names are
  /// worked out again. 2: OS names only within 0.5 km (22 Nov).
  static const placeAreaRule = 2;

  /// A line from the old sessions.jsonl.
  static Session fromLegacyJson(Map<String, dynamic> j) => Session(
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

/// Write [text] to [file] safely: to a .pending file first, then renamed
/// over the old one, so a crash mid-write never leaves half a file.
Future<void> _writeAtomic(File file, String text) async {
  final pending = File('${file.path}.pending');
  await pending.writeAsString(text, flush: true);
  await pending.rename(file.path);
}

/// The listening sessions and their detections, one folder per session:
///
///   sessions/2026-11-18T221904Z_a91e4c/
///     session.json        the session (see [Session.toJson])
///     detections.jsonl    one detection per line (see [Detection.toJson])
///     track.jsonl         position fixes on the way (see [TrackPoint]), if any
///     `audio/<id>.wav`      the clip around each detection
///     `spectrograms/<id>.bmp`
///
/// Everything is held in memory too. A session's files are rewritten as a
/// whole, shortly after a change and at once when it ends.
class DetectionStore extends ChangeNotifier {
  DetectionStore._(this.root);

  /// The app's data folder; sessions live in [sessionsDir] inside it.
  final Directory root;
  Directory get sessionsDir => Directory('${root.path}/sessions');

  /// Before session folders: detections/detections.jsonl and sessions.jsonl.
  Directory get _legacyDir => Directory('${root.path}/detections');

  final List<Detection> all = [];
  int _nextId = 1;

  /// Oldest first.
  final List<Session> sessions = [];
  int _nextSessionId = 1;
  int? _selectedId;

  final Set<Session> _dirty = {};
  Timer? _flushTimer;

  static Future<DetectionStore> open(Directory root) async {
    final s = DetectionStore._(root);
    await s.sessionsDir.create(recursive: true);
    await s._load();
    await s._migrateLegacy();
    await s._closeInterrupted();
    s.sessions.sort((a, b) => a.start.compareTo(b.start));
    s.all.sort((a, b) => a.at.compareTo(b.at));
    return s;
  }

  Directory dirOf(Session x) => Directory('${sessionsDir.path}/${x.folder ??= x.folderName}');

  Future<void> _load() async {
    await for (final e in sessionsDir.list()) {
      if (e is! Directory) continue;
      final file = File('${e.path}/session.json');
      if (!await file.exists()) continue;
      try {
        final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final x = Session.fromJson(_upgrade(j), e.uri.pathSegments.where((p) => p.isNotEmpty).last);
        sessions.add(x);
        _nextSessionId = max(_nextSessionId, x.id + 1);
        final lines = File('${e.path}/detections.jsonl');
        if (await lines.exists()) {
          for (final line in await lines.readAsLines()) {
            if (line.trim().isEmpty) continue;
            try {
              final d = Detection.fromJson(jsonDecode(line) as Map<String, dynamic>);
              all.add(d);
              _nextId = max(_nextId, d.id + 1);
            } catch (_) {}
          }
        }
        final track = File('${e.path}/track.jsonl');
        if (await track.exists()) {
          for (final line in await track.readAsLines()) {
            if (line.trim().isEmpty) continue;
            try {
              x.track.add(TrackPoint.fromJson(jsonDecode(line) as Map<String, dynamic>));
            } catch (_) {}
          }
          x.track.sort((a, b) => a.at.compareTo(b.at));
        }
      } catch (e) {
        debugPrint('session ${file.path}: $e');
      }
    }
  }

  /// Bring an older session.json up to [sessionSchemaVersion].
  Map<String, dynamic> _upgrade(Map<String, dynamic> j) {
    // Version 1 is the first; later versions add steps here.
    return j;
  }

  /// A session left open by a crash or a force-quit ends at its last call.
  Future<void> _closeInterrupted() async {
    for (final x in sessions.where((x) => x.live).toList()) {
      final inside = inSession(x);
      if (inside.isEmpty) {
        // Nothing heard before the app stopped: leave no empty folder.
        sessions.remove(x);
        final dir = dirOf(x);
        if (await dir.exists()) await dir.delete(recursive: true);
        continue;
      }
      x.end = inside.last.at;
      x.stopReason = 'interrupted';
      await _write(x);
    }
  }

  /// Move the old single-file logs into session folders, once. The old
  /// files are kept, renamed *.migrated, as a backup.
  Future<void> _migrateLegacy() async {
    final log = File('${_legacyDir.path}/detections.jsonl');
    final sesLog = File('${_legacyDir.path}/sessions.jsonl');
    if (!await log.exists() && !await sesLog.exists()) return;

    final byId = <int, Detection>{};
    if (await log.exists()) {
      for (final line in await log.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final d = Detection.fromLegacyJson(jsonDecode(line) as Map<String, dynamic>);
          byId[d.id] = d; // a later line for the same id is an update
        } catch (_) {}
      }
    }
    final old = byId.values.toList()..sort((a, b) => a.at.compareTo(b.at));

    final sesById = <int, Session?>{};
    if (await sesLog.exists()) {
      for (final line in await sesLog.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          final id = j['id'] as int;
          sesById[id] = j['deleted'] == true ? null : Session.fromLegacyJson(j);
        } catch (_) {}
      }
    }
    final oldSessions = sesById.values.whereType<Session>().toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final x in oldSessions.where((x) => x.live)) {
      final inside = old.where((d) => x.contains(d.at));
      x.end = inside.isEmpty ? x.start : inside.last.at;
    }
    // Detections from before sessions existed: one session per stretch.
    final loose = [for (final d in old) if (!oldSessions.any((x) => x.contains(d.at))) d.at];
    for (final (from, to) in groupIntoSpans(loose, legacySessionGap)) {
      oldSessions.add(Session(id: 0, start: from, end: to));
    }
    oldSessions.sort((a, b) => a.start.compareTo(b.start));

    // Renumber after anything already in folders, so ids stay unique.
    final idMap = <int, int>{};
    for (final x in oldSessions) {
      // Already moved by a run that stopped part way: keep that one.
      if (sessions.any((s) => s.stopReason == 'legacy' && s.start.isAtSameMomentAs(x.start))) {
        continue;
      }
      final moved = Session(
        id: _nextSessionId++,
        start: x.start,
        end: x.end,
        lat: x.lat,
        lon: x.lon,
        stopReason: 'legacy',
      );
      sessions.add(moved);
      final dir = dirOf(moved);
      await Directory('${dir.path}/audio').create(recursive: true);
      await Directory('${dir.path}/spectrograms').create(recursive: true);
      for (final d in old.where((d) => moved.contains(d.at))) {
        final n = idMap[d.id] ??= _nextId++;
        final nd = Detection(
            id: n, model: d.model, sci: d.sci, common: d.common, confidence: d.confidence, at: d.at);
        for (final (from, to) in [
          (File('${_legacyDir.path}/clips/${d.id}.wav'), File('${dir.path}/${nd.clipPath}')),
          (File('${_legacyDir.path}/clips/${d.id}.bmp'), File('${dir.path}/${nd.spectrogramPath}')),
        ]) {
          if (await from.exists()) {
            await from.rename(to.path);
            if (to.path.endsWith('.wav')) nd.hasClip = true;
          }
        }
        all.add(nd);
      }
      await _write(moved);
    }
    if (await log.exists()) await log.rename('${log.path}.migrated');
    if (await sesLog.exists()) await sesLog.rename('${sesLog.path}.migrated');
    debugPrint('Moved ${old.length} detections into ${oldSessions.length} session folders');
  }

  // ---- writing --------------------------------------------------------------

  Future<void> _write(Session x) async {
    final dir = dirOf(x);
    await dir.create(recursive: true);
    final inside = inSession(x);
    await _writeAtomic(File('${dir.path}/detections.jsonl'),
        inside.map((d) => '${jsonEncode(d.toJson())}\n').join());
    if (x.track.isNotEmpty) {
      await _writeAtomic(File('${dir.path}/track.jsonl'),
          x.track.map((p) => '${jsonEncode(p.toJson())}\n').join());
    }
    await _writeAtomic(File('${dir.path}/session.json'),
        const JsonEncoder.withIndent('  ').convert(x.toJson(inside)));
  }

  /// Write a session soon; changes within the next second share one write.
  void _touch(Session x) {
    _dirty.add(x);
    _flushTimer ??= Timer(const Duration(seconds: 1), () => unawaited(flush()));
  }

  /// Write every changed session now.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final todo = _dirty.toList();
    _dirty.clear();
    for (final x in todo) {
      if (sessions.contains(x)) await _write(x);
    }
  }

  // ---- sessions -------------------------------------------------------------

  /// The session the plate shows: the one picked with the arrows, else the
  /// latest that has begun (not one dated in the future).
  Session? get selected {
    if (sessions.isEmpty) return null;
    for (final x in sessions) {
      if (x.id == _selectedId) return x;
    }
    final now = DateTime.now();
    return liveSession ??
        sessions.lastWhere((x) => !x.start.isAfter(now), orElse: () => sessions.last);
  }

  int get selectedIndex {
    final sel = selected;
    return sel == null ? -1 : sessions.indexOf(sel);
  }

  /// The open session, wherever it sorts (a future-dated walk may follow it).
  Session? get liveSession {
    for (final x in sessions.reversed) {
      if (x.live) return x;
    }
    return null;
  }

  /// Move the plate [delta] sessions back (-1) or on (+1).
  void step(int delta) {
    final i = selectedIndex;
    if (i < 0) return;
    final j = (i + delta).clamp(0, sessions.length - 1).toInt();
    if (j == i) return;
    _selectedId = sessions[j].id;
    notifyListeners();
  }

  /// Show [x] on the plate (the calendar's choice).
  void select(Session x) {
    if (x.id == _selectedId || !sessions.contains(x)) return;
    _selectedId = x.id;
    notifyListeners();
  }

  Future<Session> startSession({
    DateTime? at,
    double? lat,
    double? lon,
    Map<String, dynamic> settings = const {},
    List<Map<String, dynamic>> models = const [],
  }) async {
    final x = Session(
        id: _nextSessionId++,
        start: at ?? DateTime.now(),
        lat: lat,
        lon: lon,
        settings: settings,
        models: models);
    sessions
      ..add(x)
      ..sort((a, b) => a.start.compareTo(b.start)); // same order as after a relaunch
    _selectedId = x.id;
    await _write(x);
    notifyListeners();
    return x;
  }

  /// Close a session. One that heard nothing is dropped, folder and all, so
  /// empty recordings never clutter the calendar.
  Future<void> endSession(Session x, {DateTime? at, String reason = 'manual'}) async {
    x.end = at ?? DateTime.now();
    x.stopReason = reason;
    final heard = all.any((d) => x.contains(d.at));
    if (!heard) {
      sessions.remove(x);
      _dirty.remove(x);
      if (_selectedId == x.id) _selectedId = null;
      final dir = dirOf(x);
      if (await dir.exists()) await dir.delete(recursive: true);
    } else {
      _dirty.remove(x);
      await _write(x);
    }
    notifyListeners();
  }

  /// Permanently delete a session, its detections, and its recordings folder.
  Future<void> deleteSession(Session x) async {
    if (x.live) return;
    sessions.remove(x);
    _dirty.remove(x);
    all.removeWhere((d) => x.contains(d.at));
    if (_selectedId == x.id) {
      _selectedId = sessions.isEmpty ? null : sessions.last.id;
    }
    final dir = dirOf(x);
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }

  /// Give sessions with a place but no name yet the name of their nearest
  /// town or village, one at a time, saving each as it comes (for the
  /// calendar). [lookUp] is engine/place_names.dart nearestPlace.
  Future<void> namePlaces(Future<String?> Function(double lat, double lon) lookUp) async {
    for (final x in [...sessions]) {
      if (!x.hasPlace || x.placeName != null) continue;
      final name = await lookUp(x.lat!, x.lon!);
      if (name == null) return; // offline: try again another time
      x.placeName = name;
      await saveSession(x);
    }
  }

  /// Give ended sessions with a place but no [Session.placeArea] yet the
  /// reserve, wood or heath their walk was most in, one walk at a time,
  /// saving each as it comes (for the calendar). [lookUp] is
  /// native/walk_names.dart areaOfWalk: '' for none, null when offline
  /// (stops; tried again another time).
  Future<void> nameAreas(Future<String?> Function(List<(double, double)> path) lookUp) async {
    for (final x in [...sessions]) {
      if (x.live || !x.hasPlace || x.placeArea != null) continue;
      final walk = walkOf(x);
      if (walk.any((s) => s.live)) continue;
      final path = <(double, double)>[
        for (final s in walk) ...[
          for (final p in s.track) (p.lat, p.lon),
          for (final d in inSession(s))
            if (d.hasPlace) (d.lat!, d.lon!),
        ],
      ];
      if (path.isEmpty) path.add((x.lat!, x.lon!));
      final area = await lookUp(path);
      if (area == null) return;
      for (final s in walk) {
        s.placeArea = area;
        await saveSession(s);
      }
    }
  }

  /// Record a change to a session (its place or weather found).
  Future<void> saveSession(Session x) async {
    _touch(x);
    notifyListeners();
  }

  List<Detection> inSession(Session x) => all.where((d) => x.contains(d.at)).toList();

  /// Add a position fix to a session's trail.
  void addTrackPoint(Session x, TrackPoint p) {
    x.track.add(p);
    _touch(x);
    notifyListeners();
  }

  /// The walk [x] belongs to: [x] and the sessions run straight on from it
  /// or into it because one filled up at [maxSessionSpecies] (stopReason
  /// speciesLimit, the next starting within a few seconds). Oldest first.
  List<Session> walkOf(Session x) {
    final i = sessions.indexOf(x);
    if (i < 0) return [x];
    bool joined(Session a, Session b) =>
        a.stopReason == 'speciesLimit' &&
        a.end != null &&
        b.start.difference(a.end!).abs() <= const Duration(seconds: 5);
    var from = i, to = i;
    while (from > 0 && joined(sessions[from - 1], sessions[from])) {
      from--;
    }
    while (to < sessions.length - 1 && joined(sessions[to], sessions[to + 1])) {
      to++;
    }
    return sessions.sublist(from, to + 1);
  }

  Session? sessionOf(Detection d) {
    for (var i = sessions.length - 1; i >= 0; i--) {
      if (sessions[i].contains(d.at)) return sessions[i];
    }
    return null;
  }

  // ---- detections -----------------------------------------------------------

  Future<Detection> add({
    required String model,
    required String sci,
    required String common,
    required double confidence,
    required DateTime at,
    double? windowSeconds,
    List<RankedScore> scores = const [],
    double? lat,
    double? lon,
  }) async {
    final d = Detection(
        id: _nextId++,
        model: model,
        sci: sci,
        common: common,
        confidence: confidence,
        at: at,
        windowSeconds: windowSeconds,
        scores: scores,
        lat: lat,
        lon: lon);
    all.add(d);
    // Heard with no session open (shouldn't happen): give it one.
    var x = sessionOf(d);
    if (x == null) {
      x = await startSession(at: at);
      await endSession(x, at: at, reason: 'manual');
    }
    _touch(x);
    notifyListeners();
    return d;
  }

  /// Record a change to a detection already stored (a clip saved, a higher
  /// confidence on a repeated call, a review).
  Future<void> save(Detection d) async {
    final x = sessionOf(d);
    if (x != null) _touch(x);
    notifyListeners();
  }

  /// Where a detection's clip and spectrogram go, inside its session folder.
  File clipFile(int id) => _fileFor(id, (d) => d.clipPath);
  File spectrogramFile(int id) => _fileFor(id, (d) => d.spectrogramPath);

  File _fileFor(int id, String Function(Detection) path) {
    final d = byId(id);
    final x = d == null ? null : sessionOf(d);
    if (d == null || x == null) return File('${sessionsDir.path}/missing/$id');
    final f = File('${dirOf(x).path}/${path(d)}');
    f.parent.createSync(recursive: true);
    return f;
  }

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

  /// Disk used by recordings and spectrograms.
  Future<int> clipBytes() async {
    var n = 0;
    await for (final e in sessionsDir.list(recursive: true)) {
      if (e is File &&
          (e.path.endsWith('.wav') || e.path.endsWith('.m4a') || e.path.endsWith('.bmp'))) {
        n += await e.length();
      }
    }
    return n;
  }

  /// Number of saved WAV clips that can be compressed to AAC.
  Future<int> wavClipCount() async {
    var n = 0;
    for (final d in all) {
      if (d.hasClip && d.clipExt == 'wav' && await clipFile(d.id).exists()) {
        n++;
      }
    }
    return n;
  }

  /// Convert all existing WAV recordings to compressed AAC (.m4a) using
  /// [encode] (which takes inputPath and outputPath and returns true on
  /// success). Updates detections.jsonl and deletes the WAV only after
  /// encoding succeeds.
  Future<({int converted, int failed, int savedBytes})> batchConvertWavToAac(
    Future<bool> Function(String wavPath, String m4aPath) encode, {
    void Function(int done, int total)? onProgress,
  }) async {
    final targets = <Detection>[];
    for (final d in all) {
      if (d.hasClip && d.clipExt == 'wav' && await clipFile(d.id).exists()) {
        targets.add(d);
      }
    }
    var converted = 0, failed = 0, savedBytes = 0;
    for (var i = 0; i < targets.length; i++) {
      final d = targets[i];
      final wavFile = clipFile(d.id);
      if (!await wavFile.exists()) continue;
      final wavSize = await wavFile.length();
      final m4aPath = wavFile.path.replaceFirst(RegExp(r'\.wav$'), '.m4a');
      final ok = await encode(wavFile.path, m4aPath);
      final m4aFile = File(m4aPath);
      if (ok && await m4aFile.exists() && await m4aFile.length() > 0) {
        final m4aSize = await m4aFile.length();
        savedBytes += max(0, wavSize - m4aSize);
        d.clipExt = 'm4a';
        final ses = sessionOf(d);
        if (ses != null) _dirty.add(ses);
        try {
          await wavFile.delete();
        } catch (e) {
          debugPrint('batchConvert delete ${wavFile.path}: $e');
        }
        converted++;
      } else {
        failed++;
      }
      onProgress?.call(i + 1, targets.length);
    }
    await flush();
    notifyListeners();
    return (converted: converted, failed: failed, savedBytes: savedBytes);
  }

  /// Re-read all session folders from disk (e.g. after iCloud sync pulls in
  /// sessions recorded on another device).
  Future<void> reload() async {
    await flush();
    final keepSelected = _selectedId;
    sessions.clear();
    all.clear();
    _nextId = 1;
    _nextSessionId = 1;
    await _load();
    sessions.sort((a, b) => a.start.compareTo(b.start));
    all.sort((a, b) => a.at.compareTo(b.at));
    if (keepSelected != null && sessions.any((x) => x.id == keepSelected)) {
      _selectedId = keepSelected;
    } else {
      _selectedId = null;
    }
    notifyListeners();
  }

  /// Forget everything except a session still listening (which is emptied).
  Future<void> clear() async {
    await flush();
    for (final x in sessions.where((x) => !x.live).toList()) {
      final dir = dirOf(x);
      if (await dir.exists()) await dir.delete(recursive: true);
      sessions.remove(x);
    }
    all.clear();
    _selectedId = null;
    for (final x in sessions) {
      final dir = dirOf(x);
      for (final sub in ['audio', 'spectrograms']) {
        final d = Directory('${dir.path}/$sub');
        if (await d.exists()) await d.delete(recursive: true);
      }
      await _write(x);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(flush());
    super.dispose();
  }
}
