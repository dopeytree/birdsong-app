import 'dart:math' as math;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../main.dart' show paper;
import 'landmarks.dart' show Shape, inShape;
import 'mvt.dart';

/// Pictures of wildlife on the map, as old maps drew a stag in a forest or
/// a whale at sea: decoration, not records. Each patch of map (a tile two
/// zooms out from the view) may get one animal, chosen for the habitat the
/// map's own tiles show there (wood, heath, marsh, water, sea) and by the
/// patch itself, so the same place always shows the same animal.

/// Wildlife pictures are switched off for now (Ed, 21 Nov 2026): the drawn
/// silhouettes didn't suit the map, and Bewick's engravings
/// (engravings.dart) are an untried test. The code stays to work on; set
/// this true to bring the pictures and their switch in the layers panel back.
const wildlifePicturesOn = false;

/// The habitats, and the animals drawn for each.
const habitatAnimals = <String, List<String>>{
  'wood': ['deer', 'owl', 'deer', 'owl', 'squirrel'],
  'heath': ['hare', 'grouse', 'hare'],
  'wetland': ['heron', 'heron', 'swan'],
  'water': ['otter', 'swan', 'kingfisher', 'heron'],
  // no Bewick whale or dolphin yet: the sea has his seal and puffin
  'sea': ['seal', 'puffin', 'seal'],
};

/// What each animal is called, for its label.
const animalNames = {
  'deer': 'Red deer',
  'owl': 'Tawny owl',
  'squirrel': 'Red squirrel',
  'hare': 'Brown hare',
  'grouse': 'Red grouse',
  'heron': 'Grey heron',
  'swan': 'Mute swan',
  'otter': 'Otter',
  'kingfisher': 'Kingfisher',
  'whale': 'Minke whale',
  'dolphin': 'Bottlenose dolphin',
  'seal': 'Grey seal',
  'puffin': 'Puffin',
};

/// A picture placed on the map.
class Critter {
  const Critter(this.animal, this.habitat, this.at);

  final String animal;
  final String habitat;
  final LatLng at;
}

/// A tile's habitat from a landcover or water feature, or null.
String? habitatOf(String layer, Map<String, Object?> props) {
  final c = props['class'], sub = props['subclass'];
  if (layer == 'water') {
    if (c == 'ocean' || c == 'sea' || c == 'bay') return 'sea';
    if (c == 'lake' || c == 'river' || c == 'pond' || c == 'reservoir') return 'water';
    return null;
  }
  // landcover
  if (c == 'wood' || c == 'forest') return 'wood';
  if (c == 'wetland' || sub == 'marsh' || sub == 'reedbed' || sub == 'bog' || sub == 'swamp' || sub == 'wet_meadow') {
    return 'wetland';
  }
  if (sub == 'heath' || sub == 'fell' || sub == 'moor' || sub == 'scrub' || sub == 'grassland') return 'heath';
  return null;
}

int _hash(int z, int x, int y) {
  var h = z * 73856093 ^ x * 19349663 ^ y * 83492791;
  h = (h ^ (h >> 13)) * 0x5bd1e995;
  return (h ^ (h >> 15)) & 0x7fffffff;
}

/// The animal, if any, for tile [z]/[x]/[y] from its decoded [layers]
/// ("landcover" and "water" features): the habitat covering most of the
/// tile, if it covers at least a tenth; about two tiles in three get one.
/// Placed inside that habitat, at a spot chosen by the tile.
Critter? critterInTile(Map<String, List<MvtFeature>> layers, int z, int x, int y) {
  final h = _hash(z, x, y);
  if (h % 3 == 0) return null; // not every patch
  final area = <String, double>{};
  final shapes = <String, Shape>{};
  layers.forEach((layer, fs) {
    for (final f in fs) {
      if (f.type != 3) continue;
      final hab = habitatOf(layer, f.props);
      if (hab == null) continue;
      var a = 0.0;
      for (final ring in f.parts) {
        var s = 0.0;
        for (var k = 0; k + 1 < ring.length; k++) {
          s += ring[k].$1 * ring[k + 1].$2 - ring[k + 1].$1 * ring[k].$2;
        }
        a += s / 2; // holes count against
      }
      area[hab] = (area[hab] ?? 0) + a / (f.extent * f.extent);
      (shapes[hab] ??= []).addAll(mvtPolygons(f, z, x, y));
    }
  });
  if (area.isEmpty) return null;
  final best = area.entries.reduce((a, b) => a.value >= b.value ? a : b);
  if (best.value < .1) return null;
  final hab = best.key, shape = shapes[hab]!;
  // a spot inside the habitat, tried from the tile's own sequence
  final n = 1 << z;
  final rnd = math.Random(h);
  for (var i = 0; i < 24; i++) {
    final fx = (x + .15 + .7 * rnd.nextDouble()) / n, fy = (y + .15 + .7 * rnd.nextDouble()) / n;
    final p = LatLng(math.atan(_sinh(math.pi * (1 - 2 * fy))) * 180 / math.pi, fx * 360 - 180);
    if (inShape(p, shape)) {
      final animals = habitatAnimals[hab]!;
      return Critter(animals[(h ~/ 3) % animals.length], hab, p);
    }
  }
  return null;
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

/// [critterInTile] from a tile's bytes.
Critter? critterFromBytes(Uint8List bytes, int z, int x, int y) =>
    critterInTile({'landcover': readMvtLayer(bytes, 'landcover'), 'water': readMvtLayer(bytes, 'water')}, z, x, y);

/// [critterFromBytes] on a background isolate. Kept at the top level so
/// the closure sent to the isolate holds only the tile, never a widget.
Future<Critter?> critterAway(Uint8List bytes, int z, int x, int y) =>
    Isolate.run(() => critterFromBytes(bytes, z, x, y));

/// The tiles a view's animals come from: two zooms out from [zoom] (so a
/// few per screen), no further out than 7 nor in than 13.
int critterZoom(double zoom) => (zoom.floor() - 2).clamp(7, 13);

// ---- the drawn style ------------------------------------------------------

/// An animal drawn as a small silhouette in the map's sepia ink, with a
/// paper edge, in a 48-unit square.
class CritterPainter extends CustomPainter {
  const CritterPainter(this.animal);

  final String animal;

  static const _ink = Color(0xFF5B4630);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final p = _path(animal);
    canvas
      ..drawPath(
          p,
          Paint()
            ..color = paper
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round)
      ..drawPath(p, Paint()..color = _ink.withValues(alpha: .85));
    // details: eyes, spouts, antler tines, as lines
    final line = Paint()
      ..color = _ink.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    switch (animal) {
      case 'whale':
        canvas
          ..drawLine(const Offset(13, 17), const Offset(11, 11), line)
          ..drawLine(const Offset(13, 17), const Offset(15, 11), line);
      case 'deer':
        canvas
          ..drawLine(const Offset(36, 14), const Offset(32, 4), line)
          ..drawLine(const Offset(34, 9), const Offset(29, 7), line)
          ..drawLine(const Offset(36, 14), const Offset(41, 5), line)
          ..drawLine(const Offset(39, 9), const Offset(44, 8), line);
      case 'owl':
        final eye = Paint()..color = paper;
        canvas
          ..drawCircle(const Offset(20, 17), 3, eye)
          ..drawCircle(const Offset(28, 17), 3, eye);
      case 'swan' || 'otter':
        canvas.drawLine(const Offset(4, 38), const Offset(44, 38), line..strokeWidth = 1);
    }
  }

  static Path _path(String animal) {
    final p = ui.Path();
    switch (animal) {
      case 'whale':
        p
          ..moveTo(4, 26)
          ..cubicTo(6, 18, 22, 17, 32, 22)
          ..cubicTo(36, 24, 39, 25, 41, 22)
          ..lineTo(46, 17)
          ..lineTo(44, 25)
          ..lineTo(46, 31)
          ..lineTo(41, 28)
          ..cubicTo(34, 32, 20, 34, 10, 31)
          ..cubicTo(6, 30, 4, 29, 4, 26)
          ..close();
      case 'dolphin':
        p
          ..moveTo(4, 30)
          ..cubicTo(10, 20, 22, 16, 32, 20)
          ..lineTo(30, 13)
          ..lineTo(36, 21)
          ..cubicTo(40, 23, 42, 26, 43, 28)
          ..lineTo(47, 25)
          ..lineTo(45, 32)
          ..lineTo(41, 31)
          ..cubicTo(32, 28, 20, 30, 12, 32)
          ..lineTo(4, 30)
          ..close();
      case 'seal':
        p
          ..moveTo(8, 34)
          ..cubicTo(8, 26, 14, 22, 18, 21)
          ..cubicTo(19, 16, 23, 14, 26, 16)
          ..cubicTo(28, 18, 26, 22, 24, 24)
          ..cubicTo(32, 26, 40, 30, 46, 34)
          ..lineTo(42, 36)
          ..cubicTo(30, 37, 18, 37, 8, 34)
          ..close();
      case 'puffin':
        p
          ..moveTo(18, 42)
          ..cubicTo(14, 34, 14, 22, 20, 16)
          ..cubicTo(22, 12, 28, 11, 30, 15)
          ..lineTo(37, 17)
          ..lineTo(31, 20)
          ..cubicTo(33, 28, 32, 36, 28, 42)
          ..close();
      case 'deer':
        p
          ..moveTo(10, 24)
          ..cubicTo(12, 20, 26, 20, 30, 21)
          ..lineTo(33, 13)
          ..lineTo(38, 12)
          ..lineTo(41, 15)
          ..lineTo(37, 17)
          ..lineTo(34, 25)
          ..lineTo(33, 42)
          ..lineTo(31, 42)
          ..lineTo(30, 30)
          ..lineTo(15, 30)
          ..lineTo(14, 42)
          ..lineTo(12, 42)
          ..lineTo(11, 30)
          ..cubicTo(8, 28, 8, 26, 10, 24)
          ..close();
      case 'owl':
        p
          ..moveTo(15, 12)
          ..lineTo(18, 15)
          ..lineTo(30, 15)
          ..lineTo(33, 12)
          ..cubicTo(36, 18, 36, 30, 32, 38)
          ..cubicTo(28, 43, 20, 43, 16, 38)
          ..cubicTo(12, 30, 12, 18, 15, 12)
          ..close();
      case 'squirrel':
        p
          ..moveTo(22, 40)
          ..cubicTo(18, 36, 20, 28, 24, 26)
          ..cubicTo(22, 22, 24, 18, 28, 18)
          ..lineTo(29, 14)
          ..lineTo(31, 18)
          ..cubicTo(34, 20, 33, 24, 30, 26)
          ..cubicTo(32, 32, 30, 38, 26, 40)
          ..close()
          ..moveTo(20, 38)
          ..cubicTo(8, 36, 6, 18, 14, 12)
          ..cubicTo(18, 16, 16, 28, 22, 34)
          ..close();
      case 'hare':
        p
          ..moveTo(8, 38)
          ..cubicTo(8, 28, 18, 24, 28, 26)
          ..cubicTo(30, 22, 34, 21, 37, 23)
          ..lineTo(36, 8)
          ..lineTo(39, 8)
          ..lineTo(40, 22)
          ..cubicTo(42, 24, 42, 27, 40, 28)
          ..cubicTo(38, 32, 36, 36, 34, 38)
          ..close();
      case 'grouse':
        p
          ..moveTo(8, 32)
          ..cubicTo(10, 24, 22, 22, 28, 24)
          ..cubicTo(30, 18, 36, 17, 38, 21)
          ..lineTo(42, 22)
          ..lineTo(38, 24)
          ..cubicTo(38, 30, 34, 36, 26, 37)
          ..cubicTo(18, 38, 10, 36, 8, 32)
          ..close();
      case 'heron':
        p
          ..moveTo(18, 30)
          ..cubicTo(14, 26, 16, 20, 22, 20)
          ..cubicTo(26, 20, 26, 14, 24, 11)
          ..cubicTo(23, 8, 26, 6, 28, 8)
          ..lineTo(38, 9)
          ..lineTo(29, 11)
          ..cubicTo(30, 16, 30, 22, 28, 26)
          ..cubicTo(26, 30, 22, 32, 18, 30)
          ..close()
          ..addRect(const Rect.fromLTWH(21, 30, 1.4, 12))
          ..addRect(const Rect.fromLTWH(24, 30, 1.4, 12));
      case 'swan':
        p
          ..moveTo(8, 34)
          ..cubicTo(10, 28, 24, 27, 30, 30)
          ..cubicTo(32, 24, 28, 18, 30, 14)
          ..cubicTo(32, 11, 36, 12, 36, 14)
          ..lineTo(40, 15)
          ..lineTo(35, 16)
          ..cubicTo(33, 20, 36, 26, 36, 30)
          ..cubicTo(40, 32, 40, 36, 36, 37)
          ..lineTo(12, 37)
          ..cubicTo(9, 37, 8, 36, 8, 34)
          ..close();
      case 'otter':
        p
          ..moveTo(6, 37)
          ..cubicTo(12, 33, 18, 31, 26, 32)
          ..cubicTo(28, 28, 33, 27, 36, 29)
          ..cubicTo(39, 30, 40, 33, 38, 35)
          ..lineTo(34, 36)
          ..cubicTo(26, 37, 16, 37, 6, 37)
          ..close();
      case 'kingfisher':
        p
          ..moveTo(14, 30)
          ..cubicTo(14, 24, 20, 20, 26, 20)
          ..lineTo(36, 16)
          ..lineTo(30, 22)
          ..cubicTo(32, 26, 30, 30, 26, 32)
          ..lineTo(18, 38)
          ..lineTo(18, 32)
          ..close()
          ..addRect(const Rect.fromLTWH(10, 33, 26, 1.4));
      default:
        p.addOval(const Rect.fromLTWH(18, 18, 12, 12));
    }
    return p;
  }

  @override
  bool shouldRepaint(CritterPainter old) => old.animal != animal;
}
