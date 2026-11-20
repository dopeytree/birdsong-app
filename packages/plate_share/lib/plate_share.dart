import 'dart:io';
import 'package:flutter/services.dart';

/// Takes a picture of the plate (the app's web view, without the app's own
/// buttons over it) and opens the system share sheet with it: Messages,
/// Mail, AirDrop, Photos, social apps.
class PlateShare {
  static const _channel = MethodChannel('uk.co.edstone.birdsong/plate_share');

  /// iPhone, iPad and Mac for now.
  static bool get supported => Platform.isIOS || Platform.isMacOS;

  /// Saves the picture of the plate to Photos. Returns 'saved', 'denied'
  /// (not allowed in Settings) or 'failed'.
  static Future<String> saveToPhotos() async =>
      await _channel.invokeMethod<String>('save') ?? 'failed';

  /// iOS: let the web view run under the status bar and the Dynamic Island
  /// (no automatic safe-area insets), in the page's paper colour. The page
  /// pads its own content. Elsewhere does nothing.
  static Future<void> fullBleed() async {
    if (!Platform.isIOS) return;
    for (var i = 0; i < 10; i++) {
      // The web view appears a frame or two after it is asked for.
      if (await _channel.invokeMethod<bool>('fullBleed') == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// [from] is where the button is, in logical pixels from the window's top
  /// left: the sheet points at it on iPad and Mac. Returns false if there
  /// was no plate to take.
  static Future<bool> share({String? text, Rect? from}) async {
    final ok = await _channel.invokeMethod<bool>('share', {
      'text': text,
      if (from != null) ...{
        'x': from.left,
        'y': from.top,
        'w': from.width,
        'h': from.height,
      },
    });
    return ok ?? false;
  }
}
