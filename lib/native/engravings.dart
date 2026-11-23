import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'cutout.dart';

/// Thomas Bewick's wood engravings for the map's wildlife pictures, taken
/// from the Wellcome Collection's scans of his books (Public Domain Mark):
/// A General History of Quadrupeds (1824, b33281294) and A History of
/// British Birds (1847; land birds b29333131_0001, water birds _0002).
///
/// Each animal is found by its heading in the book's text, searched through
/// the Wellcome's IIIF search service; the page around the heading is
/// fetched about 420 px wide and the engraving cut out of it as the bird
/// plates are (cutout.dart).
const engravingSources = <String, (String, String)>{
  'otter': ('b33281294', 'OTTER'),
  'seal': ('b33281294', 'SEAL'),
  'heron': ('b29333131_0002', 'HERON'),
  'swan': ('b29333131_0002', 'SWAN'),
  'puffin': ('b29333131_0002', 'PUFFIN'),
  'kingfisher': ('b29333131_0001', 'KINGFISHER'),
};

/// A heading found on a page: the page's image name and where the word is.
typedef Heading = ({String file, int x, int y, int w, int h});

/// The first hit in an IIIF search answer [json] that is [word] in
/// capitals (a heading, not the word in running text), or null.
Heading? headingHit(Map<String, Object?> json, String word) {
  final hits = json['resources'];
  if (hits is! List) return null;
  final on = RegExp(r'canvases/([^/#]+)#xywh=(\d+),(\d+),(\d+),(\d+)');
  for (final r in hits) {
    if (r is! Map) continue;
    final res = r['resource'];
    final chars = (res is Map ? res['chars'] : r['chars'])?.toString() ?? '';
    final letters = chars.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters != word || letters != letters.toUpperCase()) continue;
    final m = on.firstMatch(r['on']?.toString() ?? '');
    if (m == null) continue;
    return (
      file: m.group(1)!,
      x: int.parse(m.group(2)!),
      y: int.parse(m.group(3)!),
      w: int.parse(m.group(4)!),
      h: int.parse(m.group(5)!),
    );
  }
  return null;
}

/// The two parts of the page an engraving may sit in: just above its
/// heading, or just below it. Regions in the page's own pixels; the image
/// service crops any part past the page's edge.
List<String> engravingRegions(Heading h) {
  final top = (h.y - 1500).clamp(0, h.y);
  return [
    if (h.y - 10 - top >= 100) '0,$top,9000,${h.y - 10 - top}',
    '0,${h.y + h.h + 10},9000,1500',
  ];
}

String _imageUrl(String file, String region) =>
    'https://iiif.wellcomecollection.org/image/$file/$region/420,/0/default.jpg';

CutOut? _cutOnIsolate((Uint8List, int, int) a) => cutOutFigure(a.$1, a.$2, a.$3);

/// The engravings fetched so far. [loaded] ticks when one arrives, so the
/// map can redraw.
class Engravings {
  Engravings._();

  static final loaded = ValueNotifier<int>(0);
  static final Map<String, ui.Image?> _done = {};
  static final Set<String> _asked = {};
  static final _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  /// The engraving for [animal], if it has arrived.
  static ui.Image? of(String animal) => _done[animal];

  /// Whether [animal] has an engraving to look for.
  static bool has(String animal) => engravingSources.containsKey(animal);

  /// Starts fetching [animal]'s engraving, once.
  static void want(String animal) {
    final src = engravingSources[animal];
    if (src == null || !_asked.add(animal)) return;
    _fetch(animal, src.$1, src.$2).then((img) {
      _done[animal] = img;
      if (img != null) loaded.value++;
    });
  }

  static Future<Uint8List> _get(String url) async {
    final req = await _client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw HttpException('${res.statusCode}', uri: Uri.parse(url));
    return consolidateHttpClientResponseBytes(res);
  }

  static Future<ui.Image?> _fetch(String animal, String book, String word) async {
    try {
      final found = jsonDecode(utf8.decode(await _get(
          'https://iiif.wellcomecollection.org/search/v1/$book?q=${word.toLowerCase()}')));
      final h = found is Map<String, Object?> ? headingHit(found, word) : null;
      if (h == null) {
        debugPrint('engraving $animal: no heading $word in $book');
        return null;
      }
      ui.Image? best;
      var bestArea = 0;
      for (final region in engravingRegions(h)) {
        final url = _imageUrl(h.file, region);
        final img = await _cut(await _get(url));
        debugPrint('engraving $animal: $url -> ${img == null ? 'nothing' : '${img.width}x${img.height}'}');
        if (img == null) continue;
        final ratio = img.width / img.height;
        if (ratio < .5 || ratio > 3.5) continue; // a strip of lettering, not a picture
        if (img.width * img.height > bestArea) {
          best?.dispose();
          best = img;
          bestArea = img.width * img.height;
        } else {
          img.dispose();
        }
      }
      return best;
    } catch (e) {
      debugPrint('engraving $animal: $e');
      return null;
    }
  }

  static Future<ui.Image?> _cut(Uint8List jpg) async {
    final codec = await ui.instantiateImageCodec(jpg);
    final frame = (await codec.getNextFrame()).image;
    final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final w = frame.width, h = frame.height;
    frame.dispose();
    codec.dispose();
    if (pixels == null) return null;
    final out = await compute(_cutOnIsolate, (pixels.buffer.asUint8List(), w, h));
    if (out == null || out.width < 40 || out.height < 30) return null;
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(out.rgba, out.width, out.height, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }
}

/// Tones an engraving's black ink to the map's brown and its paper to the
/// map's paper, keeping every shade between.
ui.ColorFilter engravingTone({ui.Color ink = const ui.Color(0xFF4E3B28), ui.Color paper = const ui.Color(0xFFEFE5CF)}) {
  double c(double v) => v * 255;
  final ir = c(ink.r), ig = c(ink.g), ib = c(ink.b);
  final kr = (c(paper.r) - ir) / 255, kg = (c(paper.g) - ig) / 255, kb = (c(paper.b) - ib) / 255;
  return ui.ColorFilter.matrix([
    kr * .299, kr * .587, kr * .114, 0, ir,
    kg * .299, kg * .587, kg * .114, 0, ig,
    kb * .299, kb * .587, kb * .114, 0, ib,
    0, 0, 0, 1, 0,
  ]);
}
