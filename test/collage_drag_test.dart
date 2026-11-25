import 'package:birdsong_app/native/collage_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sampleBirds = [
    CollageBird('Erithacus rubecula', 'European Robin', 60, DateTime(2026, 11, 25, 9, 0)),
    CollageBird('Turdus merula', 'Common Blackbird', 20, DateTime(2026, 11, 25, 9, 5)),
    CollageBird('Parus major', 'Great Tit', 8, DateTime(2026, 11, 25, 9, 10)),
    CollageBird('Cyanistes caeruleus', 'Eurasian Blue Tit', 1, DateTime(2026, 11, 25, 9, 15)),
  ];

  Widget buildCollage(ValueChanged<CollageBird> onOpen) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: CollageView(
              birds: sampleBirds,
              art: {for (final b in sampleBirds) b.sci: null},
              size: const Size(500, 360),
              sizeBy: 'calls',
              markAt: 'below',
              newest: 'Cyanistes caeruleus',
              live: const {},
              onOpen: onOpen,
            ),
          ),
        ),
      );

  testWidgets('tap on any bird opens its card directly without moving it', (tester) async {
    CollageBird? opened;
    await tester.pumpWidget(buildCollage((b) => opened = b));
    await tester.pumpAndSettle();

    final blueTit = find.byKey(const ValueKey('Cyanistes caeruleus'));
    final robin = find.byKey(const ValueKey('Erithacus rubecula'));

    await tester.tap(blueTit);
    await tester.pump();
    expect(opened?.sci, 'Cyanistes caeruleus');

    await tester.tap(robin);
    await tester.pump();
    expect(opened?.sci, 'Erithacus rubecula');
  });

  testWidgets('dragging promotes the bird under pointer to the centre without opening card, then resets after 10s',
      (tester) async {
    CollageBird? opened;
    await tester.pumpWidget(buildCollage((b) => opened = b));
    await tester.pumpAndSettle();

    final robin = find.byKey(const ValueKey('Erithacus rubecula'));
    final blueTit = find.byKey(const ValueKey('Cyanistes caeruleus'));
    final startBlueWidth = tester.getSize(blueTit).width;

    // Drag starting on peripheral Blue Tit -> moves it to centre, does NOT open card
    await tester.timedDrag(blueTit, const Offset(30, 10), const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(opened, isNull);
    expect(tester.getSize(blueTit).width, greaterThan(startBlueWidth * 1.5));
    expect(tester.getSize(blueTit).width, greaterThan(tester.getSize(robin).width));

    // After 5s, still promoted
    await tester.pump(const Duration(seconds: 5));
    expect(tester.getSize(blueTit).width, greaterThan(tester.getSize(robin).width));

    // After 10s total idle, resets smoothly back to default
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(tester.getSize(blueTit).width, closeTo(startBlueWidth, 1.0));
  });
}
