import 'dart:convert';
import 'dart:io';

import 'package:birdsong_app/store/detection_store.dart';
import 'package:birdsong_app/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('birdsong_store_'));
  tearDown(() async => root.delete(recursive: true));

  test('a session is one folder: session.json and detections.jsonl', () async {
    final store = await DetectionStore.open(root);
    final t0 = DateTime(2026, 11, 18, 22, 19);
    final ses = await store.startSession(
        at: t0, settings: {'confidenceThreshold': 0.65}, models: [{'id': 'bnl-v3-10k'}]);
    final d = await store.add(
        model: 'bnl-v3-10k',
        sci: 'Strix aluco',
        common: 'Tawny Owl',
        confidence: 0.91,
        at: t0.add(const Duration(minutes: 2)),
        windowSeconds: 3,
        scores: [(sci: 'Strix aluco', confidence: 0.91), (sci: 'Asio otus', confidence: 0.02)]);
    d.confidence = 0.95;
    await store.save(d);
    ses.weather = {'temperatureC': 8.2, 'symbol': 'lightrain'};
    await store.endSession(ses, at: t0.add(const Duration(minutes: 13)));

    final folders = await store.sessionsDir.list().where((e) => e is Directory).toList();
    expect(folders, hasLength(1));
    final dir = folders.single.path;
    final j = jsonDecode(await File('$dir/session.json').readAsString()) as Map<String, dynamic>;
    expect(j['schemaVersion'], sessionSchemaVersion);
    expect(j['uuid'], ses.uuid);
    expect(j['startTime'], t0.toUtc().toIso8601String());
    expect(j['stopReason'], 'manual');
    expect(j['summary'], {'detections': 1, 'species': 1});
    expect(j['settings'], {'confidenceThreshold': 0.65});

    final lines = await File('$dir/detections.jsonl').readAsLines();
    expect(lines, hasLength(1), reason: 'an update rewrites its line, never adds one');
    final line = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(line['scientificName'], 'Strix aluco');
    expect(line['confidence'], 0.95);
    expect(line['scores'], hasLength(2));
    expect(line['windowSeconds'], 3);

    // Opened again, everything comes back.
    final again = await DetectionStore.open(root);
    expect(again.sessions.single.uuid, ses.uuid);
    expect(again.sessions.single.weather?['temperatureC'], 8.2);
    expect(again.all.single.confidence, 0.95);
    expect(again.all.single.scores.last.sci, 'Asio otus');
    expect(again.sessions.single.contains(again.all.single.at), isTrue);
  });

  test('a session that heard nothing for under a minute leaves no folder', () async {
    final store = await DetectionStore.open(root);
    final ses = await store.startSession(at: DateTime(2026, 11, 18, 7));
    await store.endSession(ses, at: DateTime(2026, 11, 18, 7, 0, 20));
    expect(store.sessions, isEmpty);
    expect(await store.sessionsDir.list().toList(), isEmpty);
  });

  test('the old single-file logs move into session folders, clips too', () async {
    final legacy = Directory('${root.path}/detections');
    await Directory('${legacy.path}/clips').create(recursive: true);
    final a = DateTime(2026, 11, 18, 6, 0);
    final b = DateTime(2026, 11, 18, 9, 0); // over 30 min later: its own session
    final old = [
      {'id': 4, 'model': 'm', 'sci': 'Turdus merula', 'common': 'Blackbird', 'confidence': 0.7, 'at': a.toIso8601String(), 'clip': true},
      {'id': 4, 'model': 'm', 'sci': 'Turdus merula', 'common': 'Blackbird', 'confidence': 0.9, 'at': a.toIso8601String(), 'clip': true},
      {'id': 5, 'model': 'm', 'sci': 'Erithacus rubecula', 'common': 'Robin', 'confidence': 0.8, 'at': b.toIso8601String(), 'clip': false},
    ];
    await File('${legacy.path}/detections.jsonl')
        .writeAsString(old.map((j) => '${jsonEncode(j)}\n').join());
    await File('${legacy.path}/clips/4.wav').writeAsBytes([1, 2, 3]);

    final store = await DetectionStore.open(root);
    expect(store.sessions, hasLength(2));
    expect(store.all, hasLength(2), reason: 'repeated lines for one detection become one');
    final blackbird = store.all.firstWhere((d) => d.sci == 'Turdus merula');
    expect(blackbird.confidence, 0.9);
    expect(blackbird.hasClip, isTrue);
    expect(await store.clipFile(blackbird.id).readAsBytes(), [1, 2, 3]);
    expect(await File('${legacy.path}/detections.jsonl.migrated').exists(), isTrue);
    expect(await File('${legacy.path}/detections.jsonl').exists(), isFalse);

    // And it happens once only.
    final again = await DetectionStore.open(root);
    expect(again.sessions, hasLength(2));
    expect(again.all, hasLength(2));
  });

  test('weather reads as a few words', () {
    expect(weatherWords({'temperatureC': 8.4, 'symbol': 'lightrainshowers_day'}),
        '8°C, light rain showers');
    expect(weatherWords({'temperatureC': -1.6, 'symbol': 'clearsky_night'}), '-2°C, clear');
    expect(weatherWords(null), '');
  });
}
