import 'dart:convert';
import 'dart:io';

import 'package:birdsong_app/native/landmarks.dart' show Area;
import 'package:birdsong_app/native/walk_names.dart';
import 'package:birdsong_app/store/detection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' hide Path;

List<List<List<LatLng>>> box(double s, double w, double n, double e) => [
      [
        [LatLng(s, w), LatLng(s, e), LatLng(n, e), LatLng(n, w), LatLng(s, w)]
      ]
    ];

void main() {
  test('the reserve walked through most is the one named', () {
    final reserves = [
      Area('Shapwick Heath', 'Nature reserve', box(51.14, -2.82, 51.15, -2.80)),
      Area('RSPB Ham Wall', 'Nature reserve', box(51.15, -2.79, 51.16, -2.77)),
    ];
    final walk = [LatLng(51.145, -2.81), LatLng(51.155, -2.78), LatLng(51.156, -2.78), LatLng(51.157, -2.78)];
    expect(mostIn(reserves, walk), 'RSPB Ham Wall');
    expect(mostIn(reserves, [LatLng(51.2, -2.7)]), isNull);
  });

  test('each point goes to the box with the nearest middle; the most points win', () {
    final places = OsPlaces.parse('Big Forest\tw\t51.0\t-3.0\t51.1\t-2.9\n'
        'Little Copse\tw\t51.04\t-2.96\t51.05\t-2.95\n'
        'Far Heath\tl\t52.0\t-1.0\t52.01\t-0.99\n');
    expect(mostInBox(places, [LatLng(51.045, -2.955)]), 'Little Copse');
    expect(mostInBox(places, [LatLng(51.045, -2.955), LatLng(51.02, -2.92), LatLng(51.08, -2.92)]), 'Big Forest');
    expect(mostInBox(places, [LatLng(50.5, -3.5)]), isNull);
  });

  test('the shipped OS file names Stockhill and Loxley Wood', () {
    final text = utf8.decode(gzip.decode(File('assets/places/os_woods.tsv.gz').readAsBytesSync()));
    final places = OsPlaces.parse(text);
    // a walk in Stockhill, Mendip, and one in Loxley Wood, Polden Hills
    expect(mostInBox(places, [LatLng(51.262, -2.640), LatLng(51.264, -2.636), LatLng(51.260, -2.645)]), 'Stockhill');
    expect(mostInBox(places, [LatLng(51.1339, -2.8467)]), 'Loxley Wood');
  });

  test('ended walks get their area once, every session of the walk, saved', () async {
    final root = await Directory.systemTemp.createTemp('birdsong_names_');
    addTearDown(() => root.delete(recursive: true));
    final store = await DetectionStore.open(root);
    final t0 = DateTime(2026, 11, 21, 9);
    final a = await store.startSession(at: t0, lat: 51.15, lon: -2.78);
    store.addTrackPoint(a, TrackPoint(at: t0.add(const Duration(minutes: 1)), lat: 51.155, lon: -2.78));
    await store.endSession(a, at: t0.add(const Duration(minutes: 30)));
    final live = await store.startSession(at: t0.add(const Duration(hours: 2)), lat: 51.26, lon: -2.64);

    final asked = <List<(double, double)>>[];
    await store.nameAreas((path) async {
      asked.add(path);
      return 'RSPB Ham Wall';
    });
    expect(asked, hasLength(1)); // not the one still listening
    expect(asked.single, contains((51.155, -2.78)));
    expect(a.placeArea, 'RSPB Ham Wall');
    expect(live.placeArea, isNull);
    expect(a.toJson(const [])['placeArea'], 'RSPB Ham Wall');

    // offline: nothing saved, asked again next time
    a.placeArea = null;
    await store.nameAreas((_) async => null);
    expect(a.placeArea, isNull);
  });
}
