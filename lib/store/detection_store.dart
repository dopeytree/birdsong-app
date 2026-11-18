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

/// Detections heard on this device, kept in memory and appended to a JSON
/// lines file. Plenty for a test build; a release would use SQLite.
class DetectionStore extends ChangeNotifier {
  DetectionStore._(this.dir);

  final Directory dir;
  final List<Detection> all = [];
  int _nextId = 1;

  File get _log => File('${dir.path}/detections.jsonl');
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
    return s;
  }

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

  /// What the plate draws: one model's detections, or every model's.
  List<Detection> forPlate(String plateModel) =>
      plateModel == 'all' ? all : all.where((d) => d.model == plateModel).toList();

  Future<void> clear() async {
    all.clear();
    if (await _log.exists()) await _log.delete();
    if (await clips.exists()) await clips.delete(recursive: true);
    await clips.create(recursive: true);
    notifyListeners();
  }
}
