import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/listen_engine.dart';
import '../engine/scribble_trace.dart';
import '../main.dart' show ink, paper, rule, sepia, serif;
import '../ui/paper_surface.dart';

/// The song scribble: along the bottom of the plate, between the buttons,
/// a pencil line drawn from the sound as it is heard, drifting to the left,
/// with the latest detected bird shown in a crisp paper ticket (or plain
/// italic text) in the middle gap — consistently for both local and remote.
class SongScribble extends StatefulWidget {
  const SongScribble({
    super.key,
    required this.engine,
    this.showLine = true,
    this.simpleWave = false,
    this.remote = false,
    this.latestName,
    this.showLatest = true,
    this.useTicket = true,
    this.onTapLatest,
  });

  final ListenEngine engine;
  final bool showLine;
  final bool simpleWave;
  final bool remote;

  /// Latest detected species name in the active local session or remote feed.
  final String? latestName;

  /// Whether to show the latest detected bird along the bottom at all.
  final bool showLatest;

  /// Whether to draw the latest detection inside a paper ticket box.
  final bool useTicket;

  /// Optional tap callback to open the latest detected bird's card.
  final VoidCallback? onTapLatest;

  @override
  State<SongScribble> createState() => _SongScribbleState();
}

class _SongScribbleState extends State<SongScribble> with SingleTickerProviderStateMixin {
  /// A quiet trace shared by remote views so they draw the exact same resting
  /// line as local mode when not recording.
  static final ScribbleTrace _quiet = ScribbleTrace();

  late final Ticker _ticker = createTicker(_frame);
  Duration _last = Duration.zero, _painted = Duration.zero;

  /// The right-hand end of the line, in slices: it follows the sound
  /// smoothly, a little behind, rather than jumping as each chunk arrives.
  double _head = 0;

  /// The name's gap, 0 (shut) to 1 (open), and the name in it.
  double _open = 0;
  String? _name;

  // The name's width, kept until the name or the room changes.
  String? _measured;
  double _measuredAt = 0, _nameWidth = 0;

  static const _nameStyle =
      TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15, height: 1.15, color: ink);

  ScribbleTrace get _trace => widget.remote ? _quiet : widget.engine.scribble;

  String? get _activeLabel {
    if (!widget.showLatest) return null;
    if (!widget.remote && widget.engine.liveName != null) return widget.engine.liveName;
    return widget.latestName;
  }

  @override
  void initState() {
    super.initState();
    _head = _trace.count.toDouble();
    final initial = _activeLabel;
    if (initial != null) {
      _name = initial;
      _open = 1.0;
    }
    widget.engine.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(SongScribble old) {
    super.didUpdateWidget(old);
    if (old.remote != widget.remote) {
      _head = _trace.count.toDouble();
    }
    if (old.remote != widget.remote ||
        old.latestName != widget.latestName ||
        old.showLatest != widget.showLatest ||
        old.useTicket != widget.useTicket) {
      final target = _activeLabel;
      if (target != null) _name = target;
      _changed();
    }
  }

  @override
  void dispose() {
    widget.engine.removeListener(_changed);
    _ticker.dispose();
    super.dispose();
  }

  void _changed() {
    final target = _activeLabel;
    final want = target != null ? 1.0 : 0.0;
    final running = !widget.remote && widget.engine.running;
    final needAnim = running || (_open - want).abs() > 0.001;
    if (needAnim && !_ticker.isActive) {
      _last = Duration.zero;
      _head = _trace.count.toDouble();
      _ticker.start();
    } else if (!needAnim && _ticker.isActive) {
      _ticker.stop();
      setState(() {
        _head = _trace.count.toDouble();
        _open = want;
        _name = target;
      });
    } else if (!needAnim) {
      if (mounted) {
        setState(() {
          _open = want;
          _name = target;
        });
      }
    }
  }

  void _frame(Duration t) {
    final dt = _last == Duration.zero ? 0.0 : (t - _last).inMicroseconds / 1e6;
    _last = t;
    final running = !widget.remote && widget.engine.running;
    if (running) {
      final count = widget.engine.scribble.count.toDouble();
      _head = (_head + dt * 1000 / ScribbleTrace.sliceMs).clamp(count - 12, count).toDouble();
    }
    final target = _activeLabel;
    if (target != null) _name = target;
    final want = target != null ? 1.0 : 0.0;
    _open = (_open + (want > _open ? dt : -dt) / .35).clamp(0.0, 1.0);
    if (_open == 0) _name = null;
    if (!running && (_open - want).abs() <= 0.001) {
      _open = want;
      _ticker.stop();
      setState(() {});
      return;
    }
    // about 60 fps for pencil scribble, 30 fps for the lighter wave mode
    final frameMs = widget.simpleWave ? 32 : 15;
    if (t - _painted < Duration(milliseconds: frameMs)) return;
    _painted = t;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final trace = _trace;
      // the head can lag 12 slices behind: keep the window inside what is kept
      final shown = math.min(trace.capacity - 16, math.max(8, (w / ScribbleTrace.unit).round()));
      final from = _head - shown;
      final base = from.floor();
      final win = trace.window(base, shown + 2);
      final name = _name;
      final ticketExtra = widget.useTicket ? 26.0 : 18.0;
      var gap = 0.0;
      if (name != null && _open > 0) {
        if (name != _measured || w != _measuredAt) {
          final tp = TextPainter(
              text: TextSpan(text: name, style: _nameStyle),
              maxLines: 1,
              textDirection: TextDirection.ltr)
            ..layout(maxWidth: math.max(0, w - 48));
          _measured = name;
          _measuredAt = w;
          _nameWidth = tp.width;
          tp.dispose();
        }
        gap = (_nameWidth + ticketExtra) * Curves.easeInOut.transform(_open);
      }
      final nameStyle = widget.useTicket
          ? _nameStyle
          : (widget.simpleWave ? _nameStyle.copyWith(color: ink) : _nameStyle.copyWith(color: sepia));
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.showLine)
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: widget.simpleWave
                      ? SimpleWavePainter(
                          level: win.level,
                          shift: from - base,
                          gap: gap,
                        )
                      : SongScribblePainter(
                          level: win.level,
                          pitch: win.pitch,
                          phase: win.phase,
                          base: base.toDouble(),
                          shift: from - base,
                          gap: gap,
                        ),
                ),
              ),
            ),
          if (name != null && _open > 0.01)
            Center(
              child: Opacity(
                opacity: Curves.easeIn.transform(_open),
                child: Semantics(
                  liveRegion: true,
                  button: widget.onTapLatest != null,
                  label: 'Latest detection: $name',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onTapLatest == null
                        ? null
                        : () {
                            hapticTap();
                            widget.onTapLatest!();
                          },
                    child: MouseRegion(
                      cursor: widget.onTapLatest != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: math.max(0, w - 40)),
                        child: widget.useTicket
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: paper.withValues(alpha: 0.92),
                                  border: Border.all(color: rule, width: 0.9),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x222A241C), offset: Offset(0, 2), blurRadius: 6),
                                  ],
                                ),
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: nameStyle,
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: nameStyle,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// A pencil scribble of the sound being heard. Art, not a measurement:
/// louder sound presses harder and loops taller; higher sound makes
/// quicker, tighter marks. Quiet, it is a faint resting line with a tremor.
/// A second, fainter pass runs just off the first, as a pencil gone over
/// twice.
///
/// [level] and [pitch] are 0 to 1 per slice, oldest first; [phase] is the
/// pencil's swing at each (from [ScribbleTrace]; worked out here when not
/// given). Slice [shift] (0 to 1) is at the left edge and the line runs
/// across all but the last; [base] numbers the first slice, so the wobble
/// travels with the sound. [gap] keeps the middle clear for a bird's name;
/// the line eases down to rest either side of it.
class SongScribblePainter extends CustomPainter {
  const SongScribblePainter({
    required this.level,
    required this.pitch,
    this.phase,
    this.base = 0,
    this.shift = 0,
    this.gap = 0,
    this.color = sepia,
  });

  final List<double> level;
  final List<double> pitch;
  final List<double>? phase;
  final double base;
  final double shift;
  final double gap;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || level.length < 3) return;
    final swing = phase ?? _phaseOf();
    _pass(canvas, size, swing, seed: 0, alpha: 1, width: 1, lift: 0);
    _pass(canvas, size, swing, seed: 37.3, alpha: .32, width: .7, lift: .7);
  }

  List<double> _phaseOf() {
    final out = List<double>.filled(level.length, 0);
    for (var k = 1; k < level.length; k++) {
      out[k] = out[k - 1] +
          ScribbleTrace.swing(level[k - 1], pitch[k - 1], (base + k - 1) * ScribbleTrace.unit) *
              ScribbleTrace.unit;
    }
    return out;
  }

  void _pass(Canvas canvas, Size size, List<double> swing,
      {required double seed, required double alpha, required double width, required double lift}) {
    final w = size.width, mid = size.height / 2 + lift;
    final span = level.length - 2;
    final steps = (w * 3).ceil();
    final dx = w / steps;
    final half = gap / 2;
    final pts = <Offset>[];
    final press = <double>[];
    final noise = ScribbleTrace.noise;
    for (var i = 0; i <= steps; i++) {
      final x0 = i * dx;
      final s = shift + x0 / w * span;
      final xa = (base + s) * ScribbleTrace.unit; // where along the sound
      var a = _at(level, s);
      final p = _at(pitch, s);
      final theta = _at(swing, s) + seed;
      // ease down to rest at the ends and either side of the name
      final edge = _smooth(math.min(x0, w - x0) / 14);
      final fromMid = (x0 - w / 2).abs();
      final clear = gap <= 0 ? 1.0 : _smooth((fromMid - half) / 16);
      a *= edge * clear;
      if (gap > 0 && fromMid < half) {
        pts.add(Offset.infinite);
        press.add(0);
        continue;
      }
      final n1 = noise(xa * .072 + seed);
      final n2 = noise(xa * .5 + seed * 2);
      // loops: the pencil runs back on itself when it presses hard; the
      // loops' size and height wander, as a hand's would
      final r = a * (7 - 3.5 * p) * (.55 + .7 * (noise(theta * .21 + seed * .1) * .5 + .5));
      final x = x0 + r * math.cos(theta) + n2 * .35;
      final tall = .9 + a * size.height * .42 * (.5 + .7 * (noise(theta * .37 + 9) * .5 + .5));
      final wander = noise(theta * .13 + 4) * a * 4;
      final y = mid + wander + tall * math.sin(theta) * (a > .04 ? 1 : .55) + n1 * 1.1 + n2 * .35;
      pts.add(Offset(x, y));
      press.add(edge * (.38 + .62 * math.min(1.0, a * 1.4)));
    }
    // short runs, each with its own weight and darkness: pencil grain
    const run = 12;
    final path = Path();
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i + 1 < pts.length; i += run) {
      path.reset();
      var started = false;
      var sum = 0.0, count = 0;
      for (var j = i; j <= math.min(i + run, pts.length - 1); j++) {
        final q = pts[j];
        if (q == Offset.infinite) {
          started = false;
          continue;
        }
        started ? path.lineTo(q.dx, q.dy) : path.moveTo(q.dx, q.dy);
        started = true;
        sum += press[j];
        count++;
      }
      if (count < 2) continue;
      // grain tied to the sound's place, so it travels with the line
      final g = noise((base + shift + i / steps * span) * .9 + seed * 5);
      final k = sum / count;
      pen
        ..strokeWidth = width * (.55 + .35 * k + .18 * g)
        ..color = color.withValues(alpha: (alpha * k * (.82 + .18 * g)).clamp(0.0, 1.0));
      canvas.drawPath(path, pen);
    }
  }

  static double _at(List<double> v, double s) {
    final f = s.clamp(0.0, v.length - 1.0);
    final i = f.floor(), t = f - i;
    final b = v[math.min(i + 1, v.length - 1)];
    return v[i] + (b - v[i]) * t;
  }

  static double _smooth(double t) {
    final c = t.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  @override
  bool shouldRepaint(SongScribblePainter old) =>
      old.level != level || old.pitch != pitch || old.phase != phase || old.shift != shift || old.gap != gap;
}

/// A lightweight single-pass black waveform for less capable / mobile devices.
/// Draws one [Path] with one [Canvas.drawPath] call and no per-pixel noise.
class SimpleWavePainter extends CustomPainter {
  const SimpleWavePainter({
    required this.level,
    this.shift = 0,
    this.gap = 0,
    this.color = ink,
  });

  final List<double> level;
  final double shift;
  final double gap;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || level.length < 3) return;
    final w = size.width, mid = size.height / 2;
    final span = level.length - 2;
    final half = gap / 2;
    const step = 3.0;
    final path = Path();
    // Resting baseline (split cleanly around the name gap)
    if (gap <= 0) {
      path
        ..moveTo(0, mid)
        ..lineTo(w, mid);
    } else {
      final leftEnd = math.max(0.0, w / 2 - half);
      final rightStart = math.min(w, w / 2 + half);
      if (leftEnd > 0) {
        path
          ..moveTo(0, mid)
          ..lineTo(leftEnd, mid);
      }
      if (rightStart < w) {
        path
          ..moveTo(rightStart, mid)
          ..lineTo(w, mid);
      }
    }
    for (var x = 1.5; x < w; x += step) {
      final fromMid = (x - w / 2).abs();
      if (gap > 0 && fromMid < half) continue;
      final s = shift + x / w * span;
      var a = SongScribblePainter._at(level, s);
      final edge = SongScribblePainter._smooth(math.min(x, w - x) / 14);
      final clear = gap <= 0 ? 1.0 : SongScribblePainter._smooth((fromMid - half) / 16);
      a *= edge * clear;
      final h = a * size.height * .44;
      if (h > .6) {
        path
          ..moveTo(x, mid - h)
          ..lineTo(x, mid + h);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(SimpleWavePainter old) =>
      old.level != level || old.shift != shift || old.gap != gap || old.color != color;
}
