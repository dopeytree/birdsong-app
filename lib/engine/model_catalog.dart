// The models this test build can download and run.
//
// File names, sizes and repositories come from BirdNET-Go's model catalogue
// (internal/classifier/model_catalog*.go) and BirdNET Live's assets
// (assets/models/model_config.json). Every model is downloaded on the device
// at runtime; nothing large is committed to this repo.
//
// TEST BUILD: models marked `releaseOk: false` are here for research and
// comparison only and must be dropped before anything is sold.

/// How a model's raw output becomes a 0..1 score per species.
enum Activation {
  /// Already probabilities (sigmoid applied inside the graph). If any value
  /// falls outside 0..1 a sigmoid is applied after all.
  auto,

  /// Raw logits; one independent sigmoid per class (BirdNET v2.4).
  sigmoid,

  /// Raw logits; softmax across classes (Google Perch v2).
  softmax,
}

class ModelFile {
  const ModelFile(this.url, this.name, this.bytes);

  /// Where it is downloaded from.
  final String url;

  /// File name on the device.
  final String name;

  /// Expected size in bytes, 0 when not known. Shown in the Models screen.
  final int bytes;
}

class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.name,
    required this.family,
    required this.licence,
    required this.releaseOk,
    required this.sampleRate,
    required this.windowSeconds,
    required this.activation,
    required this.model,
    required this.labels,
    this.restLogit,
    this.namesFromSharedLabels = false,
    this.note = '',
  });

  final String id;
  final String name;
  final String family;
  final String licence;

  /// May this model ship in a paid app?
  final bool releaseOk;

  final int sampleRate;
  final double windowSeconds;
  final Activation activation;
  final ModelFile model;
  final ModelFile labels;

  /// Perch regional slices: the logit of the classes the slice dropped, added
  /// to the softmax so scores stay on the scale of the full model.
  final double? restLogit;

  /// The labels hold scientific names only (Perch); common names are taken
  /// from the shared BirdNET+ label file instead.
  final bool namesFromSharedLabels;

  final String note;

  int get windowSamples => (sampleRate * windowSeconds).round();

  int get totalBytes => model.bytes + labels.bytes;

  /// A copy with a newer build's files in place of these. Every other field
  /// stays: the name is unchanged, so a Settings row can append the build's
  /// label itself.
  ModelSpec copyWith({
    ModelFile? model,
    ModelFile? labels,
    double? restLogit,
    bool setRestLogit = false,
  }) {
    return ModelSpec(
      id: id,
      name: name,
      family: family,
      licence: licence,
      releaseOk: releaseOk,
      sampleRate: sampleRate,
      windowSeconds: windowSeconds,
      activation: activation,
      model: model ?? this.model,
      labels: labels ?? this.labels,
      restLogit: setRestLogit ? restLogit : this.restLogit,
      namesFromSharedLabels: namesFromSharedLabels,
      note: note,
    );
  }
}

String _hf(String repo, String path) =>
    'https://huggingface.co/$repo/resolve/main/$path';

// BirdNET Live, pinned to the commit this catalogue was written against.
const _bnlCommit = '02bd0150b66fbf07f6c91d99802975822dd4d9fc';
String _bnlLfs(String file) =>
    'https://media.githubusercontent.com/media/birdnet-team/birdnet-live-app/$_bnlCommit/assets/models/${Uri.encodeComponent(file)}';
String _bnlRaw(String file) =>
    'https://raw.githubusercontent.com/birdnet-team/birdnet-live-app/$_bnlCommit/assets/models/${Uri.encodeComponent(file)}';

/// Common names for every BirdNET+ species. Downloaded with any model whose
/// own labels carry scientific names only.
final sharedNames = ModelFile(
  _bnlRaw('BirdNET+_V3.0_Global_10K_FP16_BNL_Labels.csv'),
  'bnl_v3_10k_labels.csv',
  586577,
);

/// The geomodel: which species are likely at a place in a given week.
final geomodel = ModelSpec(
  id: 'geomodel-v3',
  name: 'BirdNET+ Geomodel V3.0.4 (10K)',
  family: 'Location filter',
  licence: 'Apache-2.0',
  releaseOk: true,
  sampleRate: 0,
  windowSeconds: 0,
  activation: Activation.auto,
  model: ModelFile(
    _bnlLfs('BirdNET+_Geomodel_V3.0.4_Global_10K_FP16_BNL.onnx'),
    'bnl_geomodel_v3.0.4_fp16.onnx',
    7589200,
  ),
  labels: ModelFile(
    _bnlRaw('BirdNET+_Geomodel_V3.0.4_Global_10K_FP16_BNL_Labels.txt'),
    'bnl_geomodel_v3.0.4_labels.txt',
    482501,
  ),
  note: 'Drops species unlikely at your latitude and longitude this week.',
);

final catalog = <ModelSpec>[
  ModelSpec(
    id: 'bnl-v3-10k',
    name: 'BirdNET+ V3.0 Global 10K, FP16',
    family: 'BirdNET+ V3.0',
    licence: 'Apache-2.0',
    releaseOk: true,
    sampleRate: 32000,
    windowSeconds: 3,
    activation: Activation.auto,
    model: ModelFile(
      _bnlLfs('BirdNET+_V3.0_Global_10K_FP16_BNL.onnx'),
      'bnl_v3_10k_fp16.onnx',
      67469056,
    ),
    labels: sharedNames,
    note: 'The phone build BirdNET Live ships: 10,048 species, 3 s windows.',
  ),
  ModelSpec(
    id: 'plus-v3-uk',
    name: 'BirdNET+ V3.0 British Isles, FP32',
    family: 'BirdNET+ V3.0',
    licence: 'Apache-2.0',
    releaseOk: true,
    sampleRate: 32000,
    windowSeconds: 5,
    activation: Activation.auto,
    model: ModelFile(
      _hf('tphakala/BirdNET-Plus-V3.0',
          'regional/british-isles/birdnet-plus-v3.0-british-isles-fp32-b1.onnx'),
      'birdnet_plus_v3.0_british-isles_fp32.onnx',
      120962591,
    ),
    labels: ModelFile(
      _hf('tphakala/BirdNET-Plus-V3.0',
          'regional/british-isles/birdnet-plus-v3.0-british-isles-labels-b1.txt'),
      'birdnet_plus_v3.0_british-isles_labels.txt',
      19692,
    ),
    note: 'Regional slice: only species of the British Isles.',
  ),
  ModelSpec(
    id: 'plus-v3-global',
    name: 'BirdNET+ V3.0 Global, FP32',
    family: 'BirdNET+ V3.0',
    licence: 'Apache-2.0',
    releaseOk: true,
    sampleRate: 32000,
    windowSeconds: 5,
    activation: Activation.auto,
    model: ModelFile(
      _hf('tphakala/BirdNET-Plus-V3.0', 'full/birdnet-plus-v3.0-fp32-b1.onnx'),
      'birdnet_plus_v3.0_fp32.onnx',
      360869106,
    ),
    labels: ModelFile(
      _hf('tphakala/BirdNET-Plus-V3.0', 'full/birdnet-plus-v3.0-labels-b1.txt'),
      'birdnet_plus_v3.0_labels.txt',
      470040,
    ),
    note: 'Full model, 11,725 classes. Needs a recent phone.',
  ),
  ModelSpec(
    id: 'v3-preview-uk',
    name: 'BirdNET V3.0 preview 3.1 British Isles, FP16',
    family: 'BirdNET V3.0 preview',
    licence: 'CC BY-SA 4.0',
    releaseOk: true,
    sampleRate: 32000,
    windowSeconds: 5,
    activation: Activation.auto,
    model: ModelFile(
      _hf('tphakala/BirdNET-v3.0-Models',
          'regional/british-isles/birdnet-v3.0-preview3.1-british-isles-fp16-b1.onnx'),
      'birdnet_v3.0_british-isles_fp16.onnx',
      70274590,
    ),
    labels: ModelFile(
      _hf('tphakala/BirdNET-v3.0-Models',
          'regional/british-isles/birdnet-v3.0-preview3.1-british-isles-labels-b1.txt'),
      'birdnet_v3.0_british-isles_labels.txt',
      19328,
    ),
    note: 'The developer preview, superseded by BirdNET+ V3.0. For comparison.',
  ),
  ModelSpec(
    id: 'perch-v2-uk',
    name: 'Google Perch v2 British Isles, FP32',
    family: 'Perch v2',
    licence: 'Apache-2.0',
    releaseOk: true,
    sampleRate: 32000,
    windowSeconds: 5,
    activation: Activation.softmax,
    restLogit: 9.71,
    namesFromSharedLabels: true,
    model: ModelFile(
      _hf('tphakala/Perch-v2-Models',
          'regional/british-isles/perch_v2_british-isles_no_dft_fp32.onnx'),
      'perch_v2_british-isles_no_dft.onnx',
      68416104,
    ),
    labels: ModelFile(
      _hf('tphakala/Perch-v2-Models',
          'regional/british-isles/perch_v2_british-isles_labels.txt'),
      'perch_v2_british-isles_labels.txt',
      12955,
    ),
    note: '776 classes. Softmax scores run lower than BirdNET\'s: try a lower threshold.',
  ),
  ModelSpec(
    id: 'perch-v2-global',
    name: 'Google Perch v2 Global, FP32',
    family: 'Perch v2',
    licence: 'Apache-2.0',
    releaseOk: true,
    sampleRate: 32000,
    windowSeconds: 5,
    activation: Activation.softmax,
    namesFromSharedLabels: true,
    model: ModelFile(
      _hf('tphakala/Perch-v2-Models', 'full/perch_v2_no_dft_fp32.onnx'),
      'perch_v2_no_dft.onnx',
      413350933,
    ),
    labels: ModelFile(
      _hf('tphakala/Perch-v2-Models', 'full/perch_v2_labels.txt'),
      'perch_v2_labels.txt',
      312716,
    ),
    note: '14,795 classes. Large: a recent phone or the Mac.',
  ),
  ModelSpec(
    id: 'birdnet-v24',
    name: 'BirdNET v2.4, FP32',
    family: 'BirdNET v2.4',
    licence: 'CC BY-NC-SA 4.0',
    releaseOk: false,
    sampleRate: 48000,
    windowSeconds: 3,
    activation: Activation.sigmoid,
    model: ModelFile(
      _hf('tphakala/BirdNET-v2.4', 'BirdNET_v2.4_fp32_dfttrunc.onnx'),
      'BirdNET_v2.4_fp32_dfttrunc.onnx',
      54068648,
    ),
    labels: ModelFile(
      _hf('tphakala/BirdNET-v2.4', 'labels.txt'),
      'birdnet_v2.4_labels.txt',
      0,
    ),
    note: 'What most BirdNET-Go stations run. Non-commercial: testing only.',
  ),
];

ModelSpec? specById(String id) {
  if (id == geomodel.id) return geomodel;
  for (final s in catalog) {
    if (s.id == id) return s;
  }
  return null;
}

/// [s] with a downloaded newer build in place of the catalogue file, or [s]
/// itself when [overrides] has nothing usable for it. A half-written or
/// garbage override is ignored whole. The name is left as it is.
ModelSpec effective(ModelSpec s, Map<String, Map<String, dynamic>> overrides) {
  final o = overrides[s.id];
  if (o == null) return s;
  final modelUrl = o['modelUrl'];
  final modelName = o['modelName'];
  final labelsUrl = o['labelsUrl'];
  final labelsName = o['labelsName'];
  final modelBytes = o['modelBytes'];
  final labelsBytes = o['labelsBytes'];
  if (modelUrl is! String ||
      modelUrl.isEmpty ||
      modelName is! String ||
      modelName.isEmpty ||
      labelsUrl is! String ||
      labelsUrl.isEmpty ||
      labelsName is! String ||
      labelsName.isEmpty ||
      modelBytes is! num ||
      !modelBytes.isFinite ||
      labelsBytes is! num ||
      !labelsBytes.isFinite) {
    return s;
  }
  final rest = o['restLogit'];
  final replaceRest = rest is num && rest.isFinite;
  return s.copyWith(
    model: ModelFile(modelUrl, modelName, modelBytes.toInt()),
    labels: ModelFile(labelsUrl, labelsName, labelsBytes.toInt()),
    restLogit: replaceRest ? rest.toDouble() : null,
    setRestLogit: replaceRest,
  );
}

/// [catalog] as installed, newer builds included.
List<ModelSpec> effectiveCatalog(Map<String, Map<String, dynamic>> overrides) =>
    [for (final s in catalog) effective(s, overrides)];

/// [specById] with any downloaded newer build applied.
ModelSpec? effectiveById(String id, Map<String, Map<String, dynamic>> overrides) {
  final s = specById(id);
  return s == null ? null : effective(s, overrides);
}
