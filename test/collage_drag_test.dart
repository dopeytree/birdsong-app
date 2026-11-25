import 'package:birdsong_app/native/collage_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dragging onto a bird promotes it to the centre using layoutCollage and resets after 10s',
      (tester) async {
    final birds = [
      CollageBird('Erithacus rubecula', 'European Robin', 60, DateTime(2026, 11, 25, 9, 0)),
      CollageBird('Turdus merula', 'Common Blackbird', 20, DateTime(2026, 11, 25, 9, 5)),
      CollageBird('Parus major', 'Great Tit', 8, DateTime(2026, 11, 25, 9, 10)),
      CollageBird('Cyanistes caeruleus', 'Eurasian Blue Tit', 1, DateTime(2026, 11, 25, 9, 15)),
    ];
    CollageBird? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CollageView(
              birds: birds,
              art: {for (final b in birds) b.sci: null},
              size: const Size(500, 360),
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

    final robin = find.byKey(const ValueKey('Erithacus rubecula'));
    final blueTit = find.byKey(const ValueKey('Cyanistes caeruleus'));
    final startRobinPos = tester.getCenter(robin);
    final startBluePos = tester.getCenter(blueTit);
    final startBlueWidth = tester.getSize(blueTit).width;

    // Drag starting on the peripheral Blue Tit -> virtually promotes it to centre hero
    await tester.timedDrag(blueTit, const Offset(30, 10), const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // Blue Tit grew dramatically (hero size) and Robin moved aside
    expect(tester.getSize(blueTit).width, greaterThan(startBlueWidth * 1.5));
    expect(tester.getSize(blueTit).width, greaterThan(tester.getSize(robin).width));
    expect((tester.getCenter(robin) - startRobinPos).distance, greaterThan(20));

    // After 5s, Blue Tit is still promoted (10s not elapsed yet)
    await tester.pump(const Duration(seconds: 5));
    expect(tester.getSize(blueTit).width, greaterThan(tester.getSize(robin).width));

    // After 10s total idle, layout glides smoothly back to default
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect((tester.getCenter(robin) - startRobinPos).distance, lessThan(1.0));
    expect((tester.getCenter(blueTit) - startBluePos).distance, lessThan(1.0));
    expect(tester.getSize(blueTit).width, closeTo(startBlueWidth, 1.0));

    // Tapping a bird still opens its card normally
    await tester.tap(robin);
    await tester.pump();
    expect(opened?.sci, 'Erithacus rubecula');
  });
}
