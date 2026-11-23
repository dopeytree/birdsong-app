import 'dart:typed_data';

import 'package:birdsong_app/native/cutout.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [w] x [h] page of off-white paper, with [ink] rectangles (l, t, r, b).
Uint8List page(int w, int h, List<(int, int, int, int)> ink) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < px.length; i += 4) {
    px.setRange(i, i + 4, [250, 247, 238, 255]);
  }
  for (final (l, t, r, b) in ink) {
    for (var y = t; y < b; y++) {
      for (var x = l; x < r; x++) {
        px.setRange((y * w + x) * 4, (y * w + x) * 4 + 4, [60, 45, 30, 255]);
      }
    }
  }
  return px;
}

void main() {
  test('the figure is kept and cropped to; the paper and the caption go', () {
    // a bird in the middle and a line of lettering under it
    final cut = cutOutFigure(page(100, 80, [(35, 15, 65, 40), (20, 68, 80, 70)]), 100, 80)!;
    expect(cut.width, inInclusiveRange(28, 36));
    expect(cut.height, inInclusiveRange(23, 31), reason: 'the caption is not part of it');
    final mid = ((cut.height ~/ 2) * cut.width + cut.width ~/ 2) * 4;
    expect(cut.rgba.sublist(mid, mid + 4), [60, 45, 30, 255], reason: 'ink stays solid');
    expect(cut.cover, closeTo(750 / 8000, 0.02));
  });

  test('a pale patch inside the figure stays solid', () {
    // a ring of ink around a paper-coloured middle: a white breast
    final px = page(100, 80, [(30, 20, 70, 60)]);
    for (var y = 32; y < 48; y++) {
      for (var x = 42; x < 58; x++) {
        px.setRange((y * 100 + x) * 4, (y * 100 + x) * 4 + 4, [250, 247, 238, 255]);
      }
    }
    final cut = cutOutFigure(px, 100, 80)!;
    final mid = ((cut.height ~/ 2) * cut.width + cut.width ~/ 2) * 4;
    expect(cut.rgba[mid + 3], 255);
    expect(cut.rgba[mid], 250);
  });

  test('a painted scene is left whole, and so is a blank page', () {
    expect(cutOutFigure(page(100, 80, [(10, 10, 90, 70)]), 100, 80), isNull);
    expect(cutOutFigure(page(100, 80, const []), 100, 80), isNull);
  });
}
