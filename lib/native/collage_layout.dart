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

/// Unit quaternion for smooth, gimbal-lock-free 3D trackball rotation.
class SphereQuat {
  const SphereQuat(this.w, this.x, this.y, this.z);

  static const identity = SphereQuat(1, 0, 0, 0);

  final double w, x, y, z;

  bool get isIdentity => (w.abs() - 1).abs() < 1e-4 && x.abs() < 1e-4 && y.abs() < 1e-4 && z.abs() < 1e-4;

  /// Rotation of [angle] radians around unit axis ([ax], [ay], [az]).
  factory SphereQuat.axisAngle(double ax, double ay, double az, double angle) {
    final half = angle / 2;
    final s = math.sin(half);
    return SphereQuat(math.cos(half), ax * s, ay * s, az * s).normalized();
  }

  SphereQuat normalized() {
    final len = math.sqrt(w * w + x * x + y * y + z * z);
    if (len < 1e-9) return identity;
    return SphereQuat(w / len, x / len, y / len, z / len);
  }

  SphereQuat operator *(SphereQuat o) => SphereQuat(
        w * o.w - x * o.x - y * o.y - z * o.z,
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
      ).normalized();

  /// Rotate 3D point ([px], [py], [pz]).
  (double, double, double) rotate(double px, double py, double pz) {
    final tx = 2 * (y * pz - z * py);
    final ty = 2 * (z * px - x * pz);
    final tz = 2 * (x * py - y * px);
    return (
      px + w * tx + (y * tz - z * ty),
      py + w * ty + (z * tx - x * tz),
      pz + w * tz + (x * ty - y * tx),
    );
  }

  /// Spherical linear interpolation from `this` to [to] at [t] in 0..1.
  SphereQuat slerp(SphereQuat to, double t) {
    var dot = w * to.w + x * to.x + y * to.y + z * to.z;
    var tw = to.w, tx = to.x, ty = to.y, tz = to.z;
    if (dot < 0) {
      dot = -dot;
      tw = -tw;
      tx = -tx;
      ty = -ty;
      tz = -tz;
    }
    if (dot > 0.9995) {
      return SphereQuat(
        w + (tw - w) * t,
        x + (tx - x) * t,
        y + (ty - y) * t,
        z + (tz - z) * t,
      ).normalized();
    }
    final theta = math.acos(dot.clamp(-1.0, 1.0));
    final sinT = math.sin(theta);
    final a = math.sin((1 - t) * theta) / sinT;
    final b = math.sin(t * theta) / sinT;
    return SphereQuat(
      w * a + tw * b,
      x * a + tx * b,
      y * a + ty * b,
      z * a + tz * b,
    ).normalized();
  }
}

/// One billboarded bird projected from the 3D sphere onto the 2D collage box.
class SpherePlace {
  const SpherePlace(this.id, this.rect, {required this.z, required this.opacity});

  final String id;
  final Rect rect;

  /// Depth after rotation: +1 is dead-centre front, -1 is far back.
  final double z;

  /// 1.0 on the front hemisphere, gently faded as birds pass behind.
  final double opacity;
}

/// Places [items] on a 3D golden-angle sphere (first item at the front pole
/// `(0, 0, +1)`), rotates the sphere by [rotation], and projects each item as
/// an upright billboard facing the user inside [box].
///
/// Whichever bird rotates to the front centre (`z -> +1`) grows to equal hero
/// size; birds toward the edge shrink, and birds on the back hemisphere shrink
/// further and fade gently so the page stays airy.
List<SpherePlace> layoutSphereCollage(
  List<CollageItem> items,
  Size box, {
  SphereQuat rotation = SphereQuat.identity,
}) {
  if (items.isEmpty || box.width <= 0 || box.height <= 0) return [];
  final n = items.length;
  // Items ordered by weight descending so the view's hero sits at the front pole.
  final ordered = [...items]..sort((a, b) => b.weight.compareTo(a.weight));

  // Keep small groups mostly on the front/sides so a 2-5 bird walk doesn't hide
  // birds behind at rest; larger flocks wrap smoothly around the full sphere.
  final zSpan = n <= 4 ? 0.95 : (n <= 8 ? 1.35 : 1.82);
  final minDim = math.min(box.width, box.height);
  final heroBase = minDim * (n <= 3 ? 0.56 : (n <= 10 ? 0.46 : 0.40));
  final rxScale = box.width * 0.37;
  final ryScale = box.height * 0.36;
  final cx0 = box.width / 2;
  final cy0 = box.height / 2;

  final out = <SpherePlace>[];
  for (var i = 0; i < n; i++) {
    final it = ordered[i];
    final double px, py, pz;
    if (n == 1) {
      px = 0;
      py = 0;
      pz = 1;
    } else {
      pz = 1.0 - (i / (n - 1)) * zSpan;
      final r = math.sqrt(math.max(0.0, 1.0 - pz * pz));
      final theta = i * 2.399963229728653; // golden angle
      px = r * math.cos(theta);
      py = r * math.sin(theta);
    }

    final (rx, ry, rz) = rotation.rotate(px, py, pz);
    // Subtle perspective foreshortening without tilting the upright engraving.
    final persp = 2.6 / (2.6 - rz * 0.65);
    final sx = cx0 + rx * rxScale * persp;
    final sy = cy0 + ry * ryScale * persp;

    // Equal hero size at the front centre (rz -> +1), shrinking smoothly away.
    final front = ((rz + 1.0) / 2.0).clamp(0.0, 1.0);
    final scale = 0.26 + 0.74 * math.pow(front, 1.65).toDouble();
    final aspect = it.aspect.clamp(0.55, 2.2);
    final base = it.blank ? heroBase * 0.55 : heroBase;
    var w = base * scale * math.sqrt(aspect);
    var h = base * scale / math.sqrt(aspect);
    // Keep very wide or very tall plates inside the box comfortably.
    final maxW = box.width * 0.72, maxH = box.height * 0.78;
    if (w > maxW) {
      final k = maxW / w;
      w *= k;
      h *= k;
    }
    if (h > maxH) {
      final k = maxH / h;
      w *= k;
      h *= k;
    }

    // Front hemisphere crisp (1.0), gently fading behind to keep the page airy.
    final opacity = rz >= 0.05
        ? 1.0
        : (0.14 + 0.86 * ((rz + 0.85) / 0.90).clamp(0.0, 1.0));

    out.add(SpherePlace(
      it.id,
      Rect.fromCenter(center: Offset(sx, sy), width: w, height: h),
      z: rz,
      opacity: opacity,
    ));
  }
  return out;
}
