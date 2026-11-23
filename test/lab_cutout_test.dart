import 'dart:typed_data';

import 'package:birdsong_app/lab/cutout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paper goes clear and the figure stays, premultiplied', () {
    // 4 x 4 of off-white paper with one dark pixel and one faint mark inside.
    const w = 4, h = 4;
    final px = Uint8List(w * h * 4);
    for (var i = 0; i < px.length; i += 4) {
      px.setRange(i, i + 4, [250, 248, 240, 255]);
    }
    const dark = (1 * w + 1) * 4, faint = (2 * w + 2) * 4;
    px.setRange(dark, dark + 4, [40, 30, 20, 255]);
    px.setRange(faint, faint + 4, [250 - 39, 248, 240, 255]); // 39 from paper: half way

    final out = liftOffPaper(px, w, h);

    expect(out.sublist(0, 4), [0, 0, 0, 0], reason: 'a border pixel is paper');
    expect(out.sublist(dark, dark + 4), [40, 30, 20, 255], reason: 'ink is kept whole');
    final a = out[faint + 3];
    expect(a, inInclusiveRange(120, 135), reason: 'a faint mark is half clear');
    expect(out[faint], (250 - 39) * a ~/ 255, reason: 'colour is premultiplied by alpha');
  });
}
