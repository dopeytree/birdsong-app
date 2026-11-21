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
}
