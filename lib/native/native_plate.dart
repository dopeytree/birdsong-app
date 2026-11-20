import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import '../settings.dart';
import '../store/detection_store.dart';
import '../ui/format.dart';
import 'plate_library.dart';

/// The plate drawn by Flutter itself instead of the web page: a first
/// version, for Listen here. It has the heading, the collage, the Index of
/// species and a card for each bird, from the sessions on this device.
///
/// Plates still on their paper are "tinted": multiplied with the page's
/// paper colour, so their white becomes the page. That only works on flat
/// paper, so this screen has no vignette or grain behind the birds.
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

class _NativePlateState extends State<NativePlate> {
  PlateLibrary? _lib;

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
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
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
                  height: 280,
                  child: lib == null ? null : _Figure(lib: lib, row: r, width: 380, label: false),
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
                if (lib != null)
                  FutureBuilder<PlateArt?>(
                    future: lib.plateFor(r.sci, r.common),
                    builder: (context, snap) => Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        snap.data?.credit ??
                            (snap.connectionState == ConnectionState.done ? 'No plate found.' : ''),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 13, color: sepia),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ),
              ],
            ),
          ),
        ),
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
                          padding: const EdgeInsets.only(right: 150),
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
                          _collage(rows, box.maxWidth - 40, box.maxHeight),
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

  /// The birds, the most heard the largest, flowing in rows. (The web
  /// plate packs them more closely; this is the simple version.)
  Widget _collage(List<_Row> rows, double width, double screen) {
    final lib = _lib;
    if (lib == null) return const SizedBox(height: 200);
    final most = rows.first.count;
    final scale = [for (final r in rows) math.max(0.2, math.pow(r.count / most, 0.45).toDouble())];
    final sum = scale.fold<double>(0, (a, s) => a + s * s);
    // Fill about half of a screenful with figures.
    final k = math.sqrt(width * math.max(320.0, screen * 0.62) * 0.5 / (0.85 * sum));
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var j = 0; j < rows.length; j++)
            GestureDetector(
              onTap: () => _openCard(rows[j]),
              child: _Figure(
                  lib: lib,
                  row: rows[j],
                  width: (k * scale[j]).clamp(64.0, math.max(64.0, width * 0.62)).toDouble()),
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

/// One bird on the plate: its picture once found (kept on the device after
/// the first time), its name on a ticket until then or when there is none.
class _Figure extends StatelessWidget {
  const _Figure({required this.lib, required this.row, required this.width, this.label = true});

  final PlateLibrary lib;
  final _Row row;
  final double width;

  /// Show the name when there is no picture.
  final bool label;

  @override
  Widget build(BuildContext context) {
    final height = width * 0.85;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: width,
      height: height,
      child: FutureBuilder<PlateArt?>(
        future: lib.plateFor(row.sci, row.common),
        builder: (context, snap) {
          final art = snap.data;
          if (art == null) {
            if (!label && snap.connectionState == ConnectionState.done) return const SizedBox();
            return Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    border: Border.all(color: rule), borderRadius: BorderRadius.circular(40)),
                child: Text(row.common,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: serif,
                        fontStyle: FontStyle.italic,
                        fontSize: 13,
                        color: snap.connectionState == ConnectionState.done ? sepia : rule)),
              ),
            );
          }
          return Image.file(
            art.file,
            fit: BoxFit.contain,
            // decode no larger than it is drawn
            cacheWidth: (width * dpr).round(),
            // "Tinted": a plate on its paper is multiplied with the page's
            // paper, so its white becomes the page. A cut-out needs nothing.
            color: art.ready ? null : paper,
            colorBlendMode: art.ready ? null : BlendMode.multiply,
            errorBuilder: (context, _, __) => Center(
                child: Text(row.common,
                    style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, color: sepia))),
          );
        },
      ),
    );
  }
}
