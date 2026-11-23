import 'package:birdsong_app/native/walk_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a name box is centred under the heart', () {
    final box = birdNameBox(const Offset(100, 200), 'Robin');
    expect(box.top, 215);
    expect(box.height, 15);
    expect(box.width, closeTo('Robin'.length * 6.2 + 6, 0.001));
    expect(box.center.dx, 100);
  });

  test('overlapping names keep only the earliest', () {
    final boxes = [
      birdNameBox(const Offset(100, 100), 'Robin'),
      birdNameBox(const Offset(108, 100), 'Blackbird'),
      birdNameBox(const Offset(400, 100), 'Wren'),
    ];
    expect(boxes[0].overlaps(boxes[1]), isTrue);
    expect(boxes[0].overlaps(boxes[2]), isFalse);
    expect(birdNamesToKeep(boxes), [0, 2]);
  });

  test('a later name is kept when it misses the ones already shown', () {
    final boxes = [
      birdNameBox(const Offset(0, 0), 'A'),
      birdNameBox(const Offset(8, 0), 'BB'),
      birdNameBox(const Offset(80, 0), 'C'),
    ];
    expect(birdNamesToKeep(boxes), [0, 2]);
  });

  test('nothing overlapping keeps every name, in order', () {
    final boxes = [
      birdNameBox(const Offset(0, 0), 'Robin'),
      birdNameBox(const Offset(200, 0), 'Wren'),
    ];
    expect(birdNamesToKeep(boxes), [0, 1]);
    expect(birdNamesToKeep(const []), isEmpty);
  });
}
