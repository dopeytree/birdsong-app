import 'dart:math' as math;
import 'dart:typed_data';

import 'package:birdsong_app/engine/scribble_trace.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List tone(double hz, double amp, double seconds, {int rate = 48000}) => Float32List.fromList([
      for (var i = 0; i < rate * seconds; i++) amp * math.sin(2 * math.pi * hz * i / rate),
    ]);

void main() {
  test('starts full of quiet', () {
    final t = ScribbleTrace(capacity: 100);
    expect(t.count, 100);
    final w = t.window(t.count - 50, 50);
    expect(w.level.every((v) => v == 0), isTrue);
    for (var k = 1; k < 50; k++) {
      expect(w.phase[k], greaterThan(w.phase[k - 1]));
    }
  });

  test('a loud high song after quiet reads loud and high, then resets', () {
    final t = ScribbleTrace(capacity: 200);
    t.add(tone(4000, .0005, 1)); // a quiet room
    final before = t.count;
    t.add(tone(4000, .3, .5)); // a bird
    expect(t.count - before, 25); // 20 ms slices
    final w = t.window(t.count - 10, 10);
    expect(w.level.last, greaterThan(.8));
    expect(w.pitch.last, closeTo((4000 - 800) / 6000, .05));
    t.reset();
    expect(t.window(t.count - 10, 10).level.every((v) => v == 0), isTrue);
  });

  test('slices not kept are quiet', () {
    final t = ScribbleTrace(capacity: 50);
    final w = t.window(-20, 30);
    expect(w.level.every((v) => v == 0), isTrue);
    expect(w.phase.length, 30);
  });
}
