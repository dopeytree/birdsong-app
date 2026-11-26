import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show HapticFeedback, LogicalKeyboardKey;
import 'package:plate_share/plate_share.dart';

import '../app_state.dart';
import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import '../settings.dart';
import '../store/detection_store.dart';
import '../ui/format.dart';
import '../ui/plate_buttons.dart';
import 'song_scribble.dart';
import '../ui/settings_button.dart';
import '../ui/station_editor.dart';
import 'bird_card.dart';
import 'collage_view.dart';
import 'day_picker.dart';
import 'index_view.dart';
import 'landmarks.dart';
import 'passed_view.dart';
import 'plate_library.dart';
import 'species_sort.dart';
import 'species_traits.dart';
import 'station_feed.dart';
import 'walk_map.dart';

/// The plate drawn by Flutter itself instead of the web page: a first
/// version, for Listen here. It has the heading, the collage, the Index of
/// species and a card for each bird, from the sessions on this device.
///
/// This is the web plate (assets/web/index.html) moved across, not a new
/// design: what the page does, this does, and where it does not yet, the
/// list below says so.
///
/// Plates still on their paper are treated one of three ways (Settings >
/// Experimental, PlateStyle): cut out on the device as the web plate does,
/// tinted (multiplied with the page's paper colour) or left as they come.
///
/// The collage (collage_view.dart) is the page's: its packing, its three
/// sizings (by a button), figures that fade in, grow under the pointer with
/// a label beside it, the mark on the latest heard, the glow on one being
/// heard, the page's paper behind, and a height that leaves the index on
/// the same screen. The index (index_view.dart) is the page's too, with the
/// app's fold and session arrows. A bird's card offers its other plates; the one picked
/// is kept.
///
/// The views a to g are the web plate's (Settings.plateMode, shared with
/// it), and the card is its card (bird_card.dart).
///
/// Pinch zoom is the app's (ZoomableCollage), and share and save take a
/// picture of the plate without the buttons, as on the web plate.
///
/// So are the caption, Limit species, and skulls, wings and eggs among a
/// bird's plates (Settings > Display).
///
/// The map button shows the walk on a map in the collage's place
/// (walk_map.dart), as the web plate's map mode.
///
/// Not moved across yet: the map's landmarks (Settings > Map, extras), and
/// remote stations (those still open the web plate).
class NativePlate extends StatefulWidget {
  const NativePlate({super.key, required this.app, required this.openSettings, this.onLoaded});

  final AppState app;
  final VoidCallback openSettings;
  final VoidCallback? onLoaded;

  @override
  State<NativePlate> createState() => _NativePlateState();
}

/// One line of the index: a species and how often it was heard.
class _Row {
  _Row(this.sci, this.common);

  final String sci;
  final String common;
  int count = 0;
  DateTime? last;
}

class _NativePlateState extends State<NativePlate> {
  PlateLibrary? _lib;
  SpeciesTraits? _traits;

  // the map's extras, shared by the map and "Passed on the way"
  final _landmarks = LandmarkLookup();

  // Each species' plate once found; null when there is none. A species not
  // in the map yet is still being looked for.
  final Map<String, PlateArt?> _art = {};
  final Set<String> _asking = {};

  // The style those plates were prepared in. A change of style (Settings >
  // Experimental) starts again; [_round] lets answers from before be told
  // apart and dropped.
  PlateStyle? _artStyle;
  bool _artParts = false;
  int _round = 0;

  // The collage on show, as "session|style", once every one of its plates
  // was ready: until then nothing is drawn, so the birds appear in their
  // places rather than arriving one by one and shuffling about.
  String? _revealed;

  // The height of everything but the collage (heading, index, padding),
  // measured after each frame, so the collage can take what is left of the
  // screen. Null until first measured.
  double? _others;
  final _allKey = GlobalKey(), _plateKey = GlobalKey(), _headKey = GlobalKey(), _indexKey = GlobalKey();

  // For the index alone (view c): the heading's and the index's heights.
  double _headH = 0, _indexH = 0;

  // The page stops scrolling while the collage is pinched or zoomed in: the
  // collage ("session|style") that asked. One left behind (a new session
  // while zoomed) asks nothing.
  String? _holdFor;
  static const _padTop = 16.0; // header{padding:1rem ... 0}

  // Room at the bottom for the share button, as the web plate makes for it
  // (--bs-ui-bottom), so the index rises clear of it.
  // Room at the bottom for the buttons there, so nothing sits under them:
  // one row (view and map at the left, calendar and share at the right), and
  // one more above it for the folded index's heading.
  // Set in each build.
  double _bottomRoom = 40 + 8 + 6;

  // How far the page fades out above the bottom buttons.
  static const double _fadeRoom = 20;

  // Below the top buttons (8 from the top, 48 tall), for a view without
  // the heading.
  static const double _buttonsTop = 8 + 48;
  final _shotKey = GlobalKey(), _shareKey = GlobalKey();

  /// The most species drawn on the plate; the rest are in the index only
  /// (the page's maxOnPlate).
  static const maxOnPlate = 200;

  PlateStyle get _style => PlateStyle.named(app.settings.nativePlateStyle);

  /// Which collage is on show: a new session, style, or offer of skulls,
  /// wings and eggs is a new one, prepared afresh before it is drawn.
  String _showingFor(Session? ses) {
    final f = _feed;
    final what = f == null
        ? '${ses?.id}'
        : 'station:${f.station.id}:${f.day != null ? ymd(f.day!) : f.span.name}:${f.light.name}';
    return '$what|${_style.name}|${app.settings.nativeParts ? 'parts' : ''}';
  }

  // ---- a remote station ---------------------------------------------------

  /// What the station on show heard (station_feed.dart), while a remote
  /// station is shown; null in Listen here.
  StationFeed? _feed;

  StationFeed? _syncFeed() {
    final s = app.settings;
    final st = s.mode == AppMode.station ? s.station : null;
    final f = _feed;
    if (st == null) {
      f?.dispose();
      return _feed = null;
    }
    if (f != null && f.station.id == st.id && f.station.input == st.input) return f;
    f?.dispose();
    // each day shown kept on the phone, as a session (station_archive.dart)
    // (the back days too, when allowed: a phone asks in the calendar)
    return _feed = StationFeed(st, root: app.store.root, keepPast: () => app.settings.keepPastOf(st) ?? false);
  }

  /// The four periods (Today, Week, Month, All), as the web plate's header
  /// has them: the one shown in madder italic; [short] on a phone, closer
  /// together in the corner under the buttons.
  Widget _spanRow(StationFeed f, {bool short = false}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in Span.values) ...[
            if (s != Span.values.first) SizedBox(width: short ? 12 : 25.6),
            Semantics(
              button: true,
              selected: f.day == null && f.span == s,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => f.setSpan(s),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: short ? 6 : 1.6),
                  child: Text(s.short,
                      style: TextStyle(
                        fontFamily: serif,
                        fontSize: short ? 15 : 16,
                        fontStyle: f.day == null && f.span == s ? FontStyle.italic : FontStyle.normal,
                        color: f.day == null && f.span == s ? madder : sepia,
                      )),
                ),
              ),
            ),
          ],
        ],
      );

  /// The sun and moon: a tap counts the station's day and night, the
  /// daytime alone (sunrise to sunset), or the night alone; in madder
  /// while one alone is shown.
  Widget _lightToggle(StationFeed f, Color lines, {bool end = false}) {
    final icon = switch (f.light) {
      Light.all => Icons.brightness_6_outlined,
      Light.day => Icons.wb_sunny_outlined,
      Light.night => Icons.nightlight_outlined,
    };
    return Semantics(
      button: true,
      label: 'Showing ${f.light.label.toLowerCase()}; tap for ${f.light.next.label.toLowerCase()}',
      excludeSemantics: true,
      child: Tooltip(
        message: f.light.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: f.nextLight,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Align(
              alignment: end ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
              child: Icon(icon, size: 20, color: f.light == Light.all ? lines : madder),
            ),
          ),
        ),
      ),
    );
  }

  /// The stations button, left of the pill on a remote station: modern
  /// translucent popover matching [SpeciesSortBar] to pick or add a station.
  Future<void> _stationsTap(BuildContext context) async {
    final s = app.settings;
    final current = s.mode == AppMode.station ? s.station?.id : null;
    final picked = await showModernMenu<String>(
      anchorContext: context,
      minWidth: 210,
      items: [
        for (final st in s.stations)
          ModernMenuItem(
            value: st.id,
            icon: Icons.sensors,
            label: st.name,
            subtitle: st.kind,
            selected: st.id == current,
          ),
        const ModernMenuItem(
          value: '+',
          icon: Icons.add,
          label: 'Add a station',
        ),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == '+') {
      if (context.mounted) await editStation(context, s);
      return;
    }
    s.update((x) {
      x.mode = AppMode.station;
      x.stationId = picked;
      x.plateMode = defaultPlateMode;
      x.nativeSizeBy = 'calls';
    });
  }

  /// Look for the plates of [rows] not asked for yet.
  void _ensure(List<_Row> rows) {
    final lib = _lib;
    if (lib == null) return;
    final style = _style, parts = app.settings.nativeParts;
    if (style != _artStyle || parts != _artParts) {
      _artStyle = style;
      _artParts = parts;
      lib.parts = parts;
      _round++;
      _art.clear();
      _asking.clear();
    }
    final round = _round;
    for (final r in rows) {
      if (_art.containsKey(r.sci) || !_asking.add(r.sci)) continue;
      lib.plateFor(r.sci, r.common, style).then((art) {
        if (!mounted || round != _round) return;
        _asking.remove(r.sci);
        setState(() => _art[r.sci] = art);
      });
    }
  }

  /// The view button: the next of the plate's views, a to g, as on the web
  /// plate (Settings.plateMode, shared by both). Stepping onto a, f or g
  /// also sets how the collage is sized, as the web plate does.
  void _nextMode() {
    final s = app.settings;
    final next = s.plateMode % plateModes.length + 1;
    final mode = plateModes[next - 1];
    if (_sortOpen || _zoomTier != 1.0) {
      setState(() {
        _sortOpen = false;
        _zoomTier = 1.0;
      });
    }
    s.update((x) {
      x.plateMode = next;
      if (mode.sizeBy != null) x.nativeSizeBy = mode.sizeBy!;
    });
  }

  AppState get app => widget.app;

  int _seenPlateChoicesRev = 0;

  @override
  void initState() {
    super.initState();
    _seenPlateChoicesRev = app.icloud.plateChoicesRevision;
    app.icloud.addListener(_onIcloudChanged);
    PlateLibrary.open(dataDir: app.dataDir).then((lib) {
      if (mounted) {
        setState(() => _lib = lib);
      } else {
        lib.close();
      }
    });
    SpeciesTraits.open().then((traits) {
      if (mounted) {
        setState(() => _traits = traits);
      } else {
        traits.dispose();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoaded?.call());
  }

  void _onIcloudChanged() {
    final rev = app.icloud.plateChoicesRevision;
    if (rev == _seenPlateChoicesRev) return;
    _seenPlateChoicesRev = rev;
    final lib = _lib;
    if (lib == null) return;
    lib.reloadChoices().then((changed) {
      if (!mounted || changed.isEmpty) return;
      setState(() {
        for (final sci in changed) {
          _art.remove(sci);
          _asking.remove(sci);
        }
      });
    });
  }

  @override
  void dispose() {
    app.icloud.removeListener(_onIcloudChanged);
    _landmarks.dispose();
    _noteTimer?.cancel();
    _feed?.dispose();
    _lib?.close();
    _traits?.dispose();
    super.dispose();
  }

  List<_Row> _rows(Session? ses) {
    final f = _feed;
    if (f != null) {
      return [
        for (final s in f.species ?? const <StationSpecies>[])
          if (!app.settings.isIgnoredSpecies(s.common, s.sci))
            _Row(s.sci, s.common)
              ..count = s.count
              ..last = s.last
      ];
    }
    if (ses == null) return [];
    final by = <String, _Row>{};
    for (final d in app.store.forPlate(app.settings.plateModel, session: ses)) {
      if (app.settings.isIgnoredSpecies(d.common, d.sci)) continue;
      final r = by[d.sci] ??= _Row(d.sci, d.common);
      r.count++;
      if (r.last == null || d.at.isAfter(r.last!)) r.last = d.at;
    }
    return by.values.toList()
      ..sort((a, b) => b.count != a.count ? b.count - a.count : a.common.compareTo(b.common));
  }

  // ---- notes at the top of the plate, as the web plate's ------------------
  String? _note;
  String? _noteAction;
  VoidCallback? _noteDo;
  bool _noteShown = false;
  Timer? _noteTimer;

  /// Tap the top-left heading to hide it; tap that corner again to reshow it.
  bool _headingHidden = false;

  /// Resolution multiplier for zoomed-in high-res decoding on No pecking order.
  double _zoomTier = 1.0;

  /// Whether the sort slide-out is open on No pecking order or Index of Species.
  bool _sortOpen = false;
  bool _indexSortOpen = false;

  /// Cached dominant plumage colour key per species (for Colour sort).
  final Map<String, double> _colourKey = {};
  final Set<String> _colourLoading = {};

  /// Cached circular mean activity hour per species for Remote stations
  /// (keyed by "<stationScope>|<sci>").
  final Map<String, double?> _remoteActiveHour = {};
  final Set<String> _remoteActiveLoading = {};
  AppMode? _lastAppMode;

  // Heartbeat trigger: increments whenever a new detection arrives (local or
  // remote) so [_HeartCounter] plays a 2-second red heartbeat animation.
  String? _heartScope;
  int _heartSeenCalls = -1;
  int _heartBeatToken = 0;

  void _checkHeartPulse(String scope, int totalCalls) {
    if (_heartScope != scope) {
      _heartScope = scope;
      _heartSeenCalls = totalCalls;
      return;
    }
    if (totalCalls > _heartSeenCalls) {
      _heartSeenCalls = totalCalls;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _heartBeatToken++);
      });
    } else {
      _heartSeenCalls = totalCalls;
    }
  }

  void _ensureRemoteActiveHours(StationFeed f, List<_Row> rows) {
    final scope = '${f.station.id}:${f.day != null ? ymd(f.day!) : f.span.name}:${f.light.name}';
    final todo = <StationSpecies>[];
    for (final r in rows) {
      final k = '$scope|${r.sci}';
      if (_remoteActiveHour.containsKey(k) || _remoteActiveLoading.contains(k)) continue;
      final sp = (f.species ?? const <StationSpecies>[]).where((x) => x.sci == r.sci).firstOrNull;
      if (sp != null) todo.add(sp);
    }
    if (todo.isEmpty) return;
    // Fetch up to 4 at a time so we don't flood the station API.
    for (final sp in todo.take(4)) {
      final k = '$scope|${sp.sci}';
      _remoteActiveLoading.add(k);
      f.hourly(sp).then((res) {
        _remoteActiveLoading.remove(k);
        final mean = res == null ? null : circularMeanHour(res.hours);
        _remoteActiveHour[k] = mean;
        if (mounted && app.settings.equalSort == 'active') setState(() {});
      }).catchError((Object e) {
        debugPrint('activeHour ${sp.sci}: $e');
        _remoteActiveLoading.remove(k);
        _remoteActiveHour[k] = null;
      });
    }
  }

  Map<String, double> _localActiveHours(Session? ses) {
    if (ses == null) return const {};
    final byHour = <String, List<int>>{};
    for (final d in app.store.forPlate(app.settings.plateModel, session: ses)) {
      if (app.settings.isIgnoredSpecies(d.common, d.sci)) continue;
      (byHour[d.sci] ??= List<int>.filled(24, 0))[d.at.hour]++;
    }
    final out = <String, double>{};
    for (final e in byHour.entries) {
      final m = circularMeanHour(e.value);
      if (m != null) out[e.key] = m;
    }
    return out;
  }

  void _selectSort(String key) {
    final opt = speciesSortOptions.firstWhere(
      (o) => o.key == key,
      orElse: () => speciesSortOptions.first,
    );
    app.settings.update((x) {
      x.equalSort = opt.key;
      x.equalSortAsc = opt.defaultAsc;
    });
  }

  void _flipSort() => app.settings.update((x) => x.equalSortAsc = !x.equalSortAsc);

  void _ensureColours(List<_Row> rows) {
    for (final r in rows) {
      if (_colourKey.containsKey(r.sci) || _colourLoading.contains(r.sci)) continue;
      final art = _art[r.sci];
      if (art == null) continue;
      _colourLoading.add(r.sci);
      unawaited(_computeColourKey(r.sci, art));
    }
  }

  Future<void> _computeColourKey(String sci, PlateArt art) async {
    try {
      final bytes = await art.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      codec.dispose();
      if (data == null) {
        _colourKey[sci] = 999;
        return;
      }
      final px = data.buffer.asUint8List();
      // Weighted hue histogram (36 bins) + average lightness for achromatic birds.
      final bins = List<double>.filled(36, 0);
      var chromaSum = 0.0, lumSum = 0.0, count = 0.0;
      for (var i = 0; i + 3 < px.length; i += 4) {
        final a = px[i + 3];
        if (a < 128) continue;
        final r = px[i] / 255.0, g = px[i + 1] / 255.0, b = px[i + 2] / 255.0;
        final hi = math.max(r, math.max(g, b));
        final lo = math.min(r, math.min(g, b));
        final d = hi - lo;
        final l = (hi + lo) / 2;
        // Skip near-paper background pixels
        if (l > 0.90 && d < 0.10) continue;
        lumSum += l;
        count += 1;
        if (d > 0.12) {
          double h;
          if (hi == r) {
            h = ((g - b) / d) % 6;
          } else if (hi == g) {
            h = (b - r) / d + 2;
          } else {
            h = (r - g) / d + 4;
          }
          h = (h * 60 + 360) % 360;
          final bin = (h / 10).floor().clamp(0, 35);
          bins[bin] += d;
          chromaSum += d;
        }
      }
      double key;
      if (count == 0) {
        key = 999;
      } else if (chromaSum / count < 0.07) {
        // Dark/grey/white birds grouped cleanly at the end by lightness
        key = 400 + (lumSum / count) * 100;
      } else {
        var best = 0;
        for (var i = 1; i < 36; i++) {
          if (bins[i] > bins[best]) best = i;
        }
        key = best * 10.0 + (lumSum / count);
      }
      _colourKey[sci] = key;
      if (mounted && app.settings.equalSort == 'colour') setState(() {});
    } catch (e) {
      debugPrint('colour $sci: $e');
      _colourKey[sci] = 999;
    } finally {
      _colourLoading.remove(sci);
    }
  }

  /// Sort [rows] using the shared sort setting (`equalSort` + `equalSortAsc`),
  /// used by both "No pecking order" and "Index of Species".
  List<_Row> _sortRows(List<_Row> rows, {Session? ses, StationFeed? feed}) {
    final sort = app.settings.equalSort;
    final asc = app.settings.equalSortAsc;
    final dir = asc ? 1 : -1;
    final out = [...rows];
    int cmpOptNum(double? a, double? b, String fallbackA, String fallbackB) {
      if (a == null && b == null) return fallbackA.toLowerCase().compareTo(fallbackB.toLowerCase());
      if (a == null) return 1; // unknowns always stay at the end
      if (b == null) return -1;
      final c = a.compareTo(b);
      return c != 0 ? c * dir : fallbackA.toLowerCase().compareTo(fallbackB.toLowerCase());
    }

    int cmpOptStr(String? a, String? b, String fallbackA, String fallbackB) {
      final aa = (a ?? '').trim().toLowerCase();
      final bb = (b ?? '').trim().toLowerCase();
      if (aa.isEmpty && bb.isEmpty) return fallbackA.toLowerCase().compareTo(fallbackB.toLowerCase());
      if (aa.isEmpty) return 1;
      if (bb.isEmpty) return -1;
      final c = aa.compareTo(bb);
      return c != 0 ? c * dir : fallbackA.toLowerCase().compareTo(fallbackB.toLowerCase());
    }

    switch (sort) {
      case 'recent':
        out.sort((a, b) {
          final c = (a.last ?? DateTime(0)).compareTo(b.last ?? DateTime(0));
          return c != 0 ? c * dir : a.common.toLowerCase().compareTo(b.common.toLowerCase());
        });
      case 'active':
        if (feed != null) {
          _ensureRemoteActiveHours(feed, rows);
          final scope = '${feed.station.id}:${feed.day != null ? ymd(feed.day!) : feed.span.name}:${feed.light.name}';
          double? hourOf(_Row r) {
            final k = '$scope|${r.sci}';
            if (_remoteActiveHour.containsKey(k)) return _remoteActiveHour[k];
            final t = r.last;
            return t == null ? null : t.hour + t.minute / 60.0;
          }
          out.sort((a, b) => cmpOptNum(hourOf(a), hourOf(b), a.common, b.common));
        } else {
          final map = _localActiveHours(ses);
          out.sort((a, b) => cmpOptNum(map[a.sci], map[b.sci], a.common, b.common));
        }
      case 'name':
        out.sort((a, b) => a.common.toLowerCase().compareTo(b.common.toLowerCase()) * dir);
      case 'family':
        _traits?.wantGbif(rows.map((r) => r.sci));
        out.sort((a, b) {
          final ka = _traits?.of(a.sci)?.taxonomicKey(a.sci) ?? 'zzz|zzz|${a.sci.toLowerCase()}';
          final kb = _traits?.of(b.sci)?.taxonomicKey(b.sci) ?? 'zzz|zzz|${b.sci.toLowerCase()}';
          return ka.compareTo(kb) * dir;
        });
      case 'rare':
        _traits?.wantRarity(rows.map((r) => r.sci));
        out.sort((a, b) => cmpOptNum(
            _traits?.of(a.sci)?.rarityScore, _traits?.of(b.sci)?.rarityScore, a.common, b.common));
      case 'weight':
        _traits?.wantWikidata(rows.map((r) => r.sci));
        out.sort((a, b) => cmpOptNum(
            _traits?.of(a.sci)?.massGrams, _traits?.of(b.sci)?.massGrams, a.common, b.common));
      case 'wingspan':
        _traits?.wantWikidata(rows.map((r) => r.sci));
        out.sort((a, b) => cmpOptNum(
            _traits?.of(a.sci)?.wingspanCm, _traits?.of(b.sci)?.wingspanCm, a.common, b.common));
      case 'region':
        _traits?.wantWikidata(rows.map((r) => r.sci));
        out.sort((a, b) => cmpOptStr(
            _traits?.of(a.sci)?.region, _traits?.of(b.sci)?.region, a.common, b.common));
      case 'artist':
        out.sort((a, b) => cmpOptStr(
            artistOfPlate(_art[a.sci]), artistOfPlate(_art[b.sci]), a.common, b.common));
      case 'colour':
        _ensureColours(rows);
        out.sort((a, b) {
          final ka = _colourKey[a.sci];
          final kb = _colourKey[b.sci];
          return cmpOptNum(ka == 999 ? null : ka, kb == 999 ? null : kb, a.common, b.common);
        });
      default: // 'calls'
        out.sort((a, b) {
          final c = a.count.compareTo(b.count);
          return c != 0 ? c * dir : a.common.toLowerCase().compareTo(b.common.toLowerCase());
        });
    }
    return out;
  }

  void _say(String text, {String? action, VoidCallback? onAction, int seconds = 3}) {
    if (!mounted) return;
    _noteTimer?.cancel();
    setState(() {
      _note = text;
      _noteAction = action;
      _noteDo = onAction;
      _noteShown = true;
    });
    _noteTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _noteShown = false);
    });
  }

  // ---- the walk on a map, in place of the collage --------------------------

  void _goHome() {
    if (_sortOpen || _zoomTier != 1.0) {
      setState(() {
        _sortOpen = false;
        _zoomTier = 1.0;
      });
    }
    app.settings.update((x) {
      x.plateMode = defaultPlateMode;
      x.nativeSizeBy = x.mode == AppMode.station ? 'calls' : 'time';
    });
  }

  /// Jumps straight to the local session with the highest distinct species count.
  void _openBestSession() {
    final model = app.settings.plateModel;
    Session? best;
    var bestCount = 0;
    for (final ses in app.store.sessions) {
      final count = {
        for (final d in app.store.forPlate(model, session: ses))
          if (!app.settings.isIgnoredSpecies(d.common, d.sci)) d.sci
      }.length;
      if (count > bestCount || (count == bestCount && count > 0 && best != null && ses.start.isAfter(best.start))) {
        best = ses;
        bestCount = count;
      }
    }
    if (best != null) app.store.select(best);
    if (_sortOpen || _zoomTier != 1.0) {
      setState(() {
        _sortOpen = false;
        _zoomTier = 1.0;
      });
    }
    app.settings.update((x) {
      x.mode = AppMode.listen;
      x.plateMode = defaultPlateMode;
      x.nativeSizeBy = 'time';
    });
  }

  /// The map step of the view cycle (and Quick Launch -> Map): opens the walk
  /// or station in full-screen map mode, zoomed close to the trail. Closing
  /// returns to View 1.
  Future<void> _openMap(StationFeed? feed, List<_Row> rows) async {
    final store = app.store;
    if (feed == null && store.selected == null) {
      _goHome();
      return;
    }
    if (app.settings.showMap) app.settings.update((x) => x.showMap = false);
    await _mapFullScreen(
      () => feed != null
          ? Walk.station(feed.station.name, feed.place)
          : (store.selected == null
              ? null
              : Walk.of(store, store.selected!, app.settings.plateModel,
                  ignore: app.settings.isIgnoredSpecies)),
      rows,
    );
    if (mounted) _goHome();
  }

  /// The calendar button (day_picker.dart): a month with the days that
  /// have a session, and that day's sessions listed under it to pick from;
  /// OK shows the day's first, and the ‹ › step through the rest.
  Future<void> _pickDay() async {
    final f = _feed;
    if (f != null) {
      // a station: any day since its records began
      final st = f.station;
      final picked = await StationDayPicker.show(
        context,
        StationDayPicker(
          feed: f,
          keepPast: app.settings.keepPastOf(st),
          onKeepPast: (v) {
            app.settings.update((x) => x.stationKeepPast[st.id] = v);
            if (v) f.archive?.fill();
          },
        ),
      );
      if (picked != null && mounted) f.setDay(picked);
      return;
    }
    final store = app.store;
    final model = app.settings.plateModel;
    final picked = await DayPicker.show(
      context,
      DayPicker(
        store: store,
        shown: store.selected,
        speciesIn: (x) => {
          for (final d in store.forPlate(model, session: x))
            if (!app.settings.isIgnoredSpecies(d.common, d.sci)) d.sci
        }.length,
      ),
    );
    if (picked == null || !mounted) return;
    store.select(picked);
  }

  /// A cross on the map: the bird's card, from this session's row when it
  /// has one, else from what the walk heard (a bird from another part of
  /// the same walk), as the web map's openBird.
  /// The map on a page of its own, the whole screen (for small screens):
  /// the same walk (kept up to date while listening), extras and search;
  /// its button or Escape closes it, and a bird's cross opens the bird's
  /// card over it. "Passed on the way" sits on the map at the bottom and
  /// opens the list (Ed, 23 Nov).
  Future<void> _mapFullScreen(Walk? Function() walk, List<_Row> rows) {
    final mapShotKey = GlobalKey();
    final mapShareKey = GlobalKey();
    Future<Uint8List?> mapPicture() async {
      final box = mapShotKey.currentContext?.findRenderObject();
      if (box is! RenderRepaintBoundary) return null;
      final image = await box.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        return png?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }

    Future<void> shareMap() async {
      final box = mapShareKey.currentContext?.findRenderObject() as RenderBox?;
      final from = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      var ok = false;
      try {
        final png = await mapPicture();
        if (png != null) ok = await PlateShare.share(text: 'Walk with birdsongs.ai', from: from, png: png);
      } catch (e) {
        debugPrint('map share: $e');
      }
      if (!ok && mounted) _say("Couldn't take a picture of the map.");
    }

    Future<void> saveMap() async {
      var r = 'failed';
      try {
        final png = await mapPicture();
        if (png != null) r = await PlateShare.saveToPhotos(png: png);
      } catch (e) {
        debugPrint('map save: $e');
      }
      if (!mounted) return;
      _say(switch (r) {
        'saved' => 'Saved to Photos.',
        'denied' => 'birdsongs.ai may not add to Photos: allow it in Settings.',
        _ => "Couldn't save the map.",
      });
    }

    return Navigator.of(context).push(PageRouteBuilder<void>(
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      pageBuilder: (context, _, __) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: paper,
            body: ListenableBuilder(
              listenable: Listenable.merge([app.store, app.settings, _landmarks]),
              builder: (context, _) {
                final passed =
                    app.settings.mapExtras ? (_landmarks.walk?.passed ?? const <Passed>[]) : const <Passed>[];
                final btnStyle = app.settings.mapButtonStyle;
                final isMadder = btnStyle == 'madder';
                final isInk = btnStyle == 'ink';
                final btnBg = isMadder
                    ? madder
                    : isInk
                        ? paper.withValues(alpha: 0.85)
                        : paper.withValues(alpha: 0.94);
                final btnFg = isMadder ? paper : (isInk ? ink : madder);
                final btnShape = isMadder
                    ? const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4)))
                    : const CircleBorder(side: BorderSide(color: rule));
                return Stack(children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      key: mapShotKey,
                      child: LayoutBuilder(
                        builder: (context, box) => WalkMap(
                          walk: walk(),
                          allBirds: app.settings.mapBirds == 'all',
                          size: box.biggest,
                          // the card opens over the full-screen map; closing it
                          // leaves the map full screen
                          onBird: (sci, common) => _openFromMap(sci, common, rows),
                          onHold: (_) {},
                          landmarks: app.settings.mapExtras ? _landmarks : null,
                          settings: app.settings,
                          species: [for (final r in rows) (sci: r.sci, common: r.common)],
                          fullScreen: true,
                          onPoi: passed.isNotEmpty
                              ? () => showPassed(context, _landmarks, about: app.settings.mapPassedAbout)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  () {
                    final pad = MediaQuery.paddingOf(context);
                    final topEdge = pad.top > 24 ? math.max(16.0, pad.top - 14.0) : 10.0;
                    final bottomEdge = pad.bottom > 0 ? 18.0 : 12.0;
                    final leftEdge = pad.left > 16 ? math.max(14.0, pad.left - 10.0) : 12.0;
                    final rightEdge = pad.right > 16 ? math.max(14.0, pad.right - 10.0) : 12.0;
                    return Positioned.fill(
                      child: Stack(
                        children: [
                          // Top-right menu button on the map (always visible in all views).
                          Positioned(
                            right: rightEdge,
                            top: topEdge,
                            child: SettingsButton(
                              app: app,
                              color: ink,
                              onGoHome: () => Navigator.of(context).maybePop(),
                              onOpenMap: () {},
                              onOpenCalendar: _pickDay,
                              onOpenBestSession: () {
                                _openBestSession();
                                Navigator.of(context).maybePop();
                              },
                            ),
                          ),
                          // Bottom-left icon on the map: closes the map and returns
                          // to View 1 (Most recent on Local / Most heard on Remote).
                          Positioned(
                            left: leftEdge,
                            bottom: bottomEdge,
                            child: () {
                              final isRemote = app.settings.mode == AppMode.station;
                              final backIcon =
                                  isRemote ? Icons.view_quilt_outlined : Icons.auto_awesome_mosaic_outlined;
                              final backTip = isRemote ? 'Most heard' : 'Recent ramblings';
                              return isInk
                                  ? IconButton(
                                      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                                      padding: EdgeInsets.zero,
                                      iconSize: 22,
                                      tooltip: backTip,
                                      icon: Icon(backIcon, color: ink),
                                      onPressed: () => Navigator.of(context).maybePop(),
                                    )
                                  : Material(
                                      color: btnBg,
                                      elevation: 2,
                                      shadowColor: const Color(0x4D3C280A),
                                      shape: btnShape,
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () => Navigator.of(context).maybePop(),
                                        child: SizedBox(
                                          width: 38,
                                          height: 38,
                                          child: Center(
                                            child: Icon(backIcon, size: 21, color: btnFg),
                                          ),
                                        ),
                                      ),
                                    );
                            }(),
                          ),
                          // Bottom-right share button on the map (modern style matching filter menu).
                          if (PlateShare.supported)
                            Positioned(
                              right: rightEdge,
                              bottom: bottomEdge,
                              child: _shareMenu(
                                key: mapShareKey,
                                tooltip: 'Share or save the map',
                                onShare: shareMap,
                                onSave: saveMap,
                              ),
                            ),
                        ],
                      ),
                    );
                  }(),
                ]);
              },
            ),
          ),
        ),
      ),
    ));
  }

  void _openFromMap(String sci, String common, List<_Row> rows) {
    for (final r in rows) {
      if (r.sci == sci) return _openCard(r);
    }
    final store = app.store, ses = store.selected;
    if (ses == null) return;
    final model = app.settings.plateModel;
    final walk = [
      for (final x in store.walkOf(ses))
        for (final d in store.forPlate(model, session: x))
          if (!app.settings.isIgnoredSpecies(d.common, d.sci)) d
    ];
    final r = _Row(sci, common);
    for (final d in walk) {
      if (d.sci != sci) continue;
      r.count++;
      if (r.last == null || d.at.isAfter(r.last!)) r.last = d.at;
    }
    _openCard(r, heard: walk);
  }

  // ---- share or save the plate, as the web plate does -------------------

  /// A picture of the plate as it is on screen, without the buttons.
  Future<Uint8List?> _picture() async {
    final box = _shotKey.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return null;
    final image = await box.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _share() async {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    final from = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    var ok = false;
    try {
      final png = await _picture();
      if (png != null) ok = await PlateShare.share(text: 'Heard with birdsongs.ai', from: from, png: png);
    } catch (_) {}
    if (!ok && mounted) _say("Couldn't take a picture of the plate.");
  }

  Future<void> _save() async {
    var r = 'failed';
    try {
      final png = await _picture();
      if (png != null) r = await PlateShare.saveToPhotos(png: png);
    } catch (_) {}
    if (!mounted) return;
    _say(switch (r) {
      'saved' => 'Saved to Photos.',
      'denied' => 'birdsongs.ai may not add to Photos: allow it in Settings.',
      _ => "Couldn't save the plate.",
    });
  }

  // The record button: a tap starts a new session, a tap while recording
  // stops it.
  Future<void> _record() async {
    final engine = app.engine;
    if (engine.starting) return;
    if (engine.running) {
      await engine.stop();
      return;
    }
    HapticFeedback.mediumImpact();
    await engine.start();
    if (!mounted || engine.error == null) return;
    final noModel = engine.error!.contains('Models');
    _say(engine.error!,
        action: noModel ? 'Models' : null,
        onAction: noModel ? widget.openSettings : null,
        seconds: 6);
  }

  // The pill's sensors half: show the remote station last shown, always
  // landing on the default view (Most heard). With none saved yet, ask for one.
  void _toRemote() {
    final s = app.settings;
    if (s.stations.isEmpty) {
      editStation(context, s);
      return;
    }
    s.update((x) {
      x.mode = AppMode.station;
      x.stationId = x.station!.id;
      x.plateMode = defaultPlateMode;
      x.nativeSizeBy = 'calls';
    });
  }

  /// The bird's card (bird_card.dart), as the web plate's: what is on the
  /// plate (the session's) for the facts and recordings, and everything on
  /// this device for how long the bird has been known here.
  void _openCard(_Row r, {List<Detection>? heard}) {
    final lib = _lib;
    if (lib == null) return;
    final f = _feed;
    if (f != null) {
      final s = (f.species ?? const <StationSpecies>[]).where((x) => x.sci == r.sci).firstOrNull;
      if (s == null) return;
      BirdCard.show(
        context,
        BirdCard(
          lib: lib,
          style: _style,
          source: _StationCard(f, s),
          art: _art[r.sci],
          traits: _traits,
          onChosen: (art) {
            if (mounted) setState(() => _art[r.sci] = art);
          },
        ),
      );
      return;
    }
    final store = app.store, model = app.settings.plateModel;
    heard ??= [
      for (final d in store.forPlate(model, session: store.selected))
        if (!app.settings.isIgnoredSpecies(d.common, d.sci)) d
    ];
    final allModel = [
      for (final d in store.forPlate(model))
        if (!app.settings.isIgnoredSpecies(d.common, d.sci)) d
    ];
    BirdCard.show(
      context,
      BirdCard(
        lib: lib,
        style: _style,
        source: LocalCard(
          BirdFacts.of(r.sci, r.common, heard, allModel),
          clipOf: (d) => d.hasClip ? store.clipFile(d.id) : null,
          spectrogramOf: (d) => d.hasClip ? store.spectrogramFile(d.id) : null,
        ),
        art: _art[r.sci],
        traits: _traits,
        onChosen: (art) {
          if (mounted) setState(() => _art[r.sci] = art);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = _syncFeed();
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.settings,
        app.store,
        app.engine,
        if (feed != null) feed,
        if (_traits != null) _traits!,
      ]),
      builder: (context, _) {
        final store = app.store, engine = app.engine;
        // Whenever Local / Remote mode swaps from anywhere (pill, station list,
        // Settings), guarantee we land on View 1 (Most recent / Most heard).
        final curMode = app.settings.mode;
        if (_lastAppMode != null && _lastAppMode != curMode && app.settings.plateMode != defaultPlateMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            app.settings.update((x) {
              x.plateMode = defaultPlateMode;
              x.nativeSizeBy = x.mode == AppMode.station ? 'calls' : 'time';
            });
          });
        }
        _lastAppMode = curMode;
        // a remote station has no sessions
        final ses = feed == null ? store.selected : null;
        final mode = plateModes[(app.settings.plateMode - 1).clamp(0, plateModes.length - 1)];
        final spotlight = mode.key == 'spotlight';
        final equal = mode.key == 'equal';
        // Limit species: the most heard only, on the plate and in the index.
        // Default view loads up to maxOnPlate (200); No pecking order loads all.
        final all = _rows(ses), limit = app.settings.nativeLimit;
        final rows = limit > 0 && all.length > limit ? all.sublist(0, limit) : all;
        final onPlate = equal ? rows : rows.take(maxOnPlate).toList();
        _ensure(onPlate);
        // the creature heard last (the page's newestSci)
        String? newest;
        String? newestCommon;
        DateTime? latest;
        for (final r in all) {
          if (r.last != null && (latest == null || r.last!.isAfter(latest))) {
            latest = r.last;
            newest = r.sci;
            newestCommon = r.common;
          }
        }
        final marked = app.settings.nativeMarkAt == 'none' ? null : newest;
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        final calls = all.fold<int>(0, (n, r) => n + r.count);
        _checkHeartPulse(_showingFor(ses), calls);
        final i = store.selectedIndex, n = store.sessions.length;
        final showIndex = !equal;
        final showHeading = !equal;
        final showTopRight = !spotlight && !equal;
        // Smart edge-to-edge corner insets: gives bottom/side controls clean
        // breathing room from curved phone bezels while still using the full
        // screen canvas without double SafeArea padding.
        final mediaPad = MediaQuery.paddingOf(context);
        final cornerTop = mediaPad.top > 24 ? 18.0 : 10.0;
        final rowTop = mediaPad.top > 24 ? math.max(16.0, mediaPad.top - 14.0) : 10.0;
        final cornerBottom = mediaPad.bottom > 0 ? 18.0 : 12.0;
        final cornerLeft = mediaPad.left > 16 ? math.max(14.0, mediaPad.left - 10.0) : 12.0;
        final cornerRight = mediaPad.right > 16 ? math.max(14.0, mediaPad.right - 10.0) : 12.0;
        final topInset = showTopRight ? rowTop : cornerTop;
        final fit = app.settings.nativeFit;
        // Reserve accurate room at the bottom for the bottom icon row (+ folded
        // Index of Species heading above it) so everything fits on one screen.
        final foldedInline = showIndex && !spotlight && app.settings.nativeIndexFolded;
        _bottomRoom = equal
            ? 0.0
            : (foldedInline ? (42.0 + 10.0 + 44.0 + 6.0) : (44.0 + 8.0));
        final platePad = equal
            ? EdgeInsets.zero
            : EdgeInsets.fromLTRB(
                mediaPad.left > 16 ? math.max(10.0, mediaPad.left - 12.0) : 0.0,
                rowTop,
                mediaPad.right > 16 ? math.max(10.0, mediaPad.right - 12.0) : 0.0,
                cornerBottom,
              );
        final sortedIndex = _sortRows(rows, ses: ses, feed: feed);
        IndexView index(double width, double screen, {bool inline = false}) => IndexView(
              entries: [
                for (final r in sortedIndex)
                  IndexEntry(r.sci, r.common, r.count, noPlate: _art.containsKey(r.sci) && _art[r.sci] == null),
              ],
              width: width,
              fit: fit,
              narrow: screen <= 720,
              folded: app.settings.nativeIndexFolded,
              onFold: () => app.settings.update((x) => x.nativeIndexFolded = !x.nativeIndexFolded),
              foldable: true,
              inline: inline,
              species: all.length,
              newest: marked,
              // on a station the ‹ › step a day at a time
              steps: feed != null || n > 1,
              canPrev: feed?.canStepBack ?? i > 0,
              canNext: feed?.canStepOn ?? (i >= 0 && i < n - 1),
              onStep: feed?.stepDay ?? store.step,
              onOpen: (e) => _openCard(rows.firstWhere((r) => r.sci == e.sci)),
              sortBar: inline
                  ? null
                  : SpeciesSortBar(
                      open: _indexSortOpen,
                      sortKey: app.settings.equalSort,
                      ascending: app.settings.equalSortAsc,
                      showLabels: app.settings.nativeAllNameTickets,
                      onToggleLabels: () =>
                          app.settings.update((x) => x.nativeAllNameTickets = !x.nativeAllNameTickets),
                      centered: true,
                      onToggleOpen: () => setState(() => _indexSortOpen = !_indexSortOpen),
                      onSelect: _selectSort,
                      onFlipDirection: _flipSort,
                    ),
            );
        return Stack(
          children: [
            // The plate itself, without the buttons over it: what share takes.
            RepaintBoundary(
              key: _shotKey,
              child: PaperBackground(
                child: Padding(
                  padding: platePad,
                  child: spotlight
                      ? _spotlight(rows, newest)
                      // The heading stays put beside the buttons at the top; the
                      // rest scrolls between it and the buttons along the bottom,
                      // never under either, fading out at both edges.
                      : LayoutBuilder(builder: (context, outer) {
                          final headSide = (outer.maxWidth * .03).clamp(12.0, 48.0);
                          final headTop = outer.maxWidth <= 720 ? 8.0 : _padTop;
                          return Padding(
                            padding: EdgeInsets.only(bottom: _bottomRoom),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // the index alone and the collage alone go without
                                // the heading: just room below the top buttons
                                if (showHeading)
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(headSide, headTop, headSide, 0),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => setState(() => _headingHidden = !_headingHidden),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(minWidth: 160, minHeight: 56),
                                        child: AnimatedOpacity(
                                          opacity: _headingHidden ? 0.0 : 1.0,
                                          duration: const Duration(milliseconds: 220),
                                          child: IgnorePointer(
                                            ignoring: _headingHidden,
                                            child: _heading(ses, i, n, all.length, calls, outer.maxWidth - headSide,
                                                totals: mode.key != 'index', feed: feed),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                else if (!equal)
                                  const SizedBox(height: _buttonsTop),
                                Expanded(
                                  child: ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (r) {
                              final f = r.height <= 2 * _fadeRoom ? .5 : _fadeRoom / r.height;
                              return LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: const [
                                  Color(0x00000000),
                                  Color(0xFF000000),
                                  Color(0xFF000000),
                                  Color(0x00000000)
                                ],
                                stops: [0, f, 1 - f, 1],
                              ).createShader(r);
                            },
                            child: LayoutBuilder(builder: (context, box) {
                  final side = (box.maxWidth * (fit ? .03 : .04)).clamp(16.0, fit ? 32.0 : 48.0);
                  final plateSide = (box.maxWidth * .02).clamp(8.0, 32.0);
                  return SingleChildScrollView(
                    physics: _holdFor != null && (_holdFor == _showingFor(ses) || _holdFor == 'map')
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    // room at both ends so the first and last lines sit clear of the fades
                    padding: EdgeInsets.symmetric(vertical: equal ? 0 : _fadeRoom),
                    child: Column(
                      key: _allKey,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (rows.isEmpty)
                          Padding(
                            key: _plateKey,
                            padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                            child: Center(
                              child: Text(
                                feed != null
                                    ? (feed.error ??
                                        (feed.loading || feed.species == null
                                            ? 'Asking the station…'
                                            : 'Nothing heard ${switch (feed.light) {
                                                Light.all => '',
                                                Light.day => 'in the daytime ',
                                                Light.night => 'at night ',
                                              }}${feed.day != null ? 'that day' : 'in this period'}.'))
                                    : engine.running
                                        ? 'Listening. Birds appear here as they are heard.'
                                        : 'Nothing heard yet. Press record to listen.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontFamily: serif,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 18,
                                    color: sepia),
                              ),
                            ),
                          )
                        else
                          // Full-canvas plate (defunct side < > arrows removed).
                          Padding(
                            key: _plateKey,
                            padding: equal
                                ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
                                : EdgeInsets.fromLTRB(plateSide, 3.2, plateSide, 8.8),
                            child: _collage(
                              ses,
                              onPlate,
                              newest,
                              equal ? math.max(100.0, box.maxWidth - 16) : box.maxWidth - 2 * plateSide,
                              equal
                                  ? math.max(140.0, box.maxHeight - 16)
                                  : _plateHeight(box.maxWidth, box.maxHeight) - 12,
                              sizeBy: equal
                                  ? 'equal'
                                  : (feed != null ? 'calls' : 'time'),
                            ),
                          ),
                        // The page's caption, under the plate; not when it is
                        // fitted on one screen (body.fit #caption) or on No pecking order.
                        if (!fit && !equal)
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 704),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 9.6, 16, 0),
                                child: Text(
                                  'Each bird is drawn in proportion to how often it was heard. '
                                  'Select one to see its plate and its hours.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontFamily: serif,
                                      fontStyle: FontStyle.italic,
                                      fontSize: (box.maxWidth <= 720 ? 16 : 18) * .98 * 16 / 18,
                                      height: 1.5,
                                      color: sepia),
                                ),
                              ),
                            ),
                          ),
                        // section{padding:2.2rem clamp(1rem,4vw,3rem) 2.5rem;max-width:78rem},
                        // closer when fitted on one screen
                        if (showIndex && !foldedInline)
                        Center(
                          key: _indexKey,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: fit ? double.infinity : 1248),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(side, fit ? 8 : 35.2, side, fit ? 12.8 : 40),
                              child: index(math.min(box.maxWidth, fit ? double.infinity : 1248) - 2 * side, box.maxWidth),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                ),
              ),
            ),
            Positioned.fill(
              child: Stack(
                children: [
                // Top-left modern transparent black-icon sort bar on No pecking order.
                if (equal)
                  Positioned(
                    left: cornerLeft,
                    top: cornerTop,
                    right: cornerRight + 52,
                    child: SpeciesSortBar(
                      open: _sortOpen,
                      sortKey: app.settings.equalSort,
                      ascending: app.settings.equalSortAsc,
                      showLabels: app.settings.nativeAllNameTickets,
                      onToggleLabels: () =>
                          app.settings.update((x) => x.nativeAllNameTickets = !x.nativeAllNameTickets),
                      onToggleOpen: () => setState(() => _sortOpen = !_sortOpen),
                      onSelect: (key) {
                        _selectSort(key);
                        setState(() => _sortOpen = false);
                      },
                      onFlipDirection: _flipSort,
                    ),
                  ),
                // Top-right controls: Menu icon anchored cleanly in the top-right
                // corner across every view, with Record/Stations + SourcePill tucked
                // right underneath it on the home view so the title fits freely.
                Positioned(
                  right: cornerRight,
                  top: topInset,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SettingsButton(
                        app: app,
                        color: ink,
                        onGoHome: _goHome,
                        onOpenMap: () => _openMap(feed, rows),
                        onOpenCalendar: _pickDay,
                        onOpenBestSession: _openBestSession,
                      ),
                      if (showTopRight) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // record in Listen here, or while a session records
                            if (feed == null || engine.running || engine.starting)
                              RecordButton(recording: engine.running, busy: engine.starting, onTap: _record),
                            // on a station: the list of stations, to choose or add one
                            if (feed != null)
                              Builder(
                                builder: (bc) => IconButton(
                                  tooltip: 'Stations',
                                  constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.cell_tower, size: 20, color: ink),
                                  color: ink,
                                  onPressed: () => _stationsTap(bc),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: SourcePill(
                                listen: feed == null,
                                stationName: app.settings.station?.name,
                                onListen: () => app.settings.update((x) {
                                  x.mode = AppMode.listen;
                                  x.plateMode = defaultPlateMode;
                                  x.nativeSizeBy = 'time';
                                }),
                                onRemote: _toRemote,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // A station's four periods, centred at the top on a wide
                // screen, as the web plate's header has them.
                if (feed != null && showTopRight && MediaQuery.sizeOf(context).width >= 900)
                  Positioned(
                    top: rowTop,
                    left: 0,
                    right: 0,
                    height: SourcePill.rowHeight,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _spanRow(feed),
                          if (feed.canLight) ...[
                            const SizedBox(width: 25.6),
                            _lightToggle(feed, app.settings.nativeHeadingInk ? ink : sepia),
                          ],
                        ],
                      ),
                    ),
                  ),
                // On a phone, the four in short words at the right, neatly under
                // the stacked menu + pill, aligned to the right edge.
                if (feed != null && showTopRight && MediaQuery.sizeOf(context).width < 900)
                  Positioned(
                    top: rowTop + SourcePill.rowHeight + 40,
                    right: cornerRight + 6,
                    child: _spanRow(feed, short: true),
                  ),
                // and the sun and moon under All, ending with it
                if (feed != null && feed.canLight && showTopRight && MediaQuery.sizeOf(context).width < 900)
                  Positioned(
                    top: rowTop + SourcePill.rowHeight + 74,
                    right: cornerRight + 6,
                    child: _lightToggle(feed, app.settings.nativeHeadingInk ? ink : sepia, end: true),
                  ),
                // Single bottom-left view cycle button (order: 1 -> 3 -> 4 -> 2 -> 1):
                // 1. Default (Most recent / Most heard) -> interests -> 3. Latest & most heard
                // 3. Latest & most heard                -> grid      -> 4. No pecking order
                // 4. No pecking order                   -> map       -> 2. Map
                // 2. Map                                -> mosaic/quilt -> 1. Default
                Positioned(
                  left: cornerLeft,
                  bottom: cornerBottom,
                  child: IconButton(
                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    padding: EdgeInsets.zero,
                    iconSize: 22,
                    tooltip: switch (mode.key) {
                      'time' => 'Latest & most heard',
                      'spotlight' => 'No pecking order',
                      _ => 'The walk on a map',
                    },
                    icon: switch (mode.key) {
                      'time' => const Icon(Icons.interests_outlined, color: ink),
                      'spotlight' => const Icon(Icons.grid_view_outlined, color: ink),
                      _ => const Icon(Icons.map_outlined, color: ink),
                    },
                    color: ink,
                    onPressed: equal ? () => _openMap(feed, rows) : _nextMode,
                  ),
                ),
                // The folded index's heading, on a row of its own just above
                // the buttons along the bottom.
                if (foldedInline)
                  Positioned(
                    left: cornerLeft,
                    right: cornerRight,
                    bottom: cornerBottom + 44 + 10,
                    height: 42,
                    child: index(
                        MediaQuery.sizeOf(context).width - cornerLeft - cornerRight, MediaQuery.sizeOf(context).width,
                        inline: true),
                  ),
                // The song scribble between the buttons along the bottom: live
                // mic when listening here, or the matching resting line with
                // the latest heard species when on a remote station. Hidden on
                // No pecking order for a clean museum plate.
                if (app.settings.songScribble && !equal)
                  Positioned(
                    left: cornerLeft + 40 + 8,
                    right: (PlateShare.supported ? cornerRight + 40 : cornerRight) + 8,
                    bottom: cornerBottom,
                    height: 40,
                    child: SongScribble(
                      engine: engine,
                      simpleWave: app.settings.songScribbleMode == 'wave',
                      remote: feed != null,
                      remoteName: feed != null ? newestCommon : null,
                    ),
                  ),
                // Share or save, out of the way at the bottom right (modern translucent menu).
                if (PlateShare.supported)
                  Positioned(
                    right: cornerRight,
                    bottom: cornerBottom,
                    child: _shareMenu(
                      key: _shareKey,
                      tooltip: 'Share or save the plate',
                      onShare: _share,
                      onSave: _save,
                    ),
                  ),
                if (_note != null)
                  Positioned(
                    left: cornerLeft,
                    right: cornerRight,
                    top: rowTop,
                    child: IgnorePointer(
                      ignoring: !_noteShown,
                      child: AnimatedOpacity(
                        opacity: _noteShown ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: PlateNote(
                          text: _note!,
                          action: _noteAction,
                          onAction: _noteDo == null
                              ? null
                              : () {
                                  setState(() => _noteShown = false);
                                  _noteDo!();
                                },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ],
        );
      },
    );
  }

  /// The page's header as the app fills it in Listen here: the title with
  /// the session's number, then, each on its own line, when, where (just
  /// the position), the weather (its picture and the temperature), and,
  /// when switched on (Settings > Display, nativeTotals), the totals. Every line stops short of the buttons beside it
  /// (record, pill, menu). [width] is the room from the
  /// left padding to the screen's right edge.
  Widget _heading(Session? ses, int i, int n, int species, int calls, double width,
      {bool totals = true, StationFeed? feed}) {
    // #sub{font-style:italic;color:sepia;font-size:.95rem}, three block spans;
    // or, when chosen (Settings > Display, nativeTitleCaps), the whole
    // heading in small capitals as Index of Species is set
    final capsOn = app.settings.nativeTitleCaps;
    // the lines under the title in the title's ink, or in sepia when chosen
    // (Settings > Display, nativeHeadingInk)
    final lines = app.settings.nativeHeadingInk ? ink : sepia;
    final sub = capsOn
        ? TextStyle(fontFamily: caps, fontSize: 14.4, letterSpacing: 14.4 * .06, color: lines, height: 1.5)
        : TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15.2, color: lines, height: 1.5);
    // Top line only shares space with the 48 px menu button; lines below
    // share space with the stacked record dot + source pill (~136 px).
    const row1Title = 64.0;
    const row2Meta = 144.0;
    final weather = feed != null ? feed.weather : ses?.weather;
    final temp = (weather?['temperatureC'] as num?)?.round();
    final sky = weather?['symbol'] as String?;
    // a station: its name beside the title (as a session's number), then
    // the dates shown, its place, its weather and the sun and moon; the
    // periods themselves sit with the buttons
    final when = feed != null
        ? feed.dates
        : ses == null
        ? 'Nothing recorded yet: tap the microphone to start.'
        : ses.live
            ? 'Listening now, since ${clock(ses.start)}.'
            : '${span(ses.start, ses.end ?? ses.start)}.';
    // a station: where it is, when it says, as a session's place line
    final where = feed != null
        ? (feed.place == null ? '' : place(feed.place!.$1, feed.place!.$2))
        : ses == null
        ? ''
        : ses.hasPlace
            ? place(ses.lat!, ses.lon!)
            : (ses.live ? '' : 'Place unknown');
    return Column(
      key: _headKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (app.settings.nativeShowTitle) ...[
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.max(120, width - row1Title)),
          child: Text.rich(
            TextSpan(text: 'birdsongs.ai', children: [
              // the session's number, small, in the lines' own style
              if (feed == null && n > 0 && i >= 0)
                TextSpan(text: '  #${i + 1}', style: sub.copyWith(height: 1)),
              if (feed != null) TextSpan(text: '  #${feed.station.name.toLowerCase()}', style: sub.copyWith(height: 1)),
            ]),
            // a little smaller than the page's h1 (clamp(1.6rem,2.6vw,2.2rem));
            // in small capitals like Index of Species when chosen
            style: capsOn
                ? TextStyle(
                    fontFamily: caps,
                    fontSize: ((width + 16) * .021).clamp(20.0, 27.0),
                    letterSpacing: ((width + 16) * .021).clamp(20.0, 27.0) * .06,
                    color: ink,
                    height: 1.1)
                : TextStyle(
                    fontFamily: serif,
                    fontSize: ((width + 16) * .022).clamp(22.0, 30.0),
                    letterSpacing: -.15,
                    color: ink,
                    height: 1.05),
          ),
        ),
        const SizedBox(height: 3.2),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.max(120, width - row2Meta)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // the date and what goes with it, unless switched off
              // (Settings > Display > Date)
              if (app.settings.nativeShowDate) ...[
              Text(when, style: sub),
              if (where.isNotEmpty) Text(where, style: sub),
              if (temp != null || sky != null)
                Tooltip(
                  message: weatherWords(weather),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sky != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Icon(weatherIcon(sky), size: 17, color: lines),
                        ),
                      if (temp != null) Text('$temp°C', style: sub),
                    ],
                  ),
                ),
              // Heart outline + total species count; beats red for 2 s whenever
              // a bird is detected (local or remote), then returns to black outline.
              () {
                final lifeCount = feed != null
                    ? species
                    : {
                        for (final d in app.store.all)
                          if (!app.settings.isIgnoredSpecies(d.common, d.sci)) d.sci
                      }.length;
                return _HeartCounter(
                  count: lifeCount,
                  beatToken: _heartBeatToken,
                  textStyle: sub,
                );
              }(),
              if (feed != null && feed.lightNote != null && feed.light != Light.all)
                Text(feed.lightNote!, style: sub.copyWith(color: sepia)),
              ],
              if (totals && app.settings.nativeTotals && species > 0)
                Text('$species species from ${thousands(calls)} ${calls == 1 ? 'call' : 'calls'}.',
                    style: sub),
            ],
          ),
        ),
      ],
    );
  }

  /// The collage (collage_view.dart), once every plate of the session is
  /// ready, so the birds appear in their places; until then, the page's
  /// "Preparing the plate" and its rule. After that they only move when
  /// something asks them to: the sizing button, the window changing size, or
  /// a new bird joining while listening (it appears once its plate is
  /// ready, and the rest make room).
  Widget _collage(Session? ses, List<_Row> rows, String? newest, double width, double height,
      {required String sizeBy}) {
    final baseShowing = _showingFor(ses);
    final showing = sizeBy == 'equal' ? '$baseShowing|equal|${rows.length}' : baseShowing;
    final ready = [for (final r in rows) if (_art.containsKey(r.sci)) r];
    // Not before the height is known either (_measure), or they would be
    // placed once and then again.
    if (_revealed != showing) {
      if (ready.length < rows.length || (sizeBy != 'equal' && app.settings.nativeFit && _others == null)) {
        return SizedBox(
          width: width,
          height: height,
          child: Center(child: PlateStatus(done: ready.length, of: rows.length)),
        );
      }
      _revealed = showing;
    }
    final ordered = sizeBy == 'equal' ? _sortRows(ready, ses: ses, feed: _feed) : ready;
    final deepMaxScale = math.max(14.0, math.sqrt(ordered.length) * 2.0);
    final collage = CollageView(
      birds: [for (final r in ordered) CollageBird(r.sci, r.common, r.count, r.last)],
      art: _art,
      size: Size(width, height),
      sizeBy: sizeBy,
      markAt: app.settings.nativeMarkAt,
      newest: newest,
      live: app.engine.liveSpecies,
      showHoverInfo: app.settings.nativeHoverInfo,
      showAllNameTickets: app.settings.nativeAllNameTickets,
      allowDrag: false,
      resolutionScale: _zoomTier,
      onOpen: (b) => _openCard(rows.firstWhere((r) => r.sci == b.sci)),
    );
    return ZoomableCollage(
      // A new session or style is a new collage: nothing glides across from
      // the one before, and it starts unzoomed. High-res optical zoom + pan
      // work identically on both the home collage and No pecking order.
      key: ValueKey('$showing|$sizeBy'),
      size: Size(width, height),
      allPlatforms: true,
      maxScale: deepMaxScale,
      onScaleTier: (t) {
        if (mounted && t != _zoomTier) setState(() => _zoomTier = t);
      },
      onHold: (held) {
        final want = held ? baseShowing : null;
        if (want != _holdFor && mounted) setState(() => _holdFor = want);
      },
      child: collage,
    );
  }

  /// Modern translucent share / save popover matching [SpeciesSortBar].
  Widget _shareMenu({
    required Key key,
    required String tooltip,
    required VoidCallback onShare,
    required VoidCallback onSave,
  }) {
    return Builder(
      builder: (bc) => IconButton(
        key: key,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        iconSize: 22,
        tooltip: tooltip,
        icon: const Icon(Icons.ios_share, color: ink),
        color: ink,
        onPressed: () async {
          final picked = await showModernMenu<String>(
            anchorContext: bc,
            minWidth: 176,
            items: const [
              ModernMenuItem(value: 'share', icon: Icons.ios_share, label: 'Share'),
              ModernMenuItem(value: 'save', icon: Icons.photo_library_outlined, label: 'Save to Photos'),
            ],
          );
          if (picked == 'share') onShare();
          if (picked == 'save') onSave();
        },
      ),
    );
  }

  /// Combined Latest & Most heard view: stacked one above the other on mobile
  /// (width <= 720), side by side on larger screens.
  Widget _spotlight(List<_Row> rows, String? newest) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 64, 24, 16 + _bottomRoom),
          child: const Text(
            'Nothing heard yet. Press record to listen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 18, color: sepia),
          ),
        ),
      );
    }
    final mostHeard = rows.first;
    final latestRow = rows.firstWhere((x) => x.sci == newest, orElse: () => rows.first);
    _ensure([latestRow, mostHeard]);

    final last = latestRow.last;
    final latestDetail = last == null
        ? ''
        : (sameDay(last, DateTime.now()) ? clock(last) : '${dayMonth(last)}, ${clock(last)}');
    final mostDetail = '${calls(mostHeard.count)} this session';

    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth <= 720;
        final panelWidth = narrow ? box.maxWidth - 32 : (box.maxWidth - 65) / 2;
        final latestPanel = _spotlightPanel('Most recent', latestRow, latestDetail, panelWidth, narrow);
        final mostPanel = _spotlightPanel('Most heard', mostHeard, mostDetail, panelWidth, narrow);
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + _bottomRoom),
          child: narrow
              ? Column(
                  children: [
                    Expanded(child: latestPanel),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: rule),
                    ),
                    Expanded(child: mostPanel),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: latestPanel),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: VerticalDivider(width: 1, color: rule),
                    ),
                    Expanded(child: mostPanel),
                  ],
                ),
        );
      },
    );
  }

  Widget _spotlightPanel(String heading, _Row r, String detail, double width, bool narrow) {
    final art = _art[r.sci];
    final titleSize = narrow ? (width * .052).clamp(18.0, 24.0) : (width * .048).clamp(20.0, 30.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openCard(r),
      child: Semantics(
        button: true,
        label: '$heading: ${r.common}, open its card',
        child: Column(
          children: [
            Text(
              heading,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: caps, fontSize: 13, letterSpacing: 1.1, color: sepia),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: art == null
                  ? const SizedBox.expand()
                  : SizedBox.expand(child: PlateImage(art: art, width: width)),
            ),
            const SizedBox(height: 6),
            Text(
              r.common,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: serif, fontSize: titleSize, height: 1.18, color: ink),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1.5),
              child: Text(
                r.sci,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: serif,
                    fontStyle: FontStyle.italic,
                    fontSize: narrow ? 14.5 : 17,
                    color: sepia),
              ),
            ),
            if (detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: serif, fontSize: narrow ? 14.5 : 17, color: madder),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// How tall the collage is, with its margins. Fitted on one screen (the page's fitPlate): the
  /// screen less the heading and the index, and never under 140. Otherwise
  /// the page's own: the screen less 8.5rem and at least 420, or three wide
  /// to four tall on a narrow screen.
  double _plateHeight(double width, double screen) {
    if (app.settings.nativeFit) {
      final others = _others;
      // a first guess, only ever seen behind "Preparing the plate"
      return others == null ? math.max(140, screen * .5) : math.max(140, screen - others);
    }
    return width <= 720 ? width * 4 / 3 : math.max(420, screen - 136);
  }

  /// After each frame: the height of everything but the collage, for
  /// [_plateHeight].
  void _measure() {
    if (!mounted) return;
    final head = _headKey.currentContext?.size?.height, index = _indexKey.currentContext?.size?.height;
    if (head != null && index != null && ((head - _headH).abs() > .5 || (index - _indexH).abs() > .5)) {
      setState(() {
        _headH = head;
        _indexH = index;
      });
    }
    final all = _allKey.currentContext?.size?.height, plate = _plateKey.currentContext?.size?.height;
    if (all == null || plate == null) return;
    // and the scroll view's padding above and below
    final others = all - plate + 2 * _fadeRoom;
    if (_others == null || (others - _others!).abs() > .5) setState(() => _others = others);
  }
}

/// Total-species heart indicator beneath the weather. Whenever [beatToken]
/// increments (a bird detection arrives), the heart turns red, fills in,
/// performs a 2-second lub-dub heartbeat animation, and returns cleanly to
/// the black Material outline.
class _HeartCounter extends StatefulWidget {
  const _HeartCounter({
    required this.count,
    required this.beatToken,
    required this.textStyle,
  });

  final int count;
  final int beatToken;
  final TextStyle textStyle;

  @override
  State<_HeartCounter> createState() => _HeartCounterState();
}

class _HeartCounterState extends State<_HeartCounter> with SingleTickerProviderStateMixin {
  static const _heartRed = Color(0xFFC82820);

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..addStatusListener((status) {
      if ((status == AnimationStatus.completed || status == AnimationStatus.dismissed) && mounted) {
        setState(() {});
      }
    });

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.32).chain(CurveTween(curve: Curves.easeOut)), weight: 7),
    TweenSequenceItem(tween: Tween(begin: 1.32, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 8),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.24).chain(CurveTween(curve: Curves.easeOut)), weight: 6),
    TweenSequenceItem(tween: Tween(begin: 1.24, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 9),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.28).chain(CurveTween(curve: Curves.easeOut)), weight: 7),
    TweenSequenceItem(tween: Tween(begin: 1.28, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 8),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.20).chain(CurveTween(curve: Curves.easeOut)), weight: 6),
    TweenSequenceItem(tween: Tween(begin: 1.20, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 10),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 24),
  ]).animate(_anim);

  @override
  void didUpdateWidget(_HeartCounter old) {
    super.didUpdateWidget(old);
    if (widget.beatToken != old.beatToken && widget.beatToken > 0) {
      _anim.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 5),
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              final beating = _anim.isAnimating;
              return Transform.scale(
                scale: beating ? _scale.value : 1.0,
                child: Icon(
                  beating ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: beating ? _heartRed : ink,
                ),
              );
            },
          ),
        ),
        Text(thousands(widget.count), style: widget.textStyle),
      ],
    );
  }
}

/// A picture for MET Norway's weather symbol ("partlycloudy_day",
/// "lightrainshowers_night", ...), from Material's icons.
IconData weatherIcon(String symbol) {
  final s = symbol.toLowerCase(), night = s.endsWith('_night');
  if (s.contains('thunder')) return Icons.thunderstorm_outlined;
  if (s.contains('snow') || s.contains('sleet')) return Icons.ac_unit;
  if (s.contains('rain')) return Icons.water_drop_outlined;
  if (s.startsWith('fog')) return Icons.foggy;
  if (s.startsWith('cloudy')) return Icons.cloud_outlined;
  if (s.startsWith('partlycloudy')) return Icons.wb_cloudy_outlined;
  // clear sky, fair
  return night ? Icons.nights_stay_outlined : Icons.wb_sunny_outlined;
}

/// A bird's card from a remote station: the particulars its list gave,
/// then what the station says when asked (station_feed.dart).
class _StationCard implements CardSource {
  _StationCard(this.feed, this.s);

  final StationFeed feed;
  final StationSpecies s;

  @override
  String get sci => s.sci;
  @override
  String get common => s.common;

  @override
  List<(String, String)> get rows => [
        ('Heard', calls(s.count)),
        if (s.first != null) ('First heard', whenHeard(s.first!)),
        if (s.last != null) ('Last heard', whenHeard(s.last!)),
        if (s.maxConf > 0) ('Surest identification', inHundred(s.maxConf)),
        if (s.avgConf > 0) ('Usual confidence', inHundred(s.avgConf)),
        if (s.daysKnown > 0)
          ('Known at this station', s.daysKnown == 1 ? 'since yesterday' : 'for ${thousands(s.daysKnown)} days'),
      ];

  @override
  Future<List<(String, String)>> moreRows() => feed.particulars(s);
  @override
  Future<({List<int> hours, String label})?> hours() => feed.hourly(s);
  @override
  Future<List<({DateTime day, int count})>?> trend() => feed.trend(s);
  @override
  Future<List<CardRecording>> recordings() async => [
        for (final r in await feed.recordings(s))
          CardRecording(
            key: '${r.at.millisecondsSinceEpoch}',
            at: r.at,
            confidence: r.confidence,
            weather: r.weather,
            url: r.audioUrl,
            clip: r.clip,
            spectrogramUrl: r.spectrogramUrl,
          )
      ];
}
