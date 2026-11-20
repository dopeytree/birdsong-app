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
}
