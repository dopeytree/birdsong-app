import 'package:birdsong_app/ui/plate_icons.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every icon has marks, and every mark sits inside its 24 box', () {
    for (final g in PlateGlyph.values) {
      final marks = plateGlyphs[g];
      expect(marks, isNotEmpty, reason: '$g has no marks');
      for (final m in marks!) {
        final b = parseSvgPath(m.d).getBounds();
        expect(b.isEmpty && m.ink != Ink.stroke && m.ink != Ink.fine, isFalse, reason: '$g: ${m.d}');
        expect(const Rect.fromLTRB(0, 0, 24, 24).inflate(.01).contains(b.topLeft), isTrue, reason: '$g: ${m.d}');
        expect(const Rect.fromLTRB(0, 0, 24, 24).inflate(.01).contains(b.bottomRight), isTrue, reason: '$g: ${m.d}');
      }
    }
  });

  test('path data: relative moves, lines, curves and arcs', () {
    final p = parseSvgPath('m2 2l4 0h2v4H2Z');
    expect(p.getBounds(), const Rect.fromLTRB(2, 2, 8, 6));
    final arc = parseSvgPath('M7 12A5 5 0 1 0 17 12A5 5 0 1 0 7 12Z').getBounds();
    expect(arc.left, closeTo(7, .01));
    expect(arc.right, closeTo(17, .01));
    expect(arc.top, closeTo(7, .01));
    expect(arc.bottom, closeTo(17, .01));
    final c = parseSvgPath('M0 0C0 10 10 10 10 0').getBounds();
    expect(c.right, closeTo(10, .01));
    expect(c.bottom, closeTo(7.5, .01));
  });
}
