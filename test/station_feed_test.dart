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

  test("a day in words, with the year only when it isn't this one", () {
    expect(dayWords(DateTime(DateTime.now().year, 11, 1)).endsWith('1 Nov'), isTrue);
    expect(dayWords(DateTime(2024, 3, 3)), 'Sun 3 Mar 2024');
  });

  test("a day's weather from BirdNET-Go: nearest midday, or the latest today", () {
    final j = {
      'data': [
        {'time': '08:00:00', 'temperature': 4.2, 'weather_main': 'Clear', 'weather_desc': 'clear sky'},
        {'time': '12:10:00', 'temperature': 9.6, 'weather_main': 'Clouds', 'weather_desc': 'few clouds'},
        {'time': '18:00:00', 'temperature': 6.0, 'weather_main': 'Rain', 'weather_desc': 'light rain'},
      ]
    };
    expect(dayWeather(j, today: false), {'temperatureC': 9.6, 'symbol': 'partlycloudy_day'});
    expect(dayWeather(j, today: true), {'temperatureC': 6.0, 'symbol': 'lightrain'});
    expect(dayWeather({'data': []}, today: false), isNull);
    expect(dayWeather({'message': 'no data'}, today: false), isNull);
  });

  test('day and night: an hour counts by its middle, between sunrise and sunset', () {
    const sun = (7.5, 16.25);
    expect(inLight(7, Light.day, sun), isTrue); // 07:30 is sunrise
    expect(inLight(6, Light.day, sun), isFalse);
    expect(inLight(6, Light.night, sun), isTrue);
    expect(inLight(16, Light.day, sun), isFalse); // 16:30 is after sunset
    expect(inLight(3, Light.all, sun), isTrue);
  });

  test('a plate by the day or the night: counted again, the unheard dropped', () {
    final owl = List.filled(24, 0)..[2] = 5..[22] = 1;
    final robin = List.filled(24, 0)..[8] = 4..[12] = 6..[23] = 1;
    final rows = [
      StationSpecies(sci: 'Erithacus rubecula', common: 'Robin', count: 11, hourly: robin),
      StationSpecies(sci: 'Strix aluco', common: 'Tawny Owl', count: 6),
    ];
    const sun = (7.5, 16.25);
    final day = byLight(rows, {'Strix aluco': owl}, Light.day, sun);
    expect([for (final r in day) (r.common, r.count)], [('Robin', 10)]);
    final night = byLight(rows, {'Strix aluco': owl}, Light.night, sun);
    expect([for (final r in night) (r.common, r.count)], [('Tawny Owl', 6), ('Robin', 1)]);
    expect(byLight(rows, const {}, Light.all, sun), same(rows));
  });

  test("calls by hour from BirdNET-Go's succession or its daily lists, added up", () {
    final h = <String, List<int>>{};
    addHours(h, [
      {'scientificName': 'Turdus merula', 'counts': List.filled(24, 1)},
    ]);
    addHours(h, {
      '2026-11-20': [
        {'scientific_name': 'Turdus merula', 'hourly_counts': List.filled(24, 2)},
      ],
      '2026-11-21': [
        {'scientific_name': 'Pica pica', 'hourly_counts': List.filled(24, 1)},
      ],
    });
    expect(h['Turdus merula']![5], 3);
    expect(h['Pica pica']![0], 1);
    addHours(h, {'data': {'2026-11-22': [{'scientific_name': 'Pica pica', 'hourly_counts': List.filled(24, 1)}]}});
    expect(h['Pica pica']![0], 2);
  });

  test("sunrise and sunset: BirdNET-Go's, or worked out", () {
    expect(sunFrom({'sunrise': '2026-11-21T07:36:00Z', 'sunset': '2026-11-21T16:05:00Z'}), (7.6, 16 + 5 / 60));
    expect(sunFrom({'sunrise': 'x'}), isNull);
    // Glastonbury, 21 Nov: about 07:40 and 16:15 GMT
    final (rise, set) = sunHours(DateTime(2026, 11, 21), 51.15, -2.71, Duration.zero)!;
    expect(rise, closeTo(7.67, .15));
    expect(set, closeTo(16.25, .15));
    // midsummer at the North Cape: the sun doesn't set
    expect(sunHours(DateTime(2026, 6, 21), 71.2, 25.8, const Duration(hours: 2)), isNull);
  });
}
