import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, consolidateHttpClientResponseBytes;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart' hide Path;

import '../main.dart' show ink, madder, paper, paperDeep, sepia, serif;
import '../store/detection_store.dart';
import 'contours.dart';
import 'landmarks.dart';
import 'place_search.dart';
import 'map_style.dart';

const _tilesJson = 'https://tiles.openfreemap.org/planet';
const _glyphs = 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf';
const _dem = 'https://elevation-tiles-prod.s3.amazonaws.com/terrarium/';
const _credit = 'Elevation: Mapzen Terrain Tiles (AWS) · OpenFreeMap © OpenMapTiles © OpenStreetMap';

/// The landmarks' credits, as their licences ask (Open Government Licence
/// v3; Wikipedia CC BY-SA), shown while they are on.
String _extrasCredit() {
  final y = DateTime.now().year;
  return '\n© Historic England $y. © Natural England copyright. Contains Ordnance Survey data '
      '© Crown copyright and database right $y · Places from Wikipedia (CC BY-SA)';
}

const _searchCredit = '\nSearch: Photon by komoot, © OpenStreetMap contributors';

/// A bird on the walk: where and when it was heard.
class WalkBird {
  const WalkBird(this.sci, this.common, this.at, this.when);

  final String sci;
  final String common;
  final LatLng at;
  final DateTime when;
}

/// What the map draws: the walk the selected session belongs to (sessions
/// split at the species limit are one walk), as local_api.dart walk() gives
/// the web map.
class Walk {
  const Walk({
    required this.key,
    required this.trail,
    required this.birds,
    required this.live,
    required this.start,
    this.end,
    this.place,
    this.station,
  });

  /// A remote station's spot: no trail and no crosses, a mark where it is
  /// ([place], when it says) with its name.
  factory Walk.station(String name, (double, double)? at) => Walk(
        key: 'station:$name',
        trail: const [],
        birds: const [],
        live: false,
        start: DateTime.now(),
        place: at == null ? null : LatLng(at.$1, at.$2),
        station: name,
      );

  /// The station's name, for a station's spot.
  final String? station;

  /// The walk's sessions, so a new walk is fitted afresh.
  final String key;
  final List<LatLng> trail;

  /// Placed detections, oldest first.
  final List<WalkBird> birds;
  final bool live;
  final DateTime start;
  final DateTime? end;

  /// Where the walk began, when there is no trail.
  final LatLng? place;

  /// The walk [selected] belongs to: its trail and the detections of
  /// [model] ('all' for every model) that have a place.
  static Walk of(DetectionStore store, Session selected, String model) {
    final parts = store.walkOf(selected);
    final heard = [
      for (final x in parts)
        for (final d in store.forPlate(model, session: x))
          if (d.hasPlace) d
    ]..sort((a, b) => a.at.compareTo(b.at));
    LatLng? place;
    for (final x in parts) {
      if (x.hasPlace) {
        place = LatLng(x.lat!, x.lon!);
        break;
      }
    }
    return Walk(
      key: parts.map((x) => x.id).join(','),
      trail: [
        for (final x in parts)
          for (final p in x.track) LatLng(p.lat, p.lon)
      ],
      birds: [for (final d in heard) WalkBird(d.sci, d.common, LatLng(d.lat!, d.lon!), d.at)],
      live: parts.last.live,
      start: parts.first.start,
      end: parts.last.end,
      place: place,
    );
  }
}

/// The map, its style and fonts, read once a run (and again after a
/// failure, so a connection that comes back is used).
class _Kit {
  _Kit(this.base, this.labels, this.reserves, this.providers, this.sprites, this.glyphs);

  final vt.Theme base;
  final vt.Theme labels;

  /// OpenStreetMap's nature reserves, with the extras.
  final vt.Theme reserves;
  final vt.TileProviders providers;
  final vt.SpriteAtlas sprites;
  final vt.GlyphSource glyphs;

  static Future<_Kit>? _loading;

  static Future<_Kit> load() => _loading ??= _read().catchError((Object e) {
        _loading = null;
        throw e;
      });

  static Future<_Kit> _read() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(_tilesJson));
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw HttpException('${res.statusCode}', uri: Uri.parse(_tilesJson));
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final template = (j['tiles'] as List).first as String;
      final provider = vt.NetworkVectorTileProvider(
        urlTemplate: template,
        maximumZoom: (j['maxzoom'] as num?)?.toInt() ?? 14,
        minimumZoom: (j['minzoom'] as num?)?.toInt() ?? 0,
      );
      const reader = vt.ThemeReader();
      return _Kit(
        reader.read(baseStyle('omt'), id: 'birdsong-walk-base-1'),
        reader.read(labelStyle('omt'), id: 'birdsong-walk-labels-1'),
        reader.read(reservesStyle('omt'), id: 'birdsong-walk-reserves-1'),
        vt.TileProviders({'omt': provider}),
        await mapSprites(),
        vt.GlyphSource.network(_glyphs),
      );
    } finally {
      client.close();
    }
  }
}

/// The walk on a map, in place of the collage: the web plate's map mode
/// (assets/app/map-mode.js) in Flutter. A dotted trail from Start to End
/// (or Now), a cross where each species was first heard ([allBirds]: every
/// call), contours traced from elevation tiles, peaks with their heights,
/// on the paper style built for it. A tap on a cross opens that bird's
/// card ([onBird]); on a peak or an end, a label says what it is.
///
/// The map takes its own drags and pinches: [onHold] asks the page around
/// it to stop scrolling while a finger is on it.
class WalkMap extends StatefulWidget {
  const WalkMap({
    super.key,
    required this.walk,
    required this.allBirds,
    required this.size,
    required this.onBird,
    required this.onHold,
    this.landmarks,
  });

  final Walk? walk;
  final bool allBirds;
  final Size size;
  final void Function(String sci, String common) onBird;
  final ValueChanged<bool> onHold;

  /// The extras (Settings.mapExtras), or null when they are off.
  final LandmarkLookup? landmarks;

  @override
  State<WalkMap> createState() => _WalkMapState();
}

class _WalkMapState extends State<WalkMap> {
  final _map = MapController();
  final _peaks = vt.VectorTileLayerController();
  final _reserves = vt.VectorTileLayerController();
  _Kit? _kit;
  String? _failed;
  bool _ready = false;

  // the walk the view was last fitted to; a drag keeps the view where it is
  String? _fittedTo;
  bool _dragged = false;

  double _zoom = 5;
  final Set<int> _fingers = {};

  // contours: the lines, and what they were traced for
  List<ContourLine> _contours = const [];
  String _contourKey = '';
  int _contourRun = 0;
  Timer? _contourTimer;
  static final Map<String, Future<ui.Image>> _demTiles = {};

  // the label for a peak or an end, where it was tapped
  ({String title, String sub, Offset at})? _tip;
  Timer? _tipTimer;
  Timer? _lookTimer;

  int _focusSeen = 0;

  @override
  void initState() {
    super.initState();
    _focusSeen = widget.landmarks?.focusAsked ?? 0;
    widget.landmarks?.addListener(_landmarksChanged);
    _askLandmarks();
    _Kit.load().then((k) {
      if (mounted) setState(() => _kit = k);
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = 'The map needs an internet connection the first time it opens.');
    });
  }

  @override
  void didUpdateWidget(WalkMap old) {
    super.didUpdateWidget(old);
    if (widget.landmarks != old.landmarks) {
      old.landmarks?.removeListener(_landmarksChanged);
      widget.landmarks?.addListener(_landmarksChanged);
      _focusSeen = widget.landmarks?.focusAsked ?? 0;
    }
    _askLandmarks();
    if (widget.walk?.key != old.walk?.key) _dragged = false;
    if (_ready && !_dragged && widget.walk?.key != _fittedTo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  @override
  void dispose() {
    widget.landmarks?.removeListener(_landmarksChanged);
    _lookTimer?.cancel();
    _contourTimer?.cancel();
    _tipTimer?.cancel();
    _map.dispose();
    super.dispose();
  }

  // ---- the extras ------------------------------------------------------------

  /// The page's loadPlaces() path: the trail and the crosses, or just the
  /// place when that is all there is.
  void _askLandmarks() {
    final l = widget.landmarks, w = widget.walk;
    if (l == null || w == null) return;
    final path = [...w.trail, for (final b in w.birds) b.at];
    if (path.isEmpty && w.place != null) path.add(w.place!);
    // not while building: the lookup tells its listeners at once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) l.want(w.key, path);
    });
  }

  /// The landmarks in view, as the map comes to rest.
  void _lookAround() {
    final l = widget.landmarks;
    if (l == null || !mounted || !_ready) return;
    final c = _map.camera, b = c.visibleBounds;
    l.look(b.west, b.south, b.east, b.north, c.zoom);
  }

  /// Back to the walk, or the station: the home button.
  void _home() {
    _dragged = false;
    _fit();
  }

  /// A place from the search: its extent, or close in on its point.
  void _goTo(FoundPlace p) {
    _dragged = true;
    if (p.hasExtent && (p.north! - p.south! > .0005 || p.east! - p.west! > .0005)) {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(LatLng(p.south!, p.west!), LatLng(p.north!, p.east!)),
        padding: const EdgeInsets.all(24),
        maxZoom: 16,
      ));
    } else {
      _map.move(p.at, 15);
    }
  }

  void _landmarksChanged() {
    if (!mounted) return;
    final l = widget.landmarks!;
    if (l.focusAsked != _focusSeen && l.focus != null && _ready) {
      _focusSeen = l.focusAsked;
      // map.flyTo({center, zoom: max(zoom, 15.5)})
      _map.move(l.focus!, math.max(_map.camera.zoom, 15.5));
      _dragged = true;
    }
    setState(() {});
  }

  // ---- the view ----------------------------------------------------------

  List<LatLng> get _points => [
        ...?widget.walk?.trail,
        for (final b in widget.walk?.birds ?? const <WalkBird>[]) b.at,
      ];

  /// The page's fitWalk(): the trail and the crosses, with a margin, no
  /// closer than zoom 16; just the place at 14 when that is all there is.
  void _fit() {
    if (!mounted || !_ready) return;
    final w = widget.walk;
    _fittedTo = w?.key;
    final pts = _points;
    if (pts.isEmpty) {
      if (w?.place != null) _map.move(w!.place!, 14);
      return;
    }
    final pad = math.min(60.0, (math.min(widget.size.width, widget.size.height) / 6).roundToDouble());
    if (pts.length == 1) {
      _map.move(pts.first, 16);
    } else {
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: EdgeInsets.all(pad), maxZoom: 16));
    }
  }

  void _moved(MapCamera camera, bool byHand) {
    if (byHand) _dragged = true;
    if ((camera.zoom - _zoom).abs() > .05) setState(() => _zoom = camera.zoom);
    if (_tip != null) setState(() => _tip = null);
    _contourTimer?.cancel();
    _contourTimer = Timer(const Duration(milliseconds: 150), _traceContours);
    _lookTimer?.cancel();
    _lookTimer = Timer(const Duration(milliseconds: 600), _lookAround);
  }

  // ---- contours, traced here from terrarium tiles -------------------------

  Future<void> _traceContours() async {
    if (!mounted || !_ready) return;
    final camera = _map.camera;
    final zoom = camera.zoom;
    if (zoom < 7) {
      if (_contours.isNotEmpty) setState(() => _contours = const []);
      _contourKey = '';
      return;
    }
    final b = camera.visibleBounds;
    final dx = (b.east - b.west) * .15, dy = (b.north - b.south) * .15;
    final west = b.west - dx, east = b.east + dx;
    final south = math.max(-80.0, b.south - dy), north = math.min(80.0, b.north + dy);
    final z = contourTileZoom(west, south, east, north, zoom);
    final (minor, major) = contourInterval(zoom);
    final r = tileRange(west, south, east, north, z);
    final key = '$z:${r.x0}-${r.x1}:${r.y0}-${r.y1}:$minor/$major';
    if (key == _contourKey) return;
    _contourKey = key;
    final run = ++_contourRun;
    try {
      // every second pixel of each tile, 128 by 128 a tile
      const half = 128;
      final cols = r.x1 - r.x0 + 1, rows = r.y1 - r.y0 + 1;
      final w = cols * half, h = rows * half;
      final heights = Float32List(w * h);
      await Future.wait([
        for (var x = r.x0; x <= r.x1; x++)
          for (var y = r.y0; y <= r.y1; y++)
            _demTile(z, x, y).then((img) async {
              final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
              if (data == null) return;
              final px = data.buffer.asUint8List();
              final ox = (x - r.x0) * half, oy = (y - r.y0) * half;
              for (var j = 0; j < half; j++) {
                for (var i = 0; i < half; i++) {
                  final o = ((j * 2) * img.width + i * 2) * 4;
                  heights[(oy + j) * w + ox + i] = terrarium(px[o], px[o + 1], px[o + 2]);
                }
              }
            }),
      ]);
      final lines = await compute(traceContours, ContourJob(heights, w, h, r.x0, r.y0, z, minor, major));
      if (mounted && run == _contourRun) setState(() => _contours = lines);
    } catch (e) {
      if (run == _contourRun) _contourKey = '';
      debugPrint('contours: $e');
    }
  }

  static Future<ui.Image> _demTile(int z, int x, int y) {
    final key = '$z/$x/$y';
    final had = _demTiles[key];
    if (had != null) return had;
    final f = () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('$_dem$key.png'));
        final res = await req.close().timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) throw HttpException('elevation $key: ${res.statusCode}');
        final codec = await ui.instantiateImageCodec(await consolidateHttpClientResponseBytes(res));
        return (await codec.getNextFrame()).image;
      } finally {
        client.close();
      }
    }();
    _demTiles[key] = f;
    // a tile that failed is asked for again next time
    f.then<void>((_) {}, onError: (Object _) {
      _demTiles.remove(key);
    });
    if (_demTiles.length > 160) _demTiles.remove(_demTiles.keys.first);
    return f;
  }

  // ---- taps -----------------------------------------------------------------

  void _tapped(TapPosition at, LatLng ll) {
    final p = at.relative;
    if (p == null) return;
    final hit = _peaks.queryRenderedFeatures(p, layerIds: const ['peaks']);
    if (hit.isEmpty) {
      final found = widget.landmarks?.current;
      for (final a in [
        ...?found?.monuments,
        ...?found?.battlefields,
        ...?found?.parks,
        ...?found?.worldHeritage,
        ...?found?.nature,
      ]) {
        if (inShape(ll, a.shape)) return _say(p, a.name, a.about);
      }
      if (widget.landmarks != null) {
        final r = _reserves.queryRenderedFeatures(p, layerIds: const ['reserve-fill']);
        for (final f in r) {
          final name = f.properties['name'];
          if (name == null || '$name'.isEmpty) continue;
          return _say(p, '$name', reserveKinds[f.properties['class']] ?? 'Nature reserve');
        }
      }
      if (_tip != null) setState(() => _tip = null);
      return;
    }
    final props = hit.first.properties;
    final ele = props['ele'];
    _say(p, '${props['name'] ?? ''}', ele != null ? '$ele m' : 'Summit');
  }

  void _say(Offset at, String title, String sub) {
    _tipTimer?.cancel();
    setState(() => _tip = (title: title, sub: sub, at: at));
    _tipTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _tip = null);
    });
  }

  // ---- drawing -------------------------------------------------------------

  /// The page's note at the bottom left, or null.
  String? _note() {
    if (_failed != null) return _failed;
    if (_kit == null) return 'Drawing the map…';
    final w = widget.walk;
    if (w == null) return 'No walk to show: the map draws sessions recorded while listening here.';
    if (w.station != null) return w.place == null ? "This station doesn't say where it is." : null;
    if (w.trail.isEmpty && w.birds.isEmpty) {
      return w.place != null
          ? 'No trail for this walk: only where it began was noted. Walks recorded from now on show the way you went.'
          : 'No positions for this walk. With location allowed, the trail is drawn as you listen.';
    }
    return null;
  }

  double _lerpZoom(double z0, double a, double z1, double b) =>
      a + (b - a) * ((_zoom - z0) / (z1 - z0)).clamp(0.0, 1.0);

  List<Polyline> _contourLines() {
    final minorW = _lerpZoom(11, .4, 16, .9), majorW = _lerpZoom(11, .9, 16, 1.8);
    return [
      for (final c in _contours)
        Polyline(
          points: [for (var k = 0; k < c.lonLat.length; k += 2) LatLng(c.lonLat[k + 1], c.lonLat[k])],
          strokeWidth: c.major ? majorW : minorW,
          color: c.major ? sepia.withValues(alpha: .8) : const Color(0xFF9B7D5A).withValues(alpha: .5),
        ),
    ];
  }

  /// "120 m" on each long enough labelled line, along it, at its middle.
  List<Marker> _contourLabels() => [
        for (final c in _contours)
          if (c.major && c.lonLat.length >= 40)
            () {
              final m = (c.lonLat.length ~/ 4) * 2;
              final lon = c.lonLat[m], lat = c.lonLat[m + 1];
              final dLon = c.lonLat[m + 2] - c.lonLat[m - 2], dLat = c.lonLat[m + 3] - c.lonLat[m - 1];
              var a = math.atan2(-dLat, dLon * math.cos(lat * math.pi / 180));
              if (a > math.pi / 2) a -= math.pi;
              if (a < -math.pi / 2) a += math.pi;
              return Marker(
                point: LatLng(lat, lon),
                width: 60,
                height: 16,
                child: IgnorePointer(
                  child: Transform.rotate(angle: a, child: Center(child: _Halo('${c.ele} m', 10, sepia, halo: 1.6))),
                ),
              );
            }(),
      ];

  List<Marker> _ends() {
    final w = widget.walk;
    if (w == null) return const [];
    final line = w.trail;
    final a = line.isNotEmpty ? line.first : w.place;
    String time(DateTime? t) => t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    Marker end(LatLng at, bool start, String label, String when) => Marker(
          point: at,
          width: 80,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTapUp: (d) {
                  final box = context.findRenderObject() as RenderBox?;
                  final local = box?.globalToLocal(d.globalPosition) ?? Offset.zero;
                  _say(local, label, when);
                },
                child: CustomPaint(size: const Size.square(22), painter: _EndPainter(start)),
              ),
              Positioned(top: 28 + 11, child: IgnorePointer(child: _Halo(label, 11, ink, halo: 1.6))),
            ],
          ),
        );
    if (w.station != null) {
      return [if (w.place != null) end(w.place!, false, w.station!, 'The station')];
    }
    return [
      if (a != null) end(a, true, 'Start', time(w.start)),
      if (line.length > 1) end(line.last, false, w.live ? 'Now' : 'End', time(w.live ? DateTime.now() : w.end)),
    ];
  }

  // the extras' colours, as the page's layers
  static const _natureEdge = Color(0xFF5F7D4C), _natureWash = Color(0xFF7F9A6A);
  static const _monument = Color(0xFF8A5A3A), _building = Color(0xFF6B4A33), _wiki = Color(0xFF3D5566);

  TextStyle _labelStyle(Color c) => TextStyle(
        fontFamily: serif,
        fontStyle: FontStyle.italic,
        fontSize: 10,
        color: c,
        shadows: const [Shadow(color: paper, blurRadius: 1.5), Shadow(color: paper, blurRadius: 1.5)],
      );

  Iterable<Polygon> _polys(Area a, {Color? fill, double edge = 0, Color edgeColor = ink, StrokePattern? pattern, String? label, TextStyle? style}) sync* {
    for (final rings in a.shape) {
      if (rings.isEmpty || rings.first.length < 3) continue;
      yield Polygon(
        points: rings.first,
        holePointsList: rings.length > 1 ? rings.sublist(1) : null,
        color: fill,
        borderStrokeWidth: edge,
        borderColor: edgeColor,
        pattern: pattern ?? const StrokePattern.solid(),
        label: label,
        labelStyle: style ?? const TextStyle(),
        labelPlacementCalculator: const PolygonLabelPlacementCalculator.polylabel(),
      );
    }
  }

  /// Protected nature sites: a faint green wash, a dashed edge, the name.
  List<Polygon> _nature() => [
        for (final a in widget.landmarks?.current?.nature ?? const <Area>[])
          ..._polys(a,
              fill: _natureWash.withValues(alpha: .07),
              edge: 1.2,
              edgeColor: _natureEdge.withValues(alpha: .7),
              pattern: StrokePattern.dashed(segments: const [3.6, 2.4]),
              label: a.name,
              style: _labelStyle(_natureEdge)),
      ];

  /// Scheduled monuments' dotted edges, named from zoom 13.5.
  List<Polygon> _monumentEdges() => [
        for (final a in widget.landmarks?.current?.monuments ?? const <Area>[])
          ..._polys(a,
              edge: .9,
              edgeColor: _monument,
              pattern: StrokePattern.dashed(segments: const [.9, 1.35]),
              label: _zoom >= 13.5 ? a.name : null,
              style: _labelStyle(_monument)),
      ];

  // registered parks and gardens, battlefields, World Heritage Sites
  static const _park = Color(0xFF6F7F45), _battle = Color(0xFF8C3B2A);

  /// Parks and gardens: an olive wash and a fine dotted edge; battlefields:
  /// a madder dash-and-dot edge; World Heritage Sites: a long ink dash.
  /// Named from zoom 13.5, 12.5 and always.
  List<Polygon> _heritageAreas() {
    final found = widget.landmarks?.current;
    if (found == null) return const [];
    return [
      for (final a in found.worldHeritage)
        ..._polys(a,
            edge: 1.6,
            edgeColor: ink.withValues(alpha: .7),
            pattern: StrokePattern.dashed(segments: const [9.6, 4.8]),
            label: a.name,
            style: _labelStyle(ink)),
      for (final a in found.parks)
        ..._polys(a,
            fill: _park.withValues(alpha: .08),
            edge: 1,
            edgeColor: _park.withValues(alpha: .8),
            pattern: StrokePattern.dotted(spacingFactor: 2),
            label: _zoom >= 13.5 ? a.name : null,
            style: _labelStyle(_park)),
      for (final a in found.battlefields)
        ..._polys(a,
            fill: _battle.withValues(alpha: .05),
            edge: 1.1,
            edgeColor: _battle.withValues(alpha: .8),
            pattern: StrokePattern.dashed(segments: const [4.4, 2.2, 1.1, 2.2]),
            label: _zoom >= 12.5 ? a.name : null,
            style: _labelStyle(_battle)),
    ];
  }

  /// A listed building's little church, or a Wikipedia place's ringed dot,
  /// with its name beside it once close enough.
  List<Marker> _spots(List<Spot> spots, {required bool wiki}) => [
        for (final s in spots)
          Marker(
            point: s.at,
            width: 220,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Semantics(
                    button: true,
                    label: '${s.name}, ${s.about}',
                    child: GestureDetector(
                      onTapUp: (d) {
                        final box = context.findRenderObject() as RenderBox?;
                        _say(box?.globalToLocal(d.globalPosition) ?? Offset.zero, s.name, s.about);
                      },
                      child: CustomPaint(
                        size: const Size.square(24),
                        painter: wiki
                            ? const _WikiPainter()
                            : _BuildingPainter(switch (s.grade) { 'I' => 1.15, 'II*' => .9, _ => .7 }),
                      ),
                    ),
                  ),
                ),
                if (_zoom >= (wiki ? 14 : (s.grade == 'II' ? 16 : 14.5)))
                  Positioned(
                    left: 110 + (wiki ? 8 : 9),
                    top: 0,
                    bottom: 0,
                    width: 90,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Halo(s.name, 10, wiki ? _wiki : _building, halo: 1.5, align: TextAlign.left),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ];

  /// A cross where each species was first heard, or at every call; the
  /// first of each named and on top.
  List<Marker> _birds() {
    final seen = <String>{}, firsts = <Marker>[], rest = <Marker>[];
    for (final b in widget.walk?.birds ?? const <WalkBird>[]) {
      final first = seen.add(b.sci);
      if (!widget.allBirds && !first) continue;
      final size = first ? 24.0 : 18.0;
      final m = Marker(
        point: b.at,
        width: 140,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Semantics(
              button: true,
              label: '${b.common}: open its card',
              child: GestureDetector(
                onTap: () => widget.onBird(b.sci, b.common),
                child: CustomPaint(size: Size.square(size + 8), painter: _CrossPainter(size)),
              ),
            ),
            if (first) Positioned(top: 32 + 15, child: IgnorePointer(child: _Halo(b.common, 11, madder, halo: 1.6))),
          ],
        ),
      );
      (first ? firsts : rest).add(m);
    }
    return [...rest, ...firsts];
  }

  @override
  Widget build(BuildContext context) {
    final kit = _kit, w = widget.walk, note = _note();
    final pts = _points;
    final initial = pts.length > 1
        ? CameraFit.coordinates(
            coordinates: pts,
            padding: EdgeInsets.all(math.min(60.0, (math.min(widget.size.width, widget.size.height) / 6).roundToDouble())),
            maxZoom: 16)
        : null;
    final center = pts.length == 1 ? pts.first : (w?.place ?? const LatLng(52.5, -1.5));
    return Listener(
      onPointerDown: (e) {
        _fingers.add(e.pointer);
        widget.onHold(true);
      },
      onPointerUp: (e) {
        _fingers.remove(e.pointer);
        if (_fingers.isEmpty) widget.onHold(false);
      },
      onPointerCancel: (e) {
        _fingers.remove(e.pointer);
        if (_fingers.isEmpty) widget.onHold(false);
      },
      child: SizedBox.fromSize(
        size: widget.size,
        child: ClipRect(
          child: Stack(
            children: [
              if (kit != null)
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: pts.length == 1 ? 16 : (w?.place != null ? 14 : 5),
                    initialCameraFit: initial,
                    maxZoom: 18,
                    backgroundColor: paper,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onMapReady: () {
                      _ready = true;
                      _fittedTo = w?.key;
                      _zoom = _map.camera.zoom;
                      _traceContours();
                      _lookAround();
                    },
                    onPositionChanged: _moved,
                    onTap: _tapped,
                  ),
                  children: [
                    vt.VectorTileLayer(
                      theme: kit.base,
                      tileProviders: kit.providers,
                      sprites: kit.sprites,
                      glyphs: kit.glyphs,
                    ),
                    // extras: protected nature sites, scheduled monuments
                    if (widget.landmarks?.current != null) ...[
                      PolygonLayer(polygons: _nature(), drawLabelsLast: true),
                      _Hatch(widget.landmarks!.current!.monuments),
                      PolygonLayer(polygons: _monumentEdges(), drawLabelsLast: true),
                      PolygonLayer(polygons: _heritageAreas(), drawLabelsLast: true),
                    ],
                    // contours, traced here from the elevation tiles
                    PolylineLayer(polylines: _contourLines()),
                    MarkerLayer(markers: _contourLabels()),
                    // extras: OpenStreetMap's nature reserves, from the tiles
                    if (widget.landmarks != null)
                      vt.VectorTileLayer(
                        theme: kit.reserves,
                        tileProviders: kit.providers,
                        sprites: kit.sprites,
                        glyphs: kit.glyphs,
                        controller: _reserves,
                      ),
                    vt.VectorTileLayer(
                      theme: kit.labels,
                      tileProviders: kit.providers,
                      sprites: kit.sprites,
                      glyphs: kit.glyphs,
                      controller: _peaks,
                    ),
                    if (widget.landmarks?.current != null) ...[
                      MarkerLayer(
                          markers: _spots([
                        for (final s in widget.landmarks!.current!.listed)
                          if (s.grade != 'II' || _zoom >= 14) s
                      ], wiki: false)),
                      MarkerLayer(markers: _spots(widget.landmarks!.current!.wiki, wiki: true)),
                    ],
                    // the walk
                    if (w != null && w.trail.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(points: w.trail, strokeWidth: 7, color: paper.withValues(alpha: .8)),
                        Polyline(
                          points: w.trail,
                          strokeWidth: 3,
                          color: ink,
                          pattern: const StrokePattern.dotted(spacingFactor: 2.2),
                        ),
                      ]),
                    MarkerLayer(markers: _ends()),
                    MarkerLayer(markers: _birds()),
                  ],
                ),
              if (kit != null)
                Positioned(
                  left: 10,
                  top: 10,
                  child: _ZoomButtons(
                    map: _map,
                    home: w == null || (w.trail.isEmpty && w.birds.isEmpty && w.place == null) ? null : _home,
                    homeTip: w?.station != null ? 'Back to the station' : 'Back to the walk',
                  ),
                ),
              if (kit != null)
                Positioned(
                  right: 10,
                  top: 10,
                  child: PlaceSearch(
                    width: math.min(280.0, widget.size.width - 70),
                    near: () => _ready ? _map.camera.center : center,
                    onPick: _goTo,
                  ),
                ),
              if (kit != null)
                Positioned(
                    right: 0,
                    bottom: 0,
                    child: _Credit(_credit + (widget.landmarks != null ? _extrasCredit() : '') + _searchCredit)),
              if (note != null)
                Positioned(
                  left: 8,
                  right: 48,
                  bottom: 6.4,
                  child: IgnorePointer(
                    child: Text(note,
                        style: const TextStyle(
                          fontFamily: serif,
                          fontStyle: FontStyle.italic,
                          fontSize: 12.8,
                          color: sepia,
                          shadows: [Shadow(color: paper, blurRadius: 3), Shadow(color: paper, blurRadius: 3)],
                        )),
                  ),
                ),
              if (_tip != null) _tipBox(_tip!),
            ],
          ),
        ),
      ),
    );
  }

  /// The page's #tip: name, then a line in italic, above where it was
  /// tapped (below when there is no room).
  Widget _tipBox(({String title, String sub, Offset at}) t) => Positioned(
        left: (t.at.dx - 120).clamp(8.0, math.max(8.0, widget.size.width - 248)),
        top: t.at.dy > 80 ? t.at.dy - 70 : t.at.dy + 22,
        width: 240,
        child: IgnorePointer(
          child: Center(
            child: Container(
              decoration: const BoxDecoration(color: paper, boxShadow: [
                BoxShadow(color: paper, spreadRadius: 3),
                BoxShadow(color: Color(0xFFBCAB86), spreadRadius: 4),
                BoxShadow(color: Color(0x2E3C280A), offset: Offset(0, 6), blurRadius: 18),
              ]),
              foregroundDecoration: BoxDecoration(border: Border.all(color: const Color(0xFFBCAB86))),
              padding: const EdgeInsets.fromLTRB(12.8, 7.2, 12.8, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(t.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: serif, fontSize: 16.8, height: 1.25, color: ink)),
                if (t.sub.isNotEmpty)
                  Text(t.sub,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14.4, height: 1.25, color: sepia)),
              ]),
            ),
          ),
        ),
      );
}

/// Text in the map's way: italic, with a halo of paper round it.
class _Halo extends StatelessWidget {
  const _Halo(this.text, this.size, this.color, {required this.halo, this.align = TextAlign.center});

  final String text;
  final double size;
  final Color color;
  final double halo;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: size, fontStyle: FontStyle.italic, height: 1.2);
    return Stack(children: [
      Text(text,
          textAlign: align,
          style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = halo * 2
                ..strokeJoin = StrokeJoin.round
                ..color = paper)),
      Text(text, textAlign: align, style: style.copyWith(color: color)),
    ]);
  }
}

/// The map's ✕: two drawn strokes in madder over a broad paper one.
class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.size);

  final double size;

  @override
  void paint(Canvas canvas, Size box) {
    // drawn in the page's 48-unit picture, shown at [size]
    final k = size / 48;
    canvas.translate((box.width - size) / 2, (box.height - size) / 2);
    canvas.scale(k);
    final path = ui.Path()
      ..moveTo(12, 13)
      ..quadraticBezierTo(24, 23, 36, 35)
      ..moveTo(35, 12)
      ..quadraticBezierTo(25, 25, 13, 36);
    Paint s(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, s(paper, 13))
      ..drawPath(path, s(madder, 6));
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.size != size;
}

/// Scheduled monuments' hatching: fine diagonal lines in brown, clipped to
/// each monument (the page's "hatch" fill pattern).
class _Hatch extends StatelessWidget {
  const _Hatch(this.areas);

  final List<Area> areas;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _HatchPainter(areas, MapCamera.of(context))));
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter(this.areas, this.camera);

  final List<Area> areas;
  final MapCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF8A5A3A).withValues(alpha: .55 * .9)
      ..strokeWidth = .6;
    for (final a in areas) {
      for (final rings in a.shape) {
        if (rings.isEmpty || rings.first.length < 3) continue;
        final path = ui.Path()..fillType = PathFillType.evenOdd;
        for (final r in rings) {
          path.addPolygon([for (final p in r) camera.latLngToScreenOffset(p)], true);
        }
        final b = path.getBounds().intersect(Offset.zero & size);
        if (b.isEmpty) continue;
        canvas.save();
        canvas.clipPath(path);
        // lines x + y = c, every 4 points
        for (var c = ((b.left + b.top) / 4).floor() * 4.0; c <= b.right + b.bottom; c += 4) {
          canvas.drawLine(Offset(c - b.top, b.top), Offset(c - b.bottom, b.bottom), line);
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.camera != camera || old.areas != areas;
}

/// A listed building: the page's little church with a cross on its gable,
/// drawn in its 32-unit picture at half size, a little larger for Grade I.
class _BuildingPainter extends CustomPainter {
  const _BuildingPainter(this.scale);

  final double scale;

  @override
  void paint(Canvas canvas, Size box) {
    final k = .5 * scale;
    canvas.translate(box.width / 2 - 16 * k, box.height / 2 - 16 * k);
    canvas.scale(k);
    final body = ui.Path()
      ..moveTo(8, 27)
      ..lineTo(8, 15)
      ..lineTo(16, 8)
      ..lineTo(24, 15)
      ..lineTo(24, 27)
      ..close();
    final pen = Paint()
      ..color = const Color(0xFF6B4A33)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(body, Paint()..color = paper)
      ..drawPath(body, pen)
      ..drawPath(
          ui.Path()
            ..moveTo(16, 8)
            ..lineTo(16, 3)
            ..moveTo(13.5, 5)
            ..lineTo(18.5, 5)
            ..moveTo(14, 27)
            ..lineTo(14, 20)
            ..lineTo(18, 20)
            ..lineTo(18, 27),
          pen);
  }

  @override
  bool shouldRepaint(_BuildingPainter old) => old.scale != scale;
}

/// A Wikipedia place: a ring round a dot, in slate (the page's 28-unit
/// picture at half size).
class _WikiPainter extends CustomPainter {
  const _WikiPainter();

  @override
  void paint(Canvas canvas, Size box) {
    const slate = Color(0xFF3D5566);
    final c = box.center(Offset.zero);
    canvas
      ..drawCircle(c, 4, Paint()..color = paper)
      ..drawCircle(
          c,
          4,
          Paint()
            ..color = slate
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1)
      ..drawCircle(c, 1.3, Paint()..color = slate);
  }

  @override
  bool shouldRepaint(_WikiPainter old) => false;
}

/// Start (a ring) and End or Now (a ring round a dot).
class _EndPainter extends CustomPainter {
  const _EndPainter(this.start);

  final bool start;

  @override
  void paint(Canvas canvas, Size box) {
    final c = box.center(Offset.zero);
    // the page's 36-unit pictures, shown at half size
    final r = start ? 4.5 : 5.0;
    canvas.drawCircle(c, r, Paint()..color = paper);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = start ? 1.5 : 1.25);
    if (!start) canvas.drawCircle(c, 2.5, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_EndPainter old) => old.start != start;
}

/// The map's + and − at the top left, on paper.
class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.map, this.home, this.homeTip = ''});

  final MapController map;

  /// Back to the walk or the station; null when there is nowhere to go.
  final VoidCallback? home;
  final String homeTip;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, String tip, double by) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: () {
              final c = map.camera;
              map.move(c.center, (c.zoom + by).clamp(2.0, 18.0));
            },
            child: SizedBox(
              width: 29,
              height: 29,
              child: Center(child: Text(label, style: const TextStyle(fontSize: 18, height: 1, color: ink))),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: paper, border: Border.all(color: paperDeep)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        button('+', 'Zoom in', 1),
        Container(width: 29, height: 1, color: paperDeep),
        button('−', 'Zoom out', -1),
        if (home != null) ...[
          Container(width: 29, height: 1, color: paperDeep),
          Tooltip(
            message: homeTip,
            child: Semantics(
              button: true,
              label: homeTip,
              child: InkWell(
                onTap: home,
                child: const SizedBox(
                  width: 29,
                  height: 29,
                  child: Center(child: Icon(Icons.refresh, size: 17, color: ink)),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Where the map comes from: a small ⓘ that opens to the credit, as the
/// web map's compact attribution.
class _Credit extends StatefulWidget {
  const _Credit(this.text);

  final String text;

  @override
  State<_Credit> createState() => _CreditState();
}

class _CreditState extends State<_Credit> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          color: paper.withValues(alpha: .85),
          child: Text(_open ? widget.text : 'ⓘ',
              style: const TextStyle(fontFamily: serif, fontSize: 10, color: ink, height: 1.3)),
        ),
      );
}
