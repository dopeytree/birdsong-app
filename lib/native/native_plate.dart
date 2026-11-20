import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import '../settings.dart';
import '../store/detection_store.dart';
import '../ui/format.dart';
import 'collage_layout.dart';
import 'plate_library.dart';

/// The plate drawn by Flutter itself instead of the web page: a first
/// version, for Listen here. It has the heading, the collage, the Index of
/// species and a card for each bird, from the sessions on this device.
///
/// Plates still on their paper are treated one of three ways (Settings >
/// Experimental, PlateStyle): cut out on the device as the web plate does,
/// tinted (multiplied with the page's paper colour, which only works on
/// flat paper, so this screen has no vignette or grain), or left as they
/// come.
///
/// The collage is packed as the web plate packs it (collage_layout.dart) and
/// sized three ways, by a button: noisiest species, recent ramblings, no
/// pecking order. A bird's card offers its other plates; the one picked is
/// kept.
///
/// Not here yet (the web plate has them): the views a to g, the map, pinch
/// zoom, the live glow, recordings and spectrograms on the card, share,
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
        _ensure(rows);
        final calls = rows.fold<int>(0, (n, r) => n + r.count);
        final i = store.selectedIndex, n = store.sessions.length;
        final red = Theme.of(context).colorScheme.primary;
        return ColoredBox(
          color: paper,
          child: SafeArea(
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                    child: Column(
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
                          _collage(ses!, rows, box.maxWidth - 40, box.maxHeight),
                        const SizedBox(height: 22),
                        _indexHeading(i, n),
                        const SizedBox(height: 10),
                        _index(rows, box.maxWidth - 40),
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

  /// The birds, packed as the web plate packs them: the largest in the
  /// middle, the rest spiralling out.
  ///
  /// Nothing is drawn until every plate of the session is ready, so the
  /// birds appear in their places. After that they only move when something
  /// asks them to: the sizing button, or a new bird joining while listening
  /// (it appears once its plate is ready, and the rest make room).
  Widget _collage(Session ses, List<_Row> rows, double width, double screen) {
    final height = math.max(260.0, math.min(width * 1.15, screen * 0.62));
    final showing = '${ses.id}|${_style.name}';
    final ready = [for (final r in rows) if (_art.containsKey(r.sci)) r];
    if (_revealed != showing) {
      if (ready.length < rows.length) {
        return SizedBox(
          width: width,
          height: height,
          child: Center(
            child: Text('Preparing the plate… ${ready.length} of ${rows.length}',
                style: const TextStyle(
                    fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 17, color: sepia)),
          ),
        );
      }
      _revealed = showing;
    }
    final by = app.settings.nativeSizeBy;
    // Recent ramblings: it is the order that counts, not the gap, or a
    // morning's birds would all come out one size.
    final byTime = [...ready]..sort((a, b) => (a.last ?? DateTime(0)).compareTo(b.last ?? DateTime(0)));
    double weight(_Row r) => switch (by) {
          'equal' => 1,
          'time' => (byTime.indexOf(r) + 1).toDouble(),
          _ => r.count.toDouble(),
        };
    final places = layoutCollage([
      for (final r in ready)
        CollageItem(r.sci,
            weight: weight(r), aspect: _art[r.sci]?.aspect ?? 1.7, blank: _art[r.sci] == null)
    ], Size(width, height))
      ..sort((a, b) => a.order.compareTo(b.order));
    final row = {for (final r in ready) r.sci: r};
    return SizedBox(
      // A new session or style is a new collage: nothing glides across from
      // the one before.
      key: ValueKey(showing),
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final p in places)
            AnimatedPositioned(
              key: ValueKey(p.id),
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeInOutCubic,
              left: p.rect.left,
              top: p.rect.top,
              width: p.rect.width,
              height: p.rect.height,
              child: GestureDetector(
                onTap: () => _openCard(row[p.id]!),
                child: _Figure(art: _art[p.id], name: row[p.id]!.common, width: p.rect.width),
              ),
            ),
        ],
      ),
    );
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

  Widget _index(List<_Row> rows, double width) {
    const gap = 28.0;
    final cols = width >= 900 ? 3 : (width >= 340 ? 2 : 1);
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
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(r.common,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: serif, fontSize: 17, color: ink)),
                    ),
                    // the leader between name and number
                    Expanded(
                      child: Container(
                          height: 1,
                          margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                          color: rule.withValues(alpha: 0.6)),
                    ),
                    Text('${r.count}',
                        style: const TextStyle(fontFamily: caps, fontSize: 16, color: madder)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One bird on the plate: its picture, or its name on a ticket while it
/// is looked for ([looking]) or when there is none.
class _Figure extends StatelessWidget {
  const _Figure({required this.art, required this.name, required this.width, this.looking = false});

  final PlateArt? art;
  final String name;
  final double width;
  final bool looking;

  @override
  Widget build(BuildContext context) {
    final art = this.art;
    if (art == null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration:
              BoxDecoration(border: Border.all(color: rule), borderRadius: BorderRadius.circular(40)),
          child: Text(name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: serif,
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  color: looking ? rule : sepia)),
        ),
      );
    }
    return _PlateImage(art: art, width: width);
  }
}

/// A plate drawn to fit. A tinted one (PlateArt.tint) is multiplied with
/// the page's paper, so its white becomes the page; a cut-out, or a plate
/// as it comes, is drawn as it is.
class _PlateImage extends StatelessWidget {
  const _PlateImage({required this.art, required this.width});

  final PlateArt art;
  final double width;

  @override
  Widget build(BuildContext context) => Image.file(
        art.file,
        fit: BoxFit.contain,
        // decode no larger than it is drawn
        cacheWidth: math.max(1, (width * MediaQuery.devicePixelRatioOf(context)).round()),
        color: art.tint ? paper : null,
        colorBlendMode: art.tint ? BlendMode.multiply : null,
        gaplessPlayback: true,
        errorBuilder: (context, _, __) => const SizedBox(),
      );
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
                    : _PlateImage(art: art, width: 392),
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
            : _PlateImage(art: snap.data!, width: 70),
      );
}
