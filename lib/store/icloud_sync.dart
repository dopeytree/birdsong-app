import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:plate_share/plate_share.dart';

import '../settings.dart';
import 'detection_store.dart';

/// The Apple iCloud ubiquity container shared across iPhone, iPad and Mac.
const icloudContainerId = 'iCloud.uk.co.edstone.birdsongApp';

/// Bidirectional iCloud Drive sync for listening sessions (session.json,
/// detections.jsonl, track.jsonl, audio clips and spectrograms).
///
/// Each session lives in its own timestamp+UUID folder under `sessions/`, so
/// sessions recorded on an iPhone merge cleanly with sessions on a Mac or iPad
/// without clobbering each other.
class ICloudSync extends ChangeNotifier {
  ICloudSync(this.settings, this.store) {
    store.addListener(_onStoreChanged);
  }

  final Settings settings;
  final DetectionStore store;

  bool syncing = false;
  String? status;
  String? error;
  DateTime? lastSynced;

  Timer? _debounce;

  bool get supported => PlateShare.supported;

  void _onStoreChanged() {
    if (!supported || !settings.icloudSync) return;
    // Don't sync mid-recording; wait until listening stops or settles.
    if (store.liveSession != null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 8), () => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    if (!supported || !settings.icloudSync || syncing) return;
    syncing = true;
    error = null;
    status = 'Syncing with iCloud…';
    notifyListeners();
    try {
      final path = await PlateShare.icloudContainerPath(containerId: icloudContainerId) ??
          await PlateShare.icloudContainerPath();
      if (path == null || path.isEmpty) {
        error = 'iCloud Drive is not available. Sign in to iCloud in System Settings '
            'and make sure iCloud Drive is enabled for Birdsong.';
        status = null;
        return;
      }

      await store.flush();
      final cloudSessions = Directory('$path/sessions');
      await cloudSessions.create(recursive: true);

      final liveFolders = {
        for (final s in store.sessions)
          if (s.live && s.folder != null) s.folder!,
      };

      var pushed = 0;
      var pulled = 0;

      // 1. Push finished local session folders to iCloud.
      if (await store.sessionsDir.exists()) {
        await for (final entry in store.sessionsDir.list()) {
          if (entry is! Directory) continue;
          final name = _baseName(entry.path);
          if (name.isEmpty || name.startsWith('.') || liveFolders.contains(name)) continue;
          final dst = Directory('${cloudSessions.path}/$name');
          pushed += await _mirrorFiles(entry, dst, triggerDownload: false);
        }
      }

      // 2. Pull iCloud session folders to local storage.
      if (await cloudSessions.exists()) {
        await for (final entry in cloudSessions.list()) {
          if (entry is! Directory) continue;
          final name = _baseName(entry.path);
          if (name.isEmpty || name.startsWith('.') || liveFolders.contains(name)) continue;
          final dst = Directory('${store.sessionsDir.path}/$name');
          pulled += await _mirrorFiles(entry, dst, triggerDownload: true);
        }
      }

      if (pulled > 0) {
        await store.reload();
      }
      lastSynced = DateTime.now();
      status = pushed == 0 && pulled == 0
          ? 'Up to date'
          : 'Synced ($pushed uploaded, $pulled downloaded)';
    } catch (e) {
      debugPrint('iCloud sync: $e');
      error = 'iCloud sync failed: $e';
      status = null;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<int> _mirrorFiles(Directory srcRoot, Directory dstRoot,
      {required bool triggerDownload}) async {
    var copied = 0;
    await for (final entity in srcRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final base = _baseName(entity.path);
      if (base.endsWith('.pending') || base == '.DS_Store') continue;
      if (base.startsWith('.') && base.endsWith('.icloud')) {
        if (triggerDownload) {
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
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
