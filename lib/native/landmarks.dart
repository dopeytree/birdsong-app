import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'mvt.dart';

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

/// The kinds of OpenStreetMap park (the map tiles' park layer) taken as
/// reserves, and what each is called.
const reserveKinds = {
  'nature_reserve': 'Nature reserve',
  'protected_area': 'Protected area',
  'national_park': 'National park',
};

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
  const Spot(this.name, this.about, this.at, {this.grade = '', this.link});

  final String name;

  /// "Listed building, Grade II*", or the Wikipedia page's description.
  final String about;
  final LatLng at;

  /// A listed building's grade ("I", "II*"), for its size on the map.
  final String grade;

  /// Its page: the Wikipedia article, or Historic England's list entry.
  final String? link;
}

/// A scheduled monument or a nature site: an area with a name.
class Area {
  const Area(this.name, this.about, this.shape, {this.kind = '', this.link});

  final String name;

  /// "Scheduled monument", or the nature site's full kind.
  final String about;
  final Shape shape;

  /// A nature site's short kind (SSSI), so two kinds of one name both count.
  final String kind;

  /// Its page, when it has one: Historic England's list entry.
  final String? link;
}

/// A line of "Passed on the way": [at] null when the walk went through it
/// (a nature site), with no one point to fly to.
class Passed {
  const Passed(this.name, this.about, this.at, this.metres, this.order, {this.link, LatLng? where}) : _where = where;

  final String name;
  final String about;
  final LatLng? at;
  final double metres;

  /// Reserves first, then Natural England's sites, then buildings and
  /// monuments, then Wikipedia.
  final int order;

  /// Its page (Wikipedia, Historic England), or null: then a search.
  final String? link;

  final LatLng? _where;

  /// Where the map goes to show it: [at], or for a place walked through,
  /// where the walk was inside it.
  LatLng? get where => at ?? _where;

  /// Its page, or a web search for it.
  Uri get page => pageOf(name, about, link);
}

/// A place's page: [link] when it has one, else a web search for it.
Uri pageOf(String name, String about, String? link) =>
    link != null ? Uri.parse(link) : Uri.https('www.google.com', '/search', {'q': '$name $about'});

/// What a page is, for the line that opens it: "Wikipedia", "Historic
/// England", or "Search the web".
String pageName(Uri page) => switch (page.host) {
      'en.wikipedia.org' => 'Wikipedia',
      'historicengland.org.uk' => 'Historic England',
      _ => 'Search the web',
    };

/// Historic England's list entry for a feature of theirs, from its number.
String? heLink(Map<String, dynamic> props) {
  final n = props['ListEntry'] ?? props['LISTENTRY'] ?? props['List_Entry'];
  return n == null || '$n'.isEmpty ? null : 'https://historicengland.org.uk/listing/the-list/list-entry/$n';
}

/// A Wikipedia article's address from its title.
String wikiLink(String title) => 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}';

/// What was found in one area.
class Landmarks {
  const Landmarks({
    this.listed = const [],
    this.monuments = const [],
    this.parks = const [],
    this.battlefields = const [],
    this.worldHeritage = const [],
    this.nature = const [],
    this.reserves = const [],
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

  /// OpenStreetMap's reserves round a walk, read from the map tiles (the
  /// map draws them itself; these are for what the walk passed).
  final List<Area> reserves;
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
      reserves: both(reserves, other.reserves, area),
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

/// Metres from [p] to the nearest edge of [shape], and that nearest point
/// (flat-earth sums: fine over the few hundred metres they're used for).
(double, LatLng) metresToEdge(LatLng p, Shape shape) {
  final kx = 111320 * math.cos(p.latitude * math.pi / 180), ky = 110540.0;
  var best = double.infinity;
  var at = p;
  for (final rings in shape) {
    for (final r in rings) {
      for (var i = 0; i + 1 < r.length; i++) {
        final ax = (r[i].longitude - p.longitude) * kx, ay = (r[i].latitude - p.latitude) * ky;
        final bx = (r[i + 1].longitude - p.longitude) * kx, by = (r[i + 1].latitude - p.latitude) * ky;
        final dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy;
        final t = len == 0 ? 0.0 : (-(ax * dx + ay * dy) / len).clamp(0.0, 1.0);
        final cx = ax + t * dx, cy = ay + t * dy;
        final d = math.sqrt(cx * cx + cy * cy);
        if (d < best) {
          best = d;
          at = LatLng(p.latitude + cy / ky, p.longitude + cx / kx);
        }
      }
    }
  }
  return (best, at);
}

/// A place's name with "RSPB", "nature reserve" and the like taken off,
/// in small letters, so "RSPB Ham Wall" and Wikipedia's "Ham Wall" match.
String plainName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'\b(rspb|nnr|lnr|national nature reserve|local nature reserve|nature reserve|reserve)\b'), ' ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// A name sent in capitals (Natural England's are) in ordinary letters:
/// "SOMERSET WETLANDS" → "Somerset Wetlands"; others as they are.
String tidyName(String name) {
  if (name != name.toUpperCase() || !RegExp('[A-Z]{2}').hasMatch(name)) return name;
  const small = {'and', 'of', 'the', 'on', 'in', 'at', 'by', 'upon', 'de', 'la'};
  var first = true;
  return name.toLowerCase().replaceAllMapped(RegExp(r"[a-z][a-z']*"), (m) {
    final w = m[0]!;
    final keep = !first && small.contains(w);
    first = false;
    return keep ? w : w[0].toUpperCase() + w.substring(1);
  });
}

/// The parts of [line] inside [box] ([west, south, east, north]), as runs
/// of points (a run ends where the line leaves the box). Each segment is
/// clipped (Cohen–Sutherland), so a long outline costs only what is near.
List<List<LatLng>> clipLine(List<LatLng> line, List<double> box) {
  final w = box[0], s = box[1], e = box[2], n = box[3];
  int code(double x, double y) => (x < w ? 1 : 0) | (x > e ? 2 : 0) | (y < s ? 4 : 0) | (y > n ? 8 : 0);
  final out = <List<LatLng>>[];
  List<LatLng>? run;
  for (var i = 0; i + 1 < line.length; i++) {
    var x0 = line[i].longitude, y0 = line[i].latitude, x1 = line[i + 1].longitude, y1 = line[i + 1].latitude;
    var c0 = code(x0, y0), c1 = code(x1, y1);
    var keep = false;
    while (true) {
      if (c0 | c1 == 0) {
        keep = true;
        break;
      }
      if (c0 & c1 != 0) break;
      final c = c0 != 0 ? c0 : c1;
      double x, y;
      if (c & 8 != 0) {
        x = x0 + (x1 - x0) * (n - y0) / (y1 - y0);
        y = n;
      } else if (c & 4 != 0) {
        x = x0 + (x1 - x0) * (s - y0) / (y1 - y0);
        y = s;
      } else if (c & 2 != 0) {
        y = y0 + (y1 - y0) * (e - x0) / (x1 - x0);
        x = e;
      } else {
        y = y0 + (y1 - y0) * (w - x0) / (x1 - x0);
        x = w;
      }
      if (c == c0) {
        x0 = x;
        y0 = y;
        c0 = code(x0, y0);
      } else {
        x1 = x;
        y1 = y;
        c1 = code(x1, y1);
      }
    }
    if (!keep) {
      run = null;
      continue;
    }
    final a = LatLng(y0, x0), b = LatLng(y1, x1);
    if (run == null || run.last != a) {
      run = [a];
      out.add(run);
    }
    run.add(b);
    // the segment was cut short: the line leaves the box here
    if (b != line[i + 1]) run = null;
  }
  return out;
}

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

/// What the walk passed, most particular first: reserves (OpenStreetMap's,
/// from the tiles) walked through or within 50 m, then Natural England's
/// sites walked through (each name and kind once), then buildings within
/// 120 m and monuments (and parks, battlefields and World Heritage Sites)
/// within 200 m or walked through, then Wikipedia places within 400 m;
/// nearest first in each. A Wikipedia place of a passed reserve's name
/// ("Ham Wall" for "RSPB Ham Wall") is that reserve: it isn't listed again,
/// and lends the reserve its description.
List<Passed> passedOnTheWay(List<LatLng> path,
    {List<Spot> listed = const [],
    List<Area> monuments = const [],
    List<Area> nature = const [],
    List<Area> reserves = const [],
    List<Spot> wiki = const []}) {
  final probe = probeOf(path);
  if (probe.isEmpty) return const [];
  double near(LatLng p) => probe.map((q) => metresBetween(q, p)).reduce(math.min);
  final out = <Passed>[];
  final described = {for (final s in wiki) plainName(s.name): s};
  final reserveNames = <String>{};
  final seenReserve = <String>{};
  for (final a in reserves) {
    final key = plainName(a.name);
    if (!seenReserve.add(key)) continue;
    final inside = probe.where((p) => inShape(p, a.shape)).firstOrNull;
    var d = 0.0;
    LatLng? at;
    if (inside == null) {
      d = double.infinity;
      for (final p in probe) {
        final (m, q) = metresToEdge(p, a.shape);
        if (m < d) {
          d = m;
          at = q;
        }
      }
      if (d > 50) continue;
    }
    reserveNames.add(key);
    final w = described[key];
    out.add(Passed(a.name, w != null && w.about != 'Wikipedia' ? w.about : a.about, at, d, 0,
        link: w?.link ?? a.link, where: inside));
  }
  for (final s in listed) {
    final d = near(s.at);
    if (d <= 120) out.add(Passed(s.name, s.about, s.at, d, 2, link: s.link));
  }
  for (final a in monuments) {
    final pts = [for (final rings in a.shape) for (final r in rings) ...r];
    if (pts.isEmpty) continue;
    final inside = probe.any((p) => inShape(p, a.shape));
    final every = math.max(1, pts.length ~/ 100);
    final d = inside ? 0.0 : [for (var i = 0; i < pts.length; i += every) near(pts[i])].reduce(math.min);
    if (d <= 200) out.add(Passed(a.name, a.about, pts.first, d, 2, link: a.link));
  }
  final seen = <String>{};
  for (final a in nature) {
    if (!seen.add('${a.kind}${a.name}')) continue;
    if (reserveNames.contains(plainName(a.name))) continue;
    final inside = probe.where((p) => inShape(p, a.shape)).firstOrNull;
    if (inside != null) out.add(Passed(a.name, a.about, null, 0, 1, link: a.link, where: inside));
  }
  for (final s in wiki) {
    if (reserveNames.contains(plainName(s.name))) continue;
    final d = near(s.at);
    if (d <= 400) out.add(Passed(s.name, s.about, s.at, d, 3, link: s.link));
  }
  out.sort((a, b) => a.order != b.order ? a.order - b.order : a.metres.compareTo(b.metres));
  return out;
}

// ---- reading what the services send ----------------------------------------

/// A feature's name: its first property ending in "name" that has a value.
String nameOf(Map<String, dynamic> p) {
  final re = RegExp(r'(^|_)name$', caseSensitive: false);
  for (final e in p.entries) {
    if (re.hasMatch(e.key) && e.value != null && '${e.value}'.isNotEmpty) return tidyName('${e.value}');
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
          link: wikiLink('${p['title']}'),
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
///
/// [detail] is how simplified areas may be, in degrees (about a pixel at
/// the zoom they're for); a walk's own lookup keeps the finest.
Future<Landmarks> lookUpFrame(List<double> frame,
    {bool gradeTwo = false, List<LatLng>? path, int wikiLimit = 20, double detail = 0}) async {
  final unreached = <String>[];
  var listed = <Spot>[], wiki = <Spot>[];
  var monuments = <Area>[], parks = <Area>[], battlefields = <Area>[], worldHeritage = <Area>[], nature = <Area>[];
  Future<List<Area>> areas(String url, String about, String failed, {double simplify = .00002}) =>
      _arc(url, frame, simplify: math.max(simplify, detail)).then((fs) => [
            for (final f in fs)
              Area(nameOf(f.props), f.props['Grade'] != null ? '$about, Grade ${f.props['Grade']}' : about, shapeOf(f.geometry),
                  link: heLink(f.props))
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
                grade: '${f.props['Grade'] ?? ''}', link: heLink(f.props)),
      ];
    }).catchError((Object _) {
      unreached.add('Historic England (buildings)');
    }),
    _arc('$_he/6', frame, simplify: math.max(.00002, detail)).then((fs) {
      monuments = [
        for (final f in fs) Area(nameOf(f.props), 'Scheduled monument', shapeOf(f.geometry), link: heLink(f.props))
      ];
    }).catchError((Object _) {
      unreached.add('Historic England (monuments)');
    }),
    areas('$_he/7', 'Registered park and garden', 'Historic England (parks and gardens)').then((a) => parks = a),
    areas('$_he/8', 'Registered battlefield', 'Historic England (battlefields)').then((a) => battlefields = a),
    areas('$_he/10', 'World Heritage Site', 'Historic England (World Heritage Sites)', simplify: .0001)
        .then((a) => worldHeritage = a),
    Future.wait([
      for (final k in natureKinds)
        _arc(k.url, frame, simplify: math.max(.0001, detail))
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

/// Loads one map tile's bytes (z, x, y), or null.
typedef TileLoader = Future<Uint8List?> Function(int z, int x, int y);

/// OpenStreetMap's reserves under [path], from the map's own vector tiles
/// at zoom [z] (the park layer: nature reserves, protected areas, national
/// parks, with names): the pieces each tile holds, joined by name. Nothing
/// for a walk over more than 40 tiles (a long drive).
Future<List<Area>> reservesAlong(List<LatLng> path, TileLoader tile, {int z = 14}) async {
  final tiles = {for (final p in probeOf(path)) tileOf(p, z)};
  if (tiles.isEmpty || tiles.length > 40) return const [];
  final shapes = <String, Shape>{}, kinds = <String, String>{};
  for (final (x, y) in tiles) {
    Uint8List? bytes;
    try {
      bytes = await tile(z, x, y);
    } catch (_) {
      continue;
    }
    if (bytes == null) continue;
    final b = bytes;
    final List<(String, String, Shape)> parts;
    try {
      // decoded away from the screen's thread
      parts = await Isolate.run(() => _reserveParts(b, z, x, y));
    } catch (_) {
      continue;
    }
    for (final (name, kind, shape) in parts) {
      (shapes[name] ??= []).addAll(shape);
      kinds[name] = kind;
    }
  }
  return [
    for (final e in shapes.entries) Area(e.key, kinds[e.key]!, e.value, kind: 'OSM'),
  ];
}

/// The reserves in one tile's park layer: name, kind and polygons.
List<(String, String, Shape)> _reserveParts(Uint8List bytes, int z, int x, int y) => [
      for (final f in readMvtLayer(bytes, 'park'))
        if (reserveKinds[f.props['class']] case final kind?)
          if ((f.props['name'] ?? f.props['name:en'] ?? f.props['name:latin']) case final String name
              when name.isNotEmpty && f.type == 3)
            (name, kind, mvtPolygons(f, z, x, y)),
    ];

/// [lookUpFrame] on a thread of its own, so reading what the services send
/// (some of it large: a sea's worth of coastline) never stalls the map.
Future<Landmarks> lookUpAway(List<double> frame,
        {bool gradeTwo = false, List<LatLng>? path, int wikiLimit = 20, double detail = 0}) =>
    Isolate.run(() => lookUpFrame(frame, gradeTwo: gradeTwo, path: path, wikiLimit: wikiLimit, detail: detail));

/// The area a view is looked up for: [bounds] and a quarter again round it,
/// snapped out to a hundredth of a degree so small moves ask nothing new.
List<double> viewFrame(double west, double south, double east, double north) {
  final px = (east - west) * .25, py = (north - south) * .25;
  double down(double v) => (v * 100).floorToDouble() / 100;
  double up(double v) => (v * 100).ceilToDouble() / 100;
  return [down(west - px), down(south - py), up(east + px), up(north + py)];
}

/// What the walk passed, with the reserves too, worked out on a thread of
/// its own.
Future<List<Passed>> _passedAway(List<LatLng> path, Landmarks found, List<Area> reserves) {
  final listed = found.listed, nature = found.nature, wiki = found.wiki;
  final monuments = [...found.monuments, ...found.parks, ...found.battlefields, ...found.worldHeritage];
  return Isolate.run(
      () => passedOnTheWay(path, listed: listed, monuments: monuments, nature: nature, reserves: reserves, wiki: wiki));
}

/// Whether [outer] holds all of [inner].
bool frameHolds(List<double> outer, List<double> inner) =>
    outer[0] <= inner[0] && outer[1] <= inner[1] && outer[2] >= inner[2] && outer[3] >= inner[3];

/// For the map's debug readout: the last view lookup, how long and how big.
String lastLook = '';

/// How many areas, and how many outline points in them, [l] holds.
int countAreas(Landmarks l) =>
    l.monuments.length + l.parks.length + l.battlefields.length + l.worldHeritage.length + l.nature.length;
int countPoints(Landmarks l) => [...l.monuments, ...l.parks, ...l.battlefields, ...l.worldHeritage, ...l.nature]
    .fold(0, (n, a) => n + a.shape.fold(0, (m, rings) => m + rings.fold(0, (k, r) => k + r.length)));

/// The zoom from which Grade II buildings are looked up and drawn.
const gradeTwoZoom = 15.0;

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

  /// The line of "Passed on the way" chosen last, which the map shows; a
  /// count so the same line chosen twice is gone to twice.
  Passed? chosen;
  int focusAsked = 0;

  /// Where the map is to go: the chosen line's place.
  LatLng? get focus => chosen?.where;

  Landmarks? _merged;
  Landmarks? _mergedWalk, _mergedView;

  /// Everything to draw: the walk's and the view's, each once. Merged once
  /// for each change, not each time it is read (the map reads it often).
  Landmarks? get current {
    final w = walk, v = view;
    if (w == null) return v;
    if (v == null) return w;
    if (!identical(w, _mergedWalk) || !identical(v, _mergedView)) {
      _merged = w.merge(v);
      _mergedWalk = w;
      _mergedView = v;
    }
    return _merged;
  }

  /// What was found for [key], once looked up.
  static Landmarks? keptFor(String key) => _kept[key];

  /// Look up round [path] for the walk [key], unless that is already done;
  /// with [tile], OpenStreetMap's reserves from the map tiles too.
  Future<void> want(String key, List<LatLng> path, {TileLoader? tile}) async {
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
    final results = await Future.wait([
      lookUpAway(frameOf(path), path: path),
      tile == null ? Future.value(const <Area>[]) : reservesAlong(path, tile),
    ]);
    var found = results[0] as Landmarks;
    final reserves = results[1] as List<Area>;
    if (reserves.isNotEmpty) {
      found = Landmarks(
        listed: found.listed,
        monuments: found.monuments,
        parks: found.parks,
        battlefields: found.battlefields,
        worldHeritage: found.worldHeritage,
        nature: found.nature,
        reserves: reserves,
        wiki: found.wiki,
        passed: await _passedAway(path, found, reserves),
        unreached: found.unreached,
      );
    }
    if (found.unreached.isEmpty) _kept[key] = found;
    if (_key != key) return;
    walk = found;
    loading = false;
    notifyListeners();
  }

  /// Look up what is in the map's view, from about town scale in (zoom 12);
  /// Grade II buildings (most of them) only close in, from zoom
  /// [gradeTwoZoom]. Nothing is asked again for a view already covered.
  Future<void> look(double west, double south, double east, double north, double zoom) async {
    if (zoom < 12) return;
    final gradeTwo = zoom >= gradeTwoZoom;
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
    // areas simplified to about a pixel at this zoom, and never finer than
    // at town scale (zoom 13): street zoom needs no more detail
    final detail = 360 / (256 * math.pow(2, math.min(13, zoom.floor())));
    final clock = Stopwatch()..start();
    final found = await lookUpAway(frame, gradeTwo: gradeTwo, wikiLimit: 50, detail: detail);
    if (kDebugMode) {
      lastLook = 'look z${zoom.toStringAsFixed(1)} ${clock.elapsedMilliseconds} ms: '
          '${found.listed.length} bldg, ${found.wiki.length} wiki, '
          '${countAreas(found)} areas, ${countPoints(found)} pts'
          '${found.unreached.isEmpty ? '' : ', failed ${found.unreached.length}'}';
    }
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

  /// A line of the list chosen: the map goes to it and labels it.
  void choose(Passed p) {
    chosen = p;
    focusAsked++;
    notifyListeners();
  }
}
