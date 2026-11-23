import 'package:birdsong_app/native/bird_records.dart';
import 'package:birdsong_app/native/landmarks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("GBIF's match: a species' number, or none for a guess", () {
    expect(BirdRecords.keyOf({'usageKey': 2475493, 'speciesKey': 2475493, 'rank': 'SPECIES', 'matchType': 'EXACT'}),
        2475493);
    // a synonym: the accepted species' number
    expect(BirdRecords.keyOf({'usageKey': 1, 'acceptedUsageKey': 2, 'speciesKey': 2, 'rank': 'SPECIES', 'matchType': 'EXACT'}),
        2);
    expect(BirdRecords.keyOf({'matchType': 'NONE'}), isNull);
    expect(BirdRecords.keyOf({'usageKey': 9, 'rank': 'GENUS', 'matchType': 'HIGHERRANK'}), isNull);
    expect(BirdRecords.tiles(7), contains('taxonKey=7'));
  });

  test('each country is asked only about frames that touch it', () {
    const mull = [-6.3, 56.4, -5.8, 56.7], falmouth = [-5.1, 50.13, -5.05, 50.16], snowdon = [-4.1, 53.05, -4.05, 53.09];
    expect(touches(mull, 'scotland'), isTrue);
    expect(touches(mull, 'england'), isFalse);
    expect(touches(falmouth, 'england'), isTrue);
    expect(touches(falmouth, 'scotland'), isFalse);
    expect(touches(snowdon, 'wales'), isTrue);
    expect(touches(snowdon, 'scotland'), isFalse);
    // every nature service belongs to a country with a box
    for (final k in natureKinds) {
      expect(regionBoxes.containsKey(k.region), isTrue, reason: k.url);
    }
  });
}
