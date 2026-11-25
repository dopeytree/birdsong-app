import 'package:birdsong_app/native/collage_layout.dart';
import 'package:birdsong_app/native/collage_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const box = Size(600, 400);
  final base = layoutCollage(const [
    CollageItem('top', weight: 100, aspect: 1.2),
    CollageItem('b', weight: 40, aspect: 1.0),
    CollageItem('c', weight: 20, aspect: 1.3),
    CollageItem('d', weight: 10, aspect: 0.9),
    CollageItem('e', weight: 5, aspect: 1.1),
    CollageItem('f', weight: 2, aspect: 1.0),
  ], box);

  test('at rest (zero pan) returns the exact original layoutCollage', () {
    expect(lensCollage(base, pan: Offset.zero, box: box), same(base));
  });

  test('panning never overlaps any two birds and keeps every bird inside the box', () {
    for (final pan in const [
      Offset(80, 40),
      Offset(-110, -70),
      Offset(180, -120),
      Offset(-200, 140),
    ]) {
      final moved = lensCollage(base, pan: pan, box: box);
      for (var i = 0; i < moved.length; i++) {
        final r = moved[i].rect;
        expect(r.left, greaterThanOrEqualTo(-0.5));
        expect(r.top, greaterThanOrEqualTo(-0.5));
        expect(r.right, lessThanOrEqualTo(box.width + 0.5));
        expect(r.bottom, lessThanOrEqualTo(box.height + 0.5));
        for (var j = i + 1; j < moved.length; j++) {
          expect(r.deflate(0.5).overlaps(moved[j].rect.deflate(0.5)), isFalse,
              reason: 'birds ${moved[i].id} and ${moved[j].id} overlapped at pan $pan');
        }
      }
    }
  });

  test('dragging a small peripheral bird to the centre overrides view weight and makes it the largest', () {
    final center = Offset(box.width / 2, box.height / 2);
    final edgeBird = base.last; // smallest 2-call peripheral bird
    final panToCenter = center - edgeBird.rect.center;
    final moved = lensCollage(base, pan: panToCenter, box: box);
    final beforeById = {for (final p in base) p.id: p};
    final afterById = {for (final p in moved) p.id: p};
    // At rest, 'top' is much larger than edgeBird
    expect(beforeById['top']!.rect.width, greaterThan(beforeById[edgeBird.id]!.rect.width * 2));
    // Once edgeBird is dragged to the centre, it becomes strictly larger than 'top'
    expect(afterById[edgeBird.id]!.rect.width, greaterThan(afterById['top']!.rect.width));
  });

  testWidgets('dragging moves birds, tapping still opens, and idle resets after 10s', (tester) async {
    final birds = [
      CollageBird('Erithacus rubecula', 'European Robin', 40, DateTime(2026, 11, 25, 9, 0)),
      CollageBird('Turdus merula', 'Common Blackbird', 20, DateTime(2026, 11, 25, 9, 5)),
      CollageBird('Parus major', 'Great Tit', 10, DateTime(2026, 11, 25, 9, 10)),
      CollageBird('Cyanistes caeruleus', 'Eurasian Blue Tit', 2, DateTime(2026, 11, 25, 9, 15)),
    ];
    CollageBird? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CollageView(
              birds: birds,
              art: {for (final b in birds) b.sci: null},
              size: const Size(400, 300),
              sizeBy: 'calls',
              markAt: 'below',
              newest: 'Cyanistes caeruleus',
              live: const {},
              onOpen: (b) => opened = b,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final robin = find.text('European Robin');
    final startPos = tester.getCenter(robin);

    // Drag across the collage
    await tester.timedDrag(find.byType(CollageView), const Offset(90, 50), const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    expect((tester.getCenter(robin) - startPos).distance, greaterThan(5));

    // After 5s, still displaced (10s hasn't elapsed yet)
    await tester.pump(const Duration(seconds: 5));
    expect((tester.getCenter(robin) - startPos).distance, greaterThan(5));

    // Another drag restarts the 10s countdown
    await tester.timedDrag(find.byType(CollageView), const Offset(20, 0), const Duration(milliseconds: 150));
    await tester.pump(const Duration(seconds: 6));
    expect((tester.getCenter(robin) - startPos).distance, greaterThan(5));

    // 4+ more seconds (total 10s since last drag) -> glides smoothly back to default
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect((tester.getCenter(robin) - startPos).distance, lessThan(0.5));

    // Tapping a bird still opens its card
    await tester.tap(robin);
    await tester.pump();
    expect(opened?.sci, 'Erithacus rubecula');
  });
}
