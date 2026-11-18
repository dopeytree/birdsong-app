import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'engine/listen_engine.dart';
import 'engine/model_manager.dart';
import 'server/local_server.dart';
import 'settings.dart';
import 'store/detection_store.dart';

/// Everything the screens share, made once at start-up.
class AppState {
  AppState._(this.dataDir, this.settings, this.models, this.store, this.engine, this.server);

  final Directory dataDir;
  final Settings settings;
  final ModelManager models;
  final DetectionStore store;
  final ListenEngine engine;
  final LocalServer server;

  static Future<AppState> create() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final settings = await Settings.load(dir);
    final models = ModelManager(Directory('${dir.path}/models'));
    final store = await DetectionStore.open(Directory('${dir.path}/detections'));
    final engine = ListenEngine(settings, models, store);
    final server = LocalServer(settings, store, plateModel: () => settings.plateModel);
    await server.start();
    return AppState._(dir, settings, models, store, engine, server);
  }
}
