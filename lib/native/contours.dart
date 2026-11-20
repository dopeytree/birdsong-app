// Contour lines traced from elevation tiles, as the web plate's map does
// (assets/app/map-mode.js, contours()): Mapzen's terrarium tiles, every
// second pixel, smoothed, then the lines at each height. Plain Dart, so it
// runs in an isolate and can be tested.

import 'dart:math' as math;
import 'dart:typed_data';

/// The heights between lines and between labelled (major) lines, for a zoom.
(int minor, int major) contourInterval(double zoom) => zoom >= 15
    ? (5, 25)
    : zoom >= 12.5
        ? (10, 50)
        : zoom >= 11
            ? (20, 100)
            : zoom >= 10
                ? (25, 100)
                : zoom >= 9
                    ? (50, 250)
                    : (100, 500);

/// The tiles at [z] covering a frame (west, south, east, north, degrees).
({int x0, int x1, int y0, int y1}) tileRange(double west, double south, double east, double north, int z) {
  final n = math.pow(2, z).toDouble();
  double lx(double l) => (l + 180) / 360 * n;
  double ly(double la) {
    final r = la * math.pi / 180;
    return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n;
  }

  return (x0: lx(west).floor(), x1: lx(east).floor(), y0: ly(north).floor(), y1: ly(south).floor());
}

/// The tile zoom for a view: one finer than the map's, but no more than 36
/// tiles, between 5 and 14.
int contourTileZoom(double west, double south, double east, double north, double zoom) {
  var z = math.min(14, math.max(5, zoom.floor() + 1));
  while (z > 5) {
    final r = tileRange(west, south, east, north, z);
    if ((r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1) <= 36) break;
    z--;
  }
  return z;
}

/// A terrarium pixel as metres.
double terrarium(int r, int g, int b) => r * 256 + g + b / 256 - 32768;

/// What to trace: the tiles' heights at every second pixel, [w] by [h],
/// starting at tile ([x0], [y0]) of zoom [z].
class ContourJob {
  const ContourJob(this.heights, this.w, this.h, this.x0, this.y0, this.z, this.minor, this.major);

  final Float32List heights;
  final int w;
  final int h;
  final int x0;
  final int y0;
  final int z;
  final int minor;
  final int major;
}

/// One contour line: its height, whether it is a labelled one, and its
/// points as (longitude, latitude) pairs, flattened.
class ContourLine {
  const ContourLine(this.ele, this.major, this.lonLat);

  final int ele;
  final bool major;
  final Float64List lonLat;
}

/// A box blur of radius [rad], across then down, as the page's blur().
Float32List boxBlur(Float32List src, int w, int h, int rad) {
  final tmp = Float32List(w * h), out = Float32List(w * h);
  for (var j = 0; j < h; j++) {
    var sum = 0.0, c = 0;
    for (var i = -rad; i < w; i++) {
      if (i + rad < w) {
        sum += src[j * w + i + rad];
        c++;
      }
      if (i - rad - 1 >= 0) {
        sum -= src[j * w + i - rad - 1];
        c--;
      }
      if (i >= 0) tmp[j * w + i] = sum / c;
    }
  }
  for (var i = 0; i < w; i++) {
    var sum = 0.0, c = 0;
    for (var j = -rad; j < h; j++) {
      if (j + rad < h) {
        sum += tmp[(j + rad) * w + i];
        c++;
      }
      if (j - rad - 1 >= 0) {
        sum -= tmp[(j - rad - 1) * w + i];
        c--;
      }
      if (j >= 0) out[j * w + i] = sum / c;
    }
  }
  return out;
}

/// The lines at height [t] through a grid of [w] by [h] values, by
/// marching squares, joined end to end. Each line is a list of grid
/// positions (x, y), flattened.
List<List<double>> isolines(Float32List v, int w, int h, double t) {
  // Each crossing sits on a cell edge: horizontal edge (i,j)-(i+1,j) is
  // 2*(j*w+i), vertical edge (i,j)-(i,j+1) is 2*(j*w+i)+1.
  final at = <int, (double, double)>{};
  final link = <int, List<int>>{};
  int hEdge(int i, int j) => 2 * (j * w + i);
  int vEdge(int i, int j) => 2 * (j * w + i) + 1;
  (double, double) cross(int e) => at.putIfAbsent(e, () {
        final k = e >> 1, i = k % w, j = k ~/ w;
        final a = v[k];
        if (e.isEven) {
          final b = v[k + 1];
          return (i + (t - a) / (b - a), j.toDouble());
        }
        final b = v[k + w];
        return (i.toDouble(), j + (t - a) / (b - a));
      });
  void join(int a, int b) {
    cross(a);
    cross(b);
    (link[a] ??= []).add(b);
    (link[b] ??= []).add(a);
  }

  for (var j = 0; j < h - 1; j++) {
    for (var i = 0; i < w - 1; i++) {
      final tl = v[j * w + i] >= t, tr = v[j * w + i + 1] >= t;
      final br = v[(j + 1) * w + i + 1] >= t, bl = v[(j + 1) * w + i] >= t;
      final c = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0);
      if (c == 0 || c == 15) continue;
      final top = hEdge(i, j), bottom = hEdge(i, j + 1), left = vEdge(i, j), right = vEdge(i + 1, j);
      switch (c) {
        case 1 || 14:
          join(left, bottom);
        case 2 || 13:
          join(bottom, right);
        case 3 || 12:
          join(left, right);
        case 4 || 11:
          join(top, right);
        case 6 || 9:
          join(top, bottom);
        case 7 || 8:
          join(left, top);
        case 5 || 10:
          // a saddle: the middle decides which corners join
          final mid = (v[j * w + i] + v[j * w + i + 1] + v[(j + 1) * w + i + 1] + v[(j + 1) * w + i]) / 4 >= t;
          if ((c == 5) == mid) {
            join(left, top);
            join(bottom, right);
          } else {
            join(left, bottom);
            join(top, right);
          }
      }
    }
  }

  // Walk the chains: open ones from their ends first, then the loops.
  final done = <int>{}, lines = <List<double>>[];
  List<double> walk(int start) {
    final out = <double>[];
    int? prev;
    var cur = start;
    while (true) {
      done.add(cur);
      final p = at[cur]!;
      out
        ..add(p.$1)
        ..add(p.$2);
      final next = link[cur]!.where((n) => n != prev && !done.contains(n)).firstOrNull;
      if (next == null) {
        // a loop closes on its start
        if (link[cur]!.contains(start) && prev != null && out.length > 4) {
          final s = at[start]!;
          out
            ..add(s.$1)
            ..add(s.$2);
        }
        return out;
      }
      prev = cur;
      cur = next;
    }
  }

  for (final e in link.keys) {
    if (!done.contains(e) && link[e]!.length == 1) lines.add(walk(e));
  }
  for (final e in link.keys) {
    if (!done.contains(e)) lines.add(walk(e));
  }
  return lines;
}

/// The page's trace(): smooth the heights, find the lines at every
/// [ContourJob.minor] metres, break them where they touch the frame's edge
/// (the tiles beyond are not loaded), and place them on the map.
List<ContourLine> traceContours(ContourJob job) {
  final w = job.w, h = job.h;
  var v = job.heights;
  v = job.z >= 13
      ? boxBlur(boxBlur(boxBlur(v, w, h, 3), w, h, 3), w, h, 3)
      : boxBlur(boxBlur(v, w, h, 2), w, h, 2);
  var lo = double.infinity, hi = double.negativeInfinity;
  for (final x in v) {
    if (x < lo) lo = x;
    if (x > hi) hi = x;
  }
  lo = math.max(lo, .5);
  const tile = 256, step = 2;
  final n = math.pow(2, job.z).toDouble() * tile;
  final out = <ContourLine>[];
  for (var level = (lo / job.minor).ceil() * job.minor; level <= hi; level += job.minor) {
    final major = level.round() % job.major == 0;
    for (final line in isolines(v, w, h, level.toDouble())) {
      var run = <double>[];
      void flush() {
        if (run.length > 6) out.add(ContourLine(level, major, Float64List.fromList(run)));
        run = <double>[];
      }

      for (var k = 0; k < line.length; k += 2) {
        final x = line[k], y = line[k + 1];
        if (x <= 1 || y <= 1 || x >= w - 1 || y >= h - 1) {
          flush();
          continue;
        }
        final gx = job.x0 * tile + x * step, gy = job.y0 * tile + y * step;
        run
          ..add(gx / n * 360 - 180)
          ..add(math.atan(_sinh(math.pi * (1 - 2 * gy / n))) * 180 / math.pi);
      }
      flush();
    }
  }
  return out;
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
