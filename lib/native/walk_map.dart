import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute, consolidateHttpClientResponseBytes, kDebugMode, visibleForTesting;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show caps, ink, madder, paper, paperDeep, sepia, serif;
import '../settings.dart';
import 'bird_records.dart';
import 'engravings.dart';
import 'wildlife.dart';
import '../store/detection_store.dart';
import 'contours.dart';
import 'antiquities.dart';
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
  return '\n© Historic England $y. © Natural England copyright. Contains NatureScot information. '
      'Contains Natural Resources Wales information © Natural Resources Wales and Database Right. '
      'Contains Ordnance Survey data © Crown copyright and database right $y · Places from Wikipedia (CC BY-SA)';
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
  static Walk of(
    DetectionStore store,
    Session selected,
    String model, {
    bool Function(String common, String sci)? ignore,
  }) {
    final parts = store.walkOf(selected);
    final heard = [
      for (final x in parts)
        for (final d in store.forPlate(model, session: x))
          if (d.hasPlace && !(ignore?.call(d.common, d.sci) ?? false)) d
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
  _Kit(this.base, this.labels, this.reserves, this.hides, this.providers, this.sprites, this.glyphs);

  final vt.Theme base;
  final vt.Theme labels;

  /// OpenStreetMap's nature reserves, with the extras.
  final vt.Theme reserves;

  /// Bird hides and viewpoints, with the extras.
  final vt.Theme hides;
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
        reader.read(hidesStyle('omt'), id: 'birdsong-walk-hides-1'),
        vt.TileProviders({'omt': provider}),
        await mapSprites(),
        vt.GlyphSource.network(_glyphs),
      );
    } finally {
      client.close();
    }
  }
}

/// Approximate box of a bird's name, centred under the heart. Width is
/// about 6.2 px a letter plus 6; height about 15. The name sits 15 px
/// below the marker's centre (Ed, 23 Nov).
@visibleForTesting
Rect birdNameBox(Offset heart, String name) {
  const height = 15.0;
  final width = name.length * 6.2 + 6;
  return Rect.fromLTWH(heart.dx - width / 2, heart.dy + 15, width, height);
}

/// Approximate box of a bird's name placed above the heart when below is taken.
@visibleForTesting
Rect birdNameBoxAbove(Offset heart, String name) {
  const height = 15.0;
  final width = name.length * 6.2 + 6;
  return Rect.fromLTWH(heart.dx - width / 2, heart.dy - 15 - height, width, height);
}

/// Which names to keep when their boxes may overlap. [boxes] are in order
/// (earliest heard first): the first of a cluster is kept, and a later
/// name is dropped only when it overlaps one already kept (Ed, 23 Nov).
@visibleForTesting
List<int> birdNamesToKeep(List<Rect> boxes) {
  final keep = <int>[];
  final kept = <Rect>[];
  for (var i = 0; i < boxes.length; i++) {
    final box = boxes[i];
    if (kept.any(box.overlaps)) continue;
    keep.add(i);
    kept.add(box);
  }
  return keep;
}

/// The walk on a map, in place of the collage: the web plate's map mode
/// (assets/app/map-mode.js) in Flutter. A dotted trail from Start to End
/// (or Now), a heart where each species was first heard ([allBirds]: every
/// call), contours traced from elevation tiles, peaks with their heights,
/// on the paper style built for it. A tap on a heart, or on its name, opens
/// that bird's card ([onBird]); on a peak or an end, a label says what it is.
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
    this.onFullScreen,
    this.onPoi,
    this.fullScreen = false,
    this.settings,
    this.species = const [],
  });

  final Walk? walk;
  final bool allBirds;
  final Size size;
  final void Function(String sci, String common) onBird;
  final ValueChanged<bool> onHold;

  /// The extras (Settings.mapExtras), or null when they are off.
  final LandmarkLookup? landmarks;

  /// Opens the map full screen, or (when [fullScreen]) closes it again.
  final VoidCallback? onFullScreen;

  /// Optional POI ("Passed on the way") button beside Search at top left.
  final VoidCallback? onPoi;

  /// This map is the full-screen one: its button closes it.
  final bool fullScreen;

  /// The app's settings, for the layers button (what the map shows).
  final Settings? settings;

  /// The birds heard, most first, for "Bird records": which one's records
  /// (GBIF) to show.
  final List<({String sci, String common})> species;

  @override
  State<WalkMap> createState() => _WalkMapState();
}

class _WalkMapState extends State<WalkMap> {
  final _map = MapController();
  final _peaks = vt.VectorTileLayerController();
  final _reserves = vt.VectorTileLayerController();
  final _hides = vt.VectorTileLayerController();

  // the layers panel, and the GBIF number of the bird whose records show
  bool _layersOpen = false;

  // wildlife pictures: the animal (or none) for each tile asked, and those
  // for the view
  static final Map<String, Critter?> _critterCache = {};
  List<Critter> _critters = const [];
  int _critterRun = 0;
  String _recordsFor = '';
  int? _recordsKey;
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
  ({String title, String sub, Offset at, Uri? page})? _tip;
  Timer? _tipTimer;
  Timer? _lookTimer;

  int _focusSeen = 0;

  // ---- debug readout (debug builds only): where a slow frame's time goes
  final List<({DateTime at, int build, int raster})> _frames = [];
  String _layersCost = '';
  Timer? _probeTick;

  void _timings(List<ui.FrameTiming> ts) {
    final now = DateTime.now();
    for (final t in ts) {
      _frames.add((at: now, build: t.buildDuration.inMilliseconds, raster: t.rasterDuration.inMilliseconds));
    }
    _frames.removeWhere((f) => now.difference(f.at).inSeconds > 3);
  }

  String get _probe {
    var b = 0, r = 0;
    for (final f in _frames) {
      b = math.max(b, f.build);
      r = math.max(r, f.raster);
    }
    return 'worst frame, last 3 s: build ${b} ms (UI thread), raster ${r} ms (drawing thread) · '
        'z${_zoom.toStringAsFixed(1)}\n$_layersCost\n$lastLook';
  }

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      SchedulerBinding.instance.addTimingsCallback(_timings);
      _probeTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    _focusSeen = widget.landmarks?.focusAsked ?? 0;
    widget.landmarks?.addListener(_landmarksChanged);
    _askLandmarks();
    _Kit.load().then((k) {
      if (!mounted) return;
      setState(() => _kit = k);
      // the tiles' reserves need the kit: ask (again) now it's here
      _askLandmarks();
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
    // the pictures switched on: find them for this view
    if (wildlifePicturesOn && (widget.settings?.mapWildlife ?? true) && _critters.isEmpty && _ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _findCritters());
    }
    if (widget.walk?.key != old.walk?.key) _dragged = false;
    if (_ready && !_dragged && widget.walk?.key != _fittedTo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  @override
  void dispose() {
    if (kDebugMode) SchedulerBinding.instance.removeTimingsCallback(_timings);
    _probeTick?.cancel();
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
    final l = widget.landmarks, w = widget.walk, kit = _kit;
    // with the kit, so the reserves can be read from its tiles
    if (l == null || w == null || kit == null) return;
    final path = [...w.trail, for (final b in w.birds) b.at];
    if (path.isEmpty && w.place != null) path.add(w.place!);
    final omt = kit.providers['omt'];
    Future<Uint8List?> tile(int z, int x, int y) async {
      if (omt == null) return null;
      final r = await omt.load(vt.TileKey(math.min(z, omt.maximumZoom), x, y));
      return r is vt.TileResponseData ? r.bytes : null;
    }

    final s = widget.settings;
    final kinds = s == null
        ? allLayers
        : {
            if (s.mapShowHeritage) 'heritage',
            if (s.mapShowNature) 'nature',
            if (s.mapShowAncient) 'ancient',
            if (s.mapShowWiki) 'wiki',
          };
    // not while building: the lookup tells its listeners at once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final before = l.layers;
      l.useLayers(kinds, withReserves: s?.mapShowReserves ?? true);
      l.want(w.key, path, tile: tile);
      // layers changed: what is in view is asked for again too
      if (!identical(before, l.layers)) _lookAround();
    });
  }

  /// The landmarks in view, as the map comes to rest.
  void _lookAround() {
    final l = widget.landmarks;
    if (l == null || !mounted || !_ready) return;
    final c = _map.camera, b = c.visibleBounds;
    l.look(b.west, b.south, b.east, b.north, c.zoom);
  }

  /// The wildlife pictures for the view: one tile two zooms out at a time,
  /// read on a background isolate and kept for the run.
  Future<void> _findCritters() async {
    final kit = _kit, omt = kit?.providers['omt'];
    if (!wildlifePicturesOn || !mounted || !_ready || omt == null || !(widget.settings?.mapWildlife ?? true)) {
      if (_critters.isNotEmpty && mounted) setState(() => _critters = const []);
      return;
    }
    final run = ++_critterRun;
    final c = _map.camera, b = c.visibleBounds;
    final z = math.min(critterZoom(c.zoom), omt.maximumZoom);
    final r = tileRange(b.west, math.max(-85.0, b.south), b.east, math.min(85.0, b.north), z);
    if ((r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1) > 36) return;
    final found = <Critter>[];
    for (var x = r.x0; x <= r.x1; x++) {
      for (var y = r.y0; y <= r.y1; y++) {
        final key = '$z/$x/$y';
        if (!_critterCache.containsKey(key)) {
          Critter? got;
          try {
            final res = await omt.load(vt.TileKey(z, x, y));
            if (res is vt.TileResponseData) {
              got = await critterAway(res.bytes, z, x, y);
            }
          } catch (e) {
            debugPrint('wildlife: tile $key: $e');
          }
          _critterCache[key] = got;
          if (run != _critterRun || !mounted) return;
        }
        final got = _critterCache[key];
        if (got != null) found.add(got);
      }
    }
    for (final cr in found) {
      Engravings.want(cr.animal);
    }
    if (run == _critterRun && mounted) setState(() => _critters = found);
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
      // and its label there, which opens its page
      final p = l.chosen!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ready) _say(_map.camera.latLngToScreenOffset(p.where!), p.name, p.about, page: p.page);
      });
    }
    setState(() {});
  }

  // ---- the view ----------------------------------------------------------

  List<LatLng> get _points => [
        ...?widget.walk?.trail,
        for (final b in widget.walk?.birds ?? const <WalkBird>[]) b.at,
      ];

  bool _hasSpan(List<LatLng> pts) {
    if (pts.length < 2) return false;
    final first = pts.first;
    for (var i = 1; i < pts.length; i++) {
      if ((pts[i].latitude - first.latitude).abs() > 1e-6 ||
          (pts[i].longitude - first.longitude).abs() > 1e-6) {
        return true;
      }
    }
    return false;
  }

  /// Fit tightly to the walk trail and bird detections; fall back to the
  /// session/station place when there are no trail or bird points.
  void _fit() {
    if (!mounted || !_ready) return;
    final w = widget.walk;
    _fittedTo = w?.key;
    final pts = _points;
    if (pts.isEmpty) {
      if (w?.place != null) _map.move(w!.place!, 15);
      return;
    }
    final pad = math.min(48.0, (math.min(widget.size.width, widget.size.height) / 7).roundToDouble());
    if (!_hasSpan(pts)) {
      _map.move(pts.first, 17.5);
    } else {
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: EdgeInsets.all(pad), maxZoom: 18));
    }
  }

  void _moved(MapCamera camera, bool byHand) {
    if (byHand) _dragged = true;
    if ((camera.zoom - _zoom).abs() > .05) {
      setState(() => _zoom = camera.zoom);
    } else if (_layersBox != null && _layersMemo != null) {
      // panned past the edges cut for the last view: cut them again
      final b = camera.visibleBounds;
      if (!frameHolds(_layersBox!, [b.west, b.south, b.east, b.north])) setState(() {});
    }
    if (_tip != null) setState(() => _tip = null);
    _contourTimer?.cancel();
    _contourTimer = Timer(const Duration(milliseconds: 150), _traceContours);
    _lookTimer?.cancel();
    _lookTimer = Timer(const Duration(milliseconds: 600), () {
      _lookAround();
      _findCritters();
    });
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

  /// A tap on the map names what is there, most particular first: a bird's
  /// cross or an end (they answer for themselves), a building or Wikipedia
  /// place, a peak, a monument, battlefield or park, a reserve, then the
  /// wider designations (World Heritage Sites, Natural England's sites).
  void _tapped(TapPosition at, LatLng ll) {
    final p = at.relative;
    if (p == null) return;
    final camera = _map.camera;
    bool near(LatLng q, double px) => (camera.latLngToScreenOffset(q) - p).distance <= px;
    final w = widget.walk;
    if (w != null) {
      final ends = [if (w.trail.isNotEmpty) w.trail.first else if (w.place != null) w.place!, if (w.trail.length > 1) w.trail.last];
      if (w.birds.any((b) => near(b.at, 16)) || ends.any((e) => near(e, 14))) return;
    }
    final found = widget.landmarks?.current;
    // the nearest building or Wikipedia place within a finger's reach
    Spot? spot;
    var best = 16.0;
    // only what is drawn at this zoom (see _layers)
    for (final s in [
      if (_zoom >= 12)
        for (final s in found?.listed ?? const <Spot>[])
          if (s.grade != 'II' || _zoom >= gradeTwoZoom) s,
      if (_zoom >= 12) ...?found?.wiki,
    ]) {
      final d = (camera.latLngToScreenOffset(s.at) - p).distance;
      if (d <= best) {
        best = d;
        spot = s;
      }
    }
    if (spot != null) return _say(p, spot.name, spot.about, page: pageOf(spot.name, spot.about, spot.link));
    for (final cr in _critters) {
      if (Engravings.of(cr.animal) != null && near(cr.at, 22)) {
        return _say(p, animalNames[cr.animal] ?? cr.animal, 'A picture for the ${switch (cr.habitat) {
          'wood' => 'woods',
          'heath' => 'heath and moor',
          'wetland' => 'marsh',
          'water' => 'water',
          _ => 'sea',
        }}, not a sighting. Engraving by Thomas Bewick');
      }
    }
    if (widget.landmarks != null && (widget.settings?.mapShowHides ?? true)) {
      final h = _hides.queryRenderedFeatures(p, layerIds: const ['hides', 'viewpoints']);
      if (h.isNotEmpty) {
        final hide = h.first.properties['subclass'] == 'bird_hide';
        final name = '${h.first.properties['name'] ?? ''}';
        return _say(p, name.isEmpty ? (hide ? 'Bird hide' : 'Viewpoint') : name, hide ? 'Bird hide' : 'Viewpoint');
      }
    }
    final peak = _peaks.queryRenderedFeatures(p, layerIds: const ['peaks']);
    if (peak.isNotEmpty) {
      final props = peak.first.properties, ele = props['ele'];
      return _say(p, '${props['name'] ?? ''}', ele != null ? '$ele m' : 'Summit');
    }
    for (final a in [...?found?.monuments, ...?found?.battlefields, ...?found?.parks]) {
      if (inShape(ll, a.shape)) return _say(p, a.name, a.about, page: pageOf(a.name, a.about, a.link));
    }
    if (widget.landmarks != null && (widget.settings?.mapShowReserves ?? true)) {
      for (final f in _reserves.queryRenderedFeatures(p, layerIds: const ['reserve-fill'])) {
        final name = f.properties['name'];
        if (name == null || '$name'.isEmpty) continue;
        final plain = plainName('$name');
        // its Wikipedia line, when it has one ("Ham Wall": wetland nature reserve)
        final wiki = found?.wiki.where((s) => plainName(s.name) == plain && s.about != 'Wikipedia').firstOrNull;
        final about = wiki?.about ?? reserveKinds[f.properties['class']] ?? 'Nature reserve';
        return _say(p, '$name', about, page: pageOf('$name', about, wiki?.link));
      }
    }
    for (final a in [...?found?.worldHeritage, ...?found?.nature]) {
      if (inShape(ll, a.shape)) return _say(p, a.name, a.about, page: pageOf(a.name, a.about, a.link));
    }
    if (_tip != null) setState(() => _tip = null);
  }

  /// The label at [at]: [title], then [sub]; with [page], a last line that
  /// opens it (and the label stays a little longer to be reached).
  void _say(Offset at, String title, String sub, {Uri? page}) {
    _tipTimer?.cancel();
    // Tapping the same thing again closes its label (Ed, Nov 2026).
    if (_tip != null && _tip!.title == title && _tip!.sub == sub) {
      setState(() => _tip = null);
      return;
    }
    setState(() => _tip = (title: title, sub: sub, at: at, page: page));
    _tipTimer = Timer(Duration(milliseconds: page != null ? 8000 : 3500), () {
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

  /// Decide which bird names show (and whether below or above their heart), plus
  /// the screen rects of all bird hearts and placed bird names so Start/End
  /// labels can dodge or hide when overlapped.
  ({Map<String, bool> placement, List<Rect> obstacles}) _birdLabelLayout() {
    final birds = widget.walk?.birds ?? const <WalkBird>[];
    final seen = <String>{};
    final earliest = <WalkBird>[];
    for (final b in birds) {
      if (seen.add(b.sci)) earliest.add(b);
    }
    final placement = <String, bool>{}; // sci -> true (below) / false (above)
    final obstacles = <Rect>[];
    if (!_ready) {
      for (final b in earliest) {
        placement[b.sci] = true;
      }
      return (placement: placement, obstacles: obstacles);
    }
    final heartRects = [
      for (final b in earliest)
        Rect.fromCenter(center: _map.camera.latLngToScreenOffset(b.at), width: 22, height: 22),
    ];
    obstacles.addAll(heartRects);
    final placedNames = <Rect>[];
    for (var i = 0; i < earliest.length; i++) {
      final b = earliest[i];
      final pt = _map.camera.latLngToScreenOffset(b.at);
      final below = birdNameBox(pt, b.common);
      final above = birdNameBoxAbove(pt, b.common);
      bool collides(Rect r) {
        if (placedNames.any(r.overlaps)) return true;
        for (var j = 0; j < heartRects.length; j++) {
          if (j != i && heartRects[j].overlaps(r)) return true;
        }
        return false;
      }

      if (!collides(below)) {
        placement[b.sci] = true;
        placedNames.add(below);
        obstacles.add(below);
      } else if (!collides(above)) {
        placement[b.sci] = false;
        placedNames.add(above);
        obstacles.add(above);
      }
    }
    return (placement: placement, obstacles: obstacles);
  }

  List<Marker> _ends(List<Rect> birdObstacles) {
    final w = widget.walk;
    if (w == null) return const [];
    final line = w.trail;
    final a = line.isNotEmpty ? line.first : w.place;
    String time(DateTime? t) => t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    Marker end(LatLng at, bool start, String label, String when, {bool station = false}) {
      // Check if a bird heart or bird name covers the Start/End label:
      // try below, then above, else hide the word cleanly.
      bool? labelBelow = true;
      if (!station && _ready && birdObstacles.isNotEmpty) {
        final pt = _map.camera.latLngToScreenOffset(at);
        final below = birdNameBox(pt, label);
        final above = birdNameBoxAbove(pt, label);
        if (!birdObstacles.any(below.overlaps)) {
          labelBelow = true;
        } else if (!birdObstacles.any(above.overlaps)) {
          labelBelow = false;
        } else {
          labelBelow = null;
        }
      }
      return Marker(
        point: at,
        width: 80,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTapUp: (d) {
                final box = context.findRenderObject() as RenderBox?;
                final local = box?.globalToLocal(d.globalPosition) ?? Offset.zero;
                _say(local, label, when);
              },
              // Start +, finish ✕, in ink (Ed, Nov 2026); a station keeps its ring.
              child: CustomPaint(
                  size: const Size.square(22),
                  painter: station ? const _EndPainter(false) : _StartFinishPainter(start)),
            ),
            if (labelBelow != null)
              Positioned(
                top: labelBelow ? 32 + 12 : null,
                bottom: labelBelow ? null : 32 + 12,
                child: IgnorePointer(child: _Halo(label, 11, ink, halo: 1.6)),
              ),
          ],
        ),
      );
    }

    if (w.station != null) {
      return [if (w.place != null) end(w.place!, false, w.station!, 'The station', station: true)];
    }
    return [
      if (a != null) end(a, true, 'Start', time(w.start)),
      if (line.length > 1) end(line.last, false, w.live ? 'Now' : 'End', time(w.live ? DateTime.now() : w.end)),
    ];
  }

  // the extras' colours, as the page's layers
  static const _natureEdge = Color(0xFF5F7D4C), _natureWash = Color(0xFF7F9A6A);

  /// Over the wood's #c2cc9f and its trees: a little deeper and older.
  static const _ancient = Color(0x523F5A2A); // #3F5A2A at 32% (lightened from 60%)
  static const _monument = Color(0xFF8A5A3A), _building = Color(0xFF6B4A33), _wiki = Color(0xFF3D5566);

  TextStyle _labelStyle(Color c) => TextStyle(
        fontFamily: serif,
        fontStyle: FontStyle.italic,
        fontSize: 10,
        color: c,
        shadows: const [Shadow(color: paper, blurRadius: 1.5), Shadow(color: paper, blurRadius: 1.5)],
      );

  // Each outline's label point, worked out once. flutter_map's polylabel has
  // a fixed precision (0.0001°): on a large intricate outline (Falmouth Bay's
  // SPA, a coastal SSSI) it ran for seconds on the screen's thread at every
  // redraw, freezing the map.
  static final _labelPoints = Expando<LatLng>('label point');

  /// Where an outline's name goes: polylabel, at a precision of a hundredth
  /// of its size, for a modest outline; its centroid for a large one.
  static LatLng _labelPoint(List<LatLng> ring) {
    final had = _labelPoints[ring];
    if (had != null) return had;
    var x0 = 180.0, y0 = 90.0, x1 = -180.0, y1 = -90.0;
    for (final p in ring) {
      x0 = math.min(x0, p.longitude);
      x1 = math.max(x1, p.longitude);
      y0 = math.min(y0, p.latitude);
      y1 = math.max(y1, p.latitude);
    }
    final size = math.max(x1 - x0, y1 - y0);
    final calc = ring.length <= 600
        ? PolygonLabelPlacementCalculator.polylabel(precision: math.max(1e-5, size / 100))
        : const PolygonLabelPlacementCalculator.centroid();
    LatLng at;
    try {
      at = calc(Polygon(points: ring));
    } catch (_) {
      at = LatLng((y0 + y1) / 2, (x0 + x1) / 2);
    }
    return _labelPoints[ring] = at;
  }

  // registered parks and gardens, battlefields, World Heritage Sites
  static const _park = Color(0xFF6F7F45), _battle = Color(0xFF8C3B2A);

  /// An area's fill and its name, as polygons with no edge: the edge is
  /// drawn by [_edgeLines], cut to the view, because flutter_map works out
  /// a dashed edge's every dash along the whole outline on the screen's
  /// thread. Cornwall's mining World Heritage Site, at street zoom, is
  /// hundreds of thousands of pixels round: 11 s a frame in Falmouth.
  Iterable<Polygon> _fills(Area a, {Color? fill, String? label, TextStyle? style}) sync* {
    if (fill == null && label == null) return;
    for (final rings in a.shape) {
      if (rings.isEmpty || rings.first.length < 3) continue;
      yield Polygon(
        points: rings.first,
        holePointsList: rings.length > 1 ? rings.sublist(1) : null,
        color: fill,
        label: label,
        labelStyle: style ?? const TextStyle(),
        labelPlacementCalculator: label == null
            ? const PolygonLabelPlacementCalculator.centroid()
            : _LabelAt(_labelPoint(rings.first)),
      );
    }
  }

  /// An area's edge (every ring, holes too), only what lies in [box].
  Iterable<Polyline> _edgeLines(Area a, List<double> box,
      {required Color color, required double width, required StrokePattern pattern}) sync* {
    for (final rings in a.shape) {
      for (final r in rings) {
        for (final run in clipLine(r, box)) {
          if (run.length > 1) yield Polyline(points: run, color: color, strokeWidth: width, pattern: pattern);
        }
      }
    }
  }

  /// The areas: fills and names, then edges cut to [box].
  ({List<Polygon> fills, List<Polyline> lines}) _areas(Landmarks found, List<double> box) {
    final fills = <Polygon>[], lines = <Polyline>[];
    void area(Area a,
        {Color? fill, String? label, TextStyle? style, required Color edge, required double width, required StrokePattern pattern}) {
      fills.addAll(_fills(a, fill: fill, label: label, style: style));
      lines.addAll(_edgeLines(a, box, color: edge, width: width, pattern: pattern));
    }

    // ancient woods: the map's wood a shade deeper, no edge, no name
    for (final a in found.ancient) {
      fills.addAll(_fills(a, fill: _ancient));
    }
    // protected nature sites: a faint green wash, a dashed edge, the name
    for (final a in found.nature) {
      area(a,
          fill: _natureWash.withValues(alpha: .07),
          label: a.name,
          style: _labelStyle(_natureEdge),
          edge: _natureEdge.withValues(alpha: .7),
          width: 1.2,
          pattern: StrokePattern.dashed(segments: const [3.6, 2.4]));
    }
    // World Heritage Sites: a long ink dash, always named
    for (final a in found.worldHeritage) {
      area(a,
          label: a.name,
          style: _labelStyle(ink),
          edge: ink.withValues(alpha: .7),
          width: 1.6,
          pattern: StrokePattern.dashed(segments: const [9.6, 4.8]));
    }
    // scheduled monuments: a fine dotted edge (and hatching), named from 13.5
    // (Stonehenge by its drawing instead, [_drawnSites])
    for (final a in found.monuments) {
      area(a,
          label: _zoom >= 13.5 && !_drawnSites.any((d) => d.record(a.name)) ? a.name : null,
          style: _labelStyle(_monument),
          edge: _monument,
          width: .9,
          pattern: StrokePattern.dashed(segments: const [.9, 1.35]));
    }
    // parks and gardens: an olive wash, a dotted edge, named from 13.5
    for (final a in found.parks) {
      area(a,
          fill: _park.withValues(alpha: .08),
          label: _zoom >= 13.5 ? a.name : null,
          style: _labelStyle(_park),
          edge: _park.withValues(alpha: .8),
          width: 1,
          pattern: StrokePattern.dotted(spacingFactor: 2));
    }
    // battlefields: a madder dash-and-dot, named from 12.5
    for (final a in found.battlefields) {
      area(a,
          fill: _battle.withValues(alpha: .05),
          label: _zoom >= 12.5 ? a.name : null,
          style: _labelStyle(_battle),
          edge: _battle.withValues(alpha: .8),
          width: 1.1,
          pattern: StrokePattern.dashed(segments: const [4.4, 2.2, 1.1, 2.2]));
    }
    return (fills: fills, lines: lines);
  }

  static final _antiquityOf = <String, Antiquity?>{};

  /// What prehistoric site a monument is, if any (antiquities.dart), kept.
  static Antiquity? _antiquity(String name) => _antiquityOf.putIfAbsent(name, () => antiquityOf(name));

  /// A standing stone's slight mark: a small upright in sepia where each
  /// of Historic England's standing stones is (from 12); its name as any
  /// monument's.
  List<Marker> _standingStones(List<Area> monuments) {
    if (_zoom < 12) return const [];
    return [
      for (final a in monuments)
        if (_antiquity(a.name)?.kind == AntiquityKind.stone &&
            a.shape.isNotEmpty &&
            a.shape.first.isNotEmpty &&
            a.shape.first.first.length >= 3)
          Marker(
            point: _labelPoint(a.shape.first.first),
            width: 10,
            height: 14,
            child: IgnorePointer(child: CustomPaint(size: const Size(10, 14), painter: const _StonePainter())),
          ),
    ];
  }

  /// The two great stone circles, each drawn as a small engraving where it
  /// stands, named beneath; from zoom 9, with the landmarks on.
  List<Marker> _drawings() => [
        if (_zoom >= 9)
          for (final d in _drawnSites)
            Marker(
              point: d.at,
              width: 160,
              height: 64,
              child: IgnorePointer(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CustomPaint(size: const Size(56, 34), painter: _SitePainter(d.name)),
                  _Halo(d.name, 12, ink, halo: 1.6),
                ]),
              ),
            ),
      ];


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
                // drawn only: a tap goes to the map, which names the nearest
                // thing (so a place inside a reserve isn't answered twice)
                Center(
                  child: Semantics(
                    button: true,
                    label: '${s.name}, ${s.about}',
                    onTap: () => _say(_map.camera.latLngToScreenOffset(s.at), s.name, s.about,
                        page: pageOf(s.name, s.about, s.link)),
                    child: IgnorePointer(
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

  /// A heart where each species was first heard, or at every call; the
  /// first of each named and on top. Names that would overlap show only
  /// the earliest; a tap on a name opens the card, as the heart does
  /// (Ed, 23 Nov). Re-decided when the zoom changes ([_moved] rebuilds)
  /// and once the camera is ready.
  List<Marker> _birds(Map<String, bool> placement) {
    final birds = widget.walk?.birds ?? const <WalkBird>[];
    final seen = <String>{};
    final firsts = <Marker>[], rest = <Marker>[];
    for (final b in birds) {
      final first = seen.add(b.sci);
      if (!widget.allBirds && !first) continue;
      final size = first ? 24.0 : 18.0;
      final nameBelow = placement[b.sci];
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
                // A small red heart for each bird (Ed, Nov 2026; was a
                // madder cross), larger for a species' first.
                child: SizedBox.square(
                  dimension: size + 8,
                  child: Center(child: Text('❤️', style: TextStyle(fontSize: first ? 15 : 11, height: 1))),
                ),
              ),
            ),
            // Names in ink, apart from the red hearts (Ed, Nov 2026; were madder).
            // A tap on the name opens the card, as the heart does (Ed, 23 Nov).
            // Renders below the heart, or above if below would overlap.
            if (first && nameBelow != null)
              Positioned(
                top: nameBelow ? 32 + 15 : null,
                bottom: nameBelow ? null : 32 + 15,
                child: Semantics(
                  button: true,
                  label: '${b.common}: open its card',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onBird(b.sci, b.common),
                    child: _Halo(b.common, 11, ink, halo: 1.6),
                  ),
                ),
              ),
          ],
        ),
      );
      (first ? firsts : rest).add(m);
    }
    return [...rest, ...firsts];
  }

  // The extras as drawn, kept until what was found or a zoom step changes:
  // building them (and placing area labels) for every frame of a zoom made
  // a busy town (Falmouth) crawl.
  ({List<Polygon> fills, List<Polyline> lines, List<Area> hatched, List<Marker> spots})? _layersMemo;
  Object? _layersFound;
  String _layersStep = '';

  /// The box the edges were cut to: the view and as much again all round.
  List<double>? _layersBox;

  /// The view now, [west, south, east, north].
  List<double>? get _viewBox {
    if (!_ready) return null;
    final b = _map.camera.visibleBounds;
    return [b.west, b.south, b.east, b.north];
  }

  /// Which zoom thresholds the extras pass, as a key.
  String get _zoomStep => [11, 12, 12.5, 13, 13.5, 14, 14.5, gradeTwoZoom, 16].map((z) => _zoom >= z ? 1 : 0).join();

  /// The extras for this zoom: none when zoomed right out (below 11);
  /// buildings and Wikipedia places from 12 (Grade II from [gradeTwoZoom]),
  /// no more than [_maxSpots] of them, nearest the middle first.
  ({List<Polygon> fills, List<Polyline> lines, List<Area> hatched, List<Marker> spots})? _layers() {
    final found = widget.landmarks?.current;
    if (found == null || _zoom < 11) return null;
    final step = _zoomStep, view = _viewBox;
    final boxOk = view == null || (_layersBox != null && frameHolds(_layersBox!, view));
    if (identical(found, _layersFound) && step == _layersStep && boxOk && _layersMemo != null) return _layersMemo;
    final box = view == null
        ? <double>[-180, -85, 180, 85]
        : [
            view[0] - (view[2] - view[0]),
            view[1] - (view[3] - view[1]),
            view[2] + (view[2] - view[0]),
            view[3] + (view[3] - view[1]),
          ];
    _layersBox = view == null ? null : box;
    final listed = [
      for (final s in found.listed)
        if (_zoom >= (s.grade == 'II' ? gradeTwoZoom : 12)) s
    ];
    var spots = [...listed, if (_zoom >= 12) ...found.wiki];
    if (spots.length > _maxSpots && _ready) {
      final c = _map.camera.center;
      spots.sort((a, b) => metresBetween(a.at, c).compareTo(metresBetween(b.at, c)));
      spots = spots.take(_maxSpots).toList();
    }
    final wiki = found.wiki.toSet();
    _layersFound = found;
    _layersStep = step;
    final clock = Stopwatch()..start();
    final areas = _areas(found, box);
    _layersMemo = (
      fills: areas.fills,
      lines: areas.lines,
      hatched: found.monuments,
      spots: [
        ..._standingStones(found.monuments),
        ..._spots([for (final s in spots) if (!wiki.contains(s)) s], wiki: false),
        ..._spots([for (final s in spots) if (wiki.contains(s)) s], wiki: true),
      ],
    );
    if (kDebugMode) {
      final m = _layersMemo!;
      final pts = m.lines.fold(0, (n, p) => n + p.points.length);
      _layersCost = 'layers built in ${clock.elapsedMilliseconds} ms: ${m.fills.length} fills, ${m.lines.length} edges '
          '($pts pts near view), ${m.spots.length} marks, ${_critters.length} pictures; ${countAreas(found)} areas, ${countPoints(found)} pts';
    }
    return _layersMemo;
  }

  static const _maxSpots = 150;

  /// The chosen bird's GBIF number, looked up when the choice changes.
  void _followRecords() {
    final sci = widget.settings?.mapRecordsSci ?? '';
    if (sci == _recordsFor) return;
    _recordsFor = sci;
    _recordsKey = null;
    if (sci.isEmpty) return;
    BirdRecords.keyFor(sci).then((k) {
      if (mounted && _recordsFor == sci) setState(() => _recordsKey = k);
    });
  }

  @override
  Widget build(BuildContext context) {
    _followRecords();
    final kit = _kit, w = widget.walk, note = _note();
    final layers = _layers();
    final pts = _points;
    final hasSpan = _hasSpan(pts);
    final pad = math.min(48.0, (math.min(widget.size.width, widget.size.height) / 7).roundToDouble());
    final initial = hasSpan
        ? CameraFit.coordinates(
            coordinates: pts,
            padding: EdgeInsets.all(pad),
            maxZoom: 18)
        : null;
    final center = pts.isNotEmpty ? pts.first : (w?.place ?? const LatLng(52.5, -1.5));
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
                    initialZoom: pts.isNotEmpty && !hasSpan ? 17.5 : (w?.place != null ? 15 : 5),
                    initialCameraFit: initial,
                    maxZoom: 18,
                    backgroundColor: paper,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onMapReady: () {
                      // the camera exists: fit tightly to the trail and decide
                      // which bird names overlap (Ed, 23 Nov)
                      if (!mounted) return;
                      _ready = true;
                      if (!_dragged) _fit();
                      setState(() {
                        _fittedTo = w?.key;
                        _zoom = _map.camera.zoom;
                      });
                      _traceContours();
                      _lookAround();
                      _findCritters();
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
                    if (layers != null) ...[
                      PolygonLayer(polygons: layers.fills, drawLabelsLast: true, simplificationTolerance: 1.5),
                      if (_zoom >= 13) _Hatch(layers.hatched),
                      PolylineLayer(polylines: layers.lines, simplificationTolerance: 1.5),
                    ],
                    // contours, traced here from the elevation tiles
                    PolylineLayer(polylines: _contourLines()),
                    MarkerLayer(markers: _contourLabels()),
                    // extras: OpenStreetMap's nature reserves, from the tiles
                    if (widget.landmarks != null && (widget.settings?.mapShowReserves ?? true))
                      vt.VectorTileLayer(
                        theme: kit.reserves,
                        tileProviders: kit.providers,
                        sprites: kit.sprites,
                        glyphs: kit.glyphs,
                        controller: _reserves,
                      ),
                    // where the chosen bird has been recorded (GBIF), faintly
                    if (_recordsKey != null)
                      Opacity(
                        opacity: .55,
                        child: TileLayer(
                          urlTemplate: BirdRecords.tiles(_recordsKey!),
                          userAgentPackageName: 'uk.co.edstone.birdsongApp',
                          maxNativeZoom: 14,
                        ),
                      ),
                    vt.VectorTileLayer(
                      theme: kit.labels,
                      tileProviders: kit.providers,
                      sprites: kit.sprites,
                      glyphs: kit.glyphs,
                      controller: _peaks,
                    ),
                    if (layers != null) MarkerLayer(markers: layers.spots),
                    // Stonehenge and Calanais, drawn
                    if (widget.landmarks != null && (widget.settings?.mapShowHeritage ?? true))
                      MarkerLayer(markers: _drawings()),
                    if (widget.landmarks != null && (widget.settings?.mapShowHides ?? true))
                      vt.VectorTileLayer(
                        theme: kit.hides,
                        tileProviders: kit.providers,
                        sprites: kit.sprites,
                        glyphs: kit.glyphs,
                        controller: _hides,
                      ),
                    // wildlife pictures, for decoration
                    // (Bewick's engravings; only those that have arrived show)
                    if (wildlifePicturesOn && _critters.isNotEmpty && (widget.settings?.mapWildlife ?? true))
                      ValueListenableBuilder<int>(
                        valueListenable: Engravings.loaded,
                        builder: (context, n, child) => MarkerLayer(markers: [
                          for (final cr in _critters)
                            if (Engravings.of(cr.animal) case final img?)
                              Marker(
                                point: cr.at,
                                width: _zoom >= 12 ? 64 : 52,
                                height: _zoom >= 12 ? 64 : 52,
                                child: IgnorePointer(
                                  child: ColorFiltered(
                                    colorFilter: engravingTone(),
                                    child: RawImage(image: img, fit: BoxFit.contain),
                                  ),
                                ),
                              ),
                        ]),
                      ),
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
                    () {
                      final layout = _birdLabelLayout();
                      return MarkerLayer(markers: [
                        ..._ends(layout.obstacles),
                        ..._birds(layout.placement),
                      ]);
                    }(),
                  ],
                ),
              if (kit != null)
                Positioned(
                  right: (widget.fullScreen ? MediaQuery.paddingOf(context).right : 0) + 10,
                  top: (widget.fullScreen ? MediaQuery.paddingOf(context).top + 52 : 10),
                  child: _ZoomButtons(
                    map: _map,
                    style: widget.settings?.mapButtonStyle ?? 'ink',
                    home: w == null || (w.trail.isEmpty && w.birds.isEmpty && w.place == null) ? null : _home,
                    homeTip: w?.station != null ? 'Back to the station' : 'Back to the walk',
                    layers: widget.settings == null ? null : () => setState(() => _layersOpen = !_layersOpen),
                  ),
                ),
              if (kit != null)
                Positioned(
                  left: (widget.fullScreen ? MediaQuery.paddingOf(context).left : 0) + 10,
                  top: (widget.fullScreen ? MediaQuery.paddingOf(context).top : 0) + 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      PlaceSearch(
                        width: math.min(
                          220.0,
                          math.max(100.0, widget.size.width - 20 - 44 - (widget.onPoi != null ? 44 : 0)),
                        ),
                        style: widget.settings?.mapButtonStyle ?? 'ink',
                        near: () => _ready ? _map.camera.center : center,
                        onPick: _goTo,
                      ),
                      if (widget.onPoi != null) ...[
                        const SizedBox(width: 4),
                        _PoiButton(
                          onTap: widget.onPoi!,
                          style: widget.settings?.mapButtonStyle ?? 'ink',
                        ),
                      ],
                    ],
                  ),
                ),
              if (kit != null && _layersOpen && widget.settings != null)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _layersOpen = false),
                    child: Container(
                      color: const Color(0x402A241C),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 56),
                      child: GestureDetector(
                        onTap: () {},
                        child: SingleChildScrollView(
                          child: _LayersPanel(
                            settings: widget.settings!,
                            species: widget.species,
                            onClose: () => setState(() => _layersOpen = false),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (kit != null)
                Positioned(
                    left: (widget.fullScreen ? MediaQuery.paddingOf(context).left + 48 : 6),
                    bottom: (widget.fullScreen ? MediaQuery.paddingOf(context).bottom : 0) + 10,
                    child: _Credit(_credit +
                        (widget.landmarks != null ? _extrasCredit() : '') +
                        (_recordsKey != null ? '\nBird records: GBIF.org' : '') +
                        (_critters.any((c) => Engravings.of(c.animal) != null)
                            ? '\nEngravings: Thomas Bewick, Wellcome Collection'
                            : '') +
                        _searchCredit)),
              if (kDebugMode && widget.landmarks != null && (widget.settings?.mapDebugReadout ?? false))
                Positioned(
                  left: 44,
                  right: 8,
                  top: 48,
                  child: IgnorePointer(
                    child: Container(
                      color: const Color(0xCCFFFFFF),
                      padding: const EdgeInsets.all(4),
                      child: Text(_probe, style: const TextStyle(fontSize: 10, color: Color(0xFF000000), height: 1.25)),
                    ),
                  ),
                ),
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
  Widget _tipBox(({String title, String sub, Offset at, Uri? page}) t) => Positioned(
        left: (t.at.dx - 120).clamp(8.0, math.max(8.0, widget.size.width - 248)),
        top: t.at.dy > (t.page != null ? 98 : 80) ? t.at.dy - (t.page != null ? 92 : 70) : t.at.dy + 22,
        width: 240,
        // In the app's dialog look (Ed, Nov 2026: as the download and model
        // update dialogs): the deeper paper, rounded, a soft shadow, no ring.
        // A tap on it closes it; its link still opens the page.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _tipTimer?.cancel();
            setState(() => _tip = null);
          },
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                color: paperDeep,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x2E3C280A), offset: Offset(0, 6), blurRadius: 18)],
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 11),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(t.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: serif, fontSize: 16.8, height: 1.25, color: ink)),
                if (t.sub.isNotEmpty)
                  Text(t.sub,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14.4, height: 1.25, color: sepia)),
                if (t.page != null)
                  Semantics(
                    link: true,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => launchUrl(t.page!, mode: LaunchMode.externalApplication),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${pageName(t.page!)} ↗',
                              style: const TextStyle(
                                  fontFamily: serif,
                                  fontSize: 14.4,
                                  height: 1.25,
                                  color: madder,
                                  decoration: TextDecoration.underline,
                                  decorationColor: madder)),
                        ),
                      ),
                    ),
                  ),
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

/// A label point worked out beforehand (see _labelPoint).
@immutable
class _LabelAt implements PolygonLabelPlacementCalculator {
  const _LabelAt(this.at);

  final LatLng at;

  @override
  LatLng call(Polygon polygon) => at;

  @override
  bool operator ==(Object other) => other is _LabelAt && other.at == at;

  @override
  int get hashCode => at.hashCode;
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

/// The walk's start (+) and finish (✕), in ink on a paper halo, in the
/// cross's hand-drawn manner.
class _StartFinishPainter extends CustomPainter {
  const _StartFinishPainter(this.start);

  final bool start;

  @override
  void paint(Canvas canvas, Size box) {
    const size = 16.0;
    final k = size / 48;
    canvas.translate((box.width - size) / 2, (box.height - size) / 2);
    canvas.scale(k);
    final path = start
        ? (ui.Path()
          ..moveTo(24, 9)
          ..quadraticBezierTo(23, 24, 24.5, 39)
          ..moveTo(9, 24.5)
          ..quadraticBezierTo(24, 23, 39, 24))
        : (ui.Path()
          ..moveTo(12, 13)
          ..quadraticBezierTo(24, 23, 36, 35)
          ..moveTo(35, 12)
          ..quadraticBezierTo(25, 25, 13, 36));
    Paint s(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, s(paper, 14))
      ..drawPath(path, s(ink, 6));
  }

  @override
  bool shouldRepaint(_StartFinishPainter old) => old.start != start;
}

/// Style tokens for map controls: 'ink' (all-black icons with hover/touch-only
/// background, matching the rest of the app), 'paper' (permanent round warm
/// paper background with madder icons), or 'madder' (solid madder).
({Color bg, Color fg, Color divider, BorderRadius radius, Border? border, bool flat}) _mapControlTheme(String style) {
  if (style == 'madder') {
    return (
      bg: madder,
      fg: paper,
      divider: const Color(0x59EEE5CE),
      radius: const BorderRadius.all(Radius.circular(4)),
      border: null,
      flat: false,
    );
  }
  if (style == 'paper') {
    return (
      bg: paper.withValues(alpha: 0.94),
      fg: madder,
      divider: paperDeep,
      radius: const BorderRadius.all(Radius.circular(18)),
      border: Border.all(color: paperDeep),
      flat: false,
    );
  }
  return (
    bg: Colors.transparent,
    fg: ink,
    divider: Colors.transparent,
    radius: const BorderRadius.all(Radius.circular(20)),
    border: null,
    flat: true,
  );
}

const _controlShadow = BoxShadow(color: Color(0x4D3C280A), offset: Offset(0, 2), blurRadius: 8);

/// The map's + / − / reset / layers stack at the top right.
class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({
    required this.map,
    this.style = 'ink',
    this.home,
    this.homeTip = '',
    this.layers,
  });

  final MapController map;
  final String style;

  /// Back to the walk or the station; null when there is nowhere to go.
  final VoidCallback? home;
  final String homeTip;

  /// Opens the layers panel.
  final VoidCallback? layers;

  @override
  Widget build(BuildContext context) {
    final t = _mapControlTheme(style);
    if (t.flat) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            tooltip: 'Zoom in',
            icon: Icon(Icons.add, size: 22, color: t.fg),
            onPressed: () {
              final c = map.camera;
              map.move(c.center, (c.zoom + 1).clamp(2.0, 18.0));
            },
          ),
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            tooltip: 'Zoom out',
            icon: Icon(Icons.remove, size: 22, color: t.fg),
            onPressed: () {
              final c = map.camera;
              map.move(c.center, (c.zoom - 1).clamp(2.0, 18.0));
            },
          ),
          if (home != null)
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              padding: EdgeInsets.zero,
              tooltip: homeTip,
              icon: Icon(Icons.refresh, size: 20, color: t.fg),
              onPressed: home,
            ),
          if (layers != null)
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              padding: EdgeInsets.zero,
              tooltip: 'Layers',
              icon: Icon(Icons.layers_outlined, size: 20, color: t.fg),
              onPressed: layers,
            ),
        ],
      );
    }
    Widget button(String label, String tip, double by) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: () {
              final c = map.camera;
              map.move(c.center, (c.zoom + by).clamp(2.0, 18.0));
            },
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(child: Text(label, style: TextStyle(fontSize: 19, height: 1, color: t.fg))),
            ),
          ),
        );
    final sep = SizedBox(width: 24, height: 1, child: ColoredBox(color: t.divider));
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: t.radius, border: t.border, boxShadow: const [_controlShadow]),
      child: Material(
        color: t.bg,
        borderRadius: t.radius,
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          button('+', 'Zoom in', 1),
          sep,
          button('−', 'Zoom out', -1),
          if (home != null) ...[
            sep,
            Tooltip(
              message: homeTip,
              child: Semantics(
                button: true,
                label: homeTip,
                child: InkWell(
                  onTap: home,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(child: Icon(Icons.refresh, size: 18, color: t.fg)),
                  ),
                ),
              ),
            ),
          ],
          if (layers != null) ...[
            sep,
            Tooltip(
              message: 'Layers',
              child: Semantics(
                button: true,
                label: 'What the map shows',
                child: InkWell(
                  onTap: layers,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(child: Icon(Icons.layers_outlined, size: 18, color: t.fg)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Route / POI ("Passed on the way") icon button beside Search at top left.
class _PoiButton extends StatelessWidget {
  const _PoiButton({required this.onTap, this.style = 'ink'});

  final VoidCallback onTap;
  final String style;

  @override
  Widget build(BuildContext context) {
    final t = _mapControlTheme(style);
    if (t.flat) {
      return IconButton(
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        tooltip: 'Points of interest passed on the way',
        icon: Icon(Icons.route_outlined, size: 21, color: t.fg),
        onPressed: onTap,
      );
    }
    return Tooltip(
      message: 'Points of interest passed on the way',
      child: Semantics(
        button: true,
        label: 'POI',
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: t.radius, border: t.border, boxShadow: const [_controlShadow]),
          child: Material(
            color: t.bg,
            borderRadius: t.radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: Icon(Icons.route_outlined, size: 19, color: t.fg),
                ),
              ),
            ),
          ),
        ),
      ),
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

/// What the map shows: a box of switches beside the map's buttons. Each
/// kind of extra on or off (off, it isn't looked up either), and the bird
/// whose records (GBIF) are drawn. Turning any landmark on turns the
/// landmarks on (Settings > Map), and the last off turns them off.
class _LayersPanel extends StatelessWidget {
  const _LayersPanel({required this.settings, required this.species, required this.onClose});

  final Settings settings;
  final List<({String sci, String common})> species;
  final VoidCallback onClose;

  void _set(void Function(Settings s) change) => settings.update((s) {
        change(s);
        s.mapExtras = s.mapShowHeritage ||
            s.mapShowNature ||
            s.mapShowAncient ||
            s.mapShowWiki ||
            s.mapShowReserves ||
            s.mapShowHides;
      });

  @override
  Widget build(BuildContext context) {
    final s = settings, on = s.mapExtras;
    Widget row(String title, String sub, bool value, void Function(Settings s, bool v) put) => InkWell(
          onTap: () => _set((x) {
            // with the landmarks off, a switch turns that one on alone
            if (!on) {
              x
                ..mapShowHeritage = false
                ..mapShowNature = false
                ..mapShowAncient = false
                ..mapShowWiki = false
                ..mapShowReserves = false
                ..mapShowHides = false;
            }
            put(x, !(on && value));
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontFamily: serif, fontSize: 15, color: ink, height: 1.2)),
                  Text(sub,
                      style: const TextStyle(
                          fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 12, color: sepia, height: 1.2)),
                ]),
              ),
              Transform.scale(
                scale: .75,
                child: Switch(
                  value: on && value,
                  activeTrackColor: madder,
                  onChanged: (v) => _set((x) {
                    if (!on) {
                      x
                        ..mapShowHeritage = false
                        ..mapShowNature = false
                        ..mapShowAncient = false
                        ..mapShowWiki = false
                        ..mapShowReserves = false
                        ..mapShowHides = false;
                    }
                    put(x, v);
                  }),
                ),
              ),
            ]),
          ),
        );
    final chosen = species.any((b) => b.sci == s.mapRecordsSci) ? s.mapRecordsSci : '';
    return Container(
      width: 264,
      decoration: BoxDecoration(color: paper, border: Border.all(color: paperDeep), boxShadow: const [
        BoxShadow(color: Color(0x2E3C280A), offset: Offset(0, 6), blurRadius: 18),
      ]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 6, 0, 2),
            child: Text('On the map',
                style: TextStyle(fontFamily: serif, fontSize: 13, letterSpacing: 1.2, color: sepia)),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 16, color: sepia),
          ),
        ]),
        row('Heritage', 'Listed buildings, monuments, parks, battlefields', s.mapShowHeritage,
            (x, v) => x.mapShowHeritage = v),
        row('Nature sites', 'SSSIs, bird SPAs, nature reserves, wetlands', s.mapShowNature, (x, v) => x.mapShowNature = v),
        row('Ancient woods', 'A shade deeper: woods since 1600 (England)', s.mapShowAncient,
            (x, v) => x.mapShowAncient = v),
        row('Reserves', 'Nature reserves from OpenStreetMap', s.mapShowReserves, (x, v) => x.mapShowReserves = v),
        row('Hides & viewpoints', 'Where OpenStreetMap has them', s.mapShowHides, (x, v) => x.mapShowHides = v),
        row('Wikipedia places', 'With a line about each', s.mapShowWiki, (x, v) => x.mapShowWiki = v),
        if (wildlifePicturesOn)
        InkWell(
          onTap: () => settings.update((x) => x.mapWildlife = !x.mapWildlife),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
            child: Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Wildlife pictures', style: TextStyle(fontFamily: serif, fontSize: 15, color: ink, height: 1.2)),
                  Text('A few, for decoration: a deer in the woods',
                      style: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 12, color: sepia, height: 1.2)),
                ]),
              ),
              Transform.scale(
                scale: .75,
                child: Switch(
                  value: s.mapWildlife,
                  activeTrackColor: madder,
                  onChanged: (v) => settings.update((x) => x.mapWildlife = v),
                ),
              ),
            ]),
          ),
        ),
        const Divider(height: 1, color: paperDeep),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
          child: Text('Bird records',
              style: const TextStyle(fontFamily: serif, fontSize: 15, color: ink, height: 1.2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: species.isEmpty
              ? const Text('No birds heard here yet',
                  style: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 12, color: sepia))
              : DropdownButton<String>(
                  isExpanded: true,
                  value: chosen,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(fontFamily: serif, fontSize: 14, color: ink),
                  dropdownColor: paper,
                  items: [
                    const DropdownMenuItem(
                        value: '',
                        child: Text('None', style: TextStyle(fontStyle: FontStyle.italic, color: sepia))),
                    for (final b in species)
                      DropdownMenuItem(value: b.sci, child: Text(b.common, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => settings.update((x) => x.mapRecordsSci = v ?? ''),
                ),
        ),
        if (chosen.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Text('Where it has been recorded, from GBIF: darker hexagons, more records.',
                style: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 12, color: sepia)),
          ),
      ]),
    );
  }
}

/// Stonehenge and Calanais, the stone circles drawn on the map: where each
/// stands, and how Historic England names its record (Stonehenge's,
/// "Stonehenge, the Avenue, and three barrows…", is too long a label;
/// Calanais is in Scotland, outside Historic England's list).
typedef _DrawnSite = ({String name, LatLng at, bool Function(String record) record});

final _drawnSites = <_DrawnSite>[
  (name: 'Stonehenge', at: const LatLng(51.17886, -1.82623), record: (r) => r.startsWith('Stonehenge,')),
  (name: 'Calanais', at: const LatLng(58.19740, -6.74535), record: (_) => false),
];

/// A standing stone: a small leaning upright on a short ground line, in
/// sepia, light enough to sit under the names.
class _StonePainter extends CustomPainter {
  const _StonePainter();

  @override
  void paint(Canvas canvas, Size box) {
    final c = box.center(Offset.zero);
    final ink = Paint()..color = sepia.withValues(alpha: .85);
    canvas
      ..drawPath(
          ui.Path()
            ..moveTo(c.dx - 1.6, c.dy + 4.5)
            ..lineTo(c.dx - 1.1, c.dy - 4.6)
            ..quadraticBezierTo(c.dx + .2, c.dy - 5.8, c.dx + 1.3, c.dy - 4.9)
            ..lineTo(c.dx + 1.8, c.dy + 4.5)
            ..close(),
          ink)
      ..drawLine(c + const Offset(-3.6, 5), c + const Offset(3.6, 5),
          Paint()
            ..color = sepia.withValues(alpha: .7)
            ..strokeWidth = .7);
  }

  @override
  bool shouldRepaint(_StonePainter old) => false;
}

/// A little engraving of a great stone circle, seen from a little above:
/// Stonehenge's sarsen ring, gapped, with lintels along it, the tall
/// trilithons inside and a fallen stone before it; Calanais's ring of thin
/// stones round its tall central one, the avenue running off behind. Each
/// stone outlined in ink on paper and shaded with a few strokes.
class _SitePainter extends CustomPainter {
  const _SitePainter(this.name);

  final String name;

  @override
  void paint(Canvas canvas, Size box) {
    final w = box.width, h = box.height;
    final c = Offset(w / 2, h * .66);
    final face = Paint()..color = paper;
    final pen = Paint()
      ..color = ink
      ..strokeWidth = .65
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final hatch = Paint()
      ..color = ink
      ..strokeWidth = .4;
    // the ground: a few hatched strokes under the ring
    for (var i = -5; i <= 5; i++) {
      final x = c.dx + i * w * .075;
      canvas.drawLine(Offset(x - 1.6, c.dy + h * .3), Offset(x + 1.6, c.dy + h * .23), hatch);
    }
    // a stone: a tapering upright, outlined, shaded down its right side
    void stone(Offset foot, double tall, double wide) {
      final s = ui.Path()
        ..moveTo(foot.dx - wide / 2, foot.dy)
        ..lineTo(foot.dx - wide * .42, foot.dy - tall)
        ..quadraticBezierTo(foot.dx, foot.dy - tall * 1.06, foot.dx + wide * .4, foot.dy - tall * .98)
        ..lineTo(foot.dx + wide / 2, foot.dy)
        ..close();
      canvas
        ..drawPath(s, face)
        ..drawPath(s, pen);
      if (wide >= 2) {
        final x = foot.dx + wide * .18;
        canvas.drawLine(Offset(x, foot.dy - tall * .85), Offset(x, foot.dy - .4), hatch);
      }
    }

    // a lintel across two tops
    void lintel(Offset a, Offset b, double tall) {
      final r = ui.Path()
        ..moveTo(a.dx - 1.4, a.dy - tall - .2)
        ..lineTo(b.dx + 1.4, b.dy - tall - .2)
        ..lineTo(b.dx + 1.4, b.dy - tall - 2)
        ..lineTo(a.dx - 1.4, a.dy - tall - 2)
        ..close();
      canvas
        ..drawPath(r, face)
        ..drawPath(r, pen);
    }

    Offset on(int i, int n, double rx, double ry) =>
        c + Offset(math.cos(i * 2 * math.pi / n) * rx, math.sin(i * 2 * math.pi / n) * ry);
    bool back(int i, int n) => math.sin(i * 2 * math.pi / n) < 0;

    if (name == 'Stonehenge') {
      const n = 18, rx = 21.0, ry = 7.0, tall = 7.5;
      const gone = {3, 8, 11};
      // the far side of the ring, and its lintels
      for (var i = 0; i < n; i++) {
        if (back(i, n) && !gone.contains(i)) stone(on(i, n, rx, ry), tall, 2.4);
      }
      for (final (a, b) in const [(12, 13), (13, 14), (14, 15), (15, 16)]) {
        lintel(on(a, n, rx, ry), on(b, n, rx, ry), tall);
      }
      // the trilithons inside, taller
      for (final (x, y) in const [(-9.0, -1.5), (0.0, -3.0), (9.0, -1.5)]) {
        final f = c + Offset(x, y);
        stone(f + const Offset(-2, 0), 11.5, 2.6);
        stone(f + const Offset(2, 0), 11.5, 2.6);
        lintel(f + const Offset(-2, 0), f + const Offset(2, 0), 11.5);
      }
      // the near side
      for (var i = 0; i < n; i++) {
        if (!back(i, n) && !gone.contains(i)) stone(on(i, n, rx, ry), tall, 2.4);
      }
      for (final (a, b) in const [(0, 1), (5, 6), (6, 7)]) {
        lintel(on(a, n, rx, ry), on(b, n, rx, ry), tall);
      }
      // a fallen stone lying before the ring
      final f = ui.Path()
        ..moveTo(c.dx + 6, c.dy + 9)
        ..lineTo(c.dx + 13, c.dy + 8.2)
        ..lineTo(c.dx + 13.6, c.dy + 9.9)
        ..lineTo(c.dx + 6.4, c.dy + 10.8)
        ..close();
      canvas
        ..drawPath(f, face)
        ..drawPath(f, pen);
    } else {
      const n = 13, rx = 9.0, ry = 3.8;
      const heights = <double>[7, 9, 6, 8, 10, 7, 9, 6.5, 8, 7, 9.5, 8, 6];
      // its cross: the avenue off behind (north, going away, a little to
      // the right), and short rows east and west, drawn back to front
      for (var k = 5; k >= 1; k--) {
        final f = Offset(c.dx + k * 1.5, c.dy - ry - k * 1.5);
        final half = 3.2 - k * .25;
        stone(f + Offset(-half, 0), 5.5 - k * .45, 1.3);
        stone(f + Offset(half, 0), 5.5 - k * .45, 1.3);
      }
      for (var k = 1; k <= 3; k++) {
        stone(Offset(c.dx - rx - k * 3.6, c.dy - .3 * k), 5 - k * .5, 1.4);
        stone(Offset(c.dx + rx + k * 3.6, c.dy - .3 * k), 5 - k * .5, 1.4);
      }
      for (var i = 0; i < n; i++) {
        if (back(i, n)) stone(on(i, n, rx, ry), heights[i], 1.8);
      }
      stone(c + const Offset(0, -.5), 17, 3); // the great central stone
      for (var i = 0; i < n; i++) {
        if (!back(i, n)) stone(on(i, n, rx, ry), heights[i], 1.9);
      }
      // and the short row to the south, coming towards us
      for (var k = 1; k <= 2; k++) {
        stone(Offset(c.dx - k * 1.2, c.dy + ry + k * 2.6), 5.5 - k * .4, 1.6);
      }
    }
  }

  @override
  bool shouldRepaint(_SitePainter old) => old.name != name;
}
