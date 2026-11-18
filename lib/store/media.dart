import 'dart:math' as math;
import 'dart:typed_data';

/// 16-bit mono WAV.
Uint8List encodeWav(Float32List samples, int sampleRate) {
  final dataLen = samples.length * 2;
  final b = ByteData(44 + dataLen);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    b.setInt16(44 + i * 2, v, Endian.little);
  }
  return b.buffer.asUint8List();
}

/// In-place radix-2 FFT. [re] and [im] must be the same power-of-two length.
void fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang), wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final ar = re[i + k], ai = im[i + k];
        final br = re[i + k + len ~/ 2] * cr - im[i + k + len ~/ 2] * ci;
        final bi = re[i + k + len ~/ 2] * ci + im[i + k + len ~/ 2] * cr;
        re[i + k] = ar + br;
        im[i + k] = ai + bi;
        re[i + k + len ~/ 2] = ar - br;
        im[i + k + len ~/ 2] = ai - bi;
        final ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}

/// A spectrogram as a 24-bit BMP: ink on Birdsong's paper colour, low
/// frequencies at the bottom, 0 to [maxHz] tall.
Uint8List spectrogramBmp(Float32List samples, int sampleRate,
    {int fftSize = 1024, int maxHz = 12000, int maxWidth = 640, int height = 200}) {
  final hop = fftSize ~/ 2;
  final frames = samples.length < fftSize ? 1 : 1 + (samples.length - fftSize) ~/ hop;
  final bins = math.min(fftSize ~/ 2, (maxHz / sampleRate * fftSize).round());
  final window = Float64List(fftSize);
  for (var i = 0; i < fftSize; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (fftSize - 1));
  }

  // Power in dB per frame and bin.
  final db = List.generate(frames, (_) => Float64List(bins));
  var top = -1e9;
  final re = Float64List(fftSize), im = Float64List(fftSize);
  for (var f = 0; f < frames; f++) {
    for (var i = 0; i < fftSize; i++) {
      final s = f * hop + i;
      re[i] = s < samples.length ? samples[s] * window[i] : 0.0;
      im[i] = 0.0;
    }
    fft(re, im);
    for (var k = 0; k < bins; k++) {
      final p = re[k] * re[k] + im[k] * im[k];
      final v = 10 * math.log(p + 1e-12) / math.ln10;
      db[f][k] = v;
      if (v > top) top = v;
    }
  }

  final width = math.min(frames, maxWidth);
  const range = 70.0; // dB shown below the loudest point
  const paper = [216, 233, 239]; // BGR of #efe9d8
  const ink = [28, 36, 42]; // BGR of #2a241c
  final rowBytes = ((width * 3 + 3) ~/ 4) * 4;
  final pixelBytes = rowBytes * height;
  final b = ByteData(54 + pixelBytes);
  b.setUint8(0, 0x42);
  b.setUint8(1, 0x4D);
  b.setUint32(2, 54 + pixelBytes, Endian.little);
  b.setUint32(10, 54, Endian.little);
  b.setUint32(14, 40, Endian.little);
  b.setInt32(18, width, Endian.little);
  b.setInt32(22, height, Endian.little); // positive: bottom-up rows
  b.setUint16(26, 1, Endian.little);
  b.setUint16(28, 24, Endian.little);
  b.setUint32(34, pixelBytes, Endian.little);
  b.setInt32(38, 2835, Endian.little);
  b.setInt32(42, 2835, Endian.little);

  for (var y = 0; y < height; y++) {
    final k = math.min(bins - 1, (y / height * bins).floor());
    for (var x = 0; x < width; x++) {
      final f = math.min(frames - 1, (x / width * frames).floor());
      final t = ((db[f][k] - (top - range)) / range).clamp(0.0, 1.0);
      final at = 54 + y * rowBytes + x * 3;
      for (var c = 0; c < 3; c++) {
        b.setUint8(at + c, (paper[c] + (ink[c] - paper[c]) * t).round());
      }
    }
  }
  return b.buffer.asUint8List();
}
