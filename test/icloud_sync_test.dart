import 'dart:convert';
import 'dart:io';

import 'package:birdsong_app/settings.dart';
import 'package:birdsong_app/store/detection_store.dart';
import 'package:birdsong_app/store/icloud_sync.dart';
import 'package:birdsong_app/store/map_pins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;

void main() {
  test('iCloud sync mirrors sessions, recordings, tombstones, plate choices, map pins, settings, stations and logs',
      () async {
    final tmp = await Directory.systemTemp.createTemp('birdsongs_icloud_test_');
    addTearDown(() => tmp.delete(recursive: true));

    final phoneDir = await Directory('${tmp.path}/phone').create(recursive: true);
    final macDir = await Directory('${tmp.path}/mac').create(recursive: true);
    final cloudDir = await Directory('${tmp.path}/cloud').create(recursive: true);

    // Phone sets up a session with a recording, plate choice, map pin, station, and station log.
    final phoneSettings = await Settings.load(phoneDir);
    expect(phoneSettings.equalSort, 'family');
    expect(phoneSettings.nativeShowLatestDetection, isTrue);
    expect(phoneSettings.nativeBottomTicket, isTrue);
    phoneSettings.update((s) {
      s.icloudSync = true;
      s.useCoreMl = true; // device-local: must NOT overwrite Mac
      s.nativeAllNameTickets = true; // portable preference: MUST sync
      s.equalLabels = true; // per-view No pecking order labels: MUST sync
      s.nativeBottomTicket = false; // portable preference: MUST sync
      s.stations = [Station(id: 'st-garden', name: 'Garden', birdweather: '1234')];
    });
    await phoneSettings.saved;

    final phoneStore = await DetectionStore.open(phoneDir);
    final phonePins = await MapPinStore.open(phoneDir);
    final pin = phonePins.drop(const LatLng(51.501, -0.142), label: 'Owl oak');
    phonePins.move(pin.id, const LatLng(51.502, -0.141));
    phonePins.rename(pin.id, 'Barn Owl oak');
    await phonePins.saved;

    final ses = await phoneStore.startSession(at: DateTime(2026, 11, 25, 8, 0));
    final det = await phoneStore.add(
      model: 'bnl-v3-10k',
      sci: 'Erithacus rubecula',
      common: 'European Robin',
      confidence: 0.94,
      at: DateTime(2026, 11, 25, 8, 5),
    );
    det.hasClip = true;
    det.clipExt = 'm4a';
    await phoneStore.clipFile(det.id).writeAsBytes([1, 2, 3, 4]);
    await phoneStore.save(det);
    await phoneStore.endSession(ses, at: DateTime(2026, 11, 25, 8, 20));
    await phoneStore.flush();

    // Phone picks a preferred plate illustration for Robin
    await File('${phoneDir.path}/plate_choices.json').writeAsString(jsonEncode({
      'Erithacus rubecula': {
        'url': 'https://example.test/robin-gould.png',
        'ready': true,
        'credit': 'John Gould',
        'chosenAt': 1000,
      },
    }));

    // Phone has a station fill-log
    final phoneStLog = File('${phoneDir.path}/stations/st-garden/fill-log.txt');
    await phoneStLog.parent.create(recursive: true);
    await phoneStLog.writeAsString('2026-11-25 08:00 · filled 14 days\n');

    final phoneSync = ICloudSync(
      phoneDir,
      phoneSettings,
      phoneStore,
      pins: phonePins,
      cloudPathProvider: () async => cloudDir.path,
      supportedOverride: true,
    );
    await phoneSync.syncNow();
    expect(phoneSync.error, isNull);
    expect(await phoneSync.logFile.exists(), isTrue);
    expect(await File('${cloudDir.path}/logs/icloud-sync.log').exists(), isTrue);

    // Mac starts with its own distinct station & a different plate choice (Wren) and useCoreMl = false.
    final macSettings = await Settings.load(macDir);
    macSettings.update((s) {
      s.icloudSync = true;
      s.useCoreMl = false;
      s.stations = [Station(id: 'st-woods', name: 'Woods', birdnetUrl: 'http://192.168.1.9:8080')];
    });
    // Simulate Mac having an older preference timestamp than Phone so Phone's
    // newer scalar preferences win while both stations merge.
    macSettings.syncUpdatedAt = 1;
    await macSettings.saved;
    await File('${macDir.path}/plate_choices.json').writeAsString(jsonEncode({
      'Troglodytes troglodytes': {
        'url': 'https://example.test/wren.png',
        'ready': true,
        'credit': 'Audubon',
        'chosenAt': 2000,
      },
    }));

    final macStore = await DetectionStore.open(macDir);
    final macPins = await MapPinStore.open(macDir);
    final macSync = ICloudSync(
      macDir,
      macSettings,
      macStore,
      pins: macPins,
      cloudPathProvider: () async => cloudDir.path,
      supportedOverride: true,
    );
    await macSync.syncNow();

    // Verify session + recording pulled to Mac
    expect(macStore.sessions.length, 1);
    expect(macStore.all.length, 1);
    expect(macStore.all.single.sci, 'Erithacus rubecula');
    expect(await macStore.clipFile(macStore.all.single.id).readAsBytes(), [1, 2, 3, 4]);

    // Verify dropped map pin synced to Mac with latest moved coords & renamed label
    expect(macPins.pins.length, 1);
    expect(macPins.pins.single.label, 'Barn Owl oak');
    expect(macPins.pins.single.lat, closeTo(51.502, 1e-5));
    expect(macPins.pins.single.lon, closeTo(-0.141, 1e-5));

    // Verify plate choices merged both Robin (from phone) and Wren (from Mac)
    final mergedChoices = jsonDecode(await File('${macDir.path}/plate_choices.json').readAsString()) as Map;
    expect(mergedChoices.keys, containsAll(['Erithacus rubecula', 'Troglodytes troglodytes']));
    expect(macSync.plateChoicesRevision, 1);

    // Verify portable preferences synced, stations unioned, device-local useCoreMl preserved
    expect(macSettings.nativeAllNameTickets, isTrue);
    expect(macSettings.equalLabels, isTrue);
    expect(macSettings.nativeBottomTicket, isFalse);
    expect(macSettings.useCoreMl, isFalse);
    expect(macSettings.stations.map((s) => s.id), containsAll(['st-garden', 'st-woods']));

    // Verify station archive/log pulled to Mac
    expect(await File('${macDir.path}/stations/st-garden/fill-log.txt').readAsString(), contains('filled 14 days'));

    // Now delete the session and map pin on Phone -> tombstones sync to iCloud -> Mac removes both too!
    await phoneStore.deleteSession(phoneStore.sessions.single);
    phonePins.remove(pin.id);
    await phonePins.saved;
    await phoneSync.syncNow();
    await macSync.syncNow();
    expect(macStore.sessions, isEmpty);
    expect(macPins.pins, isEmpty);

    phoneSync.dispose();
    macSync.dispose();
    phoneStore.dispose();
    macStore.dispose();
  });
}
