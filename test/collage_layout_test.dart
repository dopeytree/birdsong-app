import 'dart:ui';

import 'package:birdsong_app/native/collage_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final items = [
    const CollageItem('starling', weight: 10, aspect: 1.2),
    const CollageItem('robin', weight: 4, aspect: 1.4),
    const CollageItem('greenfinch', weight: 2, aspect: 1.1),
    const CollageItem('dove', weight: 1, aspect: 0.8),
    const CollageItem('blackbird', weight: 1, aspect: 1.0),
    const CollageItem('human', weight: 1, aspect: 1.7, blank: true),
  ];
  const box = Size(390, 520);

  test('every figure is inside the collage and none overlap', () {
    final places = layoutCollage(items, box);
    expect(places, hasLength(items.length));
    for (final p in places) {
      expect(p.rect.left, greaterThanOrEqualTo(-0.01), reason: p.id);
      expect(p.rect.top, greaterThanOrEqualTo(-0.01), reason: p.id);
      expect(p.rect.right, lessThanOrEqualTo(box.width + 0.01), reason: p.id);
      expect(p.rect.bottom, lessThanOrEqualTo(box.height + 0.01), reason: p.id);
    }
    for (var a = 0; a < places.length; a++) {
      for (var b = a + 1; b < places.length; b++) {
        expect(places[a].rect.overlaps(places[b].rect), isFalse,
            reason: '${places[a].id} over ${places[b].id}');
      }
    }
  });

  test('the most heard is the largest, and a figure keeps its shape', () {
    final by = {for (final p in layoutCollage(items, box)) p.id: p.rect};
    double area(String id) => by[id]!.width * by[id]!.height;
    expect(area('starling'), greaterThan(area('robin')));
    expect(area('robin'), greaterThan(area('dove')));
    expect(by['robin']!.width / by['robin']!.height, closeTo(1.4, 0.01));
  });

  test('all alike come out the same size; the same inputs give the same collage', () {
    final alike = [for (final i in items.take(5)) CollageItem(i.id, weight: 1, aspect: 1)];
    final places = layoutCollage(alike, box);
    expect({for (final p in places) p.rect.width.toStringAsFixed(2)}, hasLength(1));
    final again = layoutCollage(alike, box);
    expect([for (final p in again) p.rect], [for (final p in places) p.rect]);
  });

  test('nothing to place, or nowhere to place it', () {
    expect(layoutCollage(const [], box), isEmpty);
    expect(layoutCollage(items, Size.zero), isEmpty);
  });
}
