import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model_catalog.dart';

/// Downloads models into the app's own folder and says what is installed.
class ModelManager extends ChangeNotifier {
  ModelManager(this.dir);

  final Directory dir;

  /// Model id to download progress, 0..1, while downloading.
  final Map<String, double> progress = {};

  /// Model id to the last download error.
  final Map<String, String> errors = {};

  File fileFor(ModelFile f) => File('${dir.path}/${f.name}');

  List<ModelFile> filesOf(ModelSpec s) => [
        s.model,
        s.labels,
        if (s.namesFromSharedLabels) sharedNames,
      ];

  bool isInstalled(ModelSpec s) => filesOf(s).every((f) => fileFor(f).existsSync());

  bool isDownloading(ModelSpec s) => progress.containsKey(s.id);

  int bytesOnDisk(ModelSpec s) {
    var n = 0;
    for (final f in [s.model, s.labels]) {
      final file = fileFor(f);
      if (file.existsSync()) n += file.lengthSync();
    }
    return n;
  }

  Future<void> install(ModelSpec s) async {
    if (isDownloading(s)) return;
    errors.remove(s.id);
    progress[s.id] = 0;
    notifyListeners();
    try {
      final files = filesOf(s).where((f) => !fileFor(f).existsSync()).toList();
      final total = files.fold<int>(0, (a, f) => a + (f.bytes > 0 ? f.bytes : 1));
      var done = 0;
      for (final f in files) {
        await _download(f, (got) {
          progress[s.id] = total == 0 ? 1.0 : ((done + got) / total).clamp(0.0, 1.0).toDouble();
          notifyListeners();
        });
        done += f.bytes > 0 ? f.bytes : 1;
      }
    } catch (e) {
      errors[s.id] = e.toString();
    } finally {
      progress.remove(s.id);
      notifyListeners();
    }
  }

  Future<void> remove(ModelSpec s) async {
    // The shared names file stays: other models may need it.
    for (final f in [s.model, s.labels]) {
      if (f == sharedNames) continue;
      final file = fileFor(f);
      if (await file.exists()) await file.delete();
    }
    notifyListeners();
  }

  Future<void> _download(ModelFile f, void Function(int got) onProgress) async {
    await dir.create(recursive: true);
    final part = File('${fileFor(f).path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.getUrl(Uri.parse(f.url));
      req.followRedirects = true;
      req.maxRedirects = 10;
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('${res.statusCode} for ${f.url}');
      }
      final sink = part.openWrite();
      var got = 0;
      var lastReport = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          got += chunk.length;
          if (got - lastReport > 512 * 1024) {
            lastReport = got;
            onProgress(got);
          }
        }
      } finally {
        await sink.close();
      }
      onProgress(got);
      if (f.bytes > 0 && got != f.bytes) {
        await part.delete();
        throw HttpException('${f.name}: got $got bytes, expected ${f.bytes}');
      }
      await part.rename(fileFor(f).path);
    } finally {
      client.close();
    }
  }
}
