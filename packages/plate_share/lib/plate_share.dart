import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';

/// Takes a picture of the plate (the app's web view, without the app's own
/// buttons over it) and opens the system share sheet with it: Messages,
/// Mail, AirDrop, Photos, social apps.
class PlateShare {
  static const _channel = MethodChannel('uk.co.edstone.birdsong/plate_share');

  /// iPhone, iPad and Mac for now.
  static bool get supported => Platform.isIOS || Platform.isMacOS;

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
