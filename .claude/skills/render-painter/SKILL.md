---
name: render-painter
description: Render a CustomPainter from the app to a PNG with a throwaway test, so a drawing can be checked by eye and shown to Ed before he builds. Use for any new or changed drawn mark, symbol or engraving.
---
# Looking at a drawing without building the app

Ed is the designer and wants to see an idea before it is built in. A
painter can be drawn to a PNG in about ten seconds, with no app build.

1. Copy the painter class(es) into a throwaway test. Private classes in
   `walk_map.dart` can't be imported, so paste their source in:

```dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:birdsong_app/main.dart' show ink, paper, sepia;

// …the painter classes, pasted…

void main() {
  test('render', () async {
    const k = 4.0; // four times size, so detail shows
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 160 * k, 50 * k), Paint()..color = paper);
    c.scale(k);
    c.save(); c.translate(4, 6); const MyPainter().paint(c, const Size(56, 34)); c.restore();
    final img = await rec.endRecording().toImage((160 * k).toInt(), (50 * k).toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('<scratchpad>/out.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}
```

2. Save it as `test/zz_render_test.dart`, run
   `flutter test test/zz_render_test.dart`, then **delete the test file**.
3. Read the PNG. Look for: solid black blobs (outline the shapes on paper
   instead), stacked shapes reading as a ladder, anything modern or cartoon.
4. Send the PNG to Ed and wait for his word before wiring it in.

Text drawn this way uses the test font (boxes), so this is for shapes, not
lettering. For lettering, show an inline mock-up with the real fonts.

The look: paper `#EEE5CE`, ink `#2A241C`, sepia `#6B5338`. Fine lines
(0.4 to 1), hatching for shade, nothing filled solid unless tiny.
