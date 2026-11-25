import 'package:birdsong_app/native/collage_layout.dart';
import 'package:birdsong_app/native/collage_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const box = Size(600, 400);
  final samplePlaces = layoutCollage(const [
    CollageItem('a', weight: 100, aspect: 1.2),
    CollageItem('b', weight: 40, aspect: 1.0),
    CollageItem('c', weight: 10, aspect: 1.3),
  ], box);

  test('zero drag leaves the default layout untouched', () {
    final moved = displaceCollage(
      samplePlaces,
      const {'a': 1.0, 'b': 0.5, 'c': 0.0},
      sizeBy: 'calls',
      drag: Offset.zero,
      box: box,
    );
    expect(moved, same(samplePlaces));
  });

  test('calls view anchors the most-heard bird while rarer birds glide further', () {
    final moved = displaceCollage(
      samplePlaces,
      const {'a': 1.0, 'b': 0.5, 'c': 0.0},
      sizeBy: 'calls',
      drag: const Offset(40, 20),
      box: box,
    );
    final before = {for (final p in samplePlaces) p.id: p.rect.topLeft};
    final after = {for (final p in moved) p.id: p.rect.topLeft};
    final moveA = (after['a']! - before['a']!).distance;
    final moveC = (after['c']! - before['c']!).distance;
    expect(moveA, greaterThan(0));
    expect(moveC, greaterThan(moveA));
  });

  test('time view lets the most-recent bird lead the drag ahead of older ones', () {
    final centered = [
      const CollagePlace('a', Rect.fromLTWH(250, 160, 80, 60), 1),
      const CollagePlace('b', Rect.fromLTWH(260, 170, 80, 60), 2),
      const CollagePlace('c', Rect.fromLTWH(270, 180, 80, 60), 3),
    ];
    final moved = displaceCollage(
      centered,
      const {'a': 0.0, 'b': 0.5, 'c': 1.0},
      sizeBy: 'time',
      drag: const Offset(40, 15),
      box: box,
    );
    final before = {for (final p in centered) p.id: p.rect.topLeft};
    final after = {for (final p in moved) p.id: p.rect.topLeft};
    final moveOldest = (after['a']! - before['a']!).distance;
    final moveNewest = (after['c']! - before['c']!).distance;
    expect(moveNewest, greaterThan(moveOldest));
  });

  test('all dragged birds keep their centres inside the collage bounds', () {
    final moved = displaceCollage(
      samplePlaces,
      const {'a': 1.0, 'b': 0.5, 'c': 0.0},
      sizeBy: 'equal',
      drag: const Offset(2000, -2000),
      box: box,
    );
    for (final p in moved) {
      expect(p.rect.center.dx, greaterThanOrEqualTo(0));
      expect(p.rect.center.dy, greaterThanOrEqualTo(0));
      expect(p.rect.center.dx, lessThanOrEqualTo(box.width + 0.01));
      expect(p.rect.center.dy, lessThanOrEqualTo(box.height + 0.01));
    }
  });

  testWidgets('dragging moves birds, tapping still opens, and idle resets after 10s', (tester) async {
    final birds = [
      CollageBird('Erithacus rubecula', 'European Robin', 20, DateTime(2026, 11, 25, 9, 0)),
      CollageBird('Turdus merula', 'Common Blackbird', 5, DateTime(2026, 11, 25, 9, 10)),
    ];
    CollageBird? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CollageView(
              birds: birds,
              art: const {'Erithacus rubecula': null, 'Turdus merula': null},
              size: const Size(400, 300),
              sizeBy: 'calls',
              markAt: 'below',
              newest: 'Turdus merula',
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

    // Drag across the collage (multi-step gesture like a real finger/mouse drag)
    await tester.timedDrag(find.byType(CollageView), const Offset(80, 50), const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    final draggedPos = tester.getCenter(robin);
    expect((draggedPos - startPos).distance, greaterThan(5));

    // After 5s, still displaced (10s hasn't elapsed yet)
    await tester.pump(const Duration(seconds: 5));
    expect((tester.getCenter(robin) - startPos).distance, greaterThan(5));

    // Another drag restarts the 10s countdown
    await tester.timedDrag(find.byType(CollageView), const Offset(30, 0), const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 6));
    expect((tester.getCenter(robin) - startPos).distance, greaterThan(5));

    // 4+ more seconds (total 10s since last drag) -> resets smoothly to default
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect((tester.getCenter(robin) - startPos).distance, lessThan(0.5));

    // Tapping a bird still opens its card
    await tester.tap(robin);
    await tester.pump();
    expect(opened?.sci, 'Erithacus rubecula');
  });
}
