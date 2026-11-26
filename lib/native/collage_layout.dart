import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// One figure to place on the collage.
class CollageItem {
  const CollageItem(this.id, {required this.weight, required this.aspect, this.blank = false});

  final String id;

  /// How much it counts: calls, a rank by time, or 1 for all alike. The
  /// largest weight draws the largest figure.
  final double weight;

  /// Width over height of its picture.
  final double aspect;

  /// No picture, only a name: drawn small.
  final bool blank;
}

/// Where a figure goes: its box inside the collage, and its place in the
/// stacking order (lower figures are drawn over higher ones).
class CollagePlace {
  const CollagePlace(this.id, this.rect, this.order);

  final String id;
  final Rect rect;
  final int order;
}

/// The web plate's collage, in Dart: the largest figure sits in the middle
/// and the rest are set down one by one along a spiral, each at the first
/// spot where it clears those already placed. The whole is then scaled to
/// fill [box]. Sizes follow weight to the power 0.45, never under a fifth.
///
/// The same inputs always give the same collage.
List<CollagePlace> layoutCollage(List<CollageItem> items, Size box) {
  if (items.isEmpty || box.width <= 0 || box.height <= 0) return [];
  final most = items.map((i) => i.weight).reduce(math.max);
  final ar = box.width / box.height;
  final sized = [
    for (final it in items)
      () {
        final scale = math.max(0.2, math.pow(most <= 0 ? 1 : it.weight / most, 0.45).toDouble());
        final area = it.blank ? 0.03 : scale * scale;
        return _Placed(it.id, math.sqrt(area * it.aspect), math.sqrt(area / it.aspect));
      }()
  ]..sort((a, b) => (b.w * b.h).compareTo(a.w * a.h));

  const gap = 0.035, step = 0.03; // gap: clear space kept between neighbours
  final placed = <_Placed>[];
  final sx = math.sqrt(ar) * 1.08, sy = 1 / math.sqrt(ar);
  for (final it in sized) {
    for (var i = 0; i < 80000; i++) {
      final r = step * math.sqrt(i), a = i * 2.399963;
      final cx = r * math.cos(a) * sx, cy = r * math.sin(a) * sy;
      var clear = true;
      for (final p in placed) {
        if ((cx - p.cx).abs() < (it.w + p.w) / 2 + gap && (cy - p.cy).abs() < (it.h + p.h) / 2 + gap) {
          clear = false;
          break;
        }
      }
      if (clear) {
        it.cx = cx;
        it.cy = cy;
        break;
      }
    }
    placed.add(it);
  }

  var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
  for (final p in placed) {
    x0 = math.min(x0, p.cx - p.w / 2);
    x1 = math.max(x1, p.cx + p.w / 2);
    y0 = math.min(y0, p.cy - p.h / 2);
    y1 = math.max(y1, p.cy + p.h / 2);
  }
  final k = math.min(box.width / (x1 - x0), box.height / (y1 - y0));
  final ox = (box.width - (x1 - x0) * k) / 2, oy = (box.height - (y1 - y0) * k) / 2;
  return [
    for (final p in placed)
      CollagePlace(
        p.id,
        Rect.fromLTWH(ox + (p.cx - p.w / 2 - x0) * k, oy + (p.cy - p.h / 2 - y0) * k, p.w * k, p.h * k),
        1 + ((p.cy - y0) * 3).round(),
      )
  ];
}

/// Evenly distributes [items] across [box] in a balanced grid with equal cell
/// size (for "No pecking order"), preserving each bird's aspect ratio and
/// centring any partial last row.
List<CollagePlace> layoutEvenGrid(List<CollageItem> items, Size box) {
  final n = items.length;
  if (n == 0 || box.width <= 0 || box.height <= 0) return [];

  // Choose the column count that maximises the usable cell area inside [box].
  var bestCols = 1;
  var bestScore = -1.0;
  for (var cols = 1; cols <= n; cols++) {
    final rows = (n / cols).ceil();
    final cw = box.width / cols;
    final ch = box.height / rows;
    // Prefer cells whose aspect ratio is reasonably close to a typical bird
    // plate (~1.1) while maximising the limiting dimension.
    final score = math.min(cw, ch * 1.15);
    if (score > bestScore) {
      bestScore = score;
      bestCols = cols;
    }
  }

  final rows = (n / bestCols).ceil();
  final cellW = box.width / bestCols;
  final cellH = box.height / rows;
  final padX = cellW * 0.06;
  final padY = cellH * 0.06;
  final availW = math.max(1.0, cellW - 2 * padX);
  final availH = math.max(1.0, cellH - 2 * padY);

  final out = <CollagePlace>[];
  for (var idx = 0; idx < n; idx++) {
    final it = items[idx];
    final r = idx ~/ bestCols;
    final c = idx % bestCols;
    final inRow = r == rows - 1 ? n - r * bestCols : bestCols;
    final rowOffsetX = (bestCols - inRow) * cellW / 2;

    double w, h;
    if (it.blank) {
      w = math.min(availW * 0.7, 96.0);
      h = math.min(availH * 0.35, 32.0);
    } else if (availW / availH > it.aspect) {
      h = availH;
      w = h * it.aspect;
    } else {
      w = availW;
      h = w / it.aspect;
    }
    final cx = rowOffsetX + (c + 0.5) * cellW;
    final cy = (r + 0.5) * cellH;
    out.add(CollagePlace(it.id, Rect.fromCenter(center: Offset(cx, cy), width: w, height: h), r + 1));
  }
  return out;
}

class _Placed {
  _Placed(this.id, this.w, this.h);

  final String id;
  final double w;
  final double h;
  double cx = 0;
  double cy = 0;
}
