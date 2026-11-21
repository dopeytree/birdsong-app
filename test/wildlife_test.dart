import 'package:birdsong_app/native/landmarks.dart' show inShape;
import 'package:birdsong_app/native/mvt.dart';
import 'package:birdsong_app/native/wildlife.dart';
import 'package:flutter_test/flutter_test.dart';

// a square covering the middle of a tile, clockwise (an outer ring)
MvtFeature square(String layer, Map<String, Object?> props, {int from = 512, int to = 3584}) => MvtFeature(
      props,
      3,
      [
        [(from, from), (to, from), (to, to), (from, to), (from, from)]
      ],
      4096,
    );

void main() {
  test('habitats from the tiles: woods, heath, marsh, water and sea', () {
    expect(habitatOf('landcover', {'class': 'wood', 'subclass': 'forest'}), 'wood');
    expect(habitatOf('landcover', {'class': 'grass', 'subclass': 'heath'}), 'heath');
    expect(habitatOf('landcover', {'class': 'wetland', 'subclass': 'reedbed'}), 'wetland');
    expect(habitatOf('landcover', {'class': 'farmland'}), isNull);
    expect(habitatOf('water', {'class': 'ocean'}), 'sea');
    expect(habitatOf('water', {'class': 'lake'}), 'water');
  });

  test('about two patches in three get an animal of their habitat, inside it, the same each time', () {
    var got = 0;
    for (var x = 4000; x < 4060; x++) {
      final layers = {
        'landcover': [square('landcover', {'class': 'wood'})],
        'water': <MvtFeature>[],
      };
      final c = critterInTile(layers, 13, x, 2700);
      if (c == null) continue;
      got++;
      expect(habitatAnimals['wood'], contains(c.animal));
      expect(c.habitat, 'wood');
      final poly = mvtPolygons(layers['landcover']!.single, 13, x, 2700);
      expect(inShape(c.at, poly), isTrue);
      // the same patch, the same animal in the same place
      final again = critterInTile(layers, 13, x, 2700)!;
      expect((again.animal, again.at), (c.animal, c.at));
    }
    expect(got, inInclusiveRange(25, 55)); // of 60, about 40
  });

  test('a sliver of habitat gets nothing; the largest habitat wins', () {
    final sliver = {
      'landcover': [square('landcover', {'class': 'wood'}, from: 2000, to: 2400)],
      'water': <MvtFeature>[],
    };
    for (var x = 0; x < 30; x++) {
      expect(critterInTile(sliver, 13, x, 0), isNull);
    }
    final mixed = {
      'landcover': [square('landcover', {'class': 'wood'}, from: 2000, to: 2600)],
      'water': [square('water', {'class': 'ocean'})],
    };
    for (var x = 0; x < 30; x++) {
      final c = critterInTile(mixed, 13, x, 0);
      if (c != null) expect(c.habitat, 'sea');
    }
  });

  test('every animal has a name, and the view looks two zooms out', () {
    for (final list in habitatAnimals.values) {
      for (final a in list) {
        expect(animalNames.containsKey(a), isTrue, reason: a);
      }
    }
    expect(critterZoom(15.3), 13);
    expect(critterZoom(11), 9);
    expect(critterZoom(5), 7);
  });
}
