import 'dart:math' as math;
import 'dart:typed_data';

/// A figure lifted off its plate: premultiplied RGBA, cropped to the figure.
class CutOut {
  const CutOut(this.rgba, this.width, this.height, this.cover);

  final Uint8List rgba;
  final int width;
  final int height;

  /// How much of the plate the figure covered, 0 to 1. A low number is a
  /// bird on plain paper, which cuts out cleanly.
  final double cover;
}

/// Lifts the bird off its page, as the web plate's cutout() does, step for
/// step: reads the paper colour from the margins, finds the inked areas,
/// keeps the largest figure (and others at least a fifth its size, but not
/// lines of lettering), follows its ink out to the page edge, gives it a
/// soft outline, and lets paper reachable from the edge fall away while pale
/// areas enclosed by the figure stay solid.
///
/// [rgba] is straight RGBA, 4 bytes a pixel, [w] by [h]; the page works at
/// most 420 wide, so scale the plate to that first. Null when nothing was
/// found, or when ink covers over half the plate (a full painted scene,
/// better left whole).
CutOut? cutOutFigure(Uint8List rgba, int w, int h) {
  final d = rgba;
  final m = (w * .035).round(), m2 = (w * .08).round();
  final rs = <int>[], gs = <int>[], bs = <int>[];
  for (var y = m; y < h - m; y += 3) {
    for (var x = m; x < w - m; x += 3) {
      if (x > m2 && x < w - m2 && y > m2 && y < h - m2) continue;
      final i = (y * w + x) * 4;
      rs.add(d[i]);
      gs.add(d[i + 1]);
      bs.add(d[i + 2]);
    }
  }
  if (rs.isEmpty) return null;
  int med(List<int> a) => (a..sort())[a.length >> 1];
  final pr = med(rs), pg = med(gs), pb = med(bs);
  final n = w * h;
  final dist = Float32List(n);
  for (var k = 0; k < n; k++) {
    final i = k * 4, dr = d[i] - pr, dg = d[i + 1] - pg, db = d[i + 2] - pb;
    dist[k] = math.sqrt(dr * dr + dg * dg + db * db);
  }

  // Look for the figure away from the edges, where a scan's dark border lives.
  const s = 4;
  final gw = (w / s).ceil(), gh = (h / s).ceil();
  final cnt = Uint16List(gw * gh);
  for (var y = m; y < h - m; y++) {
    for (var x = m; x < w - m; x++) {
      if (dist[y * w + x] > 42) cnt[(y ~/ s) * gw + (x ~/ s)]++;
    }
  }
  const r = 2;
  final dl = Uint8List(gw * gh);
  for (var y = 0; y < gh; y++) {
    for (var x = 0; x < gw; x++) {
      if (cnt[y * gw + x] < 3) continue;
      for (var yy = math.max(0, y - r); yy <= math.min(gh - 1, y + r); yy++) {
        for (var xx = math.max(0, x - r); xx <= math.min(gw - 1, x + r); xx++) {
          dl[yy * gw + xx] = 1;
        }
      }
    }
  }
  final lab = Int32List(gw * gh);
  final comps = <_Comp?>[null];
  final stack = <int>[];
  for (var at = 0; at < dl.length; at++) {
    if (dl[at] == 0 || lab[at] != 0) continue;
    final id = comps.length, o = _Comp(gw, gh);
    lab[at] = id;
    stack.add(at);
    while (stack.isNotEmpty) {
      final p = stack.removeLast(), py = p ~/ gw, px = p % gw;
      o.a += cnt[p];
      if (px < o.x0) o.x0 = px;
      if (px > o.x1) o.x1 = px;
      if (py < o.y0) o.y0 = py;
      if (py > o.y1) o.y1 = py;
      for (var yy = py - 1; yy <= py + 1; yy++) {
        for (var xx = px - 1; xx <= px + 1; xx++) {
          if (yy < 0 || xx < 0 || yy >= gh || xx >= gw) continue;
          final q = yy * gw + xx;
          if (dl[q] != 0 && lab[q] == 0) {
            lab[q] = id;
            stack.add(q);
          }
        }
      }
    }
    comps.add(o);
  }
  if (comps.length < 2) return null;
  var big = 1;
  for (var i = 1; i < comps.length; i++) {
    if (comps[i]!.a > comps[big]!.a) big = i;
  }
  var tot = 0;
  final keep = List<bool>.filled(comps.length, false);
  for (var i = 1; i < comps.length; i++) {
    final o = comps[i]!;
    final cw = o.x1 - o.x0 + 1, ch = o.y1 - o.y0 + 1;
    final caption = ch < gh * .07 || cw / ch > 5; // lines of lettering
    keep[i] = i == big || (o.a >= comps[big]!.a * .2 && !caption);
    if (keep[i]) tot += o.a;
  }
  if (tot / n > .5) return null; // a full painted scene: leave it whole

  // A bird drawn to the very edge of its page reaches into the margin the
  // search above left out. Follow its ink out into the margin, a pixel at a
  // time: a scan's dark border is not joined to the bird, so it stays behind.
  bool kept(int k) => keep[lab[((k ~/ w) ~/ s) * gw + ((k % w) ~/ s)]];
  final extra = Uint8List(n);
  final edge = <int>[];
  void reach(int k) {
    if (extra[k] == 0 && !kept(k) && dist[k] > 42) {
      extra[k] = 1;
      edge.add(k);
    }
  }

  void spread(int k) {
    final y = k ~/ w, x = k % w;
    if (x > 0) reach(k - 1);
    if (x < w - 1) reach(k + 1);
    if (y > 0) reach(k - w);
    if (y < h - 1) reach(k + w);
  }

  for (var k = 0; k < n; k++) {
    if (kept(k) && dist[k] > 42) spread(k);
  }
  while (edge.isNotEmpty) {
    spread(edge.removeLast());
  }
  // and one pixel of fainter ink around that, for the same soft outline
  final fringe = <int>[];
  for (var k = 0; k < n; k++) {
    if (extra[k] == 0) continue;
    final y = k ~/ w, x = k % w;
    void soft(int q) {
      if (extra[q] == 0 && !kept(q) && dist[q] > 24) fringe.add(q);
    }

    if (x > 0) soft(k - 1);
    if (x < w - 1) soft(k + 1);
    if (y > 0) soft(k - w);
    if (y < h - 1) soft(k + w);
  }
  for (final k in fringe) {
    extra[k] = 1;
  }

  // Edge of the figure: a narrow band for smooth outlines, nothing softer.
  final al = Float32List(n);
  for (var k = 0; k < n; k++) {
    if (kept(k) || extra[k] != 0) al[k] = ((dist[k] - 24) / 16).clamp(0.0, 1.0);
  }
  // Paper reachable from the page edge is removed; pale areas enclosed by
  // the figure stay solid.
  final outside = Uint8List(n);
  final q = <int>[];
  void push(int k) {
    if (outside[k] == 0 && al[k] < .5) {
      outside[k] = 1;
      q.add(k);
    }
  }

  for (var x = 0; x < w; x++) {
    push(x);
    push((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    push(y * w);
    push(y * w + w - 1);
  }
  while (q.isNotEmpty) {
    final k = q.removeLast(), y = k ~/ w, x = k % w;
    if (x > 0) push(k - 1);
    if (x < w - 1) push(k + 1);
    if (y > 0) push(k - w);
    if (y < h - 1) push(k + w);
  }
  var x0 = w, y0 = h, x1 = 0, y1 = 0;
  final alpha = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final k = y * w + x;
      final a = outside[k] != 0 ? al[k] : 1.0;
      if (a > .05) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
      alpha[k] = (a * 255).round();
    }
  }
  if (x1 <= x0 || y1 <= y0) return null;

  // Cropped to the figure, colour premultiplied by alpha (what dart:ui's
  // decodeImageFromPixels wants).
  final ow = x1 - x0 + 1, oh = y1 - y0 + 1;
  final out = Uint8List(ow * oh * 4);
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      final k = (y + y0) * w + (x + x0), i = k * 4, o = (y * ow + x) * 4, a = alpha[k];
      out[o] = d[i] * a ~/ 255;
      out[o + 1] = d[i + 1] * a ~/ 255;
      out[o + 2] = d[i + 2] * a ~/ 255;
      out[o + 3] = a;
    }
  }
  return CutOut(out, ow, oh, tot / n);
}

/// One connected patch of ink on the search grid.
class _Comp {
  _Comp(int gw, int gh)
      : x0 = gw,
        y0 = gh;

  int a = 0;
  int x0;
  int x1 = 0;
  int y0;
  int y1 = 0;
}
