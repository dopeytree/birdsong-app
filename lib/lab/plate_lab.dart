// Plate lab: can Flutter draw the plate the way the web page's CSS does?
//
// A test screen of its own, not part of the app. It imports nothing that
// needs dart:io, so the same file runs on Mac, iPhone, Android and in a
// browser (Flutter web):
//
//   flutter run -d macos  -t lib/lab/plate_lab.dart
//   flutter run -d chrome -t lib/lab/plate_lab.dart          (CanvasKit)
//   flutter run -d chrome --wasm -t lib/lab/plate_lab.dart   (skwasm)
//
// What it shows, on textured paper (a vignette and grain, as on the page):
//   1  a plate as it comes: its white paper shows as a rectangle
//   2  tinted: Image(color: paper, colorBlendMode: multiply). Cheap, but it
//      multiplies with ONE flat colour, not with the paper behind it
//   3  true multiply: the plate drawn with Paint.blendMode = multiply, the
//      same thing as CSS mix-blend-mode: multiply
//   4  cut out in Dart: the paper keyed to transparent (lib/lab/cutout.dart)
//   5  a ready-made transparent cut-out (the bundled cardinal)
//
// Switches: "Own layer" wraps each figure in a RepaintBoundary, which is
// Flutter's version of the CSS stacking-context trap: a blend can only see
// what is in its own layer. Pinch or scroll to zoom the whole sheet, the
// case that broke the blend on the web page.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'cutout.dart';

const _paper = Color(0xFFEEE5CE);
const _ink = Color(0xFF2A241C);
const _sepia = Color(0xFF6B5338);
const _madder = Color(0xFF8C3B2A);
const _serif = 'IM Fell English';

/// A plate from Wikimedia Commons with its paper left on (the bat from the
/// whole-plate-blend write-up). Needs a connection; the lab works without.
const _commonsPlate =
    'https://commons.wikimedia.org/wiki/Special:FilePath/Chalinolobus_gouldi-Cayley_2.jpg?width=500';

void main() => runApp(const PlateLabApp());

class PlateLabApp extends StatelessWidget {
  const PlateLabApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Plate lab',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: _serif,
          scaffoldBackgroundColor: _paper,
          colorScheme: ColorScheme.fromSeed(seedColor: _madder, surface: _paper, primary: _madder),
        ),
        home: const PlateLab(),
      );
}

class PlateLab extends StatefulWidget {
  const PlateLab({super.key});

  @override
  State<PlateLab> createState() => _PlateLabState();
}

class _PlateLabState extends State<PlateLab> {
  ui.Image? _plate; // a plate with its paper on
  ui.Image? _cut; // the same, lifted off its paper in Dart
  ui.Image? _ready; // a transparent cut-out, as shipped
  int? _cutMillis;
  String _source = 'drawn here';
  String? _note;
  bool _ownLayer = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _usePlate(_drawPlate(), 'drawn here');
    _load(const AssetImage('assets/app/cardinal.webp')).then((img) {
      if (mounted) setState(() => _ready = img);
    }).catchError((Object e) {
      if (mounted) setState(() => _note = 'Bundled cut-out: $e');
    });
  }

  /// Take [plate] as the plate under test and cut it out, timing the work.
  Future<void> _usePlate(Future<ui.Image> plate, String source) async {
    setState(() => _busy = true);
    try {
      final img = await plate;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) throw StateError('no pixels');
      final watch = Stopwatch()..start();
      // compute() is another isolate on phones and desktop; in a browser it
      // runs on the main thread, so the time shown there is time the page
      // would be frozen.
      final out = await compute(_lift, (data.buffer.asUint8List(), img.width, img.height));
      watch.stop();
      final cut = await _fromPixels(out, img.width, img.height);
      if (!mounted) return;
      setState(() {
        _plate = img;
        _cut = cut;
        _cutMillis = watch.elapsedMilliseconds;
        _source = source;
        _note = null;
      });
    } catch (e) {
      // In a browser this is usually the image host refusing cross-origin
      // pixel access, which the lab is here to find out.
      if (mounted) setState(() => _note = 'Could not use that plate: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plate = _plate, cut = _cut, ready = _ready;
    Widget layer(Widget child) => _ownLayer ? RepaintBoundary(child: child) : child;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Plate lab', style: TextStyle(fontSize: 22, color: _ink)),
                  Text(_where(), style: const TextStyle(color: _sepia, fontStyle: FontStyle.italic)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: _ownLayer, onChanged: (v) => setState(() => _ownLayer = v)),
                    const Text('Own layer', style: TextStyle(color: _ink)),
                  ]),
                  TextButton(
                    onPressed: _busy ? null : () => _usePlate(_drawPlate(), 'drawn here'),
                    child: const Text('Drawn plate'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _usePlate(_load(const NetworkImage(_commonsPlate)), 'Wikimedia Commons'),
                    child: const Text('Commons plate'),
                  ),
                  Text(
                    _cutMillis == null
                        ? 'Cutting out…'
                        : 'Plate $_source, ${plate?.width} × ${plate?.height}. Cut out in $_cutMillis ms.',
                    style: const TextStyle(color: _sepia),
                  ),
                  if (_note != null) Text(_note!, style: const TextStyle(color: _madder)),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: CustomPaint(
                  painter: const _PaperPainter(),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Wrap(
                        spacing: 24,
                        runSpacing: 24,
                        alignment: WrapAlignment.center,
                        children: [
                          _Panel(
                            '1  As it comes',
                            'The paper shows as a rectangle.',
                            plate == null ? null : layer(RawImage(image: plate, fit: BoxFit.contain)),
                          ),
                          _Panel(
                            '2  Tinted',
                            'Multiplied with one flat colour.',
                            plate == null
                                ? null
                                : layer(RawImage(
                                    image: plate,
                                    fit: BoxFit.contain,
                                    color: _paper,
                                    colorBlendMode: BlendMode.multiply)),
                          ),
                          _Panel(
                            '3  True multiply',
                            'Blended with the paper behind it.',
                            plate == null
                                ? null
                                : layer(CustomPaint(painter: _ImagePainter(plate, BlendMode.multiply))),
                          ),
                          _Panel(
                            '4  Cut out in Dart',
                            'Paper keyed to transparent.',
                            cut == null ? null : layer(RawImage(image: cut, fit: BoxFit.contain)),
                          ),
                          _Panel(
                            '5  Ready-made cut-out',
                            'A transparent picture, as shipped.',
                            ready == null ? null : layer(RawImage(image: ready, fit: BoxFit.contain)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _where() {
    if (!kIsWeb) return '${defaultTargetPlatform.name}, native renderer';
    const wasm = bool.fromEnvironment('dart.tool.dart2wasm');
    return wasm ? 'browser, WebAssembly build (skwasm)' : 'browser, JavaScript build (CanvasKit)';
  }
}

/// One figure with its caption.
class _Panel extends StatelessWidget {
  const _Panel(this.title, this.what, this.figure);

  final String title;
  final String what;
  final Widget? figure;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 280,
        child: Column(
          children: [
            SizedBox(
              width: 280,
              height: 230,
              child: figure ?? const Center(child: Text('…', style: TextStyle(color: _sepia))),
            ),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontSize: 17, color: _ink)),
            Text(what,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _sepia, fontStyle: FontStyle.italic)),
          ],
        ),
      );
}

/// The page's paper: a flat colour, darker towards the edges, with grain.
/// Anything that only multiplies with a flat colour shows up against it.
class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final all = Offset.zero & size;
    canvas.drawRect(all, Paint()..color = _paper);
    canvas.drawRect(
      all,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          size.longestSide * 0.7,
          const [Color(0x00000000), Color(0x00000000), Color(0x38503C1E)],
          const [0, 0.45, 1],
        ),
    );
    // Grain: the same specks every time.
    final rnd = math.Random(7);
    final dark = Paint()..color = const Color(0x143C2814);
    final light = Paint()..color = const Color(0x1EFFFFFF);
    final n = (size.width * size.height / 260).round().clamp(0, 12000);
    for (var i = 0; i < n; i++) {
      final at = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawRect(at & const Size(1.4, 1.4), i.isEven ? dark : light);
    }
    // Broad stains, so the paper differs from place to place.
    for (var i = 0; i < 9; i++) {
      final at = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(
          at,
          60 + rnd.nextDouble() * 120,
          Paint()
            ..color = const Color(0x12785A32)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40));
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) => false;
}

/// Draws [image] to fit, with [mode] as its blend against what is already on
/// the canvas: BlendMode.multiply here is CSS's mix-blend-mode: multiply.
class _ImagePainter extends CustomPainter {
  const _ImagePainter(this.image, this.mode);

  final ui.Image image;
  final BlendMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, src.size, size);
    final dst = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    canvas.drawImageRect(
        image,
        src,
        dst,
        Paint()
          ..blendMode = mode
          ..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_ImagePainter old) => old.image != image || old.mode != mode;
}

// compute() takes one argument: the pixels and their size.
Uint8List _lift((Uint8List, int, int) a) => liftOffPaper(a.$1, a.$2, a.$3);

Future<ui.Image> _fromPixels(Uint8List premultiplied, int width, int height) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(premultiplied, width, height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// A picture from an asset or the network, as a dart:ui image.
Future<ui.Image> _load(ImageProvider provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    stream.removeListener(listener);
    if (!done.isCompleted) done.complete(info.image.clone());
  }, onError: (Object e, StackTrace? _) {
    stream.removeListener(listener);
    if (!done.isCompleted) done.completeError(e);
  });
  stream.addListener(listener);
  return done.future;
}

/// A stand-in plate drawn here, so the lab needs no connection: off-white
/// paper with a bird on a branch, a soft shadow and a caption, as an
/// engraved plate has.
Future<ui.Image> _drawPlate() {
  const w = 420.0, h = 340.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFDFBF5));
  final branch = Paint()
    ..color = const Color(0xFF6E5A3C)
    ..strokeWidth = 9
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  c.drawPath(
      Path()
        ..moveTo(40, 262)
        ..quadraticBezierTo(210, 232, 384, 270),
      branch);
  c.drawLine(const Offset(300, 255), const Offset(350, 215), branch..strokeWidth = 5);
  for (final leaf in const [Offset(352, 208), Offset(92, 240), Offset(372, 262)]) {
    c.drawOval(Rect.fromCenter(center: leaf, width: 44, height: 20), Paint()..color = const Color(0xFF8A9A6B));
  }
  // a faint shadow under the bird: the part a hard cut-out loses
  c.drawOval(
      const Rect.fromLTWH(120, 236, 190, 22),
      Paint()
        ..color = const Color(0x33503C28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
  final legs = Paint()
    ..color = const Color(0xFF3C2E20)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  c.drawLine(const Offset(196, 214), const Offset(190, 248), legs);
  c.drawLine(const Offset(222, 214), const Offset(226, 248), legs);
  // tail, body, breast, wing, head, beak, eye
  c.drawPath(
      Path()
        ..moveTo(120, 150)
        ..lineTo(48, 118)
        ..lineTo(58, 150)
        ..lineTo(122, 178)
        ..close(),
      Paint()..color = const Color(0xFF5C4A34));
  c.drawOval(const Rect.fromLTWH(104, 106, 190, 116), Paint()..color = const Color(0xFF7B6A4C));
  c.drawOval(const Rect.fromLTWH(196, 120, 96, 96), Paint()..color = const Color(0xFFD9822B));
  c.drawOval(const Rect.fromLTWH(120, 118, 130, 62), Paint()..color = const Color(0xFF5C4A34));
  c.drawCircle(const Offset(282, 108), 40, Paint()..color = const Color(0xFF7B6A4C));
  c.drawPath(
      Path()
        ..moveTo(318, 98)
        ..lineTo(352, 108)
        ..lineTo(318, 118)
        ..close(),
      Paint()..color = const Color(0xFF3C2E20));
  c.drawCircle(const Offset(294, 98), 5, Paint()..color = const Color(0xFF15100A));
  final caption = TextPainter(
    text: const TextSpan(
        text: 'Avis exempli.  Plate I.',
        style: TextStyle(fontFamily: _serif, fontStyle: FontStyle.italic, fontSize: 15, color: Color(0xFF5A4A36))),
    textDirection: TextDirection.ltr,
  )..layout();
  caption.paint(c, Offset((w - caption.width) / 2, 300));
  return rec.endRecording().toImage(w.toInt(), h.toInt());
}
