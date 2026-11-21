import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:plate_share/plate_share.dart';

import '../app_state.dart';
import '../main.dart' show caps, ink, madder, paper, sepia, serif;
import '../settings.dart';
import '../store/detection_store.dart';
import '../engine/listen_engine.dart' show maxSessionSpecies;
import '../ui/format.dart';
import '../ui/plate_buttons.dart';
import '../ui/station_editor.dart';
import 'bird_card.dart';
import 'collage_view.dart';
import 'index_view.dart';
import 'plate_library.dart';
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
/// bird's plates (Settings > Experimental).
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
  final _shotKey = GlobalKey(), _shareKey = GlobalKey();

  /// The most species drawn on the plate; the rest are in the index only
  /// (the page's maxOnPlate).
  static const maxOnPlate = 60;

  PlateStyle get _style => PlateStyle.named(app.settings.nativePlateStyle);

  /// Which collage is on show: a new session, style, or offer of skulls,
  /// wings and eggs is a new one, prepared afresh before it is drawn.
  String _showingFor(Session? ses) =>
      '${ses?.id}|${_style.name}|${app.settings.nativeParts ? 'parts' : ''}';

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
    s.update((x) {
      x.plateMode = next;
      if (mode.sizeBy != null) x.nativeSizeBy = mode.sizeBy!;
    });
    _say(mode.name, seconds: 2);
  }

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    PlateLibrary.open().then((lib) {
      if (mounted) {
        setState(() => _lib = lib);
      } else {
        lib.close();
      }
    });
    _sesId = app.engine.session?.id;
    app.engine.addListener(_watchSession);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoaded?.call());
  }

  @override
  void dispose() {
    _noteTimer?.cancel();
    app.engine.removeListener(_watchSession);
    _lib?.close();
    super.dispose();
  }

  List<_Row> _rows(Session? ses) {
    if (ses == null) return [];
    final by = <String, _Row>{};
    for (final d in app.store.forPlate(app.settings.plateModel, session: ses)) {
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

  // Session started, ended, or full and carried on in a new one.
  int? _sesId;
  void _watchSession() {
    final now = app.engine.session?.id;
    if (now == _sesId) return;
    final before = _sesId;
    _sesId = now;
    final store = app.store;
    String number(int id) {
      final i = store.sessions.indexWhere((x) => x.id == id);
      return i < 0 ? '' : ' #${i + 1}';
    }

    if (before == null && now != null) {
      _say('Listening: session${number(now)} started.');
    } else if (before != null && now != null) {
      _say('Session${number(before)} is full at $maxSessionSpecies species; '
          'session${number(now)} started.', seconds: 5);
    } else if (before != null) {
      // The store closes (or drops) the session just after the engine stops.
      Future.delayed(const Duration(milliseconds: 400), () {
        final found = store.sessions.where((x) => x.id == before);
        if (found.isEmpty) {
          _say('Stopped. Nothing was heard, so no session was kept.');
          return;
        }
        final ses = found.first;
        final species = {
          for (final d in store.forPlate(app.settings.plateModel, session: ses)) d.sci
        }.length;
        _say('Session${number(before)} ended: '
            '${lasting((ses.end ?? DateTime.now()).difference(ses.start))}, '
            '$species species.', seconds: 4);
      });
    }
  }

  // ---- the walk on a map, in place of the collage --------------------------

  /// The map button: the walk on a map, or back to the plate (shared with
  /// the web plate, Settings.showMap).
  void _toggleMap() {
    final on = !app.settings.showMap;
    app.settings.update((x) => x.showMap = on);
    _say(on ? 'The walk, on a map.' : 'The plate.', seconds: 2);
  }

  /// The calendar button: a month calendar with the days that have a
  /// session; picking one shows that day's first session, and the ‹ ›
  /// step through the rest.
  Future<void> _pickDay() async {
    final store = app.store;
    if (store.sessions.isEmpty) {
      _say('Nothing recorded yet.', seconds: 2);
      return;
    }
    DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
    final days = {for (final x in store.sessions) day(x.start)};
    final first = days.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = days.reduce((a, b) => a.isAfter(b) ? a : b);
    final shown = store.selected;
    final picked = await showDatePicker(
      context: context,
      initialDate: shown == null ? last : day(shown.start),
      firstDate: first,
      lastDate: last,
      selectableDayPredicate: (d) => days.contains(day(d)),
      helpText: 'Sessions on',
    );
    if (picked == null || !mounted) return;
    final that = [for (final x in store.sessions) if (sameDay(x.start, picked)) x];
    if (that.isEmpty) return;
    store.select(that.first);
    if (that.length > 1) _say('${that.length} sessions that day: ‹ › for the others.', seconds: 3);
  }

  /// A cross on the map: the bird's card, from this session's row when it
  /// has one, else from what the walk heard (a bird from another part of
  /// the same walk), as the web map's openBird.
  void _openFromMap(String sci, String common, List<_Row> rows) {
    for (final r in rows) {
      if (r.sci == sci) return _openCard(r);
    }
    final store = app.store, ses = store.selected;
    if (ses == null) return;
    final model = app.settings.plateModel;
    final walk = [for (final x in store.walkOf(ses)) ...store.forPlate(model, session: x)];
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
      if (png != null) ok = await PlateShare.share(text: 'Heard with Birdsong', from: from, png: png);
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
      'denied' => 'Birdsong may not add to Photos: allow it in Settings.',
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

  // The pill's sensors half: show the remote station last shown (that is
  // still the web plate). With none saved yet, it asks for one.
  void _toRemote() {
    final s = app.settings;
    if (s.stations.isEmpty) {
      editStation(context, s);
      return;
    }
    s.update((x) {
      x.mode = AppMode.station;
      x.stationId = x.station!.id;
    });
  }

  /// The bird's card (bird_card.dart), as the web plate's: what is on the
  /// plate (the session's) for the facts and recordings, and everything on
  /// this device for how long the bird has been known here.
  void _openCard(_Row r, {List<Detection>? heard}) {
    final lib = _lib;
    if (lib == null) return;
    final store = app.store, model = app.settings.plateModel;
    heard ??= store.forPlate(model, session: store.selected);
    BirdCard.show(
      context,
      BirdCard(
        lib: lib,
        style: _style,
        facts: BirdFacts.of(r.sci, r.common, heard, store.forPlate(model)),
        art: _art[r.sci],
        clipOf: (d) => d.hasClip ? store.clipFile(d.id) : null,
        spectrogramOf: (d) => d.hasClip ? store.spectrogramFile(d.id) : null,
        onChosen: (art) {
          if (mounted) setState(() => _art[r.sci] = art);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.settings, app.store, app.engine]),
      builder: (context, _) {
        final store = app.store, engine = app.engine;
        final ses = store.selected;
        // Limit species: the most heard only, on the plate and in the index
        final all = _rows(ses), limit = app.settings.nativeLimit;
        final rows = limit > 0 && all.length > limit ? all.sublist(0, limit) : all;
        final onPlate = rows.take(maxOnPlate).toList();
        _ensure(onPlate);
        // the creature heard last (the page's newestSci)
        String? newest;
        DateTime? latest;
        for (final r in all) {
          if (r.last != null && (latest == null || r.last!.isAfter(latest))) {
            latest = r.last;
            newest = r.sci;
          }
        }
        final marked = app.settings.nativeMarkAt == 'none' ? null : newest;
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        final calls = all.fold<int>(0, (n, r) => n + r.count);
        final i = store.selectedIndex, n = store.sessions.length;
        final red = Theme.of(context).colorScheme.primary;
        final mode = plateModes[(app.settings.plateMode - 1).clamp(0, plateModes.length - 1)];
        // views d and e show one bird, unless the map is on: then the map
        // is drawn as in the other views
        final mapOn = app.settings.showMap && ses != null;
        final single = (mode.key == 'latest' || mode.key == 'top') && !mapOn;
        // the map takes the collage's place, and has one even in view c
        final showPlate = mode.key != 'index' || mapOn, showIndex = mode.key != 'noindex';
        final fit = app.settings.nativeFit;
        _bottomRoom = 40 + 8 + 6.0;
        // the folded index's heading has a row above the buttons
        // Folded away, the index's heading moves into the row along the
        // bottom, between the map and share buttons, and the plate takes
        // the room; opened, the list is where it always was.
        final foldedInline = showIndex && showPlate && !single && app.settings.nativeIndexFolded;
        if (foldedInline) _bottomRoom += 40 + 10;
        IndexView index(double width, double screen, {bool inline = false}) => IndexView(
              entries: [
                for (final r in rows)
                  IndexEntry(r.sci, r.common, r.count, noPlate: _art.containsKey(r.sci) && _art[r.sci] == null),
              ],
              width: width,
              fit: fit,
              narrow: screen <= 720,
              // the index alone: never folded, nothing to fold to
              folded: showPlate && app.settings.nativeIndexFolded,
              onFold: showPlate
                  ? () => app.settings.update((x) => x.nativeIndexFolded = !x.nativeIndexFolded)
                  : () {},
              foldable: showPlate,
              inline: inline,
              species: all.length,
              newest: marked,
              steps: n > 1,
              canPrev: i > 0,
              canNext: i >= 0 && i < n - 1,
              onStep: store.step,
              onOpen: (e) => _openCard(rows.firstWhere((r) => r.sci == e.sci)),
            );
        return Stack(
          children: [
            // The plate itself, without the buttons over it: what share takes.
            RepaintBoundary(
              key: _shotKey,
              child: PaperBackground(
                child: SafeArea(
                  child: single
                      ? _single(mode, rows, newest)
                      : LayoutBuilder(builder: (context, box) {
                  final side = (box.maxWidth * (fit ? .03 : .04)).clamp(16.0, fit ? 32.0 : 48.0);
                  final plateSide = (box.maxWidth * .02).clamp(8.0, 32.0);
                  final headSide = (box.maxWidth * .04).clamp(16.0, 48.0);
                  return SingleChildScrollView(
                    physics: _holdFor != null && (_holdFor == _showingFor(ses) || _holdFor == 'map')
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    padding: EdgeInsets.only(top: _padTop, bottom: _bottomRoom),
                    child: Column(
                      key: _allKey,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: headSide),
                          child: _heading(ses, i, n, all.length, calls, box.maxWidth - headSide,
                              totals: mode.key != 'index'),
                        ),
                        // the index alone sits in the middle of the window
                        if (!showPlate) SizedBox(height: _indexAloneTop(box.maxHeight)),
                        if (!showPlate)
                          const SizedBox.shrink()
                        else if (rows.isEmpty && !mapOn)
                          Padding(
                            key: _plateKey,
                            padding: const EdgeInsets.symmetric(vertical: 80),
                            child: Center(
                              child: Text(
                                engine.running
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
                          // #plate{margin:.2rem clamp(.5rem,2vw,2rem) .55rem}
                          Stack(
                            key: _plateKey,
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(plateSide, 3.2, plateSide, 8.8),
                                child: mapOn
                                    ? WalkMap(
                                        walk: Walk.of(store, ses, app.settings.plateModel),
                                        allBirds: app.settings.mapBirds == 'all',
                                        size: Size(box.maxWidth - 2 * plateSide,
                                            _plateHeight(box.maxWidth, box.maxHeight) - 12),
                                        onBird: (sci, common) => _openFromMap(sci, common, rows),
                                        onHold: (held) {
                                          final want = held ? 'map' : null;
                                          if (want != _holdFor && mounted) setState(() => _holdFor = want);
                                        },
                                      )
                                    : _collage(ses!, onPlate, newest, box.maxWidth - 2 * plateSide,
                                        _plateHeight(box.maxWidth, box.maxHeight) - 12),
                              ),
                              // With no index there is no heading to carry the
                              // session arrows: the web plate's app draws a
                              // pair at the plate's edges instead.
                              if (!showIndex && n > 1) ...[
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                      child: _EdgeArrow(Icons.chevron_left, 'Earlier session',
                                          i > 0 ? () => store.step(-1) : null)),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                      child: _EdgeArrow(Icons.chevron_right, 'Later session',
                                          i >= 0 && i < n - 1 ? () => store.step(1) : null)),
                                ),
                              ],
                            ],
                          ),
                        // The page's caption, under the plate; not when it is
                        // fitted on one screen (body.fit #caption)
                        if (showPlate && !fit)
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 704),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 9.6, 16, 0),
                                child: Text(
                                  !mapOn
                                      ? 'Each bird is drawn in proportion to how often it was heard. '
                                          'Select one to see its plate and its hours.'
                                      : app.settings.mapBirds == 'all'
                                          ? 'The way you walked, with a cross wherever a bird was heard. '
                                              'Select one to see its plate and its hours.'
                                          : 'The way you walked, with a cross where each bird was first heard. '
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
                              padding: EdgeInsets.fromLTRB(side, !showPlate ? 12.8 : (fit ? 8 : 35.2), side, fit ? 12.8 : 40),
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
            ),
            SafeArea(
              child: Stack(
                children: [
                // The same buttons as over the web plate: record, the
                // source pill, the menu, and the plate's view under it.
                Positioned(
                  right: 8,
                  top: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RecordButton(recording: engine.running, busy: engine.starting, onTap: _record),
                      SizedBox(
                      // level with the record and menu buttons
                      height: SourcePill.rowHeight,
                      child: Center(
                        child: SourcePill(
                          listen: true,
                          stationName: app.settings.station?.name,
                          onListen: () {},
                          onRemote: _toRemote,
                        ),
                      ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Settings',
                          constraints: const BoxConstraints.tightFor(
                              width: SourcePill.rowHeight, height: SourcePill.rowHeight),
                            icon: const Icon(Icons.menu),
                            color: red,
                            onPressed: widget.openSettings,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // The walk on a map in place of the collage, at the bottom
                // left; not in the views of one bird (d and e).
                // Along the bottom at the left, quick things to do: the plate's
                // view (a to g) in the corner, so it never moves while
                // stepping through the views, then the map.
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        padding: EdgeInsets.zero,
                        iconSize: 22,
                        tooltip: 'Plate: ${mode.name}',
                        icon: const Icon(Icons.dashboard_outlined),
                        color: red,
                        onPressed: _nextMode,
                      ),
                      IconButton(
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        padding: EdgeInsets.zero,
                        iconSize: 22,
                        tooltip: app.settings.showMap ? 'Back to the plate' : 'The walk on a map',
                        // the same picture on and off, so it is plain what it does
                        icon: const Icon(Icons.map_outlined),
                        isSelected: app.settings.showMap,
                        color: red,
                        onPressed: _toggleMap,
                      ),
                    ],
                  ),
                ),
                // The folded index's heading, on a row of its own just above
                // the buttons along the bottom.
                if (foldedInline)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8 + 40 + 10,
                    height: 40,
                    child: index(MediaQuery.sizeOf(context).width - 112, MediaQuery.sizeOf(context).width,
                        inline: true),
                  ),
                // The calendar, at the bottom right beside share (in the
                // corner where there is no share).
                Positioned(
                  right: PlateShare.supported ? 8 + 40 : 8,
                  bottom: 8,
                  child: IconButton(
                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    padding: EdgeInsets.zero,
                    iconSize: 22,
                    tooltip: 'Pick a day',
                    icon: const Icon(Icons.calendar_today_outlined),
                    color: red,
                    onPressed: _pickDay,
                  ),
                ),
                // Share or save, out of the way at the bottom right.
                if (PlateShare.supported)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: PopupMenuButton<String>(
                      key: _shareKey,
                      padding: const EdgeInsets.all(9),
                      iconSize: 22,
                      tooltip: 'Share or save the plate',
                      icon: Icon(Icons.ios_share, color: red),
                      color: paper,
                      onSelected: (v) => v == 'save' ? _save() : _share(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'share',
                          child: ListTile(leading: Icon(Icons.ios_share), title: Text('Share…')),
                        ),
                        PopupMenuItem(
                          value: 'save',
                          child: ListTile(
                              leading: Icon(Icons.photo_library_outlined), title: Text('Save to Photos')),
                        ),
                      ],
                    ),
                  ),
                if (_note != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 112,
                    child: IgnorePointer(
                      ignoring: !_noteShown,
                      child: AnimatedOpacity(
                        opacity: _noteShown ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Center(
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
  /// when switched on (Settings > Experimental, nativeTotals), the totals. The title stops short of the buttons' row; the lines under it
  /// stop short of the menu and view column. [width] is the room from the
  /// left padding to the screen's right edge.
  Widget _heading(Session? ses, int i, int n, int species, int calls, double width, {bool totals = true}) {
    // #sub{font-style:italic;color:sepia;font-size:.95rem}, three block spans;
    // or, when chosen (Settings > Experimental, nativeTitleCaps), the whole
    // heading in small capitals as Index of Species is set
    final capsOn = app.settings.nativeTitleCaps;
    final sub = capsOn
        ? const TextStyle(fontFamily: caps, fontSize: 14.4, letterSpacing: 14.4 * .06, color: sepia, height: 1.5)
        : const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15.2, color: sepia, height: 1.5);
    // record 44, pill 94, menu 48, and 8 from the edge; the column is the last two
    const row1 = 194.0, col = 56.0;
    final weather = ses?.weather;
    final temp = (weather?['temperatureC'] as num?)?.round();
    final sky = weather?['symbol'] as String?;
    final when = ses == null
        ? 'Nothing recorded yet: tap the microphone to start.'
        : ses.live
            ? 'Listening now, since ${clock(ses.start)}.'
            : '${span(ses.start, ses.end ?? ses.start)}.';
    final where = ses == null
        ? ''
        : ses.hasPlace
            ? place(ses.lat!, ses.lon!)
            : (ses.live ? '' : 'Place unknown');
    return Column(
      key: _headKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.max(120, width - row1)),
          child: Text.rich(
            TextSpan(text: 'Birdsong', children: [
              // the session's number, small, in the lines' own style
              if (n > 0 && i >= 0)
                TextSpan(text: '  #${i + 1}/$n', style: sub.copyWith(height: 1)),
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
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.max(120, width - col)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          child: Icon(weatherIcon(sky), size: 17, color: sepia),
                        ),
                      if (temp != null) Text('$temp°C', style: sub),
                    ],
                  ),
                ),
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
  Widget _collage(Session ses, List<_Row> rows, String? newest, double width, double height) {
    final showing = _showingFor(ses);
    final ready = [for (final r in rows) if (_art.containsKey(r.sci)) r];
    // Not before the height is known either (_measure), or they would be
    // placed once and then again.
    if (_revealed != showing) {
      if (ready.length < rows.length || (app.settings.nativeFit && _others == null)) {
        return SizedBox(
          width: width,
          height: height,
          child: Center(child: PlateStatus(done: ready.length, of: rows.length)),
        );
      }
      _revealed = showing;
    }
    final collage = CollageView(
      birds: [for (final r in ready) CollageBird(r.sci, r.common, r.count, r.last)],
      art: _art,
      size: Size(width, height),
      sizeBy: app.settings.nativeSizeBy,
      markAt: app.settings.nativeMarkAt,
      newest: newest,
      live: app.engine.liveSpecies,
      onOpen: (b) => _openCard(rows.firstWhere((r) => r.sci == b.sci)),
    );
    return ZoomableCollage(
      // A new session or style is a new collage: nothing glides across from
      // the one before, and it starts unzoomed.
      key: ValueKey(showing),
      size: Size(width, height),
      onHold: (held) {
        final want = held ? showing : null;
        if (want != _holdFor && mounted) setState(() => _holdFor = want);
      },
      child: collage,
    );
  }

  /// View c, the index alone, as the app places it on the web plate: in the
  /// middle of the window rather than of the room under the heading, as far
  /// as there is room (plate-extras.js, balance). The space above it.
  double _indexAloneTop(double screen) {
    final room = screen - _padTop - _headH;
    final pad = math.max(0.0, math.min(_headH, room - _indexH));
    return math.max(0.0, (room - pad - _indexH) / 2);
  }

  /// Views d and e: one bird, as large as the screen allows, with its name,
  /// scientific name, and when it was last heard (d) or how often (e). A
  /// tap on it opens its card. The page's #latest.
  Widget _single(PlateMode mode, List<_Row> rows, String? newest) {
    final _Row? r = rows.isEmpty
        ? null
        : mode.key == 'top'
            ? rows.first
            : rows.firstWhere((x) => x.sci == newest, orElse: () => rows.first);
    if (r != null) _ensure([r]);
    final art = r == null ? null : _art[r.sci];
    final width = MediaQuery.sizeOf(context).width;
    final last = r?.last;
    final line = r == null
        ? ''
        : mode.key == 'latest'
            ? (last == null ? '' : (sameDay(last, DateTime.now()) ? clock(last) : '${dayMonth(last)}, ${clock(last)}'))
            // "since records began" is this session, in Listen here
            : '${calls(r.count)} this session';
    return Padding(
      // clear of the buttons at the top
      padding: EdgeInsets.fromLTRB(16, 64, 16, 16 + _bottomRoom),
      child: Column(
        children: [
          Expanded(
            child: r == null || art == null
                ? const SizedBox.expand()
                : GestureDetector(
                    onTap: () => _openCard(r),
                    child: Semantics(
                      button: true,
                      label: '${r.common}: open its card',
                      child: SizedBox.expand(child: PlateImage(art: art, width: width)),
                    ),
                  ),
          ),
          const SizedBox(height: 6.4),
          GestureDetector(
            onTap: r == null ? null : () => _openCard(r),
            child: Column(
              children: [
                Text(r?.common ?? 'Nothing heard yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: serif, fontSize: (width * .034).clamp(20.8, 33.6), height: 1.25, color: ink)),
                if (r != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1.6),
                    child: Text(r.sci,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 18, color: sepia)),
                  ),
                if (line.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.4),
                    child: Text(line,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: serif, fontSize: 18, color: madder)),
                  ),
              ],
            ),
          ),
        ],
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
    final others = all - plate + _padTop + _bottomRoom;
    if (_others == null || (others - _others!).abs() > .5) setState(() => _others = others);
  }
}

/// A small arrow at the plate's edge for the next or previous session; not
/// drawn at the first or last. The web plate's _Arrow (plate_view.dart).
class _EdgeArrow extends StatelessWidget {
  const _EdgeArrow(this.icon, this.tooltip, this.onPressed);

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: tooltip,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      color: sepia.withValues(alpha: 0.75),
      icon: Icon(icon),
      onPressed: onPressed,
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
