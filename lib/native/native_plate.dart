import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import '../settings.dart';
import '../store/detection_store.dart';
import '../ui/format.dart';
import 'collage_view.dart';
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
/// the same screen. A bird's card offers its other plates; the one picked
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
  static const _padTop = 14.0, _padBottom = 28.0;

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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(_sizings[next]!, style: const TextStyle(fontFamily: serif, fontSize: 16))));
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
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoaded?.call());
  }

  @override
  void dispose() {
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

  Future<void> _record() async {
    final engine = app.engine;
    if (engine.starting) return;
    if (engine.running) {
      await engine.stop();
      return;
    }
    await engine.start();
    if (!mounted || engine.error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(engine.error!)));
  }

  void _toStation() {
    final s = app.settings;
    if (s.stations.isEmpty) {
      widget.openSettings();
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
                LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, _padTop, 20, _padBottom),
                    child: Column(
                      key: _allKey,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // room on the right for the buttons
                        Padding(
                          padding: const EdgeInsets.only(right: 196),
                          child: _heading(ses, i, n, rows.length, calls),
                        ),
                        const SizedBox(height: 18),
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
                          KeyedSubtree(
                            key: _plateKey,
                            child: _collage(ses!, onPlate, newest, box.maxWidth - 40,
                                _plateHeight(box.maxWidth - 40, box.maxHeight)),
                          ),
                        const SizedBox(height: 22),
                        _indexHeading(i, n),
                        const SizedBox(height: 10),
                        _index(rows, marked, box.maxWidth - 40),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      engine.starting
                          ? const SizedBox(
                              width: 48,
                              height: 48,
                              child: Padding(
                                  padding: EdgeInsets.all(15),
                                  child: CircularProgressIndicator(strokeWidth: 2)))
                          : IconButton(
                              tooltip: engine.running ? 'Stop recording' : 'Record a new session',
                              icon: Icon(
                                  engine.running ? Icons.stop_rounded : Icons.fiber_manual_record),
                              color: red,
                              onPressed: _record,
                            ),
                      IconButton(
                        tooltip: app.settings.stations.isEmpty
                            ? 'Add a remote station'
                            : 'Remote station: ${app.settings.station!.name}',
                        icon: const Icon(Icons.sensors),
                        color: sepia,
                        onPressed: _toStation,
                      ),
                      IconButton(
                        tooltip: 'Size the birds by: ${_sizings[app.settings.nativeSizeBy] ?? ''}',
                        icon: const Icon(Icons.autorenew),
                        color: red,
                        onPressed: _nextSizing,
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.menu),
                        color: red,
                        onPressed: widget.openSettings,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _heading(Session? ses, int i, int n, int species, int calls) {
    const sub = TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 16, color: sepia, height: 1.35);
    final w = ses == null ? '' : weatherWords(ses.weather);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(text: 'Birdsong', children: [
            if (n > 0 && i >= 0)
              TextSpan(text: '  #${i + 1}/$n', style: const TextStyle(color: sepia)),
          ]),
          style: const TextStyle(fontFamily: serif, fontSize: 30, color: ink, height: 1.05),
        ),
        const SizedBox(height: 4),
        if (ses != null)
          Text(
            ses.live
                ? '${day(ses.start)}, ${clock(ses.start)}, listening now.'
                : '${span(ses.start, ses.end!)}.',
            style: sub,
          ),
        if (ses != null && ses.hasPlace)
          Text('At ${place(ses.lat!, ses.lon!)}${w.isEmpty ? '' : ', $w'}.', style: sub),
        if (ses != null)
          Text(
            '$species species from $calls ${calls == 1 ? 'call' : 'calls'}.',
            style: sub,
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

  /// How tall the collage is. Fitted on one screen (the page's fitPlate): the
  /// screen less the heading and the index, and never under 140. Otherwise
  /// the page's own: the screen less 8.5rem and at least 420, or three wide
  /// to four tall on a narrow screen.
  double _plateHeight(double width, double screen) {
    if (app.settings.nativeFit) {
      final others = _others;
      // a first guess, only ever seen behind "Preparing the plate"
      return others == null ? math.max(140, screen * .5) : math.max(140, screen - others);
    }
    return width + 40 <= 720 ? width * 4 / 3 : math.max(420, screen - 153);
  }

  /// After each frame: the height of everything but the collage, for
  /// [_plateHeight].
  void _measure() {
    if (!mounted) return;
    final all = _allKey.currentContext?.size?.height, plate = _plateKey.currentContext?.size?.height;
    if (all == null || plate == null) return;
    // the column's own padding, top and bottom
    final others = all - plate + _padTop + _padBottom;
    if (_others == null || (others - _others!).abs() > .5) setState(() => _others = others);
  }

  Widget _indexHeading(int i, int n) {
    final store = app.store;
    Widget arrow(IconData icon, bool on, int by, String tip) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20),
          color: ink,
          onPressed: on ? () => store.step(by) : null,
        );
    return Row(
      children: [
        if (n > 1) arrow(Icons.chevron_left, i > 0, -1, 'Earlier session'),
        const Expanded(child: Divider(color: rule, indent: 8, endIndent: 14)),
        const Text('Index of species',
            style: TextStyle(fontFamily: caps, fontSize: 18, letterSpacing: 2.2, color: ink)),
        const Expanded(child: Divider(color: rule, indent: 14, endIndent: 8)),
        if (n > 1) arrow(Icons.chevron_right, i >= 0 && i < n - 1, 1, 'Later session'),
      ],
    );
  }

  Widget _index(List<_Row> rows, String? newest, double width) {
    // Fitted on one screen the page sets the index smaller and in columns
    // of 11rem (body.fit #index), so more of the screen is left for birds.
    final fit = app.settings.nativeFit;
    final gap = fit ? 26.0 : 28.0;
    final cols = fit
        ? math.max(1, ((width + gap) / (176 + gap)).floor())
        : (width >= 900 ? 3 : (width >= 340 ? 2 : 1));
    final colWidth = (width - gap * (cols - 1)) / cols;
    return Wrap(
      spacing: gap,
      children: [
        for (final r in rows)
          SizedBox(
            width: colWidth,
            child: InkWell(
              onTap: () => _openCard(r),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: fit ? 1 : 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(r.common,
                          overflow: TextOverflow.ellipsis,
                          // the latest heard has its name in madder, to match its mark
                          style: TextStyle(
                              fontFamily: serif,
                              fontSize: fit ? 15 : 17,
                              color: r.sci == newest ? madder : ink)),
                    ),
                    // the leader between name and number
                    Expanded(
                      child: Container(
                          height: 1,
                          margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                          color: rule.withValues(alpha: 0.6)),
                    ),
                    Text('${r.count}',
                        style: TextStyle(fontFamily: caps, fontSize: fit ? 14 : 16, color: madder)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
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
