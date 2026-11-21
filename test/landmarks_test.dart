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
  });
}
