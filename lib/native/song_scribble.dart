import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/listen_engine.dart';
import '../engine/scribble_trace.dart';
import '../main.dart' show sepia, serif;

/// The song scribble: along the bottom of the plate, between the buttons,
/// a pencil line drawn from the sound as it is heard, drifting to the left,
/// with the bird being heard named in a gap in the middle. A faint resting
/// line while not listening. Settings > Display > Song scribble.
class SongScribble extends StatefulWidget {
  const SongScribble({super.key, required this.engine});

  final ListenEngine engine;

  @override
  State<SongScribble> createState() => _SongScribbleState();
}

class _SongScribbleState extends State<SongScribble> with SingleTickerProviderStateMixin {
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
      TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 16, height: 1, color: sepia);

  @override
  void initState() {
    super.initState();
    _head = widget.engine.scribble.count.toDouble();
    widget.engine.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    widget.engine.removeListener(_changed);
    _ticker.dispose();
    super.dispose();
  }

  void _changed() {
    final on = widget.engine.running;
    if (on && !_ticker.isActive) {
      _last = Duration.zero;
      _head = widget.engine.scribble.count.toDouble();
      _ticker.start();
    } else if (!on && _ticker.isActive) {
      _ticker.stop();
      setState(() {
        _head = widget.engine.scribble.count.toDouble();
        _open = 0;
        _name = null;
      });
    }
  }

  void _frame(Duration t) {
    final dt = _last == Duration.zero ? 0.0 : (t - _last).inMicroseconds / 1e6;
    _last = t;
    final count = widget.engine.scribble.count.toDouble();
    _head = (_head + dt * 1000 / ScribbleTrace.sliceMs).clamp(count - 12, count).toDouble();
    final live = widget.engine.liveName;
    if (live != null) _name = live;
    _open = (_open + (live != null ? dt : -dt) / .45).clamp(0.0, 1.0);
    if (_open == 0) _name = null;
    // about sixty a second is plenty, even on a faster screen
    if (t - _painted < const Duration(milliseconds: 15)) return;
    _painted = t;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final trace = widget.engine.scribble;
        // the head can lag 12 slices behind: keep the window inside what is kept
        final shown = math.min(trace.capacity - 16, math.max(8, (w / ScribbleTrace.unit).round()));
        final from = _head - shown;
        final base = from.floor();
        final win = trace.window(base, shown + 2);
        final name = _name;
        var gap = 0.0;
        if (name != null) {
          if (name != _measured || w != _measuredAt) {
            final tp = TextPainter(
                text: TextSpan(text: name, style: _nameStyle),
                maxLines: 1,
                textDirection: TextDirection.ltr)
              ..layout(maxWidth: math.max(0, w - 60));
            _measured = name;
            _measuredAt = w;
            _nameWidth = tp.width;
            tp.dispose();
          }
          gap = (_nameWidth + 18) * Curves.easeInOut.transform(_open);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: SongScribblePainter(
                  level: win.level,
                  pitch: win.pitch,
                  phase: win.phase,
                  base: base.toDouble(),
                  shift: from - base,
                  gap: gap,
                ),
              ),
            ),
            if (name != null)
              Center(
                child: Opacity(
                  opacity: Curves.easeIn.transform(_open),
                  child: Semantics(
                    liveRegion: true,
                    label: 'Hearing $name',
                    child: ExcludeSemantics(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: math.max(0, w - 60)),
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _nameStyle),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
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
