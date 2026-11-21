import 'package:birdsong_app/native/station_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 11, 20);

  test("a station's times: a bare time is on the day asked for", () {
    expect(stationTime('07:42:10', day), DateTime(2026, 11, 20, 7, 42, 10));
    expect(stationTime('2026-11-19 18:05:00', day), DateTime(2026, 11, 19, 18, 5));
    expect(stationTime('', day), isNull);
    expect(stationTime(null, day), isNull);
  });

  test('BirdNET-Go rows, whichever names its version uses, most heard first', () {
    final rows = birdnetRows([
      {'scientific_name': 'Turdus merula', 'common_name': 'Blackbird', 'count': 3, 'last_heard': '07:42:10'},
      {'scientificName': 'Erithacus rubecula', 'commonName': 'Robin', 'total': 9, 'max_confidence': .91,
       'days_since_first_seen': 40, 'hourly_counts': List.filled(24, 1)},
      {'scientific_name': '', 'count': 5},
      {'scientific_name': 'Parus major', 'count': 0},
    ], day);
    expect(rows.map((r) => r.common), ['Robin', 'Blackbird']);
    expect(rows.first.maxConf, .91);
    expect(rows.first.daysKnown, 40);
    expect(rows.first.hourly, hasLength(24));
    expect(rows.last.last, DateTime(2026, 11, 20, 7, 42, 10));
    // wrapped in an object, as some versions answer
    expect(birdnetRows({'data': [{'scientific_name': 'Pica pica', 'count': 1}]}, day).single.sci, 'Pica pica');
  });
}
