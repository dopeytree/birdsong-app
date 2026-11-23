import 'dart:typed_data';

/// Lifts a figure off its paper, as the web page's cutout() does in a canvas:
/// the paper's colour is read from the picture's border, and every pixel
/// fades out the nearer it is to that colour.
///
/// [rgba] is straight (not premultiplied) RGBA, 4 bytes a pixel. The answer
/// is premultiplied RGBA, which is what dart:ui's decodeImageFromPixels
/// wants. A pixel within [near] of the paper (largest channel difference,
/// 0 to 255) goes clear, one [far] or more away stays solid.
Uint8List liftOffPaper(Uint8List rgba, int width, int height, {int near = 18, int far = 60}) {
  var r = 0, g = 0, b = 0, n = 0;
  void add(int x, int y) {
    final i = (y * width + x) * 4;
    r += rgba[i];
    g += rgba[i + 1];
    b += rgba[i + 2];
    n++;
  }

  for (var x = 0; x < width; x++) {
    add(x, 0);
    add(x, height - 1);
  }
  for (var y = 0; y < height; y++) {
    add(0, y);
    add(width - 1, y);
  }
  final pr = r ~/ n, pg = g ~/ n, pb = b ~/ n;

  final out = Uint8List(rgba.length);
  for (var i = 0; i < rgba.length; i += 4) {
    final dr = (rgba[i] - pr).abs(), dg = (rgba[i + 1] - pg).abs(), db = (rgba[i + 2] - pb).abs();
    final d = dr > dg ? (dr > db ? dr : db) : (dg > db ? dg : db);
    final a = d <= near ? 0 : (d >= far ? 255 : ((d - near) * 255) ~/ (far - near));
    out[i] = rgba[i] * a ~/ 255;
    out[i + 1] = rgba[i + 1] * a ~/ 255;
    out[i + 2] = rgba[i + 2] * a ~/ 255;
    out[i + 3] = a;
  }
  return out;
}
