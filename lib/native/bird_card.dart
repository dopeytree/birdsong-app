import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show ink, madder, paper, paperDeep, rule, sepia, serif;
import '../store/detection_store.dart';
import 'collage_view.dart' show PlateImage, calls;
import 'index_view.dart' show thousands;
import 'plate_library.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
String _two(int n) => n.toString().padLeft(2, '0');
String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
bool _sameDay(DateTime a, DateTime b) => _ymd(a) == _ymd(b);

/// The page's when(): "today at 07:42", or "20 November 2026, 07:42".
String whenHeard(DateTime t, {DateTime? now}) {
  final time = '${_two(t.hour)}:${_two(t.minute)}';
  if (_sameDay(t, now ?? DateTime.now())) return 'today at $time';
  return '${t.day} ${_months[t.month - 1]} ${t.year}, $time';
}

/// The page's dayLabel: "20 Nov".
String dayLabel(DateTime t) => '${t.day} ${_months[t.month - 1].substring(0, 3)}';

/// The page's pct: a confidence as "87 in 100".
String inHundred(double c) => '${(c * (c <= 1 ? 100 : 1)).round()} in 100';

/// What the card says about one species, worked out from the detections.
class BirdFacts {
  BirdFacts._(this.sci, this.common, this.heard, this.latest, this.daysKnown);

  /// [heard]: this species' detections on the plate (the session's), any
  /// order; [ever]: every detection of it on this device, for how long it
  /// has been known here.
  factory BirdFacts.of(String sci, String common, List<Detection> heard, List<Detection> ever,
      {DateTime? now}) {
    final mine = [for (final d in heard) if (d.sci == sci) d]..sort((a, b) => b.at.compareTo(a.at));
    DateTime? first;
    for (final d in ever) {
      if (d.sci == sci && (first == null || d.at.isBefore(first))) first = d.at;
    }
    final days = first == null ? 0 : (now ?? DateTime.now()).difference(first).inDays;
    return BirdFacts._(sci, common, mine, mine.take(4).toList(), days);
  }

  final String sci;
  final String common;

  /// Newest first.
  final List<Detection> heard;

  /// The latest four, for the recordings.
  final List<Detection> latest;
  final int daysKnown;

  int get count => heard.length;
  DateTime? get first => heard.isEmpty ? null : heard.last.at;
  DateTime? get last => heard.isEmpty ? null : heard.first.at;
  double get maxConfidence => heard.fold(0, (m, d) => math.max(m, d.confidence));
  double get avgConfidence =>
      heard.isEmpty ? 0 : heard.fold<double>(0, (s, d) => s + d.confidence) / heard.length;

  /// Calls in each hour of the day.
  List<int> get hours {
    final h = List<int>.filled(24, 0);
    for (final d in heard) {
      h[d.at.hour]++;
    }
    return h;
  }

  /// Calls each day for the thirty days to [today], oldest first.
  List<({DateTime day, int count})> trend({DateTime? today}) {
    final end = today ?? DateTime.now();
    final by = <String, int>{};
    for (final d in heard) {
      by[_ymd(d.at)] = (by[_ymd(d.at)] ?? 0) + 1;
    }
    return [
      for (var i = 29; i >= 0; i--)
        (day: DateTime(end.year, end.month, end.day - i), count: by[_ymd(DateTime(end.year, end.month, end.day - i))] ?? 0)
    ];
  }

  /// The card's particulars, in the page's order and words.
  List<(String, String)> get rows => [
        ('Heard', calls(count)),
        if (first != null) ('First heard', whenHeard(first!)),
        if (last != null) ('Last heard', whenHeard(last!)),
        if (maxConfidence > 0) ('Surest identification', inHundred(maxConfidence)),
        if (avgConfidence > 0) ('Usual confidence', inHundred(avgConfidence)),
        if (daysKnown > 0)
          ('Known at this station', daysKnown == 1 ? 'since yesterday' : 'for ${thousands(daysKnown)} days'),
      ];
}

/// The web plate's detail card (#detail), in Flutter: the plate with its
/// credit, the latest recordings with the spectrogram of the newest and a
/// Play for each, the names, a few lines from Wikipedia, the particulars,
/// calls by hour and by day, and the other plates of the species (tap one
/// to make it this bird's plate).
///
/// Two columns, or one on a screen of 720 or less, in the page's ruled
/// dialog.
class BirdCard extends StatefulWidget {
  const BirdCard({
    super.key,
    required this.lib,
    required this.style,
    required this.facts,
    required this.art,
    required this.clipOf,
    required this.spectrogramOf,
    required this.onChosen,
  });

  final PlateLibrary lib;
  final PlateStyle style;
  final BirdFacts facts;
  final PlateArt? art;

  /// A detection's recording and spectrogram on the device.
  final File? Function(Detection) clipOf;
  final File? Function(Detection) spectrogramOf;
  final ValueChanged<PlateArt?> onChosen;

  /// Open the card over [context].
  static Future<void> show(BuildContext context, BirdCard card) => showDialog<void>(
        context: context,
        barrierColor: const Color(0x8C2A241C), // rgba(42,36,28,.55)
        builder: (_) => card,
      );

  @override
  State<BirdCard> createState() => _BirdCardState();
}

class _BirdCardState extends State<BirdCard> {
  late PlateArt? _art = widget.art;
  late final Future<List<PlateCandidate>> _others =
      widget.lib.candidates(widget.facts.sci, widget.facts.common);
  late final Future<({String text, String url})?> _blurb = widget.lib.blurb(widget.facts.sci);
  String? _choosing;

  // One player for the card; the id of the recording playing, if any.
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _done;
  int? _playing;

  @override
  void initState() {
    super.initState();
    // Play alongside a session that is recording and whatever music is on,
    // as the recorder does (engine/listen_engine.dart).
    _player
        .setAudioContext(AudioContext(
          iOS: AudioContextIOS(category: AVAudioSessionCategory.playAndRecord, options: const {
            AVAudioSessionOptions.mixWithOthers,
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.allowBluetoothA2DP,
          }),
          android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
        ))
        .catchError((Object _) {});
    _done = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _done?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(Detection d) async {
    final was = _playing;
    await _player.stop();
    if (!mounted) return;
    setState(() => _playing = null);
    if (was == d.id) return; // that was Stop
    final f = widget.clipOf(d);
    if (f == null) return;
    try {
      await _player.play(DeviceFileSource(f.path));
      if (mounted) setState(() => _playing = d.id);
    } catch (_) {}
  }

  Future<void> _choose(PlateCandidate c) async {
    setState(() => _choosing = c.url);
    final art = await widget.lib.choose(widget.facts.sci, c, widget.style);
    if (!mounted) return;
    setState(() {
      _choosing = null;
      if (art != null) _art = art;
    });
    if (art != null) widget.onChosen(art);
  }

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final narrow = screen.width <= 720;
    final body = narrow ? 16.0 : 18.0;
    final text = TextStyle(fontFamily: serif, fontSize: body, height: 1.5, color: ink);
    final left = _left(text, screen, narrow), right = _right(text);
    return Dialog(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: screen.width * .03, vertical: screen.height * .04),
      shape: const RoundedRectangleBorder(side: BorderSide(color: sepia)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.min(960, screen.width * .94), maxHeight: screen.height * .92),
        child: Stack(
          children: [
            // outline:1px solid rule; outline-offset:-7px
            const Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: DecoratedBox(decoration: BoxDecoration(border: Border.fromBorderSide(BorderSide(color: rule)))),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(28.8),
              child: DefaultTextStyle(
                style: text,
                child: narrow
                    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 16), right])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 105, child: left),
                          const SizedBox(width: 32),
                          Expanded(flex: 100, child: right),
                        ],
                      ),
              ),
            ),
            Positioned(
              top: 14.4,
              right: 17.6,
              child: _Link('Close', onTap: () => Navigator.of(context).pop(), size: body * .95),
            ),
          ],
        ),
      ),
    );
  }

  /// The plate, its credit, and the latest recordings.
  Widget _left(TextStyle text, Size screen, bool narrow) {
    final art = _art, f = widget.facts;
    final caption = TextStyle(fontFamily: serif, fontSize: text.fontSize! * .82, height: 1.35, color: sepia);
    final spec = f.latest.isEmpty ? null : widget.spectrogramOf(f.latest.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (art != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screen.height * (narrow ? .45 : .52)),
            child: PlateImage(art: art, width: math.min(500, screen.width * .9)),
          ),
        const SizedBox(height: 8),
        Text.rich(
          art == null
              ? const TextSpan(text: 'No plate has been found for this species.')
              : TextSpan(text: art.credit, children: [
                  if (art.from.page != null) ...[
                    const TextSpan(text: ' '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _Link('View the source', onTap: () => _open(art.from.page!), size: caption.fontSize!, italic: false),
                    ),
                  ],
                ]),
          style: caption,
        ),
        if (f.latest.isNotEmpty) ...[
          const SizedBox(height: 19.2),
          _small('Latest recordings', text),
          if (spec != null) _Spectrogram(spec),
          const DecoratedBox(decoration: BoxDecoration(border: Border(top: BorderSide(color: rule)))),
          for (final d in f.latest) _recording(d, text),
          const SizedBox(height: 17.6),
        ],
      ],
    );
  }

  Widget _recording(Detection d, TextStyle text) {
    final size = text.fontSize! * .95;
    final clip = widget.clipOf(d);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4.8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: rule))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (clip != null) ...[
            SizedBox(
              width: size * 2.6,
              child: Semantics(
                label: '${_playing == d.id ? 'Stop' : 'Play'} the recording from ${dayLabel(d.at)} at ${_two(d.at.hour)}:${_two(d.at.minute)}',
                excludeSemantics: true,
                child: _Link(_playing == d.id ? 'Stop' : 'Play', onTap: () => _play(d), size: size, color: madder),
              ),
            ),
            SizedBox(width: size * .8),
          ],
          Text('${dayLabel(d.at)}, ${_two(d.at.hour)}:${_two(d.at.minute)}', style: TextStyle(fontSize: size)),
          SizedBox(width: size * .8),
          Text(inHundred(d.confidence), style: TextStyle(fontSize: size)),
        ],
      ),
    );
  }

  /// Names, Wikipedia, particulars, the two bar charts, other plates.
  Widget _right(TextStyle text) {
    final f = widget.facts, size = text.fontSize!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: size * .6),
        // a little short of the Close link
        Padding(
          padding: const EdgeInsets.only(right: 48),
          child: Text(f.common, style: TextStyle(fontSize: size * 2 * 16 / 18, height: 1.1)),
        ),
        SizedBox(height: size * .15),
        Text(f.sci, style: TextStyle(fontStyle: FontStyle.italic, color: sepia, fontSize: size * 1.15 * 16 / 18)),
        SizedBox(height: size * .6),
        FutureBuilder<({String text, String url})?>(
          future: _blurb,
          builder: (context, snap) {
            final b = snap.data;
            if (b == null || b.text.isEmpty) return const SizedBox();
            return Padding(
              padding: EdgeInsets.only(bottom: size),
              child: Text.rich(
                TextSpan(text: b.text, children: [
                  if (b.url.isNotEmpty) ...[
                    const TextSpan(text: ' '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _Link('Wikipedia', onTap: () => _open(b.url), size: size * .85, underline: false),
                    ),
                  ],
                ]),
                style: const TextStyle(height: 1.4),
              ),
            );
          },
        ),
        _particulars(f, text),
        SizedBox(height: size * 1.2),
        _small('Calls by hour of the day, over this period', text),
        _Bars(
          values: f.hours,
          label: (i, n) => '$i:00, ${calls(n)}',
        ),
        _BarLabels(const ['midnight', '6', 'noon', '18', '24'], size),
        _small('Calls each day, the last thirty days', text),
        Builder(builder: (context) {
          final days = f.trend();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Bars(values: [for (final d in days) d.count], label: (i, n) => '${dayLabel(days[i].day)}, ${calls(n)}'),
              _BarLabels([dayLabel(days.first.day), 'today'], size),
            ],
          );
        }),
        _alternatives(text),
      ],
    );
  }

  /// The page's dl: name in italic sepia, value beside it; the count large
  /// and in madder; ruled above and below.
  Widget _particulars(BirdFacts f, TextStyle text) {
    final size = text.fontSize!;
    final rows = f.rows;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9.6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: rule), bottom: BorderSide(color: rule)),
      ),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (var i = 0; i < rows.length; i++)
            TableRow(children: [
              Padding(
                padding: EdgeInsets.only(right: 19.2, bottom: i == rows.length - 1 ? 0 : 2.4),
                child: Text(rows[i].$1, style: const TextStyle(fontStyle: FontStyle.italic, color: sepia)),
              ),
              Text(rows[i].$2,
                  style: i == 0 ? TextStyle(color: madder, fontSize: size * 1.3 * 16 / 18, height: 1.2) : null),
            ]),
        ],
      ),
    );
  }

  Widget _alternatives(TextStyle text) => FutureBuilder<List<PlateCandidate>>(
        future: _others,
        builder: (context, snap) {
          final all = snap.data ?? const <PlateCandidate>[];
          final art = _art;
          // as the page: shown when there is a choice to make
          if (all.length < 2 && !(all.length == 1 && (art == null || art.from.url != all.first.url))) {
            return const SizedBox();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _small('Other plates of this species', text),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in all)
                    _Alt(
                      lib: widget.lib,
                      style: widget.style,
                      candidate: c,
                      on: art?.from.url == c.url,
                      busy: _choosing == c.url,
                      onTap: _choosing == null && art?.from.url != c.url ? () => _choose(c) : null,
                    ),
                ],
              ),
            ],
          );
        },
      );

  Widget _small(String s, TextStyle text) => Padding(
        padding: const EdgeInsets.only(bottom: 6.4),
        child: Text(s,
            style: TextStyle(fontSize: text.fontSize! * .92, color: sepia, fontStyle: FontStyle.italic)),
      );
}

/// An underlined word that does something: Close, Play, View the source.
class _Link extends StatelessWidget {
  const _Link(this.text,
      {required this.onTap, required this.size, this.color = sepia, this.italic = true, this.underline = true});

  final String text;
  final VoidCallback onTap;
  final double size;
  final Color color;
  final bool italic;
  final bool underline;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Text(text,
                style: TextStyle(
                  fontFamily: serif,
                  fontSize: size,
                  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                  color: color,
                  decoration: underline ? TextDecoration.underline : null,
                  decorationColor: color,
                )),
          ),
        ),
      );
}

/// The newest recording's spectrogram: a band 5.5rem tall, ruled in sepia,
/// greyed and warmed (the page's grayscale(1) sepia(.7) contrast(1.15)).
class _Spectrogram extends StatelessWidget {
  const _Spectrogram(this.file);

  final File file;

  // grayscale, then sepia at .7, then contrast 1.15, as one matrix
  static final ColorFilter _filter = () {
    List<double> mul(List<double> a, List<double> b) => [
          for (var r = 0; r < 4; r++)
            for (var c = 0; c < 5; c++)
              a[r * 5] * b[c] + a[r * 5 + 1] * b[5 + c] + a[r * 5 + 2] * b[10 + c] + a[r * 5 + 3] * b[15 + c] +
                  (c == 4 ? a[r * 5 + 4] : 0),
        ];
    const grey = <double>[
      .2126, .7152, .0722, 0, 0, //
      .2126, .7152, .0722, 0, 0,
      .2126, .7152, .0722, 0, 0,
      0, 0, 0, 1, 0,
    ];
    const s = .7;
    final sepiaM = <double>[
      .393 + .607 * (1 - s), .769 - .769 * (1 - s), .189 - .189 * (1 - s), 0, 0, //
      .349 - .349 * (1 - s), .686 + .314 * (1 - s), .168 - .168 * (1 - s), 0, 0,
      .272 - .272 * (1 - s), .534 - .534 * (1 - s), .131 + .869 * (1 - s), 0, 0,
      0, 0, 0, 1, 0,
    ];
    const k = 1.15, o = (1 - 1.15) / 2 * 255;
    const contrast = <double>[
      k, 0, 0, 0, o, //
      0, k, 0, 0, o,
      0, 0, k, 0, o,
      0, 0, 0, 1, 0,
    ];
    return ColorFilter.matrix(mul(contrast, mul(sepiaM, grey)));
  }();

  @override
  Widget build(BuildContext context) => Container(
        height: 88,
        margin: const EdgeInsets.only(bottom: 4.8),
        decoration: BoxDecoration(border: Border.all(color: sepia)),
        child: ColorFiltered(
          colorFilter: _filter,
          child: Image.file(file, fit: BoxFit.fill, width: double.infinity, errorBuilder: (_, __, ___) => const SizedBox()),
        ),
      );
}

/// The page's .bars: hatched columns with a rule on top, on a sepia base.
class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.label});

  final List<int> values;
  final String Function(int i, int n) label;

  @override
  Widget build(BuildContext context) {
    final top = math.max(1, values.fold<int>(0, (a, b) => a > b ? a : b));
    return Container(
      height: 67.2,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: sepia))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: Tooltip(
                message: label(i, values[i]),
                child: FractionallySizedBox(
                  heightFactor: values[i] / top,
                  alignment: Alignment.bottomCenter,
                  child: values[i] == 0 ? const SizedBox(width: double.infinity) : const CustomPaint(painter: _Hatch()),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// repeating-linear-gradient(135deg, sepia 0 1px, transparent 1px 3px),
/// with a border on top.
class _Hatch extends CustomPainter {
  const _Hatch();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = sepia
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // lines of slope +1 every 3px across, as 135deg stripes run
    for (var x = -size.height; x < size.width; x += 3 * math.sqrt2) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
    canvas.drawLine(Offset.zero, Offset(size.width, 0), p);
  }

  @override
  bool shouldRepaint(_Hatch old) => false;
}

class _BarLabels extends StatelessWidget {
  const _BarLabels(this.labels, this.size);

  final List<String> labels;
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 2, bottom: size * 1.1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final l in labels) Text(l, style: TextStyle(fontSize: size * .8, color: sepia)),
          ],
        ),
      );
}

/// One of the other plates: 4.4 by 5.6rem on the deeper paper, ringed in
/// madder when it is the one in use.
class _Alt extends StatefulWidget {
  const _Alt({
    required this.lib,
    required this.style,
    required this.candidate,
    required this.on,
    required this.busy,
    required this.onTap,
  });

  final PlateLibrary lib;
  final PlateStyle style;
  final PlateCandidate candidate;
  final bool on;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_Alt> createState() => _AltState();
}

class _AltState extends State<_Alt> {
  late final Future<PlateArt?> _art =
      widget.lib.load(widget.candidate, widget.style).then<PlateArt?>((a) => a).catchError((Object _) => null);

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.candidate.credit,
        child: Semantics(
          button: true,
          selected: widget.on,
          label: 'Another plate',
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 70.4,
              height: 89.6,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: paperDeep,
                border: Border.all(color: widget.on ? madder : rule, width: widget.on ? 2 : 1),
              ),
              child: widget.busy
                  ? const Center(
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: madder)))
                  : FutureBuilder<PlateArt?>(
                      future: _art,
                      builder: (context, snap) =>
                          snap.data == null ? const SizedBox() : PlateImage(art: snap.data!, width: 66),
                    ),
            ),
          ),
        ),
      );
}
