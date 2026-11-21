import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert' show utf8;

import 'package:latlong2/latlong.dart' hide Path;

/// A feature read from a Mapbox Vector Tile: its properties, its kind (1
/// point, 2 line, 3 polygon) and its geometry in the tile's own units
/// (0 to [extent] across), as rings or lines of x, y pairs.
class MvtFeature {
  const MvtFeature(this.props, this.type, this.parts, this.extent);

  final Map<String, Object?> props;
  final int type;
  final List<List<(int, int)>> parts;
  final int extent;
}

/// Read the features of one layer ([layer], e.g. "park") from a vector
/// tile's bytes (gzipped or not). Just enough of the format (MVT 2.1) for
/// that: no other layers are decoded.
List<MvtFeature> readMvtLayer(Uint8List bytes, String layer) {
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    bytes = Uint8List.fromList(gzip.decode(bytes));
  }
  final out = <MvtFeature>[];
  final tile = _Pb(bytes);
  while (tile.more) {
    final (field, wire) = tile.key();
    if (field == 3 && wire == 2) {
      final l = _Pb(tile.bytes());
      out.addAll(_layer(l, layer));
    } else {
      tile.skip(wire);
    }
  }
  return out;
}

List<MvtFeature> _layer(_Pb l, String want) {
  String? name;
  var extent = 4096;
  final keys = <String>[];
  final values = <Object?>[];
  final raw = <Uint8List>[];
  while (l.more) {
    final (field, wire) = l.key();
    switch ((field, wire)) {
      case (1, 2):
        name = utf8.decode(l.bytes());
        if (name != want) return const [];
      case (2, 2):
        raw.add(l.bytes());
      case (3, 2):
        keys.add(utf8.decode(l.bytes()));
      case (4, 2):
        values.add(_value(_Pb(l.bytes())));
      case (5, 0):
        extent = l.varint();
      default:
        l.skip(wire);
    }
  }
  if (name != want) return const [];
  return [for (final f in raw) _feature(_Pb(f), keys, values, extent)];
}

Object? _value(_Pb v) {
  Object? out;
  while (v.more) {
    final (field, wire) = v.key();
    switch ((field, wire)) {
      case (1, 2):
        out = utf8.decode(v.bytes());
      case (2, 5):
        out = v.float32();
      case (3, 1):
        out = v.float64();
      case (4, 0) || (5, 0):
        out = v.varint();
      case (6, 0):
        out = _zz(v.varint());
      case (7, 0):
        out = v.varint() != 0;
      default:
        v.skip(wire);
    }
  }
  return out;
}

MvtFeature _feature(_Pb f, List<String> keys, List<Object?> values, int extent) {
  var type = 0;
  var tags = const <int>[];
  var geom = const <int>[];
  while (f.more) {
    final (field, wire) = f.key();
    switch ((field, wire)) {
      case (2, 2):
        tags = f.packed();
      case (3, 0):
        type = f.varint();
      case (4, 2):
        geom = f.packed();
      default:
        f.skip(wire);
    }
  }
  final props = <String, Object?>{};
  for (var i = 0; i + 1 < tags.length; i += 2) {
    if (tags[i] < keys.length && tags[i + 1] < values.length) props[keys[tags[i]]] = values[tags[i + 1]];
  }
  // MoveTo 1, LineTo 2, ClosePath 7; deltas zigzag-encoded
  final parts = <List<(int, int)>>[];
  var x = 0, y = 0, i = 0;
  List<(int, int)>? part;
  while (i < geom.length) {
    final cmd = geom[i] & 7, count = geom[i] >> 3;
    i++;
    if (cmd == 1 || cmd == 2) {
      for (var k = 0; k < count && i + 1 < geom.length; k++) {
        x += _zz(geom[i]);
        y += _zz(geom[i + 1]);
        i += 2;
        if (cmd == 1) {
          part = [];
          parts.add(part);
        }
        part?.add((x, y));
      }
    } else if (cmd == 7) {
      if (part != null && part.isNotEmpty) part.add(part.first);
    } else {
      break;
    }
  }
  return MvtFeature(props, type, parts, extent);
}

int _zz(int n) => (n >> 1) ^ -(n & 1);

/// A polygon feature of tile [z]/[x]/[y] as polygons of rings in degrees:
/// outer rings (positive area, as the format has them) each start a
/// polygon; the inner ones that follow are its holes.
List<List<List<LatLng>>> mvtPolygons(MvtFeature f, int z, int x, int y) {
  final n = 1 << z;
  LatLng at((int, int) p) {
    final fx = (x + p.$1 / f.extent) / n, fy = (y + p.$2 / f.extent) / n;
    final lat = math.atan(_sinh(math.pi * (1 - 2 * fy))) * 180 / math.pi;
    return LatLng(lat, fx * 360 - 180);
  }

  final out = <List<List<LatLng>>>[];
  for (final ring in f.parts) {
    if (ring.length < 4) continue;
    var area = 0.0;
    for (var k = 0; k + 1 < ring.length; k++) {
      area += ring[k].$1 * ring[k + 1].$2 - ring[k + 1].$1 * ring[k].$2;
    }
    final pts = [for (final p in ring) at(p)];
    if (area > 0 || out.isEmpty) {
      out.add([pts]);
    } else {
      out.last.add(pts);
    }
  }
  return out;
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

/// The z/x/y tile a point falls in.
(int, int) tileOf(LatLng p, int z) {
  final n = 1 << z;
  final x = ((p.longitude + 180) / 360 * n).floor().clamp(0, n - 1);
  final r = p.latitude * math.pi / 180;
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor().clamp(0, n - 1);
  return (x, y);
}

/// A reader for protocol buffers' wire format, as much as tiles need.
class _Pb {
  _Pb(this.b);

  final Uint8List b;
  int i = 0;

  bool get more => i < b.length;

  int varint() {
    var r = 0, s = 0;
    while (i < b.length) {
      final c = b[i++];
      r |= (c & 0x7f) << s;
      if (c < 0x80) break;
      s += 7;
    }
    return r;
  }

  (int, int) key() {
    final k = varint();
    return (k >> 3, k & 7);
  }

  Uint8List bytes() {
    final len = varint();
    final out = Uint8List.sublistView(b, i, math.min(b.length, i + len));
    i += len;
    return out;
  }

  List<int> packed() {
    final p = _Pb(bytes());
    final out = <int>[];
    while (p.more) {
      out.add(p.varint());
    }
    return out;
  }

  double float32() {
    final v = ByteData.sublistView(b, i, i + 4).getFloat32(0, Endian.little);
    i += 4;
    return v;
  }

  double float64() {
    final v = ByteData.sublistView(b, i, i + 8).getFloat64(0, Endian.little);
    i += 8;
    return v;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        i += 8;
      case 2:
        i += varint();
      case 5:
        i += 4;
      default:
        i = b.length;
    }
  }
}
