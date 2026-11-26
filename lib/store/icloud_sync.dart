import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:plate_share/plate_share.dart';

import '../native/plate_library.dart';
import '../settings.dart';
import 'detection_store.dart';
import 'map_pins.dart';

/// The Apple iCloud ubiquity container shared across iPhone, iPad and Mac.
const icloudContainerId = 'iCloud.uk.co.edstone.birdsongApp';

/// Full bidirectional iCloud Drive sync across Apple devices:
///
/// - `sessions/`: finished listening walks (`session.json`, `detections.jsonl`,
///   `track.jsonl`, audio clips `.m4a`/`.wav`, spectrograms `.bmp`) + deletion
///   tombstones (`deleted.json`) so deleting a walk stays deleted everywhere
/// - `preferences/plate_choices.json`: user-chosen bird illustrations merged
///   per-species by `chosenAt` timestamp
/// - `preferences/settings.json`: portable settings & unioned remote stations
/// - `stations/`: remote station history (`station.json`, `days.json`,
///   `fill-log.txt`, and archived day folders)
/// - `logs/icloud-sync.log`: timestamped sync history log mirrored to iCloud
class ICloudSync extends ChangeNotifier {
  ICloudSync(
    this.dataDir,
    this.settings,
    this.store, {
    this.pins,
    Future<String?> Function()? cloudPathProvider,
    bool? supportedOverride,
  })  : _cloudPathProvider = cloudPathProvider,
        _supportedOverride = supportedOverride {
    store.addListener(_scheduleSync);
    settings.addListener(_onSettingsChanged);
    pins?.addListener(_onPinsChanged);
    PlateLibrary.choicesChanged.addListener(_scheduleSync);
  }

  final Directory dataDir;
  final Settings settings;
  final DetectionStore store;
  final MapPinStore? pins;
  final Future<String?> Function()? _cloudPathProvider;
  final bool? _supportedOverride;

  bool syncing = false;
  String? status;
  String? error;
  DateTime? lastSynced;

  /// Incremented whenever iCloud sync merges newer plate choices from another
  /// device so an open [NativePlate] can refresh those illustrations live.
  int plateChoicesRevision = 0;

  Timer? _debounce;

  bool get supported => _supportedOverride ?? PlateShare.supported;

  File get logFile => File('${dataDir.path}/logs/icloud-sync.log');
  File get localPlateChoicesFile => File('${dataDir.path}/plate_choices.json');
  Directory get localStationsDir => Directory('${dataDir.path}/stations');

  void _onSettingsChanged() {
    if (settings.applyingRemoteSync) return;
    _scheduleSync();
  }

  void _onPinsChanged() {
    if (pins?.applyingRemoteSync ?? false) return;
    _scheduleSync();
  }

  void _scheduleSync() {
    if (!supported || !settings.icloudSync) return;
    // Never push half-finished walks while recording live.
    if (store.liveSession != null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 6), () => unawaited(syncNow(manual: false)));
  }

  /// Reads the newest sync log lines (newest first) for Settings > Data.
  Future<List<String>> readLogLines({int limit = 80}) async {
    try {
      if (!await logFile.exists()) return const [];
      final lines = (await logFile.readAsString()).trim().split('\n').where((l) => l.isNotEmpty).toList();
      return lines.reversed.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _resolveCloudPath() async {
    if (_cloudPathProvider != null) return _cloudPathProvider();
    return await PlateShare.icloudContainerPath(containerId: icloudContainerId) ??
        await PlateShare.icloudContainerPath();
  }

  Future<void> syncNow({bool manual = true}) async {
    if (!supported || !settings.icloudSync || syncing) return;
    syncing = true;
    error = null;
    status = 'Syncing with iCloud…';
    notifyListeners();
    try {
      final path = await _resolveCloudPath();
      if (path == null || path.isEmpty) {
        if (manual) {
          error = 'iCloud Drive is not available. Sign in to iCloud in System Settings '
              'and make sure iCloud Drive is enabled for birdsongs.ai.';
          status = null;
        } else {
          status = 'iCloud Drive unavailable on this device';
        }
        await _appendLog('iCloud container unavailable');
        return;
      }

      await store.flush();
      await settings.saved;

      var pushed = 0;
      var pulled = 0;
      var sessionsPulled = 0;
      var choicesChanged = false;
      var settingsPulled = false;

      // 1. Sessions, recordings & deletion tombstones
      final sessionRes = await _syncSessions(Directory('$path/sessions'));
      pushed += sessionRes.pushed;
      pulled += sessionRes.pulled;
      sessionsPulled = sessionRes.pulled;

      // 2. Plate image preferences (per-species merge by chosenAt)
      final plateRes = await _syncPlateChoices(File('$path/preferences/plate_choices.json'));
      pushed += plateRes.pushed;
      pulled += plateRes.pulled;
      choicesChanged = plateRes.pulled > 0;

      // 3. Portable settings & remote stations
      final settingsRes = await _syncSettings(File('$path/preferences/settings.json'));
      pushed += settingsRes.pushed;
      pulled += settingsRes.pulled;
      settingsPulled = settingsRes.pulled > 0;

      // 4. Remote station archives & fill-logs
      final stationRes = await _syncStations(Directory('$path/stations'));
      pushed += stationRes.pushed;
      pulled += stationRes.pulled;

      // 5. User-dropped map pins
      if (pins != null) {
        final pinsRes = await _syncPins(File('$path/preferences/map_pins.json'));
        pushed += pinsRes.pushed;
        pulled += pinsRes.pulled;
      }

      if (sessionsPulled > 0) {
        await store.reload();
      }
      if (choicesChanged) {
        plateChoicesRevision++;
      }

      lastSynced = DateTime.now();
      final parts = <String>[
        if (pushed > 0) '$pushed uploaded',
        if (pulled > 0) '$pulled downloaded',
        if (choicesChanged) 'plates updated',
        if (settingsPulled) 'preferences updated',
      ];
      status = parts.isEmpty ? 'Up to date' : 'Synced (${parts.join(', ')})';
      await _appendLog(status!, cloudLogFile: File('$path/logs/icloud-sync.log'));
    } catch (e) {
      debugPrint('iCloud sync: $e');
      error = 'iCloud sync failed: $e';
      status = null;
      await _appendLog('Sync failed: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<({int pushed, int pulled})> _syncSessions(Directory cloudSessions) async {
    await cloudSessions.create(recursive: true);
    var pushed = 0;
    var pulled = 0;

    // 1a. Merge deletion tombstones first so deleted sessions never resurrect.
    final cloudTombstonesFile = File('${cloudSessions.path}/deleted.json');
    final cloudTombstones = await _readStringMap(cloudTombstonesFile);
    final merged = <String, String>{...store.deletedFolders};
    var cloudNeedsTombstones = false;
    var localNeedsTombstones = false;

    for (final e in cloudTombstones.entries) {
      final prev = merged[e.key];
      if (prev == null || e.value.compareTo(prev) > 0) {
        merged[e.key] = e.value;
        localNeedsTombstones = true;
      }
    }
    for (final e in merged.entries) {
      final prev = cloudTombstones[e.key];
      if (prev == null || e.value.compareTo(prev) > 0) {
        cloudNeedsTombstones = true;
      }
    }

    if (localNeedsTombstones) {
      await store.applyRemoteTombstones(merged);
    }
    if (cloudNeedsTombstones) {
      await _writeJsonAtomic(cloudTombstonesFile, merged);
      pushed++;
    }
    // Remove tombstoned session folders from iCloud too.
    for (final folder in merged.keys) {
      final cloudDir = Directory('${cloudSessions.path}/$folder');
      if (await cloudDir.exists()) {
        try {
          await cloudDir.delete(recursive: true);
        } catch (e) {
          debugPrint('iCloud delete tombstoned $folder: $e');
        }
      }
    }

    final liveFolders = {
      for (final s in store.sessions)
        if (s.live && s.folder != null) s.folder!,
    };

    // 1b. Push finished local session folders (incl. recordings & spectrograms) to iCloud.
    if (await store.sessionsDir.exists()) {
      await for (final entry in store.sessionsDir.list()) {
        if (entry is! Directory) continue;
        final name = _baseName(entry.path);
        if (name.isEmpty || name.startsWith('.') || liveFolders.contains(name) || merged.containsKey(name)) {
          continue;
        }
        final dst = Directory('${cloudSessions.path}/$name');
        pushed += await _mirrorFiles(entry, dst, triggerDownload: false);
      }
    }

    // 1c. Pull remote iCloud session folders to local storage.
    if (await cloudSessions.exists()) {
      await for (final entry in cloudSessions.list()) {
        if (entry is! Directory) continue;
        final name = _baseName(entry.path);
        if (name.isEmpty || name.startsWith('.') || liveFolders.contains(name) || merged.containsKey(name)) {
          continue;
        }
        final dst = Directory('${store.sessionsDir.path}/$name');
        pulled += await _mirrorFiles(entry, dst, triggerDownload: true);
      }
    }
    return (pushed: pushed, pulled: pulled);
  }

  /// Bidirectionally merges per-species plate illustration preferences using
  /// each entry's `chosenAt` timestamp.
  Future<({int pushed, int pulled})> _syncPlateChoices(File cloudFile) async {
    await cloudFile.parent.create(recursive: true);
    final local = await _readDynamicMap(localPlateChoicesFile);
    final remote = await _readDynamicMap(cloudFile);
    if (local.isEmpty && remote.isEmpty) return (pushed: 0, pulled: 0);

    final merged = <String, dynamic>{};
    final keys = <String>{...local.keys, ...remote.keys};
    var localDirty = false;
    var remoteDirty = false;

    for (final sci in keys) {
      final l = local[sci];
      final r = remote[sci];
      if (l is Map && r is Map) {
        final lt = (l['chosenAt'] as num?)?.toInt() ?? 0;
        final rt = (r['chosenAt'] as num?)?.toInt() ?? 0;
        if (rt > lt) {
          merged[sci] = r;
          if (jsonEncode(l) != jsonEncode(r)) localDirty = true;
        } else {
          merged[sci] = l;
          if (jsonEncode(l) != jsonEncode(r)) remoteDirty = true;
        }
      } else if (l is Map) {
        merged[sci] = l;
        remoteDirty = true;
      } else if (r is Map) {
        merged[sci] = r;
        localDirty = true;
      }
    }

    var pushed = 0;
    var pulled = 0;
    if (localDirty) {
      await _writeJsonAtomic(localPlateChoicesFile, merged);
      pulled = 1;
    }
    if (remoteDirty) {
      await _writeJsonAtomic(cloudFile, merged);
      pushed = 1;
    }
    return (pushed: pushed, pulled: pulled);
  }

  /// Bidirectionally merges portable settings and remote stations.
  Future<({int pushed, int pulled})> _syncSettings(File cloudFile) async {
    await cloudFile.parent.create(recursive: true);
    final remote = await _readDynamicMap(cloudFile);
    var pushed = 0;
    var pulled = 0;

    if (remote.isNotEmpty) {
      if (settings.mergeFromSyncJson(remote)) {
        await settings.saved;
        pulled = 1;
      }
    }
    final localSync = settings.toSyncJson();
    if (remote.isEmpty || jsonEncode(remote) != jsonEncode(localSync)) {
      await _writeJsonAtomic(cloudFile, localSync);
      pushed = 1;
    }
    return (pushed: pushed, pulled: pulled);
  }

  /// Bidirectionally mirrors remote station archives and `fill-log.txt` logs.
  Future<({int pushed, int pulled})> _syncStations(Directory cloudStations) async {
    var pushed = 0;
    var pulled = 0;
    final hasLocal = await localStationsDir.exists();
    final hasCloud = await cloudStations.exists();
    if (!hasLocal && !hasCloud) return (pushed: 0, pulled: 0);

    await cloudStations.create(recursive: true);
    await localStationsDir.create(recursive: true);

    await for (final entry in localStationsDir.list()) {
      if (entry is! Directory) continue;
      final name = _baseName(entry.path);
      if (name.isEmpty || name.startsWith('.')) continue;
      pushed += await _mirrorFiles(entry, Directory('${cloudStations.path}/$name'), triggerDownload: false);
    }
    await for (final entry in cloudStations.list()) {
      if (entry is! Directory) continue;
      final name = _baseName(entry.path);
      if (name.isEmpty || name.startsWith('.')) continue;
      pulled += await _mirrorFiles(entry, Directory('${localStationsDir.path}/$name'), triggerDownload: true);
    }
    return (pushed: pushed, pulled: pulled);
  }

  /// Bidirectionally merges dropped map pins & tombstones.
  Future<({int pushed, int pulled})> _syncPins(File cloudFile) async {
    final p = pins;
    if (p == null) return (pushed: 0, pulled: 0);
    await cloudFile.parent.create(recursive: true);
    await p.saved;
    final remote = await _readDynamicMap(cloudFile);
    var pushed = 0;
    var pulled = 0;
    if (remote.isNotEmpty) {
      if (p.mergeFromSyncJson(remote)) {
        await p.saved;
        pulled = 1;
      }
    }
    final localSync = p.toSyncJson();
    if ((p.pins.isNotEmpty || p.deletedIds.isNotEmpty) &&
        (remote.isEmpty || jsonEncode(remote) != jsonEncode(localSync))) {
      await _writeJsonAtomic(cloudFile, localSync);
      pushed = 1;
    }
    return (pushed: pushed, pulled: pulled);
  }

  Future<void> _appendLog(String message, {File? cloudLogFile}) async {
    try {
      await logFile.parent.create(recursive: true);
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
      final line = '$stamp · $message';
      final lines = <String>[];
      if (await logFile.exists()) {
        lines.addAll((await logFile.readAsString()).split('\n').where((l) => l.isNotEmpty));
      }
      lines.add(line);
      final trimmed = lines.length > 200 ? lines.sublist(lines.length - 200) : lines;
      final body = '${trimmed.join('\n')}\n';
      await logFile.writeAsString(body, flush: true);
      if (cloudLogFile != null) {
        await cloudLogFile.parent.create(recursive: true);
        await cloudLogFile.writeAsString(body, flush: true);
      }
    } catch (e) {
      debugPrint('iCloud log: $e');
    }
  }

  Future<Map<String, String>> _readStringMap(File f) async {
    final raw = await _readDynamicMap(f);
    return {
      for (final e in raw.entries)
        if (e.value is String) e.key: e.value as String,
    };
  }

  Future<Map<String, dynamic>> _readDynamicMap(File f) async {
    try {
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      debugPrint('iCloud read ${f.path}: $e');
    }
    return {};
  }

  Future<void> _writeJsonAtomic(File file, Object data) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.pending');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
    await tmp.rename(file.path);
  }

  Future<int> _mirrorFiles(Directory srcRoot, Directory dstRoot, {required bool triggerDownload}) async {
    var copied = 0;
    await for (final entity in srcRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final base = _baseName(entity.path);
      if (base.endsWith('.pending') || base == '.DS_Store') continue;
      if (base.startsWith('.') && base.endsWith('.icloud')) {
        if (triggerDownload && _cloudPathProvider == null) {
          unawaited(PlateShare.icloudStartDownload(entity.path));
        }
        continue;
      }
      if (base.startsWith('.')) continue;
      final rel = entity.path.substring(srcRoot.path.length + 1);
      final dstFile = File('${dstRoot.path}/$rel');
      try {
        final srcStat = await entity.stat();
        if (await dstFile.exists()) {
          final dstStat = await dstFile.stat();
          if (dstStat.size == srcStat.size &&
              !srcStat.modified.isAfter(dstStat.modified.add(const Duration(seconds: 2)))) {
            continue;
          }
        }
        await dstFile.parent.create(recursive: true);
        await entity.copy(dstFile.path);
        copied++;
      } catch (e) {
        debugPrint('iCloud copy $rel: $e');
      }
    }
    return copied;
  }

  String _baseName(String path) {
    final parts = path.split(Platform.pathSeparator).where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    store.removeListener(_scheduleSync);
    settings.removeListener(_onSettingsChanged);
    pins?.removeListener(_onPinsChanged);
    PlateLibrary.choicesChanged.removeListener(_scheduleSync);
    super.dispose();
  }
}
