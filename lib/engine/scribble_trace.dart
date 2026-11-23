import 'dart:math' as math;
import 'dart:typed_data';

/// The sound's shape for the song scribble (native/song_scribble.dart): per
/// slice of [sliceMs], how loud (0 to 1, above a slowly following noise
/// floor) and roughly how high (0 to 1, from zero crossings), and where the
/// pencil's swing has got to. Art, not a measurement.
///
/// Slices are numbered from the start; the last [capacity] are kept. It
/// starts full of quiet, so there is always a resting line to draw.
class ScribbleTrace {
  ScribbleTrace({this.capacity = 640, this.sampleRate = 48000})
      : _level = Float32List(capacity),
        _pitch = Float32List(capacity),
        _phase = Float64List(capacity) {
    reset();
  }

  static const sliceMs = 20;

  /// The pencil's travel per slice, in drawing units (about a pixel and a
  /// half: on screen a slice is drawn about this wide).
  static const unit = 1.5;

  final int capacity;
  final int sampleRate;
  final Float32List _level, _pitch;
  final Float64List _phase;

  /// Slices made so far, including the quiet it starts with.
  int count = 0;

  double _floor = -60;
  double _sum = 0, _prev = 0;
  int _n = 0, _crossings = 0;

  int get _sliceSamples => sampleRate * sliceMs ~/ 1000;

  /// Back to quiet.
  void reset() {
    count = 0;
    _floor = -60;
    _sum = 0;
    _n = 0;
    _crossings = 0;
    for (var i = 0; i < capacity; i++) {
      _push(0, .3);
    }
  }

  void add(Float32List samples) {
    final per = _sliceSamples;
    for (final x in samples) {
      _sum += x * x;
      if ((x >= 0) != (_prev >= 0)) _crossings++;
      _prev = x;
      if (++_n == per) _close();
    }
  }

  void _close() {
    final rms = math.sqrt(_sum / _n);
    final db = rms <= 0 ? -90.0 : 20 * math.log(rms) / math.ln10;
    // the floor drops at once to quiet and rises only slowly, so a steady
    // hum settles to the resting line and a song stands out above it
    _floor = db < _floor ? db : _floor + (db - _floor) * .004;
    final level = ((db - _floor - 6) / 30).clamp(0.0, 1.0);
    final hz = _crossings / 2 / (_n / sampleRate);
    final pitch = ((hz - 800) / 6000).clamp(0.0, 1.0);
    _sum = 0;
    _n = 0;
    _crossings = 0;
    _push(level, pitch);
  }

  void _push(double level, double pitch) {
    final i = count % capacity;
    final before = count == 0 ? 0.0 : _phase[(count - 1) % capacity];
    final lastL = count == 0 ? 0.0 : _level[(count - 1) % capacity];
    final lastP = count == 0 ? .3 : _pitch[(count - 1) % capacity];
    _level[i] = level;
    _pitch[i] = pitch;
    _phase[i] = before + swing(lastL, lastP, (count - 1) * unit) * unit;
    count++;
  }

  /// How fast the pencil swings at a place [x] along: quicker for higher
  /// and louder sound, with an uneven hand.
  static double swing(double level, double pitch, double x) =>
      (.22 + .95 * pitch) * (.6 + .8 * level) * (.65 + .7 * (noise(x * .03) * .5 + .5));

  /// [n] slices from slice [from]: loudness, pitch and swing. Slices no
  /// longer kept (or not yet made) are quiet.
  ({List<double> level, List<double> pitch, List<double> phase}) window(int from, int n) {
    final level = List<double>.filled(n, 0), pitch = List<double>.filled(n, .3);
    final phase = List<double>.filled(n, 0);
    final oldest = math.max(0, count - capacity);
    for (var k = 0; k < n; k++) {
      final s = (from + k).clamp(oldest, count - 1);
      final i = s % capacity;
      if (s == from + k) {
        level[k] = _level[i];
        pitch[k] = _pitch[i];
      }
      phase[k] = _phase[i] + (from + k - s) * .3 * unit;
    }
    return (level: level, pitch: pitch, phase: phase);
  }

  /// Smooth value noise, -1 to 1.
  static double noise(double x) {
    final i = x.floor(), t = x - i;
    double h(int n) {
      final s = math.sin(n * 127.1 + 311.7) * 43758.5453;
      return (s - s.floor()) * 2 - 1;
    }

    final s = t * t * (3 - 2 * t);
    return h(i) + (h(i + 1) - h(i)) * s;
  }
}
