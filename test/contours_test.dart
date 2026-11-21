import 'dart:math' as math;
import 'dart:typed_data';

import 'package:birdsong_app/native/contours.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a hill gives one closed ring at each height, round its top', () {
    const w = 41, h = 41;
    final v = Float32List(w * h);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        v[j * w + i] = 100 - math.sqrt((i - 20) * (i - 20) + (j - 20) * (j - 20)) * 5;
      }
    }
    final rings = isolines(v, w, h, 50);
    expect(rings.length, 1);
    final ring = rings.single;
    // closed: it ends where it began
    expect(ring[0], closeTo(ring[ring.length - 2], 1e-9));
    expect(ring[1], closeTo(ring[ring.length - 1], 1e-9));
    // and about ten cells out from the top all the way round
    for (var k = 0; k < ring.length; k += 2) {
      final r = math.sqrt(math.pow(ring[k] - 20, 2) + math.pow(ring[k + 1] - 20, 2));
      expect(r, closeTo(10, .6));
    }
  });

  test('a slope gives one open line, end to end', () {
    const w = 20, h = 10;
    final v = Float32List(w * h);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        v[j * w + i] = i.toDouble();
      }
    }
    final lines = isolines(v, w, h, 7.5);
    expect(lines.length, 1);
    expect(lines.single.length ~/ 2, h);
    for (var k = 0; k < lines.single.length; k += 2) {
      expect(lines.single[k], closeTo(7.5, 1e-9));
    }
  });

  test('terrarium heights, intervals and tiles read as the web map reads them', () {
    expect(terrarium(128, 0, 0), 0);
    expect(terrarium(128, 100, 128), 100.5);
    expect(contourInterval(15.2), (10, 50)); // no finer when zoomed right in
    expect(contourInterval(12), (20, 100));
    expect(contourInterval(8), (100, 500));
    // Greenwich at zoom 1 is the right-hand column, the top row for the north
    final r = tileRange(0.1, 10, 0.2, 20, 1);
    expect((r.x0, r.x1, r.y0, r.y1), (1, 1, 0, 0));
  });

  test('traced lines are placed on the map and broken at the frame', () {
    const w = 64, h = 64;
    final v = Float32List(w * h);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        v[j * w + i] = 300 - math.sqrt((i - 32) * (i - 32) + (j - 32) * (j - 32)) * 10;
      }
    }
    final lines = traceContours(ContourJob(v, w, h, 0, 0, 10, 50, 250));
    expect(lines, isNotEmpty);
    expect(lines.where((l) => l.major).map((l) => l.ele).toSet(), {250});
    for (final l in lines) {
      for (var k = 0; k < l.lonLat.length; k += 2) {
        expect(l.lonLat[k], inInclusiveRange(-180, -179)); // tile 0 of zoom 10
        expect(l.lonLat[k + 1], inInclusiveRange(84, 86));
      }
    }
  });
}
