import 'package:birdsong_app/native/plate_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a plate of the right bird on plain paper beats a famous hand on another', () {
    const sci = 'Erithacus rubecula', common = 'European Robin';
    final right = PlateLibrary.scorePlate('Erithacus rubecula Naumann.jpg', sci, common);
    final other = PlateLibrary.scorePlate('Gould Birds of Europe plate 12.jpg', sci, common);
    expect(right, greaterThan(other));
  });

  test('maps, stamps, eggs and sound files are passed over', () {
    for (final t in [
      'Erithacus rubecula distribution map.png',
      'Robin stamp 1966.jpg',
      'Erithacus rubecula egg.jpg',
      'Erithacus rubecula song.ogg',
    ]) {
      expect(PlateLibrary.scorePlate(t, 'Erithacus rubecula', 'European Robin'), -1, reason: t);
    }
  });

  test('two creatures to a page score lower than one', () {
    const sci = 'Turdus merula', common = 'Common Blackbird';
    expect(PlateLibrary.scorePlate('Turdus merula Keulemans.jpg', sci, common),
        greaterThan(PlateLibrary.scorePlate('Turdus merula and Turdus pilaris Keulemans.jpg', sci, common)));
  });

  test('skulls, wings and eggs: passed over, or offered but never first', () {
    const sci = 'Erithacus rubecula', common = 'European Robin';
    expect(PlateLibrary.plateKind('Erithacus rubecula eggs Naumann.jpg'), 'egg');
    expect(PlateLibrary.plateKind('Skull of a robin.jpg'), 'skull');
    expect(PlateLibrary.plateKind('Erithacus rubecula Naumann.jpg'), '');
    expect(PlateLibrary.scorePlate('Erithacus rubecula eggs Naumann.jpg', sci, common), -1);
    final egg = PlateLibrary.scorePlate('Erithacus rubecula eggs Naumann.jpg', sci, common, parts: true);
    final bird = PlateLibrary.scorePlate('Erithacus rubecula Naumann.jpg', sci, common, parts: true);
    expect(egg, greaterThan(0));
    expect(egg, lessThan(bird));
  });

  test("the page's artists and dated files are scored as the page scores them", () {
    const sci = 'Turdus merula', common = 'Common Blackbird';
    expect(PlateLibrary.scorePlate('Turdus merula 1880.jpg', sci, common), 70 + 50);
    expect(PlateLibrary.scorePlate('Keulemans Onze Vogels Merel.jpg', sci, common), 90);
  });
}
