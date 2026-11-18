import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'labels.dart';
import 'model_catalog.dart';

/// ONNX Runtime 1.23+ routes fp32 GEMM on arm64 through Arm KleidiAI kernels,
/// which crashed and misbehaved on some Android phones. BirdNET Live turns
/// them off with this key on every session; so do we.
const _sessionConfigs = {'mlas.disable_kleidiai': '1'};

OrtSessionOptions sessionOptions({bool coreMl = false}) => OrtSessionOptions(
      providers: coreMl
          ? const [OrtProvider.CORE_ML, OrtProvider.CPU]
          : const [OrtProvider.CPU],
      sessionConfigs: _sessionConfigs,
    );

class Score {
  const Score(this.index, this.value);
  final int index;
  final double value;
}

class Prediction {
  const Prediction(this.scores, this.millis);

  /// One 0..1 score per label.
  final Float32List scores;

  /// Time spent inside ONNX Runtime, in milliseconds.
  final int millis;

  List<Score> top(int k, {bool Function(int index)? keep}) {
    final out = <Score>[];
    for (var i = 0; i < scores.length; i++) {
      if (keep != null && !keep(i)) continue;
      final v = scores[i];
      if (out.length < k) {
        out.add(Score(i, v));
        out.sort((a, b) => b.value.compareTo(a.value));
      } else if (v > out.last.value) {
        out[out.length - 1] = Score(i, v);
        out.sort((a, b) => b.value.compareTo(a.value));
      }
    }
    return out;
  }
}

/// One audio model, loaded and ready.
class LoadedModel {
  LoadedModel._(this.spec, this._session, this.labels, this._inputName);

  final ModelSpec spec;
  final OrtSession _session;
  final List<SpeciesLabel> labels;
  final String _inputName;

  static Future<LoadedModel> load({
    required ModelSpec spec,
    required File modelFile,
    required File labelsFile,
    Map<String, String> names = const {},
    bool coreMl = false,
  }) async {
    var labels = parseLabels(await labelsFile.readAsString());
    if (names.isNotEmpty) {
      labels = [
        for (final l in labels)
          (l.common == l.sci && names[l.sci] != null)
              ? l.withCommon(names[l.sci]!)
              : l,
      ];
    }
    final session = await OnnxRuntime()
        .createSession(modelFile.path, options: sessionOptions(coreMl: coreMl));
    final input = session.inputNames.isNotEmpty ? session.inputNames.first : 'input';
    return LoadedModel._(spec, session, labels, input);
  }

  int get windowSamples => spec.windowSamples;

  Future<Prediction> predict(Float32List audio) async {
    final sw = Stopwatch()..start();
    final input = await OrtValue.fromList(audio, [1, audio.length]);
    Map<String, OrtValue>? outputs;
    try {
      outputs = await _session.run({_inputName: input});
      // Pick the output with one value per label: v3.0 graphs also return
      // embeddings, Perch returns embeddings and a spectrogram too.
      OrtValue? chosen;
      for (final v in outputs.values) {
        if (v.shape.isNotEmpty && v.shape.last == labels.length) {
          chosen = v;
          break;
        }
      }
      if (chosen == null) {
        final shapes = outputs.map((k, v) => MapEntry(k, v.shape));
        throw StateError(
            '${spec.name}: no output has ${labels.length} values $shapes');
      }
      final raw = await chosen.asFlattenedList();
      final scores = Float32List(labels.length);
      for (var i = 0; i < scores.length; i++) {
        scores[i] = (raw[i] as num).toDouble();
      }
      _activate(scores);
      sw.stop();
      return Prediction(scores, sw.elapsedMilliseconds);
    } finally {
      await input.dispose();
      if (outputs != null) {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    }
  }

  void _activate(Float32List s) {
    switch (spec.activation) {
      case Activation.auto:
        var inRange = true;
        for (final v in s) {
          if (v < 0 || v > 1 || v.isNaN) {
            inRange = false;
            break;
          }
        }
        if (!inRange) _sigmoid(s);
      case Activation.sigmoid:
        _sigmoid(s);
      case Activation.softmax:
        _softmax(s, spec.restLogit);
    }
  }

  static void _sigmoid(Float32List s) {
    for (var i = 0; i < s.length; i++) {
      s[i] = 1 / (1 + math.exp(-s[i]));
    }
  }

  static void _softmax(Float32List s, double? rest) {
    var mx = rest ?? double.negativeInfinity;
    for (final v in s) {
      if (v > mx) mx = v;
    }
    var sum = rest == null ? 0.0 : math.exp(rest - mx);
    final e = Float64List(s.length);
    for (var i = 0; i < s.length; i++) {
      e[i] = math.exp(s[i] - mx);
      sum += e[i];
    }
    for (var i = 0; i < s.length; i++) {
      s[i] = e[i] / sum;
    }
  }

  Future<void> close() => _session.close();
}

/// The geomodel: likely species at a place and week.
class GeoFilter {
  GeoFilter._(this._session, this._labels, this._input);

  final OrtSession _session;
  final List<SpeciesLabel> _labels;
  final String _input;

  static Future<GeoFilter> load(File modelFile, File labelsFile) async {
    final labels = parseLabels(await labelsFile.readAsString());
    final session =
        await OnnxRuntime().createSession(modelFile.path, options: sessionOptions());
    final input = session.inputNames.isNotEmpty ? session.inputNames.first : 'input';
    return GeoFilter._(session, labels, input);
  }

  /// BirdNET's 48-week year: four weeks to a month.
  static int weekOf(DateTime d) => (d.month - 1) * 4 + math.min((d.day - 1) ~/ 7 + 1, 4);

  /// Scientific name to occurrence score, 0..1.
  Future<Map<String, double>> scores(double lat, double lon, DateTime when) async {
    final input = await OrtValue.fromList(
        Float32List.fromList([lat, lon, weekOf(when).toDouble()]), [1, 3]);
    Map<String, OrtValue>? outputs;
    try {
      outputs = await _session.run({_input: input});
      final out = outputs.values.firstWhere(
          (v) => v.shape.isNotEmpty && v.shape.last == _labels.length,
          orElse: () => outputs!.values.first);
      final raw = await out.asFlattenedList();
      final map = <String, double>{};
      final n = math.min(raw.length, _labels.length);
      for (var i = 0; i < n; i++) {
        map[_labels[i].sci] = (raw[i] as num).toDouble();
      }
      return map;
    } finally {
      await input.dispose();
      if (outputs != null) {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    }
  }

  Future<void> close() => _session.close();
}
