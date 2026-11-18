import 'dart:math' as math;
import 'dart:typed_data';

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// Streaming rational resampler (polyphase windowed-sinc FIR).
///
/// 48 kHz to 32 kHz is up 2, down 3. Any pair of integer rates works; the
/// filter table holds `up` phases of [tapsPerPhase] taps each.
class Resampler {
  Resampler(this.inRate, this.outRate, {this.tapsPerPhase = 32}) {
    final g = _gcd(inRate, outRate);
    up = outRate ~/ g;
    down = inRate ~/ g;
    final n = tapsPerPhase * up;
    final fsUp = inRate * up.toDouble();
    // Cut off a little below the lower Nyquist so nothing folds back.
    final fc = 0.45 * math.min(inRate, outRate);
    final centre = (n - 1) / 2;
    _h = Float64List(n);
    for (var i = 0; i < n; i++) {
      final t = i - centre;
      final x = 2 * fc / fsUp * t;
      final sinc = x == 0 ? 1.0 : math.sin(math.pi * x) / (math.pi * x);
      final w = 0.42 - 0.5 * math.cos(2 * math.pi * i / (n - 1)) +
          0.08 * math.cos(4 * math.pi * i / (n - 1)); // Blackman
      _h[i] = 2 * fc / fsUp * sinc * w * up;
    }
    _history = Float64List(tapsPerPhase + 1);
  }

  final int inRate;
  final int outRate;
  final int tapsPerPhase;
  late final int up;
  late final int down;
  late final Float64List _h;

  // Input samples seen so far, as a sliding window of the most recent ones.
  late Float64List _history;
  int _inCount = 0; // total input samples consumed
  int _outCount = 0; // total output samples produced

  bool get passthrough => inRate == outRate;

  /// Feed input samples, get the output samples they complete.
  Float32List process(Float32List input) {
    if (passthrough) return input;
    // Join history and new input into one buffer indexed from `base`.
    final keep = _history.length;
    final buf = Float64List(keep + input.length);
    buf.setRange(0, keep, _history);
    for (var i = 0; i < input.length; i++) {
      buf[keep + i] = input[i];
    }
    final base = _inCount - keep; // global index of buf[0]
    _inCount += input.length;

    final out = <double>[];
    final n = _h.length;
    while (true) {
      final j0 = _outCount * down; // position on the upsampled grid
      final iMax = j0 ~/ up; // newest input sample this output needs
      if (iMax >= _inCount) break;
      var acc = 0.0;
      // Inputs i with 0 <= j0 - i*up < n.
      var iMin = (j0 - n + up) ~/ up;
      if (j0 - n + up < 0) iMin = 0;
      for (var i = iMax; i >= iMin; i--) {
        final k = j0 - i * up;
        if (k >= n) break;
        final b = i - base;
        if (b < 0) break;
        acc += _h[k] * buf[b];
      }
      out.add(acc);
      _outCount++;
    }

    // Keep the last `keep` samples for the next call.
    if (buf.length >= keep) {
      _history = Float64List.sublistView(buf, buf.length - keep);
      _history = Float64List.fromList(_history);
    }
    return Float32List.fromList(out);
  }
}
