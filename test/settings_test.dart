import 'dart:convert';
import 'dart:io';

import 'package:birdsong_app/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('birdsong_settings_'));
  tearDown(() async => root.delete(recursive: true));

  Future<Settings> loadWith(Map<String, dynamic> j) async {
    await File('${root.path}/settings.json').writeAsString(jsonEncode(j));
    return Settings.load(root);
  }

  test('the plate modes run a to g', () {
    expect([for (var i = 1; i <= plateModes.length; i++) plateLetter(i)].join(), 'abcdefg');
    expect(plateModes.map((m) => m.key).toList(),
        ['calls', 'latest', 'top', 'index', 'noindex', 'time', 'equal']);
  });

  test('a mode is kept by its key', () async {
    final s = await loadWith({'plateView': 'top'});
    expect(plateModes[s.plateMode - 1].key, 'top');
    expect(s.toJson()['plateView'], 'top');
  });

  test('a number saved in the first order finds the same mode', () async {
    // 5 was the index alone; it is d now.
    final s = await loadWith({'plateMode': 5});
    expect(plateLetter(s.plateMode), 'd');
    // 2 was recent ramblings; it is f now.
    expect(plateLetter((await loadWith({'plateMode': 2})).plateMode), 'f');
  });

  test('an old single station becomes the first saved station', () async {
    final s = await loadWith({'mode': 'station', 'birdnetUrl': 'https://birdnet.example.net'});
    expect(s.stations.length, 1);
    expect(s.station!.name, 'BirdNET-Go');
    expect(s.birdnetBase, 'https://birdnet.example.net');
    expect(s.stationDigits, '');
    // a BirdWeather number set as well was the one in use, and still is
    final both = await loadWith({'birdnetUrl': 'http://10.0.0.2:8080', 'birdweatherStation': '1234'});
    expect(both.stations.length, 2);
    expect(both.stationDigits, '1234');
    expect(both.birdnetUrl, '');
  });

  test('the station button goes to the last station, then steps between stations', () async {
    final s = await loadWith({'mode': 'listen'});
    s.putStation(Station.fromInput('Garden', 'http://192.168.1.50:8080'));
    s.putStation(Station.fromInput('Allotment', 'https://app.birdweather.com/stations/1234'));
    s.update((x) => x.mode = AppMode.listen);
    s.nextStation();
    expect(s.mode, AppMode.station);
    expect(s.station!.name, 'Allotment');   // the one last shown
    s.nextStation();
    expect(s.station!.name, 'Garden');
    s.nextStation();
    expect(s.station!.name, 'Allotment');
    // and it is all saved
    await s.saved;
    final again = await Settings.load(root);
    expect(again.stations.map((x) => x.name), ['Garden', 'Allotment']);
    expect(again.station!.name, 'Allotment');
  });

  test('a station is read from a number, a BirdWeather page or an address', () {
    expect(Station.fromInput('', '1234').kind, 'BirdWeather 1234');
    expect(Station.fromInput('', 'https://app.birdweather.com/stations/987').birdweather, '987');
    final b = Station.fromInput('', 'http://192.168.1.50:8080');
    expect(b.kind, 'BirdNET-Go');
    expect(b.name, 'BirdNET-Go');
    expect(Station.fromInput('Garden', '1234').name, 'Garden');
  });

  test('removing the station on show moves to the next, or back here', () async {
    final s = await loadWith({});
    s.putStation(Station.fromInput('A', '1'));
    s.putStation(Station.fromInput('B', '2'));
    s.removeStation(s.station!.id);
    expect(s.station!.name, 'A');
    s.removeStation(s.station!.id);
    expect(s.mode, AppMode.listen);
    expect(s.stations, isEmpty);
  });

  test('the Flutter plate is the plate, even where the old file said otherwise', () async {
    expect((await loadWith({})).nativePlate, isTrue);
    // every saved file says nativePlate: false; it is no longer read
    expect((await loadWith({'nativePlate': false})).nativePlate, isTrue);
    final web = await loadWith({'webPlate': true});
    expect((web.nativePlate, web.toJson()['webPlate']), (false, true));
    final s = await loadWith({'nativeShowTitle': false});
    expect((s.nativeShowTitle, s.nativeShowDate), (false, true));
  });

  test('the Flutter plate marks the latest below and fits one screen, unless told otherwise', () async {
    final s = await loadWith({});
    expect(s.nativeMarkAt, 'below');
    expect(s.nativeFit, isTrue);
    expect(s.nativeIndexFolded, isTrue);
    // a first run opens on recent ramblings
    expect(plateModes[s.plateMode - 1].key, 'time');
    expect(s.nativeTotals, isFalse);
    expect((await loadWith({'nativeTotals': true})).toJson()['nativeTotals'], isTrue);
    expect((await loadWith({'nativeIndexFolded': false})).toJson()['nativeIndexFolded'], isFalse);
    final t = await loadWith({'nativeMarkAt': 'fade', 'nativeFit': false});
    expect(t.toJson()['nativeMarkAt'], 'fade');
    expect(t.toJson()['nativeFit'], isFalse);
    // a value this version does not know falls back
    expect((await loadWith({'nativeMarkAt': 'sideways'})).nativeMarkAt, 'below');
  });

  test("a station's past days: as answered, else yes on a computer", () async {
    final s = await loadWith({
      'stations': [
        {'id': 'a', 'name': 'Garden', 'birdnetUrl': 'http://garden.local'},
        {'id': 'b', 'name': 'Wood', 'birdweather': '1234'},
      ],
      'stationKeepPast': {'a': false},
    });
    expect(s.keepPastOf(s.stations[0]), isFalse);
    // the tests run on a computer, which doesn't ask
    expect(s.keepPastOf(s.stations[1]), isTrue);
    expect(s.toJson()['stationKeepPast'], {'a': false});
  });
}
