import 'dart:convert';

import 'package:birdsong_app/native/station_archive.dart';
import 'package:birdsong_app/native/station_feed.dart';
import 'package:birdsong_app/settings.dart';
import 'package:birdsong_app/store/detection_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final go = Station(id: 's1/x', name: 'Garden', birdnetUrl: 'http://garden.local:8080');
  final day = DateTime(2026, 11, 20);
  final calls = [
    StationCall(
        id: 41,
        at: DateTime(2026, 11, 20, 7, 42, 10),
        sci: 'Erithacus rubecula',
        common: 'Robin',
        confidence: .91,
        verified: 'correct',
        audioUrl: 'http://garden.local:8080/api/v2/audio/41'),
    StationCall(
        id: 42, at: DateTime(2026, 11, 20, 16, 5), sci: 'Strix aluco', common: 'Tawny Owl', confidence: .8),
    StationCall(
        id: 43, at: DateTime(2026, 11, 20, 17), sci: 'Strix aluco', common: 'Tawny Owl', confidence: .7),
  ];

  test("a station's id as a folder name", () {
    expect(StationArchive.safeName('s1/x:y'), 's1_x_y');
  });

  test('a day counted from its raw detections keeps every species, most heard first', () {
    // BirdNET-Go's daily summary drops bat species the detections list has;
    // the plate counts the kept calls instead, so none are lost.
    final jsonl = [
      for (final c in [
        ...calls,
        StationCall(id: 1, at: DateTime(2026, 11, 23, 20, 32), sci: 'Tadarida teniotis', common: 'European Free-tailed Bat', confidence: .82, daysKnown: 40),
        StationCall(id: 2, at: DateTime(2026, 11, 23, 20, 29), sci: 'Nyctalus noctula', common: 'Noctule bat', confidence: .51),
        StationCall(id: 3, at: DateTime(2026, 11, 23, 20, 4), sci: 'Tadarida teniotis', common: 'European Free-tailed Bat', confidence: .98, daysKnown: 40),
      ])
        jsonEncode(stationCallJson(go, c))
    ].join('\n');
    final rows = speciesFromCalls(jsonl);
    expect(rows.map((r) => r.common), ['Tawny Owl', 'European Free-tailed Bat', 'Robin', 'Noctule bat']);
    expect(rows.first.count, 2);
    expect(rows[1].maxConf, .98);
    // how long the station has known it, and the usual confidence, survive the count
    final bat = rows[1];
    expect(bat.daysKnown, 40);
    expect(bat.avgConf, closeTo((.82 + .98) / 2, .001));
    // calls by hour, so day and night can be split without asking again
    expect(bat.hourly![20], 2);
    expect(bat.hourly!.reduce((a, b) => a + b), 2);
    // a line that won't parse is skipped, not fatal
    expect(speciesFromCalls('$jsonl\nnot json\n').length, rows.length);
    expect(speciesFromCalls(''), isEmpty);
  });

  test("a station's day as Listen's session.json, with the station and the day", () {
    final j = stationSessionJson(go, (51.12, -2.73), day, calls, uuid: 'u-1', complete: true);
    expect(j['schemaVersion'], sessionSchemaVersion);
    expect(j['id'], 20261120);
    expect(j['day'], '2026-11-20');
    expect(j['complete'], isTrue);
    expect(j['latitude'], 51.12);
    expect((j['station'] as Map)['name'], 'Garden');
    expect((j['station'] as Map)['birdnetUrl'], 'http://garden.local:8080');
    expect(j['summary'], {'detections': 3, 'species': 2});
    expect(DateTime.parse(j['startTime'] as String).toLocal(), DateTime(2026, 11, 20, 7, 42, 10));
    // and it reads back as one of Listen's sessions
    final s = Session.fromJson(j, '2026-11-20');
    expect(s.start, DateTime(2026, 11, 20, 7, 42, 10));
    expect(s.hasPlace, isTrue);
  });

  test("a call as Listen's detection line, with the station's links", () {
    final j = stationCallJson(go, calls.first);
    expect(j['scientificName'], 'Erithacus rubecula');
    expect(j['model'], 'BirdNET-Go');
    expect(j['reviewStatus'], 'correct');
    expect(j['stationDetectionId'], 41);
    expect(j['audioUrl'], 'http://garden.local:8080/api/v2/audio/41');
    final d = Detection.fromJson(j);
    expect(d.common, 'Robin');
    expect(d.at, DateTime(2026, 11, 20, 7, 42, 10));
  });

  test("the calendar's counts from BirdNET-Go's daily lists", () {
    final sums = daySumsOf({
      '2026-11-19': [
        {'scientific_name': 'Turdus merula', 'count': 3},
        {'scientific_name': 'Pica pica', 'count': 2},
      ],
      '2026-11-20': [],
    }, ['2026-11-19', '2026-11-20', '2026-11-21']);
    expect(sums, {'2026-11-19': (2, 5), '2026-11-20': (0, 0)});
    expect(daySumsOf({'data': {'2026-11-19': [{'count': 1}]}}, ['2026-11-19']), {'2026-11-19': (1, 1)});
  });

  test('what is known of a day goes to days.json and back', () {
    const k = StationDay(species: 4, calls: 30, saved: true, complete: true);
    final back = StationDay.fromJson(k.toJson());
    expect((back.species, back.calls, back.saved, back.complete), (4, 30, true, true));
    expect(const StationDay(species: 0, calls: 0).toJson(), {'species': 0, 'calls': 0});
  });
}
