import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The plate's own icons, drawn to sit with its engravings: fine lines with
/// round ends, shading by hatching, one colour. In place of Material's.
///
/// Each is drawn in a box of 24 units from a few marks written as SVG path
/// data, so tool/icon_preview.py can draw the same marks for a look at them
/// outside the app.
enum PlateGlyph {
  /// Listen here: an old microphone on its stand.
  listen,

  /// A remote station: a nest box on a post, heard from afar.
  station,

  /// Record a new session: a dot inside a ring.
  record,

  /// Stop recording.
  stop,

  /// Settings: three rules, an ornament in the middle one.
  menu,

  /// The plate and its views: a bird in a ruled frame.
  plate,

  /// The walk on a map: a folded sheet, a dotted trail, a cross.
  map,

  /// Share the plate.
  share,

  /// Save the plate to Photos.
  save,

  /// The list of stations.
  list,

  /// The other of two stations.
  swap,

  /// An earlier session.
  prev,

  /// A later session.
  next,
}

/// How a mark is drawn.
enum Ink {
  /// The main line.
  stroke,

  /// A finer line, for detail.
  fine,

  /// Filled solid.
  fill,

  /// Shaded with fine parallel lines at [Mark.angle] degrees.
  hatch,

  /// A dotted line.
  dots,
}

/// One mark of an icon: SVG path data in a box of 24 units.
class Mark {
  const Mark(this.ink, this.d, {this.angle = 45});

  final Ink ink;
  final String d;

  /// For [Ink.hatch]: the lines' angle, in degrees from the horizontal.
  final double angle;
}

/// Line weights and the hatching's spacing, in units of the 24 box.
const double strokeWeight = 1.15, fineWeight = .7, hatchWeight = .5, hatchGap = 1.5, dotGap = 1.9;

const plateGlyphs = <PlateGlyph, List<Mark>>{
  PlateGlyph.listen: [
    Mark(Ink.hatch, 'M9 6.5A3 3 0 0 1 15 6.5V10A3 3 0 0 1 9 10Z', angle: 0),
    Mark(Ink.stroke, 'M9 6.5A3 3 0 0 1 15 6.5V10A3 3 0 0 1 9 10Z'),
    Mark(Ink.stroke, 'M6.2 9.6V10.4A5.8 5.8 0 0 0 17.8 10.4V9.6'),
    Mark(Ink.stroke, 'M12 16.2V20.3'),
    Mark(Ink.stroke, 'M8.6 20.6H15.4'),
  ],
  PlateGlyph.station: [
    Mark(Ink.hatch, 'M6.6 9.2L12 4.2L17.4 9.2Z', angle: 60),
    Mark(Ink.stroke, 'M6.2 9.4L12 4.1L17.8 9.4'),
    Mark(Ink.stroke, 'M8.2 8.6V17H15.8V8.6'),
    Mark(Ink.fill, 'M10.5 11.3A1.5 1.5 0 1 0 13.5 11.3A1.5 1.5 0 1 0 10.5 11.3Z'),
    Mark(Ink.fine, 'M11 14.4H13'),
    Mark(Ink.stroke, 'M12 17V21.4'),
    Mark(Ink.stroke, 'M19.8 7A5.4 5.4 0 0 1 19.8 15'),
    Mark(Ink.stroke, 'M4.2 7A5.4 5.4 0 0 0 4.2 15'),
  ],
  PlateGlyph.record: [
    Mark(Ink.fill, 'M7 12A5 5 0 1 0 17 12A5 5 0 1 0 7 12Z'),
    Mark(Ink.fine, 'M4 12A8 8 0 1 0 20 12A8 8 0 1 0 4 12Z'),
  ],
  PlateGlyph.stop: [
    Mark(Ink.fill, 'M8 8H16V16H8Z'),
    Mark(Ink.fine, 'M5 5H19V19H5Z'),
  ],
  PlateGlyph.menu: [
    Mark(Ink.stroke, 'M4.5 6.8H19.5'),
    Mark(Ink.stroke, 'M4.5 12H9.8'),
    Mark(Ink.fill, 'M12 10.2L13.8 12L12 13.8L10.2 12Z'),
    Mark(Ink.stroke, 'M14.2 12H19.5'),
    Mark(Ink.stroke, 'M4.5 17.2H19.5'),
  ],
  PlateGlyph.plate: [
    Mark(Ink.stroke, 'M3.8 3.5H20.2V20.5H3.8Z'),
    Mark(Ink.fine, 'M5.5 5.2H18.5V18.8H5.5Z'),
    Mark(Ink.hatch,
        'M17.6 9.5C17 8.3 16.1 7.2 14.7 7.2C13 7.2 12.3 8.5 11.7 9.7C10.6 11.2 8.8 12.3 6.6 13.7'
        'L6 15.1L8.7 14.5C10.2 15.6 13.6 15.5 15 13.2C15.8 11.9 16 10.7 16.6 10.1Z', angle: 125),
    Mark(Ink.fine,
        'M17.6 9.5C17 8.3 16.1 7.2 14.7 7.2C13 7.2 12.3 8.5 11.7 9.7C10.6 11.2 8.8 12.3 6.6 13.7'
        'L6 15.1L8.7 14.5C10.2 15.6 13.6 15.5 15 13.2C15.8 11.9 16 10.7 16.6 10.1Z'),
    Mark(Ink.fill, 'M14.75 8.9A.55 .55 0 1 0 15.85 8.9A.55 .55 0 1 0 14.75 8.9Z'),
    Mark(Ink.fine, 'M11.6 15.3L11.2 16.6M12.9 15.2V16.5'),
    Mark(Ink.fine, 'M6.6 17C9.6 16.3 13.4 16.6 17.6 15.8'),
  ],
  PlateGlyph.map: [
    Mark(Ink.stroke, 'M3.5 6L9 4L15 6L20.5 4V18L15 20L9 18L3.5 20Z'),
    Mark(Ink.fine, 'M9 4V18M15 6V20'),
    Mark(Ink.dots, 'M5.8 16.4C7.6 13.6 9.6 15.6 11.6 12.6C13 10.4 14.4 11.6 15.6 10.4'),
    Mark(Ink.stroke, 'M16.2 7.2L18.8 9.8M18.8 7.2L16.2 9.8'),
  ],
  PlateGlyph.share: [
    Mark(Ink.stroke, 'M9 9.8H6.4V20.6H17.6V9.8H15'),
    Mark(Ink.hatch, 'M6.4 17.6H17.6V20.6H6.4Z', angle: 60),
    Mark(Ink.stroke, 'M12 15V3.6'),
    Mark(Ink.stroke, 'M8.8 6.8L12 3.6L15.2 6.8'),
  ],
  PlateGlyph.save: [
    Mark(Ink.stroke, 'M4 8.5V20.5H20V8.5'),
    Mark(Ink.hatch, 'M4 17.5H20V20.5H4Z', angle: 60),
    Mark(Ink.stroke, 'M12 3.4V14.6'),
    Mark(Ink.stroke, 'M8.8 11.4L12 14.6L15.2 11.4'),
  ],
  PlateGlyph.list: [
    Mark(Ink.fill, 'M4 6.8L5.4 5.4L6.8 6.8L5.4 8.2Z'),
    Mark(Ink.stroke, 'M9 6.8H20'),
    Mark(Ink.fill, 'M4 12L5.4 10.6L6.8 12L5.4 13.4Z'),
    Mark(Ink.stroke, 'M9 12H20'),
    Mark(Ink.fill, 'M4 17.2L5.4 15.8L6.8 17.2L5.4 18.6Z'),
    Mark(Ink.stroke, 'M9 17.2H20'),
  ],
  PlateGlyph.swap: [
    Mark(Ink.stroke, 'M4.5 8.6H18.5'),
    Mark(Ink.stroke, 'M15.4 5.5L18.5 8.6L15.4 11.7'),
    Mark(Ink.stroke, 'M19.5 15.4H5.5'),
    Mark(Ink.stroke, 'M8.6 12.3L5.5 15.4L8.6 18.5'),
  ],
  PlateGlyph.prev: [
    Mark(Ink.stroke, 'M14.6 5.6L8.6 12L14.6 18.4'),
  ],
  PlateGlyph.next: [
    Mark(Ink.stroke, 'M9.4 5.6L15.4 12L9.4 18.4'),
  ],
};

/// One of the plate's icons, where a Material [Icon] would go. Its size and
/// colour come from the surrounding [IconTheme] (an [IconButton] sets
/// both), unless given.
class PlateIcon extends StatelessWidget {
  const PlateIcon(this.glyph, {super.key, this.size, this.color});

  final PlateGlyph glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    var color = this.color ?? theme.color ?? const Color(0xFF2A241C);
    final opacity = theme.opacity;
    if (opacity != null && opacity < 1) color = color.withValues(alpha: color.a * opacity);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GlyphPainter(glyph, color)),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final PlateGlyph glyph;
  final Color color;

  // Parsed once for all icons.
  static final Map<String, Path> _paths = {};

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 24;
    canvas.save();
    canvas.translate((size.width - 24 * k) / 2, (size.height - 24 * k) / 2);
    canvas.scale(k);
    // Phones draw two or three pixels to each of these, so a hatching line
    // of half a unit still shows at the pill's size; only keep the finest
    // from vanishing altogether when an icon is very small.
    double weight(double w) => math.max(w, .4 / k);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final m in plateGlyphs[glyph]!) {
      final path = _paths.putIfAbsent(m.d, () => parseSvgPath(m.d));
      switch (m.ink) {
        case Ink.stroke:
          canvas.drawPath(path, line..strokeWidth = weight(strokeWeight));
        case Ink.fine:
          canvas.drawPath(path, line..strokeWidth = weight(fineWeight));
        case Ink.fill:
          canvas.drawPath(path, Paint()..color = color);
        case Ink.hatch:
          _hatch(canvas, path, m.angle, line..strokeWidth = weight(hatchWeight));
        case Ink.dots:
          _dots(canvas, path, Paint()..color = color, weight(strokeWeight) * .5);
      }
    }
    canvas.restore();
  }

  void _hatch(Canvas canvas, Path shape, double degrees, Paint paint) {
    final b = shape.getBounds();
    final a = degrees * math.pi / 180;
    final dir = Offset(math.cos(a), math.sin(a)), across = Offset(-dir.dy, dir.dx);
    final c = b.center, reach = b.size.longestSide;
    canvas.save();
    canvas.clipPath(shape);
    for (var t = -reach; t <= reach; t += hatchGap) {
      final o = c + across * t;
      canvas.drawLine(o - dir * reach, o + dir * reach, paint);
    }
    canvas.restore();
  }

  void _dots(Canvas canvas, Path path, Paint paint, double r) {
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d <= metric.length; d += dotGap) {
        final at = metric.getTangentForOffset(d);
        if (at != null) canvas.drawCircle(at.position, r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}

/// A [Path] from SVG path data: M L H V C S Q T A Z, absolute or relative.
Path parseSvgPath(String d) {
  final tokens = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  final path = Path();
  var i = 0;
  var cmd = 'M';
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  // the last control point, for S and T
  var cx = 0.0, cy = 0.0;
  var last = '';
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);
  bool flag() => n() != 0;
  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase() && cmd != 'z' && cmd != 'Z';
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + n();
        y = oy + n();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // further pairs after a move are lines
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = ox + n();
        y = oy + n();
        path.lineTo(x, y);
      case 'H':
        x = ox + n();
        path.lineTo(x, y);
      case 'V':
        y = oy + n();
        path.lineTo(x, y);
      case 'C':
        final x1 = ox + n(), y1 = oy + n(), x2 = ox + n(), y2 = oy + n();
        x = ox + n();
        y = oy + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
      case 'S':
        final smooth = 'CcSs'.contains(last);
        final x1 = smooth ? 2 * x - cx : x, y1 = smooth ? 2 * y - cy : y;
        final x2 = ox + n(), y2 = oy + n();
        x = ox + n();
        y = oy + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
      case 'Q':
        final x1 = ox + n(), y1 = oy + n();
        x = ox + n();
        y = oy + n();
        path.quadraticBezierTo(x1, y1, x, y);
        cx = x1;
        cy = y1;
      case 'T':
        final smooth = 'QqTt'.contains(last);
        final x1 = smooth ? 2 * x - cx : x, y1 = smooth ? 2 * y - cy : y;
        x = ox + n();
        y = oy + n();
        path.quadraticBezierTo(x1, y1, x, y);
        cx = x1;
        cy = y1;
      case 'A':
        final rx = n(), ry = n(), rot = n();
        final large = flag(), sweep = flag();
        x = ox + n();
        y = oy + n();
        path.arcToPoint(Offset(x, y),
            radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
      case 'Z':
        path.close();
        x = startX;
        y = startY;
      default:
        i++;
    }
    last = cmd;
  }
  return path;
}
