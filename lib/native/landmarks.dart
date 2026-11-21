import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' hide Path;

/// The map's extras, from assets/app/map-mode.js loadPlaces(): listed
/// buildings, scheduled monuments, registered parks and gardens and
/// battlefields, and World Heritage Sites (Historic England), protected
/// nature sites (Natural England) and Wikipedia places, round the walk and
/// wherever the map is looked at, and what of them the walk passed. Off
/// unless Settings.mapExtras: these send the area to those three.
const _he = 'https://services-eu1.arcgis.com/ZOdPfBS3aqqDYPUQ/arcgis/rest/services/'
    'National_Heritage_List_for_England_NHLE_v02_VIEW/FeatureServer';
const _ne = 'https://services.arcgis.com/JJzESW51TqeY9uat/arcgis/rest/services';
const _agent = 'Birdsong/0.1 github.com/dopeytree/birdsong';

/// A nature site's kind: its short name, what it stands for, and where it
/// is looked up.
typedef NatureKind = ({String kind, String full, String url});

const natureKinds = <NatureKind>[
  (kind: 'SPA', full: 'Special Protection Area (birds)', url: '$_ne/Special_Protection_Areas_England/FeatureServer/0'),
  (kind: 'SSSI', full: 'Site of Special Scientific Interest', url: '$_ne/SSSI_England/FeatureServer/0'),
  (kind: 'NNR', full: 'National Nature Reserve', url: '$_ne/National_Nature_Reserves_England/FeatureServer/0'),
  (kind: 'LNR', full: 'Local Nature Reserve', url: '$_ne/Local_Nature_Reserves_England/FeatureServer/0'),
];

/// Rings of polygons: each polygon is its outline, then its holes.
typedef Shape = List<List<List<LatLng>>>;

/// A listed building or a Wikipedia place: a point with a name and a line
/// about it.
class Spot {
  const Spot(this.name, this.about, this.at, {this.grade = ''});

  final String name;

  /// "Listed building, Grade II*", or the Wikipedia page's description.
  final String about;
  final LatLng at;

  /// A listed building's grade ("I", "II*"), for its size on the map.
  final String grade;
}

/// A scheduled monument or a nature site: an area with a name.
class Area {
  const Area(this.name, this.about, this.shape, {this.kind = ''});

  final String name;

  /// "Scheduled monument", or the nature site's full kind.
  final String about;
  final Shape shape;

  /// A nature site's short kind (SSSI), so two kinds of one name both count.
  final String kind;
}

/// A line of "Passed on the way": [at] null when the walk went through it
/// (a nature site), with no one point to fly to.
class Passed {
  const Passed(this.name, this.about, this.at, this.metres, this.order);

  final String name;
  final String about;
  final LatLng? at;
  final double metres;

  /// Nature sites first, then buildings and monuments, then Wikipedia.
  final int order;
}

/// What was found in one area.
class Landmarks {
  const Landmarks({
    this.listed = const [],
    this.monuments = const [],
    this.parks = const [],
    this.battlefields = const [],
    this.worldHeritage = const [],
    this.nature = const [],
    this.wiki = const [],
    this.passed = const [],
    this.unreached = const [],
  });

  final List<Spot> listed;
  final List<Area> monuments;

  /// Registered parks and gardens.
  final List<Area> parks;
  final List<Area> battlefields;

  /// World Heritage Sites.
  final List<Area> worldHeritage;
  final List<Area> nature;
  final List<Spot> wiki;

  /// What the walk passed; only for a walk's own lookup.
  final List<Passed> passed;

  /// The services that could not be reached ("Wikipedia").
  final List<String> unreached;

  /// This and [other] together, each place once (by name, kind and where).
  Landmarks merge(Landmarks other) {
    List<T> both<T>(List<T> a, List<T> b, String Function(T) key) {
      final seen = <String>{};
      return [
        for (final x in [...a, ...b])
          if (seen.add(key(x))) x
      ];
    }

    String spot(Spot s) => '${s.name}|${s.at.latitude.toStringAsFixed(5)},${s.at.longitude.toStringAsFixed(5)}';
    String area(Area a) => '${a.kind}|${a.about}|${a.name}';
    return Landmarks(
      listed: both(listed, other.listed, spot),
      monuments: both(monuments, other.monuments, area),
      parks: both(parks, other.parks, area),
      battlefields: both(battlefields, other.battlefields, area),
      worldHeritage: both(worldHeritage, other.worldHeritage, area),
      nature: both(nature, other.nature, area),
      wiki: both(wiki, other.wiki, spot),
      passed: passed,
      unreached: unreached,
    );
  }
}

// ---- geometry, as the page's ----------------------------------------------

/// Metres between two points (haversine).
double metresBetween(LatLng a, LatLng b) {
  const r = 6371000.0, k = math.pi / 180;
  final dLat = (b.latitude - a.latitude) * k, dLon = (b.longitude - a.longitude) * k;
  final s = math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.latitude * k) * math.cos(b.latitude * k) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(s));
}

bool _inRing(LatLng p, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].longitude, yi = ring[i].latitude, xj = ring[j].longitude, yj = ring[j].latitude;
    if ((yi > p.latitude) != (yj > p.latitude) && p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

/// Whether [p] is inside [shape]: in an outline and not in its holes.
bool inShape(LatLng p, Shape shape) => shape.any((rings) =>
    rings.isNotEmpty && _inRing(p, rings.first) && !rings.skip(1).any((h) => _inRing(p, h)));

/// The box looked in: the walk's, a fifth again on each side, and at least
/// about 300 m across. [west, south, east, north].
List<double> frameOf(List<LatLng> path) {
  var x0 = 180.0, y0 = 90.0, x1 = -180.0, y1 = -90.0;
  for (final p in path) {
    x0 = math.min(x0, p.longitude);
    x1 = math.max(x1, p.longitude);
    y0 = math.min(y0, p.latitude);
    y1 = math.max(y1, p.latitude);
  }
  final px = math.max(.004, (x1 - x0) * .2), py = math.max(.003, (y1 - y0) * .2);
  return [x0 - px, y0 - py, x1 + px, y1 + py];
}

/// Every nth point of the path, so no more than about 150 are measured to.
List<LatLng> probeOf(List<LatLng> path) {
  final every = math.max(1, path.length ~/ 150);
  return [for (var i = 0; i < path.length; i += every) path[i]];
}

/// What the walk passed: buildings within 120 m, monuments (and parks,
/// battlefields and World Heritage Sites) within 200 m or walked through,
/// nature sites walked through (each name and kind once), Wikipedia places
/// within 400 m; nature first, then nearest first.
List<Passed> passedOnTheWay(List<LatLng> path,
    {List<Spot> listed = const [], List<Area> monuments = const [], List<Area> nature = const [], List<Spot> wiki = const []}) {
  final probe = probeOf(path);
  if (probe.isEmpty) return const [];
  double near(LatLng p) => probe.map((q) => metresBetween(q, p)).reduce(math.min);
  final out = <Passed>[];
  for (final s in listed) {
    final d = near(s.at);
    if (d <= 120) out.add(Passed(s.name, s.about, s.at, d, 1));
  }
  for (final a in monuments) {
    final pts = [for (final rings in a.shape) for (final r in rings) ...r];
    if (pts.isEmpty) continue;
    final inside = probe.any((p) => inShape(p, a.shape));
    final every = math.max(1, pts.length ~/ 100);
    final d = inside ? 0.0 : [for (var i = 0; i < pts.length; i += every) near(pts[i])].reduce(math.min);
    if (d <= 200) out.add(Passed(a.name, a.about, pts.first, d, 1));
  }
  final seen = <String>{};
  for (final a in nature) {
    if (!seen.add('${a.kind}${a.name}')) continue;
    if (probe.any((p) => inShape(p, a.shape))) out.add(Passed(a.name, a.about, null, 0, 0));
  }
  for (final s in wiki) {
    final d = near(s.at);
    if (d <= 400) out.add(Passed(s.name, s.about, s.at, d, 2));
  }
  out.sort((a, b) => a.order != b.order ? a.order - b.order : a.metres.compareTo(b.metres));
  return out;
}

// ---- reading what the services send ----------------------------------------

/// A feature's name: its first property ending in "name" that has a value.
String nameOf(Map<String, dynamic> p) {
  final re = RegExp(r'(^|_)name$', caseSensitive: false);
  for (final e in p.entries) {
    if (re.hasMatch(e.key) && e.value != null && '${e.value}'.isNotEmpty) return '${e.value}';
  }
  return 'Unnamed';
}

LatLng _ll(Object? c) {
  final l = c as List;
  return LatLng((l[1] as num).toDouble(), (l[0] as num).toDouble());
}

List<LatLng> _ring(Object? r) => [for (final c in r as List) _ll(c)];

/// A GeoJSON geometry as a [Shape] (a point is a one-point outline).
Shape shapeOf(Map<String, dynamic> g) => switch (g['type']) {
      'Point' => [
          [
            [_ll(g['coordinates'])]
          ]
        ],
      'Polygon' => [
          [for (final r in g['coordinates'] as List) _ring(r)]
        ],
      'MultiPolygon' => [
          for (final poly in g['coordinates'] as List) [for (final r in poly as List) _ring(r)]
        ],
      _ => const [],
    };

/// The features of an ArcGIS answer, in GeoJSON (or Esri JSON, turned into
/// GeoJSON: rings, or x and y).
List<({Map<String, dynamic> props, Map<String, dynamic> geometry})> featuresOf(Map<String, dynamic> j) {
  if (j['error'] != null) throw Exception('${(j['error'] as Map)['message'] ?? 'query failed'}');
  final out = <({Map<String, dynamic> props, Map<String, dynamic> geometry})>[];
  for (final f in (j['features'] as List?) ?? const []) {
    final m = f as Map<String, dynamic>;
    final g = m['geometry'] as Map<String, dynamic>?;
    if (g == null) continue;
    if (j['type'] == 'FeatureCollection') {
      out.add((props: Map<String, dynamic>.from((m['properties'] as Map?) ?? const {}), geometry: g));
    } else {
      out.add((
        props: Map<String, dynamic>.from((m['attributes'] as Map?) ?? const {}),
        geometry: g['rings'] != null
            ? {'type': 'Polygon', 'coordinates': g['rings']}
            : {
                'type': 'Point',
                'coordinates': [g['x'], g['y']]
              },
      ));
    }
  }
  return out;
}

/// Wikipedia's geosearch answer as places.
List<Spot> wikiOf(Map<String, dynamic> j) {
  final pages = ((j['query'] as Map?)?['pages'] as Map?) ?? const {};
  return [
    for (final p in pages.values.cast<Map<String, dynamic>>())
      if ((p['coordinates'] as List?)?.isNotEmpty ?? false)
        Spot(
          '${p['title']}',
          (p['description'] as String?)?.isNotEmpty ?? false ? p['description'] as String : 'Wikipedia',
          LatLng(((p['coordinates'] as List).first['lat'] as num).toDouble(),
              ((p['coordinates'] as List).first['lon'] as num).toDouble()),
        ),
  ];
}

// ---- asking ----------------------------------------------------------------

Future<Map<String, dynamic>> _getJson(Uri u) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(u);
    req.headers.set(HttpHeaders.userAgentHeader, _agent);
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw HttpException('${res.statusCode}', uri: u);
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<List<({Map<String, dynamic> props, Map<String, dynamic> geometry})>> _arc(String url, List<double> frame,
    {String? where, double? simplify}) async {
  final q = <String, String>{
    'where': where ?? '1=1',
    'geometry': frame.join(','),
    'geometryType': 'esriGeometryEnvelope',
    'inSR': '4326',
    'spatialRel': 'esriSpatialRelIntersects',
    'outFields': '*',
    'outSR': '4326',
    'returnGeometry': 'true',
    'f': 'geojson',
    if (simplify != null) 'maxAllowableOffset': '$simplify',
    if (simplify != null) 'geometryPrecision': '6',
  };
  final j = await _getJson(Uri.parse('$url/query').replace(queryParameters: q));
  if (j['type'] == 'FeatureCollection') return featuresOf(j);
  // a server that won't give GeoJSON: ask again for its own JSON
  return featuresOf(await _getJson(Uri.parse('$url/query').replace(queryParameters: {...q, 'f': 'json'})));
}

Future<List<Spot>> _wikiNear(List<double> f, int limit) async => wikiOf(await _getJson(Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'generator': 'geosearch',
      'ggsbbox': '${f[3]}|${f[0]}|${f[1]}|${f[2]}',
      'ggslimit': '$limit',
      'prop': 'coordinates|description',
      'colimit': '$limit',
    })));

/// Look up [frame] ([west, south, east, north]): all of Historic England's
/// kinds, Natural England's and Wikipedia's, side by side; one that fails
/// is named in unreached. Grade II buildings only when [gradeTwo] (they are
/// most of them, so only for a close view). [path], when given, is a walk:
/// what it passed is worked out too.
Future<Landmarks> lookUpFrame(List<double> frame, {bool gradeTwo = false, List<LatLng>? path, int wikiLimit = 20}) async {
  final unreached = <String>[];
  var listed = <Spot>[], wiki = <Spot>[];
  var monuments = <Area>[], parks = <Area>[], battlefields = <Area>[], worldHeritage = <Area>[], nature = <Area>[];
  Future<List<Area>> areas(String url, String about, String failed, {double simplify = .00002}) =>
      _arc(url, frame, simplify: simplify).then((fs) => [
            for (final f in fs)
              Area(nameOf(f.props), f.props['Grade'] != null ? '$about, Grade ${f.props['Grade']}' : about, shapeOf(f.geometry))
          ]).catchError((Object _) {
        unreached.add(failed);
        return <Area>[];
      });
  await Future.wait([
    _arc('$_he/0', frame, where: gradeTwo ? null : "Grade IN ('I','II*')").then((fs) {
      listed = [
        for (final f in fs)
          if (f.geometry['type'] == 'Point')
            Spot(nameOf(f.props), 'Listed building, Grade ${f.props['Grade'] ?? ''}', _ll(f.geometry['coordinates']),
                grade: '${f.props['Grade'] ?? ''}'),
      ];
    }).catchError((Object _) {
      unreached.add('Historic England (buildings)');
    }),
    _arc('$_he/6', frame, simplify: .00002).then((fs) {
      monuments = [for (final f in fs) Area(nameOf(f.props), 'Scheduled monument', shapeOf(f.geometry))];
    }).catchError((Object _) {
      unreached.add('Historic England (monuments)');
    }),
    areas('$_he/7', 'Registered park and garden', 'Historic England (parks and gardens)').then((a) => parks = a),
    areas('$_he/8', 'Registered battlefield', 'Historic England (battlefields)').then((a) => battlefields = a),
    areas('$_he/10', 'World Heritage Site', 'Historic England (World Heritage Sites)', simplify: .0001)
        .then((a) => worldHeritage = a),
    Future.wait([
      for (final k in natureKinds)
        _arc(k.url, frame, simplify: .0001)
            .then((fs) => [for (final f in fs) Area(nameOf(f.props), k.full, shapeOf(f.geometry), kind: k.kind)])
            .catchError((Object _) {
          unreached.add('Natural England (${k.kind})');
          return <Area>[];
        }),
    ]).then((all) => nature = [for (final a in all) ...a]),
    _wikiNear(frame, wikiLimit).then((w) => wiki = w).catchError((Object _) {
      unreached.add('Wikipedia');
      return <Spot>[];
    }),
  ]);
  return Landmarks(
    listed: listed,
    monuments: monuments,
    parks: parks,
    battlefields: battlefields,
    worldHeritage: worldHeritage,
    nature: nature,
    wiki: wiki,
    passed: path == null
        ? const []
        : passedOnTheWay(path,
            listed: listed, monuments: [...monuments, ...parks, ...battlefields, ...worldHeritage], nature: nature, wiki: wiki),
    unreached: unreached,
  );
}

/// The area a view is looked up for: [bounds] and a quarter again round it,
/// snapped out to a hundredth of a degree so small moves ask nothing new.
List<double> viewFrame(double west, double south, double east, double north) {
  final px = (east - west) * .25, py = (north - south) * .25;
  double down(double v) => (v * 100).floorToDouble() / 100;
  double up(double v) => (v * 100).ceilToDouble() / 100;
  return [down(west - px), down(south - py), up(east + px), up(north + py)];
}

/// Whether [outer] holds all of [inner].
bool frameHolds(List<double> outer, List<double> inner) =>
    outer[0] <= inner[0] && outer[1] <= inner[1] && outer[2] >= inner[2] && outer[3] >= inner[3];

/// Looks up and keeps what is round each walk (by its key), and what is in
/// the map's view as it moves. The map draws [current] (both together);
/// "Passed on the way" lists [walk]; [show] asks the map to go to a place
/// in the list.
class LandmarkLookup extends ChangeNotifier {
  static final Map<String, Landmarks> _kept = {};

  /// The views looked up this run, newest last, so going back asks nothing.
  static final List<(List<double>, bool, Landmarks)> _views = [];

  String? _key;

  /// What is round the walk, with what it passed.
  Landmarks? walk;

  /// What is in the view.
  Landmarks? view;
  List<double>? _viewFrame;
  bool _viewGradeTwo = false;
  int _viewRun = 0;
  bool loading = false;

  /// Where the list asked the map to go, and a count so the same place
  /// asked for twice is gone to twice.
  LatLng? focus;
  int focusAsked = 0;

  /// Everything to draw: the walk's and the view's, each once.
  Landmarks? get current {
    final w = walk, v = view;
    if (w == null) return v;
    if (v == null) return w;
    return w.merge(v);
  }

  /// What was found for [key], once looked up.
  static Landmarks? keptFor(String key) => _kept[key];

  /// Look up round [path] for the walk [key], unless that is already done.
  Future<void> want(String key, List<LatLng> path) async {
    if (key == _key || path.isEmpty) return;
    _key = key;
    final had = _kept[key];
    if (had != null) {
      walk = had;
      loading = false;
      notifyListeners();
      return;
    }
    walk = null;
    loading = true;
    notifyListeners();
    final found = await lookUpFrame(frameOf(path), path: path);
    if (found.unreached.isEmpty) _kept[key] = found;
    if (_key != key) return;
    walk = found;
    loading = false;
    notifyListeners();
  }

  /// Look up what is in the map's view, from about town scale in (zoom 12);
  /// Grade II buildings from zoom 14. Nothing is asked again for a view
  /// already covered.
  Future<void> look(double west, double south, double east, double north, double zoom) async {
    if (zoom < 12) return;
    final gradeTwo = zoom >= 14;
    final frame = viewFrame(west, south, east, north);
    // a covered view: no new question
    final have = _viewFrame;
    if (have != null && frameHolds(have, frame) && (_viewGradeTwo || !gradeTwo)) return;
    for (final (f, g2, l) in _views.reversed) {
      if (frameHolds(f, frame) && (g2 || !gradeTwo)) {
        _viewFrame = f;
        _viewGradeTwo = g2;
        view = l;
        notifyListeners();
        return;
      }
    }
    final run = ++_viewRun;
    _viewFrame = frame;
    _viewGradeTwo = gradeTwo;
    final found = await lookUpFrame(frame, gradeTwo: gradeTwo, wikiLimit: 50);
    if (found.unreached.isEmpty) {
      _views.add((frame, gradeTwo, found));
      if (_views.length > 12) _views.removeAt(0);
    } else if (run == _viewRun) {
      // ask again next time the map moves
      _viewFrame = null;
    }
    if (run != _viewRun) return;
    view = found;
    notifyListeners();
  }

  void show(LatLng at) {
    focus = at;
    focusAsked++;
    notifyListeners();
  }
}
