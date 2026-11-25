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

  testWidgets('2-stage tap: first tap brings a bird to the centre with +, second tap opens card, idle resets after 10s',
      (tester) async {
    CollageBird? opened;
    await tester.pumpWidget(buildCollage((b) => opened = b));
    await tester.pumpAndSettle();

    final robin = find.byKey(const ValueKey('Erithacus rubecula'));
    final blueTit = find.byKey(const ValueKey('Cyanistes caeruleus'));
    final startBlueWidth = tester.getSize(blueTit).width;

    // Centre bird shows the + indicator
    expect(find.text('+'), findsOneWidget);

    // 1st tap on non-centre Blue Tit promotes it to centre, does NOT open card yet
    await tester.tap(blueTit);
    await tester.pumpAndSettle();
    expect(opened, isNull);
    expect(tester.getSize(blueTit).width, greaterThan(startBlueWidth * 1.5));
    expect(tester.getSize(blueTit).width, greaterThan(tester.getSize(robin).width));

    // 2nd tap on Blue Tit (now in centre) opens its card
    await tester.tap(blueTit);
    await tester.pump();
    expect(opened?.sci, 'Cyanistes caeruleus');

    // After 10s idle, layout glides back to default (Robin in centre)
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(tester.getSize(blueTit).width, closeTo(startBlueWidth, 1.0));
  });

  testWidgets('long-press and double-tap on a non-centre bird open its card directly', (tester) async {
    CollageBird? opened;
    await tester.pumpWidget(buildCollage((b) => opened = b));
    await tester.pumpAndSettle();

    final blackbird = find.byKey(const ValueKey('Turdus merula'));
    final greatTit = find.byKey(const ValueKey('Parus major'));

    // Long press opens card directly
    await tester.longPress(blackbird);
    await tester.pump();
    expect(opened?.sci, 'Turdus merula');

    // Fast double-tap on another non-centre bird opens card directly
    opened = null;
    await tester.tap(greatTit);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(greatTit);
    await tester.pump();
    expect(opened?.sci, 'Parus major');

    // Let the 10s timer flush cleanly before test ends
    await tester.pump(const Duration(seconds: 11));
  });
}
