// A daily look at Hugging Face for a newer build of a model already
// installed, and the offer to download it. The geomodel and BirdNET Live's
// 10K build come from GitHub and have no manifest, so they are left alone.
//
// The manifest and the choice of successor are pure, so they can be tested
// without the network. A failed fetch leaves the last offers as they were
// and does not move the next check forward.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../settings.dart';
import 'model_catalog.dart';
import 'model_manager.dart';

/// `https://huggingface.co/<owner>/<repo>/resolve/main/<path>`.
class HfRef {
  const HfRef(this.repo, this.path);

  final String repo;
  final String path;
}

/// One newer build the user can take in place of an installed model.
class ModelOffer {
  const ModelOffer({
    required this.spec,
    required this.path,
    required this.label,
    required this.model,
    required this.labels,
    required this.sha256,
    required this.labelsSha256,
    this.restLogit,
  });

  final ModelSpec spec;

  /// Path inside the Hugging Face repo. Also the key for snooze and skip.
  final String path;

  /// "v3.0.1, build 1".
  final String label;
  final ModelFile model;
  final ModelFile labels;
  final String sha256;
  final String labelsSha256;
  final double? restLogit;
}

/// One model in a repo's models.json.
class ManifestEntry {
  const ManifestEntry({
    required this.path,
    required this.build,
    required this.upstreamVersion,
    required this.variant,
    required this.region,
    required this.legacy,
    required this.supersededBy,
    required this.sizeBytes,
    required this.sha256,
    required this.labels,
    required this.labelsSizeBytes,
    required this.labelsSha256,
    required this.sampleRate,
    required this.windowSeconds,
    required this.restLogit,
  });

  final String path;
  final int build;
  final String upstreamVersion;
  final String variant;
  final String? region;
  final bool legacy;
  final String? supersededBy;
  final int sizeBytes;
  final String sha256;
  final String labels;
  final int labelsSizeBytes;
  final String labelsSha256;
  final int? sampleRate;
  final double? windowSeconds;
  final double? restLogit;
}

HfRef? hfRefOf(ModelFile f) => _hfRefOf(f);

/// File names still needed after a newer build is taken: every installed
/// spec's model and labels (overrides applied), and the shared names file.
Set<String> namesInUse(
  Map<String, Map<String, dynamic>> overrides,
  bool Function(ModelSpec spec) installed,
) {
  final names = <String>{sharedNames.name};
  for (final base in [geomodel, ...catalog]) {
    final spec = effective(base, overrides);
    if (!installed(spec)) continue;
    names.add(spec.model.name);
    names.add(spec.labels.name);
  }
  return names;
}

/// Reads a models.json object. Throws if it has no models list; a single
/// odd entry is skipped rather than failing the whole file.
List<ManifestEntry> parseManifest(Map<String, dynamic> json) {
  final raw = json['models'];
  if (raw is! List) throw const FormatException('manifest has no models list');
  final out = <ManifestEntry>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final entry = _parseEntry(item);
    if (entry != null) out.add(entry);
  }
  return out;
}

/// The successor of [currentPath] in [manifest], or null when ours is already
/// the newest we can run. [spec] supplies the sample rate and window a
/// successor must keep.
ModelOffer? successorOf({
  required ModelSpec spec,
  required String currentPath,
  required String repo,
  required Map<String, dynamic> manifest,
  Set<String> skipped = const {},
}) {
  final models = parseManifest(manifest);
  final byPath = {for (final m in models) m.path: m};
  final ours = byPath[currentPath];
  final chained = _chainEnd(byPath, currentPath);
  if (chained != null && chained.path != currentPath) {
    // The publisher named this file. A skipped path, or one whose input
    // does not match, is not replaced by a guess.
    if (skipped.contains(chained.path) || !_inputOk(chained, spec)) return null;
    return _toOffer(spec, repo, chained);
  }
  final region = ours?.region ?? _regionFromPath(currentPath);
  final variant = (ours != null && ours.variant.isNotEmpty) ? ours.variant : _variantFromPath(currentPath);
  if (variant == null) return null;
  final noDft = _noDft(currentPath);
  final oursVersion = ours != null ? _versionOf(ours.upstreamVersion, ours.build) : _versionFromPath(currentPath);
  // Missing from the manifest, and the path yields no version: offer nothing.
  if (oursVersion == null) return null;
  ManifestEntry? best;
  _Version? bestVersion;
  for (final m in models) {
    if (m.path == currentPath) continue;
    if (m.legacy) continue;
    if (m.supersededBy != null) continue;
    if (m.region != region || m.variant != variant) continue;
    if (_noDft(m.path) != noDft) continue;
    if (skipped.contains(m.path) || !_inputOk(m, spec)) continue;
    final version = _versionOf(m.upstreamVersion, m.build);
    if (version == null) continue;
    if (bestVersion == null || version.compareTo(bestVersion) > 0) {
      best = m;
      bestVersion = version;
    }
  }
  if (best == null || bestVersion!.compareTo(oursVersion) <= 0) return null;
  return _toOffer(spec, repo, best);
}

/// Checks installed models for a newer build, and remembers what the user
/// did with each offer.
class ModelUpdates extends ChangeNotifier {
  ModelUpdates(this.settings, this.models);

  final Settings settings;
  final ModelManager models;

  /// Offers from the last check that succeeded. Empty until then.
  List<ModelOffer> offers = [];

  /// The offer being downloaded, if any.
  ModelOffer? busy;

  /// The offer whose download just failed, until the user closes the notice.
  ModelOffer? failed;

  bool _checking = false;

  /// When a check was last started, epoch ms. A failed check must not be
  /// retried on every resume; automatic checks wait an hour.
  int? _lastAttempt;

  /// True while a check is in flight.
  bool get checking => _checking;

  /// Paths hidden until the next successful check (a closed failure).
  final Set<String> _held = {};

  HfRef? hfRefOf(ModelFile f) => _hfRefOf(f);

  /// The first offer that is not snoozed, skipped or held. Null while a
  /// download or its failure is on show, so the strip shows that instead.
  ModelOffer? get notice {
    if (busy != null || failed != null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final o in offers) {
      if (_held.contains(o.path) || settings.modelSkipped.contains(o.path)) continue;
      final until = settings.modelSnoozed[o.path];
      if (until != null && until > now) continue;
      return o;
    }
    return null;
  }

  /// An offer for this spec still in the last check, snoozed or not.
  ModelOffer? offerFor(String specId) {
    for (final o in offers) {
      if (o.spec.id == specId && !settings.modelSkipped.contains(o.path)) return o;
    }
    return null;
  }

  /// Looks up newer builds when the last successful check was 24 hours ago,
  /// or at once when [force] is set. A check already running is left to finish,
  /// and a check started in the last hour is not repeated unless forced.
  /// On any failure the offers stay as they were, and the clock is not moved.
  Future<void> checkIfDue({bool force = false}) async {
    if (_checking) return;
    if (!force && !_due()) return;
    _lastAttempt = DateTime.now().millisecondsSinceEpoch;
    _checking = true;
    notifyListeners();
    try {
      final next = await _collect();
      offers = next;
      _held.clear();
      failed = null;
      settings.update((s) => s.modelCheckAt = DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('model updates: check failed ($e)');
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Downloads the newer build, remembers it, and removes the files it
  /// replaces. A session already listening keeps the files it opened; the
  /// new ones are read the next time listening starts.
  Future<void> accept(ModelOffer o) async {
    if (busy != null) return;
    busy = o;
    failed = null;
    _held.remove(o.path);
    models.errors.remove(o.spec.id);
    models.progress[o.spec.id] = 0;
    models.notifyListeners();
    notifyListeners();
    final previous = effective(o.spec, settings.modelOverrides);
    try {
      final files = [
        (file: o.model, sha256: o.sha256),
        (file: o.labels, sha256: o.labelsSha256),
      ];
      final total = files.fold<int>(0, (a, f) => a + (f.file.bytes > 0 ? f.file.bytes : 1));
      var done = 0;
      for (final f in files) {
        await models.downloadFile(f.file, sha256: f.sha256, onProgress: (got) {
          models.progress[o.spec.id] =
              total == 0 ? 1.0 : ((done + got) / total).clamp(0.0, 1.0).toDouble();
          models.notifyListeners();
        });
        done += f.file.bytes > 0 ? f.file.bytes : 1;
      }
      settings.update((s) {
        s.modelOverrides[o.spec.id] = {
          'path': o.path,
          'label': o.label,
          'modelUrl': o.model.url,
          'modelName': o.model.name,
          'modelBytes': o.model.bytes,
          'sha256': o.sha256,
          'labelsUrl': o.labels.url,
          'labelsName': o.labels.name,
          'labelsBytes': o.labels.bytes,
          'restLogit': o.restLogit,
        };
      });
      try {
        await models.deleteReplaced(
          [previous.model, previous.labels],
          keep: namesInUse(settings.modelOverrides, models.isInstalled),
        );
      } catch (e) {
        debugPrint('model updates: could not remove the old files ($e)');
      }
      offers = [for (final x in offers) if (x.path != o.path && x.spec.id != o.spec.id) x];
    } catch (e) {
      debugPrint('model updates: download failed ($e)');
      models.errors[o.spec.id] = e.toString();
      failed = o;
    } finally {
      busy = null;
      models.progress.remove(o.spec.id);
      models.notifyListeners();
      notifyListeners();
    }
  }

  /// Hides the notice for a week. The offer stays, and comes back after.
  void snooze(ModelOffer o) {
    settings.update((s) {
      s.modelSnoozed[o.path] =
          DateTime.now().millisecondsSinceEpoch + const Duration(days: 7).inMilliseconds;
    });
    if (failed?.path == o.path) failed = null;
    notifyListeners();
  }

  /// Never offer this path again.
  void skip(ModelOffer o) {
    settings.update((s) => s.modelSkipped.add(o.path));
    offers = [for (final x in offers) if (x.path != o.path) x];
    if (failed?.path == o.path) failed = null;
    notifyListeners();
  }

  /// Drops the failure notice. The build is offered again at the next check.
  void dismissFailure() {
    final path = failed?.path;
    failed = null;
    if (path != null) _held.add(path);
    notifyListeners();
  }

  bool _due() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final attempt = _lastAttempt;
    if (attempt != null && now - attempt < const Duration(hours: 1).inMilliseconds) return false;
    final last = settings.modelCheckAt;
    if (last <= 0) return true;
    return now - last >= const Duration(hours: 24).inMilliseconds;
  }

  Future<List<ModelOffer>> _collect() async {
    final work = <({ModelSpec spec, HfRef ref})>[];
    for (final base in catalog) {
      final current = effective(base, settings.modelOverrides);
      if (!models.isInstalled(current)) continue;
      final ref = hfRefOf(current.model);
      if (ref == null) continue;
      work.add((spec: base, ref: ref));
    }
    final manifests = <String, Map<String, dynamic>>{};
    for (final repo in {for (final w in work) w.ref.repo}) {
      manifests[repo] = await _fetchManifest(repo);
    }
    final skipped = settings.modelSkipped;
    final out = <ModelOffer>[];
    for (final w in work) {
      final offer = successorOf(
        spec: w.spec,
        currentPath: w.ref.path,
        repo: w.ref.repo,
        manifest: manifests[w.ref.repo]!,
        skipped: skipped,
      );
      if (offer != null) out.add(offer);
    }
    return out;
  }
}

const _manifestTimeout = Duration(seconds: 20);

Future<Map<String, dynamic>> _fetchManifest(String repo) async {
  final client = HttpClient()..connectionTimeout = _manifestTimeout;
  try {
    final url = Uri.parse('https://huggingface.co/$repo/resolve/main/models.json');
    final req = await client.getUrl(url).timeout(_manifestTimeout);
    req.followRedirects = true;
    req.maxRedirects = 10;
    req.headers.set(HttpHeaders.userAgentHeader, 'Birdsong');
    final res = await req.close().timeout(_manifestTimeout);
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('${res.statusCode} for $url');
    }
    final body = await res.transform(utf8.decoder).join().timeout(_manifestTimeout);
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('manifest is not an object');
    return Map<String, dynamic>.from(decoded);
  } finally {
    client.close(force: true);
  }
}

HfRef? _hfRefOf(ModelFile f) {
  final uri = Uri.tryParse(f.url);
  if (uri == null || uri.scheme != 'https' || uri.host != 'huggingface.co') return null;
  final segs = uri.pathSegments;
  if (segs.length < 5 || segs[2] != 'resolve' || segs[3] != 'main') return null;
  if (segs[0].isEmpty || segs[1].isEmpty) return null;
  final path = segs.sublist(4).join('/');
  if (path.isEmpty) return null;
  return HfRef('${segs[0]}/${segs[1]}', path);
}

ManifestEntry? _parseEntry(Map<dynamic, dynamic> m) {
  final path = m['path'];
  if (path is! String || path.isEmpty) return null;
  final input = m['input'];
  int? sampleRate;
  double? windowSeconds;
  if (input is Map) {
    final sr = input['sample_rate'];
    final w = input['window_seconds'];
    if (sr is num) sampleRate = sr.toInt();
    if (w is num) windowSeconds = w.toDouble();
  }
  double? rest;
  final cal = m['score_calibration'];
  if (cal is Map) {
    final r = cal['rest_logit'];
    if (r is num) rest = r.toDouble();
  }
  return ManifestEntry(
    path: path,
    build: (m['build'] as num?)?.toInt() ?? 0,
    upstreamVersion: m['upstream_version'] is String ? m['upstream_version'] as String : '',
    variant: m['variant'] is String ? m['variant'] as String : '',
    region: m['region'] is String && (m['region'] as String).isNotEmpty ? m['region'] as String : null,
    legacy: m['legacy'] == true,
    supersededBy: m['superseded_by'] is String && (m['superseded_by'] as String).isNotEmpty
        ? m['superseded_by'] as String
        : null,
    sizeBytes: (m['size_bytes'] as num?)?.toInt() ?? 0,
    sha256: m['sha256'] is String ? m['sha256'] as String : '',
    labels: m['labels'] is String ? m['labels'] as String : '',
    labelsSizeBytes: (m['labels_size_bytes'] as num?)?.toInt() ?? 0,
    labelsSha256: m['labels_sha256'] is String ? m['labels_sha256'] as String : '',
    sampleRate: sampleRate,
    windowSeconds: windowSeconds,
    restLogit: rest,
  );
}

/// Follows superseded_by to the last file that exists. A loop stops at the
/// last new entry. Null when [start] itself is not in the manifest.
ManifestEntry? _chainEnd(Map<String, ManifestEntry> byPath, String start) {
  final seen = <String>{};
  var path = start;
  ManifestEntry? last;
  while (seen.add(path)) {
    final entry = byPath[path];
    if (entry == null) return last;
    last = entry;
    final next = entry.supersededBy;
    if (next == null) return entry;
    path = next;
  }
  return last;
}

bool _inputOk(ManifestEntry m, ModelSpec spec) {
  if (m.sampleRate == null || m.windowSeconds == null) return false;
  return m.sampleRate == spec.sampleRate && m.windowSeconds == spec.windowSeconds;
}

ModelOffer? _toOffer(ModelSpec spec, String repo, ManifestEntry m) {
  if (m.sha256.isEmpty || m.labels.isEmpty || m.labelsSha256.isEmpty) return null;
  return ModelOffer(
    spec: spec,
    path: m.path,
    label: _label(m.upstreamVersion, m.build),
    model: ModelFile(_hfUrl(repo, m.path), _baseName(m.path), m.sizeBytes),
    labels: ModelFile(_hfUrl(repo, m.labels), _baseName(m.labels), m.labelsSizeBytes),
    sha256: m.sha256,
    labelsSha256: m.labelsSha256,
    restLogit: m.restLogit,
  );
}

String _hfUrl(String repo, String path) => 'https://huggingface.co/$repo/resolve/main/$path';

String _baseName(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

String _label(String upstream, int build) {
  final raw = upstream.trim();
  if (raw.isEmpty) return 'build $build';
  final version = raw.startsWith('v') || raw.startsWith('V') ? raw : 'v$raw';
  return '$version, build $build';
}

bool _noDft(String path) {
  final lower = path.toLowerCase();
  return lower.contains('no_dft') || lower.contains('no-dft');
}

String? _regionFromPath(String path) {
  final parts = path.split('/');
  if (parts.length >= 3 && parts.first == 'regional' && parts[1].isNotEmpty) return parts[1];
  return null;
}

String? _variantFromPath(String path) {
  final lower = path.toLowerCase();
  String? prec;
  if (lower.contains('fp16')) {
    prec = 'fp16';
  } else if (lower.contains('fp32')) {
    prec = 'fp32';
  } else if (lower.contains('int8')) {
    prec = 'int8';
  }
  if (prec == null) return null;
  return _noDft(path) ? 'no-dft-$prec' : prec;
}

class _Version implements Comparable<_Version> {
  const _Version(this.parts, this.build);

  final List<int> parts;
  final int build;

  @override
  int compareTo(_Version other) {
    final n = parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var i = 0; i < n; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return build.compareTo(other.build);
  }
}

_Version? _versionOf(String upstream, int build) {
  final parts = _versionParts(upstream);
  if (parts == null) return null;
  return _Version(parts, build);
}

_Version? _versionFromPath(String path) {
  final vm = RegExp(r'v(\d+(?:\.\d+)*)').firstMatch(path);
  if (vm == null) return null;
  final bm = RegExp(r'-b(\d+)').firstMatch(path);
  return _Version(
    [for (final p in vm.group(1)!.split('.')) int.parse(p)],
    bm == null ? 0 : int.parse(bm.group(1)!),
  );
}

List<int>? _versionParts(String raw) {
  final m = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(raw.trim());
  if (m == null) return null;
  return [for (final p in m.group(1)!.split('.')) int.parse(p)];
}
