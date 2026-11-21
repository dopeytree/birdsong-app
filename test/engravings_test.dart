import 'package:birdsong_app/native/engravings.dart';
import 'package:birdsong_app/native/wildlife.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the heading is the word in capitals, not the word in the text', () {
    final json = <String, Object?>{
      'resources': [
        {'on': 'https://x/canvases/b1_0277.jp2#xywh=284,981,171,64', 'resource': {'chars': 'Otter,'}},
        {'on': 'https://x/canvases/b1_0504.jp2#xywh=1116,1744,282,89', 'resource': {'chars': 'OTTER.'}},
      ],
    };
    final h = headingHit(json, 'OTTER')!;
    expect((h.file, h.x, h.y, h.w, h.h), ('b1_0504.jp2', 1116, 1744, 282, 89));
    expect(headingHit(json, 'SEAL'), isNull);
    expect(headingHit(const {}, 'OTTER'), isNull);
  });

  test('the engraving is looked for just above its heading, then just below', () {
    final h = (file: 'p.jp2', x: 1116, y: 1744, w: 282, h: 89);
    expect(engravingRegions(h), ['0,244,9000,1490', '0,1843,9000,1500']);
    // a heading at the top of the page: only below
    expect(engravingRegions((file: 'p.jp2', x: 0, y: 60, w: 10, h: 10)), ['0,80,9000,1500']);
  });

  test('every water and sea animal has an engraving to fetch', () {
    for (final a in [...habitatAnimals['water']!, ...habitatAnimals['sea']!]) {
      expect(Engravings.has(a), isTrue, reason: a);
    }
  });
}
