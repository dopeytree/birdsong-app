import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../settings.dart';
import '../store/detection_store.dart';
import '../store/media.dart';
import 'classifier.dart';
import 'labels.dart';
import 'model_catalog.dart';
import 'model_manager.dart';
import 'resampler.dart';
import 'ring_buffer.dart';

/// What one model made of the latest window.
class ModelReport {
  ModelReport(this.spec);
  final ModelSpec spec;
  int millis = 0;
  int runs = 0;
  int totalMillis = 0;
  List<(String name, double score)> top = const [];
  String? error;

  int get averageMillis => runs == 0 ? 0 : totalMillis ~/ runs;
}

/// Listens to the microphone and runs every active model over it.
class ListenEngine extends ChangeNotifier {
  ListenEngine(this.settings, this.models, this.store);

  final Settings settings;
  final ModelManager models;
  final DetectionStore store;

  static const captureRate = 48000;
  static const _keepSeconds = 20;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  Timer? _timer;
  bool _busy = false;

  bool running = false;
  bool starting = false;
  String? error;

  /// Input level, dBFS of the last chunk.
  double levelDb = -90;

  /// Windows skipped because the models had not finished the last one.
  int skipped = 0;

  final _raw = RingBuffer(captureRate * _keepSeconds);
  final _to32 = Resampler(captureRate, 32000);
  final _at32 = RingBuffer(32000 * _keepSeconds);

  final List<LoadedModel> _loaded = [];
  final Map<String, ModelReport> reports = {};
  GeoFilter? _geo;
  Map<String, double>? _geoScores;
  DateTime? _geoFor;

  // (model, species) to the detection still open for repeats.
  final Map<String, Detection> _open = {};

  Future<void> start() async {
    if (running || starting) return;
    starting = true;
    error = null;
    notifyListeners();
    try {
      await _loadModels();
      if (_loaded.isEmpty) {
        throw StateError('No active model is downloaded. Pick one under Models.');
      }
      final rec = _recorder ??= AudioRecorder();
      if (!await rec.hasPermission()) {
        throw StateError('Microphone access was refused. Allow it in Settings.');
      }
      _raw.clear();
      _at32.clear();
      final stream = await rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: captureRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
      _sub = stream.listen(_onAudio, onError: (Object e) {
        error = 'Microphone: $e';
        notifyListeners();
      });
      _timer = Timer.periodic(
          Duration(milliseconds: (settings.hopSeconds * 1000).round()), (_) => _tick());
      running = true;
    } catch (e) {
      error = e.toString().replaceFirst('Bad state: ', '');
      await _unload();
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder?.stop();
    } catch (_) {}
    running = false;
    // Wait for a window still in flight before closing its sessions.
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await _unload();
    notifyListeners();
  }

  Future<void> _loadModels() async {
    await _unload();
    Map<String, String> names = const {};
    final sharedFile = models.fileFor(sharedNames);
    if (await sharedFile.exists()) {
      names = namesOf(parseLabels(await sharedFile.readAsString()));
    }
    for (final id in settings.activeModels) {
      final spec = specById(id);
      if (spec == null || !models.isInstalled(spec)) continue;
      final report = reports[id] = ModelReport(spec);
      try {
        _loaded.add(await LoadedModel.load(
          spec: spec,
          modelFile: models.fileFor(spec.model),
          labelsFile: models.fileFor(spec.labels),
          names: spec.namesFromSharedLabels ? names : const {},
          coreMl: settings.useCoreMl,
        ));
      } catch (e) {
        report.error = 'Could not load: $e';
      }
    }
    if (settings.useGeomodel &&
        settings.latitude != null &&
        settings.longitude != null &&
        models.isInstalled(geomodel)) {
      try {
        _geo = await GeoFilter.load(
            models.fileFor(geomodel.model), models.fileFor(geomodel.labels));
      } catch (e) {
        error = 'Location filter did not load: $e';
      }
    }
  }

  Future<void> _unload() async {
    for (final m in _loaded) {
      try {
        await m.close();
      } catch (_) {}
    }
    _loaded.clear();
    try {
      await _geo?.close();
    } catch (_) {}
    _geo = null;
    _geoScores = null;
    _open.clear();
  }

  void _onAudio(Uint8List bytes) {
    final samples = pcm16ToFloat(bytes);
    if (samples.isEmpty) return;
    _raw.add(samples);
    _at32.add(_to32.process(samples));
    var sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / samples.length);
    levelDb = rms <= 0 ? -90.0 : (20 * math.log(rms) / math.ln10).clamp(-90.0, 0.0).toDouble();
  }

  Future<void> _tick() async {
    if (_busy) {
      skipped++;
      return;
    }
    _busy = true;
    try {
      final now = DateTime.now();
      await _refreshGeo(now);
      for (final m in List<LoadedModel>.of(_loaded)) {
        if (!running) break;
        final ring = m.spec.sampleRate == captureRate ? _raw : _at32;
        final window = ring.latest(m.windowSamples);
        if (window == null) continue; // not enough audio yet
        final report = reports[m.spec.id]!;
        try {
          final p = await m.predict(window);
          report.millis = p.millis;
          report.runs++;
          report.totalMillis += p.millis;
          report.error = null;
          final top = p.top(5, keep: (i) => _keep(m, i));
          report.top = [for (final s in top) (m.labels[s.index].common, s.value)];
          for (final s in top) {
            if (s.value < settings.threshold) break;
            await _detected(m, m.labels[s.index], s.value, now);
          }
        } catch (e) {
          report.error = e.toString();
        }
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  bool _keep(LoadedModel m, int i) {
    final l = m.labels[i];
    if (settings.animalsOnly && !l.animal) return false;
    final geo = _geoScores;
    if (geo != null) {
      final g = geo[l.sci];
      // Species the geomodel doesn't know are kept rather than guessed away.
      if (g != null && g < settings.geoThreshold) return false;
    }
    return true;
  }

  Future<void> _refreshGeo(DateTime now) async {
    final geo = _geo;
    if (geo == null) return;
    final last = _geoFor;
    if (_geoScores != null && last != null && last.day == now.day) return;
    try {
      _geoScores = await geo.scores(settings.latitude!, settings.longitude!, now);
      _geoFor = now;
    } catch (e) {
      error = 'Location filter: $e';
    }
  }

  Future<void> _detected(LoadedModel m, SpeciesLabel l, double score, DateTime now) async {
    final key = '${m.spec.id}|${l.sci}';
    final open = _open[key];
    if (open != null &&
        now.difference(open.at).inMilliseconds < settings.repeatSeconds * 1000) {
      if (score > open.confidence) {
        open.confidence = score;
        await store.save(open);
      }
      return;
    }
    final d = await store.add(
        model: m.spec.id, sci: l.sci, common: l.common, confidence: score, at: now);
    _open[key] = d;
    unawaited(_saveClip(d, m));
  }

  /// The window that was heard, a second either side, as WAV and spectrogram.
  Future<void> _saveClip(Detection d, LoadedModel m) async {
    try {
      final seconds = m.spec.windowSeconds + 2;
      final clip = _raw.latest((captureRate * seconds).round()) ??
          _raw.latest(_raw.available);
      if (clip == null) return;
      final wav = encodeWav(clip, captureRate);
      await store.clipFile(d.id).writeAsBytes(wav, flush: true);
      final bmp = await compute(_spectrogram, clip);
      await store.spectrogramFile(d.id).writeAsBytes(bmp, flush: true);
      d.hasClip = true;
      await store.save(d);
    } catch (e) {
      debugPrint('clip ${d.id}: $e');
    }
  }

  /// Disk used by recordings.
  Future<int> clipBytes() async {
    var n = 0;
    if (!await store.clips.exists()) return 0;
    await for (final f in store.clips.list()) {
      if (f is File) n += await f.length();
    }
    return n;
  }
}

Uint8List _spectrogram(Float32List clip) =>
    spectrogramBmp(clip, ListenEngine.captureRate);
