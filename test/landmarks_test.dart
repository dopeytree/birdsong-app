import 'package:birdsong_app/native/landmarks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// a walk due east along 52°N, about 1.4 km
final walk = [for (var i = 0; i <= 20; i++) LatLng(52, -1.5 + i * .001)];

// metres to degrees of latitude, near enough
double north(double m) => m / 111195;

List<List<List<LatLng>>> box(double s, double w, double n, double e) => [
      [
        [LatLng(s, w), LatLng(s, e), LatLng(n, e), LatLng(n, w), LatLng(s, w)]
      ]
    ];

void main() {
  test('distances are haversine metres', () {
    expect(metresBetween(const LatLng(52, -1.5), LatLng(52 + north(100), -1.5)), closeTo(100, .5));
  });

  test('inside a shape, but not in its hole', () {
    final shape = [
      [
        ...box(0, 0, 10, 10).single,
        ...box(4, 4, 6, 6).single,
      ]
    ];
    expect(inShape(const LatLng(2, 2), shape), isTrue);
    expect(inShape(const LatLng(5, 5), shape), isFalse);
    expect(inShape(const LatLng(12, 5), shape), isFalse);
  });

  test('the frame is the walk and a fifth, at least about 300 m', () {
    final f = frameOf(walk);
    expect(f[0], closeTo(-1.5 - .004, 1e-9)); // .02 * .2 = .004, so the larger
    expect(f[2], closeTo(-1.48 + .004, 1e-9));
    expect(f[1], closeTo(52 - .003, 1e-9)); // no height: the least
    expect(f[3], closeTo(52 + .003, 1e-9));
  });

  test('what counts as passed, in the order the page lists it', () {
    final passed = passedOnTheWay(
      walk,
      listed: [
        Spot('Church of St Mary', 'Listed building, Grade I', LatLng(52 + north(100), -1.49)),
        Spot('Far Hall', 'Listed building, Grade II*', LatLng(52 + north(150), -1.49)),
      ],
      monuments: [
        Area('Moated site', 'Scheduled monument', box(52 + north(180), -1.492, 52 + north(300), -1.491)),
        Area('Barrow', 'Scheduled monument', box(52 + north(260), -1.492, 52 + north(400), -1.491)),
      ],
      nature: [
        Area('Long Meadow', 'Site of Special Scientific Interest', box(51.999, -1.4955, 52.001, -1.4935), kind: 'SSSI'),
        Area('Long Meadow', 'Site of Special Scientific Interest', box(51.999, -1.4955, 52.001, -1.4935), kind: 'SSSI'),
        Area('Long Meadow', 'Local Nature Reserve', box(51.999, -1.4955, 52.001, -1.4935), kind: 'LNR'),
        Area('Elsewhere Wood', 'National Nature Reserve', box(52.01, -1.495, 52.02, -1.494), kind: 'NNR'),
      ],
      wiki: [
        Spot('Little Village', 'village in England', LatLng(52 + north(350), -1.485)),
        Spot('Distant Town', 'town in England', LatLng(52 + north(900), -1.485)),
      ],
    );
    expect([for (final p in passed) p.name], [
      'Long Meadow', 'Long Meadow', // walked through, once for each kind
      'Church of St Mary', 'Moated site', // 100 m, 180 m
      'Little Village', // 350 m
    ]);
    expect(passed.first.at, isNull);
    expect(passed[2].metres, closeTo(100, 1));
  });

  test('a monument walked through is 0 m away', () {
    final p = passedOnTheWay(walk, monuments: [Area('Camp', 'Scheduled monument', box(51.999, -1.49, 52.001, -1.488))]);
    expect(p.single.metres, 0);
  });

  test("ArcGIS's GeoJSON and its own JSON read the same", () {
    final geo = featuresOf({
      'type': 'FeatureCollection',
      'features': [
        {
          'properties': {'Name': 'Church', 'Grade': 'I'},
          'geometry': {
            'type': 'Point',
            'coordinates': [-1.5, 52.0]
          }
        },
      ],
    });
    final esri = featuresOf({
      'features': [
        {
          'attributes': {'Name': 'Church', 'Grade': 'I'},
          'geometry': {'x': -1.5, 'y': 52.0}
        },
        {'attributes': {'Name': 'No place'}},
      ],
    });
    for (final fs in [geo, esri]) {
      expect(fs.length, 1);
      expect(nameOf(fs.single.props), 'Church');
      expect(shapeOf(fs.single.geometry).single.single.single, const LatLng(52, -1.5));
    }
    expect(() => featuresOf({'error': {'message': 'nope'}}), throwsException);
  });

  test('a multipolygon is each of its parts', () {
    final s = shapeOf({
      'type': 'MultiPolygon',
      'coordinates': [
        [
          [[0, 0], [1, 0], [1, 1], [0, 0]]
        ],
        [
          [[5, 5], [6, 5], [6, 6], [5, 5]],
          [[5.2, 5.2], [5.4, 5.2], [5.4, 5.4], [5.2, 5.2]]
        ],
      ],
    });
    expect(s.length, 2);
    expect(s[1].length, 2);
  });

  test('names: the first property ending in name, else Unnamed', () {
    expect(nameOf({'OBJECTID': 1, 'SSSI_NAME': 'Ham Wall'}), 'Ham Wall');
    expect(nameOf({'Name': ''}), 'Unnamed');
    expect(nameOf({'Surname': 'x'}), 'Unnamed'); // must end in _name or be name
  });

  test('a view is looked up with a quarter round it, snapped out to hundredths', () {
    final f = viewFrame(-2.80, 51.14, -2.76, 51.16);
    // holds the view and a quarter round it (.01 and .005), no more than a hundredth over
    expect(f[0], inInclusiveRange(-2.8201, -2.8099));
    expect(f[1], inInclusiveRange(51.1249, 51.1351));
    expect(f[2], inInclusiveRange(-2.7501, -2.7399));
    expect(f[3], inInclusiveRange(51.1649, 51.1751));
    for (final v in f) {
      expect((v * 100 - (v * 100).round()).abs(), lessThan(1e-6)); // on a hundredth
    }
    // a small move stays inside: nothing new is asked
    expect(frameHolds(f, viewFrame(-2.799, 51.141, -2.761, 51.159)), isTrue);
    expect(frameHolds(f, viewFrame(-2.70, 51.14, -2.66, 51.16)), isFalse);
  });

  test("the walk's and the view's places together, each once", () {
    final church = Spot('St Mary', 'Listed building, Grade I', const LatLng(51.15, -2.78), grade: 'I');
    final tor = Area('Glastonbury Tor', 'Scheduled monument', box(51.14, -2.70, 51.15, -2.69));
    final a = Landmarks(listed: [church], monuments: [tor], passed: [Passed('St Mary', 'x', church.at, 10, 1)]);
    final b = Landmarks(
        listed: [church, Spot('Abbey', 'Listed building, Grade I', const LatLng(51.146, -2.716))], monuments: [tor]);
    final m = a.merge(b);
    expect(m.listed.map((s) => s.name), ['St Mary', 'Abbey']);
    expect(m.monuments.length, 1);
    expect(m.passed.length, 1); // the walk's list stays the walk's
  });

  test("the walk's and the view's places are merged once for each change, not each read", () {
    final l = LandmarkLookup()
      ..walk = Landmarks(listed: [Spot('A', 'x', const LatLng(52, -1.5))])
      ..view = Landmarks(listed: [Spot('B', 'x', const LatLng(52, -1.49))]);
    final first = l.current;
    expect(identical(l.current, first), isTrue);
    expect(first!.listed.length, 2);
    l.view = const Landmarks();
    expect(identical(l.current, first), isFalse);
    expect(l.current!.listed.length, 1);
  });

  test('parks, battlefields and World Heritage Sites count as passed like monuments', () {
    final p = passedOnTheWay(walk, monuments: [
      Area('Old Park', 'Registered park and garden, Grade II', box(51.999, -1.49, 52.001, -1.488)),
      Area('Far Field', 'Registered battlefield', box(52.01, -1.49, 52.02, -1.488)),
    ]);
    expect(p.map((x) => x.name), ['Old Park']);
  });

  test('a reserve leads, then the designation it lies in; a reserve within 50 m counts', () {
    final p = passedOnTheWay(walk, nature: [
      Area('Somerset Wetlands', 'National Nature Reserve', box(51.99, -1.6, 52.01, -1.4), kind: 'NNR'),
    ], reserves: [
      Area('RSPB Ham Wall', 'Nature reserve', box(51.999, -1.4955, 52.001, -1.4935), kind: 'OSM'),
      Area('Just Over the Hedge', 'Nature reserve', box(52 + north(30), -1.49, 52 + north(200), -1.488), kind: 'OSM'),
      Area('Far Fen', 'Nature reserve', box(52 + north(120), -1.49, 52 + north(300), -1.488), kind: 'OSM'),
    ]);
    expect(p.map((x) => x.name), ['RSPB Ham Wall', 'Just Over the Hedge', 'Somerset Wetlands']);
    expect(p[1].metres, closeTo(30, 1));
    expect(p[1].at, isNotNull);
  });

  test('names: capitals made ordinary, and matched without RSPB or reserve', () {
    expect(tidyName('SOMERSET WETLANDS'), 'Somerset Wetlands');
    expect(tidyName('ISLE OF PORTLAND AND THE SOLENT'), 'Isle of Portland and the Solent');
    expect(tidyName('Ham Wall'), 'Ham Wall');
    expect(plainName('RSPB Ham Wall'), plainName('Ham Wall'));
    expect(plainName('Shapwick Heath National Nature Reserve'), 'shapwick heath');
    expect(nameOf({'NNR_NAME': 'SOMERSET WETLANDS'}), 'Somerset Wetlands');
  });

  test("each line opens its page: Wikipedia, Historic England's entry, or a search", () {
    expect(wikiLink('Ham Wall'), 'https://en.wikipedia.org/wiki/Ham_Wall');
    expect(heLink({'ListEntry': 1234567}), 'https://historicengland.org.uk/listing/the-list/list-entry/1234567');
    expect(heLink({'Name': 'x'}), isNull);
    final passed = passedOnTheWay(walk, listed: [
      Spot('Church of St Mary', 'Listed building, Grade I', LatLng(52 + north(50), -1.49), link: heLink({'ListEntry': 1})),
    ], nature: [
      Area('Long Meadow', 'Site of Special Scientific Interest', box(51.999, -1.4955, 52.001, -1.4935), kind: 'SSSI'),
    ]);
    expect(passed[0].page.host, 'www.google.com'); // no page of its own: a search
    expect(passed[0].page.queryParameters['q'], 'Long Meadow Site of Special Scientific Interest');
    expect(passed[1].page.toString(), 'https://historicengland.org.uk/listing/the-list/list-entry/1');
  });

  test('Wikipedia places, with or without a description', () {
    final w = wikiOf({
      'query': {
        'pages': {
          '1': {
            'title': 'Ham Wall',
            'description': 'nature reserve',
            'coordinates': [
              {'lat': 51.15, 'lon': -2.78}
            ]
          },
          '2': {
            'title': 'Glastonbury',
            'coordinates': [
              {'lat': 51.14, 'lon': -2.71}
            ]
          },
          '3': {'title': 'Nowhere'},
        }
      }
    });
    expect([for (final s in w) '${s.name}: ${s.about}'], ['Ham Wall: nature reserve', 'Glastonbury: Wikipedia']);
    expect(w.first.link, 'https://en.wikipedia.org/wiki/Ham_Wall');
  });
}
