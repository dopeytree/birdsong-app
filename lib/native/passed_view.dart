import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart' show caps, ink, madder, sepia, serif;
import 'landmarks.dart';

/// "Passed on the way", under the Index of species when the map's extras
/// are on: what the walk went by, in columns about 16rem wide, nearest
/// first. Selecting one with a place takes the map there. From
/// assets/app/map-mode.js (#bsPassed).
class PassedView extends StatelessWidget {
  const PassedView({super.key, required this.lookup, required this.width, this.fit = false});

  final LandmarkLookup lookup;
  final double width;

  /// Fitted on one screen: the smaller heading, as the index's.
  final bool fit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lookup,
        builder: (context, _) {
          final found = lookup.current;
          final passed = found?.passed ?? const <Passed>[];
          final status = lookup.loading
              ? 'Looking up what the walk passed…'
              : found == null
                  ? ''
                  : '${passed.isEmpty ? 'Nothing listed along the way. ' : ''}'
                          '${found.unreached.isNotEmpty ? "Couldn't reach: ${found.unreached.join(', ')}." : ''}'
                      .trim();
          // columns:16rem auto; column-gap:2rem, filled top to bottom
          const col = 256.0, gap = 32.0;
          final n = math.max(1, ((width + gap) / (col + gap)).floor());
          final per = (passed.length / n).ceil();
          final colWidth = (width - gap * (n - 1)) / n;
          final h2 = fit ? 16.0 : 20.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: fit ? 4.8 : 16),
                child: Text('Passed on the way',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: caps, fontSize: h2, letterSpacing: h2 * .06, height: 1.5, color: ink)),
              ),
              if (passed.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < n; c++) ...[
                      if (c > 0) const SizedBox(width: gap),
                      SizedBox(
                        width: colWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final p in passed.skip(c * per).take(per)) _Line(p, onTap: p.at == null ? null : () => lookup.show(p.at!)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              if (status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(status,
                      style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 12.8, color: sepia)),
                ),
            ],
          );
        },
      );
}

class _Line extends StatefulWidget {
  const _Line(this.p, {this.onTap});

  final Passed p;
  final VoidCallback? onTap;

  @override
  State<_Line> createState() => _LineState();
}

class _LineState extends State<_Line> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    const base = TextStyle(fontFamily: serif, fontSize: 16, height: 1.4, color: ink);
    final text = Text.rich(TextSpan(style: base, children: [
      TextSpan(text: p.name, style: TextStyle(color: _hover && widget.onTap != null ? madder : ink)),
      const TextSpan(text: ' '),
      TextSpan(text: p.about, style: const TextStyle(color: sepia, fontStyle: FontStyle.italic, fontSize: 16 * .85)),
      TextSpan(
          text: ' ${p.at != null ? '${p.metres.round()} m' : 'walked through'}',
          style: const TextStyle(color: sepia, fontSize: 16 * .8)),
    ]));
    return Semantics(
      button: widget.onTap != null,
      hint: widget.onTap != null ? 'Show it on the map' : null,
      child: MouseRegion(
        cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 1.6), child: text),
        ),
      ),
    );
  }
}
