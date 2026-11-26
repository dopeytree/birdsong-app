import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'detection_store.dart' show newUuid;

/// A user-dropped pin on the walk map: draggable, auto-saved to disk, synced
/// across devices via iCloud Drive, shareable and navigable in external map apps.
class MapPin {
  MapPin({
    required this.id,
    required this.lat,
    required this.lon,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  double lat;
  double lon;
  String label;
  final int createdAt;
  int updatedAt;

  LatLng get point => LatLng(lat, lon);

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': double.parse(lat.toStringAsFixed(6)),
        'lon': double.parse(lon.toStringAsFixed(6)),
        'label': label,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  static MapPin fromJson(Map<String, dynamic> j) => MapPin(
        id: (j['id'] as String?) ?? newUuid(),
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        label: (j['label'] as String?) ?? 'Dropped pin',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Persistent auto-saving store for dropped map pins (`<appData>/map_pins.json`),
/// with deletion tombstones so iCloud sync cleanly merges adds, drags, renames,
/// and deletes across iPhone, iPad, and Mac.
class MapPinStore extends ChangeNotifier {
  MapPinStore._(this._file);

  final File _file;
  final List<MapPin> pins = [];
  final Map<String, int> deletedIds = {};
  Future<void> _saving = Future.value();
  bool applyingRemoteSync = false;

  Future<void> get saved => _saving;

  static Future<MapPinStore> open(Directory dataDir) async {
    final store = MapPinStore._(File('${dataDir.path}/map_pins.json'));
    await store._load();
    return store;
  }

  Future<void> _load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString());
      if (j is! Map) return;
      pins.clear();
      deletedIds.clear();
      for (final raw in (j['pins'] as List? ?? const [])) {
        if (raw is Map) {
          try {
            pins.add(MapPin.fromJson(Map<String, dynamic>.from(raw)));
          } catch (_) {}
        }
      }
      final del = j['deleted'];
      if (del is Map) {
        for (final e in del.entries) {
          if (e.key is String && e.value is num) {
            deletedIds[e.key as String] = (e.value as num).toInt();
          }
        }
      }
      pins.removeWhere((p) => (deletedIds[p.id] ?? 0) >= p.updatedAt);
    } catch (e) {
      debugPrint('map pins read: $e');
    }
  }

  Map<String, dynamic> toSyncJson() => {
        'pins': [for (final p in pins) p.toJson()],
        if (deletedIds.isNotEmpty) 'deleted': deletedIds,
      };

  MapPin drop(LatLng at, {String? label}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = pins.length + 1;
    final pin = MapPin(
      id: newUuid(),
      lat: at.latitude,
      lon: at.longitude,
      label: (label != null && label.trim().isNotEmpty) ? label.trim() : 'Pin $n',
      createdAt: now,
      updatedAt: now,
    );
    pins.add(pin);
    _persist();
    notifyListeners();
    return pin;
  }

  void move(String id, LatLng to) {
    final p = pins.where((x) => x.id == id).firstOrNull;
    if (p == null) return;
    p
      ..lat = to.latitude
      ..lon = to.longitude
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    _persist();
    notifyListeners();
  }

  void rename(String id, String label) {
    final p = pins.where((x) => x.id == id).firstOrNull;
    if (p == null) return;
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed == p.label) return;
    p
      ..label = trimmed
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    _persist();
    notifyListeners();
  }

  void remove(String id) {
    final before = pins.length;
    pins.removeWhere((x) => x.id == id);
    if (pins.length == before) return;
    deletedIds[id] = DateTime.now().millisecondsSinceEpoch;
    _persist();
    notifyListeners();
  }

  /// Bidirectionally merges [remote] pins + deletion tombstones.
  /// Returns true when local pins changed.
  bool mergeFromSyncJson(Map<String, dynamic> remote) {
    final before = jsonEncode(toSyncJson());
    final rDel = remote['deleted'];
    if (rDel is Map) {
      for (final e in rDel.entries) {
        if (e.key is String && e.value is num) {
          final id = e.key as String;
          final ts = (e.value as num).toInt();
          if (ts > (deletedIds[id] ?? 0)) deletedIds[id] = ts;
        }
      }
    }
    final byId = {for (final p in pins) p.id: p};
    for (final raw in (remote['pins'] as List? ?? const [])) {
      if (raw is! Map) continue;
      try {
        final rp = MapPin.fromJson(Map<String, dynamic>.from(raw));
        final delTs = deletedIds[rp.id] ?? 0;
        if (delTs >= rp.updatedAt) continue;
        final lp = byId[rp.id];
        if (lp == null || rp.updatedAt > lp.updatedAt) {
          byId[rp.id] = rp;
        }
      } catch (_) {}
    }
    byId.removeWhere((id, p) => (deletedIds[id] ?? 0) >= p.updatedAt);
    pins
      ..clear()
      ..addAll(byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
    final after = jsonEncode(toSyncJson());
    if (before == after) return false;
    applyingRemoteSync = true;
    try {
      notifyListeners();
    } finally {
      applyingRemoteSync = false;
    }
    _persist();
    return true;
  }

  void _persist() {
    final json = const JsonEncoder.withIndent('  ').convert(toSyncJson());
    _saving = _saving.then((_) async {
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.pending');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(_file.path);
    }).catchError((Object e) {
      debugPrint('map pins save: $e');
    });
  }
}
