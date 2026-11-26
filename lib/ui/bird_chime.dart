import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the signature startup / home birdsong clip (`assets/app/startup_bird.mp3`)
/// gently without interrupting music or interfering with active microphone
/// recording.
class BirdChime {
  BirdChime._();

  static AudioPlayer? _player;
  static bool _configured = false;
  static DateTime _lastPlayed = DateTime.fromMillisecondsSinceEpoch(0);

  /// Plays the birdsong chime unless [suppress] is true (e.g. while actively
  /// recording so the microphone never picks up the app's own chime).
  /// Coalesces calls within 1.5 s so rapid view/boot transitions don't double-play.
  static Future<void> play({bool suppress = false, bool force = false}) async {
    if (suppress) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastPlayed) < const Duration(milliseconds: 1500)) return;
    _lastPlayed = now;
    try {
      final p = _player ??= AudioPlayer();
      if (!_configured) {
        _configured = true;
        await p.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
          android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
        ));
        await p.setVolume(0.75);
      }
      await p.stop();
      await p.play(AssetSource('app/startup_bird.mp3'));
    } catch (e) {
      // Safe no-op in headless widget tests or if audio device is unavailable.
      debugPrint('bird chime: $e');
    }
  }
}
