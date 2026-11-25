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
    for (var i = 0; i < 20000; i++) {
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

class _Placed {
  _Placed(this.id, this.w, this.h);

  final String id;
  final double w;
  final double h;
  double cx = 0;
  double cy = 0;
}

/// Applies a user drag [drag] (in logical pixels) to [places], moving birds
/// differently depending on the active view [sizeBy] ('calls', 'time', or
/// 'equal') while keeping every figure inside [box].
///
/// [rank] maps each bird's id to its normalized position 0..1 in the current
/// view (for 'calls': 0 = least heard, 1 = most heard; for 'time': 0 = oldest,
/// 1 = most recent; for 'equal': index fraction).
List<CollagePlace> displaceCollage(
  List<CollagePlace> places,
  Map<String, double> rank, {
  required String sizeBy,
  required Offset drag,
  required Size box,
}) {
  if (places.isEmpty || drag == Offset.zero || box.width <= 0 || box.height <= 0) {
    return places;
  }
  final center = Offset(box.width / 2, box.height / 2);
  final maxSpan = math.max(1.0, math.min(box.width, box.height));
  final dragMag = (drag.distance / maxSpan).clamp(0.0, 1.0);

  return [
    for (var i = 0; i < places.length; i++)
      () {
        final p = places[i];
        final r = (rank[p.id] ?? 0.5).clamp(0.0, 1.0);
        // How strongly this bird follows the drag depends on the view mode:
        // - calls: most-heard birds stay steadier (anchor), rarer birds glide further
        // - time: most-recent birds lead the drag, older birds trail behind
        // - equal: birds glide evenly together with subtle organic spread
        final factor = switch (sizeBy) {
          'calls' => 1.25 - 0.8 * r,
          'time' => 0.45 + 0.8 * r,
          _ => 0.85 + 0.25 * math.sin(i * 1.7),
        };
        // Gentle radial breathing room while dragging so tucked-away birds peek out
        final fromCenter = p.rect.center - center;
        final spread = fromCenter * (0.08 * dragMag);
        final dx = drag.dx * factor + spread.dx;
        final dy = drag.dy * factor + spread.dy;

        // Keep every bird's centre comfortably inside the collage box so even
        // large figures glide freely while never disappearing off-screen.
        final minLeft = -p.rect.width * 0.25;
        final maxLeft = box.width - p.rect.width * 0.75;
        final minTop = -p.rect.height * 0.25;
        final maxTop = box.height - p.rect.height * 0.75;
        final left = (p.rect.left + dx).clamp(math.min(minLeft, maxLeft), math.max(minLeft, maxLeft)).toDouble();
        final top = (p.rect.top + dy).clamp(math.min(minTop, maxTop), math.max(minTop, maxTop)).toDouble();
        final moved = Rect.fromLTWH(left, top, p.rect.width, p.rect.height);
        return CollagePlace(p.id, moved, 1 + (moved.center.dy / maxSpan * 10).round());
      }()
  ];
}
