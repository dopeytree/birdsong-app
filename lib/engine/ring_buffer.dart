import 'dart:typed_data';

/// Fixed-size circular buffer of float samples.
class RingBuffer {
  RingBuffer(int capacity) : _data = Float32List(capacity);

  final Float32List _data;
  int _write = 0;
  int _total = 0;

  int get capacity => _data.length;

  /// Samples written since creation (or the last [clear]).
  int get total => _total;

  int get available => _total < capacity ? _total : capacity;

  void add(Float32List samples) {
    var src = samples;
    if (src.length > capacity) {
      src = Float32List.sublistView(src, src.length - capacity);
    }
    final first = capacity - _write;
    if (src.length <= first) {
      _data.setRange(_write, _write + src.length, src);
    } else {
      _data.setRange(_write, capacity, src);
      _data.setRange(0, src.length - first, src, first);
    }
    _write = (_write + src.length) % capacity;
    _total += samples.length;
  }

  /// The newest [n] samples, oldest first, or null if fewer have arrived.
  Float32List? latest(int n) {
    if (n > available || n <= 0) return null;
    final out = Float32List(n);
    var start = _write - n;
    if (start >= 0) {
      out.setRange(0, n, _data, start);
    } else {
      start += capacity;
      final firstLen = capacity - start;
      out.setRange(0, firstLen, _data, start);
      out.setRange(firstLen, n, _data, 0);
    }
    return out;
  }

  void clear() {
    _write = 0;
    _total = 0;
  }
}

/// Little-endian 16-bit PCM to floats in -1..1, mixed down to mono.
Float32List pcm16ToFloat(Uint8List bytes, {int channels = 1}) {
  final bd = ByteData.sublistView(bytes);
  final frames = bytes.length ~/ (2 * channels);
  final out = Float32List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += bd.getInt16((f * channels + c) * 2, Endian.little) / 32768.0;
    }
    out[f] = sum / channels;
  }
  return out;
}
