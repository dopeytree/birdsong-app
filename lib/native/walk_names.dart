import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, consolidateHttpClientResponseBytes, debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart' hide Path;

import 'landmarks.dart' show Area, inShape, probeOf, reservesAlong;

/// Where a walk went, for the calendar's second name ("Ashcott – RSPB Ham
/// Wall"): the nature reserve it was most in (OpenStreetMap's, from the
/// map's own z14 tiles), else the named wood or heath it was most in (OS
/// Open Names, shipped with the app: assets/places/os_woods.tsv.gz, made by
/// tool/os_woods.py; "Contains OS data © Crown copyright and database right
/// 2026", Open Government Licence). '' when it was in neither; null when the
/// tiles couldn't be had (offline: asked again later).
Future<String?> areaOfWalk(List<(double, double)> path) async {
  final pts = probeOf([for (final (la, lo) in path) LatLng(la, lo)]);
  if (pts.isEmpty) return '';
  var reached = false;
  Future<Uint8List?> tile(int z, int x, int y) async {
    final b = await _tile(z, x, y);
    if (b != null) reached = true;
    return b;
  }

  final reserves = await reservesAlong(pts, tile);
  if (!reached) return null;
  final reserve = mostIn(reserves, pts);
  if (reserve != null) return reserve;
  final places = await _osPlaces();
  return places == null ? '' : (mostInBox(places, pts) ?? '');
}

/// The reserve the most of [pts] are inside, or null when none are.
@visibleForTesting
String? mostIn(List<Area> reserves, List<LatLng> pts) {
  String? best;
  var most = 0;
  for (final a in reserves) {
    final n = pts.where((p) => inShape(p, a.shape)).length;
    if (n > most) (best, most) = (a.name, n);
  }
  return best;
}

/// A named wood or heath from OS Open Names: its name and box.
class OsPlace {
  const OsPlace(this.name, this.south, this.west, this.north, this.east);

  final String name;
  final double south, west, north, east;

  bool holds(LatLng p) => p.latitude >= south && p.latitude <= north && p.longitude >= west && p.longitude <= east;

  /// How far [p] is from the box's middle (OS's point for the name), in
  /// degrees of latitude.
  double from(LatLng p) {
    final dy = p.latitude - (south + north) / 2;
    final dx = (p.longitude - (west + east) / 2) * math.cos(p.latitude * math.pi / 180);
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// The place the most of [pts] belong to, each point belonging to the box
/// that holds it with the nearest middle (boxes overlap, and a moor's can
/// be miles across); of two alike, the nearer. Null when no box holds any.
@visibleForTesting
String? mostInBox(OsPlaces places, List<LatLng> pts) {
  final counts = <OsPlace, int>{}, nearest = <OsPlace, double>{};
  for (final p in pts) {
    OsPlace? best;
    var d = double.infinity;
    for (final o in places.near(p)) {
      if (!o.holds(p)) continue;
      final e = o.from(p);
      if (e < d) (best, d) = (o, e);
    }
    if (best == null) continue;
    counts[best] = (counts[best] ?? 0) + 1;
    if (d < (nearest[best] ?? double.infinity)) nearest[best] = d;
  }
  OsPlace? won;
  for (final o in counts.keys) {
    final w = won;
    if (w == null || counts[o]! > counts[w]! || (counts[o] == counts[w] && nearest[o]! < nearest[w]!)) won = o;
  }
  return won?.name;
}

/// OS Open Names' woods and heaths, filed by tenth of a degree.
class OsPlaces {
  OsPlaces(Iterable<OsPlace> all) {
    for (final o in all) {
      for (var a = _cell(o.south); a <= _cell(o.north); a++) {
        for (var b = _cell(o.west); b <= _cell(o.east); b++) {
          (_cells[(a, b)] ??= []).add(o);
        }
      }
    }
  }

  /// The file's lines (name, kind, south, west, north, east).
  factory OsPlaces.parse(String text) => OsPlaces([
        for (final line in const LineSplitter().convert(text))
          if (line.split('\t') case [final name, _, final s, final w, final n, final e])
            OsPlace(name, double.parse(s), double.parse(w), double.parse(n), double.parse(e)),
      ]);

  final _cells = <(int, int), List<OsPlace>>{};

  static int _cell(double deg) => (deg * 10).floor();

  List<OsPlace> near(LatLng p) => _cells[(_cell(p.latitude), _cell(p.longitude))] ?? const [];
}

Future<OsPlaces?>? _loading;

Future<OsPlaces?> _osPlaces() => _loading ??= () async {
      try {
        final data = await rootBundle.load('assets/places/os_woods.tsv.gz');
        return await compute(_parse, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      } catch (e) {
        debugPrint('walk names: OS places not read ($e)');
        _loading = null;
        return null;
      }
    }();

OsPlaces _parse(Uint8List gz) => OsPlaces.parse(utf8.decode(gzip.decode(gz)));

// ---- the map's tiles, fetched directly (OpenFreeMap), kept for the run

String? _template;
final _tiles = <String, Uint8List?>{};
final _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

Future<Uint8List?> _tile(int z, int x, int y) async {
  final key = '$z/$x/$y';
  if (_tiles.containsKey(key)) return _tiles[key];
  try {
    final t = _template ??= await _tilesTemplate();
    final req = await _client.getUrl(Uri.parse(t.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y')))
        .timeout(const Duration(seconds: 10));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final bytes = await consolidateHttpClientResponseBytes(res);
    if (res.statusCode != 200) return null;
    return _tiles[key] = bytes;
  } catch (e) {
    debugPrint('walk names: tile $key not had ($e)');
    return null;
  }
}

Future<String> _tilesTemplate() async {
  final req = await _client.getUrl(Uri.parse('https://tiles.openfreemap.org/planet')).timeout(const Duration(seconds: 10));
  final res = await req.close().timeout(const Duration(seconds: 10));
  final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  return (j['tiles'] as List).first as String;
}
