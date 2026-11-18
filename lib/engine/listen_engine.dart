import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
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

  /// 'Core ML' or 'CPU': what the model is actually running on.
  String backend = 'CPU';

  int get averageMillis => runs == 0 ? 0 : totalMillis ~/ runs;
}

/// A session's plate holds at most this many species; the next new one
/// starts a fresh session.
const maxSessionSpecies = 42;

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

  /// The session being recorded, while listening.
  Session? session;

  /// Location problems, for the Listen tab; listening carries on without.
  String? locationNote;

  // Species to when the plate's model last heard them above the threshold.
  final Map<String, DateTime> _lastHeard = {};

  /// Species heard in the last couple of windows by the model the plate
  /// draws: these glow on the plate.
  Set<String> get liveSpecies {
    if (!running) return const {};
    final keep = Duration(milliseconds: (settings.hopSeconds * 2000 + 1500).round());
    final now = DateTime.now();
    return {
      for (final e in _lastHeard.entries)
        if (now.difference(e.value) <= keep) e.key,
    };
  }

  double? get _lat => settings.latitude ?? session?.lat;
  double? get _lon => settings.longitude ?? session?.lon;

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
      _lastHeard.clear();
      final ses = session = await store.startSession();
      unawaited(_locate(ses));
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
    final ses = session;
    session = null;
    _lastHeard.clear();
    if (ses != null) await store.endSession(ses);
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
      Future<LoadedModel> load(bool coreMl) => LoadedModel.load(
            spec: spec,
            modelFile: models.fileFor(spec.model),
            labelsFile: models.fileFor(spec.labels),
            names: spec.namesFromSharedLabels ? names : const {},
            coreMl: coreMl,
          );
      try {
        if (settings.useCoreMl) {
          try {
            _loaded.add(await load(true));
            report.backend = 'Core ML';
          } catch (e) {
            debugPrint('${spec.id}: Core ML refused it, using the CPU ($e)');
            _loaded.add(await load(false));
            report.backend = 'CPU (Core ML could not load this model)';
          }
        } else {
          _loaded.add(await load(false));
        }
      } catch (e) {
        report.error = 'Could not load: $e';
      }
    }
    if (settings.useGeomodel && models.isInstalled(geomodel)) {
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
    final lat = _lat, lon = _lon;
    if (geo == null || lat == null || lon == null) return;
    final last = _geoFor;
    if (_geoScores != null && last != null && last.day == now.day) return;
    try {
      _geoScores = await geo.scores(lat, lon, now);
      _geoFor = now;
    } catch (e) {
      error = 'Location filter: $e';
    }
  }

  Future<void> _detected(LoadedModel m, SpeciesLabel l, double score, DateTime now) async {
    final plate = settings.plateModel;
    final onPlate = plate == 'all' || plate == m.spec.id;
    if (onPlate && _sessionFull(l.sci)) await _nextSession(now);
    final key = '${m.spec.id}|${l.sci}';
    if (onPlate) _lastHeard[l.sci] = now;
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

  /// A new species for this session, which already holds [maxSessionSpecies]
  /// on its plate?
  bool _sessionFull(String sci) {
    final ses = session;
    if (ses == null) return false;
    final heard = {for (final d in store.forPlate(settings.plateModel, session: ses)) d.sci};
    return !heard.contains(sci) && heard.length >= maxSessionSpecies;
  }

  /// Close the full session and carry on listening in a new one, at the same
  /// place, starting with the bird that didn't fit.
  Future<void> _nextSession(DateTime now) async {
    final old = session!;
    await store.endSession(old, at: now.subtract(const Duration(milliseconds: 1)));
    session = await store.startSession(at: now, lat: old.lat, lon: old.lon);
    _open.clear();
    _lastHeard.clear();
    notifyListeners();
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

  /// Where this session is, for the plate and the location filter. Asks for
  /// permission the first time; listening goes on without it.
  Future<void> _locate(Session ses) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        locationNote = 'Location Services are off, so this session has no place.';
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) {
        locationNote = 'Location not allowed, so this session has no place.';
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      ses.lat = pos.latitude;
      ses.lon = pos.longitude;
      locationNote = null;
      _geoScores = null; // the location filter now knows where we are
      await store.saveSession(ses);
    } catch (e) {
      locationNote = 'Could not get a location: $e';
    } finally {
      notifyListeners();
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
