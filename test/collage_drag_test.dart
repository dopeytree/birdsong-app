import 'dart:math' as math;

import 'package:birdsong_app/native/collage_layout.dart';
import 'package:birdsong_app/native/collage_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const box = Size(600, 400);
  const items = [
    CollageItem('top', weight: 100, aspect: 1.0),
    CollageItem('mid1', weight: 50, aspect: 1.0),
    CollageItem('mid2', weight: 30, aspect: 1.0),
    CollageItem('mid3', weight: 20, aspect: 1.0),
    CollageItem('mid4', weight: 15, aspect: 1.0),
    CollageItem('mid5', weight: 10, aspect: 1.0),
    CollageItem('mid6', weight: 8, aspect: 1.0),
    CollageItem('mid7', weight: 5, aspect: 1.0),
    CollageItem('rare', weight: 1, aspect: 1.0),
  ];

  test('at rest the highest-weight bird sits dead centre at hero size and full opacity', () {
    final places = layoutSphereCollage(items, box);
    final byId = {for (final p in places) p.id: p};
    final top = byId['top']!;
    final rare = byId['rare']!;
    expect(top.z, closeTo(1.0, 1e-6));
    expect(top.opacity, 1.0);
    expect(top.rect.center.dx, closeTo(box.width / 2, 0.5));
    expect(top.rect.center.dy, closeTo(box.height / 2, 0.5));
    expect(top.rect.width, greaterThan(rare.rect.width * 2));
    // Back-hemisphere bird fades gently
    expect(rare.z, lessThan(0));
    expect(rare.opacity, lessThan(0.5));
  });

  test('rotating the 3D sphere 180° brings a rare bird to equal hero size and fades the old hero behind', () {
    final rest = {for (final p in layoutSphereCollage(items, box)) p.id: p};
    final flipped = {
      for (final p in layoutSphereCollage(items, box, rotation: SphereQuat.axisAngle(0, 1, 0, math.pi))) p.id: p
    };
    final rareFront = flipped['rare']!;
    final topBack = flipped['top']!;
    // Rare bird rotated to front grows large and opaque, matching hero scale
    expect(rareFront.z, greaterThan(0.6));
    expect(rareFront.opacity, 1.0);
    expect(rareFront.rect.width, greaterThan(rest['rare']!.rect.width * 2));
    // Old hero rotated to the back shrinks and fades gently
    expect(topBack.z, closeTo(-1.0, 1e-6));
    expect(topBack.opacity, lessThan(0.25));
    expect(topBack.rect.width, lessThan(rest['top']!.rect.width * 0.4));
  });

  test('slerp smoothly interpolates back to identity rotation', () {
    final q = SphereQuat.axisAngle(0, 1, 0, 1.2) * SphereQuat.axisAngle(1, 0, 0, 0.6);
    final mid = q.slerp(SphereQuat.identity, 0.5);
    final end = q.slerp(SphereQuat.identity, 1.0);
    expect(mid.isIdentity, isFalse);
    expect(end.isIdentity, isTrue);
  });

  testWidgets('dragging rotates the 3D sphere, tapping opens a front bird, and idle resets after 10s', (tester) async {
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
    final startWidth = tester.getSize(robin).width;

    // Drag across the collage to rotate the 3D sphere
    await tester.timedDrag(find.byType(CollageView), const Offset(110, 40), const Duration(milliseconds: 300));
    await tester.pump();
    final rotatedPos = tester.getCenter(robin);
    expect((rotatedPos - startPos).distance, greaterThan(15));

    // After 5s, still rotated (10s hasn't elapsed yet)
    await tester.pump(const Duration(seconds: 5));
    expect((tester.getCenter(robin) - startPos).distance, greaterThan(15));

    // Another drag restarts the 10s countdown
    await tester.timedDrag(find.byType(CollageView), const Offset(20, 0), const Duration(milliseconds: 150));
    await tester.pump(const Duration(seconds: 6));
    expect((tester.getCenter(robin) - startPos).distance, greaterThan(15));

    // 4+ more seconds (total 10s since last drag) -> smoothly slerps back to default
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect((tester.getCenter(robin) - startPos).distance, lessThan(1.0));
    expect(tester.getSize(robin).width, closeTo(startWidth, 1.0));

    // Tapping the front hero bird opens its card
    await tester.tap(robin);
    await tester.pump();
    expect(opened?.sci, 'Erithacus rubecula');
  });
}
