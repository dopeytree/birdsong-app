import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:birdsong_app/native/landmarks.dart';
import 'package:birdsong_app/native/mvt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// A small writer for the vector tile format, to make tiles to read back.
List<int> varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

List<int> field(int n, int wire, List<int> body) =>
    [...varint((n << 3) | wire), if (wire == 2) ...varint(body.length), ...body];
List<int> str(int n, String s) => field(n, 2, utf8.encode(s));
List<int> packed(int n, List<int> vs) => field(n, 2, [for (final v in vs) ...varint(v)]);
int zz(int n) => (n << 1) ^ (n >> 63);

/// A polygon's geometry commands from absolute points (each ring closed).
List<int> rings(List<List<(int, int)>> rs) {
  final out = <int>[];
  var x = 0, y = 0;
  for (final r in rs) {
    out
      ..add((1 & 7) | (1 << 3))
      ..addAll([zz(r[0].$1 - x), zz(r[0].$2 - y)]);
    x = r[0].$1;
    y = r[0].$2;
    out.add((2 & 7) | ((r.length - 1) << 3));
    for (final p in r.skip(1)) {
      out.addAll([zz(p.$1 - x), zz(p.$2 - y)]);
      x = p.$1;
      y = p.$2;
    }
    out.add(7 | (1 << 3));
  }
  return out;
}

Uint8List tile(List<List<int>> parkFeatures, {List<int> other = const []}) {
  final park = [
    ...str(1, 'park'),
    for (final f in parkFeatures) ...field(2, 2, f),
    ...str(3, 'class'),
    ...str(3, 'name'),
    ...field(4, 2, str(1, 'nature_reserve')),
    ...field(4, 2, str(1, 'RSPB Ham Wall')),
    ...field(4, 2, str(1, 'park')),
    ...field(4, 2, str(1, 'Town Park')),
    ...field(5, 0, varint(4096)),
  ];
  return Uint8List.fromList([...other, ...field(3, 2, park)]);
}

// clockwise in tile units (y down): positive area, an outer ring
const outer = [(1000, 1000), (3000, 1000), (3000, 3000), (1000, 3000)];

void main() {
  final reserve = [
    ...packed(2, [0, 0, 1, 1]), // class nature_reserve, name RSPB Ham Wall
    ...field(3, 0, varint(3)),
    ...packed(4, rings([outer])),
  ];
  final park = [
    ...packed(2, [0, 2, 1, 3]),
    ...field(3, 0, varint(3)),
    ...packed(4, rings([outer])),
  ];
  final water = field(3, 2, [...str(1, 'water'), ...field(5, 0, varint(4096))]);

  test('a layer of a tile is read: its features, names and polygons', () {
    final fs = readMvtLayer(tile([reserve, park], other: water), 'park');
    expect(fs.length, 2);
    expect(fs.first.props, {'class': 'nature_reserve', 'name': 'RSPB Ham Wall'});
    expect(fs.first.type, 3);
    expect(fs.first.parts.single.length, 5); // closed
    expect(readMvtLayer(tile([reserve]), 'water'), isEmpty);
  });

  test('gzipped tiles read the same', () {
    final fs = readMvtLayer(Uint8List.fromList(gzip.encode(tile([reserve]))), 'park');
    expect(fs.single.props['name'], 'RSPB Ham Wall');
  });

  test("a polygon is placed in the tile's square on the map", () {
    final (x, y) = tileOf(const LatLng(51.152, -2.780), 14);
    final f = readMvtLayer(tile([reserve]), 'park').first;
    final poly = mvtPolygons(f, 14, x, y);
    expect(poly.length, 1);
    final ring = poly.single.single;
    // the tile is about 1.5 km across; the square is its middle half
    final west = (x / (1 << 14)) * 360 - 180, east = ((x + 1) / (1 << 14)) * 360 - 180;
    final w = east - west;
    expect(ring.first.longitude, closeTo(west + w * 1000 / 4096, 1e-9));
    expect(ring[1].longitude, closeTo(west + w * 3000 / 4096, 1e-9));
    expect(ring.first.latitude, greaterThan(ring[2].latitude)); // y runs down
  });

  test("the walk's reserves are read from the tiles under it, and it walked through", () async {
    final start = const LatLng(51.152, -2.780);
    final (x, y) = tileOf(start, 14);
    // a walk round the middle of the tile, where the reserve is
    final f = readMvtLayer(tile([reserve]), 'park').first;
    final mid = mvtPolygons(f, 14, x, y).single.single;
    final centre = LatLng((mid[0].latitude + mid[2].latitude) / 2, (mid[0].longitude + mid[2].longitude) / 2);
    final asked = <String>[];
    final reserves = await reservesAlong([centre], (z, tx, ty) async {
      asked.add('$z/$tx/$ty');
      return tile([reserve, park]);
    });
    expect(asked, ['14/$x/$y']);
    expect(reserves.single.name, 'RSPB Ham Wall'); // the town park is not a reserve
    final passed = passedOnTheWay([centre],
        reserves: reserves,
        wiki: [Spot('Ham Wall', 'Wetland nature reserve in Somerset, England', centre)]);
    expect(passed.single.name, 'RSPB Ham Wall'); // Wikipedia's Ham Wall is the same place
    expect(passed.single.about, 'Wetland nature reserve in Somerset, England');
    expect(passed.single.at, isNull); // walked through
  });
}
