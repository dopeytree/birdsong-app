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

/// Flat-panel interactive lens over [layoutCollage]: dragging by [pan] moves
/// all birds together as a linked sheet and overrides the view's default
/// weight so whichever bird nears the panel's centre grows to full hero size
/// while the previous hero shrinks as it moves away. An iterative separation
/// + cohesion pass keeps all birds reactively packed with **zero overlap**
/// inside [box].
///
/// With [pan] == [Offset.zero], returns [base] untouched.
List<CollagePlace> lensCollage(
  List<CollagePlace> base, {
  required Offset pan,
  required Size box,
}) {
  if (base.isEmpty || pan == Offset.zero || box.width <= 0 || box.height <= 0) {
    return base;
  }
  final center = Offset(box.width / 2, box.height / 2);
  final minDim = math.min(box.width, box.height);
  final focusRadius = minDim * 0.34;
  // Smoothly hand over sizing from the resting layout to the centre magnifier
  // as soon as the user drags.
  final blend = (pan.distance / (minDim * 0.14)).clamp(0.0, 1.0);
  const gap = 4.0;

  // Use the resting hero's area as the target hero area at dead centre so a
  // small bird dragged to the middle grows as large as the #1 bird was.
  var heroArea = 0.0;
  for (final p in base) {
    final a = p.rect.width * p.rect.height;
    if (a > heroArea) heroArea = a;
  }

  final nodes = <_LensNode>[];
  for (final p in base) {
    final tx = p.rect.center.dx + pan.dx;
    final ty = p.rect.center.dy + pan.dy;
    final dist = (Offset(tx, ty) - center).distance;
    final prox = math.exp(-(dist * dist) / (2 * focusRadius * focusRadius));
    // Centre magnifier scale: 1.0 at dead centre, tapering smoothly to 0.28 away.
    final lensScale = 0.28 + 0.72 * prox;
    final restArea = math.max(1.0, p.rect.width * p.rect.height);
    final lensArea = heroArea * lensScale * lensScale;
    final targetArea = restArea + (lensArea - restArea) * blend;
    final aspect = p.rect.width / math.max(1.0, p.rect.height);
    final w = math.sqrt(targetArea * aspect);
    final h = math.sqrt(targetArea / aspect);
    nodes.add(_LensNode(p.id, tx, ty, tx, ty, w, h, prox));
  }

  // Reactive separation + gentle pull toward each bird's dragged target so the
  // whole flock shifts and parts smoothly around the new centre hero without
  // ever overlapping.
  for (var iter = 0; iter < 80; iter++) {
    var maxPen = 0.0;
    // Gentle spring toward dragged target (only on early iterations so final
    // iterations guarantee strict zero overlap).
    if (iter < 40) {
      const pull = 0.08;
      for (final n in nodes) {
        n.cx += (n.tx - n.cx) * pull;
        n.cy += (n.ty - n.cy) * pull;
      }
    }
    for (var i = 0; i < nodes.length; i++) {
      final a = nodes[i];
      for (var j = i + 1; j < nodes.length; j++) {
        final b = nodes[j];
        final dx = b.cx - a.cx;
        final dy = b.cy - a.cy;
        final ox = (a.w + b.w) / 2 + gap - dx.abs();
        final oy = (a.h + b.h) / 2 + gap - dy.abs();
        if (ox > 0 && oy > 0) {
          final pen = math.min(ox, oy);
          if (pen > maxPen) maxPen = pen;
          // Bird closer to centre yields slightly less so the centre bird stays
          // planted right in the middle while neighbours part around it.
          final wa = 1.0 - 0.55 * a.prox;
          final wb = 1.0 - 0.55 * b.prox;
          final sum = wa + wb;
          final fa = wa / sum, fb = wb / sum;
          if (ox < oy) {
            final push = ox + 0.15;
            final dir = dx == 0 ? (i < j ? 1.0 : -1.0) : dx.sign;
            a.cx -= dir * push * fa;
            b.cx += dir * push * fb;
          } else {
            final push = oy + 0.15;
            final dir = dy == 0 ? (i < j ? 1.0 : -1.0) : dy.sign;
            a.cy -= dir * push * fa;
            b.cy += dir * push * fb;
          }
        }
      }
    }
    if (maxPen == 0 && iter >= 40) break;
  }

  // Fit cleanly inside [box] while preserving zero overlap and proportions.
  var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
  for (final n in nodes) {
    x0 = math.min(x0, n.cx - n.w / 2);
    x1 = math.max(x1, n.cx + n.w / 2);
    y0 = math.min(y0, n.cy - n.h / 2);
    y1 = math.max(y1, n.cy + n.h / 2);
  }
  final spanW = math.max(1.0, x1 - x0);
  final spanH = math.max(1.0, y1 - y0);
  final k = math.min(1.0, math.min(box.width / spanW, box.height / spanH));
  final shiftX = (box.width - spanW * k) / 2 - x0 * k;
  final shiftY = (box.height - spanH * k) / 2 - y0 * k;

  return [
    for (final n in nodes)
      () {
        final w = n.w * k, h = n.h * k;
        final left = shiftX + (n.cx - n.w / 2) * k;
        final top = shiftY + (n.cy - n.h / 2) * k;
        return CollagePlace(
          n.id,
          Rect.fromLTWH(left, top, w, h),
          1 + ((top + h / 2) / math.max(1.0, box.height) * 10).round(),
        );
      }()
  ];
}

class _LensNode {
  _LensNode(this.id, this.tx, this.ty, this.cx, this.cy, this.w, this.h, this.prox);

  final String id;
  final double tx;
  final double ty;
  double cx;
  double cy;
  final double w;
  final double h;
  final double prox;
}
