import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../app_state.dart';
import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import '../settings.dart';
import '../store/detection_store.dart';
import '../engine/listen_engine.dart' show maxSessionSpecies;
import '../ui/format.dart';
import '../ui/plate_buttons.dart';
import '../ui/station_editor.dart';
import 'collage_view.dart';
import 'index_view.dart';
import 'plate_library.dart';

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
/// Not moved across yet: the views a to g, the map, pinch zoom, the limit
/// on species, skulls wings and eggs, the caption, recordings, spectrograms
/// and facts on the card, share, remote stations (those still open the web
/// plate).
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

/// How the collage is sized (Settings.nativeSizeBy), with the note shown
/// when the button steps to it. The web plate's three, by the same names.
const _sizings = {
  'calls': 'Noisiest species',
  'time': 'Recent ramblings',
  'equal': 'No pecking order',
};

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
  int _round = 0;

  // The collage on show, as "session|style", once every one of its plates
  // was ready: until then nothing is drawn, so the birds appear in their
  // places rather than arriving one by one and shuffling about.
  String? _revealed;

  // The height of everything but the collage (heading, index, padding),
  // measured after each frame, so the collage can take what is left of the
  // screen. Null until first measured.
  double? _others;
  final _allKey = GlobalKey(), _plateKey = GlobalKey();
  static const _padTop = 16.0; // header{padding:1rem ... 0}

  /// The most species drawn on the plate; the rest are in the index only
  /// (the page's maxOnPlate).
  static const maxOnPlate = 60;

  PlateStyle get _style => PlateStyle.named(app.settings.nativePlateStyle);

  /// Look for the plates of [rows] not asked for yet.
  void _ensure(List<_Row> rows) {
    final lib = _lib;
    if (lib == null) return;
    final style = _style;
    if (style != _artStyle) {
      _artStyle = style;
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

  void _nextSizing() {
    final keys = _sizings.keys.toList();
    final next = keys[(keys.indexOf(app.settings.nativeSizeBy) + 1) % keys.length];
    app.settings.update((x) => x.nativeSizeBy = next);
    _say(_sizings[next]!, seconds: 2);
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

  void _openCard(_Row r) {
    final lib = _lib;
    if (lib == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => _PlateCard(
        lib: lib,
        style: _style,
        row: r,
        art: _art[r.sci],
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
        final rows = _rows(ses);
        final onPlate = rows.take(maxOnPlate).toList();
        _ensure(onPlate);
        // the creature heard last (the page's newestSci)
        String? newest;
        DateTime? latest;
        for (final r in rows) {
          if (r.last != null && (latest == null || r.last!.isAfter(latest))) {
            latest = r.last;
            newest = r.sci;
          }
        }
        final marked = app.settings.nativeMarkAt == 'none' ? null : newest;
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        final calls = rows.fold<int>(0, (n, r) => n + r.count);
        final i = store.selectedIndex, n = store.sessions.length;
        final red = Theme.of(context).colorScheme.primary;
        return PaperBackground(
          child: SafeArea(
            child: Stack(
              children: [
                LayoutBuilder(builder: (context, box) {
                  final fit = app.settings.nativeFit;
                  final side = (box.maxWidth * (fit ? .03 : .04)).clamp(16.0, fit ? 32.0 : 48.0);
                  final plateSide = (box.maxWidth * .02).clamp(8.0, 32.0);
                  final headSide = (box.maxWidth * .04).clamp(16.0, 48.0);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.only(top: _padTop),
                    child: Column(
                      key: _allKey,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: headSide),
                          child: _heading(ses, i, n, rows.length, calls, box.maxWidth - headSide),
                        ),
                        if (rows.isEmpty)
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
                          Padding(
                            key: _plateKey,
                            padding: EdgeInsets.fromLTRB(plateSide, 3.2, plateSide, 8.8),
                            child: _collage(ses!, onPlate, newest, box.maxWidth - 2 * plateSide,
                                _plateHeight(box.maxWidth, box.maxHeight) - 12),
                          ),
                        // section{padding:2.2rem clamp(1rem,4vw,3rem) 2.5rem;max-width:78rem},
                        // closer when fitted on one screen
                        Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: fit ? double.infinity : 1248),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(side, fit ? 8 : 35.2, side, fit ? 12.8 : 40),
                              child: IndexView(
                                entries: [
                                  for (final r in rows)
                                    IndexEntry(r.sci, r.common, r.count,
                                        noPlate: _art.containsKey(r.sci) && _art[r.sci] == null),
                                ],
                                width: math.min(box.maxWidth, fit ? double.infinity : 1248) - 2 * side,
                                fit: fit,
                                narrow: box.maxWidth <= 720,
                                folded: app.settings.nativeIndexFolded,
                                onFold: () => app.settings
                                    .update((x) => x.nativeIndexFolded = !x.nativeIndexFolded),
                                newest: marked,
                                steps: n > 1,
                                canPrev: i > 0,
                                canNext: i >= 0 && i < n - 1,
                                onStep: store.step,
                                onOpen: (e) => _openCard(rows.firstWhere((r) => r.sci == e.sci)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
                      Padding(
                        padding: const EdgeInsets.only(top: 5), // level with the round buttons
                        child: SourcePill(
                          listen: true,
                          stationName: app.settings.station?.name,
                          onListen: () {},
                          onRemote: _toRemote,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Settings',
                            icon: const Icon(Icons.menu),
                            color: red,
                            onPressed: widget.openSettings,
                          ),
                          // Views a to g are not moved across yet: for now
                          // this steps through the three that size the
                          // collage (a, f and g).
                          IconButton(
                            tooltip: 'Plate: ${_sizings[app.settings.nativeSizeBy] ?? ''}',
                            icon: const Icon(Icons.dashboard_outlined),
                            color: red,
                            onPressed: _nextSizing,
                          ),
                        ],
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
        );
      },
    );
  }

  /// The page's header as the app fills it in Listen here: the title with
  /// the session's number, then, each on its own line, when, where and the
  /// totals. The title stops short of the buttons' row; the lines under it
  /// stop short of the menu and view column. [width] is the room from the
  /// left padding to the screen's right edge.
  Widget _heading(Session? ses, int i, int n, int species, int calls, double width) {
    // #sub{font-style:italic;color:sepia;font-size:.95rem}, three block spans
    const sub = TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15.2, color: sepia, height: 1.5);
    // record 44, pill 94, menu 48, and 8 from the edge; the column is the last two
    const row1 = 194.0, col = 56.0;
    final w = ses == null ? '' : weatherWords(ses.weather);
    final when = ses == null
        ? 'Nothing recorded yet: tap the microphone to start.'
        : ses.live
            ? 'Listening now, since ${clock(ses.start)}.'
            : '${span(ses.start, ses.end ?? ses.start)}.';
    final where = ses == null
        ? ''
        : ses.hasPlace
            ? 'At ${place(ses.lat!, ses.lon!)}${w.isEmpty ? '' : ', $w'}.'
            : (ses.live ? '' : 'Place unknown.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.max(120, width - row1)),
          child: Text.rich(
            TextSpan(text: 'Birdsong', children: [
              if (n > 0 && i >= 0)
                TextSpan(text: ' #${i + 1}/$n', style: const TextStyle(color: sepia)),
            ]),
            // h1{font-size:clamp(1.6rem,2.6vw,2.2rem);line-height:1.05;letter-spacing:-.005em}
            style: TextStyle(
                fontFamily: serif,
                fontSize: ((width + 16) * .026).clamp(25.6, 35.2),
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
              if (species > 0)
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
    final showing = '${ses.id}|${_style.name}';
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
    return CollageView(
      // A new session or style is a new collage: nothing glides across from
      // the one before.
      key: ValueKey(showing),
      birds: [for (final r in ready) CollageBird(r.sci, r.common, r.count, r.last)],
      art: _art,
      size: Size(width, height),
      sizeBy: app.settings.nativeSizeBy,
      markAt: app.settings.nativeMarkAt,
      newest: newest,
      live: app.engine.liveSpecies,
      onOpen: (b) => _openCard(rows.firstWhere((r) => r.sci == b.sci)),
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
    final all = _allKey.currentContext?.size?.height, plate = _plateKey.currentContext?.size?.height;
    if (all == null || plate == null) return;
    // and the scroll view's padding above
    final others = all - plate + _padTop;
    if (_others == null || (others - _others!).abs() > .5) setState(() => _others = others);
  }
}

/// A bird's card: its plate, names, how often it was heard, the plate's
/// credit, and the other plates on offer. Tapping one makes it this bird's
/// plate from now on (PlateLibrary.choose).
class _PlateCard extends StatefulWidget {
  const _PlateCard(
      {required this.lib, required this.style, required this.row, required this.art, required this.onChosen});

  final PlateLibrary lib;
  final PlateStyle style;
  final _Row row;
  final PlateArt? art;
  final ValueChanged<PlateArt?> onChosen;

  @override
  State<_PlateCard> createState() => _PlateCardState();
}

class _PlateCardState extends State<_PlateCard> {
  late PlateArt? _art = widget.art;
  late final Future<List<PlateCandidate>> _others =
      widget.lib.candidates(widget.row.sci, widget.row.common);
  String? _choosing;

  Future<void> _choose(PlateCandidate c) async {
    setState(() => _choosing = c.url);
    final art = await widget.lib.choose(widget.row.sci, c, widget.style);
    if (!mounted) return;
    setState(() {
      _choosing = null;
      if (art != null) _art = art;
    });
    if (art != null) widget.onChosen(art);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row, art = _art;
    const small = TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 13, color: sepia);
    return Dialog(
      backgroundColor: paper,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4), side: const BorderSide(color: rule)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 260,
                child: art == null
                    ? const Center(child: Text('No plate found.', style: small))
                    : PlateImage(art: art, width: 392),
              ),
              const SizedBox(height: 12),
              Text(r.common,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: serif, fontSize: 24, color: ink)),
              Text(r.sci,
                  style: const TextStyle(
                      fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 16, color: sepia)),
              const SizedBox(height: 8),
              Text(
                '${r.count == 1 ? 'Heard once' : 'Heard ${r.count} times'}'
                '${r.last == null ? '' : ', last at ${clock(r.last!)}'}.',
                style: const TextStyle(fontFamily: serif, fontSize: 16, color: ink),
              ),
              if (art != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      '${art.credit}${art.cut ? ' Cut out on this device.' : art.tint ? ' Tinted into the page.' : ''}',
                      textAlign: TextAlign.center, style: small),
                ),
              const SizedBox(height: 14),
              FutureBuilder<List<PlateCandidate>>(
                future: _others,
                builder: (context, snap) {
                  final all = snap.data;
                  if (all == null) return const Text('Looking for other plates…', style: small);
                  if (all.length < 2) return const Text('No other plates on offer.', style: small);
                  return Column(
                    children: [
                      const Text('Other plates', style: TextStyle(fontFamily: caps, fontSize: 14, letterSpacing: 1.6, color: ink)),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 78,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: all.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final c = all[i], on = art?.from.url == c.url;
                            return Tooltip(
                              message: c.credit,
                              child: InkWell(
                                onTap: _choosing == null && !on ? () => _choose(c) : null,
                                child: Container(
                                  width: 78,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      border: Border.all(color: on ? madder : rule, width: on ? 2 : 1)),
                                  child: _choosing == c.url
                                      ? const Center(
                                          child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2)))
                                      : _Thumb(lib: widget.lib, style: widget.style, candidate: c),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                          'Cut-outs first, then plates from Wikimedia Commons. '
                          'How those are treated is under Settings, Experimental.',
                          textAlign: TextAlign.center, style: small),
                    ],
                  );
                },
              ),
              Align(
                alignment: Alignment.centerRight,
                child:
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the other plates, small. Fetched (and kept) when first shown.
class _Thumb extends StatefulWidget {
  const _Thumb({required this.lib, required this.style, required this.candidate});

  final PlateLibrary lib;
  final PlateStyle style;
  final PlateCandidate candidate;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late final Future<PlateArt?> _art = widget.lib.load(widget.candidate, widget.style).then<PlateArt?>((a) => a).catchError((Object _) => null);

  @override
  Widget build(BuildContext context) => FutureBuilder<PlateArt?>(
        future: _art,
        builder: (context, snap) => snap.data == null
            ? const SizedBox()
            : PlateImage(art: snap.data!, width: 70),
      );
}
