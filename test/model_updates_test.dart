import 'dart:convert';
import 'dart:io';

import 'package:birdsong_app/engine/model_catalog.dart';
import 'package:birdsong_app/engine/model_manager.dart';
import 'package:birdsong_app/engine/model_updates.dart';
import 'package:birdsong_app/settings.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _manifest(String json) => jsonDecode(json) as Map<String, dynamic>;

/// The old global file is not listed. Decoys are newer, and must not be chosen:
/// fp16, a regional slice, a no-dft file, a different sample rate, a legacy
/// file, and one already superseded.
const _plusMissing = r'''
{
  "models": [
    {
      "path": "full/birdnet-plus-v2.4-fp32-b1.onnx",
      "build": 1, "upstream_version": "2.4", "variant": "fp32", "region": null,
      "legacy": false, "superseded_by": null,
      "size_bytes": 10, "sha256": "old", "labels": "full/old.txt",
      "labels_size_bytes": 1, "labels_sha256": "oldl",
      "input": {"sample_rate": 32000, "window_seconds": 5}
    },
    {
      "path": "full/birdnet-plus-v9.9-fp16-b1.onnx",
      "build": 1, "upstream_version": "9.9", "variant": "fp16", "region": null,
      "legacy": false, "superseded_by": null,
      "size_bytes": 11, "sha256": "fp16", "labels": "full/fp16.txt",
      "labels_size_bytes": 1, "labels_sha256": "fp16l",
      "input": {"sample_rate": 32000, "window_seconds": 5}
    },
    {
      "path": "regional/british-isles/birdnet-plus-v9.9-british-isles-fp32-b2.onnx",
      "build": 2, "upstream_version": "9.9", "variant": "fp32", "region": "british-isles",
      "legacy": false, "superseded_by": null,
      "size_bytes": 12, "sha256": "reg", "labels": "regional/british-isles/reg.txt",
      "labels_size_bytes": 1, "labels_sha256": "regl",
      "input": {"sample_rate": 32000, "window_seconds": 5}
    },
    {
      "path": "full/birdnet-plus-v9.9-no-dft-fp32-b1.onnx",
      "build": 1, "upstream_version": "9.9", "variant": "fp32", "region": null,
      "legacy": false, "superseded_by": null,
      "size_bytes": 13, "sha256": "nodft", "labels": "full/nodft.txt",
      "labels_size_bytes": 1, "labels_sha256": "nodftl",
      "input": {"sample_rate": 32000, "window_seconds": 5}
    },
    {
      "path": "full/birdnet-plus-v9.9-fp32-b1.onnx",
      "build": 1, "upstream_version": "9.9", "variant": "fp32", "region": null,
      "legacy": false, "superseded_by": null,
      "size_bytes": 14, "sha256": "rate", "labels": "full/rate.txt",
      "labels_size_bytes": 1, "labels_sha256": "ratel",
      "input": {"sample_rate": 48000, "window_seconds": 5}
    },
    {
      "path": "full/birdnet-plus-v9.9-legacy-fp32-b1.onnx",
      "build": 1, "upstream_version": "9.9", "variant": "fp32", "region": null,
      "legacy": true, "superseded_by": null,
      "size_bytes": 15, "sha256": "leg", "labels": "full/leg.txt",
      "labels_size_bytes": 1, "labels_sha256": "legl",
      "input": {"sample_rate": 32000, "window_seconds": 5}
    },
    {
      "path": "full/birdnet-plus-v9.9-gone-fp32-b1.onnx",
      "build": 1, "upstream_version": "9.9", "variant": "fp32", "region": null,
      "legacy": false, "superseded_by": "full/birdnet-plus-v9.9-gone-fp32-b2.onnx",
      "size_bytes": 16, "sha256": "sup", "labels": "full/sup.txt",
      "labels_size_bytes": 1, "labels_sha256": "supl",
      "input": {"sample_rate": 32000, "window_seconds": 5}
    },
    {
      "path": "full/birdnet-plus-v3.0.1-fp32-b1.onnx",
      "build": 1, "upstream_version": "3.0.1", "variant": "fp32", "region": null,
      "legacy": false, "superseded_by": null,
      "size_bytes": 344606647, "sha256": "winner",
      "labels": "full/birdnet-plus-v3.0.1-labels-b1.txt",
      "labels_size_bytes": 470040, "labels_sha256": "winnerl",
      "input": {"sample_rate": 32000, "window_seconds": 5}
    }
  ]
}
''';

/// b1 points at a middle build, which points at b2. Stopping early would
/// keep the middle file's rest logit of 1.
const _perchChain = r'''
{
  "models": [
    {
      "path": "regional/british-isles/perch_v2_british-isles_no_dft_fp32.onnx",
      "build": 1, "upstream_version": "2", "variant": "no-dft-fp32", "region": "british-isles",
      "legacy": true,
      "superseded_by": "regional/british-isles/perch-v2-british-isles-no-dft-fp32-b1.onnx",
      "size_bytes": 68416104, "sha256": "old",
      "labels": "regional/british-isles/perch_v2_british-isles_labels.txt",
      "labels_size_bytes": 12955, "labels_sha256": "oldl",
      "input": {"sample_rate": 32000, "window_seconds": 5},
      "score_calibration": {"method": "softmax-rest-logit", "rest_logit": 9.71}
    },
    {
      "path": "regional/british-isles/perch-v2-british-isles-no-dft-fp32-b1.onnx",
      "build": 1, "upstream_version": "2", "variant": "no-dft-fp32", "region": "british-isles",
      "legacy": true,
      "superseded_by": "regional/british-isles/perch-v2-british-isles-no-dft-fp32-b2.onnx",
      "size_bytes": 1, "sha256": "mid",
      "labels": "regional/british-isles/perch-v2-british-isles-labels-b1.txt",
      "labels_size_bytes": 1, "labels_sha256": "midl",
      "input": {"sample_rate": 32000, "window_seconds": 5},
      "score_calibration": {"method": "softmax-rest-logit", "rest_logit": 1}
    },
    {
      "path": "regional/british-isles/perch-v2-british-isles-no-dft-fp32-b2.onnx",
      "build": 2, "upstream_version": "2", "variant": "no-dft-fp32", "region": "british-isles",
      "legacy": false, "superseded_by": null,
      "size_bytes": 68883428, "sha256": "b2",
      "labels": "regional/british-isles/perch-v2-british-isles-labels-b2.txt",
      "labels_size_bytes": 13280, "labels_sha256": "b2l",
      "input": {"sample_rate": 32000, "window_seconds": 5},
      "score_calibration": {"method": "softmax-rest-logit", "rest_logit": 9.7}
    }
  ]
}
''';

void main() {
  test('hfRefOf reads a Hugging Face resolve url and nothing else', () {
    final global = specById('plus-v3-global')!;
    final ref = hfRefOf(global.model)!;
    expect(ref.repo, 'tphakala/BirdNET-Plus-V3.0');
    expect(ref.path, 'full/birdnet-plus-v3.0-fp32-b1.onnx');
    expect(hfRefOf(global.labels)!.path, 'full/birdnet-plus-v3.0-labels-b1.txt');
    final perch = hfRefOf(specById('perch-v2-uk')!.model)!;
    expect(perch.repo, 'tphakala/Perch-v2-Models');
    expect(perch.path, 'regional/british-isles/perch_v2_british-isles_no_dft_fp32.onnx');
    expect(hfRefOf(geomodel.model), isNull);
    expect(hfRefOf(sharedNames), isNull);
    expect(hfRefOf(specById('bnl-v3-10k')!.model), isNull);
    expect(hfRefOf(ModelFile('https://example.com/a.onnx', 'a.onnx', 1)), isNull);
    expect(hfRefOf(ModelFile('https://huggingface.co/only-one', 'a.onnx', 1)), isNull);
  });

  test('a superseded_by chain ends at perch british-isles b2, rest logit 9.7', () {
    final perch = specById('perch-v2-uk')!;
    final ref = hfRefOf(perch.model)!;
    final offer = successorOf(
      spec: perch,
      currentPath: ref.path,
      repo: ref.repo,
      manifest: _manifest(_perchChain),
    );
    expect(offer, isNotNull);
    expect(offer!.path, 'regional/british-isles/perch-v2-british-isles-no-dft-fp32-b2.onnx');
    expect(offer.restLogit, closeTo(9.7, 1e-9));
    expect(offer.label, 'v2, build 2');
    expect(offer.model.name, 'perch-v2-british-isles-no-dft-fp32-b2.onnx');
    expect(offer.model.bytes, 68883428);
    expect(offer.model.url,
        'https://huggingface.co/tphakala/Perch-v2-Models/resolve/main/${offer.path}');
    expect(offer.labels.name, 'perch-v2-british-isles-labels-b2.txt');
    expect(offer.sha256, 'b2');
    expect(offer.labelsSha256, 'b2l');
  });

  test('a missing entry falls back to the newest same-kind build', () {
    final global = specById('plus-v3-global')!;
    final ref = hfRefOf(global.model)!;
    expect(ref.path, 'full/birdnet-plus-v3.0-fp32-b1.onnx');
    final offer = successorOf(
      spec: global,
      currentPath: ref.path,
      repo: ref.repo,
      manifest: _manifest(_plusMissing),
    );
    expect(offer, isNotNull);
    expect(offer!.path, 'full/birdnet-plus-v3.0.1-fp32-b1.onnx');
    expect(offer.label, 'v3.0.1, build 1');
    expect(offer.model.bytes, 344606647);
    expect(offer.model.name, 'birdnet-plus-v3.0.1-fp32-b1.onnx');
    expect(offer.labels.name, 'birdnet-plus-v3.0.1-labels-b1.txt');
    expect(offer.path, isNot(contains('fp16')));
    expect(offer.path, isNot(contains('regional')));
  });

  test('the newest build is not offered again', () {
    final global = specById('plus-v3-global')!;
    final listed = _manifest(r'''
    {
      "models": [
        {
          "path": "full/birdnet-plus-v3.0-fp32-b1.onnx",
          "build": 1, "upstream_version": "3.0", "variant": "fp32", "region": null,
          "legacy": false, "superseded_by": null,
          "size_bytes": 10, "sha256": "old", "labels": "full/old.txt",
          "labels_size_bytes": 1, "labels_sha256": "oldl",
          "input": {"sample_rate": 32000, "window_seconds": 5}
        },
        {
          "path": "full/birdnet-plus-v3.0.1-fp32-b1.onnx",
          "build": 1, "upstream_version": "3.0.1", "variant": "fp32", "region": null,
          "legacy": false, "superseded_by": null,
          "size_bytes": 20, "sha256": "new", "labels": "full/new.txt",
          "labels_size_bytes": 1, "labels_sha256": "newl",
          "input": {"sample_rate": 32000, "window_seconds": 5}
        },
        {
          "path": "full/birdnet-plus-v9.9-fp16-b1.onnx",
          "build": 1, "upstream_version": "9.9", "variant": "fp16", "region": null,
          "legacy": false, "superseded_by": null,
          "size_bytes": 30, "sha256": "fp16", "labels": "full/fp16.txt",
          "labels_size_bytes": 1, "labels_sha256": "fp16l",
          "input": {"sample_rate": 32000, "window_seconds": 5}
        }
      ]
    }
    ''');
    expect(
      successorOf(
        spec: global,
        currentPath: 'full/birdnet-plus-v3.0.1-fp32-b1.onnx',
        repo: 'tphakala/BirdNET-Plus-V3.0',
        manifest: listed,
      ),
      isNull,
    );
    final perch = specById('perch-v2-uk')!;
    expect(
      successorOf(
        spec: perch,
        currentPath: 'regional/british-isles/perch-v2-british-isles-no-dft-fp32-b2.onnx',
        repo: 'tphakala/Perch-v2-Models',
        manifest: _manifest(_perchChain),
      ),
      isNull,
    );
  });

  test('a skipped path is not offered', () {
    final global = specById('plus-v3-global')!;
    final ref = hfRefOf(global.model)!;
    expect(
      successorOf(
        spec: global,
        currentPath: ref.path,
        repo: ref.repo,
        manifest: _manifest(_plusMissing),
        skipped: {'full/birdnet-plus-v3.0.1-fp32-b1.onnx'},
      ),
      isNull,
    );
    final perch = specById('perch-v2-uk')!;
    expect(
      successorOf(
        spec: perch,
        currentPath: hfRefOf(perch.model)!.path,
        repo: hfRefOf(perch.model)!.repo,
        manifest: _manifest(_perchChain),
        skipped: {'regional/british-isles/perch-v2-british-isles-no-dft-fp32-b2.onnx'},
      ),
      isNull,
    );
  });

  test('a snooze hides the notice', () async {
    final root = await Directory.systemTemp.createTemp('birdsong_updates_');
    addTearDown(() => root.delete(recursive: true));
    final settings = await Settings.load(root);
    final updates = ModelUpdates(settings, ModelManager(Directory('${root.path}/models')));
    final offer = ModelOffer(
      spec: specById('plus-v3-global')!,
      path: 'full/birdnet-plus-v3.0.1-fp32-b1.onnx',
      label: 'v3.0.1, build 1',
      model: ModelFile('https://example.invalid/m.onnx', 'm.onnx', 10),
      labels: ModelFile('https://example.invalid/l.txt', 'l.txt', 2),
      sha256: 'aa',
      labelsSha256: 'bb',
    );
    updates.offers = [offer];
    expect(updates.notice?.path, offer.path);
    updates.snooze(offer);
    expect(updates.notice, isNull);
    final until = settings.modelSnoozed[offer.path]!;
    final week = const Duration(days: 7).inMilliseconds;
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(until, greaterThan(now + week - 5000));
    expect(until, lessThan(now + week + 5000));
    settings.update((s) => s.modelSnoozed[offer.path] = now - 1000);
    expect(updates.notice?.path, offer.path);
    updates.skip(offer);
    expect(updates.notice, isNull);
    expect(settings.modelSkipped, contains(offer.path));
    await settings.saved;
  });

  test('the four update fields round-trip', () async {
    final root = await Directory.systemTemp.createTemp('birdsong_updates_');
    addTearDown(() => root.delete(recursive: true));
    final s = await Settings.load(root);
    s.update((x) {
      x.modelCheckAt = 1700000000000;
      x.modelSnoozed = {'full/a.onnx': 1700000001000};
      x.modelSkipped = {'full/b.onnx', 'full/c.onnx'};
      x.modelOverrides = {
        'plus-v3-global': {
          'path': 'full/birdnet-plus-v3.0.1-fp32-b1.onnx',
          'label': 'v3.0.1, build 1',
          'modelUrl':
              'https://huggingface.co/tphakala/BirdNET-Plus-V3.0/resolve/main/full/birdnet-plus-v3.0.1-fp32-b1.onnx',
          'modelName': 'birdnet-plus-v3.0.1-fp32-b1.onnx',
          'modelBytes': 344606647,
          'sha256': 'abc',
          'labelsUrl':
              'https://huggingface.co/tphakala/BirdNET-Plus-V3.0/resolve/main/full/birdnet-plus-v3.0.1-labels-b1.txt',
          'labelsName': 'birdnet-plus-v3.0.1-labels-b1.txt',
          'labelsBytes': 470040,
          'restLogit': 9.7,
        },
      };
    });
    await s.saved;
    final again = await Settings.load(root);
    expect(again.modelCheckAt, 1700000000000);
    expect(again.modelSnoozed, {'full/a.onnx': 1700000001000});
    expect(again.modelSkipped, {'full/b.onnx', 'full/c.onnx'});
    final saved = again.modelOverrides['plus-v3-global']!;
    expect(saved['label'], 'v3.0.1, build 1');
    expect(saved['modelName'], 'birdnet-plus-v3.0.1-fp32-b1.onnx');
    expect(saved['modelBytes'], 344606647);
    expect(saved['restLogit'], closeTo(9.7, 1e-9));
  });

  test('an override replaces the files a spec loads', () {
    final base = specById('plus-v3-global')!;
    expect(identical(effective(base, {}), base), isTrue);
    final over = <String, Map<String, dynamic>>{
      'plus-v3-global': {
        'modelUrl':
            'https://huggingface.co/tphakala/BirdNET-Plus-V3.0/resolve/main/full/birdnet-plus-v3.0.1-fp32-b1.onnx',
        'modelName': 'birdnet-plus-v3.0.1-fp32-b1.onnx',
        'modelBytes': 344606647,
        'labelsUrl':
            'https://huggingface.co/tphakala/BirdNET-Plus-V3.0/resolve/main/full/birdnet-plus-v3.0.1-labels-b1.txt',
        'labelsName': 'birdnet-plus-v3.0.1-labels-b1.txt',
        'labelsBytes': 470040,
        'restLogit': 9.7,
        'label': 'v3.0.1, build 1',
      },
      'perch-v2-uk': {
        'modelUrl':
            'https://huggingface.co/tphakala/Perch-v2-Models/resolve/main/regional/british-isles/perch-v2-british-isles-no-dft-fp32-b2.onnx',
        'modelName': 'perch-v2-british-isles-no-dft-fp32-b2.onnx',
        'modelBytes': 68883428,
        'labelsUrl':
            'https://huggingface.co/tphakala/Perch-v2-Models/resolve/main/regional/british-isles/perch-v2-british-isles-labels-b2.txt',
        'labelsName': 'perch-v2-british-isles-labels-b2.txt',
        'labelsBytes': 13280,
        'restLogit': 9.7,
      },
    };
    final got = effective(base, over);
    expect(got.model.name, 'birdnet-plus-v3.0.1-fp32-b1.onnx');
    expect(got.model.bytes, 344606647);
    expect(got.labels.name, 'birdnet-plus-v3.0.1-labels-b1.txt');
    expect(got.labels.bytes, 470040);
    expect(got.restLogit, 9.7);
    expect(got.id, base.id);
    expect(got.name, base.name);
    expect(got.sampleRate, base.sampleRate);
    expect(got.activation, base.activation);
    expect(hfRefOf(got.model)!.path, 'full/birdnet-plus-v3.0.1-fp32-b1.onnx');
    expect(effectiveById('plus-v3-global', over)!.model.name, got.model.name);
    expect(effectiveById('no-such', over), isNull);
    expect(identical(effective(base, {'plus-v3-global': {}}), base), isTrue);
    final perch = effective(specById('perch-v2-uk')!, over);
    expect(perch.restLogit, 9.7);
    expect(perch.namesFromSharedLabels, isTrue);
    expect(perch.activation, Activation.softmax);
  });

  test('garbage update fields are skipped and later settings still load', () async {
    final root = await Directory.systemTemp.createTemp('birdsong_updates_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/settings.json').writeAsString('''
{
  "modelCheckAt": "yesterday",
  "modelSnoozed": {"ok": 12, "bad": "no"},
  "modelSkipped": ["keep-me", 4, false],
  "modelOverrides": {
    "plus-v3-global": "nope",
    "perch-v2-uk": {"label": "v2, build 2"}
  },
  "webPlate": true
}
''');
    final s = await Settings.load(root);
    expect(s.modelCheckAt, 0);
    expect(s.modelSnoozed, {'ok': 12});
    expect(s.modelSkipped, {'keep-me'});
    expect(s.modelOverrides.containsKey('plus-v3-global'), isFalse);
    expect(s.modelOverrides['perch-v2-uk']?['label'], 'v2, build 2');
    expect(s.webPlate, isTrue);
  });

  test('a garbage override is ignored, and a non-number rest logit is kept', () {
    final perch = specById('perch-v2-uk')!;
    expect(perch.restLogit, 9.71);
    final garbage = <String, Map<String, dynamic>>{
      'perch-v2-uk': {
        'modelUrl': 'https://example.invalid/m.onnx',
        'modelName': '',
        'modelBytes': 'lots',
        'labelsUrl': 'https://example.invalid/l.txt',
        'labelsName': 'labels.txt',
        'labelsBytes': 10,
      },
    };
    expect(identical(effective(perch, garbage), perch), isTrue);
    final badBytes = <String, Map<String, dynamic>>{
      'perch-v2-uk': {
        'modelUrl': 'https://example.invalid/m.onnx',
        'modelName': 'm.onnx',
        'modelBytes': 'lots',
        'labelsUrl': 'https://example.invalid/l.txt',
        'labelsName': 'l.txt',
        'labelsBytes': 2,
      },
    };
    expect(identical(effective(perch, badBytes), perch), isTrue);
    final badRest = <String, Map<String, dynamic>>{
      'perch-v2-uk': {
        'modelUrl': 'https://example.invalid/m.onnx',
        'modelName': 'm.onnx',
        'modelBytes': 10,
        'labelsUrl': 'https://example.invalid/l.txt',
        'labelsName': 'l.txt',
        'labelsBytes': 2,
        'restLogit': '9.7',
      },
    };
    final got = effective(perch, badRest);
    expect(got.model.name, 'm.onnx');
    expect(got.restLogit, 9.71);
  });

  test('a file another installed model still uses is not deleted', () async {
    final root = await Directory.systemTemp.createTemp('birdsong_updates_');
    addTearDown(() => root.delete(recursive: true));
    final dir = Directory('${root.path}/models');
    await dir.create();
    final models = ModelManager(dir);
    final global = specById('plus-v3-global')!;
    final perch = specById('perch-v2-uk')!;
    final overrides = <String, Map<String, dynamic>>{
      'perch-v2-uk': {
        'modelUrl': 'https://example.invalid/m.onnx',
        'modelName': perch.model.name,
        'modelBytes': 1,
        'labelsUrl': 'https://example.invalid/l.txt',
        'labelsName': global.labels.name,
        'labelsBytes': 1,
      },
    };
    final keep = namesInUse(overrides, (s) => s.id == perch.id);
    expect(keep, contains(global.labels.name));
    expect(keep, contains(sharedNames.name));
    expect(keep, isNot(contains(global.model.name)));
    final oldModel = File('${dir.path}/${global.model.name}')..writeAsStringSync('m');
    final oldLabels = File('${dir.path}/${global.labels.name}')..writeAsStringSync('l');
    final names = File('${dir.path}/${sharedNames.name}')..writeAsStringSync('n');
    await models.deleteReplaced(
      [global.model, global.labels, sharedNames],
      keep: keep,
    );
    expect(oldModel.existsSync(), isFalse);
    expect(oldLabels.existsSync(), isTrue);
    expect(names.existsSync(), isTrue);
    await models.deleteReplaced([sharedNames], keep: {});
    expect(names.existsSync(), isTrue);
  });
}
