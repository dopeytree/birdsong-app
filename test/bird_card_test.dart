import 'package:birdsong_app/native/bird_card.dart';
import 'package:birdsong_app/native/plate_library.dart';
import 'package:birdsong_app/store/detection_store.dart';
import 'package:flutter_test/flutter_test.dart';

Detection heard(int id, String sci, DateTime at, double c) =>
    Detection(id: id, model: 'm', sci: sci, common: sci, confidence: c, at: at);

void main() {
  final now = DateTime(2026, 11, 20, 21, 0);

  test('times read as the page writes them', () {
    expect(whenHeard(DateTime(2026, 11, 20, 7, 4), now: now), 'today at 07:04');
    expect(whenHeard(DateTime(2026, 3, 2, 18, 30), now: now), '2 March 2026, 18:30');
    expect(dayLabel(DateTime(2026, 11, 20)), '20 Nov');
    expect(inHundred(.873), '87 in 100');
  });

  test('a summary gives its second and third sentences', () {
    const t = 'The Eurasian wren (Troglodytes troglodytes) is a very small bird. It is the only wren found '
        'in Eurasia. In Britain it is often just called the wren. It feeds on insects.';
    expect(blurbFrom(t), 'It is the only wren found in Eurasia. In Britain it is often just called the wren.');
    expect(blurbFrom('Only one sentence here.'), 'Only one sentence here.');
  });

  test('the facts of one species, newest first', () {
    final ds = [
      heard(1, 'Turdus merula', DateTime(2026, 11, 20, 7, 0), .6),
      heard(2, 'Erithacus rubecula', DateTime(2026, 11, 20, 7, 5), .9),
      heard(3, 'Turdus merula', DateTime(2026, 11, 20, 8, 15), .8),
    ];
    final ever = [heard(9, 'Turdus merula', DateTime(2026, 11, 1, 6, 0), .5), ...ds];
    final f = BirdFacts.of('Turdus merula', 'Blackbird', ds, ever, now: now);
    expect(f.count, 2);
    expect(f.latest.first.id, 3);
    expect(f.maxConfidence, .8);
    expect(f.avgConfidence, closeTo(.7, 1e-9));
    expect(f.daysKnown, 19);
    expect(f.hours[7], 1);
    expect(f.hours[8], 1);
    final trend = f.trend(today: now);
    expect(trend.length, 30);
    expect(trend.last.count, 2);
    expect(f.rows.first, ('Heard', '2 calls'));
    expect(f.rows.map((r) => r.$1), contains('Known at this station'));
  });
}
